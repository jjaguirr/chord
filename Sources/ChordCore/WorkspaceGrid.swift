/// One cell of the workspace grid: a context row under one of the nine columns the
/// user reaches with Option+1..9. Pure data; no window or substrate knowledge.
///
/// Rows and columns are 1-based. A cell converts to an agent-facing `Place` only when
/// its column is one `Workspace` names. The last column has no `Place` (no case exists
/// for it and none is added here), so an agent plan can never name it.
public struct GridCell: Hashable, Sendable, CustomStringConvertible {
    /// The columns of the grid: every `Workspace` plus the one `Place` cannot name.
    public static let columnCount = Workspace.allCases.count + 1

    public let row: Int
    public let column: Int

    /// Nil for a row below 1 or a column outside `1...columnCount`.
    public init?(row: Int, column: Int) {
        guard row >= 1, (1...Self.columnCount).contains(column) else { return nil }
        self.row = row
        self.column = column
    }

    private init(trustedRow row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    /// Row 1, column 1: where a grid starts.
    public static let first = GridCell(trustedRow: 1, column: 1)

    /// The cell in `row` that `place` names, or nil for the bench (it has no cell) and
    /// for a row below 1.
    public init?(row: Int, place: Place) {
        guard case .workspace(let workspace) = place else { return nil }
        self.init(row: row, column: workspace.rawValue)
    }

    /// The agent-facing place of this cell's column. Nil when `Place` has no case for it.
    public var place: Place? {
        Workspace(rawValue: column).map(Place.workspace)
    }

    /// Canonical name, `r<row>-<column>`, for example `r2-5`. This is the name a
    /// substrate workspace carries, and the text in log lines.
    public var name: String { "r\(row)-\(column)" }

    public var description: String { name }

    /// Parses exactly the text `name` produces. Anything else, including leading zeros,
    /// signs, spaces, or other case, is nil, so a foreign workspace is never mistaken
    /// for a cell.
    public init?(name: String) {
        let scalars = Array(name.unicodeScalars)
        guard scalars.count >= 4, scalars[0] == "r",
            let dash = scalars.firstIndex(of: "-")
        else { return nil }
        let rowDigits = scalars[1..<dash]
        let columnDigits = scalars[(dash + 1)...]
        guard let row = Self.canonicalNumber(rowDigits),
            let column = Self.canonicalNumber(columnDigits)
        else { return nil }
        self.init(row: row, column: column)
    }

    /// The same column in another row.
    public func inRow(_ row: Int) -> GridCell? {
        GridCell(row: row, column: column)
    }

    private static func canonicalNumber(_ digits: ArraySlice<Unicode.Scalar>) -> Int? {
        guard let first = digits.first, digits.count <= 9,
            digits.allSatisfy({ ("0"..."9").contains($0) })
        else { return nil }
        if first == "0" { return nil }
        return Int(String(String.UnicodeScalarView(digits)))
    }
}

/// Where a window sits in the grid: in a cell, or on the bench (the undecided pile).
public enum GridSlot: Hashable, Sendable, CustomStringConvertible {
    case cell(GridCell)
    case bench

    /// The substrate workspace name of the bench.
    public static let benchName = "bench"

    public var name: String {
        switch self {
        case .cell(let cell): return cell.name
        case .bench: return Self.benchName
        }
    }

    public var description: String { name }

    /// Parses `GridSlot.name`. Nil for any other workspace name.
    public init?(name: String) {
        if name == Self.benchName {
            self = .bench
        } else if let cell = GridCell(name: name) {
            self = .cell(cell)
        } else {
            return nil
        }
    }

    /// The slot `place` names when rows are read in `row`: the bench stays the bench.
    public init?(row: Int, place: Place) {
        switch place {
        case .bench: self = .bench
        case .workspace:
            guard let cell = GridCell(row: row, place: place) else { return nil }
            self = .cell(cell)
        }
    }

    /// The agent-facing place. Nil for a cell whose column `Place` cannot name.
    public var place: Place? {
        switch self {
        case .cell(let cell): return cell.place
        case .bench: return .bench
        }
    }
}

/// One step across the grid.
public enum GridStep: Equatable, Sendable {
    case left, down, up, right
}

/// The grid of workspaces and which cell is showing. Rows are contexts, columns are
/// the nine Option+1..9 places. Pure: events in, new state out. It touches no window.
public struct WorkspaceGrid: Equatable, Sendable {
    // DECISION: three rows. The planner decisions fix the columns (nine) and say rows
    // are contexts, but not how many. Three is the smallest count that still shows a
    // row above and below the current one; callers may pass another count.
    public static let defaultRowCount = 3

    public let rowCount: Int
    /// Whether `neighbour` continues from the opposite edge instead of stopping.
    public let wrap: Bool
    public private(set) var current: GridCell

    /// Starts on row 1, column 1. A row count below 1 is raised to 1.
    public init(rowCount: Int = WorkspaceGrid.defaultRowCount, wrap: Bool = false) {
        self.rowCount = max(1, rowCount)
        self.wrap = wrap
        self.current = .first
    }

    /// Whether `cell` lies inside this grid.
    public func contains(_ cell: GridCell) -> Bool {
        cell.row <= rowCount
    }

    /// Shows `cell` and returns the cell it replaced, which is the inverse: showing
    /// the returned cell restores the previous state. A cell outside the grid is
    /// refused and changes nothing.
    @discardableResult
    public mutating func show(_ cell: GridCell) -> GridCell? {
        guard contains(cell) else { return nil }
        let previous = current
        current = cell
        return previous
    }

    /// The cell one step from `current`, or nil when the step leaves the grid and the grid
    /// does not wrap: the edge stops a step, so a repeated key never lands somewhere
    /// surprising. A grid that wraps continues from the opposite edge; a step that wraps
    /// onto the cell it started from (one row, or one column) returns `current`.
    public func neighbour(_ step: GridStep) -> GridCell? {
        var row = current.row
        var column = current.column
        switch step {
        case .left: column -= 1
        case .right: column += 1
        case .up: row -= 1
        case .down: row += 1
        }
        if wrap {
            row = (row - 1 + rowCount) % rowCount + 1
            column = (column - 1 + GridCell.columnCount) % GridCell.columnCount + 1
        }
        return GridCell(row: row, column: column).flatMap { contains($0) ? $0 : nil }
    }

    /// The cell in the current row that `place` names; nil for the bench.
    public func cell(for place: Place) -> GridCell? {
        GridCell(row: current.row, place: place)
    }

    /// The slot `place` names in the current row.
    public func slot(for place: Place) -> GridSlot? {
        GridSlot(row: current.row, place: place)
    }

    /// Log line for showing `slot` (a cell or the bench). `previous` is nil when what was
    /// showing is a workspace Chord did not create.
    public static func logLine(showing slot: GridSlot, from previous: GridSlot?) -> String {
        "show workspace \(slot.name) (was \(previous?.name ?? "none"))"
    }

    /// Log line for moving a window.
    public static func logLine(moving windowID: Int, from previous: GridSlot, to slot: GridSlot) -> String {
        "move window \(windowID): \(previous.name) -> \(slot.name)"
    }
}
