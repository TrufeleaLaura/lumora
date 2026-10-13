import Foundation

/// Facial landmarks in normalized image coordinates (0...1, y up). "Left"/"right" are as seen
/// in the photo (smaller x = left), regardless of which way the person faces.
public struct FaceLandmarks: Equatable, Sendable {
    public var bounds: CGRectValue
    public var contour: [SIMD2<Double>]
    public var leftEye: [SIMD2<Double>]
    public var rightEye: [SIMD2<Double>]
    public var leftBrow: [SIMD2<Double>]
    public var rightBrow: [SIMD2<Double>]
    public var nose: [SIMD2<Double>]
    public var noseCrest: [SIMD2<Double>]
    public var outerLips: [SIMD2<Double>]
    public var innerLips: [SIMD2<Double>]
    public var leftPupil: SIMD2<Double>?
    public var rightPupil: SIMD2<Double>?
    /// Head roll in radians (positive = counterclockwise), if known.
    public var roll: Double

    public init(
        bounds: CGRectValue,
        contour: [SIMD2<Double>] = [],
        leftEye: [SIMD2<Double>] = [],
        rightEye: [SIMD2<Double>] = [],
        leftBrow: [SIMD2<Double>] = [],
        rightBrow: [SIMD2<Double>] = [],
        nose: [SIMD2<Double>] = [],
        noseCrest: [SIMD2<Double>] = [],
        outerLips: [SIMD2<Double>] = [],
        innerLips: [SIMD2<Double>] = [],
        leftPupil: SIMD2<Double>? = nil,
        rightPupil: SIMD2<Double>? = nil,
        roll: Double = 0
    ) {
        self.bounds = bounds
        self.contour = contour
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.leftBrow = leftBrow
        self.rightBrow = rightBrow
        self.nose = nose
        self.noseCrest = noseCrest
        self.outerLips = outerLips
        self.innerLips = innerLips
        self.leftPupil = leftPupil
        self.rightPupil = rightPupil
        self.roll = roll
    }

    public var anchor: FaceAnchor {
        FaceAnchor(x: bounds.midX, y: bounds.midY, size: max(bounds.width, bounds.height))
    }

    public static func centroid(_ points: [SIMD2<Double>]) -> SIMD2<Double> {
        guard !points.isEmpty else { return SIMD2(0, 0) }
        return points.reduce(SIMD2(0, 0), +) / Double(points.count)
    }
}

/// Identifies a face across re-analysis (by position and size, normalized).
public struct FaceAnchor: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var size: Double

    public init(x: Double, y: Double, size: Double) {
        self.x = x
        self.y = y
        self.size = size
    }

    public func matches(_ other: FaceAnchor) -> Bool {
        hypot(x - other.x, y - other.y) < max(size, other.size) * 0.35
    }
}

/// Retouch and reshape settings for one face (all 0 = untouched).
public struct FaceRetouchSettings: Codable, Hashable, Sendable {
    // Skin (0...100)
    public var smooth: Double = 0
    /// Automatic spot and blemish healing, 0...100.
    public var blemishes: Double = 0
    /// How much fine pore texture survives smoothing.
    public var texture: Double = 60
    public var evenTone: Double = 0
    public var shine: Double = 0
    public var darkCircles: Double = 0
    // Eyes
    public var eyeBrighten: Double = 0
    public var eyeWhiten: Double = 0
    /// Iris recolor amount (0...100) and target hue (0...360).
    public var irisColor: Double = 0
    public var irisHue: Double = 200
    /// -100...100
    public var eyeSize: Double = 0
    public var eyeDistance: Double = 0
    // Teeth
    public var teethWhiten: Double = 0
    // Face shape (-100...100)
    public var faceSlim: Double = 0
    public var cheekbones: Double = 0
    public var jaw: Double = 0
    public var chin: Double = 0
    public var forehead: Double = 0
    public var faceLength: Double = 0
    // Nose (-100...100)
    public var noseWidth: Double = 0
    public var noseLength: Double = 0
    public var noseTip: Double = 0
    // Lips (-100...100)
    public var lipsFullness: Double = 0
    public var lipsWidth: Double = 0
    public var smile: Double = 0
    // Eyebrows, makeup and hair color
    public var makeup = MakeupSettings()

    public init() {}

