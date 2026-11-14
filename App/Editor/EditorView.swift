import LumoraCore
import LumoraEngine
import SwiftUI

struct EditorView: View {
    @ObservedObject var session: EditorSession
    var onClose: () -> Void

    @State private var isShowingExport = false
    @State private var isShowingHistory = false
    @State private var isShowingFinder = false
    /// The last tool used in each category, so switching back returns to it.
    @State private var lastTool: [StudioCategory: StudioTool] = [:]
    /// Categories whose first-time tip was dismissed ("looks,adjust,").
    @AppStorage("tips.seen") private var seenTips = ""
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
                        .font(Typeface.jost(13, weight: 500))
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
        .sheet(isPresented: $isShowingFinder) {
            ToolFinderView(session: session)
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
            barButton("magnifyingglass") { isShowingFinder = true }
                .accessibilityLabel("Find a tool")

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

    // MARK: - Dock: recipe bar, tool tabs, the panel and the five categories

    private var dock: some View {
        VStack(spacing: 0) {
            if let guide = session.guide {
                guideBar(guide)
            }
            toolTabs
            Hairline()
            toolSummary
            toolPanel
            Hairline()
            categoryBar
        }
        .background(Darkroom.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Hairline() }
        .animation(Darkroom.spring, value: session.guide)
        .onChange(of: session.studioTool) { _, tool in
            lastTool[tool.category] = tool
        }
    }

    /// A recipe in progress: the step, what to do, and Next.
    private func guideBar(_ guide: GuideProgress) -> some View {
        HStack(spacing: 10) {
            Text("STEP \(guide.step + 1)/\(guide.recipe.steps.count)")
                .filmCode(10)
                .foregroundStyle(Darkroom.safelight)
            Text(guide.current.title)
                .font(Typeface.jost(13.5, weight: 500))
                .foregroundStyle(Darkroom.cream)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(guide.isLast ? "Done" : "Next") {
                withAnimation(Darkroom.spring) { session.advanceGuide() }
            }
            .caps(10.5)
            .foregroundStyle(Darkroom.cream)
            .buttonStyle(PressStyle())
            Button {
                withAnimation(Darkroom.spring) { session.endGuide() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Darkroom.stone)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Leave the recipe")
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .background(Darkroom.raised)
        .overlay(alignment: .bottom) { Hairline() }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// The tools of the current category, in italic Cormorant; a safelight rule marks the open one.
    private var toolTabs: some View {
        ScrollViewReader { proxy in
            HScroll {
                HStack(spacing: 22) {
                    ForEach(session.studioTool.category.tools) { tool in
                        let selected = session.studioTool == tool
                        Button {
                            withAnimation(Darkroom.spring) { session.studioTool = tool }
                        } label: {
                            Text(tool.title)
                                .font(Typeface.cormorant(19, weight: 500, italic: true))
                                .foregroundStyle(selected ? Darkroom.cream : Darkroom.stone)
                                .padding(.top, 10)
                                .padding(.bottom, 8)
                                .overlay(alignment: .bottom) {
                                    if selected {
                                        Rectangle()
                                            .fill(Darkroom.safelight)
                                            .frame(height: 1.5)
                                            .matchedGeometryEffect(id: "toolTab", in: toolNamespace)
                                    }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(tool.id)
                        .accessibilityLabel(tool.title)
                        .accessibilityIdentifier("tool.\(tool.rawValue)")
                    }
                }
                .padding(.horizontal, 20)
            }
            .onChange(of: session.studioTool) { _, tool in
                withAnimation(Darkroom.spring) { proxy.scrollTo(tool.id, anchor: .center) }
            }
        }
    }

    /// One line saying what the open tool does (plus Auto for face tools).
    private var toolSummary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(session.studioTool.summary)
                .font(Typeface.jost(13))
                .foregroundStyle(Darkroom.stone)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if !session.studioTool.faceSections.isEmpty {
                Button("Auto") { session.autoBeauty() }
                    .caps(10.5)
                    .foregroundStyle(Darkroom.safelight)
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Auto retouch")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private var toolPanel: some View {
        let category = session.studioTool.category
        return VStack(spacing: 0) {
            if session.guide == nil && !seenTips.contains(category.rawValue) {
                tipCard(category)
            }
            // Panels cross-fade in place (a ZStack, so old and new never stack up).
            ZStack(alignment: .top) {
                panel(for: session.studioTool)
                    .id(session.studioTool)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // Anything taller than the panel runs off the bottom, never the top.
        .frame(height: 232, alignment: .top)
        .clipped()
    }

    /// A short tip, shown the first time a category opens.
    private func tipCard(_ category: StudioCategory) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Darkroom.safelight)
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(category.tip)
                .font(Typeface.jost(13))
                .foregroundStyle(Darkroom.cream)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Got it") {
                withAnimation(Darkroom.ease) { seenTips += category.rawValue + "," }
            }
            .caps(9.5)
            .foregroundStyle(Darkroom.stone)
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("tip.dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Darkroom.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .transition(.opacity)
    }

    @ViewBuilder
    private func panel(for tool: StudioTool) -> some View {
        switch tool {
        case .presets:
            LooksPanel(session: session, thumbnails: session.lookThumbnails).panelPadding()
        case .auto:
            EnhancePanel(session: session, part: .auto).panelPadding()
        case .sky:
            EnhancePanel(session: session, part: .sky).panelPadding()
        case .background:
            EnhancePanel(session: session, part: .background).panelPadding()
        case .light, .color, .curve, .grading, .detail:
            adjustPanel(tool.adjustSections)
        case .masks:
            MasksPanel(session: session).panelPadding()
        case .crop:
            CropPanel(session: session).panelPadding(horizontal: 20)
        case .skin, .features, .makeup, .hair:
            FacePanel(session: session, sections: tool.faceSections).panelPadding()
        case .body:
            BodyPanel(session: session).panelPadding()
        case .reshape:
            ReshapePanel(session: session).panelPadding()
        case .remove, .heal, .clone:
            RetouchPanel(session: session, showsToolPicker: false).panelPadding()
        case .effects:
            StylesPanel(session: session, thumbnails: session.lookThumbnails).panelPadding()
        case .lightAndDust:
            OverlaysPanel(session: session, fixedPage: .overlays).panelPadding()
        case .frames:
            OverlaysPanel(session: session, fixedPage: .frame).panelPadding()
        case .text:
            TextPanel(session: session, mode: .text).panelPadding()
        case .stickers:
            TextPanel(session: session, mode: .stickers).panelPadding()
        }
    }

    /// Adjust tools show one or more parts of the Adjust panel (Detail: detail, effects and optics).
    @ViewBuilder
    private func adjustPanel(_ sections: [AdjustSection]) -> some View {
        if sections.contains(where: { !$0.scrolls }) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sections) { section in
                    panelContent(section)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(sections) { section in
                        if sections.count > 1 {
                            Text(section.title)
                                .caps(10)
                                .foregroundStyle(Darkroom.stone)
                        }
                        panelContent(section)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
    }

    /// The five categories. The active one is marked by a short safelight rule.
    private var categoryBar: some View {
        HStack(spacing: 0) {
            ForEach(StudioCategory.allCases) { category in
                let active = session.studioTool.category == category
                Button {
                    withAnimation(Darkroom.spring) {
                        session.studioTool = lastTool[category] ?? category.tools[0]
                    }
                } label: {
                    VStack(spacing: 0) {
                        ZStack {
                            if active {
                                Rectangle()
                                    .fill(Darkroom.safelight)
                                    .frame(width: 18, height: 1.5)
                                    .matchedGeometryEffect(id: "category", in: toolNamespace)
                            }
                        }
                        .frame(height: 1.5)
                        Text(category.title)
                            .caps(10)
                            .foregroundStyle(active ? Darkroom.cream : Darkroom.stone)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.95))
                .accessibilityLabel(category.title)
                .accessibilityIdentifier("cat.\(category.rawValue)")
            }
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func panelContent(_ section: AdjustSection) -> some View {
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
                .font(Typeface.jost(13, weight: 500))
                Button {
                    session.pickingWhiteBalance.toggle()
                } label: {
                    Label(session.pickingWhiteBalance ? "Tap something white or grey on the photo" : "White balance picker", systemImage: "eyedropper")
                        .font(Typeface.jost(13, weight: 500))
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
            .padding(.top, 10)
            .padding(.bottom, 10)
            .frame(maxHeight: .infinity, alignment: .top)
    }
}
