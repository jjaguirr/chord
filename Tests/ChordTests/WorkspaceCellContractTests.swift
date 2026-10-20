import ChordCore
import Testing
@testable import Chord

/// The cell contract every `WorkspaceBackend` that has workspaces must pass. A second
/// adapter replaces AeroSpace by being added to `ContractSubject` and passing these.
enum ContractSubject: CaseIterable, Sendable, CustomTestStringConvertible {
    case fake
    case aerospace

    var testDescription: String {
        switch self {
        case .fake: return "fake"
        case .aerospace: return "AeroSpace adapter over a fake server"
        }
    }

    /// Windows 10 (Terminal, r1-1), 11 (Safari, r1-2), 12 (Notes, bench) and 13 (Mail,
    /// r2-3). Cell r1-1 is showing. Window 10 has focus.
    func make() async throws -> any WorkspaceBackend {
        let frame = ScreenRect(x: 0, y: 0, width: 333, height: 471)
        switch self {
        case .fake:
            let backend = FakeWorkspaceBackend(
                monitors: [],
                windows: [
                    WindowSnapshot(id: WindowID(10), appName: "Terminal", place: .workspace(.one), isFloating: true, bounds: frame),
                    WindowSnapshot(id: WindowID(11), appName: "Safari", place: .workspace(.two), isFloating: true, bounds: frame),
                    WindowSnapshot(id: WindowID(12), appName: "Notes", place: .bench, isFloating: true, bounds: frame),
                    WindowSnapshot(id: WindowID(13), appName: "Mail", place: .workspace(.three), isFloating: true, bounds: frame),
                ],
                focusedWindow: WindowID(10))
            try await backend.moveWindow(WindowID(13), to: GridCell(row: 2, column: 3)!)
            return backend
        case .aerospace:
            let server = FakeAeroSpaceServer(
                windows: [(10, "r1-1", "Terminal"), (11, "r1-2", "Safari"), (12, "bench", "Notes"), (13, "r2-3", "Mail")],
                focusedWorkspace: "r1-1", focusedWindow: 10)
            return AeroSpaceBackend(
                transport: server, pinnedTag: "v0.21.3-Beta", monitors: { [] },
                frames: { ids in Dictionary(uniqueKeysWithValues: ids.map { ($0, frame) }) })
        }
    }
}

@Suite("WorkspaceBackend cell contract")
struct WorkspaceCellContractTests {
    private func cell(_ row: Int, _ column: Int) -> GridCell {
        GridCell(row: row, column: column)!
    }

    private func places(_ backend: any WorkspaceBackend) async throws -> [Int: Place] {
        Dictionary(
            uniqueKeysWithValues: try await backend.snapshot().windows.map { ($0.id.rawValue, $0.place) })
    }

    private func allCells(_ backend: any WorkspaceBackend) async throws -> [String: [WindowID]] {
        var listed: [String: [WindowID]] = [:]
        for row in 1...3 {
            for column in 1...GridCell.columnCount {
                let at = cell(row, column)
                listed[at.name] = try await backend.listWindows(in: at)
            }
        }
        return listed
    }

    // MARK: Reads

    @Test(arguments: ContractSubject.allCases)
    func listWindowsReportsEachCellsWindowsAndNothingForAnEmptyCell(subject: ContractSubject) async throws {
        let backend = try await subject.make()

        #expect(try await backend.listWindows(in: cell(1, 1)) == [WindowID(10)])
        #expect(try await backend.listWindows(in: cell(1, 2)) == [WindowID(11)])
        #expect(try await backend.listWindows(in: cell(2, 3)) == [WindowID(13)])
        #expect(try await backend.listWindows(in: cell(3, 3)).isEmpty)
    }

    @Test(arguments: ContractSubject.allCases)
    func snapshotReportsTheBenchAndTheShownRowsColumnsOnly(subject: ContractSubject) async throws {
        let backend = try await subject.make()

        let placed = try await places(backend)
        #expect(placed[10] == .workspace(.one))
        #expect(placed[11] == .workspace(.two))
        #expect(placed[12] == .bench)
        #expect(placed[13] == nil)

        try await backend.show(cell(2, 1))
        let inRowTwo = try await places(backend)
        #expect(inRowTwo[13] == .workspace(.three))
        #expect(inRowTwo[10] == nil)
        #expect(inRowTwo[11] == nil)
        #expect(inRowTwo[12] == .bench)
    }

    // MARK: Show

