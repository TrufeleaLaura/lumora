import Foundation

/// Snapshot-based undo/redo history. Callers `record` the state *before* a change.
public struct UndoStack<State> {
    public private(set) var undoStates: [State] = []
    public private(set) var redoStates: [State] = []
    public let limit: Int

    public init(limit: Int = 200) {
        self.limit = limit
    }

    public var canUndo: Bool { !undoStates.isEmpty }
    public var canRedo: Bool { !redoStates.isEmpty }

    /// Stores `state` as the point to return to on undo, and clears the redo history.
    public mutating func record(_ state: State) {
        undoStates.append(state)
        if undoStates.count > limit {
            undoStates.removeFirst(undoStates.count - limit)
        }
        redoStates.removeAll()
    }

    /// Returns the previous state, remembering `current` for redo.
    public mutating func undo(current: State) -> State? {
        guard let previous = undoStates.popLast() else { return nil }
        redoStates.append(current)
        return previous
    }

    /// Returns the next state, remembering `current` for undo.
    public mutating func redo(current: State) -> State? {
        guard let next = redoStates.popLast() else { return nil }
        undoStates.append(current)
        return next
    }

    public mutating func removeAll() {
        undoStates.removeAll()
        redoStates.removeAll()
    }
}
