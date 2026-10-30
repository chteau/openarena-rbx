# Network format

This file describes how the server and a client exchange messages. It
follows ioquake3's protocol (`qcommon/msg.c`, `server/sv_client.c`,
`server/sv_snapshot.c`, `client/cl_parse.c`, `client/cl_input.c`)
field for field. It drops the parts a Roblox place does not need: UDP
fragments, Huffman coding, challenges, downloads and pure checks.

| Piece | File |
| --- | --- |
| Shared encoder and decoder | `src/shared/net/msg.luau` (`MSG`) |
| Server side | `src/server/sv/sv_main.luau` |
| Roblox transport | `src/server/sv/transport_roblox.luau` |
| Reference client-side parser and writer | `tests/server/fakeclient.luau` |

The reference parser is a straight port of `CL_ParseServerMessage`,
`CL_ParseGamestate`, `CL_ParseSnapshot`, `CL_ParsePacketEntities` and
`CL_WritePacket`. The integration test decodes every snapshot with it and
compares the result field by field with what the server encoded. On real
maps it finds 0 mismatches in 17k entity states.

## Transport

`ReplicatedStorage.OANet` holds two remotes:

| Remote | Direction | Payload |
| --- | --- | --- |
| `Unreliable` (UnreliableRemoteEvent) | client → server | a client packet (`buffer`) |
| `Unreliable` | server → client | a server message of 800 bytes or less |
| `Reliable` (RemoteEvent) | client → server | `("connect", userinfo)` or `("p", buffer)` |
| `Reliable` | server → client | `("connected", clientNum)`, `("refused", reason)` or `("p", buffer)` |

The 800-byte cut-off keeps unreliable payloads under Roblox's limit of
about 900 serialized bytes. Larger messages go over the reliable remote. That covers every
gamestate (3 to 4 KB on OA maps), and any client packet whose reliable
commands make it too big.

Every packet starts with a 32-bit sequence number, standing in for the
netchan header. Each side drops any packet whose sequence is not newer
than the last one it processed, so the two remotes can interleave freely.
Delta compression keeps working through drops because each side names
what it acknowledged, as in Q3.

### Connecting

1. The client sends `Reliable:FireServer("connect", userinfo)`.
2. The server answers `"connected", clientNum` or `"refused", reason`.
   The reason is the `ClientConnect` string, for example `"Server is full."`
   or a ban message.

The server fills in two userinfo keys itself on every userinfo change.
Clients cannot spoof either one:

| Key | Value |
| --- | --- |
| `ip` | `rbx:<UserId>`, the address that g_admin bans and the reconnect check use |
| `cl_guid` | 32 hex digits from `SV.GuidFor(UserId)` |

From then on the client sends packets. Its first packets carry
`serverId 0`, so the server sees a stale gamestate and sends one. The
client then sends usercmds stamped with the gamestate's `sv_serverid`, and
the first one moves it from `CS_PRIMED` to `CS_ACTIVE`
(`SV_ClientEnterWorld` → `ClientBegin`).

When the player leaves, the transport calls `SV_Disconnect`. When the
server drops a client (kick, timeout or command overflow), the client gets
a `disconnect "reason"` server command and the transport kicks the player
a second later.

## Bit stream

Messages are a plain bit stream, least significant bit first, in a Luau
`buffer`:

- `MSG.WriteBits(msg, value, bits)` writes the low `bits` bits of `value`.
- A negative `bits` on read sign-extends.
- Bytes, shorts and longs are 8, 16 and 32-bit writes. Shorts and longs
  read back signed.
- Strings are bytes ending in 0. On both write and read, `%` and bytes
  above 127 become `.`, as in `MSG_WriteString` and `MSG_ReadString`.

Unlike ioq3, the stream is not Huffman-coded. Roblox compresses remote
payloads itself, and a Huffman coder in Luau would cost more than it saves.

## Server → client message

```
long   sequence             message number (netchan outgoing sequence)
long   reliableAcknowledge  last client command the server executed
{ op ... }                  until svc_EOF (8)
```

| Op | Value | Body |
| --- | --- | --- |
| `svc_nop` | 1 | (none) |
| `svc_gamestate` | 2 | `long serverCommandSequence`, then `{ svc_configstring(3) short index, bigstring }*`, then `{ svc_baseline(4) entityDelta(null → baseline, force) }*`, then `svc_EOF`, `long clientNum`, `long checksumFeed` |
| `svc_serverCommand` | 5 | `long sequence`, `string text` (a reliable command; the server resends it until acknowledged) |
| `svc_snapshot` | 7 | see below |

The snapshot body is:

```
long   serverTime
byte   deltaNum        0 = not delta compressed, else messageNum - deltaNum
byte   snapFlags       SNAPFLAG_RATE_DELAYED 1, SNAPFLAG_NOT_ACTIVE 2, SNAPFLAG_SERVERCOUNT 4
byte   areabytes, then areabytes bytes of area mask (inverted: 0 bit = visible)
playerStateDelta(from = ps of frame deltaNum, or zeros)
packetEntities:
    { bits(10) number, entityDelta }*  in increasing number order
    bits(10) 1023                      end marker
```

