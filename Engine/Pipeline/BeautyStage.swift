import CoreImage
import Foundation
import LumoraCore

extension RenderPipeline {
    // MARK: - Retouch

    /// Skin, eyes and teeth retouching, face by face (only inside each face's region).
    func applyBeauty(_ beauty: BeautySettings, to input: CIImage, analysis: ImageAnalysis) -> CIImage {
        guard !beauty.isIdentity else { return input }
        let faces = analysis.faces
        guard !faces.isEmpty else { return input }
        var image = applyBlemishes(beauty, to: input, analysis: analysis)
        for face in faces {
            let settings = beauty.settings(for: face.landmarks.anchor)
            guard settings.hasRetouch else { continue }
            image = retouch(face, settings: settings, image: image)
        }
        return image
    }

    private func retouch(_ face: FaceInfo, settings: FaceRetouchSettings, image: CIImage) -> CIImage {
        let extent = image.extent
        let rect = Self.pixelRect(face.maskRegion, in: extent).integral.intersection(extent)
        guard rect.width > 4, rect.height > 4 else { return image }
        let faceWidth = CGFloat(face.landmarks.bounds.width) * extent.width

        let crop = image.clampedToExtent().cropped(to: rect)
        let fine = GuidedFilter.gaussian(Kernels.perceptualLuma.apply(crop), radius: max(0.6, faceWidth * 0.0045))
        // Guided by the blurred luma, so the smooth base layer can't carry grain back in.
        let base = GuidedFilter.selfCoefficients(pair: Kernels.lumaPair.apply(fine), radius: max(2, faceWidth * 0.03), eps: 0.0016)
        let chroma = GuidedFilter.gaussian(Kernels.toOklab.apply(crop), radius: max(2, faceWidth * 0.04))
        let masksA = Self.place(face.masksA, region: face.maskRegion, in: extent).cropped(to: rect)
        let masksB = Self.place(face.masksB, region: face.maskRegion, in: extent).cropped(to: rect)

        let iris = ColorMath.oklabDirection(forWheelHue: settings.irisHue)
        let retouched = Kernels.faceRetouch.apply(
            crop, base, fine, chroma, masksA, masksB,
            CIVector(x: CGFloat(settings.smooth / 100), y: CGFloat(settings.texture / 100), z: CGFloat(settings.evenTone / 100), w: CGFloat(settings.shine / 100)),
            CIVector(x: CGFloat(settings.darkCircles / 100), y: CGFloat(settings.teethWhiten / 100), z: CGFloat(settings.eyeBrighten / 100), w: CGFloat(settings.eyeWhiten / 100)),
            CIVector(x: CGFloat(settings.irisColor / 100), y: CGFloat(iris.0), z: CGFloat(iris.1), w: 0),
            CIVector(x: CGFloat(face.skinTone.x), y: CGFloat(face.skinTone.y), z: CGFloat(face.skinTone.z), w: 0)
        )
        return retouched.composited(over: image)
    }

    // MARK: - Makeup & hair

    /// Eyebrows, makeup and hair color, face by face.
    func applyMakeup(_ beauty: BeautySettings, to input: CIImage, analysis: ImageAnalysis) -> CIImage {
        guard !beauty.isIdentity else { return input }
        let faces = analysis.faces
        guard !faces.isEmpty else { return input }
        var image = input
        for face in faces {
            let settings = beauty.settings(for: face.landmarks.anchor)
            if settings.hasMakeup, let masks = face.makeup {
                image = makeup(face, masks: masks, settings: settings.makeup, image: image)
            }
            if settings.hasHairColor, let masks = face.makeup {
                if let hairMask = analysis.hairMask {
                    if settings.makeup.hairColorAmount != 0 {
                        image = hair(face, masks: masks, hairMask: hairMask, settings: settings.makeup, image: image)
                    }
                    if settings.makeup.hairOmbre != 0 || settings.makeup.hairShine != 0 {
                        image = hairStyle(face, masks: masks, hairMask: hairMask, region: analysis.hairRegion, settings: settings.makeup, image: image)
                    }
                } else if settings.makeup.hairColorAmount != 0, let person = analysis.personMask {
                    image = hair(face, masks: masks, person: person, analysisSize: analysis.imageSize, settings: settings.makeup, image: image)
                }
            }
        }
        return image
    }

    private static func vector(_ amount: Double, _ color: MakeupColor) -> CIVector {
        let lab = color.oklab
        return CIVector(x: CGFloat(amount / 100), y: CGFloat(lab.0), z: CGFloat(lab.1), w: CGFloat(lab.2))
    }

    private static func tone(_ value: SIMD3<Float>) -> CIVector {
        CIVector(x: CGFloat(value.x), y: CGFloat(value.y), z: CGFloat(value.z), w: 0)
    }

