import ChordCore

/// Opaque window identity as the substrate reports it.
public struct WindowID: Hashable, Sendable {
    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }
}

/// Opaque monitor identity as the substrate reports it.
public struct MonitorID: Hashable, Sendable {
    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }
}

/// A rectangle in logical screen points.
public struct ScreenRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct MonitorSnapshot: Equatable, Sendable {
    public let id: MonitorID
    public let bounds: ScreenRect
    public let isPrimary: Bool

    public init(id: MonitorID, bounds: ScreenRect, isPrimary: Bool) {
        self.id = id
        self.bounds = bounds
        self.isPrimary = isPrimary
    }
}

/// One window as the backend reports it. Titles are deliberately absent: agents
/// never see them, and nothing in the backend contract needs them.
public struct WindowSnapshot: Equatable, Sendable {
    public let id: WindowID
    public let appName: String
    public let place: Place
    public let isFloating: Bool
    public let bounds: ScreenRect

    public init(id: WindowID, appName: String, place: Place, isFloating: Bool, bounds: ScreenRect) {
        self.id = id
        self.appName = appName
        self.place = place
        self.isFloating = isFloating
        self.bounds = bounds
    }
}

/// A full read of the substrate. Callers re-read after any `.unknown` error
/// before deciding what to do next.
///
/// A window in the vault is never reported: the backend omits it, so it is an
/// unknown window to every caller.
public struct BackendSnapshot: Equatable, Sendable {
    public let monitors: [MonitorSnapshot]
    public let windows: [WindowSnapshot]
    public let focusedWindow: WindowID?
    /// Window ids from back to front.
    public let stackingOrder: [WindowID]

    public init(
        monitors: [MonitorSnapshot], windows: [WindowSnapshot], focusedWindow: WindowID?,
        stackingOrder: [WindowID] = []
    ) {
        self.monitors = monitors
        self.windows = windows
        self.focusedWindow = focusedWindow
        self.stackingOrder = stackingOrder
    }
}

/// Failure taxonomy. Every backend call either returns a confirmed result or
/// throws one of these; a failed call is never reported as success.
public enum BackendError: Error, Equatable, Sendable {
    /// No connection. The request was not sent; nothing changed.
    case notConnected
    /// The named window is not known to the substrate. Nothing changed.
    case unknownWindow(WindowID)
    /// The request was sent or may have been applied, but no confirmed result
    /// arrived. The substrate may or may not have changed. Re-read the snapshot
    /// before acting again; never assume either outcome.
    case unknown(reason: String)
}

/// The one boundary to the workspace substrate. Only `Sources/Chord/Executor/`
/// may call these methods to change windows.
///
/// Mutations return the state they replaced so the Executor can record an
/// inverse for every action it applies.
public protocol WorkspaceBackend: Sendable {
    func snapshot() async throws -> BackendSnapshot

    /// Like `snapshot()`, but lists every window currently visible on any monitor, not
    /// only the ones the backend already tracks. Minimized, hidden, and other-Space
    /// windows are left out where the substrate can tell. Costs more than `snapshot()`,
    /// so only Look asks for it. A backend that already lists every window answers
    /// with its ordinary snapshot.
    func visibleSnapshot() async throws -> BackendSnapshot

    /// Moves a window to another place and returns the place it left.
    @discardableResult
    func moveWindow(_ id: WindowID, to place: Place) async throws -> Place

    /// Sets a window's frame exactly as given and returns the frame it replaced.
    /// The Executor rounds before calling; the backend does not reinterpret.
    @discardableResult
    func applyFrame(_ id: WindowID, to frame: ScreenRect) async throws -> ScreenRect

    /// Focuses a window and raises that one window only (AXRaise on the window,
    /// never an app-wide activation that pops up its siblings). Returns the
    /// previously focused window, if any.
    @discardableResult
    func focusWindow(_ id: WindowID) async throws -> WindowID?

    /// Raises one window to the front without changing focus.
    func raiseWindow(_ id: WindowID) async throws

    /// Re-establishes the connection after `.notConnected`. Idempotent when connected.
    func reconnect() async throws
}

extension WorkspaceBackend {
    public func visibleSnapshot() async throws -> BackendSnapshot {
        try await snapshot()
    }
}
