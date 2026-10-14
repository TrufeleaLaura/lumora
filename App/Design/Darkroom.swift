import SwiftUI

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

extension View {
    /// Small tracked capitals for labels, tabs and buttons.
    func caps(_ size: CGFloat = 11, weight: Font.Weight = .semibold) -> some View {
        font(.system(size: size, weight: weight))
            .tracking(size * 0.14)
            .textCase(.uppercase)
    }

    /// Monospaced film-edge code (frame numbers, values, counters).
    func filmCode(_ size: CGFloat = 10, weight: Font.Weight = .medium) -> some View {
        font(.system(size: size, weight: weight, design: .monospaced))
            .tracking(size * 0.06)
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
