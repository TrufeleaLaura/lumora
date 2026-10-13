import LumoraCore
import LumoraEngine
import SwiftUI

extension EditorSession {
    /// One-tap enhancement (optionally tuned for dark, noisy photos), as ordinary edits.
    func autoEnhance(lowLight: Bool) {
        let proxy = self.proxy
        let analysis = self.analysis
        preparingMask = lowLight ? "Brightening…" : "Enhancing…"
        Task {
            let proposal = await Task.detached(priority: .userInitiated) { () -> AutoEnhance.Proposal in
                // Portraits are exposed for the largest face.
                let face = analysis.faces.max { $0.landmarks.bounds.width < $1.landmarks.bounds.width }
                return AutoEnhance.propose(for: proxy, faceLightness: face.map { Double($0.skinTone.x) })
            }.value
            preparingMask = nil
            perform(lowLight ? "Low light" : "Auto enhance") { document in
                proposal.apply(to: &document)
                if lowLight {
                    document.light.exposure = min(document.light.exposure + 0.4, 2.5)
                    document.light.shadows = max(document.light.shadows, 45)
                    document.light.highlights = min(document.light.highlights, -20)
                    document.detail.noiseReduction = max(document.detail.noiseReduction, 45)
                    document.detail.colorNoiseReduction = max(document.detail.colorNoiseReduction, 60)
                }
            }
        }
    }

    func setSkyStyle(_ style: SkyStyle) {
        guard style != .none else {
            perform("Original sky") { $0.sky.style = .none }
            return
        }
        let analysis = self.analysis
        preparingMask = "Finding the sky…"
        Task {
            let found = await Task.detached(priority: .userInitiated) { analysis.skyRegion != nil }.value
            preparingMask = nil
            guard found else {
                showToast("No sky found in this photo")
                return
            }
            perform("Sky \(style.title)") { $0.sky.style = style }
        }
    }

    func setBackgroundMode(_ mode: BackgroundMode) {
        guard mode != .keep else {
            perform("Keep background") { $0.background.mode = .keep }
            return
        }
        let analysis = self.analysis
        preparingMask = "Finding the subject…"
        Task {
            let found = await Task.detached(priority: .userInitiated) { analysis.subjectMask != nil }.value
            preparingMask = nil
            guard found else {
                showToast("No subject found")
                return
            }
            perform(mode == .transparent ? "Remove background" : "Background color") { $0.background.mode = mode }
            if mode == .transparent {
                showToast("Export as PNG to keep the transparency")
            }
        }
    }
}

/// One-tap enhance, sky replacement and background tools.
struct EnhancePanel: View {
    @ObservedObject var session: EditorSession

    var body: some View {
        if let busy = session.preparingMask {
            ProgressView(busy)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        bigButton("Auto enhance", symbol: "sparkles") { session.autoEnhance(lowLight: false) }
                        bigButton("Low light", symbol: "moon.stars") { session.autoEnhance(lowLight: true) }
                        bigButton("Blur background", symbol: "camera.aperture") {
                            session.perform("Blur background") { document in
                                document.styles.lensBlur.mode = .subject
                                document.styles.lensBlur.amount = max(document.styles.lensBlur.amount, 60)
                            }
                        }
                    }

                    Text("Sky")
                        .font(.subheadline.weight(.semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(SkyStyle.allCases) { style in
                                let selected = session.document.sky.style == style
                                Button {
                                    session.setSkyStyle(style)
                                } label: {
                                    Text(style.title)
                                        .font(.footnote.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .foregroundStyle(selected ? Color.black : Color.primary)
                                        .background(selected ? Theme.accent : Theme.panelRaised, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if session.document.sky.style != .none {
                        SliderList(session: session, specs: [
                            SliderSpec(id: "sky.amount", title: "Amount", range: 0...100, defaultValue: 100, style: .integer, keyPath: \EditDocument.sky.amount),
                            SliderSpec(id: "sky.relight", title: "Relight", range: 0...100, defaultValue: 50, style: .integer, keyPath: \EditDocument.sky.relight),
                            SliderSpec(id: "sky.seed", title: "Clouds", range: 0...9, style: .integer, keyPath: \EditDocument.sky.seed),
                        ])
                    }

                    Text("Background")
                        .font(.subheadline.weight(.semibold))
                    Picker("Background", selection: Binding(
                        get: { session.document.background.mode },
                        set: { session.setBackgroundMode($0) }
                    )) {
                        ForEach(BackgroundMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    if session.document.background.mode == .color {
                        ColorRow(selected: session.document.background.color) { color in
                            session.perform("Background color") { $0.background.color = color }
                        }
                    } else if session.document.background.mode == .transparent {
                        Text("The background is cut out. Export as PNG to keep it transparent.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Tip: Export, then Enlarge 2×, makes a bigger file for prints.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func bigButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
