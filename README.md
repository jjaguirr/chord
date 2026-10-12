# Chord

Keyboard-first window management for macOS. Windows are paper on a desk, not walls of a room.

> **Status: pre-alpha, design phase.** Nothing is installable yet. The only thing built so far is a browser prototype of the `hjkl` input. This README is the project charter; code lands as the milestones below complete.

Most window managers decide how big things should be. Chord decides where things live and how you move between them, and leaves size to you.

## What v1 is

- **Nine workspaces on `1-9` plus a bench on backtick**, built on [AeroSpace](https://github.com/nikitabobko/AeroSpace) running headless, and driven by Chord's own keys.
- **Look is immediate.** A pure picker chooses the neighbouring window in a direction and focus moves there. No preview overlay.
- **Unfold** (`Mod+0` tap): a window shrinks to a card, then grows along a smooth path to the largest 16:9 box that fits the screen.
- **Spread** (`Mod+0` hold): windows on the current workspace shrink to cards grouped by target workspace as a preview. Commit once, or undo to restore every window exactly.
- **Agents are plain files.** A Sorter proposes where windows belong as a typed plan. Only the Executor touches windows, and it logs everything.

## Key grammar

`Mod` is Option on a Mac.

- `Mod+1-9` go to workspace n. `Mod+Shift+1-9` carry the focused window there.
- `` Mod+` `` go to the bench. `Mod+Tab` back to the previous workspace.
- `Mod+hjkl` look. `Mod+Shift+hjkl` carry a floating window. `Mod+Ctrl+hjkl` reshape.
- `Mod+0` tap for Unfold, hold for spread.

Keys bind by physical position, so the home-row shape survives Dvorak and Colemak.

## Principles

1. **Size is the user's decision.** A window is born small and stays that size until you decide otherwise. No app, layout engine or agent resizes it.
2. **Everything that decides is pure; everything that acts goes through the Executor.**
3. **Every action has an inverse and a log line.** No hidden state.
4. **Workspace 9 is off-limits to agents by construction.** The plan type has no case for it.
5. **Agents propose, the Executor disposes.** They emit typed plans from a whitelist and never touch windows.
6. **Privacy by default.** Agents see an app name and a redacted title, never pixels.

## Architecture

Chord talks to AeroSpace over its documented Unix socket and reads window geometry itself. Modules:

- **InputLayer:** registered global hotkeys, with an event tap as fallback.
- **KeyStateMachine (pure):** tap and hold, chords, held-key repeat.
- **Picker (pure):** window rectangles and a direction in, target window out.
- **Unfold (pure `frame()` plus animator):** the signature move.
- **WorkspaceBackend:** a protocol, implemented today by the AeroSpace socket.
- **Spread:** a view mode with remembered frames, not a window migration.
- **Executor:** the only component allowed to change windows.
- **Agents:** files in `~/.config/chord/agents/`.

## Milestones

Estimates assume about ten focused hours a week.

- **M0, spikes (week 1):** verify the assumptions below on real hardware.
- **M1, usable core (weeks 2-3):** input, workspaces and bench, carry, look.
- **M2, signature move (weeks 4-5):** Unfold, birth size, float carry, reshape.
- **M3, spread and Sorter (weeks 6-8):** spread, rules-based Sorter, agent files, Executor, undo.
- **M4, beta (weeks 9-10):** config, docs, permission onboarding, signed and notarized build.

## Unverified assumptions (M0)

- AeroSpace window IDs equal system window IDs.
- Frames Chord sets on floating windows survive AeroSpace workspace switches.
- Registered global hotkeys deliver overlapping chords and releases reliably on current macOS.
- Windows can be resized on creation without a visible flash.
- Unfold holds 30 fps or better in browsers, Electron apps and Terminal.

## Not in v1

Voice control, window peek, fold-model tiling, workspace templates, a training mode, and the Sorter's model layer (rules come first).

## Acknowledgements

Workspace emulation comes from [AeroSpace](https://github.com/nikitabobko/AeroSpace) (MIT) by Nikita Bobko. Chord is not affiliated with or endorsed by that project.

## License

Not yet chosen.

## Feedback

Ideas and critiques are welcome as issues.
