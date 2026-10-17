# ROLES.md (DRAFT for captain approval; not committed)

Source: captain's design handoff s3 and s11, repo `docs/PRODUCT.md`, `docs/GLOSSARY.md`. Charter wins on conflict.

## Places

Places are roles: they answer "what is this for", not "which app is this". Bind by physical key position.

| Key | Place | Scope | Agent tier |
|---|---|---|---|
| 1 `!` | Urgent | Todos, today's calendar, anything on fire | open |
| 2 `@` | Work relations | Email, leads, clients, work calls, CRM | open |
| 3 `#` | Automation | Rules, workflows, scripts, agents, systems | open |
| 4 `$` | Money | Bills, deals, savings, life admin | redacted |
| 5 `%` | Strategy | Game theory, psychology, reasoning, planning, dashboards | open |
| 6 `^` | Ideas | Predictions, creativity, top ideas | open |
| 7 `&` | Art | Beauty, music, play, passion | open |
| 8 `*` | Personal world | Friends, family, personal targets, events, sources | open |
| 9 `(` | Self (the vault) | Reflection, growth, health | blind |
| `` ` `` | Workbench (the bench) | Where active making happens; the undecided pile the Sorter may re-sort | open |
| 0 | This window | Window action key: tap = Unfold, hold = Spread | n/a |

## Tiers

- **open**: agents see app name and a redacted title; never pixels.
- **redacted (4)**: agents see app and a redacted title; the title is redacted before it reaches any agent. A redaction type exists in v1; no model layer.
- **blind (9, the vault)**: agents cannot see it or send to it. Enforced by construction: `enum Workspace` has no case 9, so a `Plan` cannot name it. No runtime vault check in the Executor, no special-casing anywhere, no hard-coded `9`, `4` or `` ` `` outside config defaults. Exit is user-only. Layout, titles, pixels and voice never reach an agent.
- Password managers are redacted in every place.

## Movement rules

- `Mod+1..9` go to place n; `Mod+Shift+1..9` carry the focused window; `` Mod+` `` / `` Mod+Shift+` `` go to / carry to the bench; `Mod+Tab` goes back to the previous place.
- Reshape: hold `Mod+R`, then `hjkl`. Every Chord hotkey is Option-based; Ctrl is never a Chord modifier (it stays free for Ctrl+hjkl arrow remaps).
- `Mod+n` while on n ("tidy this room"): re-applying templates is post-v1; the v1 behavior is defined in C9.
- The Sorter and Executor change where a window lives, never how big it is. Every move records a home (frame + place) for undo; Spread/gather restores exact homes.

## Sorter decision layers (rules first)

pins -> app rules -> memory -> bench. The model layer is post-v1. The Sorter emits typed plans only; a window it cannot place goes to the bench; decode failure falls back to rules + bench.

## Per-place configuration

Per-place TOML templates (default layout, default apps, float/tile behavior, permitted agents) are post-v1. v1 config (C12) holds key bindings, timing thresholds (hold, tap, chord window, A5 hold, and Unfold step window), carry ramp and edge-magnet settings, the pinned AeroSpace tag, and standing wishes. Config errors yield defaults for the whole file; it has no agent settings, and only `fullscreen` or `zoom` standing wishes can request size changes.
