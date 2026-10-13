import Foundation

/// What happens behind the main subject.
public enum BackgroundMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case keep, color, transparent

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .keep: return "Keep"
        case .color: return "Color"
        case .transparent: return "Remove"
        }
    }
}

public struct BackgroundSettings: Codable, Equatable, Sendable {
    public var mode: BackgroundMode = .keep
    public var color: RGBColor = .white

    public init() {}

    public var isIdentity: Bool { mode == .keep }
}

/// Generated skies for sky replacement.
public enum SkyStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case none, clear, sunset, golden, dramatic, pastel, night

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: return "Original"
        case .clear: return "Clear"
        case .sunset: return "Sunset"
        case .golden: return "Golden"
        case .dramatic: return "Dramatic"
        case .pastel: return "Pastel"
        case .night: return "Starry"
        }
    }

    /// Zenith and horizon colors (sRGB), cloud cover (0...1) and cloud brightness.
    public var palette: (zenith: RGBColor, horizon: RGBColor, clouds: Double, cloudLight: RGBColor, cloudShade: RGBColor) {
        switch self {
        case .none, .clear:
            return (RGBColor(0.16, 0.4, 0.84), RGBColor(0.7, 0.83, 0.96), 0.22, RGBColor(1, 1, 1), RGBColor(0.72, 0.78, 0.88))
        case .sunset:
            return (RGBColor(0.24, 0.2, 0.46), RGBColor(1.0, 0.52, 0.24), 0.42, RGBColor(1.0, 0.62, 0.5), RGBColor(0.42, 0.24, 0.4))
        case .golden:
            return (RGBColor(0.42, 0.58, 0.85), RGBColor(1.0, 0.8, 0.5), 0.3, RGBColor(1.0, 0.93, 0.8), RGBColor(0.75, 0.62, 0.55))
        case .dramatic:
            return (RGBColor(0.13, 0.17, 0.26), RGBColor(0.55, 0.6, 0.66), 0.68, RGBColor(0.85, 0.87, 0.9), RGBColor(0.2, 0.22, 0.27))
        case .pastel:
            return (RGBColor(0.6, 0.68, 0.95), RGBColor(1.0, 0.8, 0.84), 0.35, RGBColor(1.0, 0.95, 0.97), RGBColor(0.82, 0.76, 0.88))
        case .night:
            return (RGBColor(0.01, 0.02, 0.06), RGBColor(0.08, 0.1, 0.22), 0.0, RGBColor(0.3, 0.32, 0.4), RGBColor(0.05, 0.05, 0.1))
        }
    }
}

public struct SkySettings: Codable, Equatable, Sendable {
    public var style: SkyStyle = .none
    /// 0...100, how much of the new sky shows.
    public var amount: Double = 100
    /// 0...100, how much the landscape takes on the new sky's light.
    public var relight: Double = 50
    /// Cloud layout variation.
    public var seed: Double = 0

    public init() {}

    public var isIdentity: Bool { style == .none || amount <= 0 }
}
