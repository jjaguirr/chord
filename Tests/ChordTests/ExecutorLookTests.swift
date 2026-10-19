import ChordCore
import Foundation
import Testing
@testable import Chord

@Suite("Executor look (fake backend)")
struct ExecutorLookTests {
    private let leftMonitor = MonitorSnapshot(
        id: MonitorID(1), bounds: ScreenRect(x: 0, y: 0, width: 1000, height: 800), isPrimary: true)
    private let rightMonitor = MonitorSnapshot(
        id: MonitorID(2), bounds: ScreenRect(x: 1000, y: 0, width: 1000, height: 800), isPrimary: false)

    private func window(_ id: Int, _ x: Double, _ y: Double, floating: Bool = true) -> WindowSnapshot {
        WindowSnapshot(
            id: WindowID(id), appName: "App\(id)", place: .bench, isFloating: floating,
            bounds: ScreenRect(x: x, y: y, width: 96, height: 96))
    }

    private func makeBackend(
        _ windows: [WindowSnapshot], focused: Int? = 1, monitors: [MonitorSnapshot]? = nil
    ) -> FakeWorkspaceBackend {
        FakeWorkspaceBackend(
            monitors: monitors ?? [leftMonitor, rightMonitor], windows: windows,
            focusedWindow: focused.map { WindowID($0) })
    }

    private func focused(_ backend: FakeWorkspaceBackend) async throws -> Int? {
        try await backend.snapshot().focusedWindow?.rawValue
    }

    @Test func focusMovesToTheNearestWindowInTheDirectionAndIsLogged() async throws {
        let backend = makeBackend([window(1, 100, 352), window(2, 400, 352), window(3, 700, 352)])
        let executor = Executor(backend: backend)

        let result = try await executor.look(.l)

        #expect(result.decision.outcome == .picked(2, .sameMonitor))
        #expect(result.change == .focus(from: 1, to: 2))
        #expect(try await focused(backend) == 2)
        let log = await executor.log
        #expect(log.contains("look l: from window 1: picked window 2 on the same monitor; candidates [2, 3]"))
        #expect(log.contains("focus window 2 (was 1)"))
    }

    @Test func atTheEdgeFocusCrossesToTheAdjacentMonitor() async throws {
        let backend = makeBackend([window(1, 800, 352), window(2, 1100, 352), window(3, 1500, 352)])
        let executor = Executor(backend: backend)

        let result = try await executor.look(.l)

        #expect(result.decision.outcome == .picked(2, .adjacentMonitor))
        #expect(try await focused(backend) == 2)
        #expect(await executor.log.contains { $0.contains("picked window 2 on the adjacent monitor") })
    }

    @Test func nothingThatWayChangesNothingAndLogsWhy() async throws {
        let backend = makeBackend([window(1, 100, 352), window(2, 400, 352)])
        let executor = Executor(backend: backend)

        let result = try await executor.look(.h)

        #expect(result.change == nil)
        #expect(result.decision.outcome == .nothing(.noMonitorInDirection))
        #expect(try await focused(backend) == 1)
        let log = await executor.log
        #expect(log.count == 1)
        #expect(log[0].hasPrefix("look h: from window 1: nothing picked: nothing that way on this monitor and no monitor that way"))
        // Undo has nothing to undo: a miss is not a change.
        await #expect(throws: ExecutorError.nothingToUndo) { try await executor.undo() }
    }

    @Test func aLoneWindowLogsThatThereIsNoOtherWindow() async throws {
        let executor = Executor(backend: makeBackend([window(1, 100, 352)]))

        let result = try await executor.look(.l)

        #expect(result.change == nil)
        #expect(await executor.log.contains { $0.contains("no other visible window") })
    }

    @Test func noFocusedWindowThrowsAndChangesNothing() async throws {
        let backend = makeBackend([window(1, 100, 352), window(2, 400, 352)], focused: nil)
        let executor = Executor(backend: backend)

        await #expect(throws: ExecutorError.noFocusedWindow) { try await executor.look(.l) }
        #expect(try await focused(backend) == nil)
    }

    @Test func lookWithoutAccessibilityThrowsNotConnected() async throws {
        let backend = makeBackend([window(1, 100, 352), window(2, 400, 352)])
        await backend.queue([.disconnected])
        let executor = Executor(backend: backend)

        await #expect(throws: BackendError.notConnected) { try await executor.look(.l) }
        try await backend.reconnect()
        #expect(try await focused(backend) == 1)
    }

    @Test func lookIsUndoableAsOneFocusChange() async throws {
        let backend = makeBackend([window(1, 100, 352), window(2, 400, 352)])
        let executor = Executor(backend: backend)
        try await executor.look(.l)

        try await executor.undo()

        #expect(try await focused(backend) == 1)
    }

    @Test func theOppositeKeyReturnsToTheWindowYouLeft() async throws {
        let backend = makeBackend([window(1, 100, 352), window(2, 400, 352), window(3, 700, 352)])
        let executor = Executor(backend: backend)

        try await executor.look(.l)
        try await executor.look(.l)
        #expect(try await focused(backend) == 3)
        try await executor.look(.h)
        try await executor.look(.h)

        #expect(try await focused(backend) == 1)
    }

    @Test func aWindowTheBackendDoesNotReportIsNeverACandidate() async throws {
        // Minimized, hidden and other-Space windows are not in the visible snapshot, so a
        // closer window that is not listed cannot take focus.
        let backend = makeBackend([window(1, 100, 352), window(3, 700, 352)])
        let executor = Executor(backend: backend)

        let result = try await executor.look(.l)

        #expect(result.decision.target == 3)
        #expect(result.decision.candidates == [3])
    }

    @Test func aMoreRecentlyFocusedWindowWinsATieInTheDirection() async throws {
        // 2 and 3 tie in every score; 3 was focused more recently, so it wins.
        let backend = makeBackend([window(1, 100, 352), window(2, 400, 200), window(3, 400, 504)])
        let executor = Executor(backend: backend)
        try await executor.focus(3)
        try await executor.focus(1)

        let result = try await executor.look(.l)

        #expect(result.decision.target == 3)
    }
}
