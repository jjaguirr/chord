import ChordCore
import Foundation
import Testing
@testable import Chord

@Suite("Executor motion (fake backend)")
struct ExecutorMotionTests {
    private let visible = ScreenRect(x: 0, y: 25, width: 1440, height: 875)
    private let start = ScreenRect(x: 100, y: 100, width: 333, height: 471)

    private func makeBackend(
        frame: ScreenRect? = nil, focused: Bool = true, supportsPlaces: Bool = true
    ) -> FakeWorkspaceBackend {
        FakeWorkspaceBackend(
            monitors: [MonitorSnapshot(id: MonitorID(1), bounds: visible, isPrimary: true)],
            windows: [WindowSnapshot(
                id: WindowID(1), appName: "App", place: .bench, isFloating: true, bounds: frame ?? start)],
            focusedWindow: focused ? WindowID(1) : nil,
            supportsPlaces: supportsPlaces)
    }

    private func bounds(_ backend: FakeWorkspaceBackend) async throws -> ScreenRect? {
        try await backend.snapshot().windows.first?.bounds
    }

    // MARK: Frame run

    @Test func aFrameRunAppliesRoundedStepsAndClosesAsOneUndoableChange() async throws {
        let backend = makeBackend()
        let executor = Executor(backend: backend)

        let context = try await executor.beginFrameRun(label: "unfold")
        #expect(context == WindowContext(id: 1, bounds: start, visibleFrame: visible))
        try await executor.stepFrameRun(to: ScreenRect(x: 10.4, y: 30.6, width: 400.2, height: 300.5))
        try await executor.stepFrameRun(to: ScreenRect(x: 500, y: 200, width: 444, height: 630))
        let closed = await executor.endFrameRun()

        #expect(closed == [.frame(windowID: 1, from: start, to: ScreenRect(x: 500, y: 200, width: 444, height: 630))])
        #expect(try await bounds(backend) == ScreenRect(x: 500, y: 200, width: 444, height: 630))
        let log = await executor.log
        #expect(log.filter { $0.hasPrefix("unfold:") }.count == 1)

        try await executor.undo()
        #expect(try await bounds(backend) == start)
    }

