import CoreImage
import Foundation
import LumoraCore
import Vision

public enum BodyAnalyzer {
    /// Detects people with Vision's 2D body pose (19 joints). Sorted left to right.
    public static func detect(in image: CIImage) -> [BodyPose] {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let poses: [BodyPose] = (request.results ?? []).compactMap { observation in
            guard let points = try? observation.recognizedPoints(.all) else { return nil }
            var joints: [BodyJoint: SIMD2<Double>] = [:]
            for (name, point) in points where point.confidence > 0.1 {
                if let joint = BodyJoint(rawValue: name.rawValue.rawValue) {
                    joints[joint] = SIMD2(Double(point.location.x), Double(point.location.y))
                }
            }
            let pose = BodyPose(joints: joints)
            return pose.hipCenter != nil && pose.shoulderCenter != nil ? pose : nil
        }
        return poses.sorted { ($0.hipCenter?.x ?? 0) < ($1.hipCenter?.x ?? 0) }
    }

    /// Measures the person's outline at the body levels used for reshaping.
    public static func shape(for pose: BodyPose, personMask: CIImage?, imageSize: CGSize, context: CIContext = RenderContext.analysis) -> BodyShape? {
        let aspect = Double(imageSize.height / max(imageSize.width, 1))
        guard let frame = BodyReshape.frame(pose, aspect: aspect) else { return nil }
        let mask = personMask.map { MaskSampler(mask: $0, imageSize: imageSize, context: context) }

        func iso(_ p: SIMD2<Double>) -> SIMD2<Double> { SIMD2(p.x, p.y * aspect) }
        func normal(_ p: SIMD2<Double>) -> SIMD2<Double> { SIMD2(p.x, p.y / aspect) }
        func lerp(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ t: Double) -> SIMD2<Double> { a + (b - a) * t }

        /// Walks from `center` along ±`direction` until leaving the person (or a default width).
        func measure(center: SIMD2<Double>, direction: SIMD2<Double>, maxDistance: Double, fallback: Double) -> EdgePair {
            func edge(_ sign: Double) -> SIMD2<Double> {
                let step = maxDistance / 120
                if let mask {
                    var last = center
                    var distance = step
                    while distance <= maxDistance {
                        let probe: SIMD2<Double> = center + direction * (sign * distance)
                        if mask.value(at: normal(probe)) < 0.5 { return last }
                        last = probe
                        distance += step
                    }
                }
                return center + direction * (sign * fallback)
            }
            return EdgePair(first: normal(edge(-1)), second: normal(edge(1)), center: normal(center))
        }

        var outline: [BodyLevel: EdgePair] = [:]
        let sw = frame.shoulderWidth
        let torsoPoint: (Double) -> SIMD2<Double> = { t in lerp(frame.shoulders, frame.hips, t) }
        outline[.shoulders] = measure(center: torsoPoint(0.05), direction: frame.right, maxDistance: sw * 1.1, fallback: sw * 0.55)
        outline[.chest] = measure(center: torsoPoint(0.3), direction: frame.right, maxDistance: sw * 0.9, fallback: sw * 0.45)
        outline[.waist] = measure(center: torsoPoint(0.62), direction: frame.right, maxDistance: sw * 0.8, fallback: sw * 0.36)
        outline[.hips] = measure(center: torsoPoint(1.06), direction: frame.right, maxDistance: sw * 0.9, fallback: sw * 0.45)

        for (hipJoint, kneeJoint, upper, middle) in [
            (BodyJoint.leftHip, BodyJoint.leftKnee, BodyLevel.upperThighLeft, BodyLevel.midThighLeft),
            (BodyJoint.rightHip, BodyJoint.rightKnee, BodyLevel.upperThighRight, BodyLevel.midThighRight),
        ] {
            guard let hip = pose[hipJoint].map(iso), let knee = pose[kneeJoint].map(iso) else { continue }
            let axis: SIMD2<Double> = knee - hip
            let legLength = max(BodyReshape.length(axis), 1e-6)
            let across = SIMD2(axis.y, -axis.x) / legLength
            outline[upper] = measure(center: lerp(hip, knee, 0.22), direction: across, maxDistance: sw * 0.45, fallback: sw * 0.2)
            outline[middle] = measure(center: lerp(hip, knee, 0.5), direction: across, maxDistance: sw * 0.4, fallback: sw * 0.17)
        }
        for (shoulderJoint, elbowJoint, level) in [
            (BodyJoint.leftShoulder, BodyJoint.leftElbow, BodyLevel.upperArmLeft),
            (BodyJoint.rightShoulder, BodyJoint.rightElbow, BodyLevel.upperArmRight),
        ] {
            guard let shoulder = pose[shoulderJoint].map(iso), let elbow = pose[elbowJoint].map(iso) else { continue }
            let axis: SIMD2<Double> = elbow - shoulder
            let armLength = max(BodyReshape.length(axis), 1e-6)
            let across = SIMD2(axis.y, -axis.x) / armLength
            outline[level] = measure(center: lerp(shoulder, elbow, 0.5), direction: across, maxDistance: sw * 0.25, fallback: sw * 0.1)
        }

        // Region: all joints plus a margin, so warps fade out well away from the body.
        let points = pose.joints.values.map(iso)
        let xs = points.map(\.x), ys = points.map(\.y)
        let margin = sw * 0.6
        let minX = max(0, (xs.min() ?? 0) - margin)
        let maxX = min(1, (xs.max() ?? 1) + margin)
        let minY = max(0, ((ys.min() ?? 0) - margin) / aspect)
        let maxY = min(1, ((ys.max() ?? aspect) + margin) / aspect)
        let region = CGRectValue(x: minX, y: minY, width: max(maxX - minX, 0.01), height: max(maxY - minY, 0.01))
        return BodyShape(pose: pose, outline: outline, region: region)
    }
}

/// CPU lookup into a person mask (bilinear, normalized coordinates, y up).
struct MaskSampler {
    private let pixels: [Float]
    private let width: Int
    private let height: Int

    init(mask: CIImage, imageSize: CGSize, context: CIContext) {
        // Work at up to 512 px: plenty for finding outlines.
        let scale = min(1, 512 / max(mask.extent.width, mask.extent.height, 1))
        let small = mask.transformed(by: CGAffineTransform(translationX: -mask.extent.minX, y: -mask.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let data = RenderContext.readFloats(small, context: context)
        var gray = [Float](repeating: 0, count: data.width * data.height)
        for i in 0..<(data.width * data.height) {
            gray[i] = data.pixels[i * 4]
        }
        self.pixels = gray
        self.width = data.width
        self.height = data.height
    }

    /// Mask value at a normalized point (0 outside the image).
    func value(at p: SIMD2<Double>) -> Float {
        guard width > 1, height > 1, p.x >= 0, p.x <= 1, p.y >= 0, p.y <= 1 else { return 0 }
        let x = p.x * Double(width - 1)
        // readFloats returns rows top-down (bitmap order); flip so y = 0 is the bottom row.
        let y = (1 - p.y) * Double(height - 1)
        let x0 = Int(x), y0 = Int(y)
        let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        let tx = Float(x - Double(x0)), ty = Float(y - Double(y0))
        func at(_ c: Int, _ r: Int) -> Float { pixels[r * width + c] }
        let first = at(x0, y0) * (1 - tx) + at(x1, y0) * tx
        let second = at(x0, y1) * (1 - tx) + at(x1, y1) * tx
        return first * (1 - ty) + second * ty
    }
}
