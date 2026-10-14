# spikes

Throwaway M0 harnesses (Python/Swift). Nothing in `Sources/` or `Package.swift`
may import or reference anything here; `scripts/check_invariants.py` enforces it.
A spike that succeeds is re-implemented properly in `Sources/`, never promoted.

# C6 platform spikes

These disposable probes are deliberately outside SwiftPM targets. Run each on a disposable macOS account with test apps/windows; do not grant permissions from a harness. Each probe must print exactly one `PASS:` or `FAIL:` summary with the acceptance threshold and its failure path. A permission denial or missing fixture is `FAIL` with remediation, never a passing result.

| # | Probe | Acceptance / fail path |
|---|---|---|
| 1 | `window-ids.swift` | Enumerate windows for at least three distinct apps, relaunch/re-enumerate, compare IDs; fail if IDs collide or do not survive the observed lifecycle. Record the lifecycle boundary; do not imply IDs persist across reboot. |
| 2 | `frame-survival.swift` | Set a test window frame using AX, poll readback for 5 seconds, and check after app restore/reopen. Fail if the app refuses, restores a different frame, or AX access is unavailable. |
| 3 | `hotkeys.swift` | Compare Carbon registration and event-tap delivery; verify Option+key is intercepted before text insertion and Ctrl+hjkl in Terminal, iTerm, and Vim. Fail on missing event, typed character leakage, or permission denial. |
| 4 | `birth-size.swift` | Create test windows and request 333×471; accept exact size or the app-reported minimum clamp. Fail if size cannot be observed/set or exceeds the requested dimensions without a minimum-size explanation. |
| 5 | `unfold-spread.swift` | Replay frame updates at 30 and 60 fps with elapsed-time skipping; separately time each tick moving 20 windows. Fail if the 60-fps run misses its frame budget or 20-window tick exceeds 16.67 ms. |
| 6 | [`socket-latency.sh`](socket-latency.sh) | Measure 100 `list-windows` round trips against AeroSpace; fail if p95 exceeds 16.67 ms or requests fail. |
| 7 | `hold-detector.swift` | Standalone Mod+0 hold detector with repeated deliberate holds and resting-finger observation. Fail on any resting-finger activation or missed deliberate hold. |

The Swift probes in this table remain protocols, not implemented harnesses in this checkout; do not interpret them as completed or run. The socket probe is executable and reports `FAIL` when its prerequisites are unavailable. No spike code is imported by product targets; validated behavior must be reimplemented behind product interfaces.

Current environment: AeroSpace server is disabled (installed client/server `0.20.3-Beta`), so window, frame, socket, and animation trials cannot run against the substrate here. Accessibility/Input Monitoring permission-dependent trials remain not run; no settings were changed. See [`../docs/C6-SUBSTRATE.md`](../docs/C6-SUBSTRATE.md).
