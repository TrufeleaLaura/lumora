import Foundation

/// How a slider value is displayed.
public enum SliderValueStyle: Sendable {
    /// "+25", "-10", "0" for bipolar sliders.
    case signedInteger
    /// "25" for 0...N sliders.
    case integer
    /// "+1.25", "-0.50", "0.00" (exposure stops)
    case ev
    /// "1.0"
    case decimal
    /// "120°"
    case degrees
}

/// Data description of one adjustment slider. The UI is generated from these specs,
/// so adding a new adjustment only needs a model field, a spec and a render step.
public struct SliderSpec: Identifiable {
    public let id: String
    public let title: String
    public let range: ClosedRange<Double>
    public let defaultValue: Double
    public let style: SliderValueStyle
    public let keyPath: WritableKeyPath<EditDocument, Double>

    public init(
        id: String,
        title: String,
        range: ClosedRange<Double>,
        defaultValue: Double = 0,
        style: SliderValueStyle = .signedInteger,
        keyPath: WritableKeyPath<EditDocument, Double>
    ) {
        self.id = id
        self.title = title
        self.range = range
        self.defaultValue = defaultValue
        self.style = style
        self.keyPath = keyPath
    }

    /// True when the slider is centered on zero (fill grows left or right of the middle).
    public var isBipolar: Bool { range.lowerBound < 0 && range.upperBound > 0 }

    public func formatted(_ value: Double) -> String {
        switch style {
        case .ev:
            if abs(value) < 0.005 { return "0.00" }
            return String(format: "%+.2f", value)
        case .signedInteger:
            let rounded = Int(value.rounded())
            return rounded > 0 ? "+\(rounded)" : "\(rounded)"
        case .integer:
            return "\(Int(value.rounded()))"
        case .decimal:
            return String(format: "%.1f", value)
        case .degrees:
            return "\(Int(value.rounded()))°"
        }
    }
}

/// A panel of related sliders in the editor ("Light", "Color", ...).
public struct ToolGroup: Identifiable {
    public let id: String
    public let title: String
    /// SF Symbol name.
    public let symbol: String
    public let sliders: [SliderSpec]

    public init(id: String, title: String, symbol: String, sliders: [SliderSpec]) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.sliders = sliders
    }
}

public enum AdjustmentCatalog {
    public static let light = ToolGroup(id: "light", title: "Light", symbol: "sun.max", sliders: [
        SliderSpec(id: "exposure", title: "Exposure", range: -5...5, style: .ev, keyPath: \.light.exposure),
        SliderSpec(id: "contrast", title: "Contrast", range: -100...100, keyPath: \.light.contrast),
        SliderSpec(id: "highlights", title: "Highlights", range: -100...100, keyPath: \.light.highlights),
        SliderSpec(id: "shadows", title: "Shadows", range: -100...100, keyPath: \.light.shadows),
        SliderSpec(id: "whites", title: "Whites", range: -100...100, keyPath: \.light.whites),
        SliderSpec(id: "blacks", title: "Blacks", range: -100...100, keyPath: \.light.blacks),
    ])

    public static let color = ToolGroup(id: "color", title: "Color", symbol: "thermometer.medium", sliders: [
        SliderSpec(id: "temperature", title: "Temperature", range: -100...100, keyPath: \.color.temperature),
        SliderSpec(id: "tint", title: "Tint", range: -100...100, keyPath: \.color.tint),
        SliderSpec(id: "vibrance", title: "Vibrance", range: -100...100, keyPath: \.color.vibrance),
        SliderSpec(id: "saturation", title: "Saturation", range: -100...100, keyPath: \.color.saturation),
    ])

    public static let effects = ToolGroup(id: "effects", title: "Effects", symbol: "sparkles", sliders: [
        SliderSpec(id: "texture", title: "Texture", range: -100...100, keyPath: \.effects.texture),
        SliderSpec(id: "clarity", title: "Clarity", range: -100...100, keyPath: \.effects.clarity),
        SliderSpec(id: "dehaze", title: "Dehaze", range: -100...100, keyPath: \.effects.dehaze),
        SliderSpec(id: "fade", title: "Fade", range: 0...100, style: .integer, keyPath: \.effects.fade),
        SliderSpec(id: "vignette", title: "Vignette", range: -100...100, keyPath: \.effects.vignette),
        SliderSpec(id: "vignetteMidpoint", title: "Midpoint", range: 0...100, defaultValue: 50, style: .integer, keyPath: \.effects.vignetteMidpoint),
        SliderSpec(id: "vignetteFeather", title: "Feather", range: 0...100, defaultValue: 50, style: .integer, keyPath: \.effects.vignetteFeather),
        SliderSpec(id: "vignetteRoundness", title: "Roundness", range: -100...100, keyPath: \.effects.vignetteRoundness),
        SliderSpec(id: "vignetteHighlights", title: "Vignette highlights", range: 0...100, style: .integer, keyPath: \.effects.vignetteHighlights),
        SliderSpec(id: "grain", title: "Grain", range: 0...100, style: .integer, keyPath: \.effects.grain),
        SliderSpec(id: "grainSize", title: "Grain size", range: 0...100, defaultValue: 25, style: .integer, keyPath: \.effects.grainSize),
        SliderSpec(id: "grainRoughness", title: "Roughness", range: 0...100, defaultValue: 50, style: .integer, keyPath: \.effects.grainRoughness),
    ])

