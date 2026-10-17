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
| InputLayer | no | Registered Carbon hotkeys; CGEventTap fallback |
| KeyStateMachine | yes | Timestamped tap/hold, directional chords, carry ramp, reshape intents |
| Picker | yes | Rects + direction vector → target window |
| Unfold | yes | Pure `frame()` geometry |
| Spread | no | View mode with remembered frames |
| WorkspaceBackend | no | Replaceable substrate protocol; PR1 provides a deterministic fake |
| Executor | no | The only component allowed to change windows (`Sources/Chord/Executor`) |
| ChordShell | no | Menu-bar status, pause, permission, and launch-at-login controls; no window operations |
| Agents | no | Files emitting typed plans |

Exactly one arrow reaches the socket. CI enforces the backend boundary;
see `AGENTS.md` for the check.

## Rules

- Every action has an inverse and a log line.
- Agents emit typed plans and never touch windows.
- Plans naming unknown windows or duplicate windows are rejected or fall back
  to rules + bench. The vault cannot be represented in a Plan.
