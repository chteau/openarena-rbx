# Architecture

Goal: OpenArena 0.8.8 on Roblox, as close to 1:1 as the platform allows,
with every map, weapon, item, player model and game mode. The place is
assembled through rbx-native's MCP server (`rbxstudio --mcp`).

## Sources (not committed, fetched into `vendor/`)

| Path | What | Used for |
|---|---|---|
| `vendor/oa088/openarena-0.8.8/baseoa/*.pk3` | OA 0.8.8 final data | all assets. Skip `pak2-players-mature.pk3` |
| `vendor/oa088/openarena-0.8.8/missionpack/` | Team Arena-style data | Harvester/Overload/1FCTF assets |
| `vendor/gamecode-088/code/{game,cgame,q3_ui}` | OA gamecode at `9e0f0c0`, the source of 0.8.8's release QVMs (built 2012-01-28) | **the Luau port follows this** |
| `vendor/gamecode/code/...` | OA gamecode master (post-0.8.8, 2025) | reference only; its behaviour differs (pmove, HUD, colours) |
| `vendor/ioq3/code/qcommon/cm_*.c`, `code/botlib/*.c` | ioquake3 (GPLv2) | collision model, AAS bot routing |
| `vendor/oa088/openarena-0.8.8/openarena.x86_64` | real OA | reference screenshots / feel checks |

`scripts/fetch-vendor.sh` re-creates `vendor/`.

## Units and coordinates

All game logic runs in **Quake units and Quake axes** (Z up), exactly as
the C code does, so the ported math stays verbatim. Conversion happens only
at the render/sound boundary (`src/shared/Units.luau`):

- 1 stud = 8 Quake units (player box 30x30x56 u = 3.75x3.75x7 studs).
- Quake (x, y, z) -> Roblox (x, z, -y) / 8.

## Repo layout

```
tools/oaconv/        Rust: pk3 + shader + BSP + MD3 + texture + sound converter
src/shared/          Luau port of bg_* (pmove, items, misc), cm (collision), Units
src/server/          Luau port of g_* (combat, weapons, items, movers, modes, bots)
src/client/          Luau port of cg_* (prediction, view, effects, sound, models)
src/ui/              HUD, scoreboard, menus (cg_draw + q3_ui look)
place/               MCP assembly scripts and the place manifest
build/               converter output (git-ignored, regenerable)
docs/                this file, per-workstream notes, parity checklist
```

## Key design decisions

1. **Own collision, no Roblox physics for players.** `cm_load/cm_trace/cm_patch`
   are ported to Luau (`src/shared/cm/`). Brushes, patch collision and the
   BSP tree are shipped as binary blobs (base64 `buffer`s in ModuleScripts,
   chunked under 190k chars each). Pmove, weapon traces and projectiles all
   use `CM_BoxTrace` semantics. Roblox parts are visual only
   (`CanCollide/CanQuery/CanTouch = false`).
