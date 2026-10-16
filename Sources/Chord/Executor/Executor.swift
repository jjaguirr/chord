import ChordCore

/// One applied change to a window, with the state it replaced. Every case has an
/// inverse and a log line.
public enum Change: Equatable, Sendable {
    case place(windowID: Int, from: Place, to: Place)
    case frame(windowID: Int, from: ScreenRect, to: ScreenRect)
    case focus(from: Int?, to: Int)

    public var inverse: Change {
        switch self {
        case .place(let id, let from, let to): return .place(windowID: id, from: to, to: from)
        case .frame(let id, let from, let to): return .frame(windowID: id, from: to, to: from)
        case .focus(let from, let to): return .focus(from: to, to: from ?? to)
        }
    }

    public var logLine: String {
        switch self {
        case .place(let id, let from, let to): return Action.place(windowID: id, from: from, to: to).logLine
        case .frame(let id, let from, let to):
            return Action.frame(windowID: id, from: from.actionRect, to: to.actionRect).logLine
        case .focus(let from, let to): return Action.focus(from: from, to: to).logLine
        }
    }
}

private extension ScreenRect {
    var actionRect: ActionRect { ActionRect(x: x, y: y, width: width, height: height) }
}

private extension ActionRect {
    var screenRect: ScreenRect { ScreenRect(x: x, y: y, width: width, height: height) }
}

private extension WindowHome {
    var screenRect: ScreenRect { frame.screenRect }
}

public enum ExecutorError: Error, Equatable, Sendable {
    case nothingToUndo
}

extension ScreenRect {
    /// The frame as it is applied to a window: whole points only.
    func roundedToIntegers() -> ScreenRect {
        ScreenRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }
}

