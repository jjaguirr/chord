import ChordCore

/// A scripted failure for the next backend call that reaches the fake.
public enum FakeFault: Equatable, Sendable {
    /// Connection drops: the call throws `.notConnected` and nothing changes.
    /// Calls keep throwing until `reconnect()`.
    case disconnected
    /// The call times out before reaching the substrate: throws `.unknown`, nothing changes.
    case timeoutBeforeApply
    /// The call is applied, but its reply is lost: throws `.unknown` while the state changed.
    case lostReply
}

/// Deterministic in-memory `WorkspaceBackend` for tests. No clocks, no randomness,
/// no I/O. Faults are consumed one per call, in the order they were queued.
public actor FakeWorkspaceBackend: WorkspaceBackend {
    private var monitors: [MonitorSnapshot]
    private var windows: [WindowSnapshot]
    private var focused: WindowID?
    private var connected = true
    private var faults: [FakeFault] = []

    public init(monitors: [MonitorSnapshot], windows: [WindowSnapshot], focusedWindow: WindowID? = nil) {
        self.monitors = monitors
        self.windows = windows
        self.focused = focusedWindow
    }

    /// Queues faults; each applies to the next call that reaches the backend.
    public func queue(_ faults: [FakeFault]) {
        self.faults.append(contentsOf: faults)
    }

    public func snapshot() async throws -> BackendSnapshot {
        try guardConnected()
        try failIfReadFaulted()
        return BackendSnapshot(monitors: monitors, windows: windows, focusedWindow: focused)
    }

    @discardableResult
    public func moveWindow(_ id: WindowID, to workspace: Workspace) async throws -> Workspace {
        try guardConnected()
        guard let index = windows.firstIndex(where: { $0.id == id }) else {
            throw BackendError.unknownWindow(id)
        }
        let previous = windows[index].workspace
        let fault = consumeFaultValue()
        try failIfBeforeApply(fault)
        windows[index] = windows[index].with(workspace: workspace)
        try failIfReplyLost(fault)
        return previous
    }

    @discardableResult
    public func focusWindow(_ id: WindowID) async throws -> WindowID? {
        try guardConnected()
        guard windows.contains(where: { $0.id == id }) else {
            throw BackendError.unknownWindow(id)
        }
        let previous = focused
        let fault = consumeFaultValue()
        try failIfBeforeApply(fault)
        focused = id
        try failIfReplyLost(fault)
        return previous
    }

    public func reconnect() async throws {
        connected = true
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
        case nil:
            return
        }
    }

    private func failIfBeforeApply(_ fault: FakeFault?) throws {
        switch fault {
        case .disconnected:
            throw BackendError.notConnected
        case .timeoutBeforeApply:
            throw BackendError.unknown(reason: "timed out before apply")
        case .lostReply, nil:
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
    func with(workspace: Workspace) -> WindowSnapshot {
        WindowSnapshot(id: id, appName: appName, workspace: workspace, isFloating: isFloating, bounds: bounds)
    }
}
