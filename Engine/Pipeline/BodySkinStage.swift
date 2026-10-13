import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import LumoraCore

/// Caches muscle lighting maps (they only depend on the pattern).
enum MuscleMapCache {
    private static let lock = NSLock()
    private static var maps: [String: CIImage] = [:]
    static let size = 128

    static func map(_ pattern: MuscleRelief.Pattern, key: String) -> CIImage {
        lock.lock()
        defer { lock.unlock() }
        if let cached = maps[key] { return cached }
        let width = size, height = size
        let shading = MuscleRelief.shading(pattern, width: width, height: height)
        var floats = [Float](repeating: 1, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                let value = shading[row * width + column]
                // Bitmap rows are top-down; the shading grid is bottom-up.
                let index = ((height - 1 - row) * width + column) * 4
                floats[index] = value.x
                floats[index + 1] = value.y
                floats[index + 2] = 0
            }
        }
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        let image = CIImage(bitmapData: data, bytesPerRow: width * 16, size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: nil)
        maps[key] = image
        return image
    }
}

extension RenderPipeline {
    /// Muscle definition (abs, chest, arms, V-line) and body skin (smooth, tan, cellulite), per person.
    func applyBodySkin(_ edits: BodyEditSettings, to input: CIImage, analysis: ImageAnalysis) -> CIImage {
        guard !edits.isIdentity else { return input }
        var image = input
        for body in analysis.bodies {
            let settings = edits.settings(for: body.pose.anchor)
            guard settings.hasMuscles || settings.hasSkin, let person = analysis.personMask else { continue }
            image = bodySkin(body, settings: settings, person: person, analysisSize: analysis.imageSize, faces: analysis, image: image)
        }
        return image
    }