    private func makeup(_ face: FaceInfo, masks: MakeupMaskSet, settings m: MakeupSettings, image: CIImage) -> CIImage {
        let extent = image.extent
        let rect = Self.pixelRect(face.maskRegion, in: extent).integral.intersection(extent)
        guard rect.width > 4, rect.height > 4 else { return image }
        let crop = image.clampedToExtent().cropped(to: rect)
        func place(_ mask: CIImage) -> CIImage { Self.place(mask, region: face.maskRegion, in: extent).cropped(to: rect) }

        let finish: CIVector
        switch m.lipFinish {
        case .matte: finish = CIVector(x: 0, y: 0, z: 1, w: 0)
        case .satin: finish = CIVector(x: 0.35, y: 0, z: 0, w: 0)
        case .gloss: finish = CIVector(x: 1, y: 0, z: 0, w: 0)
        case .shimmer: finish = CIVector(x: 0.4, y: 1, z: 0, w: 0)
        }
        let browColor = m.browColor.oklab
        let result = Kernels.makeup.apply(
            crop,
            place(face.masksA), place(face.masksB), place(masks.c), place(masks.d), place(masks.e),
            Self.vector(m.lipstickAmount, m.lipstickColor),
            finish,
            Self.tone(face.lipTone),
            Self.vector(m.blushAmount, m.blushColor),
            CIVector(x: CGFloat(m.contour / 100), y: CGFloat(m.highlight / 100), z: 0, w: 0),
            Self.vector(m.eyeshadowAmount, m.eyeshadowColor),
            CIVector(x: CGFloat(m.eyeliner / 100), y: CGFloat(m.lashes / 100), z: 0, w: 0),
            CIVector(x: CGFloat(m.browThickness / 100), y: CGFloat(m.browColorAmount / 100), z: 0, w: 0),
            CIVector(x: CGFloat(browColor.0), y: CGFloat(browColor.1), z: CGFloat(browColor.2), w: 0),
            Self.tone(face.browTone),
            Self.tone(face.skinTone)
        )
        return result.composited(over: image)
    }

