import Foundation

/// Undo/redo history made of labelled steps ("Exposure +0.50"), each remembering the
/// document before and after the change.
public struct EditHistory {
    public struct Step: Equatable {
        public var label: String
        public var before: EditDocument
        public var after: EditDocument

        public init(label: String, before: EditDocument, after: EditDocument) {
            self.label = label
            self.before = before
            self.after = after
        }
    }

    /// Applied steps, oldest first.
    public private(set) var undoSteps: [Step] = []
    /// Undone steps; the last element is the next one to redo.
    public private(set) var redoSteps: [Step] = []
    public let limit: Int

    public init(limit: Int = 200) {
        self.limit = limit
    }

    public var canUndo: Bool { !undoSteps.isEmpty }
    public var canRedo: Bool { !redoSteps.isEmpty }

    /// Records a change. Changes that don't modify the document are ignored.
    public mutating func record(label: String, before: EditDocument, after: EditDocument) {
        guard before != after else { return }
        undoSteps.append(Step(label: label, before: before, after: after))
        if undoSteps.count > limit {
            undoSteps.removeFirst(undoSteps.count - limit)
        }
        redoSteps.removeAll()
    }

    /// Undoes the latest step and returns the document to show.
    public mutating func undo() -> EditDocument? {
        guard let step = undoSteps.popLast() else { return nil }
        redoSteps.append(step)
        return step.before
    }

    /// Redoes the next step and returns the document to show.
    public mutating func redo() -> EditDocument? {
        guard let step = redoSteps.popLast() else { return nil }
        undoSteps.append(step)
        return step.after
    }

    /// Moves to the state after `appliedCount` steps of the combined timeline
    /// (0 = the original photo). Returns the document to show.
    public mutating func jump(toAppliedCount appliedCount: Int) -> EditDocument? {
        let total = undoSteps.count + redoSteps.count
        let target = max(0, min(appliedCount, total))
        var result: EditDocument?
        while undoSteps.count > target, let document = undo() {
            result = document
        }
        while undoSteps.count < target, let document = redo() {
            result = document
        }
        return result
    }

    /// The full timeline (applied then undone steps) for display, oldest first.
    public var timeline: [Step] {
        undoSteps + redoSteps.reversed()
    }

    public mutating func removeAll() {
        undoSteps.removeAll()
        redoSteps.removeAll()
    }
}
