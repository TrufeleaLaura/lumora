import SwiftUI

/// Lumora's "Aura" design language: deep plum night, lavender–rose–peach light, soft glass,
/// rounded type and springy motion.
enum Aura {
    // MARK: Palette

    /// App background.
    static let plum = Color(hex: 0x140F1A)
    /// Around the photo while editing (darker and almost neutral, so colors are judged fairly).
    static let canvas = Color(hex: 0x0C090F)
    /// Panels.
    static let surface = Color(hex: 0x1C1524)
    /// Tiles, unselected chips, tracks.
    static let surfaceRaised = Color(hex: 0x2A2134)
    static let lavender = Color(hex: 0xB9A6FF)
    static let rose = Color(hex: 0xFF9EC7)
    static let peach = Color(hex: 0xFFC2A8)
    /// Text on gradient fills.
    static let ink = Color(hex: 0x1E1328)
    static let textPrimary = Color(hex: 0xF7F1FB)
    static let textSecondary = Color(hex: 0xB9ABC8)
    static let hairline = Color.white.opacity(0.09)

    // MARK: Gradients

    static let gradientColors = [lavender, rose, peach]
    static let gradient = LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
    static let diagonal = LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Thin luminous edge for glass shapes.
    static let rim = LinearGradient(
        colors: [lavender.opacity(0.75), rose.opacity(0.25), peach.opacity(0.6)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let orb = RadialGradient(
        colors: [Color.white, Color(hex: 0xEDE6FF), lavender],
        center: UnitPoint(x: 0.35, y: 0.3),
        startRadius: 1,
        endRadius: 16
    )

    // MARK: Motion

    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.74)
    static let bouncy = Animation.spring(response: 0.45, dampingFraction: 0.58)
    static let soft = Animation.easeInOut(duration: 0.35)

    /// UI tests launch with this flag; endless ambient motion would keep the app from ever idling.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-skipOnboarding")
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
