# STATUS.md

Bootstrap steps 1–5 are built: a dependency-free Swift package with pure frame
math, the Picker, and Plan types with strict Codable and fallback, not a
functioning window manager. Estimates below assume ~10 focused hours a week.
They are estimates, not promises.

| Piece | State |
|---|---|
| `hjkl` aim/chord prototype | Built (single HTML file, browser only) |
| Swift package core | Built: `ChordCore` has pure `frame()`, Picker, Plan types, and a timestamp-driven KeyStateMachine (tap/hold, chords, carry, and reshape intents); tests cover core behavior. Executor window operations are implemented against the fake backend but are not wired into the executable; no hotkeys are implemented |
| `WorkspaceBackend` (C7 PR1, #8) | Built: protocol, deterministic `FakeWorkspaceBackend` with scripted faults, and contract tests against the fake (`Tests/ChordTests`). No real substrate: AeroSpace socket implementation is PR2, pending spike results |
| Executor (C8, #9) | Built against the fake backend only: typed ChordCore actions for place, frame, focus, and restore-home, applied by the Executor whitelist; frame rounding; undo for place, frame, focus, and restore-home; focus via single-window raise with floats re-raised above tiles; per-workspace focus history. `WorkspaceBackend` gained `applyFrame`, `raiseWindow`, a `Place`-typed `moveWindow` and stacking order. Executor tests cover the fake backend. Real AX AXRaise and AeroSpace behavior are unverified |
| App shell (#23) | Built; see [README](../README.md) for shell behavior and packaging details |
| Update check (#29) | Built; see [PRODUCT.md](PRODUCT.md) for behavior and privacy. `ReleaseVersion` and `UpdateCheck` are pure in `ChordCore`; release parsing and comparison have offline tests. Sparkle is deferred (#37) |
| Unfold animation | Pure `frame()` math and tests built; pure press-and-timer stepper (`UnfoldAnimator`) built (`UnfoldAnimator`, tests with fake clock); not wired to windows, fps not measured |
| Config core (#24) | Built, pure: `Config` with defaults, a hand-written TOML-subset parser (`TOML.swift`), and typed diagnostics with line numbers. Any diagnostic yields defaults for the whole file. No agent or vault setting exists; `keys.vault` is a user binding only. Standing wishes are the only size-changing rule (`fullscreen`, `zoom`). Unfold step window is `[timing] unfold_step_window_ms`; Unfold step count is not configurable (fixed ratio progression A5, square, 4:3, 3:2, golden, 16:9). Parser and config tests are in `Tests/ChordCoreTests`; not run locally, CI is the oracle |
| Diagnostics (#30) | Built. Pure, in `ChordCore/Diagnostics.swift`: `LogPolicy` (1 MiB rotation, two archives), `LogRedaction` (place 4, password managers, and unplaced windows redacted), `DiagnosticsReport` (text render, no config values). Shell: size-capped `ActionLog`, Copy Diagnostics, Open Log Folder, Recent Crash Reports (reveal in Finder only, no upload). AeroSpace health shown as not connected; Executor is not wired to the file log. Tests run in CI only. |
| Everything else | Design only |

## Bootstrap

`swift build` builds the package and `swift run Chord` starts the menu-bar shell
(no Dock icon). `scripts/build-app.sh` builds `build/Chord.app`.
`swift build --build-tests` compiles the test target. Tests cover frame
behavior, generated landmarks, Picker rules and properties, Plan
validation, decoding, fallback, and action reversibility, plus KeyStateMachine
event sequences for tap/hold, direction chords, carry repeats and edge
snapping, and reshape intents. Executor operations are tested through the fake
backend but are not wired into the executable. No hotkeys are implemented.
No real substrate is wired; see the `WorkspaceBackend` row above. The app
shell does not yet integrate window operations or hotkeys.

`swift build` succeeds. `swift test` is currently blocked because this machine's Swift installation cannot load the `TestingMacros` plugin; the existing test target fails before tests execute.
Picker supports came-from preference on exact primary-score ties; pathological layouts may remain non-reciprocal under the required tie order. Diagonal tie-breaking uses explicit pure screen bounds; horizontal z-fallback is a no-op when no spatial target exists.

## Milestones

| Milestone | Window | Exit |
|---|---|---|
| M0 Spikes | week 1 | Unverified assumptions retired |
| M1 Usable core | weeks 2-3 | Live in it a week without AeroSpace's own keys |
| M2 Signature move | weeks 4-5 | Unfold holds fps target, or proxy fallback chosen |
| M3 Spread + Sorter | weeks 6-8 | 20-window spread/gather restores exactly; undo works |
| M4 Beta | weeks 9-10 | Config, README, onboarding, signed + notarized |

## Kill criterion

If, after M1's week of daily driving, Chord doesn't beat plain AeroSpace
plus Rectangle, we stop and write down why.

## Unverified

| C6 spike | Result |
|---|---|
| Window IDs across apps | Not run: AeroSpace server disabled; no multi-app sample |
| AX frame survival | Not run: no disposable app/window fixture |
| Global hotkeys | Not run: Terminal/iTerm/Vim fixtures absent; Vim-specific behavior is manual and unverified by the probe |
| Window birth size | Not run: no fresh-window fixture |
| Unfold frame rate / 20-window Spread | Not run: 20-window fixture absent |
| Socket latency | FAIL: AeroSpace server disabled; 100-request p95 not measured |
| Mod+0 hold detector | Not run: controlled resting-finger trial absent |

Detailed substrate evidence and the provisional backend recommendation are in
[C6-SUBSTRATE.md](C6-SUBSTRATE.md).
