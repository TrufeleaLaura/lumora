import Foundation

/// Global tone settings (Lightroom's "Light" panel).
public struct LightSettings: Codable, Equatable, Sendable {
    /// Exposure in EV stops, -5...+5.
    public var exposure: Double = 0
    /// -100...+100 for the rest.
    public var contrast: Double = 0
    public var highlights: Double = 0
    public var shadows: Double = 0
    public var whites: Double = 0
    public var blacks: Double = 0

    public init() {}
}

/// Global color settings (Lightroom's "Color" panel).
public struct ColorSettings: Codable, Equatable, Sendable {
    /// -100 (cooler) ... +100 (warmer)
    public var temperature: Double = 0
    /// -100 (green) ... +100 (magenta)
    public var tint: Double = 0
    public var vibrance: Double = 0
    /// -100 (monochrome) ... +100
    public var saturation: Double = 0

    public init() {}
}

/// The eight hue ranges of the color mixer.
public enum HueBand: Int, CaseIterable, Codable, Sendable, Identifiable {
    case red, orange, yellow, green, aqua, blue, purple, magenta

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .aqua: return "Aqua"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .magenta: return "Magenta"
        }
    }

    /// Representative sRGB color for UI swatches.
    public var swatch: (red: Double, green: Double, blue: Double) {
        switch self {
        case .red: return (0.90, 0.20, 0.20)
        case .orange: return (0.95, 0.55, 0.15)
        case .yellow: return (0.95, 0.85, 0.20)
        case .green: return (0.25, 0.75, 0.30)
        case .aqua: return (0.20, 0.75, 0.80)
        case .blue: return (0.20, 0.40, 0.90)
        case .purple: return (0.55, 0.30, 0.85)
        case .magenta: return (0.85, 0.25, 0.65)
        }
    }
}

/// HSL color mixer: per-band hue shift, saturation and luminance (-100...+100).
public struct ColorMixerSettings: Codable, Equatable, Sendable {
    public var hue: [Double] = Array(repeating: 0, count: 8)
    public var saturation: [Double] = Array(repeating: 0, count: 8)
    public var luminance: [Double] = Array(repeating: 0, count: 8)

    public init() {}
}

/// One color-grading wheel.
public struct GradingWheel: Codable, Equatable, Sendable {
    /// 0...360 degrees on a standard hue wheel (0 = red).
    public var hue: Double = 0
    /// 0...100
    public var saturation: Double = 0
    /// -100...+100
    public var luminance: Double = 0

    public init(hue: Double = 0, saturation: Double = 0, luminance: Double = 0) {
        self.hue = hue
        self.saturation = saturation
        self.luminance = luminance
    }
}

/// 3-way color grading (Lightroom "Color Grading").
public struct ColorGradingSettings: Codable, Equatable, Sendable {
    public var shadows = GradingWheel()
    public var midtones = GradingWheel()
    public var highlights = GradingWheel()
    public var global = GradingWheel()
    /// 0...100, how much the tonal ranges overlap.
    public var blending: Double = 50
    /// -100...+100, shifts the split between shadows and highlights.
    public var balance: Double = 0

    public init() {}
}

/// Black & white conversion with a per-band luminance mix (-100...+100).
public struct BlackWhiteSettings: Codable, Equatable, Sendable {
    public var isEnabled = false
    public var mix: [Double] = Array(repeating: 0, count: 8)

    public init() {}
}

public struct CurvePoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum CurveChannel: String, CaseIterable, Codable, Sendable, Identifiable {
    case master, red, green, blue

    public var id: String { rawValue }
}

/// Point curves (perceptual 0...1 space) plus Lightroom-style parametric regions.
public struct ToneCurveSettings: Codable, Equatable, Sendable {
    public static let linear = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]

    public var master: [CurvePoint] = ToneCurveSettings.linear
    public var red: [CurvePoint] = ToneCurveSettings.linear
    public var green: [CurvePoint] = ToneCurveSettings.linear
    public var blue: [CurvePoint] = ToneCurveSettings.linear
    /// Parametric regions, -100...+100.
    public var highlights: Double = 0
    public var lights: Double = 0
    public var darks: Double = 0
    public var shadows: Double = 0

    public init() {}

    public func points(for channel: CurveChannel) -> [CurvePoint] {
        switch channel {
        case .master: return master
        case .red: return red
        case .green: return green
        case .blue: return blue
        }
    }

    public mutating func setPoints(_ points: [CurvePoint], for channel: CurveChannel) {
        switch channel {
        case .master: master = points
        case .red: red = points
        case .green: green = points
        case .blue: blue = points
        }
    }
}