    private func bodySkin(_ body: BodyShape, settings s: BodySettings, person: CIImage, analysisSize: CGSize, faces analysis: ImageAnalysis, image: CIImage) -> CIImage {
        let extent = image.extent
        let aspect = Double(extent.height / max(extent.width, 1))
        guard let frame = BodyReshape.frame(body.pose, aspect: aspect) else { return image }
        let rect = Self.pixelRect(body.region, in: extent).integral.intersection(extent)
        guard rect.width > 8, rect.height > 8 else { return image }
        let crop = image.clampedToExtent().cropped(to: rect)
        let pixelsPerUnit = extent.width

        // Muscle lighting maps placed on the body.
        var shading = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: rect)
        func place(_ pattern: MuscleRelief.Pattern, key: String, amount: Double, center: SIMD2<Double>, across: SIMD2<Double>, along: SIMD2<Double>, width: Double, height: Double) {
            guard amount > 0 else { return }
            let map = MuscleMapCache.map(pattern, key: key)
            let size = CGFloat(MuscleMapCache.size)
            let halfAcross: SIMD2<Double> = across * (width / 2)
            let halfAlong: SIMD2<Double> = along * (height / 2)
            let corner: SIMD2<Double> = center - halfAcross
            let originIso: SIMD2<Double> = corner - halfAlong
            let origin: SIMD2<Double> = originIso * Double(pixelsPerUnit)
            let ax: SIMD2<Double> = across * (width * Double(pixelsPerUnit)) / Double(size)
            let ay: SIMD2<Double> = along * (height * Double(pixelsPerUnit)) / Double(size)
            let transform = CGAffineTransform(
                a: CGFloat(ax.x), b: CGFloat(ax.y),
                c: CGFloat(ay.x), d: CGFloat(ay.y),
                tx: CGFloat(origin.x) + extent.minX, ty: CGFloat(origin.y) + extent.minY
            )
            let scaled = map.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: CGFloat(amount), y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: CGFloat(amount), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            .transformed(by: transform)
            shading = scaled.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: shading]).cropped(to: rect)
        }

        let up = frame.up
        let right = frame.right
        let torso = frame.torso
        let sw = frame.shoulderWidth
        if !body.pose.isBackView {
            let absShift: Double = s.absPosition / 100 * 0.1 * torso
            let absOffset: Double = absShift - 0.62 * torso
            let absCenter: SIMD2<Double> = frame.shoulders + up * absOffset
            place(.abs(s.absStyle), key: "abs-\(s.absStyle.rawValue)", amount: s.abs / 100, center: absCenter, across: right, along: up, width: 0.44 * sw, height: 0.5 * torso)
            let chestCenter: SIMD2<Double> = frame.shoulders - up * (0.2 * torso)
            place(.pecs, key: "pecs", amount: s.pecs / 100, center: chestCenter, across: right, along: up, width: 0.95 * sw, height: 0.32 * torso)
            let vCenter: SIMD2<Double> = frame.hips + up * (0.02 * torso)
            place(.vLine, key: "vline", amount: s.vLine / 100, center: vCenter, across: right, along: up, width: 0.55 * sw, height: 0.3 * torso)
        }
        for (shoulderJoint, elbowJoint) in [(BodyJoint.leftShoulder, BodyJoint.leftElbow), (BodyJoint.rightShoulder, BodyJoint.rightElbow)] {
            guard s.armDefinition > 0, let shoulderN = body.pose[shoulderJoint], let elbowN = body.pose[elbowJoint] else { continue }
            let shoulder = SIMD2(shoulderN.x, shoulderN.y * aspect)
            let elbow = SIMD2(elbowN.x, elbowN.y * aspect)
            let axis: SIMD2<Double> = shoulder - elbow
            let armLength = BodyReshape.length(axis)
            guard armLength > 1e-6 else { continue }
            let along: SIMD2<Double> = axis / armLength
            let across = SIMD2(along.y, -along.x)
            let center: SIMD2<Double> = (shoulder + elbow) / 2
            place(.arm, key: "arm", amount: s.armDefinition / 100, center: center, across: across, along: along, width: 0.16 * sw, height: armLength * 0.9)
        }

        // Smoothing inputs at body scale.
        let swPixels = CGFloat(sw) * extent.width
        let pair = Kernels.perceptualLumaPair.apply(crop)
        let base = GuidedFilter.selfCoefficients(pair: pair, radius: max(2, swPixels * 0.03), eps: 0.0016)
        let fine = GuidedFilter.gaussian(Kernels.perceptualLuma.apply(crop), radius: max(0.6, swPixels * 0.004))
        let chroma = GuidedFilter.gaussian(Kernels.toOklab.apply(crop), radius: max(2, swPixels * 0.03))

        // Cellulite area: below the hips, fading in over a short band.
        let hipY = CGFloat(frame.hips.y / aspect) * extent.height + extent.minY
        let band = CGFloat(torso / aspect) * extent.height * 0.12
        let gradient = CIFilter.linearGradient()
        gradient.point0 = CGPoint(x: rect.midX, y: hipY - band)
        gradient.point1 = CGPoint(x: rect.midX, y: hipY + band)
        gradient.color0 = CIColor(red: 1, green: 1, blue: 1)
        gradient.color1 = CIColor(red: 0, green: 0, blue: 0)
        let lowerBody = gradient.outputImage?.cropped(to: rect) ?? CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: rect)

        let personScaled = person
            .transformed(by: CGAffineTransform(scaleX: extent.width / max(analysisSize.width, 1), y: extent.height / max(analysisSize.height, 1)))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: rect)

        let tone = body.skinTone ?? analysis.faces.first.map { SIMD3(Double($0.skinTone.x), Double($0.skinTone.y), Double($0.skinTone.z)) } ?? SIMD3(0.65, 0.04, 0.05)
        let result = Kernels.bodySkin.apply(
            crop, personScaled, shading, base, fine, chroma, lowerBody,
            CIVector(x: CGFloat(s.skinSmooth / 100), y: CGFloat(s.tan / 100), z: CGFloat(s.cellulite / 100), w: 0),
            CIVector(x: CGFloat(tone.x), y: CGFloat(tone.y), z: CGFloat(tone.z), w: 0)
        )
        return result.composited(over: image)
    }
}
