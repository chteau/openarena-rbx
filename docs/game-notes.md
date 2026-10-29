# Game logic notes

These notes cover the Luau port of the collision model, bg_* and g_*,
plus the dedicated-server engine around them. They record the decisions
taken, the evidence behind them, and the places where the port differs
from the C, with the reason for each.

## Layout

| Path | What | C original |
| --- | --- | --- |
| `src/shared/cm/` | collision model: BSP lumps → brushes, patches, traces, PVS/areas | ioq3 `qcommon/cm_*.c` |
| `src/shared/Collision.luau` | public face of `cm/` (`Collision.BoxTrace`, ...) | `cm_public.h` |
| `src/shared/bg/` | pmove, slidemove, item list, trajectories, events | OA `bg_pmove.c`, `bg_slidemove.c`, `bg_misc.c` |
| `src/shared/q_math.luau`, `q_shared.luau` | float32-exact math, strings, info strings, parsing | `q_math.c`, `q_shared.c` |
| `src/shared/net/msg.luau` | message bit stream and delta coding | ioq3 `qcommon/msg.c` |
| `src/server/g_*.luau` | the game module, every g_*.c of OA (large files in `_1`, `_2`, ... parts) | OA `code/game/g_*.c` |
| `src/server/bg_alloc.luau`, `ai_stubs.luau` | BG_InitMemory and the bot entry points | `bg_alloc.c`, `ai_main.c` prototypes |
| `src/server/sv/` | dedicated-server engine: cvars, command buffer, virtual FS, world links, trap layer, frame loop, clients, snapshots, Roblox transport | ioq3 `qcommon/cvar.c`, `cmd.c`, `files.c`, `server/*.c` |
| `src/server/Game.luau` | loads all of the above and exposes `Init`, `Command` and `Frame` | |

Every ported file keeps the GPL-2.0 header and names its C source.

## How the port was checked

- **Collision and movement**
  - A native C oracle (`tools/oracle/oracle.c`) links ioq3's `cm_*` and
    OA's `bg_*` and logs traces and Pmove frames on real maps.
  - **Traces:** the Luau port reproduces the oracle's trace logs bit for
    bit.
  - **Pmove:** bit-exact on 9 maps. That is 405,000 frames in resync mode
    (Luau state reset to C every frame) and 270 free-run scenarios (Luau
    runs alone for whole scenarios). The runs cover walking, strafe
    jumping, crouching, water, stairs, slopes, jump pads and
    teleporters. Max divergence is 0 ulps.
  - Run with `lune run tests/oracle/replay_pmove.luau <map.bsp> <log>`.
- **Game module**
  - `tools/check_port.sh --strict` over `src/server`, `src/server/sv`
    (the Roblox-only transport aside) and `msg.luau` runs a static check
    (57 files, 0 errors). It loads each module and resolves every
    `C.`/`QS.`/`Q.`/`BG.`/`S.` member. It requires every `G.X` call to
    have exactly one definition. It lints for undeclared globals,
    misleading `and/or`, bad format strings and similar mistakes.
  - Cross-file signature mismatches are a pattern the static check
    misses: a function whose C out-parameter one file kept while another
    turned it into a return value. These were found with an arity scan
    and fixed: `G_SayArgv`, `G_SanitiseString`, `G_DecolorString`,
    `G_MatchOnePlayer`, `G_admin_name_check` and the
    `G_admin_ban_check` caller.
- **Integration**
  - `tests/server/test_integration.luau` runs a headless server on real
    maps with fake clients over the loopback transport. It covers every
    mode, a vote, the tourney queue, map_restart and map change.
  - Every snapshot a client decodes is compared with the server's
    frame: 0 mismatches.
- **Rules**
  - `tests/server/test_rules.luau` (81 checks) covers:
    - the damage, armor, self-damage, handicap and quad formulas;
    - item respawn timers;
    - CTF capture, return and auto-return.
- **Benchmarks:** `tests/bench/bench_trace.luau <map>` and
  `tests/bench/bench_server.luau [map] [clients]`.

## Decisions and deviations

### The vendored gamecode is post-0.8.8

`vendor/gamecode` is OA's later `gamecode` tree, not the 0.8.8 release.
It has:

