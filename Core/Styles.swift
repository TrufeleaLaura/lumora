import Foundation

/// What stays sharp with Lens Blur.
public enum FocusMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// The main subject (Vision), background blurred like a fast lens.
    case subject
    /// An ellipse around a point.
    case radial
    /// A band across the photo (tilt-shift).
    case band

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .subject: return "Subject"
        case .radial: return "Radial"
        case .band: return "Tilt-shift"
        }
    }
}

/// Depth-of-field effect (Snapseed Lens Blur / Tilt-Shift, Lightroom Lens Blur).
public struct LensBlurSettings: Codable, Equatable, Sendable {
    /// 0...100
    public var amount: Double = 0
    public var mode: FocusMode = .subject
    /// Focus center (normalized, y up).
    public var center = SIMD2<Double>(0.5, 0.5)
    /// Radial: focus radius; band: half height (fractions of the photo width).
    public var size: Double = 0.22
    /// 0...100, length of the sharp-to-blurred transition.
    public var transition: Double = 50
    /// Band rotation in degrees.
    public var angle: Double = 0
    /// 0...100, how much bright spots bloom into discs.
    public var bokeh: Double = 40
    /// 0...100, extra saturation and contrast for the miniature (tilt-shift) look.
    public var miniature: Double = 0

    public init() {}
}

/// Snapseed-style creative effects (all 0 = off).
public struct CreativeSettings: Codable, Equatable, Sendable {
    /// HDR Scape: compressed tones with strong local detail, 0...100.
    public var hdr: Double = 0
    /// Drama: gritty mid-scale detail, 0...100, with its own saturation (-100...100).
    public var drama: Double = 0
    public var dramaSaturation: Double = 0
    /// Tonal Contrast: fine detail per tonal range, 0...100.
    public var tonalHigh: Double = 0
    public var tonalMid: Double = 0
    public var tonalLow: Double = 0
    /// Glamour Glow, 0...100, warmth -100...100.
    public var glow: Double = 0
    public var glowWarmth: Double = 0
    /// Film halation: red-orange halos around highlights, 0...100.
    public var halation: Double = 0
    /// Faded, warm vintage film, 0...100.
    public var vintage: Double = 0
    /// High-contrast black & white with a washed glow, 0...100.
    public var noir: Double = 0
    /// Gritty texture, 0...100, and its variation (0...4).
    public var grunge: Double = 0
    public var grungeStyle: Double = 0
    /// Chromatic channel offset, 0...100.
    public var rgbSplit: Double = 0
    public var lensBlur = LensBlurSettings()

    public init() {}

    public var isIdentity: Bool {
        hdr == 0 && drama == 0 && tonalHigh == 0 && tonalMid == 0 && tonalLow == 0 && glow == 0 && halation == 0
            && vintage == 0 && noir == 0 && grunge == 0 && rgbSplit == 0 && lensBlur.amount == 0
    }
}

/// The Styles tool's effects and their sliders.
public enum StyleCatalog {
    public enum Effect: String, CaseIterable, Identifiable, Sendable {
        case hdr, drama, tonal, glow, halation, vintage, noir, grunge, rgbSplit, lensBlur

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .hdr: return "HDR Scape"
            case .drama: return "Drama"
            case .tonal: return "Tonal contrast"
            case .glow: return "Glamour glow"
            case .halation: return "Halation"
            case .vintage: return "Vintage"
            case .noir: return "Noir"
            case .grunge: return "Grunge"
            case .rgbSplit: return "RGB split"
            case .lensBlur: return "Lens blur"
            }
        }

        public var symbol: String {
            switch self {
            case .hdr: return "mountain.2"
            case .drama: return "theatermasks"
            case .tonal: return "circle.lefthalf.striped.horizontal"
            case .glow: return "sparkles"
            case .halation: return "sun.haze"
            case .vintage: return "film"
            case .noir: return "moon"
            case .grunge: return "scribble.variable"
            case .rgbSplit: return "square.3.layers.3d"
            case .lensBlur: return "camera.aperture"
            }
        }

        /// True when the effect is in use.
        public func isActive(_ s: CreativeSettings) -> Bool {
            switch self {
            case .hdr: return s.hdr > 0
            case .drama: return s.drama > 0
            case .tonal: return s.tonalHigh > 0 || s.tonalMid > 0 || s.tonalLow > 0
            case .glow: return s.glow > 0
            case .halation: return s.halation > 0
            case .vintage: return s.vintage > 0
            case .noir: return s.noir > 0
            case .grunge: return s.grunge > 0
            case .rgbSplit: return s.rgbSplit > 0
            case .lensBlur: return s.lensBlur.amount > 0
            }
        }
    }

    public static func sliders(_ effect: Effect) -> [SliderSpec] {
        func spec(_ id: String, _ title: String, _ key: WritableKeyPath<CreativeSettings, Double>, range: ClosedRange<Double> = 0...100, defaultValue: Double = 0, style: SliderValueStyle = .integer) -> SliderSpec {
            SliderSpec(id: "styles.\(id)", title: title, range: range, defaultValue: defaultValue, style: style, keyPath: (\EditDocument.styles).appending(path: key))
        }
        switch effect {
        case .hdr:
            return [spec("hdr", "Strength", \.hdr)]
        case .drama:
            return [spec("drama", "Strength", \.drama), spec("dramaSaturation", "Saturation", \.dramaSaturation, range: -100...100, style: .signedInteger)]
        case .tonal:
            return [spec("tonalHigh", "High tones", \.tonalHigh), spec("tonalMid", "Mid tones", \.tonalMid), spec("tonalLow", "Low tones", \.tonalLow)]
        case .glow:
            return [spec("glow", "Glow", \.glow), spec("glowWarmth", "Warmth", \.glowWarmth, range: -100...100, style: .signedInteger)]
        case .halation:
            return [spec("halation", "Strength", \.halation)]
        case .vintage:
            return [spec("vintage", "Strength", \.vintage)]
        case .noir:
            return [spec("noir", "Strength", \.noir)]
        case .grunge:
            return [spec("grunge", "Strength", \.grunge), spec("grungeStyle", "Style", \.grungeStyle, range: 0...4, style: .integer)]
        case .rgbSplit:
            return [spec("rgbSplit", "Strength", \.rgbSplit)]
        case .lensBlur:
            return [
                spec("lensBlur.amount", "Blur", \.lensBlur.amount),
                spec("lensBlur.size", "Focus size", \.lensBlur.size, range: 0.03...0.6, defaultValue: 0.22, style: .percent),
                spec("lensBlur.transition", "Transition", \.lensBlur.transition, defaultValue: 50),
                spec("lensBlur.bokeh", "Bokeh", \.lensBlur.bokeh, defaultValue: 40),
                spec("lensBlur.angle", "Angle", \.lensBlur.angle, range: -90...90, style: .degrees),
                spec("lensBlur.miniature", "Miniature", \.lensBlur.miniature),
            ]
        }
    }
}