    public var isIdentity: Bool { self == FaceRetouchSettings() }

    public var hasMakeup: Bool {
        let m = makeup
        return m.browThickness != 0 || m.browColorAmount != 0 || m.lipstickAmount != 0 || m.blushAmount != 0
            || m.contour != 0 || m.highlight != 0 || m.eyeshadowAmount != 0 || m.eyeliner != 0 || m.lashes != 0
    }

    public var hasHairColor: Bool { makeup.hairColorAmount != 0 || makeup.hairOmbre != 0 || makeup.hairShine != 0 }

    /// True if any shape slider (which needs the warp stage) is used.
    public var hasReshape: Bool {
        eyeSize != 0 || eyeDistance != 0 || faceSlim != 0 || cheekbones != 0 || jaw != 0 || chin != 0
            || forehead != 0 || faceLength != 0 || noseWidth != 0 || noseLength != 0 || noseTip != 0
            || lipsFullness != 0 || lipsWidth != 0 || smile != 0 || makeup.hasBrowShape || makeup.hairVolume != 0
    }

    public var hasRetouch: Bool {
        smooth != 0 || blemishes != 0 || evenTone != 0 || shine != 0 || darkCircles != 0 || eyeBrighten != 0 || eyeWhiten != 0
            || irisColor != 0 || teethWhiten != 0
    }
}

/// Per-face edit tied to a detected face.
public struct FaceEdit: Codable, Equatable, Sendable {
    public var anchor: FaceAnchor
    public var settings: FaceRetouchSettings

    public init(anchor: FaceAnchor, settings: FaceRetouchSettings) {
        self.anchor = anchor
        self.settings = settings
    }
}

/// Face retouching for the whole photo: defaults for every face plus per-face overrides.
public struct BeautySettings: Codable, Equatable, Sendable {
    public var allFaces = FaceRetouchSettings()
    public var faces: [FaceEdit] = []

    public init() {}

    public var isIdentity: Bool { allFaces.isIdentity && faces.allSatisfy { $0.settings.isIdentity } }

    /// Settings to use for a detected face.
    public func settings(for anchor: FaceAnchor) -> FaceRetouchSettings {
        faces.first { $0.anchor.matches(anchor) }?.settings ?? allFaces
    }
}

