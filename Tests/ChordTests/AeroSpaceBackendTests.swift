import ChordCore
import Testing
@testable import Chord

@Suite("AeroSpaceBackend (fake server)")
struct AeroSpaceBackendTests {
    private let frame = ScreenRect(x: 10, y: 20, width: 333, height: 471)

    private func cell(_ row: Int, _ column: Int) -> GridCell { GridCell(row: row, column: column)! }

    private func makeServer() -> FakeAeroSpaceServer {
        FakeAeroSpaceServer(
            windows: [(10, "r1-1", "Terminal"), (11, "r1-2", "Safari"), (12, "bench", "Notes")],
            focusedWorkspace: "r1-1", focusedWindow: 11)
    }

    private func makeBackend(
        _ server: FakeAeroSpaceServer, tag: String = "v0.21.3-Beta",
        frames: @escaping @Sendable ([WindowID]) -> [WindowID: ScreenRect]? = { _ in nil }
    ) -> AeroSpaceBackend {
        let rect = frame
        return AeroSpaceBackend(
            transport: server, pinnedTag: tag, monitors: { [] },
            frames: { ids in frames(ids) ?? Dictionary(uniqueKeysWithValues: ids.map { ($0, rect) }) })
    }

    // MARK: Commands

    @Test func commandsAreSentAsTheDocumentedArguments() {
        #expect(AeroSpaceCommand.showWorkspace("r2-5").args == ["workspace", "r2-5"])
        #expect(
            AeroSpaceCommand.moveWindow(WindowID(42), toWorkspace: "r2-5").args
                == ["move-node-to-workspace", "--window-id", "42", "r2-5"])
        #expect(AeroSpaceCommand.focusedWorkspace.args == ["list-workspaces", "--focused", "--format", "%{workspace}"])
        #expect(AeroSpaceCommand.focusedWindowID.args == ["list-windows", "--focused", "--format", "%{window-id}"])
        #expect(AeroSpaceCommand.listAllWindows.args.prefix(2) == ["list-windows", "--all"])
    }

    // MARK: Snapshot

    @Test func snapshotReportsWindowsFloatingFlagFocusAndFrames() async throws {
        let server = makeServer()
        let backend = makeBackend(server)

        let snapshot = try await backend.snapshot()

        #expect(snapshot.windows.map(\.id) == [WindowID(10), WindowID(11), WindowID(12)])
        #expect(snapshot.windows.map(\.appName) == ["Terminal", "Safari", "Notes"])
        #expect(snapshot.windows.allSatisfy { $0.isFloating && $0.bounds == frame })
        #expect(snapshot.focusedWindow == WindowID(11))
    }

    @Test func aTiledWindowIsNotFloating() async throws {
        let server = makeServer()
        await server.overrideWindowLines(["10\tr1-1\th_tiles\tTerminal"])
        let snapshot = try await makeBackend(server).snapshot()
        #expect(snapshot.windows.map(\.isFloating) == [false])
    }

    @Test func anAppNameWithATabOrSpacesIsKeptWhole() async throws {
        let server = makeServer()
        await server.overrideWindowLines(["10\tr1-1\tfloating\tMy\tOdd App  Name"])
        let snapshot = try await makeBackend(server).snapshot()
        #expect(snapshot.windows.map(\.appName) == ["My\tOdd App  Name"])
    }

    @Test(arguments: ["9", "2"])
    func aWindowOnAWorkspaceChordDidNotNameIsInvisibleAndImmovable(foreign: String) async throws {
        let server = FakeAeroSpaceServer(
            windows: [(10, foreign, "Vault"), (11, "r1-1", "Terminal")], focusedWorkspace: "r1-1")
        let backend = makeBackend(server)

        #expect(try await backend.snapshot().windows.map(\.id) == [WindowID(11)])
        for row in 1...3 {
            for column in 1...GridCell.columnCount {
                let listed = try await backend.listWindows(in: cell(row, column))
                #expect(!listed.contains(WindowID(10)))
            }
        }
        await #expect(throws: BackendError.unknownWindow(WindowID(10))) {
            try await backend.moveWindow(WindowID(10), to: self.cell(1, 2))
        }
        await #expect(throws: BackendError.unknownWindow(WindowID(10))) {
            try await backend.moveWindow(WindowID(10), to: Place.bench)
        }
        await #expect(throws: BackendError.unknownWindow(WindowID(10))) {
            try await backend.moveWindow(WindowID(10), to: .workspace(.two))
        }
        #expect(await server.changes.isEmpty)
        #expect(await server.workspace(of: 10) == foreign)
    }

    @Test func aWindowWithNoFrameIsLeftOutNotGuessed() async throws {
        let server = makeServer()
        let rect = frame
        let backend = makeBackend(server) { ids in
            Dictionary(uniqueKeysWithValues: ids.filter { $0 != WindowID(11) }.map { ($0, rect) })
        }

        #expect(try await backend.snapshot().windows.map(\.id) == [WindowID(10), WindowID(12)])
    }

    @Test func noFocusedWindowReadsAsNone() async throws {
        let server = FakeAeroSpaceServer(windows: [(10, "r1-1", "Terminal")], focusedWorkspace: "r1-1")
        #expect(try await makeBackend(server).snapshot().focusedWindow == nil)
    }

    @Test func aLineItCannotReadIsUnknownNotAPartialSnapshot() async throws {
        let server = makeServer()
        await server.overrideWindowLines(["10\tr1-1\tfloating\tTerminal", "garbage"])
        let backend = makeBackend(server)

        await #expect(throws: BackendError.self) { try await backend.snapshot() }
        await #expect(throws: BackendError.self) { try await backend.listWindows(in: GridCell.first) }
    }

    // MARK: Changes

    @Test func showingTheShownCellSendsNothing() async throws {
        let server = makeServer()
        let backend = makeBackend(server)

        #expect(try await backend.show(cell(1, 1)) == cell(1, 1))
        #expect(await server.changes.isEmpty)
    }

    @Test func showOverAWorkspaceChordDidNotMakeReportsNoPreviousCell() async throws {
        let server = FakeAeroSpaceServer(windows: [], focusedWorkspace: "1")
        let backend = makeBackend(server)

        #expect(try await backend.show(cell(1, 2)) == nil)
        #expect(await server.focusedWorkspace == "r1-2")
    }

    @Test func aMoveSendsOneCommandAfterReadingTheWindow() async throws {
        let server = makeServer()
        let backend = makeBackend(server)

        try await backend.moveWindow(WindowID(10), to: cell(3, 4))

        #expect(await server.changes == [.moveWindow(WindowID(10), toWorkspace: "r3-4")])
        #expect(await server.sent.first == .listAllWindows)
    }

    @Test func movingToTheBenchUsesTheBenchWorkspaceNameInAnyRow() async throws {
        let server = FakeAeroSpaceServer(
            windows: [(10, "r2-1", "Terminal")], focusedWorkspace: "r1-1")
        let backend = makeBackend(server)
        try await backend.show(cell(2, 1))

        try await backend.moveWindow(WindowID(10), to: GridSlot.bench)

        #expect(await server.workspace(of: 10) == "bench")
    }

    @Test func aPlaceMoveLandsInTheRowShowingNowEvenAfterAnOutsideSwitch() async throws {
        let server = FakeAeroSpaceServer(
            windows: [(10, "r3-1", "A"), (11, "r1-1", "B")], focusedWorkspace: "r3-1")
        let backend = makeBackend(server)

        try await backend.moveWindow(WindowID(10), to: .workspace(.two))
        await server.setFocusedWorkspace("r1-1")
        try await backend.moveWindow(WindowID(11), to: .workspace(.two))

        #expect(await server.workspace(of: 10) == "r3-2")
        #expect(await server.workspace(of: 11) == "r1-2")
    }

    @Test func aWindowInAnotherRowIsOutsideThePlaceApiButFaithfulThroughTheCellApi() async throws {
        let server = FakeAeroSpaceServer(
            windows: [(10, "r1-3", "Mail"), (11, "r2-1", "Terminal")], focusedWorkspace: "r2-1")
        let backend = makeBackend(server)

        #expect(try await backend.snapshot().windows.map(\.id) == [WindowID(11)])
        await #expect(throws: BackendError.unknownWindow(WindowID(10))) {
            try await backend.moveWindow(WindowID(10), to: Place.bench)
        }
        await #expect(throws: BackendError.unknownWindow(WindowID(10))) {
            try await backend.moveWindow(WindowID(10), to: .workspace(.three))
        }
        #expect(await server.changes.isEmpty)
        #expect(try await backend.listWindows(in: cell(1, 3)) == [WindowID(10)])

        let left = try await backend.moveWindow(WindowID(10), to: cell(2, 3))
        #expect(left == .cell(cell(1, 3)))
        #expect(try await backend.moveWindow(WindowID(10), to: cell(1, 3)) == .cell(cell(2, 3)))
        #expect(await server.workspace(of: 10) == "r1-3")
    }

    @Test func aPlaceMoveAfterReconnectUsesTheServersRowNotARemembered() async throws {
        let server = FakeAeroSpaceServer(windows: [(10, "r1-1", "A")], focusedWorkspace: "r2-1")
        let backend = makeBackend(server)
        try await backend.show(cell(2, 1))
        await server.setFocusedWorkspace("r1-1")
        try await backend.reconnect()

        try await backend.moveWindow(WindowID(10), to: .workspace(.five))

        #expect(await server.workspace(of: 10) == "r1-5")
    }

    @Test(arguments: ["9", "bench", "2"])
    func whenNoRowIsShowingThePlaceApiSeesNothingAndRefusesButTheSlotApiWorks(focused: String) async throws {
        let server = FakeAeroSpaceServer(
            windows: [(10, "r1-1", "Terminal"), (11, "bench", "Notes")], focusedWorkspace: focused)
        let backend = makeBackend(server)

        #expect(try await backend.snapshot().windows.isEmpty)
        let error = await #expect(throws: BackendError.self) {
            try await backend.moveWindow(WindowID(10), to: .workspace(.five))
        }
        guard case .unknown = error else {
            Issue.record("a Place move with no row showing must be .unknown, got \(String(describing: error))")
            return
        }
        await #expect(throws: BackendError.self) { try await backend.moveWindow(WindowID(11), to: Place.bench) }
        #expect(await server.changes.isEmpty)

        #expect(try await backend.listWindows(in: cell(1, 1)) == [WindowID(10)])
        #expect(try await backend.moveWindow(WindowID(10), to: cell(2, 5)) == .cell(cell(1, 1)))
        #expect(try await backend.moveWindow(WindowID(11), to: cell(1, 2)) == .bench)
        #expect(try await backend.moveWindow(WindowID(11), to: GridSlot.bench) == .cell(cell(1, 2)))
        #expect(await server.workspace(of: 10) == "r2-5")
        #expect(await server.workspace(of: 11) == "bench")
    }

    // MARK: Failure is never silent success

    @Test func aDisabledServerIsNotConnectedForEveryCallAndAppliesNothing() async throws {
        let server = makeServer()
        await server.setEnabled(false)
        let backend = makeBackend(server)

        await #expect(throws: BackendError.notConnected) { try await backend.snapshot() }
        await #expect(throws: BackendError.notConnected) { try await backend.show(GridCell.first) }
        await #expect(throws: BackendError.notConnected) { try await backend.moveWindow(WindowID(10), to: GridCell.first) }
        await #expect(throws: BackendError.notConnected) { try await backend.moveWindow(WindowID(10), to: Place.bench) }
        await #expect(throws: BackendError.notConnected) { try await backend.listWindows(in: GridCell.first) }
        await #expect(throws: BackendError.notConnected) { try await backend.reconnect() }
        #expect(await server.changes.isEmpty)
    }

    @Test func aServerThatIsNotThePinnedVersionIsRefusedBeforeAnyChange() async throws {
        let server = makeServer()
        await server.setVersion("0.20.3-Beta 6dde91ba43f6")
        let backend = makeBackend(server)

        await #expect(throws: BackendError.notConnected) { try await backend.snapshot() }
        await #expect(throws: BackendError.notConnected) { try await backend.show(self.cell(2, 2)) }
        await #expect(throws: BackendError.notConnected) { try await backend.moveWindow(WindowID(10), to: self.cell(2, 2)) }
        #expect(await server.changes.isEmpty)
    }

    @Test func theConfiguredTagIsTheOneEnforced() async throws {
        let server = makeServer()
        await server.setVersion("0.21.4-Beta abc")

        #expect(try await makeBackend(server, tag: "v0.21.4-Beta").snapshot().windows.count == 3)
        await #expect(throws: BackendError.notConnected) {
            try await self.makeBackend(server, tag: "v0.21.3-Beta").snapshot()
        }
    }

    @Test func noConnectionAndAHandshakeMismatchAreNotConnected() async throws {
        let server = makeServer()
        let backend = makeBackend(server)

        await server.queue([.cannotConnect])
        await #expect(throws: BackendError.notConnected) { try await backend.show(self.cell(2, 2)) }
        await server.queue([.protocolMismatch])
        await #expect(throws: BackendError.notConnected) { try await backend.snapshot() }
        #expect(await server.changes.isEmpty)
    }

    @Test func aLostReplyOnAMoveIsUnknownAndTheRereadIsTheTruth() async throws {
        let server = makeServer()
        let backend = makeBackend(server)
        // list-windows read first, then the move whose answer is lost.
        await server.queue([.proceed, .noReplyAfterApply])

        await #expect(throws: BackendError.self) { try await backend.moveWindow(WindowID(10), to: self.cell(2, 2)) }

        #expect(await server.workspace(of: 10) == "r2-2")
        #expect(try await backend.listWindows(in: cell(2, 2)) == [WindowID(10)])
    }

    @Test func aMoveLostBeforeItAppliedIsUnknownAndChangedNothing() async throws {
        let server = makeServer()
        let backend = makeBackend(server)
        await server.queue([.proceed, .noReplyBeforeApply])

        let error = await #expect(throws: BackendError.self) {
            try await backend.moveWindow(WindowID(10), to: self.cell(2, 2))
        }
        guard case .unknown = error else {
            Issue.record("a lost command must be .unknown, got \(String(describing: error))")
            return
        }
        #expect(await server.workspace(of: 10) == "r1-1")
    }

    @Test func aCommandTheServerRefusesIsUnknownWithItsFirstErrorLine() async throws {
        let server = makeServer()
        let backend = makeBackend(server)
        await server.queue([.proceed, .failure("Workspace name is bad\nmore detail")])

        let error = await #expect(throws: BackendError.self) {
            try await backend.moveWindow(WindowID(10), to: self.cell(2, 2))
        }
        guard case .unknown(let reason) = error else {
            Issue.record("a refused command must be .unknown, got \(String(describing: error))")
            return
        }
        #expect(reason.contains("Workspace name is bad"))
        #expect(!reason.contains("more detail"))
    }

    @Test func showFailingAfterItsReadIsUnknownAndKeepsTheOldRow() async throws {
        let server = makeServer()
        let backend = makeBackend(server)
        await server.queue([.proceed, .failure("nope")])

        await #expect(throws: BackendError.self) { try await backend.show(self.cell(3, 3)) }

        // The failed show must not have moved the remembered row: a place move still
        // lands where the server really is.
        try await backend.moveWindow(WindowID(10), to: .workspace(.five))
        #expect(await server.workspace(of: 10) == "r1-5")
    }

    // MARK: Not AeroSpace's job

    @Test func frameFocusAndRaiseAreRefusedAsUnknownNotFaked() async throws {
        let backend = makeBackend(makeServer())

        await #expect(throws: BackendError.self) { try await backend.applyFrame(WindowID(10), to: self.frame) }
        await #expect(throws: BackendError.self) { try await backend.focusWindow(WindowID(10)) }
        await #expect(throws: BackendError.self) { try await backend.raiseWindow(WindowID(10)) }
    }

    @Test func reconnectResetsTheConnectionAndProvesTheServerAnswers() async throws {
        let server = makeServer()
        let backend = makeBackend(server)

        try await backend.reconnect()

        #expect(await server.resets == 1)
        #expect(await server.sent == [.focusedWorkspace])
    }
}
