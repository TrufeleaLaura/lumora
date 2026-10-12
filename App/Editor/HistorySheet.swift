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
            HStack {
                Text(title)
                    .foregroundStyle(isUndone ? Color.secondary : Color.primary)
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}
