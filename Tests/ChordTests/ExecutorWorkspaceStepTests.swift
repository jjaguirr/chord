import ChordCore
import Foundation
import Testing
@testable import Chord

private final class LogBox: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        lines.append(line)
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

/// The Option+W layer's two Executor operations: step to the neighbouring cell, and carry the
/// focused window along. Same fake backend and conventions as `ExecutorWorkspaceTests`.
@Suite("Executor workspace steps")
struct ExecutorWorkspaceStepTests {
    private let frame = ScreenRect(x: 100, y: 100, width: 600, height: 400)
    private let monitor = MonitorSnapshot(
        id: MonitorID(1), bounds: ScreenRect(x: 0, y: 25, width: 1440, height: 875), isPrimary: true)

    private func cell(_ row: Int, _ column: Int) -> GridCell {
        guard let cell = GridCell(row: row, column: column) else {
            fatalError("test cell r\(row)-\(column) is out of range")
        }
        return cell
    }

    /// Window 1 in r1-1 (focused), 2 on the bench.
    private func makeBackend() -> FakeWorkspaceBackend {
        func window(_ id: Int, _ place: Place) -> WindowSnapshot {
            WindowSnapshot(id: WindowID(id), appName: "App", place: place, isFloating: true, bounds: frame)
        }
        return FakeWorkspaceBackend(
            monitors: [monitor],
            windows: [window(1, .workspace(.one)), window(2, .bench)],
            focusedWindow: WindowID(1))
    }

    private func makeExecutor(
        _ backend: FakeWorkspaceBackend, layout: WorkspaceLayout = .defaults
    ) -> (Executor, LogBox) {
        let log = LogBox()
        return (Executor(backend: backend, workspaces: layout, logSink: { log.append($0) }), log)
    }

    private func start(_ backend: FakeWorkspaceBackend, at cell: GridCell) async {
        await backend.switchOutsideChord(to: .cell(cell))
    }

    private func bounds(_ backend: FakeWorkspaceBackend) async throws -> [Int: ScreenRect] {
        Dictionary(
            uniqueKeysWithValues: try await backend.snapshot().windows.map { ($0.id.rawValue, $0.bounds) })
    }

    // MARK: Step

    @Test func lAndHStepColumnsAndJAndKStepRowsInTheRowShowingNow() async throws {
        let backend = makeBackend()
        await start(backend, at: cell(2, 4))
        let (executor, _) = makeExecutor(backend)

        try await executor.stepWorkspace(.right)
        #expect(try await backend.showing() == .cell(cell(2, 5)))
        try await executor.stepWorkspace(.left)
        try await executor.stepWorkspace(.left)
        #expect(try await backend.showing() == .cell(cell(2, 3)))
        try await executor.stepWorkspace(.down)
        #expect(try await backend.showing() == .cell(cell(3, 3)))
        try await executor.stepWorkspace(.up)
        try await executor.stepWorkspace(.up)
        #expect(try await backend.showing() == .cell(cell(1, 3)))
    }

    @Test func aStepIsAnExecutorShowChangeWithALogLineAndOneUndo() async throws {
        let backend = makeBackend()
        let (executor, log) = makeExecutor(backend)

        let changes = try await executor.stepWorkspace(.down)

        #expect(changes == [.show(from: .cell(cell(1, 1)), to: .cell(cell(2, 1)))])
        #expect(log.all == ["workspace step down: r1-1 -> r2-1", "show workspace r2-1 (was r1-1)"])

        let undone = try await executor.undo()

        #expect(undone == [.show(from: .cell(cell(2, 1)), to: .cell(cell(1, 1)))])
        #expect(try await backend.showing() == .cell(cell(1, 1)))
        #expect(log.all.last == "undo: show workspace r1-1 (was r2-1)")
        await #expect(throws: ExecutorError.nothingToUndo) { try await executor.undo() }
    }

    @Test func aStepMovesAndResizesNoWindow() async throws {
        let backend = makeBackend()
        let (executor, _) = makeExecutor(backend)
        let before = try await bounds(backend)

        try await executor.stepWorkspace(.right)
        try await executor.stepWorkspace(.down)
        try await executor.stepWorkspace(.up)
        try await executor.stepWorkspace(.left)

        #expect(try await bounds(backend) == before)
        #expect(await backend.slot(of: WindowID(1)) == .cell(cell(1, 1)))
    }

