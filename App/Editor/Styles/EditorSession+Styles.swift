import LumoraCore
import SwiftUI

extension EditorSession {
    /// Turns one creative effect off (back to its defaults).
    func resetStyle(_ effect: StyleCatalog.Effect) {
        perform("Reset \(effect.title)") { document in
            let defaults = CreativeSettings()
            switch effect {
            case .hdr:
                document.styles.hdr = defaults.hdr
            case .drama:
                document.styles.drama = defaults.drama
                document.styles.dramaSaturation = defaults.dramaSaturation
            case .tonal:
                document.styles.tonalHigh = defaults.tonalHigh
                document.styles.tonalMid = defaults.tonalMid
                document.styles.tonalLow = defaults.tonalLow
            case .glow:
                document.styles.glow = defaults.glow
                document.styles.glowWarmth = defaults.glowWarmth
            case .halation:
                document.styles.halation = defaults.halation
            case .vintage:
                document.styles.vintage = defaults.vintage
            case .noir:
                document.styles.noir = defaults.noir
            case .grunge:
                document.styles.grunge = defaults.grunge
                document.styles.grungeStyle = defaults.grungeStyle
            case .rgbSplit:
                document.styles.rgbSplit = defaults.rgbSplit
            case .lensBlur:
                document.styles.lensBlur = defaults.lensBlur
            }
        }
    }
}
