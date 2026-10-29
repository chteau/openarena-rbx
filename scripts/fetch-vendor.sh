#!/usr/bin/env bash
# Fetches the OpenArena 0.8.8 data, OA gamecode and ioquake3 into vendor/.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p vendor/oa088
[ -d vendor/gamecode ] || git clone https://github.com/OpenArena/gamecode vendor/gamecode
[ -d vendor/gamecode-088 ] || git -C vendor/gamecode worktree add --detach ../gamecode-088 9e0f0c0
[ -d vendor/ioq3 ] || git clone --depth 1 https://github.com/ioquake/ioq3 vendor/ioq3
if [ ! -d vendor/oa088/openarena-0.8.8 ]; then
  curl -L -o vendor/oa088/openarena-0.8.8.zip \
    https://download.tuxfamily.org/openarena/rel/088/openarena-0.8.8.zip
  (cd vendor/oa088 && unzip -q openarena-0.8.8.zip)
fi
