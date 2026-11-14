import SwiftUI
import UIKit

@main
struct LumoraApp: App {
    init() {
        Self.applyDarkroomAppearance()
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .preferredColorScheme(.dark)
                .tint(Darkroom.cream)
                .font(Typeface.jost(15))
        }
    }

    /// UIKit controls SwiftUI still uses (segmented pickers, navigation titles) in the Darkroom style.
    private static func applyDarkroomAppearance() {
        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = UIColor(Darkroom.cream)
        segmented.backgroundColor = UIColor(Darkroom.raised).withAlphaComponent(0.6)
        let segmentFont = Typeface.uiJost(13, weight: 500)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(Darkroom.ink), .font: segmentFont, .kern: 0.4], for: .selected)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(Darkroom.stone), .font: segmentFont, .kern: 0.4], for: .normal)

        let navigation = UINavigationBar.appearance()
        navigation.titleTextAttributes = [
            .foregroundColor: UIColor(Darkroom.cream),
            .font: Typeface.uiJost(13, weight: 500),
            .kern: 2.6,
        ]
        navigation.largeTitleTextAttributes = [
            .foregroundColor: UIColor(Darkroom.cream),
            .font: Typeface.uiCormorant(34, weight: 500),
        ]
    }
}

extension Bundle {
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
