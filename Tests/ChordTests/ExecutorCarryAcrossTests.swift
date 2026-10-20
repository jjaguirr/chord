import ChordCore
import Foundation
import Testing
@testable import Chord

@Suite("Executor cross-monitor carry (fake backend)")
struct ExecutorCarryAcrossTests {
    private let main = MonitorSnapshot(
        id: MonitorID(1), bounds: ScreenRect(x: 0, y: 25, width: 1440, height: 875), isPrimary: true)
    /// A larger monitor with a different scale, to its right; same coordinate space of points.
    private let wide = MonitorSnapshot(
        id: MonitorID(2), bounds: ScreenRect(x: 1440, y: 0, width: 2560, height: 1415), isPrimary: false)
    private let small = MonitorSnapshot(
        id: MonitorID(3), bounds: ScreenRect(x: 1440, y: 0, width: 800, height: 500), isPrimary: false)

    private func make(
        _ monitors: [MonitorSnapshot], frame: ScreenRect
    ) -> FakeWorkspaceBackend {
        FakeWorkspaceBackend(
            monitors: monitors,
            windows: [WindowSnapshot(
                id: WindowID(1), appName: "App", place: .bench, isFloating: true, bounds: frame)],
            focusedWindow: WindowID(1))
    }

    private func bounds(_ backend: FakeWorkspaceBackend) async throws -> ScreenRect? {
        try await backend.snapshot().windows.first?.bounds
    }

    @Test func crossesToTheAdjacentMonitorKeepingSizeAndUndoesBack() async throws {
        let start = ScreenRect(x: 1107, y: 300, width: 333, height: 471)
        let backend = make([main, wide], frame: start)
        let executor = Executor(backend: backend)

        let changes = try await executor.carryAcross(.l)

        #expect(changes.count == 1)
        #expect(try await bounds(backend) == ScreenRect(x: 1440, y: 300, width: 333, height: 471))
        #expect(await executor.log.contains { $0.hasPrefix("carry l across monitors 1 -> 2") })

        try await executor.undo()
        #expect(try await bounds(backend) == start)
    }

    @Test func clampsIntoTheTargetWhenItIsSmaller() async throws {
        let backend = make([main, small], frame: ScreenRect(x: 1107, y: 400, width: 333, height: 471))
        let executor = Executor(backend: backend)

        try await executor.carryAcross(.l)

        // 400 + 471 would overhang the 500-tall monitor: pulled up to fit.
        #expect(try await bounds(backend) == ScreenRect(x: 1440, y: 29, width: 333, height: 471))
    }

    @Test func comesBackAcrossLeftwardsFlushWithTheNearEdge() async throws {
        let backend = make([main, wide], frame: ScreenRect(x: 1440, y: 300, width: 333, height: 471))
        let executor = Executor(backend: backend)

        try await executor.carryAcross(.h)

        #expect(try await bounds(backend) == ScreenRect(x: 1107, y: 300, width: 333, height: 471))
    }

    @Test func noNeighbourMovesNothingAndLogsWhy() async throws {
        let start = ScreenRect(x: 1107, y: 300, width: 333, height: 471)
        let backend = make([main, wide], frame: start)
        let executor = Executor(backend: backend)

        #expect(try await executor.carryAcross(.h) == [])
        #expect(try await executor.carryAcross(.j) == [])
        #expect(try await bounds(backend) == start)
        #expect(await executor.log.filter { $0.contains("no monitor that way") }.count == 2)
        await #expect(throws: ExecutorError.nothingToUndo) { try await executor.undo() }
    }

    @Test func needsAFocusedWindow() async throws {
        let backend = FakeWorkspaceBackend(monitors: [main, wide], windows: [], focusedWindow: nil)
        let executor = Executor(backend: backend)
        await #expect(throws: ExecutorError.noFocusedWindow) { try await executor.carryAcross(.l) }
    }
}
