# STATUS.md

Bootstrap steps 1–5 are built: a dependency-free Swift package with pure frame
math, the Picker, and Plan types with strict Codable and fallback, not a
functioning window manager. Estimates below assume ~10 focused hours a week.
They are estimates, not promises.

| Piece | State |
|---|---|
| `hjkl` aim/chord prototype | Built (single HTML file, browser only) |
| Swift package core | Built: `ChordCore` has pure `frame()`, Picker, Plan types, and a timestamp-driven KeyStateMachine (tap/hold, chords, carry, and reshape intents); tests cover core behavior. Executor window operations are tested against the fake backend; Unfold, Reshape, and Carry are wired to real windows through `AXWindowBackend` (see the Live motion row) |
| `WorkspaceBackend` (C7 PR1, #8) | Built: protocol, deterministic `FakeWorkspaceBackend` with scripted faults, and contract tests against the fake (`Tests/ChordTests`). No real substrate: AeroSpace socket implementation is PR2, pending spike results |
| Executor (C8, #9) | Built against the fake backend only: typed ChordCore actions for place, frame, focus, restore-home, and reshape (pure `reshapeAction` translates KeyStateMachine reshape intents into log-space aspect/area actions; Executor applies and undoes them, skipping undo if the window was resized since), applied by the Executor whitelist; frame rounding; undo for place, frame, focus, restore-home, and reshape; focus via single-window raise with floats re-raised above tiles; per-workspace focus history. `WorkspaceBackend` gained `applyFrame`, `raiseWindow`, a `Place`-typed `moveWindow` and stacking order. Executor tests cover the fake backend. Real AX AXRaise and AeroSpace behavior, real app minimum sizes, and the real visible frame (the backend only reports monitor bounds) are unverified; no hotkey capture or input loop routes Option+R then h/j/k/l to this translator |
| App shell (#23) | Built; see [README](../README.md) for shell behavior and packaging details |
| Update check (#29) | Built; see [PRODUCT.md](PRODUCT.md) for behavior and privacy. `ReleaseVersion` and `UpdateCheck` are pure in `ChordCore`; release parsing and comparison have offline tests. Sparkle is deferred (#37) |
| Unfold animation | Pure `frame()` math and tests built; pure press-and-timer stepper (`UnfoldAnimator`) built (`UnfoldAnimator`, tests with fake clock); wired to real windows by Live motion (below), fps not measured |
| Config core (#24) | Built, pure: `Config` with defaults, a hand-written TOML-subset parser (`TOML.swift`), and typed diagnostics with line numbers. Any diagnostic yields defaults for the whole file. No agent or vault setting exists; `keys.vault` is a user binding only. Standing wishes are the only size-changing rule (`fullscreen`, `zoom`). Unfold step window is `[timing] unfold_step_window_ms`; Unfold step count is not configurable (fixed ratio progression A5, square, 4:3, 3:2, golden, 16:9). Parser and config tests are in `Tests/ChordCoreTests`; not run locally, CI is the oracle |
| Diagnostics (#30) | Built; user-facing behavior and privacy are documented in [README](../README.md) and [PRODUCT](PRODUCT.md). Executor's optional log sink is not wired to a live shell Executor in this build. |
| InputLayer capture (#58, first slice of #10) | Built in `Sources/Chord/Input`: Carbon `RegisterEventHotKey` for Option+0, Option+R, Option+1-9, Option+hjkl, their Shift variants, Option+backtick (and Shift) and Option+Tab, with a CGEventTap fallback for keys Carbon refuses to register. The tap also watches Carbon-owned keys without consuming them: a press the tap saw that Carbon did not deliver within 0.1 s is logged as a `DIAGNOSTIC` line and counted as `carbon silent`; ownership never changes. Every event is logged with key, modifiers, path (`carbon`/`tap`) and the resulting KeyIntent; intents go to `WindowMotion` (Live motion row). Menu: Input status (permissions, tap state, per-key OSStatus, counters, one-line cause for any failed precondition) and Copy Input Diagnostics. Sources sit behind a `HotkeySource` protocol; `InputCaptureTests` drive fakes with a fake clock. Never tested live: real capture, permissions, registration conflicts (see Unverified) |
| Live motion (#59, slice of #10) | Built, unverified live: `WindowMotion` (`Sources/Chord/Motion`) takes `InputCapture` intents and calls the Executor. **Unfold**: Option+0 taps run `UnfoldAnimator` on the focused window (first press eases to centered A5 333x471, each press inside `unfold_step_window_ms` steps square, 4:3, 3:2, golden, 16:9 from `frame()`'s bisected stops on the monitor's visible frame; A5 is skipped when it does not fit; expiry restarts at A5). A timer applies the animator's rect for the clock's now, so a slow AX call skips frames; per-frame steps skip snapshots and individual log lines, and the run closes as one undoable, logged frame change. **Reshape**: Option+R held then hjkl, one `reshapeAction` step per press, undoable. **Carry**: Option+Shift+hjkl moves the focused window by the state machine's ramp and edge magnets, never further past a visible-frame edge; a held carry extends one undo entry. Look, Spread, place keys (Option[+Shift]+digit), bench, and Tab only log. AX only (spike 6: AeroSpace is too slow per frame); Accessibility missing logs and moves nothing; nothing prompts. **Focused-window lookup** (`FocusedWindowLookup`): reads `kAXFocusedWindow`; for Chromium-based and Electron apps only, when that read fails it sets `AXManualAccessibility` (latched per pid once the set succeeds) and re-reads up to 3 times, 50 ms apart; every outcome is logged as a `focus lookup:` line with per-attribute AX error codes, deduplicated against the previous line. No other fallback: an app with no focused window moves nothing. No undo key is bound. Unverified live: see below |
| Everything else | Design only |

## Bootstrap

`swift build` builds the package and `swift run Chord` starts the menu-bar shell
(no Dock icon). `scripts/build-app.sh` builds `build/Chord.app`.
`swift build --build-tests` compiles the test target. Tests cover frame
behavior, generated landmarks, Picker rules and properties, Plan
validation, decoding, fallback, and action reversibility, plus KeyStateMachine
event sequences for tap/hold, direction chords, carry repeats and edge
snapping, and reshape intents. Executor operations are tested through the fake
backend but are not wired into the executable. Option+0 taps, Option+R then hjkl, and Option+Shift+hjkl move the focused window
through the Accessibility backend (see the Live motion row); no other key moves a window.
No real substrate is wired; see the `WorkspaceBackend` row above. The app
shell does not yet integrate window operations.

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
| Window IDs across apps | Not run: no multi-app sample |
| AX frame survival | Not run: no disposable app/window fixture |
| Global hotkeys | Not run: Terminal/Vim fixtures absent; Vim-specific behavior is manual and unverified by the probe |
| Live hotkey capture (InputLayer, #58) | Not run: needs a real Option keypress session. Unverified: Carbon registration results on this machine (conflicts with AeroSpace `alt-` bindings), whether Carbon delivers Option-only hotkeys on this macOS version, Input Monitoring/Accessibility state, Option+0 consumption (no character typed), tap re-enable after system disable. Read the answers from Input status and the `input:` log lines |
| Window birth size | Not run: no fresh-window fixture |
| Unfold frame rate / 20-window Spread | Not run: 20-window fixture absent |
| Socket latency (spike 6, CLI per request) | FAIL: p95 53.497ms > 16.67ms with CLI spawn included (server enabled on re-run) |
| Socket latency (spike 6b, direct socket) | FAIL: p95 41.322ms > 16.67ms (min 6.113, max 248.658, 100 samples), direct socket, server enabled, 2026-10-17; server-side latency, not CLI spawn, exceeds the budget (spike 6 CLI-spawn p95 53.497ms). AeroSpace reads are not viable per-frame; command-speed use only. Probe targets installed 0.20.3 framing (`spikes/socket-latency-direct.py`) |
| Mod+0 hold detector | Not run: controlled resting-finger trial absent |
| Live motion (#59) | Not run on real windows. Unverified: AX size, position, then size writes landing on real apps (apps that snap or refuse sizes, e.g. terminals; whether the second size write lets a growing window reach its target), real app minimum sizes (a fixed 120x80 floor stands in for them), multi-monitor and mixed-DPI coordinates (visible frames are converted from Cocoa to top-left points, not tested on two displays), 1000 ms step window and hold timing feel, Unfold frame rate under AX latency (each frame is two size writes, a position write, and two reads), Option+R then hjkl while R is held, Accessibility trust and focused-window reads from the app bundle, whether `AXManualAccessibility` makes Chrome and other Chromium browsers answer `kAXFocusedWindow` (a Chrome 155 test profile answered the plain read and rejected the set with `attributeUnsupported`; read the answer from the `focus lookup:` log lines), Stage Manager and full-screen windows |

Detailed substrate evidence and the provisional backend recommendation are in
[C6-SUBSTRATE.md](C6-SUBSTRATE.md).
