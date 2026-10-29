#!/bin/sh
# Refreshes this branch's src/ and tests/ inside build/overlay (after edits).
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[ -d "$ROOT/build/overlay/src" ] || exec "$ROOT/tools/bots-overlay.sh"
cp -r "$ROOT/src/." "$ROOT/build/overlay/src/"
cp -r "$ROOT/tests/." "$ROOT/build/overlay/tests/"
