import LumoraCore
import SwiftUI

/// HSL color mixer (or the B&W luminance mix when black & white is on).
struct MixerPanel: View {
    @ObservedObject var session: EditorSession
    @State private var channel: AdjustmentCatalog.MixerChannel = .hue

    private var swatches: [String: Color] {
        var result: [String: Color] = [:]
        let specs = session.document.blackWhite.isEnabled ? AdjustmentCatalog.blackWhiteSliders : AdjustmentCatalog.mixerSliders(channel)
        for (spec, band) in zip(specs, HueBand.allCases) {
            let c = band.swatch
            result[spec.id] = Color(red: c.red, green: c.green, blue: c.blue)
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.document.blackWhite.isEnabled {
                Text("Black & white mix")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Aura.textSecondary)
                SliderList(session: session, specs: AdjustmentCatalog.blackWhiteSliders, swatches: swatches)
            } else {
                Picker("Channel", selection: $channel) {
                    ForEach(AdjustmentCatalog.MixerChannel.allCases) { channel in
                        Text(channel.title).tag(channel)
                    }
                }
                .pickerStyle(.segmented)
                SliderList(session: session, specs: AdjustmentCatalog.mixerSliders(channel), swatches: swatches)
            }
        }
    }
}