Every message ends with `svc_EOF`. The game's own entity is never in
`packetEntities`, because the client rebuilds it from the playerState
(`BG_PlayerStateToEntityState`).

### Entity delta (`MSG.WriteDeltaEntity` / `MSG.ReadDeltaEntity`)

The 10-bit entity number has already been read when the delta starts.

```
bit remove              1 = entity left the snapshot (nothing follows)
bit hasDelta            0 = identical to the "from" state
byte lc                 number of fields up to the last changed one
for each of the first lc fields in MSG.entityStateFields order:
    bit changed
    if changed, float field:   bit nonzero; if nonzero:
                                  bit 0 + 13 bits (value + 4096)  integral, |v| < 4096
                                  bit 1 + 32 bits IEEE float
    if changed, int field:     bit nonzero; if nonzero: <field bits> bits
```

The C code compares fields as 32-bit ints, so the port compares floats by
bit pattern: -0 → +0 counts as a change and arrives as +0. Ints are sent
in the field's width. Fields after `lc` are copied from the "from" state.

- **New entity:** the delta source is the entity's baseline from the
  gamestate.
- **Entity seen in the delta frame:** the source is its state in that
  frame.

### PlayerState delta

```
byte lc
for each of the first lc MSG.playerStateFields:
    bit changed; if changed:
        float field: bit 0 + 13 bits (value + 4096) | bit 1 + 32-bit float
        int field:   <bits> bits (negative widths sign-extend on read)
bit arraysChanged; if 1:
    bit + 16-bit mask + shorts   stats[16]
    bit + 16-bit mask + shorts   persistant[16]
    bit + 16-bit mask + shorts   ammo[16]
    bit + 16-bit mask + longs    powerups[16]
```

Field order and widths are ioq3's `entityStateFields` and
`playerStateFields`, unchanged, so OA's cgame logic sees the same
quantisation as the C game. The playerState carries several values
packed into those fields:

- `weapon` is 5 bits.
- `generic1` is 8 bits.
- `movementDir` is 4 bits.

## Client → server packet

```
long   sequence              client packet number (netchan)
long   serverId              sv_serverid of the gamestate the client has
long   messageAcknowledge    last server message sequence received
long   reliableAcknowledge   last server command sequence received
{ clc_clientCommand(4) long seq, string text }*   every unacknowledged command
[ clc_move(2) | clc_moveNoDelta(3)
  byte count (1..32)
  count x usercmdDelta ]
clc_EOF(5)
```

The move op tells the server whether to delta-compress the next snapshot:

- `clc_move` means "delta from messageAcknowledge is fine".
- `clc_moveNoDelta` asks for a full snapshot. The client sends it when it
  does not hold that snapshot.

Client commands are the `cmd` strings the cgame and UI send, such as
`team red`, `say hi`, `callvote map oa_dm1`, `vote yes`, `follow 2` and
`userinfo "\name\..."`. Each carries a sequence number, and the client
resends it until the server acknowledges it.

The server's flood protection works as in ioq3:

- It ignores more than one command per second from an active client, but
  still processes that client's moves.
- A gap in the sequence numbers drops the client with "Lost reliable
  commands".

### usercmd_t

`usercmd_t` is defined in `src/shared/structs.luau`:

| Field | Meaning | On the wire |
| --- | --- | --- |
| `serverTime` | the client's command time, ms | |
| `angles[3]` | `ANGLE2SHORT(viewangle)` | 16 bits |
| `buttons` | BUTTON_ATTACK 1, TALK 2, USE_HOLDABLE 4, GESTURE 8, WALKING 16, AFFIRMATIVE 32, ... | 16 bits |
| `weapon` | WP_* | 8 bits |
| `forwardmove`, `rightmove`, `upmove` | -127..127 | 8 bits, signed |

### usercmd delta (`MSG.WriteDeltaUsercmdKey`)

```
bit 1 + 8 bits (serverTime - previous.serverTime)   if the gap is < 256
bit 0 + 32 bits serverTime                           otherwise
bit changed; if 1, each field as
    bit 0 (same) | bit 1 + (value XOR key) in the field's width
```

The first command is deltaed against an all-zero command. The key mixes
values that both sides know:

```
key = checksumFeed XOR messageAcknowledge XOR MSG.HashKey(serverCommands[reliableAcknowledge & 63], 32)
```

`checksumFeed` comes from the gamestate. Before the fields are written,
the key is XORed with `serverTime`.

The server runs `ClientThink`, and so a full Pmove, for each command that
is newer than the last one executed and not newer than the last one in the
packet. This is ioq3's `SV_UserMove`. Movement therefore follows the
client's frame times. `pmove_fixed`, `pmove_msec` and
`g_synchronousClients` work as in OA.

## Timing

`Game.Frame(msec)` runs from `RunService.Heartbeat`, with a carried
fraction so that whole milliseconds reach the engine.

