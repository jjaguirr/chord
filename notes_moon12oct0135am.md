# Notes — 2026-10-12 01:35 AM

Repo initialized for `jjaguirr/chord` with the project scaffold and design docs from the provided handoff.

Status:
- Added `AGENTS.md` and repo docs under `docs/`.
- Created the initial repo structure matching the handoff: `Sources/`, `Tests/`, `spikes/`, `docs/`.
- Confirmed the project is intentionally in pre-alpha design-only state.

Next step:
- Bootstrap the Swift package skeleton: `ChordCore`, `Chord`, and empty test target, with no dependencies.
- Then port the pure `frame()` logic and property-tested picker work per the bootstrap sequence.

Key constraints to preserve:
- `ChordCore` stays pure; no AppKit/OS APIs/deps.
- The Executor is the only window-writer.
- No vault case in `Plan`.
- `frame()` and Picker behavior must be validated by tests before UI or real window wiring.
