import LumoraCore
import LumoraEngine
import SwiftUI

struct EditorView: View {
    @ObservedObject var session: EditorSession
    var onClose: () -> Void

    @State private var section: AdjustSection = .light
    @State private var isShowingExport = false
    @State private var isShowingHistory = false
    /// Per-tool tap counters (each tap bounces only that tool's symbol).
    @State private var toolTaps: [EditorTool: Int] = [:]
    @Namespace private var toolNamespace

    var body: some View {
        VStack(spacing: 0) {
            topBar
            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(-1)
            dock
        }
        .background(Aura.canvas.ignoresSafeArea())
        // Panels are dense; very large text sizes would push the photo off screen.
        .dynamicTypeSize(...DynamicTypeSize.large)
        .overlay(alignment: .top) {
            if let toast = session.toast {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Aura.gradient)
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Aura.textPrimary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .auraGlass(Capsule(), tint: 0.5)
                .shadow(color: Aura.lavender.opacity(0.25), radius: 14)
                .padding(.top, 64)
                .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(Aura.bouncy, value: session.toast)
        .sheet(isPresented: $isShowingExport) {
            ExportSheet(session: session)
                .presentationDetents([.medium, .large])
                .presentationBackground(Aura.plum)
                .presentationCornerRadius(30)
        }
        .sheet(isPresented: $isShowingHistory) {
            HistorySheet(session: session)
                .presentationDetents([.medium, .large])
                .presentationBackground(Aura.plum)
                .presentationCornerRadius(30)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            AuraIconButton(symbol: "chevron.left") {
                session.finish()
                onClose()
            }
            .accessibilityLabel("Back to library")

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                barButton("arrow.uturn.backward", disabled: !session.canUndo) { session.undo() }
                    .accessibilityLabel("Undo")
                barButton("arrow.uturn.forward", disabled: !session.canRedo) { session.redo() }
                    .accessibilityLabel("Redo")
                barButton("square.split.2x1", active: session.compareMode == .split) {
                    withAnimation(Aura.spring) {
                        session.compareMode = session.compareMode == .split ? .none : .split
                    }
                }
                .accessibilityLabel("Before and after split view")

                Menu {
                    Button {
                        isShowingHistory = true
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                    Button {
                        session.copyEdits()
                    } label: {
                        Label("Copy edits", systemImage: "doc.on.doc")
                    }
                    Button {
                        session.pasteEdits()
                    } label: {
                        Label("Paste edits", systemImage: "doc.on.clipboard")
                    }
                    .disabled(!session.canPasteEdits)
                    Divider()
                    Button(role: .destructive) {
                        session.resetAll()
                    } label: {
                        Label("Reset all", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Aura.textPrimary)
                        .frame(width: 38, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More")
            }
            .padding(.horizontal, 4)
            .auraGlass(Capsule(), tint: 0.4, rim: 0.55)

            Spacer(minLength: 0)

            Button {
                isShowingExport = true
            } label: {
                ZStack {
                    Text("Export").opacity(session.isExporting ? 0 : 1)
                    if session.isExporting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Aura.ink)
                    }
                }
            }
            .buttonStyle(AuraPrimaryButtonStyle(compact: true))
            .disabled(session.isExporting)
            .accessibilityLabel("Export")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func barButton(_ symbol: String, active: Bool = false, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? AnyShapeStyle(Aura.gradient) : AnyShapeStyle(Aura.textPrimary))
                .frame(width: 38, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(AuraPressStyle(scale: 0.85))
        .disabled(disabled)
        .opacity(disabled ? 0.32 : 1)
        .animation(Aura.soft, value: disabled)
    }

    // MARK: - Canvas

    private var canvas: some View {
        CanvasView(renderer: session.renderer)
            .background(Aura.canvas)
            .overlay {
                if session.activeTool == .crop {
                    CropOverlay(renderer: session.renderer, session: session)
                } else if session.activeTool == .face && session.compareMode == .none {
                    FaceMarkersOverlay(renderer: session.renderer, session: session)
                } else if session.activeTool == .body && session.compareMode == .none {
                    BodyMarkersOverlay(renderer: session.renderer, session: session)
                } else if session.activeTool == .masks && session.compareMode == .none {
                    MaskCanvasOverlay(renderer: session.renderer, session: session)
                } else if session.activeTool == .retouch && session.compareMode == .none {
                    RetouchCanvasOverlay(renderer: session.renderer, session: session)
                } else if session.activeTool == .styles && session.compareMode == .none {
                    FocusOverlay(renderer: session.renderer, session: session)
                } else if session.activeTool == .text && session.compareMode == .none {
                    TextCanvasOverlay(renderer: session.renderer, session: session)
                } else if session.activeTool == .reshape && session.compareMode == .none {
                    ReshapeCanvasOverlay(renderer: session.renderer, session: session)
                } else if session.compareMode == .split {
                    SplitDivider(position: $session.splitPosition)
                }
            }
            .overlay(alignment: .topTrailing) {
                if session.activeTool == .adjust && session.compareMode == .none {
                    HistogramView(session: session)
                        .padding(10)
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .topTrailing)))
                }
            }
            .overlay(alignment: .topLeading) {
                if session.compareMode == .holding {
                    badge("Original")
                } else if session.compareMode == .split {
                    HStack {
                        badge("Before")
                        Spacer()
                        badge("After")
                    }
                }
            }
            .overlay {
                SparkleBurst(trigger: session.celebration)
            }
            .clipped()
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Aura.textPrimary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .auraGlass(Capsule(), tint: 0.45, rim: 0.6)
            .padding(12)
            .allowsHitTesting(false)
    }

    // MARK: - Dock (tool panel + tool bar)

    private var dock: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
        return VStack(spacing: 0) {
            toolPanel
            toolBar
        }
        .background {
            ZStack(alignment: .top) {
                shape.fill(Aura.surface)
                // A soft wash of aura light along the top edge.
                shape.fill(
                    LinearGradient(
                        colors: [Aura.lavender.opacity(0.10), Aura.rose.opacity(0.03), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                shape.stroke(Aura.rim, lineWidth: 0.8)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.12)))
            }
            .ignoresSafeArea(edges: .bottom)
            .shadow(color: .black.opacity(0.45), radius: 18, y: -4)
        }
    }

