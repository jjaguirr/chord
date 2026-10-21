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

@Suite("Executor workspaces")
struct ExecutorWorkspaceTests {
    private let frame = ScreenRect(x: 100, y: 100, width: 600, height: 400)
    private let monitor = MonitorSnapshot(
        id: MonitorID(1), bounds: ScreenRect(x: 0, y: 25, width: 1440, height: 875), isPrimary: true)

    private func cell(_ row: Int, _ column: Int) -> GridCell {
        guard let cell = GridCell(row: row, column: column) else {
            fatalError("test cell r\(row)-\(column) is out of range")
        }
        return cell
    }

    /// Window 1 in r1-1 (focused), 2 on the bench, 3 in r1-3.
    private func makeBackend(focused: WindowID? = WindowID(1)) -> FakeWorkspaceBackend {
        func window(_ id: Int, _ place: Place) -> WindowSnapshot {
            WindowSnapshot(id: WindowID(id), appName: "App", place: place, isFloating: true, bounds: frame)
        }
        return FakeWorkspaceBackend(
            monitors: [monitor],
            windows: [window(1, .workspace(.one)), window(2, .bench), window(3, .workspace(.three))],
            focusedWindow: focused)
    }

    private func makeExecutor(_ backend: FakeWorkspaceBackend) -> (Executor, LogBox) {
        let log = LogBox()
        return (Executor(backend: backend, logSink: { log.append($0) }), log)
    }

    private func bounds(_ backend: FakeWorkspaceBackend) async throws -> [Int: ScreenRect] {
        Dictionary(
            uniqueKeysWithValues: try await backend.snapshot().windows.map { ($0.id.rawValue, $0.bounds) })
    }

    // MARK: Switch

    @Test func optionNShowsColumnNInTheRowShowingNow() async throws {
        let backend = makeBackend()
        let (executor, _) = makeExecutor(backend)

        let changes = try await executor.showColumn(5)

        #expect(changes == [.show(from: .cell(cell(1, 1)), to: .cell(cell(1, 5)))])
        #expect(try await backend.showing() == .cell(cell(1, 5)))

        await backend.switchOutsideChord(to: .cell(cell(2, 2)))
        try await executor.showColumn(7)
        #expect(try await backend.showing() == .cell(cell(2, 7)))
    }

    @Test func aSwitchMovesAndResizesNoWindow() async throws {
        let backend = makeBackend()
        let (executor, _) = makeExecutor(backend)
        let before = try await bounds(backend)

        try await executor.showColumn(3)
        try await executor.showColumn(1)

        #expect(try await bounds(backend) == before)
        #expect(await backend.slot(of: WindowID(1)) == .cell(cell(1, 1)))
        #expect(await backend.slot(of: WindowID(3)) == .cell(cell(1, 3)))
    }

    @Test func aSwitchIsLoggedAndUndoShowsWhatWasShowing() async throws {
        let backend = makeBackend()
        let (executor, log) = makeExecutor(backend)

        try await executor.showColumn(5)
        #expect(log.all == ["show workspace r1-5 (was r1-1)"])

        let undone = try await executor.undo()

        #expect(undone == [.show(from: .cell(cell(1, 5)), to: .cell(cell(1, 1)))])
        #expect(try await backend.showing() == .cell(cell(1, 1)))
        #expect(log.all.last == "undo: show workspace r1-1 (was r1-5)")
    }

    @Test func showingWhatIsAlreadyShowingChangesNothingAndLeavesNothingToUndo() async throws {
        let backend = makeBackend()
        let (executor, log) = makeExecutor(backend)

        #expect(try await executor.showColumn(1) == [])

        #expect(log.all == ["show workspace r1-1: already showing; nothing changed"])
        await #expect(throws: ExecutorError.nothingToUndo) { try await executor.undo() }
    }

