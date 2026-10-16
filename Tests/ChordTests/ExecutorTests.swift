import ChordCore
import Foundation
import Testing
@testable import Chord

@Suite("Executor (fake backend)")
struct ExecutorTests {
    private let frameA = ScreenRect(x: 0, y: 0, width: 333, height: 471)
    private let frameB = ScreenRect(x: 400, y: 0, width: 444, height: 630)

    private func window(_ id: Int, _ place: Place, floating: Bool = true, frame: ScreenRect? = nil)
        -> WindowSnapshot
    {
        WindowSnapshot(
            id: WindowID(id), appName: "App\(id)", place: place, isFloating: floating,
            bounds: frame ?? frameA)
    }

    private func makeBackend(_ windows: [WindowSnapshot]? = nil, focused: Int? = nil)
        -> FakeWorkspaceBackend
    {
        FakeWorkspaceBackend(
            monitors: [],
            windows: windows ?? [
                window(1, .workspace(.one)),
                window(2, .workspace(.two), frame: frameB),
                window(3, .bench),
            ],
            focusedWindow: focused.map(WindowID.init))
    }

    private func plan(_ assignments: (Int, Place)...) throws -> Plan {
        try Plan(assignments: assignments.map { Assignment(windowID: $0, place: $1, reason: .pinned) })
    }

    private func windows(_ backend: FakeWorkspaceBackend) async throws -> [Int: WindowSnapshot] {
        Dictionary(
            uniqueKeysWithValues: try await backend.snapshot().windows.map { ($0.id.rawValue, $0) })
    }

    // MARK: Apply and undo

    @Test func appliesPlanAndLogsOneLinePerChange() async throws {
        let backend = makeBackend()
        let executor = Executor(backend: backend)

        let applied = try await executor.apply(
            plan((1, .workspace(.five)), (2, .workspace(.two)), (3, .workspace(.one))))

        #expect(applied.count == 2)  // window 2 already in place: no action
        let now = try await windows(backend)
        #expect(now[1]?.place == .workspace(.five))
        #expect(now[3]?.place == .workspace(.one))
        #expect(await executor.log.count == 2)
    }

    @Test func undoRestoresPreviousPlaceAndFrame() async throws {
        let backend = makeBackend()
        let before = try await windows(backend)
        let executor = Executor(backend: backend)

        try await executor.apply(
            plan((1, .workspace(.five)), (3, .workspace(.four))),
            frames: [1: ScreenRect(x: 10.4, y: 20.5, width: 500.2, height: 300.7)])
        #expect(try await windows(backend) != before)

        try await executor.undo()

        #expect(try await windows(backend) == before)
        #expect(await executor.log.contains { $0.hasPrefix("undo:") })
    }

    @Test func undoUnwindsOneStepAtATimeThenReportsNothingToUndo() async throws {
        let backend = makeBackend()
        let executor = Executor(backend: backend)
        try await executor.apply(plan((1, .workspace(.five))))
        try await executor.apply(plan((1, .workspace(.six))))

        try await executor.undo()
        #expect(try await windows(backend)[1]?.place == .workspace(.five))
        try await executor.undo()
        #expect(try await windows(backend)[1]?.place == .workspace(.one))
        await #expect(throws: ExecutorError.nothingToUndo) { try await executor.undo() }
    }

    @Test func undoSkipsClosedWindowsAndStillRestoresTheRest() async throws {
        let backend = makeBackend([window(1, .workspace(.one)), window(3, .bench)])
        let executor = Executor(backend: backend)
        try await executor.apply(plan((1, .workspace(.five)), (3, .workspace(.four))))

        await backend.removeWindow(WindowID(3))
        try await executor.undo()

        let log = await executor.log
        #expect(log.contains { $0.contains("window 3 is gone") })
    }

    // MARK: Rejections

