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
            celebrate()
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

/// One-tap enhance, sky replacement and background tools. The Auto, Sky and Background tools
/// each open one part.
struct EnhancePanel: View {
    @ObservedObject var session: EditorSession
    var part: Part = .all

    enum Part { case all, auto, sky, background }

    var body: some View {
        if let busy = session.preparingMask {
            DevelopingIndicator(caption: busy)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if part == .all || part == .auto {
                        ActionGroup {
                            ActionRow(title: "Auto enhance", detail: "Balances light and color", action: "Apply") {
                                session.autoEnhance(lowLight: false)
                            }
                            ActionRow(title: "Low light", detail: "Brightens and removes noise", action: "Apply") {
                                session.autoEnhance(lowLight: true)
                            }
                        }
                        Text("Tip: Export, then Enlarge 2\u{00D7}, makes a bigger file for prints.")
                            .font(Typeface.jost(12))
                            .foregroundStyle(Darkroom.stone)
                    }
                    if part == .all || part == .sky {
                        if part == .all { heading("Sky") }
                        sky
                    }
                    if part == .all || part == .background {
                        if part == .all { heading("Background") }
                        background
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .caps(10)
            .foregroundStyle(Darkroom.stone)
    }

    private var sky: some View {
        VStack(alignment: .leading, spacing: 12) {
            HScroll {
                HStack(spacing: 6) {
                    ForEach(SkyStyle.allCases) { style in
                        let selected = session.document.sky.style == style
                        Button {
                            session.setSkyStyle(style)
                        } label: {
                            Text(style.title)
                                .font(Typeface.jost(13, weight: 500))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .drChip(selected, shape: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        .buttonStyle(PressStyle())
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
        }
    }

    private var background: some View {
        VStack(alignment: .leading, spacing: 12) {
            ActionGroup {
                ActionRow(title: "Blur the background", detail: "Like a portrait lens", action: "Apply") {
                    session.perform("Blur background") { document in
                        document.styles.lensBlur.mode = .subject
                        document.styles.lensBlur.amount = max(document.styles.lensBlur.amount, 60)
                    }
                }
            }
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
                    .font(Typeface.jost(12))
                    .foregroundStyle(Darkroom.stone)
            }
        }
    }
}