    @Test func aColumnOutsideTheGridIsRefusedAndChangesNothing() async throws {
        let backend = makeBackend()
        let (executor, log) = makeExecutor(backend)

        #expect(try await executor.showColumn(0) == [])
        #expect(try await executor.showColumn(GridCell.columnCount + 1) == [])
        #expect(try await executor.carryToColumn(0) == [])

        #expect(try await backend.showing() == .cell(cell(1, 1)))
        #expect(await backend.slot(of: WindowID(1)) == .cell(cell(1, 1)))
        #expect(log.all.count == 3)
        #expect(log.all.allSatisfy { $0.contains("no such workspace; nothing changed") })
        await #expect(throws: ExecutorError.nothingToUndo) { try await executor.undo() }
    }

    @Test func anEmptyCellShowsLikeAnyOther() async throws {
        let backend = makeBackend()
        let (executor, _) = makeExecutor(backend)

        try await executor.showColumn(8)

        #expect(try await backend.showing() == .cell(cell(1, 8)))
        #expect(try await backend.listWindows(in: cell(1, 8)).isEmpty)
    }

    @Test func aSwitchAwayFromAWorkspaceChordDidNotMakeHasNoInverseButIsStillUndoable() async throws {
        let backend = makeBackend()
        await backend.switchOutsideChord(to: nil)
        let (executor, log) = makeExecutor(backend)

        try await executor.showColumn(4)

        #expect(log.all == ["show workspace r1-4 (was none)"])
        #expect(try await executor.undo() == [.noop(windowID: 0)])
        #expect(try await backend.showing() == .cell(cell(1, 4)))
    }

    // MARK: Back

    @Test func optionTabReturnsToThePreviousCellAndPressedAgainReturnsAgain() async throws {
        let backend = makeBackend()
        let (executor, _) = makeExecutor(backend)
        try await executor.showColumn(6)

        try await executor.showPrevious()
        #expect(try await backend.showing() == .cell(cell(1, 1)))
        try await executor.showPrevious()
        #expect(try await backend.showing() == .cell(cell(1, 6)))
    }

    @Test func backFollowsASwitchMadeOutsideChord() async throws {
        let backend = makeBackend()
        let (executor, _) = makeExecutor(backend)
        try await executor.showColumn(2)
        await backend.switchOutsideChord(to: .cell(cell(3, 9)))

        try await executor.showPrevious()

        #expect(try await backend.showing() == .cell(cell(1, 2)))
    }

    @Test func backWithNoEarlierWorkspaceChangesNothing() async throws {
        let backend = makeBackend()
        let (executor, log) = makeExecutor(backend)

        #expect(try await executor.showPrevious() == [])

        #expect(log.all == ["show previous: no earlier workspace; nothing changed"])
        #expect(try await backend.showing() == .cell(cell(1, 1)))
    }

    @Test func backIsOneUndoableChange() async throws {
        let backend = makeBackend()
        let (executor, _) = makeExecutor(backend)
        try await executor.showColumn(6)
        try await executor.showPrevious()

        try await executor.undo()

        #expect(try await backend.showing() == .cell(cell(1, 6)))
    }

    // MARK: Bench view

    @Test func theBenchIsAViewAndOptionTabReturnsFromIt() async throws {
        let backend = makeBackend()
        let (executor, log) = makeExecutor(backend)
        try await executor.showColumn(4)

        try await executor.showBench()
        #expect(try await backend.showing() == .bench)
        #expect(log.all.last == "show workspace bench (was r1-4)")

        try await executor.showPrevious()
        #expect(try await backend.showing() == .cell(cell(1, 4)))
    }

    @Test func theRowIsRememberedWhileTheBenchShows() async throws {
        let backend = makeBackend()
        await backend.switchOutsideChord(to: .cell(cell(2, 3)))
        let (executor, _) = makeExecutor(backend)

        try await executor.showBench()
        try await executor.showColumn(6)

        #expect(try await backend.showing() == .cell(cell(2, 6)))
    }

