import Testing
@testable import ChordCore

@Suite("WorkspaceNavigation")
struct WorkspaceNavigationTests {
    private func cell(_ row: Int, _ column: Int) -> GridSlot {
        guard let cell = GridCell(row: row, column: column) else {
            fatalError("test cell r\(row)-\(column) is out of range")
        }
        return .cell(cell)
    }

    @Test func aColumnIsReadInTheRowShowingNow() {
        var navigation = WorkspaceNavigation(layout: WorkspaceLayout(rows: 3))
        navigation.observe(cell(2, 4))

        #expect(navigation.cell(column: 7)?.name == "r2-7")
        #expect(navigation.cell(column: 9)?.name == "r2-9")
    }

    @Test func aColumnOutsideTheNineIsNoCell() {
        let navigation = WorkspaceNavigation()
        #expect(navigation.cell(column: 0) == nil)
        #expect(navigation.cell(column: GridCell.columnCount + 1) == nil)
        #expect(navigation.cell(column: -3) == nil)
    }

    @Test func theRowIsRememberedWhileTheBenchOrAForeignWorkspaceShows() {
        var navigation = WorkspaceNavigation(layout: WorkspaceLayout(rows: 3))
        navigation.observe(cell(3, 2))

        navigation.observe(.bench)
        #expect(navigation.cell(column: 5)?.name == "r3-5")
        navigation.observe(nil)
        #expect(navigation.cell(column: 5)?.name == "r3-5")
    }

    @Test func aChangePutsTheOldSlotInPreviousAndSeeingItAgainChangesNothing() {
        var navigation = WorkspaceNavigation()
        navigation.observe(cell(1, 1))
        #expect(navigation.previous == nil)

        navigation.observe(cell(1, 5))
        #expect(navigation.previous == cell(1, 1))
        navigation.observe(cell(1, 5))
        #expect(navigation.previous == cell(1, 1))
        #expect(navigation.showing == cell(1, 5))
    }

    @Test func goingBackAndBackAgainTogglesBetweenTwoSlots() {
        var navigation = WorkspaceNavigation()
        navigation.observe(cell(1, 2))
        navigation.observe(cell(1, 6))

        for _ in 0..<3 {
            let back = navigation.previous
            navigation.observe(back)
            #expect(navigation.showing == cell(1, 2))
            let forth = navigation.previous
            navigation.observe(forth)
            #expect(navigation.showing == cell(1, 6))
        }
    }

    @Test func theBenchIsAPreviousSlotLikeAnyOther() {
        var navigation = WorkspaceNavigation()
        navigation.observe(cell(1, 3))
        navigation.observe(.bench)
        #expect(navigation.previous == cell(1, 3))

        navigation.observe(navigation.previous)
        #expect(navigation.showing == cell(1, 3))
        #expect(navigation.previous == .bench)
    }

    @Test func aSwitchMadeOutsideChordStillCountsAsTheSlotLeft() {
        var navigation = WorkspaceNavigation()
        navigation.observe(cell(1, 3))
        navigation.observe(cell(2, 8))  // the user switched without Chord

        #expect(navigation.previous == cell(1, 3))
        #expect(navigation.cell(column: 1)?.name == "r2-1")
    }

    @Test func comingBackFromAForeignWorkspaceLeavesNothingToGoBackTo() {
        var navigation = WorkspaceNavigation()
        navigation.observe(cell(1, 4))
        navigation.observe(nil)
        navigation.observe(cell(1, 4))

        #expect(navigation.previous == nil)
    }

    @Test func aForeignWorkspaceIsNeverARememberedPrevious() {
        var navigation = WorkspaceNavigation()
        navigation.observe(nil)
        navigation.observe(cell(1, 4))

        #expect(navigation.previous == nil)
    }

    @Test func leavingForAForeignWorkspaceKeepsTheLastKnownSlotToReturnTo() {
        var navigation = WorkspaceNavigation()
        navigation.observe(cell(1, 4))
        navigation.observe(nil)

        #expect(navigation.previous == cell(1, 4))
    }

    @Test func aCellBeyondTheLastRowIsNotUsedAsANavigationOrigin() {
        var navigation = WorkspaceNavigation(layout: WorkspaceLayout(rows: 2))
        navigation.observe(cell(2, 1))
        navigation.observe(cell(5, 1))

        #expect(navigation.grid.current.name == "r2-1")
        #expect(navigation.showingOutsideGrid?.name == "r5-1")
    }
}
