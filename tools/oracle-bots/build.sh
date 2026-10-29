#!/bin/sh
# Build the bot C oracle: ioquake3's botlib and collision model compiled
# natively, with a minimal botlib import (oracle_bots.c) whose traces are
# ioquake3's CM_BoxTrace, then extract the oracle maps (.bsp + .aas) from
# the OpenArena pk3s. Everything lands in build/oracle-bots (git-ignored).
#   tools/oracle-bots/build.sh
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$ROOT/build/oracle-bots
IOQ=$ROOT/vendor/ioq3/code
SRC=$ROOT/tools/oracle-bots
PK3=$ROOT/vendor/oa088/openarena-0.8.8/baseoa
MAPS=${MAPS:-"oa_dm1 oa_ctf2 am_thornish oa_bases7 oa_koth1 oa_koth2"}
mkdir -p "$OUT/obj" "$OUT/maps"
cd "$OUT/obj"
# plain SSE float math, no FMA contraction, no fast-math: every float op
# rounds to single precision, which is what the Luau port reproduces
CFLAGS="-O2 -ffp-contract=off -fno-fast-math -fno-strict-aliasing -w -DNDEBUG -DBOTLIB"
# AAS_UpdateAreaRoutingCache reads its zeroed startareatraveltimes[128] once per
# reversed link of the start area: oa_koth1's area 205 has 266, so C reads stack
# garbage past the array. The oracle gets the zeroes C meant, like the port.
sed 's/startareatraveltimes\[128\]/startareatraveltimes[4096]/' "$IOQ/botlib/be_aas_route.c" >be_aas_route.c
for f in "$IOQ"/botlib/*.c; do
	case $f in */be_aas_route.c) f=$PWD/be_aas_route.c ;; esac
	gcc -c $CFLAGS -I"$IOQ/qcommon" -I"$IOQ/botlib" "$f" -o bl_$(basename "$f" .c).o
done
for f in cm_load cm_patch cm_polylib cm_test cm_trace q_math q_shared md4; do
	gcc -c $CFLAGS -I"$IOQ/qcommon" "$IOQ/qcommon/$f.c" -o qc_$f.o
done
gcc -c $CFLAGS -I"$IOQ/qcommon" -I"$IOQ/botlib" "$SRC/oracle_bots.c" -o oracle_bots.o
gcc -o "$OUT/oracle-bots" *.o -lm
# maps: the last pk3 holding a file wins, like the search path
for m in $MAPS; do
	for ext in bsp aas; do
		for p in pak1-maps.pk3 pak6-misc.pk3 pak6-patch085.pk3 pak6-patch088.pk3; do
			if unzip -l "$PK3/$p" "maps/$m.$ext" >/dev/null 2>&1; then
				unzip -o -q -j "$PK3/$p" "maps/$m.$ext" -d "$OUT/maps"
			fi
		done
	done
done
# botfiles (weapon/item configs, characters, chats) for BotLibSetup
for p in pak6-misc.pk3 pak6-patch088.pk3; do
	unzip -o -q "$PK3/$p" 'botfiles/*' -d "$OUT"
done
echo "built $OUT/oracle-bots"