    @Test func aSwitchViewingTheBenchMovesNoWindow() async throws {
        let backend = makeBackend()
        let (executor, _) = makeExecutor(backend)

        try await executor.showBench()

        #expect(await backend.slot(of: WindowID(1)) == .cell(cell(1, 1)))
        #expect(await backend.slot(of: WindowID(2)) == .bench)
    }

    @Test func carryingToTheBenchRemembersTheHomeAndUndoReturnsIt() async throws {
        let backend = makeBackend()
        let (executor, log) = makeExecutor(backend)
        try await executor.showColumn(1)
        try await executor.carryToColumn(4)

        let changes = try await executor.carryToBench()

        #expect(changes == [
            .move(windowID: 1, from: .cell(cell(1, 4)), to: .bench),
            .show(from: .cell(cell(1, 4)), to: .bench),
        ])
        #expect(log.all.contains("move window 1: r1-4 -> bench"))
        #expect(await backend.slot(of: WindowID(1)) == .bench)
        #expect(try await backend.showing() == .bench)

        try await executor.undo()

        #expect(await backend.slot(of: WindowID(1)) == .cell(cell(1, 4)))
        #expect(try await backend.showing() == .cell(cell(1, 4)))
    }

    @Test func aWindowCarriedFromTheBenchViewLandsInTheRememberedRow() async throws {
        let backend = makeBackend(focused: WindowID(2))
        await backend.switchOutsideChord(to: .cell(cell(2, 1)))
        let (executor, _) = makeExecutor(backend)
        try await executor.showBench()

        try await executor.carryToColumn(5)

        #expect(await backend.slot(of: WindowID(2)) == .cell(cell(2, 5)))
        #expect(try await backend.showing() == .cell(cell(2, 5)))
    }

    // MARK: Carry

    @Test func optionShiftNCarriesTheFocusedWindowAndFollowsIt() async throws {
        let backend = makeBackend()
        let (executor, log) = makeExecutor(backend)

        let changes = try await executor.carryToColumn(5)

        #expect(changes == [
            .move(windowID: 1, from: .cell(cell(1, 1)), to: .cell(cell(1, 5))),
            .show(from: .cell(cell(1, 1)), to: .cell(cell(1, 5))),
        ])
        #expect(await backend.slot(of: WindowID(1)) == .cell(cell(1, 5)))
        #expect(try await backend.showing() == .cell(cell(1, 5)))
        #expect(log.all == ["move window 1: r1-1 -> r1-5", "show workspace r1-5 (was r1-1)"])
    }

    @Test func aCarryResizesNoWindow() async throws {
        let backend = makeBackend()
        let (executor, _) = makeExecutor(backend)
        let before = try await bounds(backend)[1]

        try await executor.carryToColumn(5)

        #expect(try await bounds(backend)[1] == before)
    }

    @Test func undoPutsTheWindowBackInItsPreviousCellAndShowsThatCell() async throws {
        let backend = makeBackend()
        let (executor, log) = makeExecutor(backend)
        try await executor.carryToColumn(5)

        let undone = try await executor.undo()

        #expect(undone == [
            .show(from: .cell(cell(1, 5)), to: .cell(cell(1, 1))),
            .move(windowID: 1, from: .cell(cell(1, 5)), to: .cell(cell(1, 1))),
        ])
        #expect(await backend.slot(of: WindowID(1)) == .cell(cell(1, 1)))
        #expect(try await backend.showing() == .cell(cell(1, 1)))
        #expect(log.all.suffix(2) == ["undo: show workspace r1-1 (was r1-5)", "undo: move window 1: r1-5 -> r1-1"])
        await #expect(throws: ExecutorError.nothingToUndo) { try await executor.undo() }
    }

    @Test func carryingToTheCellItIsInChangesNothing() async throws {
        let backend = makeBackend()
        let (executor, log) = makeExecutor(backend)

        #expect(try await executor.carryToColumn(1) == [])

        #expect(log.all == ["carry window 1: already in r1-1; nothing changed"])
        await #expect(throws: ExecutorError.nothingToUndo) { try await executor.undo() }
    }

    @Test func carryingFromAnEmptyCellNeedsAFocusedWindowAndChangesNothing() async throws {
        let backend = makeBackend(focused: nil)
        await backend.switchOutsideChord(to: .cell(cell(1, 8)))
        let (executor, _) = makeExecutor(backend)

        await #expect(throws: ExecutorError.noFocusedWindow) { try await executor.carryToColumn(2) }

        #expect(try await backend.showing() == .cell(cell(1, 8)))
        #expect(await backend.slot(of: WindowID(1)) == .cell(cell(1, 1)))
        await #expect(throws: ExecutorError.nothingToUndo) { try await executor.undo() }
    }

    @Test func carryingFromAForeignWorkspaceNeedsAFocusedWindowTheBackendKnows() async throws {
        let backend = makeBackend(focused: nil)
        await backend.switchOutsideChord(to: nil)
        let (executor, _) = makeExecutor(backend)

        await #expect(throws: ExecutorError.noFocusedWindow) { try await executor.carryToColumn(2) }
    }

    @Test func carryingAWindowIntoTheVaultColumnCannotBeUndoneByChord() async throws {
        let backend = makeBackend()
        let (executor, log) = makeExecutor(backend)

        try await executor.carryToColumn(GridCell.columnCount)
        #expect(await backend.slot(of: WindowID(1)) == .cell(cell(1, GridCell.columnCount)))

        try await executor.undo()

        // Exit from the vault is the user's alone: no read reports the window, so the move
        // back is skipped and the window stays.
        #expect(await backend.slot(of: WindowID(1)) == .cell(cell(1, GridCell.columnCount)))
        #expect(log.all.contains("undo skipped: window 1 is gone"))
    }

    // MARK: Failures

    @Test func aDroppedConnectionThrowsAndChangesNothing() async throws {
        let backend = makeBackend()
        await backend.queue([.disconnected])
        let (executor, _) = makeExecutor(backend)

        await #expect(throws: BackendError.notConnected) { try await executor.showColumn(5) }
        await #expect(throws: BackendError.notConnected) { try await executor.carryToColumn(5) }

        try await backend.reconnect()
        #expect(try await backend.showing() == .cell(cell(1, 1)))
        #expect(await backend.slot(of: WindowID(1)) == .cell(cell(1, 1)))
        await #expect(throws: ExecutorError.nothingToUndo) { try await executor.undo() }
    }

    @Test func aLostReplyOnAShowIsResolvedByReadingWhatIsShowing() async throws {
        let backend = makeBackend()
        await backend.queue([.proceed, .lostReply])
        let (executor, log) = makeExecutor(backend)

        try await executor.showColumn(5)

        #expect(try await backend.showing() == .cell(cell(1, 5)))
        #expect(log.all == ["show workspace r1-5 (was r1-1)"])
    }

    @Test func aShowThatTimesOutBeforeApplyingIsAFailureNotASuccess() async throws {
        let backend = makeBackend()
        await backend.queue([.proceed, .timeoutBeforeApply])
        let (executor, log) = makeExecutor(backend)

        await #expect(throws: BackendError.self) { try await executor.showColumn(5) }

        #expect(try await backend.showing() == .cell(cell(1, 1)))
        #expect(log.all.contains { $0.hasPrefix("failed: show workspace r1-5") })
        await #expect(throws: ExecutorError.nothingToUndo) { try await executor.undo() }
    }

    @Test func aCarryWhoseFollowFailsKeepsTheMoveUndoable() async throws {
        let backend = makeBackend()
        // showing, focusedWindow, moveWindow proceed; the show times out.
        await backend.queue([.proceed, .proceed, .proceed, .timeoutBeforeApply])
        let (executor, _) = makeExecutor(backend)

        await #expect(throws: BackendError.self) { try await executor.carryToColumn(5) }
        #expect(await backend.slot(of: WindowID(1)) == .cell(cell(1, 5)))

        try await executor.undo()

        #expect(await backend.slot(of: WindowID(1)) == .cell(cell(1, 1)))
    }
}