    @Test(arguments: ContractSubject.allCases)
    func showReturnsThePreviousCellAndIsReversible(subject: ContractSubject) async throws {
        let backend = try await subject.make()

        let left = try await backend.show(cell(2, 5))
        #expect(left == cell(1, 1))
        let back = try await backend.show(try #require(left))
        #expect(back == cell(2, 5))
        #expect(try await backend.show(cell(1, 1)) == cell(1, 1))
    }

    @Test(arguments: ContractSubject.allCases)
    func showMovesNoWindow(subject: ContractSubject) async throws {
        let backend = try await subject.make()
        let before = try await places(backend)
        let cells = try await allCells(backend)

        try await backend.show(cell(3, 7))
        try await backend.show(cell(1, 1))

        #expect(try await places(backend) == before)
        #expect(try await allCells(backend) == cells)
    }

    // MARK: Move

    @Test(arguments: ContractSubject.allCases)
    func moveToACellReturnsTheSlotItLeftAndIsReversible(subject: ContractSubject) async throws {
        let backend = try await subject.make()

        let left = try await backend.moveWindow(WindowID(10), to: cell(2, 5))
        #expect(left == .cell(cell(1, 1)))
        #expect(try await backend.listWindows(in: cell(2, 5)) == [WindowID(10)])
        #expect(try await backend.listWindows(in: cell(1, 1)).isEmpty)
        #expect(try await places(backend)[10] == nil)

        guard case .cell(let origin) = left else {
            Issue.record("a window that left a cell must report that cell")
            return
        }
        #expect(try await backend.moveWindow(WindowID(10), to: origin) == .cell(cell(2, 5)))
        #expect(try await backend.listWindows(in: cell(1, 1)) == [WindowID(10)])
    }

    @Test(arguments: ContractSubject.allCases)
    func movingOffTheBenchReportsTheBenchAndTheBenchIsReachableAgain(subject: ContractSubject) async throws {
        let backend = try await subject.make()

        #expect(try await backend.moveWindow(WindowID(12), to: cell(1, 4)) == .bench)
        #expect(try await places(backend)[12] == .workspace(.four))
        #expect(try await backend.moveWindow(WindowID(12), to: GridSlot.bench) == .cell(cell(1, 4)))
        #expect(try await places(backend)[12] == .bench)
    }

    @Test(arguments: ContractSubject.allCases)
    func movingOffTheBenchIntoAnotherRowIsReversibleWhateverRowIsShowing(subject: ContractSubject) async throws {
        let backend = try await subject.make()
        try await backend.show(cell(2, 1))

        #expect(try await backend.moveWindow(WindowID(12), to: cell(1, 3)) == .bench)
        #expect(try await backend.listWindows(in: cell(1, 3)) == [WindowID(12)])
        #expect(try await places(backend)[12] == nil)

        #expect(try await backend.moveWindow(WindowID(12), to: GridSlot.bench) == .cell(cell(1, 3)))
        #expect(try await backend.listWindows(in: cell(1, 3)).isEmpty)
        #expect(try await places(backend)[12] == .bench)
    }

    @Test(arguments: ContractSubject.allCases)
    func movingToTheCellItIsInChangesNothing(subject: ContractSubject) async throws {
        let backend = try await subject.make()

        #expect(try await backend.moveWindow(WindowID(11), to: cell(1, 2)) == .cell(cell(1, 2)))
        #expect(try await backend.listWindows(in: cell(1, 2)) == [WindowID(11)])
    }

    @Test(arguments: ContractSubject.allCases)
    func aPlaceMoveLandsInTheShownRow(subject: ContractSubject) async throws {
        let backend = try await subject.make()
        try await backend.show(cell(2, 1))

        #expect(try await backend.moveWindow(WindowID(13), to: .workspace(.six)) == .workspace(.three))

        #expect(try await backend.listWindows(in: cell(2, 6)) == [WindowID(13)])
        #expect(try await backend.listWindows(in: cell(1, 6)).isEmpty)
    }

    @Test(arguments: ContractSubject.allCases)
    func aWindowInAnotherRowIsUnknownToThePlaceApiAndFaithfulThroughTheCellApi(subject: ContractSubject) async throws {
        let backend = try await subject.make()
        try await backend.show(cell(2, 1))
        try await backend.moveWindow(WindowID(10), to: cell(1, 3))
        let cells = try await allCells(backend)

        #expect(try await places(backend)[10] == nil)
        await #expect(throws: BackendError.unknownWindow(WindowID(10))) {
            try await backend.moveWindow(WindowID(10), to: Place.bench)
        }
        await #expect(throws: BackendError.unknownWindow(WindowID(10))) {
            try await backend.moveWindow(WindowID(10), to: .workspace(.three))
        }
        #expect(try await allCells(backend) == cells)

        let left = try await backend.moveWindow(WindowID(10), to: cell(2, 3))
        #expect(left == .cell(cell(1, 3)))
        #expect(try await places(backend)[10] == .workspace(.three))
        #expect(try await backend.moveWindow(WindowID(10), to: cell(1, 3)) == .cell(cell(2, 3)))
        #expect(try await backend.listWindows(in: cell(1, 3)) == [WindowID(10)])
    }

    @Test(arguments: ContractSubject.allCases)
    func anUnknownWindowIsRejectedAndChangesNothing(subject: ContractSubject) async throws {
        let backend = try await subject.make()
        let before = try await places(backend)

        await #expect(throws: BackendError.unknownWindow(WindowID(99))) {
            try await backend.moveWindow(WindowID(99), to: GridCell(row: 1, column: 3)!)
        }
        await #expect(throws: BackendError.unknownWindow(WindowID(99))) {
            try await backend.moveWindow(WindowID(99), to: .workspace(.three))
        }
        #expect(try await places(backend) == before)
    }

    // MARK: The vault

    @Test(arguments: ContractSubject.allCases)
    func aWindowInTheVaultColumnIsNeverReportedAndNothingCanMoveItBack(subject: ContractSubject) async throws {
        let backend = try await subject.make()
        let vault = cell(1, GridCell.columnCount)

        #expect(try await backend.moveWindow(WindowID(12), to: vault) == .bench)

        let snapshot = try await backend.snapshot()
        #expect(!snapshot.windows.map(\.id).contains(WindowID(12)))
        #expect(try await backend.listWindows(in: vault).isEmpty)
        await #expect(throws: BackendError.unknownWindow(WindowID(12))) {
            try await backend.moveWindow(WindowID(12), to: GridCell(row: 1, column: 1)!)
        }
        await #expect(throws: BackendError.unknownWindow(WindowID(12))) {
            try await backend.moveWindow(WindowID(12), to: Place.bench)
        }
    }

    @Test(arguments: ContractSubject.allCases)
    func theVaultColumnCanBeShownByTheUserAndLeftAgain(subject: ContractSubject) async throws {
        let backend = try await subject.make()
        let vault = cell(1, GridCell.columnCount)

        #expect(try await backend.show(vault) == cell(1, 1))
        #expect(try await backend.show(cell(1, 1)) == vault)
    }
}
