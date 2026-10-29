#!/usr/bin/env bash
# Takes an OpenArena 0.8.8 reference screenshot at 1280x720.
#   scripts/oa-ref.sh <name> [console commands run before the shot...]
# Uses vendor/oa088's openarena.x86_64 when its SDL 1.2 loads, otherwise an
# ioquake3 client built from vendor/ioq3 (OA_ENGINE=path) running the same
# OA 0.8.8 QVMs and data. The shot lands in docs/parity/ref/<name>.png.
set -euo pipefail
cd "$(dirname "$0")/.."
name=$1; shift
oa=$PWD/vendor/oa088/openarena-0.8.8
engine=${OA_ENGINE:-$oa/openarena.x86_64}
home=${OA_HOME:-$HOME/.openarena}
shots=$home/baseoa/screenshots
rm -f "$shots"/shot*.tga "$home/baseoa/crashlog.txt"
args=(+set cl_renderer opengl1 +set fs_basepath "$oa" +set com_basegame baseoa
  +set fs_homepath "$home" +set r_mode -1 +set r_customwidth 1280
  +set r_customheight 720 +set r_fullscreen 0 +set s_initsound 0
  +set cl_allowDownload 0 +set com_introplayed 1)
# The commands go through a cfg: the command line splits on '+', which
# would eat "+scores" and friends.
printf '%s\n' "$@" screenshot "wait 30" quit >"$home/baseoa/oaref.cfg"
args+=(+exec oaref.cfg)
(cd "$(dirname "$engine")" && timeout 120 "$engine" "${args[@]}" >"$home/oa-ref.log" 2>&1) || true
mkdir -p docs/parity/ref
convert "$shots"/shot0000.tga "docs/parity/ref/$name.png"
echo "docs/parity/ref/$name.png"