    /// Hair color with a full hair mask (photo matte or grown from the face): follows the whole
    /// hairstyle, ponytails included.
    private func hair(_ face: FaceInfo, masks: MakeupMaskSet, hairMask: CIImage, settings m: MakeupSettings, image: CIImage) -> CIImage {
        let extent = image.extent
        let mask = Self.stretch(hairMask, over: extent)
        let faceArea = Self.place(masks.d, region: face.maskRegion, in: extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            .composited(over: Self.black(extent))
            .cropped(to: extent)
        return Kernels.hairColor.apply(
            image, mask, Self.white(extent), faceArea,
            Self.vector(m.hairColorAmount, m.hairColor),
            Self.tone(face.hairTone),
            Self.tone(face.skinTone),
            Float(1)
        )
    }

    /// Ombré and shine along the whole hairstyle.
    private func hairStyle(_ face: FaceInfo, masks: MakeupMaskSet, hairMask: CIImage, region: CGRectValue?, settings m: MakeupSettings, image: CIImage) -> CIImage {
        let extent = image.extent
        let mask = Self.stretch(hairMask, over: extent)
        let faceArea = Self.place(masks.d, region: face.maskRegion, in: extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            .composited(over: Self.black(extent))
            .cropped(to: extent)
        let blurred = GuidedFilter.gaussian(image, radius: max(1.5, CGFloat(face.landmarks.bounds.width) * extent.width * 0.012))
        // Vertical position within the hair (top 0 → bottom 1).
        let hair = region ?? CGRectValue(x: 0, y: 0, width: 1, height: 1)
        let ramp = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: extent.midX, y: extent.minY + CGFloat(hair.y + hair.height) * extent.height),
            "inputPoint1": CIVector(x: extent.midX, y: extent.minY + CGFloat(hair.y) * extent.height),
            "inputColor0": CIColor(red: 0, green: 0, blue: 0),
            "inputColor1": CIColor(red: 1, green: 1, blue: 1),
        ])?.outputImage?.cropped(to: extent) ?? Self.black(extent)
        let ombre = m.hairOmbreColor.oklab
        return Kernels.hairStyle.apply(
            image, mask, faceArea, blurred, ramp,
            CIVector(x: CGFloat(m.hairShine / 100), y: CGFloat(m.hairOmbre / 100), z: 0, w: 0),
            CIVector(x: 0, y: CGFloat(ombre.0), z: CGFloat(ombre.1), w: CGFloat(ombre.2)),
            Self.tone(face.hairTone)
        )
    }

    private func hair(_ face: FaceInfo, masks: MakeupMaskSet, person: CIImage, analysisSize: CGSize, settings m: MakeupSettings, image: CIImage) -> CIImage {
        let extent = image.extent
        let rect = Self.pixelRect(masks.headRegion, in: extent).integral.intersection(extent)
        guard rect.width > 4, rect.height > 4 else { return image }
        let crop = image.clampedToExtent().cropped(to: rect)
        // The person mask was made at analysis size; stretch it over this render's extent.
        let personScaled = person
            .transformed(by: CGAffineTransform(scaleX: extent.width / max(analysisSize.width, 1), y: extent.height / max(analysisSize.height, 1)))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: rect)
        let head = Self.place(masks.head, region: masks.headRegion, in: extent).cropped(to: rect)
        // Solid face area lives in the blue channel of mask set D; move it to red for the kernel.
        let faceArea = Self.place(masks.d, region: face.maskRegion, in: extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            .composited(over: CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: rect))
            .cropped(to: rect)
        let result = Kernels.hairColor.apply(
            crop, personScaled, head, faceArea,
            Self.vector(m.hairColorAmount, m.hairColor),
            Self.tone(face.hairTone),
            Self.tone(face.skinTone),
            Float(0)
        )
        return result.composited(over: image)
    }

    // MARK: - Reshape

    /// Face reshaping (slim, jaw, eyes, nose, lips…) as one smooth warp per face.
    func applyFaceWarp(_ beauty: BeautySettings, to input: CIImage, analysis: ImageAnalysis) -> CIImage {
        guard !beauty.isIdentity else { return input }
        let extent = input.extent
        let aspect = Double(extent.height / max(extent.width, 1))
        var image = input
        for (index, face) in analysis.faces.enumerated() {
            let settings = beauty.settings(for: face.landmarks.anchor)
            guard settings.hasReshape else { continue }
            let key = "face-\(index)-\(settings.hashValue)-\(Int(aspect * 10000))"
            guard let field = analysis.cachedField(key: key, build: {
                FaceReshape.field(for: face.landmarks, settings: settings, aspect: aspect)
            }) else { continue }
            image = applyDisplacement(field, to: image)
        }
        return image
    }

    /// Warps an image with a backward displacement field.
    public func applyDisplacement(_ field: DisplacementField, to image: CIImage) -> CIImage {
        guard !field.isEmpty, field.columns > 1, field.rows > 1 else { return image }
        let extent = image.extent
        let width = extent.width
        let height = extent.height

        var floats = [Float](repeating: 1, count: field.columns * field.rows * 4)
        var maxOffset: CGFloat = 0
        for row in 0..<field.rows {
            for column in 0..<field.columns {
                let offset = field.offsets[row * field.columns + column]
                // Bitmap rows are stored top-down; field rows are bottom-up.
                let index = ((field.rows - 1 - row) * field.columns + column) * 4
                floats[index] = offset.x
                floats[index + 1] = offset.y
                floats[index + 2] = 0
                maxOffset = max(maxOffset, abs(CGFloat(offset.x)) * width, abs(CGFloat(offset.y)) * height)
            }
        }
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        let fieldImage = CIImage(
            bitmapData: data,
            bytesPerRow: field.columns * 16,
            size: CGSize(width: field.columns, height: field.rows),
            format: .RGBAf,
            colorSpace: nil
        )
        // Pixel centers of the field image sit on the grid vertices.
        let stepX = CGFloat(field.region.width) * width / CGFloat(field.columns - 1)
        let stepY = CGFloat(field.region.height) * height / CGFloat(field.rows - 1)
        let placed = fieldImage.transformed(by: CGAffineTransform(translationX: -0.5, y: -0.5)
            .concatenating(CGAffineTransform(scaleX: stepX, y: stepY))
            .concatenating(CGAffineTransform(translationX: extent.minX + CGFloat(field.region.x) * width, y: extent.minY + CGFloat(field.region.y) * height)))

        let margin = maxOffset + 2
        return Kernels.displace.apply(
            extent: extent,
            roiCallback: { index, rect in index == 0 ? rect.insetBy(dx: -margin, dy: -margin) : rect },
            arguments: [image.clampedToExtent(), placed, CIVector(x: width, y: height)]
        ) ?? image
    }

    // MARK: - Helpers

    static func pixelRect(_ region: CGRectValue, in extent: CGRect) -> CGRect {
        CGRect(
            x: extent.minX + CGFloat(region.x) * extent.width,
            y: extent.minY + CGFloat(region.y) * extent.height,
            width: CGFloat(region.width) * extent.width,
            height: CGFloat(region.height) * extent.height
        )
    }

    /// Stretches a mask image (covering `region`, normalized) over the matching pixels of `extent`.
    static func place(_ mask: CIImage, region: CGRectValue, in extent: CGRect) -> CIImage {
        let target = pixelRect(region, in: extent)
        let source = mask.extent
        guard source.width > 0, source.height > 0 else { return mask }
        return mask
            .transformed(by: CGAffineTransform(translationX: -source.minX, y: -source.minY)
                .concatenating(CGAffineTransform(scaleX: target.width / source.width, y: target.height / source.height))
                .concatenating(CGAffineTransform(translationX: target.minX, y: target.minY)))
    }
}
