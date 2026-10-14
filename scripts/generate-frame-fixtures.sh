#!/bin/sh
# Regenerates Tests/ChordCoreTests/FrameLandmarkFixtures.swift by bisecting
# frame() itself. Compiles the pure core directly, so it needs only swiftc.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

swiftc -O -o "$tmp/generate-frame-fixtures" \
    "$root/Sources/ChordCore/Unfold.swift" \
    "$root/Sources/ChordCore/PureMath.swift" \
    "$root/scripts/frame-fixtures/main.swift"
"$tmp/generate-frame-fixtures" > "$root/Tests/ChordCoreTests/FrameLandmarkFixtures.swift"
