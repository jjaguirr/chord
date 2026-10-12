# AGENTS.md

Instructions for coding agents working in this repo. `CLAUDE.md` is a
symlink to this file. If anything here conflicts with `docs/CHARTER.md`,
the charter wins — open an issue rather than guessing.

## Read first, in this order

1. `docs/CHARTER.md` — what we're building and why
2. `docs/PRODUCT.md` — behavior, non-goals
3. `docs/ROLES.md` — places, tiers, the vault
4. `docs/ARCHITECTURE.md` — modules and the one-writer rule
5. `docs/STATUS.md` — what's actually built

## Hard invariants — never violate

1. **One writer.** Only the Executor changes windows. No other module may
   set a frame, raise, or move a window. Enforce this in review and, once
   CI exists, with a check.
2. **Size is the user's decision.** The complete list of things that may
   make a window big is in `docs/PRODUCT.md` §Philosophy. Nothing else
   resizes — not an agent, not a "convenience," not you.
3. **The vault (9) is unrepresentable in a `Plan`.** Do not add a case for
   it. Do not add a runtime check for it in the Executor.
4. **Agents propose, the Executor disposes.** Agents emit typed plans and
   never touch windows.
5. **Every action has an inverse and a log line.** If you add an action
   without an undo path, you are not done.
6. **Pure core stays pure.** No AppKit, no OS APIs, no third-party
   dependencies in the core module. Events in, intents out.

## Repo map

```
Sources/ChordCore/     pure: frame(), Picker, KeyStateMachine, Plan types
Sources/Chord/         impure: InputLayer, Executor, animator, backend, app
Tests/ChordCoreTests/  unit + property tests for the pure core
spikes/                throwaway M0 harnesses (Python/Swift)
docs/                  design docs
```

If you're unsure whether code is pure, it goes in `Chord`, not `ChordCore`.

## Bootstrap — establishing the project

Do these in order. Do not start a later step until the earlier one's tests
pass.

1. **Swift package skeleton.** `ChordCore` + `Chord` targets, empty test
   target. No dependencies.
2. **Port `frame()`** as a pure function from the Unfold spec (stops S0
   `333×471`, S1 `444×630`, S2 largest fitting 16:9; `T_KNOT = 1/φ² =
   0.382`; smootherstep; interpolate log-area and log-aspect separately).
3. **Regenerate the landmark fixtures by bisecting `frame()` itself** at
   five resolutions. Never hand-type them. The old spec's table is wrong
   (perfect square lands near t = 0.65, not 0.614).
4. **Port the Picker** with the full normalization rules, then write the
   seven property tests before any UI: order-independence,
   jitter-independence, reversibility, reachability, totality, chord
   equals sequence on a plain grid, cancel is a no-op.
5. **Plan types + decode.** `enum Workspace` with no case for 9; decode
   failure falls back to rules + bench.
6. **Spikes 1-6** (`docs/STATUS.md`) in `spikes/`, each emitting a
   pass/fail line against its threshold and its fail path.
7. **Only then** wire real windows.

## Coding standards

- Swift, no force-unwraps in the core, no global mutable state.
- Use a monotonic clock. Keep animation rects in state; never read a
  frame back from the window each tick.
- Round frames to integers when setting them.
- Bind `hjkl` by **physical key position** (`event.code`), never by
  character.
- Pin the AeroSpace version. The backend sits behind a protocol; nothing
  outside it may import the socket client.

## Testing

- Property tests are the definition of "predictable." A picker change
  without the property tests updated is not done.
- Fixtures for `frame()` are generated from `frame()`, not typed by hand.
- Replay recorded key streams for `KeyStateMachine`; do not unit-test
  timing by sleeping.
- Executor tests: unknown windows, duplicates, and vault targets.

## Spikes

`spikes/` is throwaway. Do not import it from `Sources/`. If a spike
succeeds, re-implement its result properly rather than promoting the file.

## Do not

- Add anything from the "Cut from v1" list without asking.
- Let an agent or the Sorter resize a window.
- Add a vault case to `Plan`.
- Special-case the vault in the Executor.
- Send pixels anywhere; agents get app name and a redacted title.
- Touch vault window titles, pixels, or voice for any agent.
- Hard-code `9`, `4`, or `` ` `` outside the config defaults.

## Commits and PRs

- One logical change per commit. Imperative subject line.
- Reference the milestone (`M0`, `M1`, …) in the body.
- Every PR states: which invariant it touches, and how it was tested.
- If you touch the pure core, the PR must include test changes.

## Definition of done

A change is done when: it builds, the pure core is still pure, tests pass,
every new action has an inverse and a log line, no invariant above is
violated, and the relevant doc is updated if behavior changed.

## When stuck

Prefer the smallest reversible change. If a decision is genuinely open
(see the "Open" list in the docs), pick the option marked recommended,
leave a `// DECISION:` comment with the alternative, and move on — do not
stall.
