/// What Chord last saw showing, for the two things Option+Tab and Option+1..9 need to
/// remember: the slot shown before (`previous`) and the row the user is in (kept while the
/// bench or a foreign workspace is showing, which have no row of their own).
///
/// Pure memory, never the truth: the substrate decides what is showing, and the user can
/// switch without Chord (the mouse, another tool). Callers `observe` what the substrate
/// reports before they plan, and again after every change they make.
public struct WorkspaceNavigation: Equatable, Sendable {
    public private(set) var grid: WorkspaceGrid
    /// What was showing at the last observation: a cell, the bench, or nil for a workspace
    /// Chord did not create (or nothing observed yet).
    public private(set) var showing: GridSlot?
    /// What was showing before `showing`, when that was a slot Chord can name.
    public private(set) var previous: GridSlot?

    public init(rowCount: Int = WorkspaceGrid.defaultRowCount) {
        grid = WorkspaceGrid(rowCount: rowCount)
    }

    /// Records what the substrate says is showing now. A change from a known slot makes
    /// that slot `previous`, whoever caused it; seeing the same slot again changes nothing.
    public mutating func observe(_ slot: GridSlot?) {
        guard slot != showing else { return }
        if let showing { previous = showing }
        showing = slot
        // Leaving a slot for a foreign workspace and coming back: nothing else to return to.
        if previous == slot { previous = nil }
        if case .cell(let cell)? = slot { grid.show(cell) }
    }

    /// Column `column` of the remembered row: nil for a column outside `1...columnCount`.
    public func cell(column: Int) -> GridCell? {
        GridCell(row: grid.current.row, column: column)
    }
}