    @Test func stepsClampAtEveryEdgeByDefaultAndLogWhyNothingChanged() async throws {
        let backend = makeBackend()
        let (executor, log) = makeExecutor(backend)

        #expect(try await executor.stepWorkspace(.left) == [])
        #expect(try await executor.stepWorkspace(.up) == [])
        #expect(try await backend.showing() == .cell(cell(1, 1)))
        #expect(log.all == [
            "workspace step left from r1-1: edge of the grid; nothing changed",
            "workspace step up from r1-1: edge of the grid; nothing changed",
        ])
        await #expect(throws: ExecutorError.nothingToUndo) { try await executor.undo() }

        await start(backend, at: cell(3, GridCell.columnCount))
        #expect(try await executor.stepWorkspace(.right) == [])
        #expect(try await executor.stepWorkspace(.down) == [])
        #expect(try await backend.showing() == .cell(cell(3, GridCell.columnCount)))
    }

    @Test func anObservedCellOutsideTheConfiguredGridIsNotUsedAsAStaleStepOrigin() async throws {
        let backend = makeBackend()
        let (executor, log) = makeExecutor(backend, layout: WorkspaceLayout(rows: 2))
        await start(backend, at: cell(2, 1))
        try await executor.stepWorkspace(.right)
        await start(backend, at: cell(3, 1))

        #expect(try await executor.stepWorkspace(.right) == [])
        #expect(try await backend.showing() == .cell(cell(3, 1)))
        #expect(log.all.last == "workspace step right from r3-1: outside the configured grid; nothing changed")
    }

    @Test func theRowCountComesFromTheLayout() async throws {
        let backend = makeBackend()
        let (executor, _) = makeExecutor(backend, layout: WorkspaceLayout(rows: 2))

        try await executor.stepWorkspace(.down)
        #expect(try await executor.stepWorkspace(.down) == [])

        #expect(try await backend.showing() == .cell(cell(2, 1)))
    }

    @Test func wrapContinuesFromTheOppositeEdge() async throws {
        let backend = makeBackend()
        let (executor, _) = makeExecutor(backend, layout: WorkspaceLayout(rows: 3, wrap: true))

        try await executor.stepWorkspace(.left)
        #expect(try await backend.showing() == .cell(cell(1, GridCell.columnCount)))
        try await executor.stepWorkspace(.up)
        #expect(try await backend.showing() == .cell(cell(3, GridCell.columnCount)))
        try await executor.stepWorkspace(.right)
        #expect(try await backend.showing() == .cell(cell(3, 1)))
        try await executor.stepWorkspace(.down)
        #expect(try await backend.showing() == .cell(cell(1, 1)))
    }

    @Test func aRowStepThatWrapsOntoTheSameRowIsAnAlreadyShowingNoOp() async throws {
        let backend = makeBackend()
        let (executor, log) = makeExecutor(backend, layout: WorkspaceLayout(rows: 1, wrap: true))

        #expect(try await executor.stepWorkspace(.down) == [])

        #expect(log.all.last == "show workspace r1-1: already showing; nothing changed")
    }

    @Test func logLinesCarryTheRowNames() async throws {
        let backend = makeBackend()
        let layout = WorkspaceLayout(rows: 3, rowNames: ["work", "home", "play"])
        let (executor, log) = makeExecutor(backend, layout: layout)

        try await executor.stepWorkspace(.down)
        try await executor.stepWorkspace(.up)
        try await executor.stepWorkspace(.up)

        #expect(log.all.contains("workspace step down: r1-1 (row \"work\") -> r2-1 (row \"home\")"))
        #expect(log.all.last == "workspace step up from r1-1 (row \"work\"): edge of the grid; nothing changed")
    }

    @Test func fromTheBenchAStepStartsAtTheRememberedCell() async throws {
        let backend = makeBackend()
        await start(backend, at: cell(2, 3))
        let (executor, _) = makeExecutor(backend)
        try await executor.showBench()

        try await executor.stepWorkspace(.right)

        #expect(try await backend.showing() == .cell(cell(2, 4)))
    }

    @Test func aStepFollowsASwitchMadeOutsideChord() async throws {
        let backend = makeBackend()
        let (executor, _) = makeExecutor(backend)
        try await executor.stepWorkspace(.right)
        await start(backend, at: cell(3, 7))

        try await executor.stepWorkspace(.left)

        #expect(try await backend.showing() == .cell(cell(3, 6)))
    }

    @Test func theVaultColumnIsAnOrdinaryColumnToStepOnto() async throws {
        let backend = makeBackend()
        await start(backend, at: cell(1, GridCell.columnCount - 1))
        let (executor, _) = makeExecutor(backend)

        try await executor.stepWorkspace(.right)

        #expect(try await backend.showing() == .cell(cell(1, GridCell.columnCount)))
    }

    // MARK: Carry along

    @Test func shiftCarriesTheFocusedWindowToTheNeighbourAndFollowsIt() async throws {
        let backend = makeBackend()
        let (executor, log) = makeExecutor(backend)
        let before = try await bounds(backend)[1]

        let changes = try await executor.carryStepWorkspace(.right)

        #expect(changes == [
            .move(windowID: 1, from: .cell(cell(1, 1)), to: .cell(cell(1, 2))),
            .show(from: .cell(cell(1, 1)), to: .cell(cell(1, 2))),
        ])
        #expect(await backend.slot(of: WindowID(1)) == .cell(cell(1, 2)))
        #expect(try await backend.showing() == .cell(cell(1, 2)))
        #expect(log.all == [
            "workspace step right: r1-1 -> r1-2", "move window 1: r1-1 -> r1-2",
            "show workspace r1-2 (was r1-1)",
        ])
        #expect(try await bounds(backend)[1] == before)
    }

    @Test func carryingDownMovesTheWindowToTheNextRow() async throws {
        let backend = makeBackend()
        let (executor, _) = makeExecutor(backend)

        try await executor.carryStepWorkspace(.down)

        #expect(await backend.slot(of: WindowID(1)) == .cell(cell(2, 1)))
        #expect(try await backend.showing() == .cell(cell(2, 1)))
    }

    @Test func carryingAlongIsOneUndoThatPutsTheWindowBack() async throws {
        let backend = makeBackend()
        let (executor, _) = makeExecutor(backend)
        try await executor.carryStepWorkspace(.down)

        try await executor.undo()

        #expect(await backend.slot(of: WindowID(1)) == .cell(cell(1, 1)))
        #expect(try await backend.showing() == .cell(cell(1, 1)))
        await #expect(throws: ExecutorError.nothingToUndo) { try await executor.undo() }
    }

    @Test func carryingOffTheEdgeMovesNothingAndShowsNothing() async throws {
        let backend = makeBackend()
        let (executor, log) = makeExecutor(backend)

        #expect(try await executor.carryStepWorkspace(.up) == [])

        #expect(await backend.slot(of: WindowID(1)) == .cell(cell(1, 1)))
        #expect(try await backend.showing() == .cell(cell(1, 1)))
        #expect(log.all == ["workspace step up from r1-1: edge of the grid; nothing changed"])
        await #expect(throws: ExecutorError.nothingToUndo) { try await executor.undo() }
    }

    @Test func carryingWithNoFocusedWindowThrowsAndMovesNothing() async throws {
        let backend = FakeWorkspaceBackend(monitors: [monitor], windows: [], focusedWindow: nil)
        let (executor, _) = makeExecutor(backend)

        await #expect(throws: ExecutorError.noFocusedWindow) { try await executor.carryStepWorkspace(.right) }

        #expect(try await backend.showing() == .cell(cell(1, 1)))
    }

    @Test func carryingRightOntoTheVaultColumnIsRefused() async throws {
        let backend = makeBackend()
        await backend.switchOutsideChord(to: .cell(cell(1, GridCell.columnCount - 1)))
        let (executor, log) = makeExecutor(backend)

        #expect(try await executor.carryStepWorkspace(.right) == [])

        #expect(await backend.slot(of: WindowID(1)) == .cell(cell(1, 1)))
        #expect(try await backend.showing() == .cell(cell(1, GridCell.columnCount - 1)))
        #expect(log.all == [
            "workspace carry step right from r1-8: r1-9 is the vault column; nothing changed"
        ])
        await #expect(throws: ExecutorError.nothingToUndo) { try await executor.undo() }
    }

    @Test func carryingLeftWrappingOntoTheVaultColumnIsRefused() async throws {
        let backend = makeBackend()
        let (executor, _) = makeExecutor(backend, layout: WorkspaceLayout(rows: 3, wrap: true))

        #expect(try await executor.carryStepWorkspace(.left) == [])

        #expect(await backend.slot(of: WindowID(1)) == .cell(cell(1, 1)))
        #expect(try await backend.showing() == .cell(cell(1, 1)))
        await #expect(throws: ExecutorError.nothingToUndo) { try await executor.undo() }
    }

    @Test func carryingDownOrUpWithinTheVaultColumnIsRefused() async throws {
        for step in [GridStep.down, .up] {
            let backend = makeBackend()
            await backend.switchOutsideChord(to: .cell(cell(2, GridCell.columnCount)))
            let (executor, _) = makeExecutor(backend)

            #expect(try await executor.carryStepWorkspace(step) == [])

            #expect(try await backend.showing() == .cell(cell(2, GridCell.columnCount)))
            #expect(await backend.slot(of: WindowID(1)) == .cell(cell(1, 1)))
            await #expect(throws: ExecutorError.nothingToUndo) { try await executor.undo() }
        }
    }

    @Test func steppingIsNotUndoneByAnEarlierCarry() async throws {
        let backend = makeBackend()
        let (executor, _) = makeExecutor(backend)
        try await executor.carryStepWorkspace(.right)
        try await executor.stepWorkspace(.right)

        try await executor.undo()

        // Only the step is undone: the window stays carried, the view goes back to its cell.
        #expect(await backend.slot(of: WindowID(1)) == .cell(cell(1, 2)))
        #expect(try await backend.showing() == .cell(cell(1, 2)))
    }
}
