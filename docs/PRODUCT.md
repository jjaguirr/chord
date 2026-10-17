# PRODUCT.md

## What it is

A window manager built on one idea: a window is paper on a desk. You
decide where it sits and how you move; the manager never decides how big
it is.

## Philosophy

1. **Size is a decision, never a default.** A window is born small, as a
   card (333 × 471 px), and stays until you decide otherwise. The complete
   list of things that may make it big: a fullscreen or zoom command, a
   mouse resize, a reshape, an Unfold. Nothing else — not an app's
   preferred size, not a layout engine, not an agent. A user may record a
   *standing wish*; that is still the user's decision, stored as a rule.
2. **Places, not app groups.** Workspaces answer "what is this for."
3. **One grammar, escalating consequence.** `hjkl` are directions;
   modifiers set how much a keystroke changes — look, carry, reshape.
   `Shift` always means "take this with you."
4. **Preview, then commit.** Nothing moves until you commit.
5. **Predictable by construction.** Decisions are pure functions of window
   rectangles and a few integers. Property tests, not intuition, define
   "predictable."
6. **Agents propose, the Executor disposes.**
7. **Keyboard first, the mouse stays honest.**

## What ships in v1

- Nine places on `1-9` plus the bench.
- The key grammar above.
- Immediate look — a pure picker chooses and focus moves. No preview
  overlay, no latch.
- Unfold (`Mod+0` tap) and Spread (`Mod+0` hold).
- Agents as plain files; the Sorter is the first. An Executor applies
  typed plans through a whitelist, logs, and supports undo.

## Cut from v1

Voice · peek · fold-model tiling · workspace templates · the training
dojo · the `Mod+0` palette · the Sorter's model layer (rules first).

## Privacy

Agents see an app name and a redacted title, never pixels. The vault (9)
is invisible to agents. Password managers are redacted everywhere.
Diagnostics remain local until you choose to share them. **Copy Diagnostics**
copies the Chord and macOS versions, pinned AeroSpace version and health,
Accessibility state, config default/customized flags and standing-wish count
(not values or app names), recent Chord crash-report file names, and the last
50 log lines to the clipboard. Chord
does not upload that report. Recent Crash Reports lists at most five Chord
reports and reveals a selected report in Finder; attaching it to an issue is
manual.

The local log is `~/Library/Logs/Chord/chord.log`, with two rotated archives.
The active file rotates at 1 MiB; individual messages are clipped to 4096
UTF-8 bytes. The window-title redaction policy excludes Place 4 and
password-manager titles.

Update checks send one unauthenticated `GET` to
`https://api.github.com/repos/jjaguirr/chord/releases/latest`. The request
carries the Chord version in its `User-Agent` and nothing else: no install
identifier, no account, no cookies, no telemetry, no crash reports. Chord
never downloads or installs an update; "Open Download Page" opens the release
page in the browser only when the user clicks it. The once-a-day background
check is off by default and enabled with `[updates] background_check = true`
in `~/Library/Application Support/Chord/config.toml`.

## Non-goals

No auto-maximizing. No app or agent resizing. No AI in the vault. No
hidden state.
