import ChordCore
import Testing
@testable import Chord

@Suite("WorkspaceBackend contract (fake)")
struct WorkspaceBackendContractTests {
    private let frameA = ScreenRect(x: 0, y: 0, width: 333, height: 471)
    private let frameB = ScreenRect(x: 400, y: 0, width: 444, height: 630)

    private func makeBackend() -> FakeWorkspaceBackend {
        FakeWorkspaceBackend(
            monitors: [
                MonitorSnapshot(id: MonitorID(1), bounds: ScreenRect(x: 0, y: 0, width: 1728, height: 1117), isPrimary: true),
                MonitorSnapshot(id: MonitorID(2), bounds: ScreenRect(x: 1728, y: 0, width: 2560, height: 1440), isPrimary: false),
            ],
            windows: [
                WindowSnapshot(id: WindowID(10), appName: "Terminal", workspace: .one, isFloating: true, bounds: frameA),
                WindowSnapshot(id: WindowID(11), appName: "Safari", workspace: .two, isFloating: true, bounds: frameB),
            ],
            focusedWindow: WindowID(10)
        )
    }

    // MARK: Reads

    @Test func snapshotReportsMonitorsWindowsAndFocus() async throws {
        let snap = try await makeBackend().snapshot()

        #expect(snap.monitors.map(\.id) == [MonitorID(1), MonitorID(2)])
        #expect(snap.monitors.map(\.isPrimary) == [true, false])
        #expect(snap.monitors[1].bounds == ScreenRect(x: 1728, y: 0, width: 2560, height: 1440))
        #expect(snap.windows.map(\.id) == [WindowID(10), WindowID(11)])
        #expect(snap.windows[1].workspace == .two)
        #expect(snap.windows[1].bounds == frameB)
        #expect(snap.focusedWindow == WindowID(10))
    }

    @Test func snapshotWithoutFocusReportsNil() async throws {
        let backend = FakeWorkspaceBackend(monitors: [], windows: [])
        #expect(try await backend.snapshot().focusedWindow == nil)
    }

    // MARK: Mutations return inverses

    @Test func moveReturnsPreviousWorkspaceAndIsReversible() async throws {
        let backend = makeBackend()

        let left = try await backend.moveWindow(WindowID(10), to: .five)
        #expect(left == .one)
        #expect(try await backend.snapshot().windows[0].workspace == .five)

        try await backend.moveWindow(WindowID(10), to: left)
        #expect(try await backend.snapshot().windows[0].workspace == .one)
    }

    @Test func focusReturnsPreviousFocusAndIsReversible() async throws {
        let backend = makeBackend()

        let previous = try await backend.focusWindow(WindowID(11))
        #expect(previous == WindowID(10))
        #expect(try await backend.snapshot().focusedWindow == WindowID(11))

        try await backend.focusWindow(previous!)
        #expect(try await backend.snapshot().focusedWindow == WindowID(10))
    }

    @Test func unknownWindowIsRejectedAndChangesNothing() async throws {
        let backend = makeBackend()
        let before = try await backend.snapshot()

        await #expect(throws: BackendError.unknownWindow(WindowID(99))) {
            try await backend.moveWindow(WindowID(99), to: .three)
        }
        await #expect(throws: BackendError.unknownWindow(WindowID(99))) {
            try await backend.focusWindow(WindowID(99))
        }
        #expect(try await backend.snapshot() == before)
    }

    // MARK: Failure surfaces, never silent success

    @Test func disconnectSendsNothingAndStaysDisconnectedUntilReconnect() async throws {
        let backend = makeBackend()
        await backend.queue([.disconnected])
        await #expect(throws: BackendError.notConnected) {
            try await backend.moveWindow(WindowID(10), to: .four)
        }

        await #expect(throws: BackendError.notConnected) {
            try await backend.snapshot()
        }
        await #expect(throws: BackendError.notConnected) {
            try await backend.focusWindow(WindowID(11))
        }

        try await backend.reconnect()
        #expect(try await backend.snapshot().windows[0].workspace == .one)
        try await backend.moveWindow(WindowID(10), to: .four)
        #expect(try await backend.snapshot().windows[0].workspace == .four)
    }

    @Test func timeoutBeforeApplyIsUnknownAndChangesNothing() async throws {
        let backend = makeBackend()
        await backend.queue([.timeoutBeforeApply])

        await #expect(throws: BackendError.unknown(reason: "timed out before apply")) {
            try await backend.moveWindow(WindowID(10), to: .six)
        }
        #expect(try await backend.snapshot().windows[0].workspace == .one)
    }

    @Test func lostReplyIsUnknownButStateIsReadableAsTruth() async throws {
        let backend = makeBackend()
        await backend.queue([.lostReply])

        // The caller must not treat this as success, and must not assume failure:
        // the re-read snapshot is the source of truth.
        await #expect(throws: BackendError.unknown(reason: "reply lost after apply")) {
            try await backend.moveWindow(WindowID(10), to: .six)
        }
        #expect(try await backend.snapshot().windows[0].workspace == .six)
    }

    @Test func faultedReadIsUnknownAndNeverFabricatesASnapshot() async throws {
        let backend = makeBackend()
        await backend.queue([.timeoutBeforeApply, .lostReply])

        await #expect(throws: BackendError.unknown(reason: "snapshot not confirmed")) {
            try await backend.snapshot()
        }
        await #expect(throws: BackendError.unknown(reason: "snapshot not confirmed")) {
            try await backend.snapshot()
        }
        #expect(try await backend.snapshot().windows.count == 2)
    }

    @Test func faultsAreConsumedInQueueOrder() async throws {
        let backend = makeBackend()
        await backend.queue([.timeoutBeforeApply, .lostReply])

        await #expect(throws: BackendError.unknown(reason: "timed out before apply")) {
            try await backend.focusWindow(WindowID(11))
        }
        await #expect(throws: BackendError.unknown(reason: "reply lost after apply")) {
            try await backend.focusWindow(WindowID(11))
        }
        #expect(try await backend.snapshot().focusedWindow == WindowID(11))
    }
}
