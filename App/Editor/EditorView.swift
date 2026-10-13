import LumoraCore
import LumoraEngine
import SwiftUI

struct EditorView: View {
    @ObservedObject var session: EditorSession
    var onClose: () -> Void

    @State private var section: AdjustSection = .light
    @State private var isShowingExport = false
    @State private var isShowingHistory = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            canvas
            toolPanel
            toolBar
        }
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            if let toast = session.toast {
                Text(toast)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 64)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.toast)
        .sheet(isPresented: $isShowingExport) {
            ExportSheet(session: session)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isShowingHistory) {
            HistorySheet(session: session)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 18) {
            Button {
                session.finish()
                onClose()
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Back to library")

            Spacer()

            Button { session.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!session.canUndo)
            .accessibilityLabel("Undo")

            Button { session.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!session.canRedo)
            .accessibilityLabel("Redo")

            Button {
                session.compareMode = session.compareMode == .split ? .none : .split
            } label: {
                Image(systemName: "square.split.2x1")
                    .foregroundStyle(session.compareMode == .split ? Theme.accent : Color.primary)
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
                Image(systemName: "ellipsis.circle")
            }

            Spacer()

            Button {
                isShowingExport = true
            } label: {
                if session.isExporting {
                    ProgressView()
                } else {
                    Text("Export").fontWeight(.semibold)
                }
            }
            .disabled(session.isExporting)
        }
        .font(.system(size: 18, weight: .medium))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Canvas

    private var canvas: some View {
        CanvasView(renderer: session.renderer)
            .background(Color.black)
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
                } else if session.compareMode == .split {
                    SplitDivider(position: $session.splitPosition)
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
            .clipped()
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(12)
            .allowsHitTesting(false)
    }

    // MARK: - Tools

    private var toolPanel: some View {
        VStack(spacing: 0) {
            switch session.activeTool {
            case .looks:
                LooksPanel(session: session, thumbnails: session.lookThumbnails)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(maxHeight: .infinity, alignment: .top)
            case .adjust:
                sectionChips
                    .padding(.top, 10)
                Group {
                    if section.scrolls {
                        ScrollView {
                            panelContent
                                .padding(.horizontal, 22)
                                .padding(.vertical, 12)
                        }
                    } else {
                        panelContent
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
            case .masks:
                MasksPanel(session: session)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(maxHeight: .infinity, alignment: .top)
            case .retouch:
                RetouchPanel(session: session)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(maxHeight: .infinity, alignment: .top)
            case .face:
                FacePanel(session: session)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(maxHeight: .infinity, alignment: .top)
            case .body:
                BodyPanel(session: session)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(maxHeight: .infinity, alignment: .top)
            case .crop:
                CropPanel(session: session)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(height: 290)
        .background(Theme.panel)
    }

    private var sectionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(AdjustSection.allCases) { item in
                    Button {
                        section = item
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(section == item ? Color.black : Color.primary)
                            .background(section == item ? Theme.accent : Theme.panelRaised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private var toolBar: some View {
        HStack {
            ForEach(EditorTool.allCases) { tool in
                Button {
                    session.activeTool = tool
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 19))
                        Text(tool.title)
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(session.activeTool == tool ? Theme.accent : Color.secondary)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Theme.panel.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Divider().overlay(Color.white.opacity(0.06))
        }
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
                .tint(Theme.accent)
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
                    .fill(Color.white)
                    .frame(width: 2)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                Circle()
                    .fill(Color.white)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 4)
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
