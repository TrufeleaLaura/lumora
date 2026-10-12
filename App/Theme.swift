import SwiftUI

enum Theme {
    static let background = Color(red: 0.055, green: 0.051, blue: 0.063)
    static let panel = Color(red: 0.094, green: 0.090, blue: 0.106)
    static let panelRaised = Color(red: 0.137, green: 0.129, blue: 0.153)
    /// Warm gold.
    static let accent = Color(red: 0.965, green: 0.757, blue: 0.467)
    /// Rose.
    static let accentSecondary = Color(red: 0.922, green: 0.435, blue: 0.573)

    static let gradient = LinearGradient(
        colors: [accent, accentSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
