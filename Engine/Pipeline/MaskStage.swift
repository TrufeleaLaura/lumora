import CoreImage
import Foundation
import LumoraCore

/// Rasterized brush strokes, cached (strokes only change while painting).
enum BrushMaskCache {
    private struct Key: Hashable {
        let strokes: [BrushStroke]
        let width: Int
        let height: Int
    }

    private static let lock = NSLock()
    private static var entries: [(key: Key, image: CIImage)] = []

    /// Coverage image over (0, 0, width, height), gray.
    static func image(_ strokes: [BrushStroke], width: Int, height: Int) -> CIImage {
        let key = Key(strokes: strokes, width: width, height: height)
        lock.lock()
        if let hit = entries.first(where: { $0.key == key }) {
            lock.unlock()
            return hit.image
        }
        lock.unlock()
        let coverage = BrushRasterizer.rasterize(strokes, width: width, height: height)
        // One byte per pixel (gray) keeps cached brush masks small.
        let bytes = coverage.map { UInt8(min(max($0, 0), 1) * 255 + 0.5) }
        let image = CIImage(bitmapData: Data(bytes), bytesPerRow: width, size: CGSize(width: width, height: height), format: .L8, colorSpace: nil)
        lock.lock()
        entries.append((key, image))
        if entries.count > 6 { entries.removeFirst() }
        lock.unlock()
        return image
    }
}

extension RenderPipeline {
    /// Local adjustments: each visible mask blends its adjusted version of the image in.
    /// Masks are evaluated on `reference` (the unedited photo), so they don't shift as edits change.
    func applyMasks(_ masks: [Mask], to input: CIImage, reference: CIImage, analysis: ImageAnalysis, scale: CGFloat) -> CIImage {
        var image = input
        for mask in masks where mask.isActive {
            let alpha = maskImage(mask, reference: reference, analysis: analysis)
            let adjusted = applyLocal(mask.adjustments, to: image, analysis: analysis, scale: scale)
            image = Kernels.maskBlend.apply(image, adjusted, alpha, Float(mask.amount / 100))
        }
        return image
    }

    /// The image with one mask's local adjustments applied everywhere (the mask limits it later).
    func applyLocal(_ local: LocalAdjustments, to input: CIImage, analysis: ImageAnalysis, scale: CGFloat) -> CIImage {
        var image = input
        var effects = EffectsSettings()
        effects.texture = local.texture
        effects.clarity = local.clarity
        image = applyLocalContrast(effects, to: image, analysis: analysis)

        var color = ColorSettings()
        color.temperature = local.temperature
        color.tint = local.tint
        image = applyWhiteBalance(color, to: image)
        image = applyDehaze(local.dehaze, to: image, analysis: analysis)

        var light = LightSettings()
        light.exposure = local.exposure
        light.contrast = local.contrast
        light.highlights = local.highlights
        light.shadows = local.shadows
        light.whites = local.whites
        light.blacks = local.blacks
        image = applyTone(light, to: image, analysis: analysis)

        var document = EditDocument()
        document.color.saturation = local.saturation
        document.mixer.hue = Array(repeating: local.hue, count: HueBand.allCases.count)
        if local.colorAmount > 0 {
            document.grading.global = GradingWheel(hue: local.colorHue, saturation: local.colorAmount, luminance: 0)
        }
        image = applyColor(document, to: image)

        if local.noise > 0 {
            var detail = DetailSettings()
            detail.noiseReduction = local.noise
            detail.colorNoiseReduction = local.noise * 0.6
            image = applyNoiseReduction(detail, to: image, scale: scale)
        }
        if local.sharpness > 0 {
            var detail = DetailSettings()
            detail.sharpening = local.sharpness * 1.2
            detail.sharpenDetail = 35
            image = applySharpening(detail, to: image, scale: scale)
        } else if local.sharpness < 0 {
            // Softening: a blur that grows with the slider (radius in full-resolution pixels).
            let radius = CGFloat(-local.sharpness / 100) * 6 * scale
            image = GuidedFilter.gaussian(image, radius: radius)
        }
        return image
    }

    // MARK: - Mask images