2. **Networking = Q3 model.** The client sends usercmds over an
   UnreliableRemoteEvent and predicts with the same pmove. The server is
   authoritative at `sv_fps 20`-equivalent snapshots (Heartbeat-driven,
   pmove at the client's frame msec like Q3), and corrects the client on mismatch.
3. **Map rendering:** BSP surfaces (planar, patches tessellated, triangle
   soups) are grouped per shader class, and **lightmaps are baked into the
   textures**: diffuse x lightmap x overbright is written into per-map atlas
   pages (≤1024², Roblox's limit), with uploaded meshes ≤20k tris each. Shader
   classes that can't be baked (sky, additive, scrolling/animated, alpha-test,
   `deformVertexes`) become separate MeshParts that a client effect system
   animates (Texture offsets, Transparency, swapped TextureIds for animMap).
   Light grid -> per-entity lighting for models (sampled in Luau).
4. **Models (MD3)** are vertex-animated, which Roblox meshes can't do.
   Players, weapons and items are built at runtime as `EditableMesh` from
   frame data (quantised positions shipped as buffers), and the client
   updates the vertices for the current frame/lerp.
   Static md3s (map models, non-animated items) are uploaded as baked meshes.
   Tag-based attachment (tag_torso, tag_head, tag_weapon, tag_flash) follows
   cg_players.c.
5. **Sound:** ~540 effects packed into a few long audio atlases (silence
   gaps between clips) to fit Roblox's monthly audio upload quota, played
   via `Sound.PlaybackRegion`. The music tracks are uploaded as-is.
   `src/client/SoundAtlas.luau` maps an OA path like `sound/weapons/rocket/rocklf1a.wav` to (asset, start, len).
6. **Bots:** botlib's AAS routing is ported (`be_aas_*`) and reads the
   map's shipped `.aas` file, with `ai_dmq3`/`ai_dmnet` behaviour, characters
   from `botfiles/`, and chat lines.
7. **One place, all maps.** Maps live in ServerStorage as folders and are
   loaded on map change (`map`/vote/rotation as in OA's `g_*` cvars).
8. **Config = cvars.** A small cvar table (`g_gametype`, `fraglimit`,
   `timelimit`, `g_instagib`, ...) mirrors OA's so the gamecode ports cleanly.

## Game modes (all of OA 0.8.8)

FFA, Tourney, Single Player-style (bot match), TDM, CTF, 1FCTF, Overload,
Harvester, Elimination, CTF Elimination, Last Man Standing, Double
Domination, Domination, and the `g_instagib`/`g_rockets` modifiers.

## Pipeline

1. `tools/oaconv` reads `vendor/` -> `build/` (meshes as glTF, atlas/texture
   PNGs, sound atlases as OGG, collision/AAS/entity/model blobs as Luau
   modules, and `build/manifest.json` listing every upload).
2. Upload: rbx-native's `rbx_cloud` (`create_model_asset`, Decal upload, and
   Audio). This needs Chee's Open Cloud key, so Chee runs the command. Asset
   ids go to `build/assets.lock.json` and never get uploaded twice.
3. Assembly: `place/assemble.*` drives `rbxstudio --mcp` (execute_luau for
   instances, multi_edit for scripts from `src/`), then saves
   `place/openarena.rbxl`.
4. Verification: run the **real rbx-native build binary directly** (no
   Xephyr): Play through it, screen_capture via MCP, and compare against
   `openarena.x86_64` at the same map/viewpoint. `docs/PARITY.md` tracks it.

## Player roster

Players are drawn as their own Roblox avatar by default (R15, scaled to
OA's model height, OA's animations recreated; visual only, the box and
pmove stay OA's): `docs/client-notes.md`, "Roblox avatars". The OA models
below remain for bots, for players without an avatar and for anyone who
picks "OA models" in the player setup menu.

Only the player models in `tools/oaconv/roster.json` ship. It lists every
kept model with the reason it passed review, and every dropped one with the
reason it was dropped:

- dropped, female models: neko, angelyss (and `hnt`, her other skins'
  textures), sorceress, major, kyonshi (and the missionpack head
  `heads/kyonshi`), arachna and ayumi (bots, voices, shaders and sounds only:
  their models are in the mature pk3);
- dropped, a realistic bare human torso a nudity classifier could flag:
  merman, and beret's Headcrash skin;
- dropped, a bare male upper body: sarge's Classic skins (classic,
  classicred, classicblue, textures `grism/morphed*`) and beret's Macho skin
  (his bare-chested `skin1*` with no vest);
- shipped only toned (`toned`): beret's `skin1`, `skin1red` and `skin1blue`,
  which paint a bare muscled chest, back and shoulders under his vest. The
  copies in `assets/toned/` paint a plain t-shirt (grey, red, blue) over
  every bare torso texel, so his default, red and blue skins keep their face,
  arms and hands (`docs/toned-beret.jpg`); the pk3 originals never ship;
- kept: sarge (its textures live in `grism/`), assassin, beret, gargoyle,
  liz, penguin, sergei, skelebot, smarine, tony.

What uses it:

- `oaconv convert` drops the excluded paths from its VFS (`src/roster.rs`):
  no texture, icon, md3, glb, sound or shader of theirs, and no upload entry;
  its `models.json` skins name the `retexture` texture instead (no entry
  today). A `toned` path resolves only from the overlay (`assets/toned/`),
  never from a pk3. `oaconv upload` also skips such entries left in an older manifest. `oaconv
  tone` regenerates `assets/toned/`; of it, only beret's `skin1*` ships.
- `tools/roster.py` applies the same rules to the game's file packs
  (`place/assemble.py`, `scripts/client-dev-assets.py`,
  `tools/pack-botfiles.py`, the lune test hosts): shipped `.skin` files name
  the `retexture` texture in place of a dropped one, `scripts/bots.txt` moves
  the bots on a dropped skin of a kept model to that model (`bot_models`:
  Grism wears `sarge`, Morgan `beret`) and loses the 15 bots with a dropped
  model (so `addbot neko` prints OA's "Bot 'neko'
  not defined", and `bot_minplayers`, random bots and the menus only see the
  18 kept ones and Jiangshi, below), `botfiles/` loses the character files only they use, and
  `scripts/arenas.txt` / `*.arena` name a kept substitute (`arena_bots`):

  | dropped | substitute | dropped | substitute |
  |---|---|---|---|
  | Ayumi | Grunt | Sorceress | Sarge |
  | Jenna | Liz | Tanisha | Ghost |
  | Merman | Beret | Rai | Grism |
  | Headcrash | Andriy | Angelyss | Metalbot |
  | Major | Skelebot | Dark | Tony |
  | Nekoyss | Broadklin | Murielle | Assassin |
  | Arachna | Cyber-Garg | Kyonshi | Jiangshi |
  | Neko | Penguin | | |

  No arena names the same bot twice. q3_ui's team-game bot seeds (Kyonshi,
  Merman) take Sarge and Beret.

  Kyonshi was the boss of the Final arena (czest1tourney). Her model is
  dropped but her botfiles are text only, so the roster's `bots` adds
  Jiangshi, a new bot on her character, chat, item and weapon files and on
  beret's chrome Cooldude skin (a kept skin no other bot wears), and
  S_Marine gets a character of his own. Both characters are tuned copies in
  the botfiles overlay `assets/botfiles/`, which replaces or adds files under
  `botfiles/`: Jiangshi is the strongest bot in the game and S_Marine the
  second (roster.json `strongest`; docs/bots-notes.md, "Bot roster"). `tools/roster.py check` validates the
  config against the pk3s and fails on a dropped name hardcoded in `src/`, a
  shipped `.skin` naming a dropped texture, a `toned` path with no copy in
  `assets/toned/`, a bot wearing a dropped model or without its character
  file, or a `strongest` bot whose aim, accuracy, attack skill, view or
  reaction falls below another bot's at any skill level.
