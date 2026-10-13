import Foundation

/// Places on the body where the person's outline is measured.
public enum BodyLevel: String, CaseIterable, Sendable {
    case shoulders, chest, waist, hips
    case upperThighLeft, upperThighRight, midThighLeft, midThighRight
    case upperArmLeft, upperArmRight
}

/// The two outline points of the body (or a limb) across one level, plus the level's center.
public struct EdgePair: Equatable, Sendable {
    public var first: SIMD2<Double>
    public var second: SIMD2<Double>
    public var center: SIMD2<Double>

    public init(first: SIMD2<Double>, second: SIMD2<Double>, center: SIMD2<Double>) {
        self.first = first
        self.second = second
        self.center = center
    }
}

/// A person ready for reshaping: pose and measured outline (normalized image coordinates).
public struct BodyShape: Equatable, Sendable {
    public var pose: BodyPose
    public var outline: [BodyLevel: EdgePair]
    /// Region covering the person (normalized), grown a little.
    public var region: CGRectValue

    public init(pose: BodyPose, outline: [BodyLevel: EdgePair], region: CGRectValue) {
        self.pose = pose
        self.outline = outline
        self.region = region
    }
}

public enum BodyReshape {
    /// Body axes in isotropic units (x across the image width, y scaled by the aspect ratio).
    public struct Frame: Sendable {
        public var hips: SIMD2<Double>
        public var shoulders: SIMD2<Double>
        public var up: SIMD2<Double>
        public var right: SIMD2<Double>
        public var torso: Double
        public var shoulderWidth: Double
    }

    static func iso(_ p: SIMD2<Double>, _ aspect: Double) -> SIMD2<Double> { SIMD2(p.x, p.y * aspect) }

    public static func length(_ v: SIMD2<Double>) -> Double { (v.x * v.x + v.y * v.y).squareRoot() }

    public static func frame(_ pose: BodyPose, aspect: Double) -> Frame? {
        guard let hipsN = pose.hipCenter, let shouldersN = pose.shoulderCenter else { return nil }
        let hips = iso(hipsN, aspect)
        let shoulders = iso(shouldersN, aspect)
        let axis: SIMD2<Double> = shoulders - hips
        let torso = max(length(axis), 1e-6)
        let up: SIMD2<Double> = axis / torso
        let right = SIMD2(up.y, -up.x)
        var shoulderWidth = torso * 0.8
        if let l = pose[.leftShoulder], let r = pose[.rightShoulder] {
            shoulderWidth = max(length(iso(l, aspect) - iso(r, aspect)), torso * 0.3)
        }
        return Frame(hips: hips, shoulders: shoulders, up: up, right: right, torso: torso, shoulderWidth: shoulderWidth)
    }

    /// The warp for one person's shape sliders (not the stretches), or nil if none is used.
    public static func field(for body: BodyShape, settings s: BodySettings, aspect: Double, resolution: Int = 80) -> DisplacementField? {
        guard s.hasReshape, let f = frame(body.pose, aspect: aspect) else { return nil }
        var controls: [WarpControl] = []
        var scales: [LocalScale] = []

        /// Moves both outline points of a level toward (+) or away from (−) its center by
        /// `amount` × half its width, with background anchors just outside and a center anchor.
        func squeeze(_ level: BodyLevel, _ amount: Double, onlyOuter: Bool = false) {
            guard amount != 0, let pair = body.outline[level] else { return }
            let center = iso(pair.center, aspect)
            for point in [iso(pair.first, aspect), iso(pair.second, aspect)] {
                let toCenter: SIMD2<Double> = center - point
                let half = length(toCenter)
                guard half > 1e-6 else { continue }
                let direction: SIMD2<Double> = toCenter / half
                if onlyOuter && level.isThigh && isInnerThighEdge(point, f) { continue }
                let shift: SIMD2<Double> = direction * (amount * half)
                controls.append(WarpControl(source: point, target: point + shift))
                let outside: SIMD2<Double> = point - direction * (0.7 * half)
                controls.append(.anchor(outside))
            }
            controls.append(.anchor(center))
        }

        let waist = s.waist / 100
        squeeze(.waist, 0.13 * waist)
        squeeze(.chest, 0.04 * waist)
        squeeze(.hips, 0.05 * waist)

        let hips = s.hips / 100
        squeeze(.hips, -0.11 * hips)
        squeeze(.waist, -0.03 * hips)
        squeeze(.upperThighLeft, -0.08 * hips, onlyOuter: true)
        squeeze(.upperThighRight, -0.08 * hips, onlyOuter: true)

        let thighs = s.thighs / 100
        for level in [BodyLevel.upperThighLeft, .upperThighRight] { squeeze(level, 0.12 * thighs) }
        for level in [BodyLevel.midThighLeft, .midThighRight] { squeeze(level, 0.1 * thighs) }

        let arms = s.arms / 100
        for level in [BodyLevel.upperArmLeft, .upperArmRight] { squeeze(level, 0.16 * arms) }

        squeeze(.shoulders, -0.07 * s.shoulders / 100)

        // Butt: back views scale and lift the seat; front views widen the lower hip curve a little.
        if s.butt != 0 || s.buttLift != 0 {
            let hipHalf = halfWidth(body.outline[.hips], aspect) ?? f.shoulderWidth * 0.45
            if body.pose.isBackView {
                let down: SIMD2<Double> = f.up * (0.12 * f.torso)
                let seat: SIMD2<Double> = f.hips - down
                let seatRadius = SIMD2(hipHalf * 1.25, f.torso * 0.32)
                let widthScale: Double = 1 + 0.1 * s.butt / 100
                let heightScale: Double = 1 + 0.13 * s.butt / 100
                scales.append(LocalScale(center: seat, radius: seatRadius, axis: f.right, scale: SIMD2(widthScale, heightScale)))
                if s.buttLift != 0 {
                    for t in [-0.5, -0.2, 0.2, 0.5] {
                        let across: SIMD2<Double> = f.right * (t * hipHalf * 1.6)
                        let below: SIMD2<Double> = f.up * (0.3 * f.torso)
                        let bottom: SIMD2<Double> = f.hips + across - below
                        let lift: SIMD2<Double> = f.up * (0.06 * f.torso * s.buttLift / 100)
                        controls.append(WarpControl(source: bottom, target: bottom + lift))
                    }
                    controls.append(.anchor(f.hips + f.up * (0.25 * f.torso)))
                }
            } else {
                squeeze(.upperThighLeft, -0.05 * s.butt / 100, onlyOuter: true)
                squeeze(.upperThighRight, -0.05 * s.butt / 100, onlyOuter: true)
            }
        }

        // Bust/chest (front views): scale around each side of the chest.
        if s.bust != 0, !body.pose.isBackView {
            for side in [-1.0, 1.0] {
                let below: SIMD2<Double> = f.up * (0.3 * f.torso)
                let across: SIMD2<Double> = f.right * (side * 0.22 * f.shoulderWidth)
                let chest: SIMD2<Double> = f.shoulders - below + across
                let chestRadius = SIMD2(0.2 * f.shoulderWidth, 0.17 * f.shoulderWidth)
                let factor: Double = 1 + 0.12 * s.bust / 100
                scales.append(LocalScale(center: chest, radius: chestRadius, axis: f.right, scale: SIMD2(factor, factor)))
            }
        }

        // Head size around the head center.
        if s.headSize != 0 {
            let headPoints = [BodyJoint.nose, .leftEye, .rightEye, .leftEar, .rightEar].compactMap { body.pose[$0] }.map { iso($0, aspect) }
            if !headPoints.isEmpty {
                let center = headPoints.reduce(SIMD2(0, 0), +) / Double(headPoints.count)
                let radius = f.shoulderWidth * 0.42
                let factor = 1 + 0.15 * s.headSize / 100
                scales.append(LocalScale(center: center, radius: SIMD2(radius, radius * 1.2), axis: f.right, scale: SIMD2(factor, factor)))
            }
        }

        guard !controls.isEmpty || !scales.isEmpty else { return nil }
        return DisplacementField.build(controls: controls, scales: scales, region: body.region, aspect: aspect, columns: resolution, rows: resolution)
    }

