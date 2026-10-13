import Foundation

/// Body joints (Vision's 2D human body pose). Raw values are Vision's joint names.
public enum BodyJoint: String, CaseIterable, Codable, Sendable {
    case nose = "head_joint"
    case leftEye = "left_eye_joint"
    case rightEye = "right_eye_joint"
    case leftEar = "left_ear_joint"
    case rightEar = "right_ear_joint"
    case neck = "neck_1_joint"
    case leftShoulder = "left_shoulder_1_joint"
    case rightShoulder = "right_shoulder_1_joint"
    case leftElbow = "left_forearm_joint"
    case rightElbow = "right_forearm_joint"
    case leftWrist = "left_hand_joint"
    case rightWrist = "right_hand_joint"
    case root = "root"
    case leftHip = "left_upLeg_joint"
    case rightHip = "right_upLeg_joint"
    case leftKnee = "left_leg_joint"
    case rightKnee = "right_leg_joint"
    case leftAnkle = "left_foot_joint"
    case rightAnkle = "right_foot_joint"
}

/// A detected person: joints in normalized image coordinates (y up). Left/right are the
/// person's own (as Vision reports them).
public struct BodyPose: Equatable, Sendable {
    public var joints: [BodyJoint: SIMD2<Double>]

    public init(joints: [BodyJoint: SIMD2<Double>]) {
        self.joints = joints
    }

    public subscript(_ joint: BodyJoint) -> SIMD2<Double>? { joints[joint] }

    /// Hip center (Vision's root, or the midpoint of the hips).
    public var hipCenter: SIMD2<Double>? {
        if let root = joints[.root] { return root }
        if let l = joints[.leftHip], let r = joints[.rightHip] { return (l + r) / 2 }
        return nil
    }

    public var shoulderCenter: SIMD2<Double>? {
        if let l = joints[.leftShoulder], let r = joints[.rightShoulder] { return (l + r) / 2 }
        return joints[.neck]
    }

    /// True when the person faces away from the camera (their left shoulder is on the photo's left).
    public var isBackView: Bool {
        guard let l = joints[.leftShoulder], let r = joints[.rightShoulder] else { return false }
        return l.x < r.x
    }

    public var anchor: BodyAnchor? {
        guard let hips = hipCenter, let shoulders = shoulderCenter else { return nil }
        let delta: SIMD2<Double> = shoulders - hips
        let length: Double = (delta.x * delta.x + delta.y * delta.y).squareRoot()
        return BodyAnchor(x: hips.x, y: hips.y, size: length)
    }
}

/// Identifies a person across re-analysis (hip position and torso size, normalized).
public struct BodyAnchor: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var size: Double

    public init(x: Double, y: Double, size: Double) {
        self.x = x
        self.y = y
        self.size = size
    }

    public func matches(_ other: BodyAnchor) -> Bool {
        hypot(x - other.x, y - other.y) < max(size, other.size) * 0.5
    }
}

/// Body reshaping, muscle definition and body skin (all 0 = untouched).
public struct BodySettings: Codable, Hashable, Sendable {
    // Shape (-100...100)
    public var waist: Double = 0
    public var hips: Double = 0
    public var butt: Double = 0
    public var buttLift: Double = 0
    public var bust: Double = 0
    public var thighs: Double = 0
    public var legs: Double = 0
    public var height: Double = 0
    public var arms: Double = 0
    public var shoulders: Double = 0
    public var neck: Double = 0
    public var headSize: Double = 0

    public init() {}

    public var isIdentity: Bool { self == BodySettings() }

    public var hasReshape: Bool {
        waist != 0 || hips != 0 || butt != 0 || buttLift != 0 || bust != 0 || thighs != 0 || arms != 0
            || shoulders != 0 || headSize != 0
    }

    public var hasStretch: Bool { legs != 0 || height != 0 || neck != 0 }
}

public struct BodyEdit: Codable, Equatable, Sendable {
    public var anchor: BodyAnchor
    public var settings: BodySettings

    public init(anchor: BodyAnchor, settings: BodySettings) {
        self.anchor = anchor
        self.settings = settings
    }
}

/// Body edits for the photo: defaults for every person plus per-person overrides.
public struct BodyEditSettings: Codable, Equatable, Sendable {
    public var allBodies = BodySettings()
    public var bodies: [BodyEdit] = []

    public init() {}

    public var isIdentity: Bool { allBodies.isIdentity && bodies.allSatisfy { $0.settings.isIdentity } }

    public func settings(for anchor: BodyAnchor?) -> BodySettings {
        guard let anchor else { return allBodies }
        return bodies.first { $0.anchor.matches(anchor) }?.settings ?? allBodies
    }
}

public enum BodyCatalog {
    public enum Section: String, CaseIterable, Identifiable {
        case shape, length, upper

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .shape: return "Shape"
            case .length: return "Length"
            case .upper: return "Upper body"
            }
        }

        public var symbol: String {
            switch self {
            case .shape: return "figure.stand"
            case .length: return "arrow.up.and.down"
            case .upper: return "figure.arms.open"
            }
        }
    }

    public static func sliders(_ section: Section, target: WritableKeyPath<EditDocument, BodySettings>) -> [SliderSpec] {
        func spec(_ id: String, _ title: String, _ path: WritableKeyPath<BodySettings, Double>) -> SliderSpec {
            SliderSpec(id: "body.\(id)", title: title, range: -100...100, keyPath: target.appending(path: path))
        }
        switch section {
        case .shape:
            return [
                spec("waist", "Slim waist", \.waist),
                spec("hips", "Hips", \.hips),
                spec("butt", "Butt", \.butt),
                spec("buttLift", "Butt lift", \.buttLift),
                spec("bust", "Bust / chest", \.bust),
                spec("thighs", "Slim thighs", \.thighs),
            ]
        case .length:
            return [
                spec("legs", "Longer legs", \.legs),
                spec("height", "Height", \.height),
                spec("neck", "Neck", \.neck),
            ]
        case .upper:
            return [
                spec("shoulders", "Shoulders", \.shoulders),
                spec("arms", "Slim arms", \.arms),
                spec("headSize", "Head size", \.headSize),
            ]
        }
    }
}