/// Lightroom "Effects" plus Tezza-style fade.
public struct EffectsSettings: Codable, Equatable, Sendable {
    /// -100...+100
    public var texture: Double = 0
    public var clarity: Double = 0
    public var dehaze: Double = 0
    /// -100 (dark) ... +100 (light)
    public var vignette: Double = 0
    /// 0...100
    public var vignetteMidpoint: Double = 50
    /// -100...+100
    public var vignetteRoundness: Double = 0
    /// 0...100
    public var vignetteFeather: Double = 50
    /// 0...100, keeps bright areas from darkening.
    public var vignetteHighlights: Double = 0
    /// 0...100
    public var grain: Double = 0
    /// 0...100
    public var grainSize: Double = 25
    /// 0...100
    public var grainRoughness: Double = 50
    /// 0...100, matte lift of the blacks.
    public var fade: Double = 0

    public init() {}
}

/// Sharpening and noise reduction.
public struct DetailSettings: Codable, Equatable, Sendable {
    /// 0...150
    public var sharpening: Double = 0
    /// 0.5...3.0 pixels
    public var sharpenRadius: Double = 1.0
    /// 0...100
    public var sharpenDetail: Double = 25
    /// 0...100
    public var sharpenMasking: Double = 0
    /// 0...100
    public var noiseReduction: Double = 0
    /// 0...100
    public var noiseDetail: Double = 50
    /// 0...100
    public var colorNoiseReduction: Double = 0

    public init() {}
}

/// Manual lens corrections.
public struct OpticsSettings: Codable, Equatable, Sendable {
    /// -100 (pincushion fix) ... +100 (barrel fix)
    public var distortion: Double = 0
    /// -100...+100, brightens (+) or darkens (-) the corners to undo lens vignetting.
    public var vignetteCorrection: Double = 0
    /// 0...100, removes purple/green fringes on high-contrast edges.
    public var defringe: Double = 0

    public init() {}
}

/// The complete, non-destructive description of an edit. Rendering a source image
/// through `RenderPipeline` with this document produces the edited result.
public struct EditDocument: Codable, Equatable, Sendable {
    public var formatVersion: Int = 2
    public var light = LightSettings()
    public var color = ColorSettings()
    public var mixer = ColorMixerSettings()
    public var grading = ColorGradingSettings()
    public var blackWhite = BlackWhiteSettings()
    public var curve = ToneCurveSettings()
    public var effects = EffectsSettings()
    public var detail = DetailSettings()
    public var optics = OpticsSettings()
    public var geometry = GeometrySettings()
    public var look = LookSettings()
    public var beauty = BeautySettings()
    public var body = BodyEditSettings()
    /// Local adjustments, applied in order.
    public var masks: [Mask] = []
    /// Heal, clone, remove and red eye (applied first).
    public var retouch = RetouchSettings()
    /// Snapseed-style creative effects and lens blur.
    public var styles = CreativeSettings()

    public init() {}

    /// The document's adjustments without photo-specific geometry (for presets and paste).
    public func adjustmentsOnly(keeping geometry: GeometrySettings) -> EditDocument {
        var copy = self
        copy.geometry = geometry
        // Per-face/per-person edits are tied to this photo; the "all" settings carry over.
        copy.beauty.faces = []
        copy.body.bodies = []
        copy.retouch = RetouchSettings()
        // Automatic and shape masks carry over; painted strokes and tapped objects belong to this photo.
        copy.masks = masks.compactMap { mask in
            var mask = mask
            mask.components.removeAll { $0.kind == .brush || $0.kind == .object }
            return mask.components.isEmpty ? nil : mask
        }
        return copy
    }

    /// True when the document makes no change to the image.
    public var isIdentity: Bool {
        var normalized = self
        normalized.formatVersion = EditDocument().formatVersion
        return normalized == EditDocument()
    }
}
