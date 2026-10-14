# STATUS.md

Bootstrap steps 1-3 are built: a dependency-free Swift package with pure frame
math and its tests, not a functioning window manager. Estimates below assume
~10 focused hours a week. They are estimates, not promises.

| Piece | State |
|---|---|
| `hjkl` aim/chord prototype | Built (single HTML file, browser only) |
| Swift package skeleton | Built: pure `ChordCore` has `frame()`; executable remains startup-only; frame tests added |
| Unfold animation | Pure `frame()` math and tests built; animator not coded |
| Everything else | Design only |

## Bootstrap

With Swift 6.0 or newer, `swift build` builds the package and `swift run Chord`
prints `Chord: bootstrap only; window management is not implemented.` then exits.
`swift build --build-tests` compiles the frame test target.
The tests cover frame stops, interpolation, boundaries, and generated landmarks;
no UI, window operations, hotkeys, or backend are implemented.

Next is bootstrap step 4: implement the Picker and its property tests before
any real window wiring. The referenced `CHARTER.md` and `ROLES.md` specs are
absent from this checkout.

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
| AX frame survival | Not run: Accessibility preflight passed; no disposable app/window fixture |
| Global hotkeys | Not run: Input Monitoring preflight passed; Terminal/iTerm/Vim fixtures absent |
| Window birth size | Not run: Accessibility preflight passed; no fresh-window fixture |
| Unfold frame rate / 20-window Spread | Not run: Accessibility preflight passed; 20-window fixture absent |
| Socket latency | FAIL: AeroSpace server disabled; 100-request p95 not measured |
| Mod+0 hold detector | Not run: Input Monitoring preflight passed; controlled resting-finger trial absent |

All seven spike harnesses and their thresholds/fail paths are in `spikes/`.
`docs/C6-SUBSTRATE.md` recommends AeroSpace `v0.21.3-Beta` as a provisional,
replaceable backend with its remaining validation gaps recorded. The installed
AeroSpace is `0.20.3-Beta`; its server explicitly rejects commands while
settings were not changed. AX/Input Monitoring preflights passed where checked;
the behavior trials remain unverified because disposable fixtures were absent.
