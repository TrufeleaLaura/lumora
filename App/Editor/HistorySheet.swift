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
            .drFormStyle()
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
                // Each step is a frame on the roll.
                Text(Darkroom.frameCode(index * 2))
                    .filmCode(10)
                    .foregroundStyle(isCurrent ? Darkroom.safelight : Darkroom.muted)
                    .frame(width: 34, alignment: .leading)
                Text(title)
                    .font(.system(size: 15, weight: isCurrent ? .medium : .regular))
                    .foregroundStyle(isUndone ? Darkroom.muted : Darkroom.cream)
                Spacer()
                if isCurrent {
                    Text("Now")
                        .caps(10)
                        .foregroundStyle(Darkroom.safelight)
                }
            }
        }
        .listRowBackground(isCurrent ? Darkroom.raised : Color.clear)
    }
}