/// The only component that changes windows. It accepts typed plans and explicit
/// frames, validates them against a fresh backend snapshot, applies them through
/// `WorkspaceBackend`, and logs every change. Rearrangements are undoable as one
/// step; focus changes are logged with an inverse but are navigation, not
/// rearrangement, so they are not on the undo stack.
///
/// Size is never decided here: frames are applied exactly as the caller supplies
/// them, rounded to integers. The Executor never reads a frame back to compute
/// the next one; the previous frame comes from the backend's own reply.
public actor Executor {
    private let backend: any WorkspaceBackend
    private var undoStack: [[Change]] = []
    /// Window ids, least to most recently focused. Per-workspace history is this
    /// list filtered by each window's current place.
    private var focusOrder: [Int] = []
    private var focusedID: Int?
    private var focusedPlace: Place?

    /// Every applied, undone, or failed change, in order.
    public private(set) var log: [String] = []

    public init(backend: any WorkspaceBackend) {
        self.backend = backend
    }

    // MARK: Plans

    /// Applies `plan` and optional explicit `frames` as one undoable step. Throws
    /// `PlanError.unknownWindow` before changing anything if any named window is
    /// not in the backend's snapshot. If a backend call fails midway, the changes
    /// already applied stay on the undo stack and the error is rethrown.
    @discardableResult
    public func apply(_ plan: Plan, frames: [Int: ScreenRect] = [:]) async throws -> [Change] {
        let snapshot = try await backend.snapshot()
        let known = Set(snapshot.windows.map(\.id.rawValue))
        try plan.validate(knownWindows: known)
        if let stray = frames.keys.sorted().first(where: { !known.contains($0) }) {
            throw PlanError.unknownWindow(stray)
        }

        var model: [Int: Place] = [:]
        var bounds: [Int: ScreenRect] = [:]
        for window in snapshot.windows {
            model[window.id.rawValue] = window.place
            bounds[window.id.rawValue] = window.bounds
        }

        let requested = frames.keys.sorted().compactMap { id -> Action? in
            guard let current = bounds[id], let frame = frames[id] else { return nil }
            let target = frame.roundedToIntegers()
            guard current != target else { return nil }
            return .frame(windowID: id, from: current.actionRect, to: target.actionRect)
        }
        let actions = try plan.actions(from: model, requested: requested)
        let planned = changes(from: actions)
        let applied = try await run(planned)
        if !applied.isEmpty { undoStack.append(applied) }
        return applied
    }

    /// Moves one window to an exact frame (rounded) as its own undoable step.
    @discardableResult
    public func setFrame(_ id: Int, to frame: ScreenRect) async throws -> [Change] {
        let snapshot = try await backend.snapshot()
        guard let window = snapshot.windows.first(where: { $0.id.rawValue == id }) else {
            throw PlanError.unknownWindow(id)
        }
        let target = frame.roundedToIntegers()
        guard window.bounds != target else { return [] }
        let plan = try Plan(assignments: [])
        let action = Action.frame(windowID: id, from: window.bounds.actionRect, to: target.actionRect)
        let planned = changes(from: try plan.actions(from: [id: window.place], requested: [action]))
        guard !planned.isEmpty else { return [] }
        let applied = try await run(planned)
        undoStack.append(applied)
        return applied
    }

    /// Restores a remembered place and frame as one undoable transaction.
    @discardableResult
    public func restoreHome(_ id: Int, to home: WindowHome) async throws -> [Change] {
        let snapshot = try await backend.snapshot()
        guard let window = snapshot.windows.first(where: { $0.id.rawValue == id }) else {
            throw PlanError.unknownWindow(id)
        }
        let current = WindowHome(place: window.place, frame: window.bounds.actionRect)
        let plan = try Plan(assignments: [])
        let action = Action.restoreHome(windowID: id, from: current, to: home)
        let planned = changes(from: try plan.actions(from: [id: window.place], requested: [action]))
        guard !planned.isEmpty else { return [] }
        log.append(action.logLine)
        let applied = try await run(planned)
        undoStack.append(applied)
        return applied
    }

    /// Reverts the most recent rearrangement, restoring each window's previous
    /// place and frame. Windows that have since closed are skipped and logged.
    /// If the backend fails midway, the changes not yet reverted stay undoable.
    @discardableResult
    public func undo() async throws -> [Change] {
        guard let transaction = undoStack.popLast() else { throw ExecutorError.nothingToUndo }
        var reverted: [Change] = []
        for (index, change) in transaction.enumerated().reversed() {
            do {
                reverted.append(contentsOf: try await run([change.inverse], label: "undo"))
            } catch BackendError.unknownWindow(let id) {
                log.append("undo skipped: window \(id) is gone")
            } catch {
                undoStack.append(Array(transaction[...index]))
                throw error
            }
        }
        return reverted
    }

    // MARK: Focus

    /// Focuses one window, raising only that window, then restores floating
    /// windows in its place above tiles. Records it in the place's focus history.
    @discardableResult
    public func focus(_ id: Int) async throws -> Change {
        let snapshot = try await backend.snapshot()
        guard let window = snapshot.windows.first(where: { $0.id.rawValue == id }) else {
            throw PlanError.unknownWindow(id)
        }
        let plan = try Plan(assignments: [])
        let action = Action.focus(from: snapshot.focusedWindow?.rawValue, to: id)
        let places = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.id.rawValue, $0.place) })
        let applied = try await run(changes(from: try plan.actions(from: places, requested: [action])))

        focusedPlace = window.place
        if !window.isFloating {
            let rank = Dictionary(
                snapshot.stackingOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            let floats = snapshot.windows
                .filter { $0.isFloating && $0.place == window.place }
                .sorted { (rank[$0.id] ?? 0) < (rank[$1.id] ?? 0) }
            for float in floats {
                try await backend.raiseWindow(float.id)
                log.append("raise floating window \(float.id.rawValue)")
            }
        }
        return applied[0]
    }

    /// Window ids last focused in `place`, most recent first, for windows that exist.
    public func focusHistory(in place: Place) async throws -> [Int] {
        let snapshot = try await backend.snapshot()
        let places = Dictionary(
            snapshot.windows.map { ($0.id.rawValue, $0.place) }, uniquingKeysWith: { first, _ in first })
        return focusOrder.reversed().filter { places[$0] == place }
    }

    /// Call after a window closes. Forgets closed windows and, if the focused
    /// window was among them, focuses the most recently focused survivor in the
    /// same place. Returns the window it focused, if any.
    @discardableResult
    public func reconcileAfterClose() async throws -> Int? {
        let snapshot = try await backend.snapshot()
        let existing = Set(snapshot.windows.map(\.id.rawValue))
        focusOrder.removeAll { !existing.contains($0) }
        guard let closed = focusedID, !existing.contains(closed), let place = focusedPlace else {
            return nil
        }
        focusedID = nil
        focusedPlace = nil
        let places = Dictionary(
            snapshot.windows.map { ($0.id.rawValue, $0.place) }, uniquingKeysWith: { first, _ in first })
        guard let next = focusOrder.last(where: { places[$0] == place }) else { return nil }
        try await focus(next)
        return next
    }

    // MARK: Applying changes

    /// Applies changes in order through the backend, returning what the backend
    /// confirmed. An `.unknown` reply is resolved by re-reading the snapshot, never
    /// assumed either way.
    private func run(_ changes: [Change], label: String? = nil) async throws -> [Change] {
        var applied: [Change] = []
        for change in changes {
            do {
                let confirmed = try await perform(change)
                applied.append(confirmed)
                record(confirmed, label: label)
            } catch let error as BackendError {
                if case .unknown = error, await landed(change) {
                    applied.append(change)
                    record(change, label: label)
                    continue
                }
                log.append("failed: \(change.logLine): \(error)")
                if !applied.isEmpty, label == nil { undoStack.append(applied) }
                throw error
            }
        }
        return applied
    }

    private func changes(from actions: [Action]) -> [Change] {
        var changes: [Change] = []
        for action in actions {
            switch action {
            case .place(let id, let from, let to):
                changes.append(.place(windowID: id, from: from, to: to))
            case .frame(let id, let from, let to):
                let target = to.screenRect.roundedToIntegers()
                if from.screenRect != target {
                    changes.append(.frame(windowID: id, from: from.screenRect, to: target))
                }
            case .focus(let from, let to):
                changes.append(.focus(from: from, to: to))
            case .restoreHome(let id, let from, let to):
                if from.place != to.place {
                    changes.append(.place(windowID: id, from: from.place, to: to.place))
                }
                let target = to.screenRect.roundedToIntegers()
                if from.frame.screenRect != target {
                    changes.append(.frame(windowID: id, from: from.frame.screenRect, to: target))
                }
            }
        }
        return changes
    }

    private func perform(_ change: Change) async throws -> Change {
        switch change {
        case .place(let id, _, let to):
            let from = try await backend.moveWindow(WindowID(id), to: to)
            return .place(windowID: id, from: from, to: to)
        case .frame(let id, _, let to):
            let from = try await backend.applyFrame(WindowID(id), to: to)
            return .frame(windowID: id, from: from, to: to)
        case .focus(_, let to):
            let from = try await backend.focusWindow(WindowID(to))
            return .focus(from: from?.rawValue, to: to)
        }
    }

    /// After an `.unknown` error: did the backend actually reach the change's target?
    private func landed(_ change: Change) async -> Bool {
        guard let snapshot = try? await backend.snapshot() else { return false }
        switch change {
        case .place(let id, _, let to):
            return snapshot.windows.first { $0.id.rawValue == id }?.place == to
        case .frame(let id, _, let to):
            return snapshot.windows.first { $0.id.rawValue == id }?.bounds == to
        case .focus(_, let to):
            return snapshot.focusedWindow?.rawValue == to
        }
    }

    private func record(_ change: Change, label: String?) {
        log.append(label.map { "\($0): \(change.logLine)" } ?? change.logLine)
        switch change {
        case .focus(_, let to):
            focusOrder.removeAll { $0 == to }
            focusOrder.append(to)
            focusedID = to
        case .place(let id, _, let to) where id == focusedID:
            focusedPlace = to
        case .place, .frame:
            break
        }
    }
}
