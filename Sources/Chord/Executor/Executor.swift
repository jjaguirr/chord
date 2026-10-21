import ChordCore

/// One applied change to a window, with the state it replaced. Every case has an
/// inverse and a log line.
public enum Change: Equatable, Sendable {
    case place(windowID: Int, from: Place, to: Place)
    case frame(windowID: Int, from: ScreenRect, to: ScreenRect)
    case focus(from: Int?, to: Int)
    case reshape(windowID: Int, aspectDelta: Double, areaDelta: Double, from: ScreenRect, to: ScreenRect)
    case noop(windowID: Int)
    /// A workspace switch. `from` is nil when what was showing is a workspace Chord did
    /// not create: it cannot be named, so the switch has no inverse beyond a logged no-op.
    case show(from: GridSlot?, to: GridSlot)
    /// A window moved between slots (a cell or the bench), in any row.
    case move(windowID: Int, from: GridSlot, to: GridSlot)

    public var inverse: Change {
        switch self {
        case .place(let id, let from, let to): return .place(windowID: id, from: to, to: from)
        case .frame(let id, let from, let to): return .frame(windowID: id, from: to, to: from)
        case .focus(let from, let to): return from.map { .focus(from: to, to: $0) } ?? .noop(windowID: to)
        case .reshape(let id, let aspect, let area, let from, let to):
            return .reshape(windowID: id, aspectDelta: 0 - aspect, areaDelta: 0 - area, from: to, to: from)
        case .noop: return self
        case .show(let from, let to): return from.map { .show(from: to, to: $0) } ?? .noop(windowID: 0)
        case .move(let id, let from, let to): return .move(windowID: id, from: to, to: from)
        }
    }

    public var logLine: String {
        switch self {
        case .place(let id, let from, let to): return Action.place(windowID: id, from: from, to: to).logLine
        case .frame(let id, let from, let to):
            return Action.frame(windowID: id, from: from.actionRect, to: to.actionRect).logLine
        case .focus(let from, let to): return Action.focus(from: from, to: to).logLine
        case .reshape(let id, let aspect, let area, let from, let to):
            return Action.reshape(
                windowID: id, aspectDelta: aspect, areaDelta: area, from: from.actionRect, to: to.actionRect
            ).logLine
        case .noop: return Action.noop(windowID: 0).logLine
        case .show(let from, let to): return WorkspaceGrid.logLine(showing: to, from: from)
        case .move(let id, let from, let to): return WorkspaceGrid.logLine(moving: id, from: from, to: to)
        }
    }
}

private extension ScreenRect {
    var actionRect: ActionRect { ActionRect(x: x, y: y, width: width, height: height) }
    var pickerRect: PickerRect { PickerRect(x: x, y: y, width: width, height: height) }
}

private extension ActionRect {
    var screenRect: ScreenRect { ScreenRect(x: x, y: y, width: width, height: height) }
}

private extension WindowHome {
    var screenRect: ScreenRect { frame.screenRect }
}

public enum ExecutorError: Error, Equatable, Sendable {
    case nothingToUndo
    /// No visible frame was supplied and no monitor contains the window.
    case noVisibleFrame
    /// The backend reports no focused window to act on.
    case noFocusedWindow
    /// A frame step arrived with no frame run begun.
    case noFrameRun
}

/// The focused window as the backend reported it, with the visible frame of the
/// monitor that holds it. Both are in the backend's screen coordinates.
public struct WindowContext: Equatable, Sendable {
    public let id: Int
    public let bounds: ScreenRect
    public let visibleFrame: ScreenRect

    public init(id: Int, bounds: ScreenRect, visibleFrame: ScreenRect) {
        self.id = id
        self.bounds = bounds
        self.visibleFrame = visibleFrame
    }
}

extension ScreenRect {
    /// The frame as it is applied to a window: whole points only.
    func roundedToIntegers() -> ScreenRect {
        ScreenRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }
}

