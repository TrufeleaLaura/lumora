import SwiftUI
import UIKit

@main
struct LumoraApp: App {
    init() {
        Self.applyAuraAppearance()
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .preferredColorScheme(.dark)
                .tint(Aura.lavender)
                .fontDesign(.rounded)
        }
    }

    /// UIKit controls SwiftUI still uses (segmented pickers, navigation titles) in the Aura style.
    private static func applyAuraAppearance() {
        func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
            return UIFont(descriptor: descriptor, size: size)
        }

        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = UIColor(Aura.lavender)
        segmented.backgroundColor = UIColor(Aura.surfaceRaised).withAlphaComponent(0.7)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(Aura.ink), .font: rounded(13, .semibold)], for: .selected)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(Aura.textSecondary), .font: rounded(13, .medium)], for: .normal)

        let navigation = UINavigationBar.appearance()
        navigation.titleTextAttributes = [.foregroundColor: UIColor(Aura.textPrimary), .font: rounded(17, .semibold)]
        navigation.largeTitleTextAttributes = [.foregroundColor: UIColor(Aura.textPrimary), .font: rounded(32, .bold)]
    }
}

extension Bundle {
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
