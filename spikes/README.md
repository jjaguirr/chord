# spikes

Throwaway M0 harnesses (Python/Swift). Nothing in `Sources/` or `Package.swift`
may import or reference anything here; `scripts/check_invariants.py` enforces it.
A spike that succeeds is re-implemented properly in `Sources/`, never promoted.

# C6 platform spikes

These disposable probes are deliberately outside SwiftPM targets. Run each on a disposable macOS account with test apps/windows; do not grant permissions from a harness. Each probe must print exactly one `PASS:` or `FAIL:` summary with the acceptance threshold and its failure path. A permission denial or missing fixture is `FAIL` with remediation, never a passing result.

| # | Probe | Acceptance / fail path |
|---|---|---|
| 1 | [`window-ids.swift`](window-ids.swift) | Require at least three apps, unique IDs, stable app-ID associations across a 2-second idle interval. Does not claim relaunch stability. |
| 2 | [`frame-survival.swift`](frame-survival.swift) | Set a dedicated app's only AX test window position and size; require both to survive 5 seconds within 2pt; restore original geometry. |
| 3 | [`hotkeys.swift`](hotkeys.swift) | Run `--carbon` and `--tap-fallback` separately; capture Option+0 before text insertion and each physical Ctrl+h/j/k/l in Terminal and iTerm; Vim-in-Terminal/iTerm must be tested manually and remain unverified by the probe; fail on missing events or leakage. |
| 4 | [`birth-size.swift`](birth-size.swift) | Set a dedicated app's only fresh test window to 333×471; accept exact size or a supplied, documented app minimum clamp; restore original size. |
| 5 | [`unfold-spread.swift`](unfold-spread.swift) | Replay 120-frame 30/60-fps AX geometry changes with elapsed-time skipping; time 20-window Spread moves; p95 budgets 33.33/16.67/16.67ms. |
| 6 | [`socket-latency.sh`](socket-latency.sh) | Measure 100 AeroSpace CLI request round trips; p95 ≤16.67ms. Includes CLI startup overhead. |
| 7 | [`hold-detector.swift`](hold-detector.swift) | Standalone Mod+0 detector with a 10-second resting baseline and three deliberate holds ≥700ms; fail on resting activation or missed hold. |


Current environment: AeroSpace server is disabled (installed client/server `0.20.3-Beta`), so window, frame, socket, and animation trials cannot run against the substrate here. Accessibility/Input Monitoring permission-dependent trials remain not run; no settings were changed. See [`../docs/C6-SUBSTRATE.md`](../docs/C6-SUBSTRATE.md).
