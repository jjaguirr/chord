#!/bin/sh
# C6 socket latency probe; run only with the pinned AeroSpace server enabled.
set -u
threshold_ms=16.67
samples=100
if ! command -v aerospace >/dev/null 2>&1; then
  printf 'FAIL: socket latency requires aerospace CLI; fail path: install pinned AeroSpace and rerun\n'
  exit 1
fi
if ! aerospace list-windows --all --format '%{window-id}' >/dev/null 2>&1; then
  printf 'FAIL: socket unavailable; threshold p95 <= %sms; fail path: enable pinned AeroSpace server in disposable account, then rerun\n' "$threshold_ms"
  exit 1
fi
# Use Perl's monotonic clock and record each measured CLI round-trip in ms.
result=$(aerospace list-windows --all --format '%{window-id}' >/dev/null 2>&1) || {
  printf 'FAIL: socket probe failed; threshold p95 <= %sms; fail path: inspect server/socket configuration\n' "$threshold_ms"
  exit 1
}
export samples
latencies=$(perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e '
  $n=$ENV{samples};
  for (1..$n) {
    $start=clock_gettime(CLOCK_MONOTONIC);
    system("aerospace list-windows --all --format \"%{window-id}\" >/dev/null 2>&1") == 0 or exit 2;
    printf "%.3f\n", (clock_gettime(CLOCK_MONOTONIC)-$start)*1000;
  }
') || {
  printf 'FAIL: socket request failed; threshold p95 <= %sms; fail path: inspect server/socket configuration\n' "$threshold_ms"
  exit 1
}
p95=$(printf '%s\n' "$latencies" | sort -n | awk 'NR==int(ENVIRON["samples"]*.95+0.999) {print; found=1} END {if (!found) exit 1}') || {
  printf 'FAIL: incomplete latency samples; threshold p95 <= %sms; fail path: rerun with a healthy server\n' "$threshold_ms"
  exit 1
}
awk -v p95="$p95" -v limit="$threshold_ms" 'BEGIN { if (p95 <= limit) {printf "PASS: socket p95 %.3fms <= %sms over 100 samples\n", p95, limit; exit 0} else {printf "FAIL: socket p95 %.3fms > %sms; fail path: investigate server/protocol latency\n", p95, limit; exit 1} }'
