import ChordCore

/// The live `WorkspaceBackend`: windows and frames from one backend, workspaces from
/// another. In the app `frames` is `AXWindowBackend` (per-frame work, never AeroSpace;
/// spike 6b) and `workspaces` is `AeroSpaceBackend`, the interim engine. When Chord has its
/// own workspace model, only `workspaces` changes.
///
/// Window ids from the two sides are separate namespaces until the live check proves
/// AeroSpace's ids equal the Accessibility backend's (they do not today: that backend
/// numbers windows itself). So the Executor's workspace operations take a window id and
/// every other workspace fact from `workspaces` alone, and never mix the two.
public struct SplitBackend: WorkspaceBackend {
    private let frames: any WorkspaceBackend
    private let workspaces: any WorkspaceBackend

    public init(frames: any WorkspaceBackend, workspaces: any WorkspaceBackend) {
        self.frames = frames
        self.workspaces = workspaces
    }

    public func snapshot() async throws -> BackendSnapshot {
        try await frames.snapshot()
    }

    public func visibleSnapshot() async throws -> BackendSnapshot {
        try await frames.visibleSnapshot()
    }

    @discardableResult
    public func moveWindow(_ id: WindowID, to place: Place) async throws -> Place {
        try await workspaces.moveWindow(id, to: place)
    }

    @discardableResult
    public func show(_ slot: GridSlot) async throws -> GridSlot? {
        try await workspaces.show(slot)
    }

    public func showing() async throws -> GridSlot? {
        try await workspaces.showing()
    }

    public func focusedWindow() async throws -> WindowID? {
        try await workspaces.focusedWindow()
    }

    @discardableResult
    public func moveWindow(_ id: WindowID, to slot: GridSlot) async throws -> GridSlot {
        try await workspaces.moveWindow(id, to: slot)
    }

    public func listWindows(in cell: GridCell) async throws -> [WindowID] {
        try await workspaces.listWindows(in: cell)
    }

    @discardableResult
    public func applyFrame(_ id: WindowID, to frame: ScreenRect) async throws -> ScreenRect {
        try await frames.applyFrame(id, to: frame)
    }

    @discardableResult
    public func focusWindow(_ id: WindowID) async throws -> WindowID? {
        try await frames.focusWindow(id)
    }

    public func raiseWindow(_ id: WindowID) async throws {
        try await frames.raiseWindow(id)
    }

    public func reconnect() async throws {
        try await frames.reconnect()
        try await workspaces.reconnect()
    }
}
