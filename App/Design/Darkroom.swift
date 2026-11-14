import CoreText
import SwiftUI
import UIKit

/// Lumora's "Darkroom" design language: warm black like a darkroom, cream type like photo paper,
/// one safelight-orange accent used sparingly, film details (edge codes, frame numbers,
/// sprockets), fine hairlines, and quick, precise motion without bounce.
enum Darkroom {
    // MARK: Palette

    /// App background, and type on cream fills.
    static let ink = Color(hex: 0x0E0D0C)
    /// Around the photo while editing (near-black and neutral, so colors are judged fairly).
    static let canvas = Color(hex: 0x080707)
    /// Panels.
    static let surface = Color(hex: 0x161412)
    /// Tiles and resting controls.
    static let raised = Color(hex: 0x201D1A)
    /// Contact-sheet film base.
    static let film = Color(hex: 0x1B1917)
    /// Primary type and selection.
    static let cream = Color(hex: 0xEDE6DA)
    /// Secondary type.
    static let stone = Color(hex: 0x958B80)
    /// Tick marks and tertiary details.
    static let muted = Color(hex: 0x5C554E)
    /// Hairlines.
    static let line = Color(hex: 0xEDE6DA, opacity: 0.13)
    /// The single accent: a darkroom safelight.
    static let safelight = Color(hex: 0xE0603A)

    // MARK: Motion

    /// Quick and settled (no overshoot).
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.92)
    static let ease = Animation.easeOut(duration: 0.2)

    /// UI tests launch with this flag; endless ambient motion would keep the app from ever idling.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-skipOnboarding")

    // MARK: Film codes

    /// Frame numbers as printed on film edges: 01, 01A, 02, 02A…
    static func frameCode(_ index: Int) -> String {
        let number = index / 2 + 1
        return String(format: "%02d", number) + (index % 2 == 1 ? "A" : "")
    }
}

/// Lumora's type: Cormorant Garamond for titles and tabs, Jost for text and labels, DM Mono for
/// film codes and values. The two variable fonts are set to exact weights through their `wght` axis.
enum Typeface {
    private static let weightAxis = 0x7767_6874 // 'wght'
    private static var cache: [String: UIFont] = [:]

    /// Titles, tabs and other display text.
    static func cormorant(_ size: CGFloat, weight: CGFloat = 500, italic: Bool = false) -> Font {
        Font(uiCormorant(size, weight: weight, italic: italic) as CTFont)
    }

    /// Running text, rows and labels.
    static func jost(_ size: CGFloat, weight: CGFloat = 400) -> Font {
        Font(uiJost(size, weight: weight) as CTFont)
    }

    /// Film codes, frame numbers and slider values.
    static func mono(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? "DMMono-Medium" : "DMMono-Regular", fixedSize: size)
    }

    static func uiCormorant(_ size: CGFloat, weight: CGFloat = 500, italic: Bool = false) -> UIFont {
        variable(italic ? "CormorantGaramond-LightItalic" : "CormorantGaramond-Light", size: size, weight: weight)
    }

    static func uiJost(_ size: CGFloat, weight: CGFloat = 400) -> UIFont {
        variable("Jost-Regular", size: size, weight: weight)
    }

    /// Jost weights that match SwiftUI's named weights.
    static func jostWeight(_ weight: Font.Weight) -> CGFloat {
        switch weight {
        case .ultraLight: return 200
        case .thin: return 250
        case .light: return 300
        case .medium: return 500
        case .semibold: return 560
        case .bold: return 640
        case .heavy, .black: return 720
        default: return 400
        }
    }

    private static func variable(_ name: String, size: CGFloat, weight: CGFloat) -> UIFont {
        let key = "\(name)-\(size)-\(weight)"
        if let font = cache[key] { return font }
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: name,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [
                NSNumber(value: weightAxis): NSNumber(value: Double(weight)),
            ],
        ])
        let font = UIFont(descriptor: descriptor, size: size)
        cache[key] = font
        return font
    }
}

extension View {
    /// Small tracked capitals for labels, tabs and buttons.
    func caps(_ size: CGFloat = 11, weight: Font.Weight = .medium) -> some View {
        font(Typeface.jost(size, weight: Typeface.jostWeight(weight)))
            .tracking(size * 0.2)
            .textCase(.uppercase)
    }

    /// Monospaced film-edge code (frame numbers, values, counters).
    func filmCode(_ size: CGFloat = 10, weight: Font.Weight = .regular) -> some View {
        font(Typeface.mono(size, medium: weight != .regular))
            .tracking(size * 0.04)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
