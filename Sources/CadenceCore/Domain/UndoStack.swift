import Foundation

/// One reversible operation, with the words to describe it to the user.
public struct UndoableAction {
    /// Shown in the toast and in the Édition menu: "Annuler : paiement de 70 €".
    public let label: String
    public let undo: () throws -> Void
    public let redo: () throws -> Void

    public init(label: String, undo: @escaping () throws -> Void, redo: @escaping () throws -> Void) {
        self.label = label
        self.undo = undo
        self.redo = redo
    }
}

/// The safety net that lets Cadence do away with confirmation dialogs.
///
/// Recording a payment or marking a presence happens instantly, with no "are you
/// sure?", because ⌘Z reliably takes it back. That trade — immediate action plus a
/// dependable undo — is worth far more over a working day than a wall of prompts.
public final class UndoStack {
    public static let depth = 50

    private var undoStack: [UndoableAction] = []
    private var redoStack: [UndoableAction] = []
    /// Guards against an undo action re-registering itself while it runs.
    private var isPerforming = false

    public private(set) var revision = 0

    public init() {}

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var nextUndoLabel: String? { undoStack.last?.label }
    public var nextRedoLabel: String? { redoStack.last?.label }

    public func register(_ action: UndoableAction) {
        guard !isPerforming else { return }
        undoStack.append(action)
        if undoStack.count > Self.depth { undoStack.removeFirst() }
        redoStack.removeAll()
        revision += 1
    }

    public func register(label: String, undo: @escaping () throws -> Void, redo: @escaping () throws -> Void) {
        register(UndoableAction(label: label, undo: undo, redo: redo))
    }

    /// Reverts the most recent action. Returns its label so the caller can confirm it.
    @discardableResult
    public func undo() throws -> String? {
        guard let action = undoStack.popLast() else { return nil }
        isPerforming = true
        defer { isPerforming = false; revision += 1 }
        do {
            try action.undo()
            redoStack.append(action)
            return action.label
        } catch {
            // Putting it back keeps the stack honest: a failed undo is not an undo.
            undoStack.append(action)
            throw error
        }
    }

    @discardableResult
    public func redo() throws -> String? {
        guard let action = redoStack.popLast() else { return nil }
        isPerforming = true
        defer { isPerforming = false; revision += 1 }
        do {
            try action.redo()
            undoStack.append(action)
            return action.label
        } catch {
            redoStack.append(action)
            throw error
        }
    }

    public func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        revision += 1
    }
}
