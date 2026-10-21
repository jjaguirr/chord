# ARCHITECTURE.md

**One rule:** everything that decides is pure; everything that acts goes
through the Executor.

**Provisional substrate:** AeroSpace, evaluated as a replaceable backend over
its documented Unix socket. The intended configuration disables AeroSpace key
bindings, floats every window, and uses persistent workspaces; operational
behavior is not yet validated. Chord reads window geometry itself. See the
[C6 substrate report](C6-SUBSTRATE.md) for evidence and remaining gaps.

## Modules

| Module | Pure? | Job |
|---|---|---|
| InputLayer | no | Registered Carbon hotkeys; CGEventTap fallback for keys Carbon cannot register, and a passive Carbon cross-check that only logs (`Sources/Chord/Input`). Behind a `HotkeySource` protocol; feeds KeyStateMachine, logs intents, and hands them to WindowMotion |
| WindowMotion | no | Turns captured intents into Executor calls: Unfold stepper timing (elapsed-time frame skipping), Reshape, Carry, Look, workspace switch and carry (`Sources/Chord/Motion`). Makes no window call itself |
| KeyStateMachine | yes | Timestamped tap/hold, directional chords, carry ramp, reshape intents; a fresh carry press at a visible-frame edge emits `carryAcross` |
| Picker | yes | Rects + direction vector → target window. `Look` adds monitors: same-monitor pool first, then the adjacent monitor at an edge (tie rules in `Look.swift`). `MonitorAdjacency` holds the shared monitor adjacency and landing rule that Look and cross-monitor carry use |
| Unfold | yes | Pure `frame()` geometry and press/timer state machine |
| WorkspaceNavigation | yes | Memory of what was last seen showing, the previous slot (Option+Tab) and the row Option+N acts in; never the truth, the backend's `showing()` is |
| Spread | no | View mode with remembered frames |
| WorkspaceBackend | no | Replaceable substrate protocol. A deterministic fake; `AXWindowBackend` (Accessibility only: focused window, or every visible window for Look; no workspaces; AX writes are `Executor/AXWindowWriter`); and `AeroSpaceBackend`, the interim workspace engine (a cell of the pure `WorkspaceGrid` is one named AeroSpace workspace; windows on any workspace Chord did not name are never reported or moved, so a stock-config workspace `9` stays invisible; the `Place`-typed API acts only on the row showing now, windows in other rows being omitted from `snapshot()` and unknown to `Place`-typed moves; with no grid cell focused (the bench, a foreign workspace) `snapshot()` reports no windows and `Place`-typed moves throw `.unknown`, never defaulting to row 1, while the slot-typed `moveWindow(_, to: GridSlot)` and `listWindows(in:)` reach every row and the bench whatever is showing; `AeroSpaceWire`/`AeroSpaceSocket` are the only socket code; `AeroSpaceDoctor` reports a missing, disabled, or wrong-version server and never starts or enables it). One cell contract runs over every backend with workspaces. Per-frame motion never goes through AeroSpace (spike 6). `show(_ slot:)` shows a cell or the bench; `showing()` and `focusedWindow()` read what is showing and the focused window wherever it sits; `SplitBackend` is the live composite (frames, focus and snapshots from `AXWindowBackend`, workspaces from `AeroSpaceBackend`; the two sides' window ids are separate namespaces) |
| Executor | no | The only component allowed to change windows (`Sources/Chord/Executor`) |
| ChordShell | no | Menu-bar status, pause, permission, launch-at-login, update, and diagnostics controls; no window operations. Update implementation is in `Sources/Chord/Update` |
| Agents | no | Files emitting typed plans |

Exactly one arrow reaches the socket. CI enforces the backend boundary;
see `AGENTS.md` for the check.

## Rules

- Every action has an inverse and a log line.
- Agents emit typed plans and never touch windows.
- Plans naming unknown windows or duplicate windows are rejected or fall back
  to rules + bench. The vault cannot be represented in a Plan.
