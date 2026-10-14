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
                .tint(Darkroom.safelight)
        }
    }

    /// UIKit controls SwiftUI still uses (segmented pickers, navigation titles) in the Darkroom style.
    private static func applyDarkroomAppearance() {
        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = UIColor(Darkroom.cream)
        segmented.backgroundColor = UIColor(Darkroom.raised).withAlphaComponent(0.6)
        let segmentFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(Darkroom.ink), .font: segmentFont, .kern: 0.6], for: .selected)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(Darkroom.stone), .font: segmentFont, .kern: 0.6], for: .normal)

        let navigation = UINavigationBar.appearance()
        navigation.titleTextAttributes = [
            .foregroundColor: UIColor(Darkroom.cream),
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
            .kern: 2.2,
        ]
        navigation.largeTitleTextAttributes = [
            .foregroundColor: UIColor(Darkroom.cream),
            .font: UIFont.systemFont(ofSize: 30, weight: .light),
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