    private var toolPanel: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Aura.textSecondary.opacity(0.25))
                .frame(width: 34, height: 4)
                .padding(.top, 7)
            // Panels cross-fade in place (a ZStack, so old and new never stack up).
            ZStack(alignment: .top) {
                Group {
                    switch session.activeTool {
                    case .looks:
                        LooksPanel(session: session, thumbnails: session.lookThumbnails)
                            .panelPadding()
                    case .adjust:
                        VStack(spacing: 0) {
                            AuraChipBar(items: AdjustSection.allCases, selection: $section, title: { $0.title }, symbol: { $0.symbol })
                                .padding(.horizontal, 12)
                                .padding(.top, 2)
                            if section.scrolls {
                                ScrollView {
                                    panelContent
                                        .padding(.horizontal, 22)
                                        .padding(.vertical, 10)
                                }
                            } else {
                                panelContent
                                    .padding(.horizontal, 22)
                                    .padding(.vertical, 10)
                                    .frame(maxHeight: .infinity, alignment: .top)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    case .masks:
                        MasksPanel(session: session).panelPadding()
                    case .retouch:
                        RetouchPanel(session: session).panelPadding()
                    case .styles:
                        StylesPanel(session: session, thumbnails: session.lookThumbnails).panelPadding()
                    case .enhance:
                        EnhancePanel(session: session).panelPadding()
                    case .overlays:
                        OverlaysPanel(session: session).panelPadding()
                    case .text:
                        TextPanel(session: session).panelPadding()
                    case .face:
                        FacePanel(session: session).panelPadding()
                    case .body:
                        BodyPanel(session: session).panelPadding()
                    case .reshape:
                        ReshapePanel(session: session).panelPadding()
                    case .crop:
                        CropPanel(session: session).panelPadding(horizontal: 22)
                    }
                }
                .id(session.activeTool)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 18)).combined(with: .scale(scale: 0.98, anchor: .top)),
                        removal: .opacity
                    )
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 258)
        .clipped()
    }

    private var toolBar: some View {
        ScrollViewReader { proxy in
            AuraHScroll {
                HStack(spacing: 0) {
                    ForEach(EditorTool.allCases) { tool in
                        let active = session.activeTool == tool
                        Button {
                            toolTaps[tool, default: 0] += 1
                            withAnimation(Aura.spring) {
                                session.activeTool = tool
                                proxy.scrollTo(tool.id, anchor: .center)
                            }
                        } label: {
                            VStack(spacing: 3) {
                                ZStack {
                                    if active {
                                        Circle()
                                            .fill(Aura.diagonal)
                                            .shadow(color: Aura.lavender.opacity(0.65), radius: 9)
                                            .shadow(color: Aura.rose.opacity(0.3), radius: 16, y: 4)
                                            .matchedGeometryEffect(id: "activeTool", in: toolNamespace)
                                    }
                                    Image(systemName: tool.symbol)
                                        .font(.system(size: 15, weight: active ? .semibold : .regular))
                                        .foregroundStyle(active ? Aura.ink : Aura.textSecondary)
                                        .symbolEffect(.bounce, value: toolTaps[tool, default: 0])
                                }
                                .frame(width: 34, height: 34)
                                Text(tool.title)
                                    .font(.system(size: 10, weight: active ? .semibold : .medium))
                                    .foregroundStyle(active ? Aura.textPrimary : Aura.textSecondary.opacity(0.85))
                                    .lineLimit(1)
                            }
                            .frame(width: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(AuraPressStyle(scale: 0.88))
                        .id(tool.id)
                        .accessibilityLabel(tool.title)
                        .accessibilityIdentifier("tool.\(tool.rawValue)")
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var panelContent: some View {
        switch section {
        case .light:
            SliderList(session: session, specs: AdjustmentCatalog.light.sliders)
        case .color:
            VStack(spacing: 14) {
                Toggle("Black & white", isOn: Binding(
                    get: { session.document.blackWhite.isEnabled },
                    set: { enabled in
                        session.perform(enabled ? "Black & white" : "Color") { $0.blackWhite.isEnabled = enabled }
                    }
                ))
                .tint(Aura.lavender)
                .font(.footnote.weight(.medium))
                Button {
                    session.pickingWhiteBalance.toggle()
                } label: {
                    Label(session.pickingWhiteBalance ? "Tap something white or grey on the photo" : "White balance picker", systemImage: "eyedropper")
                        .font(.footnote.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .tint(session.pickingWhiteBalance ? Aura.lavender : Aura.textPrimary)
                SliderList(session: session, specs: AdjustmentCatalog.color.sliders)
            }
        case .mixer:
            MixerPanel(session: session)
        case .grading:
            GradingPanel(session: session)
        case .curve:
            CurvePanel(session: session)
        case .effects:
            SliderList(session: session, specs: AdjustmentCatalog.effects.sliders)
        case .detail:
            SliderList(session: session, specs: AdjustmentCatalog.detail.sliders)
        case .optics:
            SliderList(session: session, specs: AdjustmentCatalog.optics.sliders)
        }
    }
}

/// Sections of the Adjust tool.
enum AdjustSection: String, CaseIterable, Identifiable {
    case light, color, mixer, grading, curve, effects, detail, optics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .color: return "Color"
        case .mixer: return "Mixer"
        case .grading: return "Grading"
        case .curve: return "Curve"
        case .effects: return "Effects"
        case .detail: return "Detail"
        case .optics: return "Optics"
        }
    }

    var symbol: String {
        switch self {
        case .light: return "sun.max"
        case .color: return "thermometer.medium"
        case .mixer: return "paintpalette"
        case .grading: return "circle.lefthalf.filled"
        case .curve: return "point.topleft.down.to.point.bottomright.curvepath"
        case .effects: return "sparkles"
        case .detail: return "triangle"
        case .optics: return "camera.aperture"
        }
    }

    /// Panels with 2-D drag controls don't scroll (so drags aren't stolen by scrolling).
    var scrolls: Bool {
        self != .curve && self != .grading
    }
}

/// Draggable vertical divider for the before/after split view.
struct SplitDivider: View {
    @Binding var position: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let x = proxy.size.width * position
            ZStack {
                Rectangle()
                    .fill(LinearGradient(colors: Aura.gradientColors, startPoint: .top, endPoint: .bottom))
                    .frame(width: 2)
                    .shadow(color: Aura.lavender.opacity(0.6), radius: 4)
                Circle()
                    .fill(Aura.orb)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Aura.ink)
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                    .shadow(color: Aura.lavender.opacity(0.7), radius: 10)
            }
            .frame(width: 44)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .position(x: x, y: proxy.size.height / 2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        position = min(max(value.location.x / proxy.size.width, 0.02), 0.98)
                    }
            )
        }
    }
}

private extension View {
    /// Standard inset for a tool's panel.
    func panelPadding(horizontal: CGFloat = 18) -> some View {
        padding(.horizontal, horizontal)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .frame(maxHeight: .infinity, alignment: .top)
    }
}
