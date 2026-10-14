# ARCHITECTURE.md

**One rule:** everything that decides is pure; everything that acts goes
through the Executor.

**Substrate:** AeroSpace, run headless (pinned version), over its
documented Unix socket. No key bindings, a rule that floats every window,
persistent workspaces. Chord reads window geometry itself. The backend
sits behind a protocol so it can be replaced.

## Modules

| Module | Pure? | Job |
|---|---|---|
| InputLayer | no | Registered Carbon hotkeys; CGEventTap fallback |
| KeyStateMachine | yes | Tap/hold, chords, held-key repeat |
| Picker | yes | Rects + direction vector → target window |
| Unfold | yes | Pure `frame()` geometry |
| Spread | no | View mode with remembered frames |
| WorkspaceBackend | no | AeroSpace socket implementation |
| Executor | no | The only component allowed to change windows |
| Agents | no | Files emitting typed plans |

Exactly one arrow reaches the socket. CI enforces the backend boundary;
see `AGENTS.md` for the check.

## Rules

- Every action has an inverse and a log line.
- Agents emit typed plans and never touch windows.
- Plans that name unknown windows, contain duplicates, or target the
  vault are rejected or fall back to rules + bench.