- The server (`ClientUserinfoChanged`) turns a dropped skin of a kept model
  into that model's default skin (`sarge/classic` -> `sarge`, `beret/macho`
  -> `beret`), and a `model`/`headmodel` with no shipped skin file into
  `sarge`, OA's default, the model the cgame falls back to. The team defaults are `sarge` in this port; `sergei` (0.8.8's) is
  kept too.
- `place/assemble.py --players` refuses a dropped model.

## Multiplayer on Roblox servers

Roblox has no LAN and no master server, so OA's multiplayer menus are
backed by Roblox's own servers. Every Roblox server of the experience is
one OA server (the game server already runs inside it); what it is decides
how it starts (`src/server/sv/servers_roblox.luau`, called by the boot
script):

| kind | made by | starts with | listed |
|---|---|---|---|
| public | Roblox matchmaking (joining the experience) | the dedicated-style rotation in `src/server/sv/servers_config.luau`: FFA / TDM / CTF through q3's `nextmap` chain (`set d1 "...; set nextmap vstr d2"`), `bot_minplayers 4`, maps the place lacks skipped | yes |
| host | Start Server (`TeleportService:ReserveServer`) | the creator's settings, as the cvars ServerOptions_Start sets, then `map` and the `addbot` lines | if "Public Server" was on, else by code only |
| sp | a single player arena (`spmap`) | `g_spSkill N; spmap <map>`: that player alone | never |
| private | a reserved server whose settings were lost (or expired after 1 h) | the rotation | no |
| studio | Studio, rbx-native's runtime, lune (no TeleportService / MemoryStore) | the place's `Startup` attribute or the first map: the single-server behaviour of before | - |

A public server still uses the `Startup` attribute when the place has one
(dev playtests); `assemble.py --startup ""` builds a place that runs the
rotation.

**Registry.** A `MemoryStoreService` SortedMap (`OAServers`), key = the
server's join code, value = JobId, PlaceId, the access code of a reserved
server, hostname, map, gametype, clients, bots, maxclients, reserved,
public. Every server but SP ones writes its entry every 10 s with a 30 s
expiry (a crashed server drops out by itself) and removes it in
`BindToClose` (`servers_registry.luau`). A listing pages `GetRangeAsync`
(200 a page, 2 pages at most) and is cached 5 s for every player of that
server. MemoryStore's quota is 1000 + 100 x concurrent users request units
a minute for the experience; a server writes 6 a minute. Any failed call
backs the registry off (2 s doubling to 60 s, the last good listing is
served meanwhile). Access codes never leave the servers.

