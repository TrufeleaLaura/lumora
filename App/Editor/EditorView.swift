import LumoraCore
import LumoraEngine
import SwiftUI

struct EditorView: View {
    @ObservedObject var session: EditorSession
    var onClose: () -> Void

    @State private var selectedGroupID = AdjustmentCatalog.groups[0].id
    @State private var isShowingExport = false
    @State private var isShowingHistory = false

    private var selectedGroup: ToolGroup {
        AdjustmentCatalog.groups.first { $0.id == selectedGroupID } ?? AdjustmentCatalog.groups[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            canvas
            toolPanel
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
                if session.compareMode == .split {
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
            ScrollView {
                VStack(spacing: 18) {
                    ForEach(selectedGroup.sliders) { spec in
                        AdjustmentSlider(
                            spec: spec,
                            value: binding(for: spec),
                            onEditingChanged: { editing in
                                if editing {
                                    session.beginChange()
                                } else {
                                    let value = session.document[keyPath: spec.keyPath]
                                    session.endChange(label: "\(spec.title) \(spec.formatted(value))")
                                }
                            },
                            onReset: { session.reset(spec) }
                        )
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
            }
            .frame(height: 250)

            Divider().overlay(Color.white.opacity(0.06))

            HStack {
                ForEach(AdjustmentCatalog.groups) { group in
                    Button {
                        selectedGroupID = group.id
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: group.symbol)
                                .font(.system(size: 19))
                            Text(group.title)
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(selectedGroupID == group.id ? Theme.accent : Color.secondary)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
        .background(Theme.panel.ignoresSafeArea(edges: .bottom))
    }

    private func binding(for spec: SliderSpec) -> Binding<Double> {
        Binding(
            get: { session.document[keyPath: spec.keyPath] },
            set: { session.document[keyPath: spec.keyPath] = $0 }
        )
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
