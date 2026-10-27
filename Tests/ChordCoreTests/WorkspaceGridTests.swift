import Testing
@testable import ChordCore

@Suite("WorkspaceGrid")
struct WorkspaceGridTests {
    private func cell(_ row: Int, _ column: Int) -> GridCell {
        guard let cell = GridCell(row: row, column: column) else {
            fatalError("test cell r\(row)-\(column) is out of range")
        }
        return cell
    }

    // MARK: Cells and names

    @Test func columnsAreEveryWorkspacePlusTheOneNoPlaceNames() {
        #expect(GridCell.columnCount == 9)
        #expect(GridCell(row: 1, column: 0) == nil)
        #expect(GridCell(row: 1, column: 10) == nil)
        #expect(GridCell(row: 0, column: 1) == nil)
        #expect(GridCell(row: -1, column: 1) == nil)
    }

    @Test func everyCellNameRoundTrips() {
        for row in 1...12 {
            for column in 1...GridCell.columnCount {
                let original = cell(row, column)
                #expect(GridCell(name: original.name) == original)
                #expect(GridSlot(name: original.name) == .cell(original))
            }
        }
        #expect(cell(2, 5).name == "r2-5")
    }

    @Test func benchNameRoundTripsAndIsNotACell() {
        #expect(GridSlot(name: GridSlot.benchName) == .bench)
        #expect(GridSlot.bench.name == GridSlot.benchName)
        #expect(GridCell(name: GridSlot.benchName) == nil)
    }

    @Test func foreignAndNonCanonicalNamesAreNotCells() {
        let foreign = [
            "", "1", "2", "r", "r1", "r1-", "r-1", "r1-0", "r1-10", "r0-1", "r01-1", "r1-01",
            "R1-1", "r1-1 ", " r1-1", "r+1-1", "r1--1", "r1-1-2", "r١-1", "bench ", "Bench",
            "r1-1\n", "r9999999999-1",
        ]
        for name in foreign {
            #expect(GridCell(name: name) == nil, "\(name.debugDescription) must not parse")
            #expect(GridSlot(name: name) == nil, "\(name.debugDescription) must not parse as a slot")
        }
    }

    // MARK: Places and the vault

    @Test func onlyWorkspaceColumnsHaveAPlaceAndTheVaultColumnHasNone() {
        for workspace in Workspace.allCases {
            #expect(cell(3, workspace.rawValue).place == .workspace(workspace))
            #expect(GridCell(row: 3, place: .workspace(workspace)) == cell(3, workspace.rawValue))
        }
        let vaultColumn = GridCell.columnCount
        #expect(cell(1, vaultColumn).place == nil)
        #expect(GridSlot.cell(cell(1, vaultColumn)).place == nil)
    }

    @Test func noPlaceMapsToTheVaultColumn() {
        for workspace in Workspace.allCases {
            #expect(GridCell(row: 1, place: .workspace(workspace))?.column != GridCell.columnCount)
        }
        #expect(Workspace.allCases.count == GridCell.columnCount - 1)
    }

    @Test func benchHasNoCellButIsAPlaceAndASlot() {
        #expect(GridCell(row: 1, place: .bench) == nil)
        #expect(GridSlot(row: 2, place: .bench) == .bench)
        #expect(GridSlot.bench.place == .bench)
        #expect(GridSlot(row: 2, place: .workspace(.six)) == .cell(cell(2, 6)))
    }

    // MARK: Showing and stepping

    @Test func startsAtRowOneColumnOne() {
        let grid = WorkspaceGrid()
        #expect(grid.current == cell(1, 1))
        #expect(grid.rowCount == WorkspaceGrid.defaultRowCount)
    }

    @Test func showReturnsThePreviousCellAndIsReversible() {
        var grid = WorkspaceGrid(rowCount: 3)
        let start = grid.current

        #expect(grid.show(cell(2, 5)) == start)
        #expect(grid.current == cell(2, 5))
        #expect(grid.show(start) == cell(2, 5))
        #expect(grid == WorkspaceGrid(rowCount: 3))
    }

    @Test func showRefusesACellBeyondTheLastRowAndChangesNothing() {
        var grid = WorkspaceGrid(rowCount: 2)
        #expect(grid.show(cell(3, 1)) == nil)
        #expect(grid.current == cell(1, 1))
    }

    @Test func rowCountBelowOneIsRaisedToOne() {
        #expect(WorkspaceGrid(rowCount: 0).rowCount == 1)
        #expect(WorkspaceGrid(rowCount: -4).rowCount == 1)
    }

    @Test func stepsMoveOneCellAndEveryEdgeRefusesWithoutWrapping() {
        var grid = WorkspaceGrid(rowCount: 3)
        #expect(grid.neighbour(.left) == nil)
        #expect(grid.neighbour(.up) == nil)
        #expect(grid.neighbour(.right) == cell(1, 2))
        #expect(grid.neighbour(.down) == cell(2, 1))

        grid.show(cell(3, GridCell.columnCount))
        #expect(grid.neighbour(.right) == nil)
        #expect(grid.neighbour(.down) == nil)
        #expect(grid.neighbour(.left) == cell(3, GridCell.columnCount - 1))
        #expect(grid.neighbour(.up) == cell(2, GridCell.columnCount))
    }

    @Test func aWrappingGridContinuesFromTheOppositeEdge() {
        var grid = WorkspaceGrid(rowCount: 3, wrap: true)
        #expect(grid.neighbour(.left) == cell(1, GridCell.columnCount))
        #expect(grid.neighbour(.up) == cell(3, 1))

        grid.show(cell(3, GridCell.columnCount))
        #expect(grid.neighbour(.right) == cell(3, 1))
        #expect(grid.neighbour(.down) == cell(1, GridCell.columnCount))
    }

    @Test func aWrappingGridOfOneRowStepsBackOntoItsOwnRow() {
        let grid = WorkspaceGrid(rowCount: 1, wrap: true)
        #expect(grid.neighbour(.up) == grid.current)
        #expect(grid.neighbour(.down) == grid.current)
    }

    @Test func everyStepIsInsideTheGridOrRefusedFromEveryCell() {
        for wrap in [false, true] {
            for rows in 1...4 {
                for row in 1...rows {
                    for column in 1...GridCell.columnCount {
                        var grid = WorkspaceGrid(rowCount: rows, wrap: wrap)
                        grid.show(cell(row, column))
                        for step in [GridStep.left, .right, .up, .down] {
                            let target = grid.neighbour(step)
                            #expect(target.map(grid.contains) ?? !wrap)
                        }
                    }
                }
            }
        }
    }

    @Test func placesResolveInTheCurrentRow() {
        var grid = WorkspaceGrid(rowCount: 3)
        grid.show(cell(2, 1))
        #expect(grid.cell(for: .workspace(.four)) == cell(2, 4))
        #expect(grid.slot(for: .bench) == .bench)
        #expect(grid.cell(for: .bench) == nil)
    }

    @Test func logLinesNameTheCellsAndWindow() {
        #expect(WorkspaceGrid.logLine(showing: .cell(cell(2, 5)), from: .cell(cell(1, 1))) == "show workspace r2-5 (was r1-1)")
        #expect(WorkspaceGrid.logLine(showing: .cell(cell(2, 5)), from: nil) == "show workspace r2-5 (was none)")
        #expect(WorkspaceGrid.logLine(showing: .bench, from: .cell(cell(1, 1))) == "show workspace bench (was r1-1)")
        #expect(
            WorkspaceGrid.logLine(moving: 7, from: .bench, to: .cell(cell(1, 3))) == "move window 7: bench -> r1-3")
    }
}