    /// The mask (white = full effect) over `reference`'s extent.
    public func maskImage(_ mask: Mask, reference: CIImage, analysis: ImageAnalysis) -> CIImage {
        let extent = reference.extent
        var result: CIImage?
        for component in mask.components {
            let value = componentImage(component, reference: reference, analysis: analysis)
            if let current = result {
                let mode: CGFloat
                switch component.mode {
                case .add: mode = 0
                case .subtract: mode = 1
                case .intersect: mode = 2
                }
                result = Kernels.maskCombine.apply(current, value, CIVector(x: mode, y: component.inverted ? 1 : 0, z: 0, w: 0))
            } else if component.mode == .subtract {
                result = Self.black(extent)
            } else {
                result = component.inverted ? Kernels.maskInvert.apply(value) : value
            }
        }
        return result ?? Self.black(extent)
    }

    /// The photo tinted where the mask applies (mask preview).
    public func maskOverlay(_ mask: Mask, on image: CIImage, reference: CIImage, analysis: ImageAnalysis) -> CIImage {
        let alpha = maskImage(mask, reference: reference, analysis: analysis)
        let aligned = Self.stretch(alpha, over: image.extent)
        return Kernels.maskOverlay.apply(image, aligned, CIVector(x: 1, y: 0.12, z: 0.12, w: 0.55))
    }

