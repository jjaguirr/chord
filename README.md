# Chord
### Beautiful window management. *(working name)*

Chord is a keyboard-first window manager for macOS. It decides **where**
windows live and **how you move between them** — and leaves **size** to you.

> **Status: pre-alpha, app shell, input capture, and four window moves.** Chord builds
> as a menu-bar agent bundle (`scripts/build-app.sh`) with an Accessibility permission
> flow, a pause switch, launch at login, and global Option hotkey capture that logs
> every captured key and the intent the key state machine derives from it. With
> Accessibility granted, Option+h/j/k/l moves focus at once to the nearest visible
> window in that direction (across monitors at a monitor edge), Option+0 taps run Unfold,
> Option+R then h/j/k/l reshapes, and Option+Shift+h/j/k/l carries the focused window,
> through the Accessibility API directly. Each move is logged and undoable in the
> Executor (no undo key yet). Option+1-9 shows a workspace column and Option+Shift+1-9
> carries the focused window there, Option+backtick shows the bench and Option+Tab goes
> back, through AeroSpace (a pinned server must be running; Chord never starts it). Not
> yet verified on live windows. Spread is not wired.

## The bet

Windows are paper on a desk, not walls of a room. Most window managers
decide how big things should be. Chord doesn't. It decides where things
live and how you move between them.

If the keyboard grammar feels as good in the hand as it does on paper,
this is worth keeping. If it doesn't, we find out in weeks.

## Grammar (draft)

| Combo | Meaning |
|---|---|
| `Mod+1-9` | Go to place |
| `Mod+Shift+1-9` | Carry the focused window there |
| `` Mod+` `` | Bench |
| `Mod+Tab` | Back |
| `Mod+hjkl` | Look (move focus) |
| `Mod+Shift+hjkl` | Carry a window |
| Hold `Mod+R`, then `hjkl` | Reshape |
| `Mod+0` tap | Unfold |
| `Mod+0` hold | Spread |

`Mod` is Option on macOS. Keys bind by **physical position**, so Dvorak and
Colemak users keep the home row.

## Build and run

Requires Swift 6.0 or newer and macOS 13 or newer.

```sh
swift build
swift run Chord
swift build --build-tests
scripts/build-app.sh          # writes build/Chord.app
open build/Chord.app
```

`swift run Chord` runs the menu-bar shell without a bundle; launch at login
requires the packaged `.app`. The shell adds a menu-bar item showing status
(running, paused, or needs Accessibility permission), Pause/Resume, Launch at
Login (off by default), Check for Updates… (a single GitHub Releases request;
see the Privacy section of `docs/PRODUCT.md`), Open Log Folder, Copy Diagnostics,
and a Recent Crash Reports submenu. **Input status** shows Accessibility and Input
Monitoring state, whether the event tap is enabled, each hotkey's Carbon
registration result (the OSStatus on failure), and event counters (including `carbon silent`,
presses the event tap saw that Carbon never delivered; each is also logged as an
`input: DIAGNOSTIC` line and no hotkey changes owner); **Copy Input
Diagnostics** copies that plus recent `input:` log lines. A failed precondition (no
permission, tap disabled by the system, a hotkey another app already holds) appears as
one line under the status line and in the log. Without Accessibility access it explains why,
opens System Settings, and re-checks every second. Log lines go to
`~/Library/Logs/Chord/chord.log`. See the Privacy section of
[`docs/PRODUCT.md`](docs/PRODUCT.md) for update-check behavior and configuration.
The bundle id `com.example.chord` is a placeholder for the release issue.

`ChordCore` contains pure `frame()` math, a spatial `Picker`, Plan types with
strict decoding and fallback, and a timestamp-driven `KeyStateMachine` for
tap/hold, directional chords, carry, and reshape intents. `ChordCoreTests` has
behavioral tests for these pure components. `swift build --build-tests`
checks that the test target compiles.

Bootstrap steps 1–5 are complete; see [STATUS.md](docs/STATUS.md) for current
progress.

## Filing a bug

Diagnostics are copied to your clipboard only; Chord does not upload them. To
report a problem:

1. Choose **Copy Diagnostics** in the Chord menu and paste the report into a
   new GitHub issue.
2. If **Recent Crash Reports** lists a report, choose it to reveal it in Finder
   and attach it to the issue by hand.

See the [Privacy section](docs/PRODUCT.md#privacy) for what the report contains,
where logs are stored, retention, and redaction.

## Docs

- [PRODUCT.md](docs/PRODUCT.md) — what it is, what ships, non-goals
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — modules and the one-writer rule
- `ROLES.md` — referenced design spec, not yet present in this checkout
- [STATUS.md](docs/STATUS.md) — milestones and what's actually built
- [GLOSSARY.md](docs/GLOSSARY.md) — vocabulary
- `CHARTER.md` — referenced founder's charter, not yet present in this checkout

## Non-goals

- No auto-maximizing. Nothing fills the screen unless asked.
- No app and no agent ever resizes a window.
- No AI anywhere near the vault.
- No hidden state: if the manager moved it, there is a log line and an undo.

## Name

"Chord" is a working name. Collision check before public release.

## License

TBD. AeroSpace (MIT) is the provisional backend recommendation; see the [C6 substrate report](docs/C6-SUBSTRATE.md).
