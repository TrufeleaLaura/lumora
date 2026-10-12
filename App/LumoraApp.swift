import SwiftUI

@main
struct LumoraApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

extension Bundle {
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