- **Game frames:** the server runs `G_RunFrame` every `1000 / sv_fps` ms.
  `sv_fps` defaults to 20.
- **Snapshots:** each client gets one every `1000 / snaps` ms, where
  `snaps` comes from userinfo (default 20, capped at `sv_fps`).
- **Rates:** `rate` is parsed but not enforced. Roblox paces remotes, and
  an unreliable event that cannot go out is dropped rather than queued.
- **Ping:** measured as in `SV_CalcPings`, from the server time a snapshot
  was sent to the server time it was acknowledged. The game reads it from
  `ps.ping`.

`map_restart` keeps the gamestate. Clients get a `map_restart` server
command and a new `sv_serverid` through a `cs 1` update. A map change
sends a new gamestate.

## What the client gets from the game

### Data shapes

`src/shared/structs.luau` (from `q_shared.h`) defines these shapes. The
client constructs them with `S.playerState_t()`, `S.entityState_t()`,
`S.usercmd_t()` and `S.trajectory_t()`.

- **Arrays** are 0-based tables: `{[0] = x, y, z}`, `stats[0..15]` and
  so on.
- **Constants** are in `src/shared/consts.luau`. They include `CS_*`,
  `EV_*`, `ET_*`, `PW_*`, `WP_*`, `STAT_*`, `PERS_*`, `EF_*`, `PMF_*`,
  `GT_*` and `TEAM_*`.
- **Numbering** is OpenArena 0.8.8's (`bg_public.h` at gamecode
  `9e0f0c0`), not OA master's. Stats are `STAT_HEALTH` 0,
  `STAT_HOLDABLE_ITEM` 1, `STAT_PERSISTANT_POWERUP` 2, `STAT_WEAPONS` 3,
  `STAT_ARMOR` 4, `STAT_DEAD_YAW` 5, `STAT_CLIENTS_READY` 6 and
  `STAT_MAX_HEALTH` 7. Gametypes stop at `GT_DOMINATION` 12 (no
  Possession). Events end at `EV_TAUNT_PATROL` 82, and animations at
  `MAX_TOTALANIMATIONS` 37 (no master-only footstep events or OA3 torso
  animations). The netField tables are ioq3's and did not change.

### Configstrings

The `CS_*` indices in the table below come from `bg_public.h`. The
gamestate carries every non-empty configstring. Later changes arrive as
reliable `cs <index> "<value>"` commands. A configstring of 1000 bytes or
more is split into `bcs0`, `bcs1` and `bcs2` pieces, as in ioq3
(`SV_SendConfigstring`).

| Index | Contents |
| --- | --- |
| 0 `CS_SERVERINFO` | serverinfo cvars |
| 1 `CS_SYSTEMINFO` | `sv_serverid`, `sv_cheats`, ... |
| 2 | music |
| 3 | map message |
| 5 `CS_WARMUP` | |
| 8-19 | votes |
| 20 | game version |
| 21 `CS_LEVEL_START_TIME` | |
| 22 `CS_INTERMISSION` | |
| 23 `CS_FLAGSTATUS` | |
| 24 `CS_SHADERSTATE` | |
| 27 `CS_ITEMS` | the item-registered mask |
| 32+ `CS_MODELS` | |
| 288+ `CS_SOUNDS` | |
| 544+ `CS_PLAYERS` | |
| 608+ `CS_LOCATIONS` | |

### Events

These are the standard Q3 mechanisms, from `bg_misc.c`:

- **Predictable events** go in `ps.events[0..1]` and `ps.eventParms`.
  `ps.eventSequence` counts them.
- **External events** go in `ps.externalEvent`.
- **Entity events** go in `es.event`. Toggle bits `EV_EVENT_BITS` (0x300)
  mark a new occurrence of the same event.
- **Temp entities** have `eType = ET_EVENTS + EV_*`.

The event names are in `BG.eventnames` (`bg_misc.c`'s `eventnames[]`), in
`EV_*` order.

### Server commands

These are the commands the game sends, as `cg_servercmds.c` parses them:

| Command | Purpose |
| --- | --- |
| `cs` | configstring update |
| `print` | console print |
| `cp` | centerprint |
| `chat`, `tchat` | chat (bots and the server) |
| `rchat <MessageId> <chat\|tchat> "<prefix>"` | Roblox only: the name prefix of a player's line, whose text TextChatService delivers filtered (`server/sv/chat_roblox.luau`) |
| `vchat`, `vtchat`, `vtell`, `tell` | voice chat and tells |
| `scores` | scoreboard |
| `tinfo` | team overlay |
| `map_restart` | |
| `disconnect` | |
| `oh` | obelisk health |
| `team` | |
| `elimination` | elimination state |
| `attackingteam` | |
| `domStatus` | Domination point status |
| `ddTakeAt` | Double Domination |
| `customvotes` | |
| `accs` | accuracy |
| `respawn` | |
| `ch` | challenge (award) progress |
| `bp` | big centered print from the server console |
| `loaddefered` | |
| `levelshot`, `clientLevelShot` | |
