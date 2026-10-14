import LumoraCore
import LumoraEngine
import SwiftUI

struct EditorView: View {
    @ObservedObject var session: EditorSession
    var onClose: () -> Void

    @State private var section: AdjustSection = .light
    @State private var isShowingExport = false
    @State private var isShowingHistory = false
    @Namespace private var toolNamespace

    var body: some View {
        VStack(spacing: 0) {
            topBar
            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(-1)
            dock
        }
        .background(Darkroom.canvas.ignoresSafeArea())
        // Panels are dense; very large text sizes would push the photo off screen.
        .dynamicTypeSize(...DynamicTypeSize.large)
        .overlay(alignment: .top) {
            if let toast = session.toast {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Darkroom.safelight)
                        .frame(width: 5, height: 5)
                    Text(toast)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Darkroom.cream)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .drSurface(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Darkroom.spring, value: session.toast)
        .sheet(isPresented: $isShowingExport) {
            ExportSheet(session: session)
                .presentationDetents([.medium, .large])
                .presentationBackground(Darkroom.ink)
        }
        .sheet(isPresented: $isShowingHistory) {
            HistorySheet(session: session)
                .presentationDetents([.medium, .large])
                .presentationBackground(Darkroom.ink)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 4) {
            IconButton(symbol: "chevron.left") {
                session.finish()
                onClose()
            }
            .accessibilityLabel("Back to library")

            Spacer(minLength: 0)

            barButton("arrow.uturn.backward", disabled: !session.canUndo) { session.undo() }
                .accessibilityLabel("Undo")
            barButton("arrow.uturn.forward", disabled: !session.canRedo) { session.redo() }
                .accessibilityLabel("Redo")
            barButton("square.split.2x1", active: session.compareMode == .split) {
                withAnimation(Darkroom.spring) {
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
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(Darkroom.cream)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More")

            Spacer(minLength: 0)

            Button {
                isShowingExport = true
            } label: {
                ZStack {
                    Text("Export").opacity(session.isExporting ? 0 : 1)
                    if session.isExporting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Darkroom.ink)
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
            .disabled(session.isExporting)
            .accessibilityLabel("Export")
            .accessibilityIdentifier("Export")
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 4)
        .background(Darkroom.ink.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func barButton(_ symbol: String, active: Bool = false, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(active ? Darkroom.safelight : Darkroom.cream)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.88))
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
        .animation(Darkroom.ease, value: disabled)
    }

    // MARK: - Canvas

    private var canvas: some View {
        CanvasView(renderer: session.renderer)
            .background(Darkroom.canvas)
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
                        .transition(.opacity)
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
                ShutterFlash(trigger: session.celebration)
            }
            .clipped()
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .caps(10)
            .foregroundStyle(Darkroom.cream)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Darkroom.ink.opacity(0.72), in: RoundedRectangle(cornerRadius: 2, style: .continuous))
            .padding(12)
            .allowsHitTesting(false)
    }

    // MARK: - Dock (tool panel + tool bar)

    private var dock: some View {
        VStack(spacing: 0) {
            toolPanel
            Hairline()
            toolBar
        }
        .background(Darkroom.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Hairline() }
    }

    private var toolPanel: some View {
        // Panels cross-fade in place (a ZStack, so old and new never stack up).
        ZStack(alignment: .top) {
            Group {
                switch session.activeTool {
                case .looks:
                    LooksPanel(session: session, thumbnails: session.lookThumbnails)
                        .panelPadding()
                case .adjust:
                    VStack(spacing: 0) {
                        SectionTabs(items: AdjustSection.allCases, selection: $section, title: { $0.title })
                            .padding(.horizontal, 18)
                            .padding(.top, 6)
                        Hairline()
                        if section.scrolls {
                            ScrollView {
                                panelContent
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                            }
                        } else {
                            panelContent
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
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
                    CropPanel(session: session).panelPadding(horizontal: 20)
                }
            }
            .id(session.activeTool)
            .transition(.opacity.combined(with: .offset(y: 8)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(height: 262)
        .clipped()
    }

    private var toolBar: some View {
        ScrollViewReader { proxy in
            HScroll {
                HStack(spacing: 0) {
                    ForEach(EditorTool.allCases) { tool in
                        let active = session.activeTool == tool
                        Button {
                            withAnimation(Darkroom.spring) {
                                session.activeTool = tool
                                proxy.scrollTo(tool.id, anchor: .center)
                            }
                        } label: {
                            VStack(spacing: 5) {
                                // The active tool is marked by a short safelight rule above it.
                                ZStack {
                                    if active {
                                        Rectangle()
                                            .fill(Darkroom.safelight)
                                            .frame(width: 18, height: 1.5)
                                            .matchedGeometryEffect(id: "activeTool", in: toolNamespace)
                                    }
                                }
                                .frame(height: 1.5)
                                Image(systemName: tool.symbol)
                                    .font(.system(size: 18, weight: .light))
                                    .frame(height: 24)
                                Text(tool.title)
                                    .caps(9, weight: active ? .semibold : .medium)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(active ? Darkroom.cream : Darkroom.stone)
                            .frame(width: 62)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.92))
                        .id(tool.id)
                        .accessibilityLabel(tool.title)
                        .accessibilityIdentifier("tool.\(tool.rawValue)")
                    }
                }
                .padding(.horizontal, 6)
            }
        }
        .padding(.top, 0)
        .padding(.bottom, 4)
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
                .tint(Darkroom.safelight)
                .font(.footnote.weight(.medium))
                Button {
                    session.pickingWhiteBalance.toggle()
                } label: {
                    Label(session.pickingWhiteBalance ? "Tap something white or grey on the photo" : "White balance picker", systemImage: "eyedropper")
                        .font(.footnote.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .tint(session.pickingWhiteBalance ? Darkroom.safelight : Darkroom.cream)
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
        case .effects: return "camera.filters"
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
                    .fill(Darkroom.cream)
                    .frame(width: 1)
                Circle()
                    .fill(Darkroom.ink.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(Darkroom.cream, lineWidth: 1))
                    .overlay(
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Darkroom.cream)
                    )
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
            .padding(.top, 14)
            .padding(.bottom, 10)
            .frame(maxHeight: .infinity, alignment: .top)
    }
}