    static func black(_ extent: CGRect) -> CIImage {
        CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: extent)
    }

    static func white(_ extent: CGRect) -> CIImage {
        CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent)
    }

    /// Stretches an image over `extent` (edges clamped).
    static func stretch(_ image: CIImage, over extent: CGRect) -> CIImage {
        let source = image.extent
        guard source.width > 0, source.height > 0, source != extent else { return image.cropped(to: extent) }
        return image.clampedToExtent()
            .transformed(by: CGAffineTransform(translationX: -source.minX, y: -source.minY)
                .concatenating(CGAffineTransform(scaleX: extent.width / source.width, y: extent.height / source.height))
                .concatenating(CGAffineTransform(translationX: extent.minX, y: extent.minY)))
            .cropped(to: extent)
    }

    static func maximum(_ a: CIImage, _ b: CIImage) -> CIImage {
        Kernels.maskCombine.apply(a, b, CIVector(x: 0, y: 0, z: 0, w: 0))
    }

    private static func point(_ p: SIMD2<Double>, in extent: CGRect) -> CIVector {
        CIVector(x: extent.minX + CGFloat(p.x) * extent.width, y: extent.minY + CGFloat(p.y) * extent.height)
    }

    func componentImage(_ c: MaskComponent, reference: CIImage, analysis: ImageAnalysis) -> CIImage {
        let extent = reference.extent
        let black = Self.black(extent)
        switch c.kind {
        case .subject, .background:
            guard let mask = analysis.subjectMask else { return black }
            return Self.stretch(mask, over: extent)
        case .object:
            guard let mask = analysis.objectMask(at: c.points) else { return black }
            return Self.stretch(mask, over: extent)
        case .sky:
            guard let coefficients = analysis.skyCoefficients else { return black }
            let aligned = GuidedFilter.upsample(coefficients, to: extent)
            return Kernels.guidedMask.apply(reference, aligned)
        case .people:
            return peopleMask(c, reference: reference, analysis: analysis)
        case .brush:
            return brushMask(c, reference: reference)
        case .linear:
            return Kernels.linearMask.apply(
                extent: extent,
                roiCallback: { _, rect in rect },
                arguments: [Self.point(c.start, in: extent), Self.point(c.end, in: extent)]
            ) ?? black
        case .radial:
            return radialMask(center: c.start, radius: c.radius, angle: c.angle, feather: c.feather / 100, extent: extent)
        case .color:
            guard !c.colors.isEmpty else { return black }
            return colorRangeMask(c.colors, refine: c.refine, reference: reference)
        case .luminance:
            let feather = 0.02 + c.refine / 100 * 0.2
            let low = min(c.range.x, c.range.y), high = max(c.range.x, c.range.y)
            return Kernels.luminanceMask.apply(reference, CIVector(x: CGFloat(low), y: CGFloat(high), z: CGFloat(feather), w: 0))
        case .point:
            let circle = radialMask(center: c.start, radius: SIMD2(c.radius.x, c.radius.x), angle: 0, feather: 0.85, extent: extent)
            guard let color = c.colors.first else { return circle }
            let similar = colorRangeMask([color], refine: c.refine, reference: reference)
            return Kernels.maskMultiply.apply(circle, similar)
        }
    }

    private func radialMask(center: SIMD2<Double>, radius: SIMD2<Double>, angle: Double, feather: Double, extent: CGRect) -> CIImage {
        let c = Self.point(center, in: extent)
        let radians = angle * .pi / 180
        return Kernels.radialMask.apply(
            extent: extent,
            roiCallback: { _, rect in rect },
            arguments: [
                CIVector(x: c.x, y: c.y, z: CGFloat(radius.x) * extent.width, w: CGFloat(radius.y) * extent.width),
                CIVector(x: CGFloat(cos(radians)), y: CGFloat(sin(radians)), z: CGFloat(feather), w: 0),
            ]
        ) ?? Self.black(extent)
    }

    private func colorRangeMask(_ colors: [SIMD3<Double>], refine: Double, reference: CIImage) -> CIImage {
        func vector(_ index: Int) -> CIVector {
            guard index < colors.count else { return CIVector(x: 0, y: 0, z: 0, w: 0) }
            let c = colors[index]
            return CIVector(x: CGFloat(c.x), y: CGFloat(c.y), z: CGFloat(c.z), w: 1)
        }
        let extent = reference.extent
        // A slight blur keeps sensor noise from speckling the mask.
        let softened = GuidedFilter.gaussian(reference, radius: max(0.5, max(extent.width, extent.height) * 0.0008))
        let tolerance = Float(0.025 + refine / 100 * 0.12)
        return Kernels.colorRangeMask.apply(softened, vector(0), vector(1), vector(2), vector(3), vector(4), tolerance)
    }

    private func brushMask(_ c: MaskComponent, reference: CIImage) -> CIImage {
        let extent = reference.extent
        guard !c.strokes.isEmpty, extent.width > 0, extent.height > 0 else { return Self.black(extent) }
        let longSide = max(extent.width, extent.height)
        let rasterLong: CGFloat = longSide > 2048 ? 2048 : min(longSide, 1024)
        let factor = rasterLong / longSide
        let width = max(8, Int(safe: (extent.width * factor).rounded()))
        let height = max(8, Int(safe: (extent.height * factor).rounded()))
        let raster = BrushMaskCache.image(c.strokes, width: width, height: height)
        let mask = Self.stretch(raster, over: extent)
        guard c.autoEdge else { return mask }
        // Auto edge: a guided filter snaps the painted mask to edges in the photo.
        let guide = Kernels.perceptualLuma.apply(ImageSource.scaled(reference, maxDimension: rasterLong))
        let target = Self.stretch(raster, over: guide.extent)
        let coefficients = GuidedFilter.coefficients(guide: guide, target: target, radius: max(2, rasterLong * 0.006), eps: 0.0008)
        let snapped = Kernels.guidedMask.apply(reference, GuidedFilter.upsample(coefficients, to: extent))
        // Don't let it leak far outside what was painted.
        let reach = GuidedFilter.gaussian(mask, radius: longSide * 0.01)
        return Kernels.maskMultiply.apply(snapped, Kernels.luminanceMask.apply(reach, CIVector(x: 0.35, y: 2, z: 0.25, w: 0)))
    }

    // MARK: - People

    private func peopleMask(_ c: MaskComponent, reference: CIImage, analysis: ImageAnalysis) -> CIImage {
        let extent = reference.extent
        let parts = Set(c.parts)
        var result = Self.black(extent)
        let faces = analysis.faces
        var chosenFaces = faces
        if let point = c.person, !faces.isEmpty {
            let nearest = faces.min { a, b in
                Self.distance(point, to: a.landmarks.bounds) < Self.distance(point, to: b.landmarks.bounds)
            }
            chosenFaces = nearest.map { [$0] } ?? []
        }
        let person = analysis.personMask.map { Self.stretch($0, over: extent) }

        let bodyParts = parts.intersection([.person, .bodySkin, .clothes])
        if !bodyParts.isEmpty, var personImage = person {
            if let point = c.person, let region = personRegion(point, analysis: analysis, faces: chosenFaces, extent: extent) {
                personImage = Kernels.maskMultiply.apply(personImage, region)
            }
            var faceArea = Self.black(extent)
            var heads = Self.black(extent)
            for face in faces {
                guard let makeup = face.makeup else { continue }
                let area = Self.place(makeup.d, region: face.maskRegion, in: extent)
                    .applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                        "inputGVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                        "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    ])
                faceArea = Self.maximum(faceArea, area.composited(over: Self.black(extent)))
                let head = Self.place(makeup.head, region: makeup.headRegion, in: extent)
                heads = Self.maximum(heads, head.composited(over: Self.black(extent)))
            }
            let tone = skinTone(chosenFaces.first, analysis: analysis)
            let body = Kernels.peopleBody.apply(
                reference, personImage, faceArea, heads,
                CIVector(x: bodyParts.contains(.person) ? 1 : 0, y: bodyParts.contains(.bodySkin) ? 1 : 0, z: bodyParts.contains(.clothes) ? 1 : 0, w: 0),
                tone
            )
            result = Self.maximum(result, body)
        }

        var faceParts = parts.intersection([.faceSkin, .eyes, .iris, .brows, .lips, .teeth, .hair])
        // A full hair mask (photo matte or grown) follows the whole hairstyle.
        if faceParts.contains(.hair), let hairMask = analysis.hairMask {
            result = Self.maximum(result, Self.stretch(hairMask, over: extent))
            faceParts.remove(.hair)
        }
        if !faceParts.isEmpty {
            for face in chosenFaces {
                guard let makeup = face.makeup else { continue }
                let rect = Self.pixelRect(makeup.headRegion, in: extent).union(Self.pixelRect(face.maskRegion, in: extent)).integral.intersection(extent)
                guard rect.width > 4, rect.height > 4 else { continue }
                let crop = reference.clampedToExtent().cropped(to: rect)
                let clear = Self.black(rect)
                func aligned(_ mask: CIImage, _ region: CGRectValue) -> CIImage {
                    Self.place(mask, region: region, in: extent).composited(over: clear).cropped(to: rect)
                }
                let personCrop = (person ?? Self.white(extent)).cropped(to: rect)
                let partsA = CIVector(
                    x: faceParts.contains(.faceSkin) ? 1 : 0, y: faceParts.contains(.eyes) ? 1 : 0,
                    z: faceParts.contains(.iris) ? 1 : 0, w: faceParts.contains(.brows) ? 1 : 0
                )
                let partsB = CIVector(x: faceParts.contains(.lips) ? 1 : 0, y: faceParts.contains(.teeth) ? 1 : 0, z: faceParts.contains(.hair) ? 1 : 0, w: 0)
                let faceMask = Kernels.peopleFace.apply(
                    crop, personCrop,
                    aligned(face.masksA, face.maskRegion), aligned(face.masksB, face.maskRegion),
                    aligned(makeup.d, face.maskRegion), aligned(makeup.e, face.maskRegion),
                    aligned(makeup.head, makeup.headRegion),
                    partsA, partsB,
                    Self.tone(face.skinTone), Self.tone(face.hairTone)
                )
                result = Self.maximum(result, faceMask.composited(over: Self.black(extent)))
            }
        }
        return result
    }

    private static func tone(_ value: SIMD3<Float>) -> CIVector {
        CIVector(x: CGFloat(value.x), y: CGFloat(value.y), z: CGFloat(value.z), w: 0)
    }

    private func skinTone(_ face: FaceInfo?, analysis: ImageAnalysis) -> CIVector {
        if let face { return Self.tone(face.skinTone) }
        if let body = analysis.bodies.first(where: { $0.skinTone != nil }), let tone = body.skinTone {
            return CIVector(x: CGFloat(tone.x), y: CGFloat(tone.y), z: CGFloat(tone.z), w: 0)
        }
        return CIVector(x: 0.65, y: 0.04, z: 0.05, w: 0)
    }

    private static func distance(_ point: SIMD2<Double>, to rect: CGRectValue) -> Double {
        let center = SIMD2(rect.x + rect.width / 2, rect.y + rect.height / 2)
        let d: SIMD2<Double> = point - center
        return (d.x * d.x + d.y * d.y).squareRoot()
    }

    /// Soft area around the chosen person (body outline region, or a box below their face).
    private func personRegion(_ point: SIMD2<Double>, analysis: ImageAnalysis, faces: [FaceInfo], extent: CGRect) -> CIImage? {
        var box: CGRect?
        let bodies = analysis.bodies
        if let body = bodies.min(by: { Self.distance(point, to: $0.region) < Self.distance(point, to: $1.region) }) {
            let region = body.region
            box = Self.pixelRect(CGRectValue(x: region.x - region.width * 0.15, y: region.y - region.height * 0.05, width: region.width * 1.3, height: region.height * 1.15), in: extent)
        } else if let face = faces.first {
            let b = face.landmarks.bounds
            box = Self.pixelRect(CGRectValue(x: b.x - b.width * 1.6, y: 0, width: b.width * 4.2, height: b.y + b.height * 1.6), in: extent)
        }
        guard let box else { return nil }
        let blur = max(extent.width, extent.height) * 0.02
        let solid = Self.white(box.intersection(extent)).composited(over: Self.black(extent))
        return GuidedFilter.gaussian(solid, radius: blur)
    }
}
