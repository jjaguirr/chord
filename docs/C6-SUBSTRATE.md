# C6 substrate report

## Decision

AeroSpace-as-backend is the recommendation, pinned to `v0.21.3-Beta` for the next controlled integration trial; do not ship it as validated until that trial passes. This is the newest tag cited by C6 and was confirmed as an official release (2026-07-16). The installed client/server are only `0.20.3-Beta` (`6dde91ba43f62b407b2faf3739b837318266e077`), and the server explicitly rejects commands while disabled. Enabling it would alter machine-level behavior, so this report does not do so.

AeroSpace is lower-risk than a Chord-owned workspace model for the next milestone because its pinned release documents a public socket protocol and configurable empty keybinding tables, floating-window callbacks, and persistent workspaces. The repository already puts the backend behind a replaceable boundary. The alternative removes the external manager dependency but requires Chord to implement and maintain workspace/window control itself. This is a decision to evaluate AeroSpace, not proof its operational behavior passes.

## Evidence and gaps

- `aerospace --version`: client and server both report `0.20.3-Beta`, commit `6dde91ba43f62b407b2faf3739b837318266e077`.
- `aerospace list-windows --all ...`: server responds: “AeroSpace server is disabled and doesn't accept commands. You can use 'aerospace enable on' to enable the server”. No command was issued to enable it.
- A Unix socket path `/tmp/bobko.aerospace-jjaguirr.sock` exists, but server rejection means its presence does not establish an operational protocol or latency.
- The exact pinned documentation/release inspected: [v0.21.3-Beta guide](https://github.com/nikitabobko/AeroSpace/blob/v0.21.3-Beta/docs/guide.adoc), [commands reference](https://github.com/nikitabobko/AeroSpace/blob/v0.21.3-Beta/docs/commands.adoc), and [release notes](https://github.com/nikitabobko/AeroSpace/releases/tag/v0.21.3-Beta). The guide describes empty fallback keybinding tables, `on-window-detected` floating callbacks, and `persistent-workspaces` config. It does not document a headless mode; no `headless` mention appears in the pinned guide. The release notes cite unrelated window-ID-zero and popup-detection fixes, not a latency guarantee.
- Socket-protocol source: [AeroSpace v0.21.0-Beta protocol discussion](https://github.com/nikitabobko/AeroSpace/discussions/2139) and the pinned command documentation. The probe measures CLI request round trips (including process startup), not isolated socket transport time.
- No pinned-tag installation, configured-floating/no-key-binding run, or multi-window latency trial was possible here because only `0.20.3-Beta` is installed and its server is disabled.
- The no-change `AXIsProcessTrusted` and `CGPreflightListenEventAccess` checks passed in this environment. The corresponding behavior probes were not run because controlled test apps, windows, and terminal sessions were absent. No permissions or privacy settings were changed.
- AeroSpace is identified as MIT licensed by its [GitHub repository](https://github.com/nikitabobko/AeroSpace) (license at current default branch is `LICENSE.txt`).
- The source checkout lacks `docs/CHARTER.md` and `docs/ROLES.md`; see `docs/STATUS.md`.

## Required follow-up measurements

All seven isolated probe harnesses are present and their thresholds/failure paths are listed in `spikes/README.md`. The socket probe was attempted and failed at its server-unavailable preflight; no p95 samples were collected. Window IDs, AX frames/birth size, global hotkeys, Unfold/Spread throughput, and hold behavior were not run because their required substrate or controlled fixtures were unavailable. The AX/Input Monitoring preflights passed where checked; no system settings were changed. Do not treat absent measurements as passes.

Next trial: in a disposable macOS account, install and pin AeroSpace `v0.21.3-Beta`, configure empty AeroSpace key-binding tables, all windows floating via its new-window callback, and persistent workspaces; run all seven probes with the required fixtures/permissions already granted. Record OS/build, app versions, permissions, sample sizes, thresholds, p95 timings, and failures. If headless operation cannot be achieved with the documented configuration, or if IDs/frames/latency fail the documented thresholds, reopen the substrate choice; do not paper over it with implicit window-size policy.

## Scope

This is a report of observed limits and a provisional recommendation, not a claim that C6 platform behavior passed. The harnesses are isolated under `spikes/` and are not product dependencies.
