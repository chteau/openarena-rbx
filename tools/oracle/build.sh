#!/bin/sh
# Build the C oracle: ioquake3's collision model plus OpenArena's bg_pmove,
# bg_slidemove and bg_misc as shipped in 0.8.8 (gamecode 9e0f0c0, the
# vendor/gamecode-088 checkout), compiled natively, driven by oracle.c.
# Output goes to build/oracle (git-ignored). Usage: tools/oracle/build.sh
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$ROOT/build/oracle
IOQ=$ROOT/vendor/ioq3/code/qcommon
OA=$ROOT/vendor/gamecode-088/code
SRC=$ROOT/tools/oracle
mkdir -p "$OUT"
cd "$OUT"
# Plain SSE float math, no contraction into FMA, no fast-math: every float
# op rounds to single precision, which is what the Luau port reproduces.
CFLAGS="-O2 -ffp-contract=off -fno-fast-math -fno-strict-aliasing -w -DNDEBUG"

# collision side, against ioquake3's headers; only CM_* and the dump helpers
# stay global so its q_math does not clash with OpenArena's
for f in cm_load cm_patch cm_polylib cm_test cm_trace q_math q_shared; do
	gcc -c $CFLAGS -I"$IOQ" "$IOQ/$f.c" -o io_$f.o
done
gcc -c $CFLAGS -I"$IOQ" "$SRC/cm_side.c" -o io_cm_side.o
ld -r io_*.o -o cm_all.o
objcopy -w --keep-global-symbol='CM_*' --keep-global-symbol='oracle_*' cm_all.o cm_all.o

# game side, against OpenArena's headers
for f in game/bg_pmove game/bg_slidemove game/bg_misc qcommon/q_math qcommon/q_shared; do
	gcc -c $CFLAGS -DARCH_STRING='"x86_64"' -I"$OA/qcommon" "$OA/$f.c" -o oa_$(basename $f).o
done
gcc -c $CFLAGS -DARCH_STRING='"x86_64"' -I"$OA/qcommon" -I"$OA/game" "$SRC/oracle.c" -o oracle.o
gcc -o oracle oracle.o oa_*.o cm_all.o -lm
echo "built $OUT/oracle"