    @Test func aStepEqualToTheLastAppliedFrameNeverReachesTheBackend() async throws {
        let backend = makeBackend()
        let executor = Executor(backend: backend)
        _ = try await executor.beginFrameRun(label: "unfold")
        let target = ScreenRect(x: 10, y: 30, width: 400, height: 300)
        try await executor.stepFrameRun(to: target)

        await backend.queue([.timeoutBeforeApply])
        try await executor.stepFrameRun(to: ScreenRect(x: 10.2, y: 29.8, width: 399.9, height: 300.1))

        // The queued fault is still waiting: the skipped step never made a backend call.
        await #expect(throws: BackendError.unknown(reason: "snapshot not confirmed")) {
            _ = try await backend.snapshot()
        }
        #expect(try await bounds(backend) == target)
    }

    @Test func aStepWithoutARunThrows() async throws {
        let executor = Executor(backend: makeBackend())
        await #expect(throws: ExecutorError.noFrameRun) {
            try await executor.stepFrameRun(to: ScreenRect(x: 0, y: 0, width: 10, height: 10))
        }
    }

    @Test func aRunThatEndsWhereItBeganLeavesNothingToUndo() async throws {
        let executor = Executor(backend: makeBackend())
        _ = try await executor.beginFrameRun(label: "unfold")

        #expect(await executor.endFrameRun() == [])
        await #expect(throws: ExecutorError.nothingToUndo) { try await executor.undo() }
    }

    @Test func aFailedStepStillLetsUndoRestoreTheStart() async throws {
        let backend = makeBackend()
        let executor = Executor(backend: backend)
        _ = try await executor.beginFrameRun(label: "unfold")
        await backend.queue([.lostReply])
        await #expect(throws: BackendError.unknown(reason: "reply lost after apply")) {
            try await executor.stepFrameRun(to: ScreenRect(x: 10, y: 30, width: 400, height: 300))
        }

        let closed = await executor.endFrameRun()
        #expect(closed.count == 1)
        try await executor.undo()
        #expect(try await bounds(backend) == start)
        #expect(await executor.log.contains { $0.hasPrefix("failed: unfold") })
    }

    @Test func aRunNeedsAFocusedWindow() async throws {
        let executor = Executor(backend: makeBackend(focused: false))
        await #expect(throws: ExecutorError.noFocusedWindow) {
            _ = try await executor.beginFrameRun(label: "unfold")
        }
    }

    // MARK: Carry

    @Test func carryMovesTheFocusedWindowAndKeepsItsSize() async throws {
        let backend = makeBackend()
        let executor = Executor(backend: backend)

        let changes = try await executor.carry(dx: 10, dy: -20)

        #expect(changes.count == 1)
        #expect(try await bounds(backend) == ScreenRect(x: 110, y: 80, width: 333, height: 471))
    }

    @Test func carryNeverPushesAWindowFurtherPastAnEdge() async throws {
        let backend = makeBackend(frame: ScreenRect(x: 1100, y: 100, width: 333, height: 471))
        let executor = Executor(backend: backend)

        try await executor.carry(dx: 30, dy: 0)

        // The visible frame ends at 1440: the window stops flush against it.
        #expect(try await bounds(backend)?.x == 1107)
    }

    @Test func carryNeitherPullsBackNorPushesFurtherAWindowTheUserPutOffscreen() async throws {
        let backend = makeBackend(frame: ScreenRect(x: 1400, y: 100, width: 333, height: 471))
        let executor = Executor(backend: backend)

        #expect(try await executor.carry(dx: 10, dy: 0) == [])
        #expect(try await bounds(backend)?.x == 1400)
        try await executor.carry(dx: -10, dy: 0)
        #expect(try await bounds(backend)?.x == 1390)
    }

    @Test func aHeldCarryExtendsOneUndoEntry() async throws {
        let backend = makeBackend()
        let executor = Executor(backend: backend)

        try await executor.carry(dx: 10, dy: 0)
        try await executor.carry(dx: 20, dy: 0)
        try await executor.carry(dx: 30, dy: 0)
        #expect(try await bounds(backend)?.x == 160)

        try await executor.undo()
        #expect(try await bounds(backend) == start)
        await #expect(throws: ExecutorError.nothingToUndo) { try await executor.undo() }
    }

    @Test func aCarryAfterTheUserMovedTheWindowStartsANewUndoEntry() async throws {
        let backend = makeBackend()
        let executor = Executor(backend: backend)
        try await executor.carry(dx: 10, dy: 0)
        let byMouse = ScreenRect(x: 600, y: 300, width: 333, height: 471)
        try await backend.applyFrame(WindowID(1), to: byMouse)

        try await executor.carry(dx: 10, dy: 0)
        try await executor.undo()

        #expect(try await bounds(backend) == byMouse)
    }

    @Test func carryNeedsAFocusedWindow() async throws {
        let executor = Executor(backend: makeBackend(focused: false))
        await #expect(throws: ExecutorError.noFocusedWindow) {
            try await executor.carry(dx: 10, dy: 0)
        }
    }

    // MARK: Reshape

    @Test func reshapeFocusedWidensAroundTheCenterInsideTheMonitor() async throws {
        let backend = makeBackend()
        let executor = Executor(backend: backend)

        let changes = try await executor.reshapeFocused(
            aspectDelta: 0.05, areaDelta: 0, minimumSize: ActionSize(width: 120, height: 80))

        #expect(changes.count == 1)
        let found = try await bounds(backend)
        let after = try #require(found)
        #expect(after.width > start.width)
        #expect(after.height < start.height)
        #expect(abs((after.x + after.width / 2) - (start.x + start.width / 2)) <= 1)
        try await executor.undo()
        #expect(try await bounds(backend) == start)
    }

    // MARK: Places

    @Test func placingOnABackendWithoutPlacesLogsAndLeavesTheWindow() async throws {
        let backend = makeBackend(supportsPlaces: false)
        let executor = Executor(backend: backend)

        let changes = try await executor.placeFocused(.workspace(.three))

        #expect(changes == [])
        #expect(try await backend.snapshot().windows.first?.place == .bench)
        #expect(await executor.log.contains { $0.hasPrefix("place:") && $0.contains("no places") })
    }

    @Test func placingMovesTheFocusedWindowWhenTheBackendHasPlaces() async throws {
        let backend = makeBackend()
        let executor = Executor(backend: backend)

        try await executor.placeFocused(.workspace(.three))
        #expect(try await backend.snapshot().windows.first?.place == .workspace(.three))

        try await executor.undo()
        #expect(try await backend.snapshot().windows.first?.place == .bench)
    }
}
