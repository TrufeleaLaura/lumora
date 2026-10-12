import LumoraCore
import LumoraEngine
import SwiftUI

struct EditorView: View {
    @ObservedObject var session: EditorSession
    var onClose: () -> Void

    @State private var selectedGroupID = AdjustmentCatalog.groups[0].id

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
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 20) {
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Close")

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

            Image(systemName: "circle.lefthalf.filled")
                .foregroundStyle(session.isShowingOriginal ? Theme.accent : Color.primary)
                .onLongPressGesture(minimumDuration: 0.01, maximumDistance: 60, perform: {}, onPressingChanged: { pressing in
                    session.isShowingOriginal = pressing
                })
                .accessibilityLabel("Hold to compare with original")

            Spacer()

            Button { session.saveToPhotos() } label: {
                if session.isExporting {
                    ProgressView()
                } else {
                    Text("Save").fontWeight(.semibold)
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
        MetalImageView(image: session.displayImage)
            .background(Color.black)
            .overlay(alignment: .topLeading) {
                if session.isShowingOriginal {
                    Text("Original")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(12)
                }
            }
            .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 30, perform: {}, onPressingChanged: { pressing in
                session.isShowingOriginal = pressing
            })
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
                                    session.endChange()
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
