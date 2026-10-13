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

        /// Walks from `center` along ±`direction` until leaving the person. Stops early at a dip
        /// in the mask (the thin gap between an arm and the torso), and never goes far beyond the
        /// width expected from the joints, so arms touching the body aren't mistaken for the torso.
        func measure(center: SIMD2<Double>, direction: SIMD2<Double>, expected: Double) -> EdgePair {
            func edge(_ sign: Double) -> SIMD2<Double> {
                let limit = expected * 1.3
                let step = limit / 160
                guard let mask else { return center + direction * (sign * expected) }
                var last = center
                var distance = step
                var peak: Float = 0
                while distance <= limit {
                    let probe: SIMD2<Double> = center + direction * (sign * distance)
                    let value = mask.value(at: normal(probe))
                    if value < 0.5 { return last }
                    peak = max(peak, value)
                    // A clear dip after the body interior, past 60% of the expected width.
                    if distance > expected * 0.6, peak > 0.9, value < peak - 0.18 { return last }
                    last = probe
                    distance += step
                }
                return center + direction * (sign * expected)
            }
            return EdgePair(first: normal(edge(-1)), second: normal(edge(1)), center: normal(center))
        }

        var outline: [BodyLevel: EdgePair] = [:]
        let sw = frame.shoulderWidth
        var hipHalf = sw * 0.3
        if let l = pose[.leftHip], let r = pose[.rightHip] {
            hipHalf = max(BodyReshape.length(iso(l) - iso(r)) / 2, sw * 0.15)
        }
        let shoulderHalf = sw / 2
        let torsoPoint: (Double) -> SIMD2<Double> = { t in lerp(frame.shoulders, frame.hips, t) }
        outline[.shoulders] = measure(center: torsoPoint(0.05), direction: frame.right, expected: shoulderHalf * 1.18)
        outline[.chest] = measure(center: torsoPoint(0.3), direction: frame.right, expected: shoulderHalf * 0.95)
        outline[.waist] = measure(center: torsoPoint(0.62), direction: frame.right, expected: max(shoulderHalf * 0.72, hipHalf * 1.25))
        outline[.hips] = measure(center: torsoPoint(1.06), direction: frame.right, expected: hipHalf * 1.65)

        for (hipJoint, kneeJoint, upper, middle) in [
            (BodyJoint.leftHip, BodyJoint.leftKnee, BodyLevel.upperThighLeft, BodyLevel.midThighLeft),
            (BodyJoint.rightHip, BodyJoint.rightKnee, BodyLevel.upperThighRight, BodyLevel.midThighRight),
        ] {
            guard let hip = pose[hipJoint].map(iso), let knee = pose[kneeJoint].map(iso) else { continue }
            let axis: SIMD2<Double> = knee - hip
            let legLength = max(BodyReshape.length(axis), 1e-6)
            let across = SIMD2(axis.y, -axis.x) / legLength
            outline[upper] = measure(center: lerp(hip, knee, 0.22), direction: across, expected: hipHalf * 0.95)
            outline[middle] = measure(center: lerp(hip, knee, 0.5), direction: across, expected: hipHalf * 0.75)
        }
        for (shoulderJoint, elbowJoint, level) in [
            (BodyJoint.leftShoulder, BodyJoint.leftElbow, BodyLevel.upperArmLeft),
            (BodyJoint.rightShoulder, BodyJoint.rightElbow, BodyLevel.upperArmRight),
        ] {
            guard let shoulder = pose[shoulderJoint].map(iso), let elbow = pose[elbowJoint].map(iso) else { continue }
            let axis: SIMD2<Double> = elbow - shoulder
            let armLength = max(BodyReshape.length(axis), 1e-6)
            let across = SIMD2(axis.y, -axis.x) / armLength
            outline[level] = measure(center: lerp(shoulder, elbow, 0.5), direction: across, expected: sw * 0.11)
        }

        // Region: all joints plus a margin, so warps fade out well away from the body.
        let points: [SIMD2<Double>] = pose.joints.values.map(iso)
        let xs: [Double] = points.map { $0.x }
        let ys: [Double] = points.map { $0.y }
        let margin: Double = sw * 0.6
        let lowX: Double = (xs.min() ?? 0) - margin
        let highX: Double = (xs.max() ?? 1) + margin
        let lowY: Double = ((ys.min() ?? 0) - margin) / aspect
        let highY: Double = ((ys.max() ?? aspect) + margin) / aspect
        let minX: Double = Swift.max(0.0, lowX)
        let maxX: Double = Swift.min(1.0, highX)
        let minY: Double = Swift.max(0.0, lowY)
        let maxY: Double = Swift.min(1.0, highY)
        let region = CGRectValue(x: minX, y: minY, width: Swift.max(maxX - minX, 0.01), height: Swift.max(maxY - minY, 0.01))
        return BodyShape(pose: pose, outline: outline, region: region)
    }
}

/// CPU lookup into a person mask (bilinear, normalized coordinates, y up).
struct MaskSampler {
    private let pixels: [Float]
    private let width: Int
    private let height: Int

    init(mask: CIImage, imageSize: CGSize, context: CIContext) {
        // Work at up to 1024 px so thin gaps between arms and torso survive.
        let scale = min(1, 1024 / max(mask.extent.width, mask.extent.height, 1))
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
