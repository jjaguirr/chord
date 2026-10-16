import ChordCore

/// A scripted failure for the next backend call that reaches the 
public enum FakeFault: Equatable, Sendable {
    /// Connection drops: the call throws `.notConnected` and nothing changes.
    /// Calls keep throwing until `reconnect()`.
    case disconnected
    /// The call times out before reaching the substrate: throws `.unknown`, nothing changes.
    case timeoutBeforeApply
    /// The call is applied, but its reply is lost: throws `.unknown` while the state changed.
    case lostReply
    /// The call succeeds normally but still consumes this queue slot, to aim a later fault.
    case proceed
}

/// Deterministic in-memory `WorkspaceBackend` for tests. No clocks, no randomness,
/// no I/O. Faults are consumed one per call, in the order they were queued.
public actor FakeWorkspaceBackend: WorkspaceBackend {
    private var monitors: [MonitorSnapshot]
    private var windows: [WindowSnapshot]
    private var focused: WindowID?
    private var stacking: [WindowID]
    private var connected = true
    private var faults: [FakeFault] = []

    public init(monitors: [MonitorSnapshot], windows: [WindowSnapshot], focusedWindow: WindowID? = nil) {
        self.monitors = monitors
        self.windows = windows
        self.focused = focusedWindow
        self.stacking = windows.map(\.id)
    }

    /// Queues faults; each applies to the next call that reaches the backend.
    public func queue(_ faults: [FakeFault]) {
        self.faults.append(contentsOf: faults)
    }

    public func snapshot() async throws -> BackendSnapshot {
        try guardConnected()
        try failIfReadFaulted()
        return BackendSnapshot(monitors: monitors, windows: windows, focusedWindow: focused, stackingOrder: stacking)
    }

    @discardableResult
    public func moveWindow(_ id: WindowID, to place: Place) async throws -> Place {
        try mutate(id) { index in
            let previous = windows[index].place
            windows[index] = windows[index].with(place: place)
            return previous
        }
    }

    @discardableResult
    public func applyFrame(_ id: WindowID, to frame: ScreenRect) async throws -> ScreenRect {
        try mutate(id) { index in
            let previous = windows[index].bounds
            windows[index] = windows[index].with(bounds: frame)
            return previous
        }
    }

    @discardableResult
    public func focusWindow(_ id: WindowID) async throws -> WindowID? {
        try mutate(id) { _ in
            let previous = focused
            focused = id
            bringToFront(id)
            return previous
        }
    }

    public func raiseWindow(_ id: WindowID) async throws {
        try mutate(id) { _ in bringToFront(id) }
    }

    public func reconnect() async throws {
        connected = true
    }

    /// Applies `body` to the window's index with the scripted fault ordering:
    /// guard, unknown-window check, fault, apply, lost-reply.
    private func mutate<T>(_ id: WindowID, _ body: (Int) -> T) throws -> T {
        try guardConnected()
        guard let index = windows.firstIndex(where: { $0.id == id }) else {
            throw BackendError.unknownWindow(id)
        }
        let fault = consumeFaultValue()
        try failIfBeforeApply(fault)
        let result = body(index)
        try failIfReplyLost(fault)
        return result
    }

    private func bringToFront(_ id: WindowID) {
        stacking.removeAll { $0 == id }
        stacking.append(id)
    }

    private func guardConnected() throws {
        if !connected { throw BackendError.notConnected }
    }

    private func consumeFaultValue() -> FakeFault? {
        guard !faults.isEmpty else { return nil }
        let fault = faults.removeFirst()
        if fault == .disconnected { connected = false }
        return fault
    }

    private func failIfReadFaulted() throws {
        switch consumeFaultValue() {
        case .disconnected:
            throw BackendError.notConnected
        case .timeoutBeforeApply, .lostReply:
            throw BackendError.unknown(reason: "snapshot not confirmed")
        case .proceed, nil:
            return
        }
    }

    private func failIfBeforeApply(_ fault: FakeFault?) throws {
        switch fault {
        case .disconnected:
            throw BackendError.notConnected
        case .timeoutBeforeApply:
            throw BackendError.unknown(reason: "timed out before apply")
        case .lostReply, .proceed, nil:
            return
        }
    }

    private func failIfReplyLost(_ fault: FakeFault?) throws {
        if fault == .lostReply {
            throw BackendError.unknown(reason: "reply lost after apply")
        }
    }
}

private extension WindowSnapshot {
    func with(place: Place) -> WindowSnapshot {
        WindowSnapshot(id: id, appName: appName, place: place, isFloating: isFloating, bounds: bounds)
    }

    func with(bounds: ScreenRect) -> WindowSnapshot {
        WindowSnapshot(id: id, appName: appName, place: place, isFloating: isFloating, bounds: bounds)
    }
}

extension FakeWorkspaceBackend {
    /// Simulates the user closing a window; not a Chord change, so it consumes no fault.
    public func removeWindow(_ id: WindowID) {
        windows.removeAll { $0.id == id }
        stacking.removeAll { $0 == id }
        if focused == id { focused = nil }
    }
}