/// The only component that changes windows. It accepts typed plans and explicit
/// frames, validates them against a fresh backend snapshot, applies them through
/// `WorkspaceBackend`, and logs every change. Undo restores the previous window,
/// frame, and place, but not the exact stacking order ([#42](https://github.com/jjaguirr/chord/issues/42)).
/// Rearrangements and focus changes are undoable, including a logged no-op when
/// focus had no previous window.
///
/// Size is never decided here: frames are applied exactly as the caller supplies
/// them, rounded to integers. The Executor never reads a frame back to compute
/// the next one; the previous frame comes from the backend's own reply.
public actor Executor {
    private let logSink: (@Sendable (String) -> Void)?

    private let backend: any WorkspaceBackend

    /// An open run of frames for one window (Unfold). Steps are applied without a
    /// snapshot and without a log line each; the run closes as one undoable change.
    private struct FrameRun {
        let label: String
        let id: Int
        let start: ScreenRect
        var last: ScreenRect
    }
    private var frameRun: FrameRun?
    /// The window of the last carry step and the undo depth right after it. A carry
    /// held down extends that one undo entry instead of adding a hundred.
    private var carryRun: (id: Int, depth: Int)?
    private var undoStack: [[Change]] = []
    /// Window ids, least to most recently focused. Per-workspace history is this
    /// list filtered by each window's current place.
    private var focusOrder: [Int] = []
    private var focusedID: Int?
    private var focusedPlace: Place?
    /// The last Look move, so the opposite key can prefer the window it came from.
    private var lastLook: (from: Int, to: Int)?
    /// What Chord last saw showing: for Option+Tab and the row Option+N acts in.
    private var navigation: WorkspaceNavigation

    /// Every applied, undone, or failed change, in order.
    public private(set) var log: [String] = []

    public init(
        backend: any WorkspaceBackend, workspaces: WorkspaceLayout = .defaults,
        logSink: (@Sendable (String) -> Void)? = nil
    ) {
        self.backend = backend
        self.logSink = logSink
        self.navigation = WorkspaceNavigation(layout: workspaces)
    }


    // MARK: Plans

    /// Applies `plan`, optional explicit `frames`, and typed `requested` actions as
    /// one undoable step. Throws `PlanError.unknownWindow` before changing anything
    /// if any named window is not in the backend's snapshot. If a backend call fails
    /// midway, the changes already applied stay on the undo stack and the error is rethrown.
    @discardableResult
    public func apply(
        _ plan: Plan, frames: [Int: ScreenRect] = [:], requested requestedActions: [Action] = []
    ) async throws -> [Change] {
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

        let frameActions = frames.keys.sorted().compactMap { id -> Action? in
            guard let current = bounds[id], let frame = frames[id] else { return nil }
            let target = frame.roundedToIntegers()
            guard current != target else { return nil }
            return .frame(windowID: id, from: current.actionRect, to: target.actionRect)
        }
        let actions = try plan.actions(from: model, requested: frameActions + requestedActions)
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

    /// One user reshape step: log-space deltas on aspect and area, clamped to the
    /// visible frame and `minimumSize`, rounded to integers, as its own undoable
    /// step. The start frame is the backend's fresh snapshot, so a size the user
    /// set with the mouse is the base of the next step, never overwritten by a
    /// remembered one. Nothing is read back after the apply. `visibleFrame`
    /// defaults to the monitor holding the window's center. Returns `[]` when the
    /// step is already clamped.
    @discardableResult
    public func reshape(
        _ id: Int, aspectDelta: Double, areaDelta: Double,
        minimumSize: ActionSize, visibleFrame: ScreenRect? = nil
    ) async throws -> [Change] {
        let snapshot = try await backend.snapshot()
        guard let window = snapshot.windows.first(where: { $0.id.rawValue == id }) else {
            throw PlanError.unknownWindow(id)
        }
        guard let visible = visibleFrame ?? Self.monitorBounds(holding: window.bounds, in: snapshot) else {
            throw ExecutorError.noVisibleFrame
        }
        guard let action = reshapeAction(
            for: .reshape(aspectDelta: aspectDelta, areaDelta: areaDelta),
            windowID: id, from: window.bounds.actionRect,
            within: visible.actionRect, minimumSize: minimumSize)
        else { return [] }
        let plan = try Plan(assignments: [])
        let planned = changes(from: try plan.actions(from: [id: window.place], requested: [action]))
        let applied = try await run(planned)
        undoStack.append(applied)
        return applied
    }

    /// `reshape` on the focused window.
    @discardableResult
    public func reshapeFocused(
        aspectDelta: Double, areaDelta: Double, minimumSize: ActionSize
    ) async throws -> [Change] {
        let context = try await focusedWindowContext()
        return try await reshape(
            context.id, aspectDelta: aspectDelta, areaDelta: areaDelta,
            minimumSize: minimumSize, visibleFrame: context.visibleFrame)
    }

    // MARK: Focused-window motion

    /// The focused window and its monitor's visible frame, read fresh from the backend.
    public func focusedWindowContext() async throws -> WindowContext {
        let snapshot = try await backend.snapshot()
        return try Self.focusedContext(in: snapshot).context
    }

    private static func focusedContext(in snapshot: BackendSnapshot) throws -> (window: WindowSnapshot, context: WindowContext) {
        guard let focused = snapshot.focusedWindow,
            let window = snapshot.windows.first(where: { $0.id == focused })
        else { throw ExecutorError.noFocusedWindow }
        guard let visible = monitorBounds(holding: window.bounds, in: snapshot) else {
            throw ExecutorError.noVisibleFrame
        }
        return (window, WindowContext(id: window.id.rawValue, bounds: window.bounds, visibleFrame: visible))
    }

    /// Opens a frame run on the focused window and returns where it stands. A run
    /// still open is closed first. Only a caller that animates a size the user asked
    /// for (Unfold) may use this.
    public func beginFrameRun(label: String) async throws -> WindowContext {
        endFrameRun()
        let context = try await focusedWindowContext()
        frameRun = FrameRun(label: label, id: context.id, start: context.bounds, last: context.bounds)
        return context
    }

    /// Applies one frame of the open run: rounded, skipped when it equals the last
    /// applied frame, never preceded by a snapshot. If the backend fails, the run
    /// still counts the frame as applied so that undo restores the start.
    public func stepFrameRun(to frame: ScreenRect) async throws {
        guard let run = frameRun else { throw ExecutorError.noFrameRun }
        let target = frame.roundedToIntegers()
        guard target != run.last else { return }
        do {
            try await backend.applyFrame(WindowID(run.id), to: target)
        } catch {
            appendLog("failed: \(run.label) step on window \(run.id): \(error)")
            frameRun?.last = target
            throw error
        }
        frameRun?.last = target
    }

    /// Closes the open run as one undoable frame change from where it began to where
    /// it ended, with one log line. Returns `[]` when there was no run or it ended
    /// where it began.
    @discardableResult
    public func endFrameRun() -> [Change] {
        guard let run = frameRun else { return [] }
        frameRun = nil
        guard run.last != run.start else {
            appendLog("\(run.label): window \(run.id) ended where it began")
            return []
        }
        let change = Change.frame(windowID: run.id, from: run.start, to: run.last)
        appendLog("\(run.label): \(change.logLine)")
        undoStack.append([change])
        return [change]
    }

    /// Moves the focused window by `(dx, dy)` points without changing its size. A
    /// step never pushes the window further out past an edge of its visible frame,
    /// though it never pulls a window the user put off-screen back either. Held
    /// carry steps extend one undo entry.
    @discardableResult
    public func carry(dx: Double, dy: Double) async throws -> [Change] {
        let snapshot = try await backend.snapshot()
        let (window, context) = try Self.focusedContext(in: snapshot)
        let bounds = context.bounds
        let visible = context.visibleFrame
        let target = ScreenRect(
            x: Self.carried(bounds.x, by: dx, size: bounds.width, low: visible.x, high: visible.x + visible.width),
            y: Self.carried(bounds.y, by: dy, size: bounds.height, low: visible.y, high: visible.y + visible.height),
            width: bounds.width, height: bounds.height
        ).roundedToIntegers()
        guard target != bounds else { return [] }

        let plan = try Plan(assignments: [])
        let action = Action.frame(windowID: context.id, from: bounds.actionRect, to: target.actionRect)
        let planned = changes(from: try plan.actions(from: [context.id: window.place], requested: [action]))
        guard !planned.isEmpty else { return [] }
        let applied = try await run(planned)

        if let tail = carryRun, tail.id == context.id, tail.depth == undoStack.count,
            undoStack.last?.count == 1,
            case .frame(_, let origin, let previousEnd)? = undoStack.last?.first, previousEnd == bounds,
            case .frame(_, _, let end)? = applied.last
        {
            undoStack[undoStack.count - 1] = [.frame(windowID: context.id, from: origin, to: end)]
        } else if !applied.isEmpty {
            undoStack.append(applied)
        }
        carryRun = (context.id, undoStack.count)
        return applied
    }

    /// Carries the focused window to the adjacent monitor in `direction`: same size, flush
    /// with the edge it enters through, its position along the other axis kept and clamped
    /// into that monitor's visible frame (`MonitorAdjacency`, the rule Look also uses).
    /// Adjacency comes from the backend's monitors. One undo entry restores the previous
    /// frame, and with it the previous monitor. With no monitor that way the window takes
    /// the ordinary carry step `(dx, dy)` instead and the reason is logged.
    @discardableResult
    public func carryAcross(_ direction: PickDirection, dx: Double, dy: Double) async throws -> [Change] {
        let snapshot = try await backend.snapshot()
        let (window, context) = try Self.focusedContext(in: snapshot)
        let monitors = snapshot.monitors.map {
            PickerMonitor(id: $0.id.rawValue, bounds: $0.bounds.pickerRect, isPrimary: $0.isPrimary)
        }
        guard !monitors.isEmpty else { throw ExecutorError.noVisibleFrame }
        let bounds = context.bounds
        let origin = monitors[MonitorAdjacency.index(holding: bounds.pickerRect, in: monitors)]
        guard let target = MonitorAdjacency.neighbour(of: origin, in: monitors, direction: direction) else {
            appendLog("carry \(direction.keys): window \(context.id): no monitor that way; carried within the monitor")
            return try await carry(dx: dx, dy: dy)
        }
        let landed = MonitorAdjacency.landing(
            of: bounds.pickerRect, from: origin.bounds, on: target.bounds, direction: direction)
        let crossesX = MonitorAdjacency.isBeyond(target.bounds, origin.bounds, PickDirection(x: direction.x, y: 0))
        let crossesY = MonitorAdjacency.isBeyond(target.bounds, origin.bounds, PickDirection(x: 0, y: direction.y))
        let visible = target.bounds
        let frame = ScreenRect(
            x: crossesX
                ? landed.x
                : Self.carried(landed.x, by: dx, size: landed.width, low: visible.x, high: visible.x + visible.width),
            y: crossesY
                ? landed.y
                : Self.carried(landed.y, by: dy, size: landed.height, low: visible.y, high: visible.y + visible.height),
            width: landed.width, height: landed.height
        ).roundedToIntegers()
        guard frame != bounds else { return [] }

        let plan = try Plan(assignments: [])
        let action = Action.frame(windowID: context.id, from: bounds.actionRect, to: frame.actionRect)
        let planned = changes(from: try plan.actions(from: [context.id: window.place], requested: [action]))
        guard !planned.isEmpty else { return [] }
        let label = "carry \(direction.keys) across monitors \(origin.id) -> \(target.id)"
        let applied = try await run(planned, label: label)
        if !applied.isEmpty { undoStack.append(applied) }
        carryRun = nil
        return applied
    }

    /// `origin` moved by `delta`, held inside `low...high` only in the direction of travel.
    private static func carried(_ origin: Double, by delta: Double, size: Double, low: Double, high: Double) -> Double {
        let moved = origin + delta
        if delta > 0 { return min(moved, max(origin, high - size)) }
        if delta < 0 { return max(moved, min(origin, low)) }
        return origin
    }

    private static func monitorBounds(holding rect: ScreenRect, in snapshot: BackendSnapshot) -> ScreenRect? {
        ScreenGeometry.visibleFrame(holding: rect, monitors: snapshot.monitors)
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
        let applied = try await run(planned)
        appendLog(action.logLine)
        undoStack.append(applied)
        return applied
    }

    /// Reverts the most recent rearrangement or focus change. Windows that have
    /// since closed are skipped and logged.
    /// If the backend fails midway, the changes not yet reverted stay undoable.
    @discardableResult
    public func undo() async throws -> [Change] {
        guard let transaction = undoStack.popLast() else { throw ExecutorError.nothingToUndo }
        var reverted: [Change] = []
        for (index, change) in transaction.enumerated().reversed() {
            do {
                if case .reshape(let id, _, _, _, let to) = change {
                    // The user resized it since (mouse, app): that size stands.
                    let current = try await backend.snapshot().windows.first { $0.id.rawValue == id }
                    if let current, current.bounds != to {
                        appendLog("undo skipped: window \(id) was resized since the reshape")
                        continue
                    }
                }
                reverted.append(contentsOf: try await run([change.inverse], label: "undo"))
            } catch BackendError.unknownWindow(let id) {
                appendLog("undo skipped: window \(id.rawValue) is gone")
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
        if !applied.isEmpty { undoStack.append(applied) }

        focusedPlace = window.place
        if !window.isFloating {
            let rank = Dictionary(
                snapshot.stackingOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            let floats = snapshot.windows
                .filter { $0.isFloating && $0.place == window.place }
                .sorted { (rank[$0.id] ?? 0) < (rank[$1.id] ?? 0) }
            for float in floats {
                try await backend.raiseWindow(float.id)
                appendLog("raise floating window \(float.id.rawValue)")
            }
        }
        return applied[0]
    }

    /// What one Look press found and did.
    public struct LookResult: Equatable, Sendable {
        public let decision: LookDecision
        /// The focus change, or nil when nothing was picked.
        public let change: Change?
    }

    /// Look: focuses the nearest visible window in `direction` from the focused one, on any
    /// monitor (see `Look`). Candidates are every window the backend reports visible;
    /// ranking is the pure Picker's. The focus goes through `focus`, so it raises that one
    /// window, is undoable, and is logged. The press, its candidates, and the pick (or why
    /// there was none) get one log line. Nothing is picked, and nothing changes, when
    /// there is no focused window, no other window, or no target that way.
    @discardableResult
    public func look(_ direction: PickDirection) async throws -> LookResult {
        let snapshot = try await backend.visibleSnapshot()
        guard let originID = snapshot.focusedWindow?.rawValue,
            snapshot.windows.contains(where: { $0.id.rawValue == originID })
        else { throw ExecutorError.noFocusedWindow }
        let windows = snapshot.windows.map { window in
            PickerWindow(
                id: window.id.rawValue, rect: window.bounds.pickerRect,
                layer: window.isFloating ? 1 : 0,
                mru: (focusOrder.lastIndex(of: window.id.rawValue) ?? -1) + 1, coverage: 0)
        }
        let monitors = snapshot.monitors.map {
            PickerMonitor(id: $0.id.rawValue, bounds: $0.bounds.pickerRect, isPrimary: $0.isPrimary)
        }
        let cameFrom = lastLook.flatMap { $0.to == originID ? $0.from : nil }
        let decision = Look.decide(
            from: originID, direction: direction, cameFrom: cameFrom, windows: windows, monitors: monitors)
        let considered = "candidates \(decision.candidates.sorted())"
        guard let target = decision.target else {
            appendLog("look \(direction.keys): from window \(originID): nothing picked: \(decision.summary); \(considered)")
            return LookResult(decision: decision, change: nil)
        }
        appendLog("look \(direction.keys): from window \(originID): \(decision.summary); \(considered)")
        let change = try await focus(target)
        lastLook = (originID, target)
        return LookResult(decision: decision, change: change)
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
        let places = Dictionary(
            snapshot.windows.map { ($0.id.rawValue, $0.place) }, uniquingKeysWith: { first, _ in first })
        guard let next = focusOrder.last(where: { places[$0] == place }) else { return nil }
        try await focus(next)
        return next
    }

    // MARK: Workspaces

    /// Option+N: shows column `column` of the row showing now. Refuses a column outside
    /// the grid and changes nothing. Showing what is already showing sends nothing.
    /// Moves no window and resizes none. Undo shows what was showing before.
    @discardableResult
    public func showColumn(_ column: Int) async throws -> [Change] {
        let current = try await observeShowing()
        guard let cell = navigation.cell(column: column) else {
            appendLog("show column \(column): no such workspace; nothing changed")
            return []
        }
        return try await show(.cell(cell), replacing: current)
    }

    /// The bench key: shows the bench, a view of the undecided pile. The row Option+N acts
    /// in stays the one left, so the next column key lands back in it.
    @discardableResult
    public func showBench() async throws -> [Change] {
        try await show(.bench, replacing: try await observeShowing())
    }

    /// Option+Tab: shows the slot that was showing before, a cell or the bench. Pressed
    /// again it returns. Nothing happens when there is no earlier slot.
    @discardableResult
    public func showPrevious() async throws -> [Change] {
        let current = try await observeShowing()
        guard let previous = navigation.previous else {
            appendLog("show previous: no earlier workspace; nothing changed")
            return []
        }
        return try await show(previous, replacing: current)
    }

    /// Option+Shift+N: carries the focused window to column `column` of the row showing
    /// now and shows it there. One undoable change: undo shows the earlier slot and puts
    /// the window back where it was (its remembered home).
    ///
    /// A window carried into the vault column is not reported by any read afterwards,
    /// so Chord cannot move it back: undo reports it skipped. Leaving the vault is the
    /// user's alone.
    @discardableResult
    public func carryToColumn(_ column: Int) async throws -> [Change] {
        let current = try await observeShowing()
        guard let cell = navigation.cell(column: column) else {
            appendLog("carry to column \(column): no such workspace; nothing changed")
            return []
        }
        return try await carry(to: .cell(cell), replacing: current)
    }

    /// Shift+bench key: carries the focused window to the bench and shows the bench. The
    /// window's cell is its remembered home: undo returns it there.
    @discardableResult
    public func carryToBench() async throws -> [Change] {
        try await carry(to: .bench, replacing: try await observeShowing())
    }

    /// Option+W then h/j/k/l: shows the cell one step from the one showing now (the one last
    /// shown, when the bench or a workspace Chord did not create is showing). h/l are the
    /// previous/next column, k/j the previous/next row. A step off the edge of a grid that
    /// does not wrap changes nothing and says so. Moves no window and resizes none. Undo shows
    /// what was showing before.
    @discardableResult
    public func stepWorkspace(_ step: GridStep) async throws -> [Change] {
        let current = try await observeShowing()
        guard let target = stepTarget(step) else { return [] }
        return try await show(.cell(target), replacing: current)
    }

    /// Option+W then Shift+h/j/k/l: carries the focused window to the cell one step away and
    /// shows it there. One undoable change, like `carryToColumn`. A step whose target is the
    /// vault column is refused: nothing moves, nothing is shown, nothing can be undone.
    @discardableResult
    public func carryStepWorkspace(_ step: GridStep) async throws -> [Change] {
        let current = try await observeShowing()
        guard let target = stepTarget(step, carrying: true) else { return [] }
        return try await carry(to: .cell(target), replacing: current)
    }

    /// The cell one step from the remembered one, logged; nil (logged) when the step leaves a
    /// grid that does not wrap, or when a carry would enter the vault column.
    private func stepTarget(_ step: GridStep, carrying: Bool = false) -> GridCell? {
        let origin = navigation.grid.current
        let layout = navigation.layout
        guard let target = navigation.grid.neighbour(step) else {
            appendLog(
                "workspace step \(step) from \(layout.label(origin)): edge of the grid; nothing changed")
            return nil
        }
        if carrying && target.column == GridCell.columnCount {
            appendLog(
                "workspace carry step \(step) from \(layout.label(origin)): \(layout.label(target)) is the vault column; nothing changed")
            return nil
        }
        appendLog("workspace step \(step): \(layout.label(origin)) -> \(layout.label(target))")
        return target
    }

    /// Reads what is showing from the substrate, which is the truth (the user may have
    /// switched without Chord), and updates what Chord remembers.
    private func observeShowing() async throws -> GridSlot? {
        let slot = try await backend.showing()
        navigation.observe(slot)
        return slot
    }

    private func show(_ target: GridSlot, replacing current: GridSlot?) async throws -> [Change] {
        guard current != target else {
            appendLog("show workspace \(target.name): already showing; nothing changed")
            return []
        }
        let applied = try await run([.show(from: current, to: target)])
        undoStack.append(applied)
        return applied
    }

    private func carry(to target: GridSlot, replacing current: GridSlot?) async throws -> [Change] {
        guard let id = try await backend.focusedWindow() else { throw ExecutorError.noFocusedWindow }
        guard current != target else {
            appendLog("carry window \(id.rawValue): already in \(target.name); nothing changed")
            return []
        }
        // The focused window sits in what is showing. The move's `from` is a placeholder:
        // the backend reports the slot the window really left, and that is what is logged
        // and undone.
        let applied = try await run([
            .move(windowID: id.rawValue, from: current ?? .bench, to: target),
            .show(from: current, to: target),
        ])
        undoStack.append(applied)
        return applied
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
                appendLog("failed: \(change.logLine): \(error)")
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
            case .reshape(let id, let aspect, let area, let from, let to):
                let target = to.screenRect.roundedToIntegers()
                if from.screenRect != target {
                    changes.append(
                        .reshape(windowID: id, aspectDelta: aspect, areaDelta: area, from: from.screenRect, to: target))
                }
            case .restoreHome(let id, let from, let to):
                if from.place != to.place {
                    changes.append(.place(windowID: id, from: from.place, to: to.place))
                }
                let target = to.screenRect.roundedToIntegers()
                if from.frame.screenRect != target {
                    changes.append(.frame(windowID: id, from: from.frame.screenRect, to: target))
                }
            case .noop(let id):
                changes.append(.noop(windowID: id))
            }
        }
        return changes
    }

    private func perform(_ change: Change) async throws -> Change {
        switch change {
        case .place(let id, _, let to):
            let from = try await backend.moveWindow(WindowID(id), to: to)
            return .place(windowID: id, from: from, to: to)
        case .reshape(let id, let aspect, let area, _, let to):
            let target = to.roundedToIntegers()
            let from = try await backend.applyFrame(WindowID(id), to: target)
            return .reshape(windowID: id, aspectDelta: aspect, areaDelta: area, from: from, to: target)
        case .frame(let id, _, let to):
            let target = to.roundedToIntegers()
            let from = try await backend.applyFrame(WindowID(id), to: target)
            return .frame(windowID: id, from: from, to: target)
        case .focus(_, let to):
            let from = try await backend.focusWindow(WindowID(to))
            return .focus(from: from?.rawValue, to: to)
        case .noop(let id):
            return .noop(windowID: id)
        case .show(_, let to):
            let from = try await backend.show(to)
            return .show(from: from, to: to)
        case .move(let id, _, let to):
            let from = try await backend.moveWindow(WindowID(id), to: to)
            return .move(windowID: id, from: from, to: to)
        }
    }

    /// After an `.unknown` error: did the backend actually reach the change's target?
    private func landed(_ change: Change) async -> Bool {
        // Workspace changes are read back from the workspace side, whose window ids are
        // not the snapshot's (see `SplitBackend`).
        switch change {
        case .show(_, let to):
            return (try? await backend.showing()) == to
        case .move(let id, _, .cell(let cell)):
            return (try? await backend.listWindows(in: cell))?.contains(WindowID(id)) ?? false
        case .move:
            // No read lists the bench, so a lost reply cannot be resolved: report it.
            return false
        default:
            break
        }
        guard let snapshot = try? await backend.snapshot() else { return false }
        switch change {
        case .place(let id, _, let to):
            return snapshot.windows.first { $0.id.rawValue == id }?.place == to
        case .reshape(let id, _, _, _, let to):
            return snapshot.windows.first { $0.id.rawValue == id }?.bounds == to
        case .frame(let id, _, let to):
            return snapshot.windows.first { $0.id.rawValue == id }?.bounds == to
        case .focus(_, let to):
            return snapshot.focusedWindow?.rawValue == to
        case .noop:
            return true
        case .show, .move:
            return false  // handled above
        }
    }

    private func appendLog(_ line: String) {
        log.append(line)
        logSink?(line)
    }

    private func record(_ change: Change, label: String?) {
        appendLog(label.map { "\($0): \(change.logLine)" } ?? change.logLine)
        switch change {
        case .focus(let from, let to):
            if let from {
                focusOrder.removeAll { $0 == from }
                focusOrder.append(from)
            }
            focusOrder.removeAll { $0 == to }
            focusOrder.append(to)
            focusedID = to
        case .place(let id, _, let to) where id == focusedID:
            focusedPlace = to
        case .show(_, let to):
            navigation.observe(to)
        case .place, .frame, .reshape, .noop, .move:
            break
        }
    }
}
