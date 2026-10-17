#!/usr/bin/env bash
# Builds Chord.app from the SwiftPM `Chord` executable product.
# Usage: scripts/build-app.sh [output-dir]   (default: <repo>/build)
# The bundle is ad-hoc signed; release signing and the final bundle id come from the release issue.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${1:-$root/build}"
app="$out_dir/Chord.app"
bundle_src="$root/scripts/bundle"

cd "$root"
swift build -c release --product Chord
bin_dir="$(swift build -c release --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Chord" "$app/Contents/MacOS/Chord"
cp "$bundle_src/Info.plist" "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist" >/dev/null
codesign --force --sign - --options runtime --entitlements "$bundle_src/Chord.entitlements" "$app"
codesign --verify --strict "$app"

echo "$app"
