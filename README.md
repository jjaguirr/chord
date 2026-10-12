# Chord
### Beautiful window management. *(working name)*

Chord is a keyboard-first window manager for macOS. It decides **where**
windows live and **how you move between them** — and leaves **size** to you.

> **Status: pre-alpha, bootstrap only.** The dependency-free Swift package
> builds and prints a startup message; it is not a functioning window manager.
> The browser input prototype remains separate. Product behavior is design-only.

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

## Build and run the bootstrap

Requires Swift 6.0 or newer (macOS for the intended window manager).

```sh
swift build
swift run Chord
swift build --build-tests
```

`Chord` prints `Chord: bootstrap only; window management is not implemented.`
and exits. It does not access or change windows, register hotkeys, or start UI.
`ChordCore` is an empty pure library; `ChordCoreTests` is an intentionally
empty test target, with no placeholder tests. `swift build --build-tests`
checks that the test target compiles; there are no behavioral tests yet.

Bootstrap step 1 is complete. Next: implement and test the pure `frame()`
function, generate its fixtures, then implement the property-tested Picker
in the order specified by the project bootstrap instructions.

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

TBD. AeroSpace (MIT) is used as a headless substrate.