**Join codes.** Six characters from a 32-letter alphabet without 0/O/1/I,
the first a digit (q3_ui's favorites and Specify want an address whose
first character is numeric), hashed (FNV-1a) from the JobId or
PrivateServerId
(`src/shared/net/servers.luau`). The in-game SERVER INFO menu shows it as
`sv_code`, and `cl_currentServerAddress` is set to it so "Add to
favorites" works. The code is the browser's server "address".

**Browser.** `ui_servers2.c` and `ui_specifyserver.c` are ported; their
engine side (`localservers`, `globalservers`, `ping`, `connect <address>`
and the `LAN_*` traps) is `src/client/sys/LAN.luau`, talking to the
`ReplicatedStorage.OANet.Servers` RemoteFunction (rate limited per player).
The source list maps to:

The server you are on is always in the list (first, marked by its
measured ping), listed or not.

- **Internet**: every public server (sv_master1 is set; Internet(2)-(5)
  have no master, so ioq3's skip lands on Favorites, as in OA). The
  gametype filter and "show full / show empty" are the master protocol's
  words (`ffa`, `ctf`, ..., `full`, `empty`).
- **Local**: this server plus the public servers friends are on
  (`Player:GetFriendsOnline`, matched by JobId). A region would need an
  HTTP geo lookup (an experience setting), so friends it is.
- **Favorites**: q3_ui's `server1..16` cvars, mirrored to a DataStore key
  per user (`OAFavorites`, `u<UserId>`), loaded at start; a change is
  written back at most every 30 s and only while
  `GetRequestBudgetForRequestType` is above 10.
- **Specify**: the address field takes a join code (the port field is
  ignored). A private server is reachable this way only. When nobody is
  in it the server is gone (Roblox closes an empty reserved server), so
  the code is looked up in `OAReserved` and the same reserved server
  starts again with its settings. SP records are never joinable.

**Ping.** A Roblox client can't reach another server, so no ping can be
measured: the server you are on shows `Player:GetNetworkPing` (a round
trip), every other one shows `?` (sorted after known pings, never dropped
as slow). The netnames column says `RBX`.

**Teleports.** Join: `TeleportAsync` with `TeleportOptions.ServerInstanceId`
(public) or `ReservedServerAccessCode` (reserved). Start Server and SP:
the server validates the request (`servers.validateSpec`: gametype, a map
the place has, the allowed cvars clamped, bot names, at most 11 bots),
filters the hostname through `TextService`, reserves, writes the settings
to the `OAReserved` SortedMap under the server's join code (1 h,
renewed every time the server starts), and
teleports the player. The reserved server reads them back from there on
arrival (trusted, written by a server); only if that read fails does it
take its first player's TeleportData, checked the same way. The menus
are unchanged: `map`/`spmap` capture the cvars the menu just set and the
`addbot`/`team` lines it queues behind them (`LAN.Map`). TeleportData
carries the player's archived cvars (name, model, colours, SP progress
are client cvars and a teleport starts a fresh client) and the team; the
client checks it (`servers.validateArrival`), applies it and connects
straight away.

**Host.** The creator of a host or SP server is its host: `sv_running 1`
on their client enables q3_ui's ADD BOTS / REMOVE BOTS / RESTART ARENA,
and `addbot`, `clientkick`, `kick`, `map_restart` and `rcon <cmd>` go to
the server's rcon, limited to the commands and cvars those menus and a
server admin need (no `say`: text other players see must pass Roblox's
filter; `sv_hostname` is re-filtered when it changes). Start Server from
the host restarts their server with the new settings, as OA's listen
server does, instead of reserving another. Apply and rcon text goes
through `Cbuf_AddText` and runs in the next server frame, never inside
the RemoteFunction handler.

**Experience settings.** None changed; MemoryStore, DataStore and
TeleportService need none, but teleports need a published place (the
play sandbox is one).

**Testing it live.** rbx-native's Play publishes the place to the
sandbox and runs one Sober client, but ends the session ("Play ended: you
left the game", `StopReason::PlayerLeft`) as soon as that player leaves
the first server, which a teleport is, and kills Sober. So the live run
used Play only to publish, then started Sober alone on the place
(`flatpak run org.vinegarhq.Sober "roblox://placeId=<id>"`), driven by a
scratch LocalScript that walks the menus and prints markers to Sober's
output. One account is in one server at a time and the server it leaves
closes, so two servers alive in the registry together needs a second
account; the registry paging and expiry are covered by the lune tests.

## Content notes for Roblox

- OA has blood and gibs (`cg_gibs`, `com_blood`). These are kept behind
  the same cvars. Chee decides the maturity questionnaire answers at publish.
- EditableMesh in a published game needs the owner to be ID-verified.
