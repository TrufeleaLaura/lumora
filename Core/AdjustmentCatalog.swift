import Foundation

/// How a slider value is displayed.
public enum SliderValueStyle: Sendable {
    /// "+25", "-10", "0"
    case signedInteger
    /// "+1.25", "-0.50", "0.00" (exposure stops)
    case ev
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

    public func formatted(_ value: Double) -> String {
        switch style {
        case .ev:
            if abs(value) < 0.005 { return "0.00" }
            return String(format: "%+.2f", value)
        case .signedInteger:
            let rounded = Int(value.rounded())
            return rounded > 0 ? "+\(rounded)" : "\(rounded)"
        }
    }
}

/// A tab of related sliders in the editor ("Light", "Color", ...).
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
        SliderSpec(id: "whites", title: "Whites", range: -100...100, keyPath: \.light.whites),
        SliderSpec(id: "blacks", title: "Blacks", range: -100...100, keyPath: \.light.blacks),
    ])

    public static let color = ToolGroup(id: "color", title: "Color", symbol: "thermometer.medium", sliders: [
        SliderSpec(id: "temperature", title: "Temperature", range: -100...100, keyPath: \.color.temperature),
        SliderSpec(id: "tint", title: "Tint", range: -100...100, keyPath: \.color.tint),
        SliderSpec(id: "vibrance", title: "Vibrance", range: -100...100, keyPath: \.color.vibrance),
        SliderSpec(id: "saturation", title: "Saturation", range: -100...100, keyPath: \.color.saturation),
    ])

    public static let groups: [ToolGroup] = [light, color]
}
