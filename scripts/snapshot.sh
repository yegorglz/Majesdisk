#!/bin/bash
# Needs a debug build (scripts/build-app.sh debug) for --collect / --delete-collected / --debug-no-elevation.
# Usage: scripts/snapshot.sh <out.png> <delay-seconds> [app args...]  — renders the app window to a PNG.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$1"; DELAY="$2"; shift 2
rm -f "$OUT"
open -W -n dist/MajesDisk.app --args --snapshot "$OUT" --snapshot-delay "$DELAY" "$@"
ls "$OUT" >/dev/null