- `GT_POSSESSION`;
- `cg_enableQ` and the Quake-like viewheight;
- extra footsteps;
- `g_unlagged`, `g_admin` and `g_killspree`;
- in pmove: `DF_NO_BUNNY`, `DF_FAST_WATER_MOVE`,
  `DF_INSTANT_WEAPON_CHANGE` and `PMF_ELIMWARMUP`.

The port follows this tree, because it is the one the task vendors. With
the extra flags off, everything 0.8.8 does behaves the same.

### `MISSIONPACK` is not defined

This matches how OA builds its game module. The `#else` branches are
ported. OA's own additions (Overload, Harvester, 1FCTF and so on) are
not behind `MISSIONPACK` in this tree, so they are all present.

### `g_rankings.c` is not ported

OA's build does not compile it (it is the id rankings client).
`trap_Rankings*` is never called.

### Ladders

There are no ladders. Neither Q3's nor OA's pmove has ladder code
(`grep -i ladder bg_*.c` finds nothing), so there is nothing to port.

### Floats: native, not QVM

The reference is the native build (`openarena.x86_64`'s qagame and our
oracle), not the QVM interpreter:

- arithmetic is float32 with C's promotions;
- double literals promote to double and round once at the store;
- `M_PI` is `<math.h>`'s double.

QVM builds can differ by an ulp in rare places. The native build is the
one the oracle checks.

### trap_SnapVector

The engine's `trap_SnapVector` rounds through an int with SSE (round to
nearest even), so -0 becomes +0. An earlier oracle used `rintf`, which
keeps -0. That caused 288 bogus velocity mismatches until the oracle was
fixed. `Q.SnapVectorRint` and `G.trap_SnapVector` do the integer round
trip.

### Capsule clip handle

`CM_TempBoxModel(..., capsule)` returns `CAPSULE_MODEL_HANDLE` (254). In
ioq3, `CM_ClipHandleToModel(254)` would `Com_Error`, because only the
trace code special-cases that handle. Our `CM_ClipHandleToModel` returns
the box model for it. That model holds the bounds the trace reads, so
`SV_ClipHandleForEntity` on an `SVF_CAPSULE` entity works instead of
erroring.

### PVS for cluster -1

The C does `clientpvs[cluster >> 3]` without a bounds check, so a point
in the void (cluster -1) reads the byte before the visibility data.
`sv_world.luau`'s `pvsBit` gives the same answer for every in-range read
and treats out-of-range bytes as "not visible". The C result there
depends on memory layout.

### ARMOR_PROTECTION is a double

`ceil(damage * 0.66)` is computed in double. So 100 damage on 100 armor
saves 67, not 66, because `100 * 0.66 = 66.00000000000001`. The port
does the same, and `test_rules` checks it.

### The dropped-flag return time is 30 s, not 40 s

`g_team.h`'s `CTF_FLAG_RETURN_TIME` (40 s) is never used.
`LaunchItem` gives dropped flags `Team_DroppedFlagThink` at +30 s, and
that is what the port and `test_rules` follow.

### Memory and statics

- `BG_Alloc` and `BG_Free` became table construction, and
  `BG_InitMemory` is a no-op.
- `game_memory` reports the Luau heap.
- File-static variables of C files that were split into parts live in
  `G.FileStatics("<cfile>")`, so every part shares them.

### Bots

