# STATUS.md

Bootstrap step 1 is built: a dependency-free Swift package, not a functioning
window manager. Estimates below assume ~10 focused hours a week. They are
estimates, not promises.

| Piece | State |
|---|---|
| `hjkl` aim/chord prototype | Built (single HTML file, browser only) |
| Swift package skeleton | Built: empty pure `ChordCore`, startup-only `Chord` executable, empty `ChordCoreTests` target |
| Unfold animation | Spec + math written; not coded |
| Everything else | Design only |

## Bootstrap

With Swift 6.0 or newer, `swift build` builds the package and `swift run Chord`
prints `Chord: bootstrap only; window management is not implemented.` then exits.
`swift build --build-tests` compiles the intentionally empty test target.
No behavioral tests exist yet; no UI, window operations, hotkeys, or backend
are implemented.

Next is bootstrap step 2: port and test pure `frame()`, then generate fixtures
and implement the Picker with its property tests before any real window wiring.
The referenced `CHARTER.md` and `ROLES.md` specs are absent from this checkout.

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

Spikes 1-5 (window IDs, frame survival, hotkeys, birth size, Unfold fps)
plus socket latency. Each has a defined fail path.