    static func halfWidth(_ pair: EdgePair?, _ aspect: Double) -> Double? {
        guard let pair else { return nil }
        return length(iso(pair.first, aspect) - iso(pair.second, aspect)) / 2
    }

    static func isInnerThighEdge(_ point: SIMD2<Double>, _ f: Frame) -> Bool {
        // The inner edge of a thigh is the one closer to the body's center line.
        abs(FaceReshape.dot(point - f.hips, f.right)) < f.shoulderWidth * 0.12
    }

    /// Vertical stretches (longer legs, height, neck) as one full-width field (normalized y, y up).
    public static func stretchField(for pose: BodyPose, settings s: BodySettings, rows: Int = 192) -> DisplacementField? {
        guard s.hasStretch, let hips = pose.hipCenter, let shoulders = pose.shoulderCenter else { return nil }
        let torso = max(shoulders.y - hips.y, 0.02)
        let chin = pose[.nose].map { $0.y - torso * 0.12 } ?? shoulders.y + torso * 0.2

        let legs = 1 + 0.16 * s.legs / 100
        let height = 1 + 0.09 * s.height / 100
        let neckShift = 0.05 * torso * s.neck / 100

        // Output y -> source y, built segment by segment; blended over small bands so it stays smooth.
        func source(_ y: Double) -> Double {
            var value = y
            // Height: everything below the shoulders stretches downward from the shoulders.
            if height != 1, value < shoulders.y {
                value = shoulders.y - (shoulders.y - value) / height
            }
            // Legs: below the hips, stretch downward from the hips.
            let hipLine = hips.y - torso * 0.05
            if legs != 1, value < hipLine {
                let band = torso * 0.08
                let t = min(max((hipLine - value) / band, 0), 1)
                let stretched = hipLine - (hipLine - value) / legs
                value = value + (stretched - value) * (t * t * (3 - 2 * t))
            }
            // Neck: lift the head by sampling lower above the chin; ramp between shoulders and chin.
            if neckShift != 0, value > shoulders.y {
                let t = min(max((value - shoulders.y) / max(chin - shoulders.y, 1e-4), 0), 1)
                value -= neckShift * t
            }
            return value
        }

        var offsets: [SIMD2<Float>] = []
        offsets.reserveCapacity(rows * 2)
        for row in 0..<rows {
            let y = Double(row) / Double(rows - 1)
            let dy = Float(source(y) - y)
            offsets.append(SIMD2(0, dy))
            offsets.append(SIMD2(0, dy))
        }
        return DisplacementField(region: CGRectValue(x: 0, y: 0, width: 1, height: 1), columns: 2, rows: rows, offsets: offsets)
    }
}

extension BodyLevel {
    var isThigh: Bool {
        self == .upperThighLeft || self == .upperThighRight || self == .midThighLeft || self == .midThighRight
    }
}
