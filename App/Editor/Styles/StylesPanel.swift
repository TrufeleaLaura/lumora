import LumoraCore
import SwiftUI

/// Snapseed-style creative effects: pick an effect, adjust its sliders.
struct StylesPanel: View {
    @ObservedObject var session: EditorSession
    @ObservedObject var thumbnails: LookThumbnails
    @State private var effect: StyleCatalog.Effect = .hdr

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HScroll {
                HStack(spacing: 8) {
                    ForEach(StyleCatalog.Effect.allCases) { item in
                        let active = item.isActive(session.document.styles)
                        Button {
                            effect = item
                            session.focusEditing = item == .lensBlur
                        } label: {
                            let selected = effect == item
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack(alignment: .topTrailing) {
                                    thumbnail(item)
                                        .frame(width: 62, height: 62)
                                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                .stroke(Darkroom.cream, lineWidth: 1.5)
                                                .padding(-3)
                                                .opacity(selected ? 1 : 0)
                                        )
                                    // In use: a small safelight mark in the corner.
                                    if active {
                                        Rectangle()
                                            .fill(Darkroom.safelight)
                                            .frame(width: 6, height: 6)
                                            .padding(4)
                                            .transition(.opacity)
                                    }
                                }
                                .animation(Darkroom.ease, value: selected)
                                .animation(Darkroom.ease, value: active)
                                Text(item.title)
                                    .caps(9, weight: selected ? .semibold : .medium)
                                    .lineLimit(1)
                                    .foregroundStyle(selected ? Darkroom.cream : Darkroom.stone)
                            }
                            .frame(width: 68)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if effect == .lensBlur {
                        Picker("Focus", selection: Binding(
                            get: { session.document.styles.lensBlur.mode },
                            set: { mode in session.perform("Focus \(mode.title)") { $0.styles.lensBlur.mode = mode } }
                        )) {
                            ForEach(FocusMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(focusHint)
                            .font(.footnote)
                            .foregroundStyle(Darkroom.stone)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    SliderList(session: session, specs: specs)
                    if effect.isActive(session.document.styles) {
                        Button {
                            session.resetStyle(effect)
                        } label: {
                            Label("Reset \(effect.title)", systemImage: "arrow.counterclockwise")
                                .font(.footnote)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .onAppear { session.focusEditing = effect == .lensBlur }
        .onDisappear { session.focusEditing = false }
    }

    /// A preview of the effect on this photo.
    @ViewBuilder
    private func thumbnail(_ item: StyleCatalog.Effect) -> some View {
        var preview = EditDocument()
        let _ = Self.configure(item, &preview.styles)
        if let image = thumbnails.image(for: "style.\(item.rawValue)", document: preview) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Darkroom.raised
                .overlay(Image(systemName: item.symbol).foregroundStyle(Darkroom.stone))
        }
    }

    /// Typical settings used for the preview tiles.
    static func configure(_ item: StyleCatalog.Effect, _ styles: inout CreativeSettings) {
        switch item {
        case .hdr: styles.hdr = 75
        case .drama: styles.drama = 65
        case .tonal: styles.tonalHigh = 60; styles.tonalMid = 60; styles.tonalLow = 60
        case .glow: styles.glow = 75
        case .halation: styles.halation = 80
        case .vintage: styles.vintage = 75
        case .noir: styles.noir = 75
        case .grunge: styles.grunge = 65
        case .rgbSplit: styles.rgbSplit = 80
        case .lensBlur: styles.lensBlur.amount = 85
        }
    }

    private var specs: [SliderSpec] {
        let all = StyleCatalog.sliders(effect)
        guard effect == .lensBlur else { return all }
        let mode = session.document.styles.lensBlur.mode
        return all.filter { spec in
            switch spec.id {
            case "styles.lensBlur.angle", "styles.lensBlur.miniature": return mode == .band
            case "styles.lensBlur.size": return mode != .subject
            default: return true
            }
        }
    }

    private var focusHint: String {
        switch session.document.styles.lensBlur.mode {
        case .subject: return "Keeps the main subject sharp and blurs the background like a fast lens."
        case .radial: return "Drag the focus point on the photo."
        case .band: return "Drag the band on the photo. Add Miniature for a toy-model look."
        }
    }
}

/// Lens blur focus handle (radial center or tilt-shift band).
struct FocusOverlay: View {
    @ObservedObject var renderer: CanvasRenderer
    @ObservedObject var session: EditorSession
    @State private var dragStart: SIMD2<Double>?

    var body: some View {
        let frame = renderer.imageFrame
        let blur = session.document.styles.lensBlur
        ZStack(alignment: .topLeading) {
            if session.focusEditing, blur.amount > 0, blur.mode != .subject, frame.width > 0 {
                let center = CGPoint(x: frame.minX + CGFloat(blur.center.x) * frame.width, y: frame.minY + CGFloat(1 - blur.center.y) * frame.height)
                if blur.mode == .radial {
                    let radius = CGFloat(blur.size) * frame.width
                    Circle()
                        .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .frame(width: radius * 2, height: radius * 2)
                        .position(center)
                        .allowsHitTesting(false)
                } else {
                    bandLines(center: center, blur: blur, frame: frame)
                        .allowsHitTesting(false)
                }
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .position(center)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStart == nil {
                                    dragStart = blur.center
                                    session.beginChange()
                                }
                                guard let start = dragStart else { return }
                                let dx = Double(value.translation.width / frame.width)
                                let dy = Double(-value.translation.height / frame.height)
                                session.document.styles.lensBlur.center = SIMD2(min(max(start.x + dx, 0), 1), min(max(start.y + dy, 0), 1))
                            }
                            .onEnded { _ in
                                dragStart = nil
                                session.endChange(label: "Move focus")
                            }
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bandLines(center: CGPoint, blur: LensBlurSettings, frame: CGRect) -> some View {
        let radians = CGFloat(blur.angle) * .pi / 180
        // Band direction on screen (y down) and its normal.
        let along = CGPoint(x: cos(radians), y: -sin(radians))
        let normal = CGPoint(x: -along.y, y: along.x)
        let half = CGFloat(blur.size) * frame.width * 0.5
        let reach = max(frame.width, frame.height) * 2
        func line(_ offset: CGFloat) -> Path {
            Path { path in
                let base = CGPoint(x: center.x + normal.x * offset, y: center.y + normal.y * offset)
                path.move(to: CGPoint(x: base.x - along.x * reach, y: base.y - along.y * reach))
                path.addLine(to: CGPoint(x: base.x + along.x * reach, y: base.y + along.y * reach))
            }
        }
        return ZStack {
            line(half).stroke(Color.white.opacity(0.85), lineWidth: 1.5)
            line(-half).stroke(Color.white.opacity(0.85), lineWidth: 1.5)
        }
        .shadow(color: .black.opacity(0.5), radius: 1)
    }
}
