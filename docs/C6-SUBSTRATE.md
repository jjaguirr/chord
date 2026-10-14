# C6 substrate report

## Decision

Keep AeroSpace as the intended replaceable backend, but do not treat it as validated or pin a release for implementation yet. The installed environment cannot run the required headless configuration: AeroSpace client and server are `0.20.3-Beta` (commit `6dde91ba43f62b407b2faf3739b837318266e077`), older than the previously observed `v0.21.3-Beta`; the server reports that it is disabled and rejects commands. Enabling it would alter machine-level behavior, so this report does not do so. The project should retain the backend protocol and revisit the pin after a controlled test on the required version.

AeroSpace remains the lower-risk default relative to a Chord-owned workspace model because its documented socket provides an existing control boundary and the repository already describes it as replaceable. That is a provisional architecture choice, not evidence that latency, headless operation, floating rules, persistent workspaces, or window behavior meet requirements. A Chord-owned model would avoid depending on those unverified behaviors but requires implementing and maintaining window/workspace control directly; this checkout has no runtime to compare it empirically.

## Evidence and gaps

- `aerospace --version`: client and server both report `0.20.3-Beta`, commit `6dde91ba43f62b407b2faf3739b837318266e077`.
- `aerospace list-windows --all ...`: server responds: “AeroSpace server is disabled and doesn't accept commands. You can use 'aerospace enable on' to enable the server”. No command was issued to enable it.
- A Unix socket path `/tmp/bobko.aerospace-jjaguirr.sock` exists, but server rejection means its presence does not establish an operational protocol or latency.
- The issue cites `v0.21.3-Beta` as newest previously seen. This installed version is not that tag. No pinned-tag, configured-floating, no-key-binding, multi-window, or latency trial was possible here.
- The task environment does not authorize granting Accessibility or Input Monitoring permissions; those tests were not run. No privacy or permission settings were changed.
- The source checkout lacks `docs/CHARTER.md` and `docs/ROLES.md`; see `docs/STATUS.md`.

## Required follow-up measurements

`spikes/README.md` specifies probe thresholds and failure paths. Only `spikes/socket-latency.sh` is implemented; it reports `FAIL` here because the installed AeroSpace server is disabled. The other six harnesses remain unimplemented, and their measurements are unavailable. Do not treat this report as evidence that those assumptions passed.

On a disposable test account with Accessibility and Input Monitoring already granted, install and pin the selected AeroSpace release, disable its user key bindings, configure all windows floating and persistent workspaces, then implement and run the six pending probes. Record OS/build, app versions, permissions, sample sizes, thresholds, raw elapsed times, and failures. Measure socket round-trip distributions rather than inferring latency from socket existence. A failure of server operation, frame survival, identity stability, or target frame rate reopens the substrate choice; do not paper over it with implicit window-size policy.

## Scope

This is a report of observed limits and a provisional recommendation, not a claim that C6 platform behavior passed. The harnesses are isolated under `spikes/` and are not product dependencies.
