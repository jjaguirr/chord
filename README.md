# Chord
### Beautiful window management. *(working name)*

Chord is a keyboard-first window manager for macOS. It decides **where**
windows live and **how you move between them** — and leaves **size** to you.

> **Status: pre-alpha, app shell only.** Chord builds as a menu-bar agent
> bundle (`scripts/build-app.sh`) with an Accessibility permission flow, a pause
> switch, and launch at login. It is not yet a functioning window manager: no
> window operations, hotkeys, or backend are wired in. The pure core includes a
> timestamp-driven key state machine; integration into the app remains design-only.

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
| `Mod+Ctrl+hjkl` | Reshape |
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
and a Recent Crash Reports submenu. Without Accessibility access it explains why,
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

Chord sends nothing anywhere. To report a problem:

1. Open the Chord menu and choose **Copy Diagnostics**. It copies the Chord and macOS versions, the pinned AeroSpace version and health, Accessibility state, config as "defaults" or "customized" flags (no key bindings or app names), recent crash report file names, and the last 50 log lines.
2. Paste it into a new GitHub issue.
3. If **Recent Crash Reports** lists a report, choose it to reveal it in Finder and attach it to the issue by hand.

The log is `~/Library/Logs/Chord/chord.log`; **Open Log Folder** shows it. It rotates at 1 MiB and keeps two older files. Place 4 and password-manager window titles are redacted. No current log line includes a window title.

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