/// Slider definitions for the Face tool.
public enum FaceCatalog {
    public enum Section: String, CaseIterable, Identifiable {
        case skin, eyes, shape, noseLips, teeth, brows, lipstick, cheeks, eyeMakeup, hair

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .skin: return "Skin"
            case .eyes: return "Eyes"
            case .shape: return "Shape"
            case .noseLips: return "Nose & lips"
            case .teeth: return "Teeth"
            case .brows: return "Brows"
            case .lipstick: return "Lipstick"
            case .cheeks: return "Blush & contour"
            case .eyeMakeup: return "Eye makeup"
            case .hair: return "Hair"
            }
        }

        public var symbol: String {
            switch self {
            case .skin: return "drop"
            case .eyes: return "eye"
            case .shape: return "face.dashed"
            case .noseLips: return "mouth"
            case .teeth: return "sparkle"
            case .brows: return "eyebrow"
            case .lipstick: return "paintbrush.pointed"
            case .cheeks: return "circle.hexagongrid"
            case .eyeMakeup: return "eye.circle"
            case .hair: return "scissors"
            }
        }

        /// Color palette shown in this section, with the setting it changes.
        public var palette: (colors: [(String, MakeupColor)], keyPath: WritableKeyPath<MakeupSettings, MakeupColor>)? {
            switch self {
            case .brows: return (MakeupPalette.brows, \.browColor)
            case .lipstick: return (MakeupPalette.lipstick, \.lipstickColor)
            case .cheeks: return (MakeupPalette.blush, \.blushColor)
            case .eyeMakeup: return (MakeupPalette.eyeshadow, \.eyeshadowColor)
            case .hair: return (MakeupPalette.hair, \.hairColor)
            default: return nil
            }
        }
    }

    /// Sliders of a section, bound to the given face settings in the document.
    public static func sliders(_ section: Section, target: WritableKeyPath<EditDocument, FaceRetouchSettings>) -> [SliderSpec] {
        func spec(_ id: String, _ title: String, _ path: WritableKeyPath<FaceRetouchSettings, Double>, range: ClosedRange<Double> = -100...100, defaultValue: Double = 0) -> SliderSpec {
            SliderSpec(
                id: "face.\(id)",
                title: title,
                range: range,
                defaultValue: defaultValue,
                style: range.lowerBound < 0 ? .signedInteger : .integer,
                keyPath: target.appending(path: path)
            )
        }
        switch section {
        case .skin:
            return [
                spec("blemishes", "Remove blemishes", \.blemishes, range: 0...100),
                spec("smooth", "Smooth", \.smooth, range: 0...100),
                spec("texture", "Keep texture", \.texture, range: 0...100, defaultValue: 60),
                spec("evenTone", "Even tone", \.evenTone, range: 0...100),
                spec("shine", "Reduce shine", \.shine, range: 0...100),
                spec("darkCircles", "Dark circles", \.darkCircles, range: 0...100),
            ]
        case .eyes:
            return [
                spec("eyeBrighten", "Brighten", \.eyeBrighten, range: 0...100),
                spec("eyeWhiten", "Whiten", \.eyeWhiten, range: 0...100),
                spec("eyeSize", "Size", \.eyeSize),
                spec("eyeDistance", "Distance", \.eyeDistance),
                spec("irisColor", "Iris color", \.irisColor, range: 0...100),
                spec("irisHue", "Iris hue", \.irisHue, range: 0...360, defaultValue: 200),
            ]
        case .shape:
            return [
                spec("faceSlim", "Slim face", \.faceSlim),
                spec("cheekbones", "Cheekbones", \.cheekbones),
                spec("jaw", "Jawline", \.jaw),
                spec("chin", "Chin", \.chin),
                spec("forehead", "Forehead", \.forehead),
                spec("faceLength", "Face length", \.faceLength),
            ]
        case .noseLips:
            return [
                spec("noseWidth", "Nose width", \.noseWidth),
                spec("noseLength", "Nose length", \.noseLength),
                spec("noseTip", "Nose tip", \.noseTip),
                spec("lipsFullness", "Lip fullness", \.lipsFullness),
                spec("lipsWidth", "Lip width", \.lipsWidth),
                spec("smile", "Smile", \.smile),
            ]
        case .teeth:
            return [spec("teethWhiten", "Whiten teeth", \.teethWhiten, range: 0...100)]
        case .brows:
            return [
                spec("browThickness", "Fuller", \.makeup.browThickness, range: 0...100),
                spec("browColorAmount", "Color", \.makeup.browColorAmount, range: 0...100),
                spec("browLift", "Lift", \.makeup.browLift),
                spec("browArch", "Arch", \.makeup.browArch),
                spec("browTilt", "Tilt", \.makeup.browTilt),
            ]
        case .lipstick:
            return [spec("lipstickAmount", "Lipstick", \.makeup.lipstickAmount, range: 0...100)]
        case .cheeks:
            return [
                spec("blushAmount", "Blush", \.makeup.blushAmount, range: 0...100),
                spec("contour", "Contour", \.makeup.contour, range: 0...100),
                spec("highlight", "Highlight", \.makeup.highlight, range: 0...100),
            ]
        case .eyeMakeup:
            return [
                spec("eyeshadowAmount", "Eyeshadow", \.makeup.eyeshadowAmount, range: 0...100),
                spec("eyeliner", "Eyeliner", \.makeup.eyeliner, range: 0...100),
                spec("lashes", "Lashes", \.makeup.lashes, range: 0...100),
            ]
        case .hair:
            return [
                spec("hairColorAmount", "Color", \.makeup.hairColorAmount, range: 0...100),
                spec("hairOmbre", "Ombré", \.makeup.hairOmbre, range: 0...100),
                spec("hairShine", "Shine", \.makeup.hairShine, range: 0...100),
                spec("hairVolume", "Volume", \.makeup.hairVolume),
            ]
        }
    }

    /// One-tap natural retouch.
    public static var autoBeauty: FaceRetouchSettings {
        var settings = FaceRetouchSettings()
        settings.smooth = 45
        settings.blemishes = 80
        settings.evenTone = 25
        settings.shine = 30
        settings.darkCircles = 30
        settings.eyeBrighten = 20
        settings.eyeWhiten = 25
        settings.teethWhiten = 30
        return settings
    }
}