The bot AI and botlib are a separate workstream (ARCHITECTURE.md #6).
`ai_stubs.luau` keeps every hook the game calls (`BotAISetup`,
`BotAILoadMap`, `BotAIStartFrame`, `BotAISetupClient`, ...) and the
`trap_AAS_*` queries. `trap_AAS_Initialized()` is false, so
`G_BotConnect` refuses bots the way an engine without AAS data does. The
engine side is ready for bots:

- `trap_BotAllocateClient` and `trap_BotFreeClient` manage client slots.
- Bot clients get snapshots built but not sent.
- `SV.SV_ClientThink(cl, cmd)` is the entry point for bot usercmds.

### g_admin and killspree

Both are ported in full. Their files (`admin.dat`, `sprees.dat`,
`g_adminLog`) go through the virtual FS (`sv/fs.luau`):

- At first start they do not exist, and the game prints the same "could
  not open" notices the C does.
- The host can mount saved copies at `Game.Init({files = ...})`.
- The host can persist writes through `Fs.onWrite(path, data)`, for
  example to a DataStore.

Admin identities rest on two userinfo keys the server sets itself:

- **`cl_guid`** is forced to a value derived from the Roblox UserId
  (`SV.GuidFor`). The admin and GUID checks therefore apply to accounts,
  and clients cannot spoof them.
- **`ip`** is `rbx:<UserId>`, so IP bans become account bans.

### Engine differences

`src/server/sv` is a port of ioq3's server, minus what has no meaning on
Roblox:

- **Dropped:** challenges, netchan fragments, downloads, pure checks,
  rcon, master heartbeats, VoIP and rate limiting.
- **Messages:** not Huffman-coded.
- **Snapshots:** each frame keeps its own entity copies instead of
  ioq3's shared ring, so "delta from an entity that rolled off the
  ring" cannot happen.
- **Clock:** `com_frameTime` (the source of `sv_serverid`) starts at a
  random non-zero value. A client's first packets carry serverId 0 and
  must never look current.

`docs/formats/net.md` documents the wire format.

### The lumps interface (for the converter)

`Collision.LoadMap(name, lumps)` takes plain tables, and
`src/shared/cm/cm_load.luau`'s header documents their shape:

- `shaders`, `planes`, `nodes`, `leafs`, `leafsurfaces`, `leafbrushes`,
  `models`, `brushes`, `brushsides`, `entities` (string), `visibility`
  (buffer) and `numSurfaces`;
- `patches`, keyed by surface index, with `shaderNum`, `width`, `height`
  and `points`.

`cm/bsp.luau` builds these lumps from an IBSP v46 file, and the tests use
it. When the converter's collision blob (`docs/formats/collision.md`)
lands, a thin adapter that turns the blob into this table is all that is
needed. The server gets maps through `Game.Init({loadMap = function(name)
return lumps end})`.

## Trap API

The game calls the engine through `G.trap_*`, implemented in
`src/server/sv/sv_game.luau`. These are the C calls, with out-parameters
turned into return values:

- **Strings and handles come back as return values.**
  `trap_Cvar_VariableStringBuffer(name) -> string`,
  `trap_GetUserinfo(n) -> string`, `trap_GetConfigstring(n) -> string`,
  `trap_Argv(n) -> string`, `trap_FS_Read(len, f) -> string`,
  `trap_FS_FOpenFile(path, mode) -> (len, handle)`,
  `trap_FS_GetFileList(dir, ext) -> (count, names[0..])`.
- **Structs are still filled in place.** `trap_Trace(results, ...)`,
  `trap_GetUsercmd(n, cmd)`, `trap_RealTime(qtime)`.
- **trap_GetEntityToken() returns `string?`**: `nil` where C returns
  `qfalse`.
- **trap_Error raises** a game error object
  (`{isGameError = true, text}`).

## API for the client and bots

- **Shapes:** `src/shared/structs.luau` defines `playerState_t`,
  `entityState_t`, `usercmd_t`, `trajectory_t`, `trace_t` and `pmove_t`.
  Constants are in `src/shared/consts.luau`.
- **Movement:** `BG.Pmove(pm)` uses the same code as the server. A
  `pmove_t` with `ps`, `cmd`, `trace(results, start, mins, maxs, end,
  pass, mask)` and `pointcontents(p, pass)` callbacks is all the client's
  prediction needs.
- **Events:** event names are in `BG.eventnames`. The helpers are
  `BG.BG_EvaluateTrajectory`, `BG.BG_PlayerStateToEntityState` and
  `BG.BG_TouchJumpPad`.
- **Network:** `src/shared/net/msg.luau` plus `docs/formats/net.md`. The
  parser and writer in `tests/server/fakeclient.luau` are the reference
  `cl_parse.c` / `CL_WritePacket` the client can follow.
- **Bots:** see Bots above. `SV.SV_ClientThink(cl, cmd)` and
  `SV.SV_ExecuteClientCommand(cl, text, true)` feed a bot's input.
  `SV.SV_BuildClientSnapshot(cl)` fills `cl.frames[...]` with what it
  sees.