    @Test func unknownWindowIsRejectedAndNothingChanges() async throws {
        let backend = makeBackend()
        let before = try await backend.snapshot()
        let executor = Executor(backend: backend)

        await #expect(throws: PlanError.unknownWindow(99)) {
            try await executor.apply(plan((1, .workspace(.five)), (99, .bench)))
        }
        await #expect(throws: PlanError.unknownWindow(77)) {
            try await executor.apply(plan((1, .workspace(.five))), frames: [77: frameA])
        }
        await #expect(throws: PlanError.unknownWindow(99)) { try await executor.focus(99) }
        #expect(try await backend.snapshot() == before)
        #expect(await executor.log.isEmpty)
    }

    @Test func duplicateWindowsCannotReachTheExecutor() async throws {
        #expect(throws: PlanError.duplicateWindow(1)) {
            try Plan(assignments: [
                Assignment(windowID: 1, place: .bench, reason: .pinned),
                Assignment(windowID: 1, place: .workspace(.two), reason: .pinned),
            ])
        }
        let json = Data(
            """
            {"assignments":[{"window":1,"place":2,"reason":"pinned"},{"window":1,"place":3,"reason":"pinned"}]}
            """.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Plan.self, from: json) }
    }

    @Test func vaultTargetIsUnrepresentableAndVaultWindowsAreUnknown() async throws {
        let json = Data(
            #"{"assignments":[{"window":1,"place":9,"reason":"pinned"}]}"#.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Plan.self, from: json) }

        // The backend never reports a vault window, so naming one is just unknown.
        let backend = makeBackend()
        let executor = Executor(backend: backend)
        await #expect(throws: PlanError.unknownWindow(900)) {
            try await executor.apply(plan((900, .bench)))
        }
    }

    // MARK: Frames

    @Test func framesAreRoundedToIntegersAtApplyTime() async throws {
        let backend = makeBackend()
        let executor = Executor(backend: backend)

        try await executor.setFrame(1, to: ScreenRect(x: 10.4, y: 20.5, width: 500.49, height: 300.51))

        #expect(try await windows(backend)[1]?.bounds == ScreenRect(x: 10, y: 21, width: 500, height: 301))
    }

    @Test func settingTheSameFrameIsANoOp() async throws {
        let executor = Executor(backend: makeBackend())
        let applied = try await executor.setFrame(1, to: frameA)
        #expect(applied.isEmpty)
        await #expect(throws: ExecutorError.nothingToUndo) { try await executor.undo() }
    }

    @Test func restoreHomeRestoresPlaceAndFrameAndCanBeUndone() async throws {
        let backend = makeBackend()
        let executor = Executor(backend: backend)
        let home = WindowHome(
            place: .workspace(.one),
            frame: ActionRect(x: frameA.x, y: frameA.y, width: frameA.width, height: frameA.height))

        try await executor.apply(plan((1, .workspace(.five))), frames: [1: frameB])
        try await executor.restoreHome(1, to: home)

        #expect(try await windows(backend)[1]?.place == .workspace(.one))
        #expect(try await windows(backend)[1]?.bounds == frameA)
        #expect(await executor.log.contains { $0.contains("restore home for window 1") })

        try await executor.undo()
        #expect(try await windows(backend)[1]?.place == .workspace(.five))
        #expect(try await windows(backend)[1]?.bounds == frameB)
    }

    // MARK: Focus

    @Test func focusRaisesOnlyTheTargetAmongSameAppWindows() async throws {
        let backend = makeBackend(
            [window(1, .workspace(.one), floating: false), window(2, .workspace(.one), floating: false),
             window(3, .workspace(.one), floating: false)])
        let executor = Executor(backend: backend)

        try await executor.focus(1)

        let snap = try await backend.snapshot()
        #expect(snap.focusedWindow == WindowID(1))
        #expect(snap.stackingOrder == [WindowID(2), WindowID(3), WindowID(1)])
    }

    @Test func floatsStayAboveTilesOnEveryFocusChange() async throws {
        let backend = makeBackend([
            window(1, .workspace(.one), floating: false),
            window(2, .workspace(.one), floating: false),
            window(3, .workspace(.one), floating: true),
            window(4, .workspace(.one), floating: true),
            window(5, .workspace(.two), floating: true),
        ])
        let executor = Executor(backend: backend)

        for tile in [1, 2, 1] {
            try await executor.focus(tile)
            let order = try await backend.snapshot().stackingOrder
            let tilePos = order.firstIndex(of: WindowID(tile))!
            #expect(order.firstIndex(of: WindowID(3))! > tilePos)
            #expect(order.firstIndex(of: WindowID(4))! > tilePos)
            #expect(order.firstIndex(of: WindowID(3))! < order.firstIndex(of: WindowID(4))!)
        }
    }

    @Test func focusingAFloatLeavesItOnTop() async throws {
        let backend = makeBackend([
            window(1, .workspace(.one), floating: false),
            window(3, .workspace(.one), floating: true),
            window(4, .workspace(.one), floating: true),
        ])
        let executor = Executor(backend: backend)

        try await executor.focus(3)

        #expect(try await backend.snapshot().stackingOrder.last == WindowID(3))
    }

    @Test func focusChangeHasInverseAndLogLine() async throws {
        let executor = Executor(backend: makeBackend(focused: 1))
        let change = try await executor.focus(2)
        #expect(change == .focus(from: 1, to: 2))
        #expect(change.inverse == .focus(from: 2, to: 1))
        #expect(await executor.log.first == "focus window 2 (was 1)")
    }

    // MARK: Focus history

    @Test func closingFocusedWindowReturnsFocusToLastFocusedInWorkspace() async throws {
        let backend = makeBackend([
            window(1, .workspace(.one)), window(2, .workspace(.one)),
            window(3, .workspace(.one)), window(4, .workspace(.two)),
        ])
        let executor = Executor(backend: backend)
        for id in [1, 2, 4, 3] { try await executor.focus(id) }
        #expect(try await executor.focusHistory(in: .workspace(.one)) == [3, 2, 1])

        await backend.removeWindow(WindowID(3))
        let refocused = try await executor.reconcileAfterClose()

        #expect(refocused == 2)  // not 4: that is another workspace
        #expect(try await backend.snapshot().focusedWindow == WindowID(2))
        #expect(try await executor.focusHistory(in: .workspace(.one)) == [2, 1])
    }

    @Test func closingAnUnfocusedWindowDoesNotMoveFocus() async throws {
        let backend = makeBackend([window(1, .workspace(.one)), window(2, .workspace(.one))])
        let executor = Executor(backend: backend)
        try await executor.focus(1)
        await backend.removeWindow(WindowID(2))

        #expect(try await executor.reconcileAfterClose() == nil)
        #expect(try await backend.snapshot().focusedWindow == WindowID(1))
    }

    @Test func historyFollowsAWindowThatMoved() async throws {
        let backend = makeBackend([window(1, .workspace(.one)), window(2, .workspace(.one))])
        let executor = Executor(backend: backend)
        try await executor.focus(1)
        try await executor.focus(2)
        try await executor.apply(plan((2, .workspace(.three))))

        #expect(try await executor.focusHistory(in: .workspace(.one)) == [1])
        #expect(try await executor.focusHistory(in: .workspace(.three)) == [2])
    }

    // MARK: Backend failures

    @Test func lostReplyIsResolvedByReReadingNotAssumed() async throws {
        let backend = makeBackend()
        let executor = Executor(backend: backend)
        await backend.queue([.proceed, .lostReply])

        let applied = try await executor.apply(plan((1, .workspace(.five))))

        #expect(applied == [.place(windowID: 1, from: .workspace(.one), to: .workspace(.five))])
        try await executor.undo()
        #expect(try await windows(backend)[1]?.place == .workspace(.one))
    }

    @Test func failureMidwayKeepsAppliedChangesUndoable() async throws {
        let backend = makeBackend()
        let before = try await windows(backend)
        let executor = Executor(backend: backend)
        // Slots: snapshot, first move, second move (times out).
        await backend.queue([.proceed, .proceed, .timeoutBeforeApply])

        await #expect(throws: BackendError.unknown(reason: "timed out before apply")) {
            try await executor.apply(plan((1, .workspace(.five)), (3, .workspace(.four))))
        }
        #expect(try await windows(backend)[1]?.place == .workspace(.five))
        #expect(try await windows(backend)[3]?.place == .bench)

        try await executor.undo()
        #expect(try await windows(backend) == before)
    }
}