    public static let detail = ToolGroup(id: "detail", title: "Detail", symbol: "triangle", sliders: [
        SliderSpec(id: "sharpening", title: "Sharpening", range: 0...150, style: .integer, keyPath: \.detail.sharpening),
        SliderSpec(id: "sharpenRadius", title: "Radius", range: 0.5...3.0, defaultValue: 1.0, style: .decimal, keyPath: \.detail.sharpenRadius),
        SliderSpec(id: "sharpenDetail", title: "Detail", range: 0...100, defaultValue: 25, style: .integer, keyPath: \.detail.sharpenDetail),
        SliderSpec(id: "sharpenMasking", title: "Masking", range: 0...100, style: .integer, keyPath: \.detail.sharpenMasking),
        SliderSpec(id: "noiseReduction", title: "Noise reduction", range: 0...100, style: .integer, keyPath: \.detail.noiseReduction),
        SliderSpec(id: "noiseDetail", title: "Noise detail", range: 0...100, defaultValue: 50, style: .integer, keyPath: \.detail.noiseDetail),
        SliderSpec(id: "colorNoiseReduction", title: "Color noise", range: 0...100, style: .integer, keyPath: \.detail.colorNoiseReduction),
    ])

    public static let optics = ToolGroup(id: "optics", title: "Optics", symbol: "camera.aperture", sliders: [
        SliderSpec(id: "distortion", title: "Distortion", range: -100...100, keyPath: \.optics.distortion),
        SliderSpec(id: "vignetteCorrection", title: "Lens vignetting", range: -100...100, keyPath: \.optics.vignetteCorrection),
        SliderSpec(id: "defringe", title: "Defringe", range: 0...100, style: .integer, keyPath: \.optics.defringe),
    ])

    public static let curveParametric = ToolGroup(id: "curveParametric", title: "Parametric", symbol: "point.topleft.down.to.point.bottomright.curvepath", sliders: [
        SliderSpec(id: "curveHighlights", title: "Highlights", range: -100...100, keyPath: \.curve.highlights),
        SliderSpec(id: "curveLights", title: "Lights", range: -100...100, keyPath: \.curve.lights),
        SliderSpec(id: "curveDarks", title: "Darks", range: -100...100, keyPath: \.curve.darks),
        SliderSpec(id: "curveShadows", title: "Shadows", range: -100...100, keyPath: \.curve.shadows),
    ])

    public static let grading = ToolGroup(id: "gradingBalance", title: "Grading", symbol: "circle.lefthalf.filled", sliders: [
        SliderSpec(id: "gradingBlending", title: "Blending", range: 0...100, defaultValue: 50, style: .integer, keyPath: \.grading.blending),
        SliderSpec(id: "gradingBalance", title: "Balance", range: -100...100, keyPath: \.grading.balance),
    ])

    /// Slider-only panels.
    public static let groups: [ToolGroup] = [light, color, effects, detail, optics]

    /// Every slider in the app (for validation).
    public static var allSliders: [SliderSpec] {
        (groups + [curveParametric, grading]).flatMap(\.sliders) + mixerSliders(.hue) + mixerSliders(.saturation)
            + mixerSliders(.luminance) + blackWhiteSliders + gradingWheelSliders(.shadows) + gradingWheelSliders(.midtones)
            + gradingWheelSliders(.highlights) + gradingWheelSliders(.global)
    }

    // MARK: - Mixer

    public enum MixerChannel: String, CaseIterable, Identifiable {
        case hue, saturation, luminance

        public var id: String { rawValue }
        public var title: String { rawValue.capitalized }
    }

    public static func mixerSliders(_ channel: MixerChannel) -> [SliderSpec] {
        HueBand.allCases.map { band in
            let keyPath: WritableKeyPath<EditDocument, Double>
            switch channel {
            case .hue: keyPath = \EditDocument.mixer.hue[band.rawValue]
            case .saturation: keyPath = \EditDocument.mixer.saturation[band.rawValue]
            case .luminance: keyPath = \EditDocument.mixer.luminance[band.rawValue]
            }
            return SliderSpec(id: "mixer.\(channel.rawValue).\(band.rawValue)", title: band.title, range: -100...100, keyPath: keyPath)
        }
    }

    public static var blackWhiteSliders: [SliderSpec] {
        HueBand.allCases.map { band in
            SliderSpec(id: "bw.\(band.rawValue)", title: band.title, range: -100...100, keyPath: \EditDocument.blackWhite.mix[band.rawValue])
        }
    }

    // MARK: - Grading wheels

    public enum GradingRange: String, CaseIterable, Identifiable {
        case shadows, midtones, highlights, global

        public var id: String { rawValue }
        public var title: String { rawValue.capitalized }

        public var keyPath: WritableKeyPath<EditDocument, GradingWheel> {
            switch self {
            case .shadows: return \EditDocument.grading.shadows
            case .midtones: return \EditDocument.grading.midtones
            case .highlights: return \EditDocument.grading.highlights
            case .global: return \EditDocument.grading.global
            }
        }
    }

    public static func gradingWheelSliders(_ range: GradingRange) -> [SliderSpec] {
        let wheel = range.keyPath
        return [
            SliderSpec(id: "grading.\(range.rawValue).hue", title: "Hue", range: 0...360, style: .degrees, keyPath: wheel.appending(path: \GradingWheel.hue)),
            SliderSpec(id: "grading.\(range.rawValue).saturation", title: "Saturation", range: 0...100, style: .integer, keyPath: wheel.appending(path: \GradingWheel.saturation)),
            SliderSpec(id: "grading.\(range.rawValue).luminance", title: "Luminance", range: -100...100, keyPath: wheel.appending(path: \GradingWheel.luminance)),
        ]
    }
}
