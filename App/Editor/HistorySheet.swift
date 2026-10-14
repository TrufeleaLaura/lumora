import LumoraCore
import SwiftUI

/// Lists every edit step; tapping a row returns the photo to that point.
struct HistorySheet: View {
    @ObservedObject var session: EditorSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let timeline = session.history.timeline
        let applied = session.history.undoSteps.count

        NavigationStack {
            List {
                row(title: "Original", index: 0, isCurrent: applied == 0, isUndone: false)
                ForEach(Array(timeline.enumerated()), id: \.offset) { offset, step in
                    row(title: step.label, index: offset + 1, isCurrent: applied == offset + 1, isUndone: offset + 1 > applied)
                }
            }
            .listStyle(.plain)
            .auraFormStyle()
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(title: String, index: Int, isCurrent: Bool, isUndone: Bool) -> some View {
        Button {
            session.jumpToHistory(appliedCount: index)
        } label: {
            HStack(spacing: 12) {
                // A timeline: a dot per step, the current one glowing.
                Circle()
                    .fill(isCurrent ? AnyShapeStyle(Aura.diagonal) : AnyShapeStyle(isUndone ? Aura.surfaceRaised : Aura.textSecondary.opacity(0.6)))
                    .frame(width: isCurrent ? 12 : 8, height: isCurrent ? 12 : 8)
                    .shadow(color: isCurrent ? Aura.lavender.opacity(0.8) : .clear, radius: 6)
                    .frame(width: 14)
                Text(title)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isUndone ? Aura.textSecondary.opacity(0.6) : Aura.textPrimary)
                Spacer()
                if isCurrent {
                    Text("Now")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .auraChip(true, shape: Capsule())
                }
            }
        }
        .listRowBackground(isCurrent ? Aura.lavender.opacity(0.08) : Color.clear)
    }
}
