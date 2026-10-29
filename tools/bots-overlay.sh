#!/bin/sh
# Lays the bot port over the game module in build/overlay so the bot code
# can be loaded and run headless (lune) before feat/bots and feat/game are
# merged: the game worktree's src/ and tests/server/ first, then this
# branch's src/ and tests/ on top. Nothing here is committed.
#   tools/bots-overlay.sh            (GAME_WT defaults to ../game)
#   cd build/overlay && lune run tests/bots/<test>.luau
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GAME_WT=${GAME_WT:-$ROOT/../game}
CONV_WT=${CONV_WT:-$ROOT/../conv}
OUT=$ROOT/build/overlay
rm -rf "$OUT"
mkdir -p "$OUT/build" "$OUT/tests"
cp -r "$GAME_WT/src" "$OUT/src"
cp -r "$GAME_WT/tests/server" "$OUT/tests/server"
cp -r "$ROOT/src/." "$OUT/src/"
cp -r "$ROOT/tests/." "$OUT/tests/"
ln -s "$ROOT/vendor" "$OUT/vendor"
ln -s "$GAME_WT/build/maps" "$OUT/build/maps"
ln -s "$CONV_WT/build/maps" "$OUT/build/conv-maps"
[ -d "$ROOT/build/oracle-bots" ] && ln -s "$ROOT/build/oracle-bots" "$OUT/build/oracle-bots"
[ -d "$ROOT/build/botfiles" ] && ln -s "$ROOT/build/botfiles" "$OUT/build/botfiles"
echo "overlay: $OUT"
