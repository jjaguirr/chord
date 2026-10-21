/// The shape of the workspace grid as the user configured it: how many rows of contexts sit
/// under the nine columns, what they are called, and what a step off the edge does.
/// Pure data; `Config` reads it from `[workspaces]`.
public struct WorkspaceLayout: Equatable, Sendable {
    // DECISION: at most nine rows, a grid as tall as it is wide. Nothing in the substrate
    // limits rows (a workspace is just `r<row>-<column>`); more than nine contexts is more
    // than the j/k layer is a good way to reach. Raise the cap here if that turns out wrong.
    public static let maxRows = 9

    public let rows: Int
    /// One name per row, or empty when rows are unnamed. Never partial.
    public let rowNames: [String]
    /// Whether a step past the last row or column lands on the first (and the reverse)
    /// instead of doing nothing.
    public let wrap: Bool

    // DECISION: clamp by default. A repeated key never lands somewhere surprising; wrap is
    // opt-in with `wrap = true`.
    public static let defaults = WorkspaceLayout()

    /// Rows are raised to at least 1 and capped at `maxRows`; names are kept only when
    /// there is exactly one per row.
    public init(
        rows: Int = WorkspaceGrid.defaultRowCount, rowNames: [String] = [], wrap: Bool = false
    ) {
        let rows = min(max(1, rows), Self.maxRows)
        self.rows = rows
        self.rowNames = rowNames.count == rows ? rowNames : []
        self.wrap = wrap
    }

    /// The name of 1-based `row`, nil when rows are unnamed or `row` is outside the grid.
    public func name(ofRow row: Int) -> String? {
        rowNames.indices.contains(row - 1) ? rowNames[row - 1] : nil
    }

    /// `r2-3`, or `r2-3 (row "work")` when the row has a name. For log lines.
    public func label(_ cell: GridCell) -> String {
        guard let name = name(ofRow: cell.row) else { return cell.name }
        return "\(cell.name) (row \"\(name)\")"
    }
}
