import ChordCore
import Foundation

/// A `WorkspaceBackend` over a pinned AeroSpace server: the interim engine until
/// Chord has its own workspace model. Everything AeroSpace-specific lives in this
/// file, `AeroSpaceWire`, and `AeroSpaceSocket`; a second adapter replaces it by
/// passing the same contract tests.
///
/// Each grid cell is one AeroSpace workspace named `r<row>-<column>` (`GridCell.name`),
/// and the bench is the workspace `bench`. AeroSpace is flat, so rows exist only in
/// that naming. Any other workspace (AeroSpace's own `1`, `2`, ..., or a stock-config
/// `9`) is not Chord's: its windows are never reported, listed, or moved, and are
/// unknown to every caller exactly like a window in the vault column.
///
/// The `Place`-typed API acts only on the row showing now (the focused workspace's row):
/// `snapshot()` omits windows sitting in other rows, and `moveWindow(_, to: Place)` on one
/// throws `.unknownWindow` with nothing changed. When the focused workspace is not a grid
/// cell (the bench, a stock-config `9`, any foreign workspace) no row is showing: `snapshot()`
/// reports no windows and a `Place`-typed move throws `.unknown` with nothing sent. Windows
/// stay reachable through `listWindows(in:)` and `moveWindow(_, to: GridSlot)`, which work
/// in any row and on the bench, whatever is showing, and report a faithful `GridSlot`.
///
/// Every call returns a confirmed result or throws, and a failure is never silent
/// success: a server that is unreachable, disabled, or not the pinned version throws
/// `.notConnected` (nothing was applied); any other failure after a command may have
/// reached the server throws `.unknown`. Before any change this backend reads from the
/// server, so a wrong version is refused before anything is applied.
///
/// AeroSpace does not report or set frames, and per-frame work never goes through it
/// (spike 6b: reads cost tens of milliseconds). Snapshots take frames from the window
/// server, and `applyFrame`, `focusWindow`, and `raiseWindow` belong to the Accessibility
/// backend.
public actor AeroSpaceBackend: WorkspaceBackend {
    typealias FrameSource = @Sendable ([WindowID]) -> [WindowID: ScreenRect]

    private let transport: any AeroSpaceTransport
    private let pinnedTag: String
    private let monitors: @Sendable () -> [MonitorSnapshot]
    private let frames: FrameSource

    init(
        transport: any AeroSpaceTransport,
        pinnedTag: String,
        monitors: @escaping @Sendable () -> [MonitorSnapshot] = { ScreenGeometry.monitors() },
        frames: @escaping FrameSource = { WindowFrameReader.frames(of: $0) }
    ) {
        self.transport = transport
        self.pinnedTag = pinnedTag
        self.monitors = monitors
        self.frames = frames
    }

    // MARK: Reads

    public func snapshot() async throws -> BackendSnapshot {
        let rows = try await readWindows()
        let focused = try await readFocusedWindow()
        let shown = try await shownRow()
        let reported = rows.compactMap { row -> (Row, Place)? in
            guard let shown, row.isPlaced(inRow: shown), let place = row.slot.place else { return nil }
            return (row, place)
        }
        let bounds = frames(reported.map(\.0.id))
        let windows = reported.compactMap { row, place -> WindowSnapshot? in
            guard let frame = bounds[row.id] else { return nil }
            return WindowSnapshot(
                id: row.id, appName: row.appName, place: place, isFloating: row.isFloating, bounds: frame)
        }
        let ids = Set(windows.map(\.id))
        return BackendSnapshot(
            monitors: monitors(), windows: windows,
            focusedWindow: focused.flatMap { ids.contains($0) ? $0 : nil })
    }

    public func listWindows(in cell: GridCell) async throws -> [WindowID] {
        // The vault column is never reported, so there is nothing to read.
        guard cell.place != nil else { return [] }
        return try await readWindows().filter { $0.slot == .cell(cell) }.map(\.id)
    }

    // MARK: Changes

    @discardableResult
    public func show(_ slot: GridSlot) async throws -> GridSlot? {
        let name = try await readFocusedWorkspace()
        let previous = GridSlot(name: name)
        // Already showing: send nothing, so AeroSpace's back-and-forth setting cannot
        // turn a repeat key into a switch away.
        if name != slot.name {
            try requireSuccess(try await send(.showWorkspace(slot.name), isRead: false))
        }
        return previous
    }

    public func showing() async throws -> GridSlot? {
        GridSlot(name: try await readFocusedWorkspace())
    }

    public func focusedWindow() async throws -> WindowID? {
        guard let id = try await readFocusedWindow() else { return nil }
        // A window on a workspace Chord did not create, or in the vault column, is unknown.
        guard let row = try await readWindows().first(where: { $0.id == id }), row.slot.place != nil else {
            return nil
        }
        return id
    }

    @discardableResult
    public func moveWindow(_ id: WindowID, to slot: GridSlot) async throws -> GridSlot {
        try await relocate(id, to: slot)
    }

    @discardableResult
    public func moveWindow(_ id: WindowID, to place: Place) async throws -> Place {
        guard let shown = try await shownRow() else {
            throw BackendError.unknown(reason: "no row is showing: the focused workspace is not a grid cell")
        }
        guard let slot = GridSlot(row: shown, place: place) else {
            throw BackendError.unknown(reason: "no workspace for that place in row \(shown)")
        }
        let previous = try await relocate(id, to: slot, placedInRow: shown)
        // A window placed in the shown row is on the bench or in a column `Place` names.
        return previous.place ?? .bench
    }

    @discardableResult
    public func applyFrame(_ id: WindowID, to frame: ScreenRect) async throws -> ScreenRect {
        throw BackendError.unknown(reason: "AeroSpace does not set frames; frames go through the Accessibility backend")
    }

    @discardableResult
    public func focusWindow(_ id: WindowID) async throws -> WindowID? {
        throw BackendError.unknown(reason: "AeroSpace does not focus single windows here; focus goes through the Accessibility backend")
    }

    public func raiseWindow(_ id: WindowID) async throws {
        throw BackendError.unknown(reason: "AeroSpace does not raise windows; raising goes through the Accessibility backend")
    }

    public func reconnect() async throws {
        await transport.reset()
        // A read proves the server answers, is enabled, and is the pinned version.
        _ = try await readFocusedWorkspace()
    }

    // MARK: Moving

    /// Moves `id` to `slot` and returns the slot it left. Reads first, which proves the
    /// window exists and the server is the pinned version; a window already in `slot`
    /// is left alone and nothing is sent. With `placedInRow`, a window in another row is
    /// unknown, because the `Place` API cannot name where it is.
    private func relocate(_ id: WindowID, to slot: GridSlot, placedInRow shown: Int? = nil) async throws -> GridSlot {
        guard let found = try await readWindows().first(where: { $0.id == id }) else {
            throw BackendError.unknownWindow(id)
        }
        // A window in the vault column is unknown to every caller.
        guard found.slot.place != nil else { throw BackendError.unknownWindow(id) }
        if let shown, !found.isPlaced(inRow: shown) { throw BackendError.unknownWindow(id) }
        if found.slot == slot { return found.slot }
        try requireSuccess(try await send(.moveWindow(id, toWorkspace: slot.name), isRead: false))
        return found.slot
    }

    /// The row of the focused workspace, or nil when it is not a grid cell.
    private func shownRow() async throws -> Int? {
        GridCell(name: try await readFocusedWorkspace())?.row
    }

    // MARK: Protocol

    private struct Row {
        let id: WindowID
        let slot: GridSlot
        let isFloating: Bool
        let appName: String

        /// Whether the `Place` API reports this window when `shown` is the row showing:
        /// on the bench, or in a column of that row.
        func isPlaced(inRow shown: Int) -> Bool {
            switch slot {
            case .bench: return true
            case .cell(let cell): return cell.row == shown && cell.place != nil
            }
        }
    }

    private func readWindows() async throws -> [Row] {
        let answer = try await send(.listAllWindows, isRead: true)
        try requireSuccess(answer)
        return try answer.stdout.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let fields = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count == 4, let id = Int(fields[0]) else {
                throw BackendError.unknown(reason: "list-windows answered a line this build cannot read")
            }
            guard let slot = GridSlot(name: String(fields[1])) else { return nil }
            return Row(
                id: WindowID(id), slot: slot,
                isFloating: fields[2] == "floating", appName: String(fields[3]))
        }
    }

    /// The focused window, or nil when none has focus. AeroSpace reports "no focused
    /// window" as an error, so any failed answer reads as none.
    private func readFocusedWindow() async throws -> WindowID? {
        let answer = try await send(.focusedWindowID, isRead: true)
        guard answer.exitCode == 0 else { return nil }
        return Int(answer.stdout.trimmingCharacters(in: .whitespacesAndNewlines)).map(WindowID.init)
    }

    private func readFocusedWorkspace() async throws -> String {
        let answer = try await send(.focusedWorkspace, isRead: true)
        try requireSuccess(answer)
        let name = answer.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw BackendError.unknown(reason: "AeroSpace reported no focused workspace") }
        return name
    }

    /// Sends `command` and maps transport failure and a disabled or wrong-version server
    /// onto the backend taxonomy. The version is enforced on reads only: after a change
    /// was sent, refusing its answer as "not connected" would claim nothing applied.
    private func send(_ command: AeroSpaceCommand, isRead: Bool) async throws -> AeroSpaceAnswer {
        let answer: AeroSpaceAnswer
        do {
            answer = try await transport.send(command)
        } catch AeroSpaceTransportError.cannotConnect, AeroSpaceTransportError.protocolMismatch {
            throw BackendError.notConnected
        } catch AeroSpaceTransportError.noReply(let reason) {
            throw BackendError.unknown(reason: "no confirmed answer from AeroSpace: \(reason)")
        } catch {
            throw BackendError.unknown(reason: "AeroSpace call failed: \(error.localizedDescription)")
        }
        if answer.isServerDisabled { throw BackendError.notConnected }
        if isRead,
            !AeroSpaceVersion.matches(pinnedTag: pinnedTag, serverVersionAndHash: answer.serverVersionAndHash)
        {
            throw BackendError.notConnected
        }
        return answer
    }

    private func requireSuccess(_ answer: AeroSpaceAnswer) throws {
        guard answer.exitCode == 0 else {
            let line = answer.stderr.split(separator: "\n").first.map(String.init) ?? "exit code \(answer.exitCode)"
            throw BackendError.unknown(reason: "AeroSpace refused the command: \(LogPolicy.clipped(line))")
        }
    }
}

extension AeroSpaceBackend {
    /// The backend over the user's AeroSpace socket. The shell builds it here so the
    /// socket client stays inside `Backend/`.
    static func live(pinnedTag: String) -> AeroSpaceBackend {
        AeroSpaceBackend(transport: AeroSpaceSocket(), pinnedTag: pinnedTag)
    }
}
