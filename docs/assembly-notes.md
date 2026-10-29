# Assembly notes: the place, built through rbx-native's MCP server

How `place/openarena.rbxl` is put together, how asset ids are referenced,
what the playtests in rbx-native showed, and the gaps found on the way.

## Building the place

    tools/pack-botfiles.py                      # build/botfiles/luau
    oaconv convert --out build ...              # build/ (maps, md3, sounds, manifest)
    place/resolve_ids.py                        # upload lock -> place/asset-ids.json
    place/assemble.py --launch --maps all       # -> place/openarena.rbxl

`assemble.py` starts `rbxstudio` on the place (an empty place made with lune
when the file is missing) with `XDG_CONFIG_HOME`, `XDG_CACHE_HOME` and
`XDG_STATE_HOME` under `--home`, turns the `mcp-server` beta on there
(`<config>/rbx-native/beta.json`), and drives `rbxstudio --mcp` over stdio
JSON-RPC. Every instance comes from an MCP tool call:

| what | where in the place | MCP tool |
|---|---|---|
| client, ui and shared modules from `src/` | `ReplicatedStorage.OA.{client,ui,shared}` | `multi_edit` (folders first with `execute_luau`) |
| server and shared modules | `ServerScriptService.OA.{server,shared}` | `multi_edit` |
| scripts whose name differs from a sibling only in case (`q/Consts` next to `q/consts`, `shared/BG` next to `shared/bg`, ...) | same | `execute_luau` (see gaps) |
| server boot `place/boot/Boot.server.luau` | `ServerScriptService.OA.Boot` (Script, attribute `Startup` = console text run once) | `multi_edit` |
| client boot `src/client/OAClient.client.luau` | `StarterPlayer.StarterPlayerScripts.OAClient` (LocalScript) | `multi_edit` |
| remotes | `ReplicatedStorage.OANet.Reliable` (RemoteEvent), `.Unreliable` (UnreliableRemoteEvent) | `execute_luau` |
| text files of the pk3s (shaders, menus, arenas, bot scripts...) | `ReplicatedStorage.OA.client.sys.Files` + parts | `execute_luau` (<= 900 KB of source per call) |
| asset index (image ids, sizes, md3 meshes, static bundles, sky, music, sound atlas id map from `build/SoundIndex.luau`) | `ReplicatedStorage.OA.client.sys.AssetIndex` + parts | `execute_luau` |
| md3 models (vertex blobs) | `ReplicatedStorage.OA.client.sys.Models.*` | `execute_luau` |
| per map: `Checksum` and `LightGrid` attributes, `Data` = Collision/Entities/LightGrid/Aas blob modules | `ServerStorage.OAMaps.<map>` | `execute_luau` |
| per map: the uploaded map Model's MeshParts, placed by the manifest's centers and sizes, TextureID = the atlas page's image id | `ServerStorage.OAMaps.<map>.Meshes` | `insert_asset`, then `execute_luau` |
| botfiles blob | `ServerStorage.OABotfiles.Botfiles` + chunks | `execute_luau` |
| `Workspace.Map` (current map's meshes, filled at map load), `Players.CharacterAutoLoads = false`, flat Lighting (ambient white, brightness 0, no shadows: the lightmaps are baked into the atlas pages), `Technology = Compatibility` | | `execute_luau` |
| checks | | `inspect_instance`, `search_game_tree` |

The server boot copies the current map's client half (Collision, Entities,
LightGrid) to `ReplicatedStorage.OAMap.<map>` and its meshes to
`Workspace.Map` on every map load; the client boot hooks those into CM,
LightGrid and WorldFx, and the transport (`src/client/sys/Transport.luau`,
the client side of `docs/formats/net.md`) into the cgame.

The editor has no save tool: `assemble.py` sends Ctrl+S to the editor window
(titled after the .rbxl) with XSendEvent, which neither moves the pointer
nor takes focus, and waits for the file's mtime.

Sizes: all 72 maps with the default player list
(`sarge,major,tony,penguin,beret,assassin,liz`) give a **92.9 MB** place
(72 maps, 2339 MeshParts, 2057 ModuleScripts after a lune round trip, built
in 187 s). The playtest place (`--maps oa_dm1,oa_ctf2 --players sarge`) is
6.1 MB, built in 32 s.

## Asset ids

`place/resolve_ids.py` reads the upload lock (`conv/build/assets.lock.json`,
read only) and asks Open Cloud (key from the keyring entry rbx-native keeps,
never printed or written) what each id is:

- **Images** were uploaded as `Decal`: the id in the lock is a Decal
  (asset-delivery `assetTypeId` 13) whose content is an XML Decal with
  `Texture = http://www.roblox.com/asset/?id=<image>`. `<image>` is a
  separate `Image` asset (`assetTypeId` 1). `MeshPart.TextureID`,
  `ImageLabel.Image` and the client's AssetIndex use the **image** id.
- **Map meshes** (`.glb`) were uploaded as `Model` (`assetTypeId` 10): a
  binary .rbxm with one Model per glTF node holding one MeshPart named after
  the manifest mesh, `MeshContent = rbxassetid://<mesh>`, no texture. The
  importer turns the scene 180 degrees about Y: a part sits at (-x, y, -z)
  of the manifest's center. The place inserts the Model (`insert_asset`)
  and re-places each part at the manifest center with
  `CFrame.new(center) * CFrame.Angles(0, pi, 0)`.
- **Static md3 bundles** (map models): the AssetIndex keys them
  `"<path_no_ext with / -> _>#<surface>"` -> `{id = mesh id, c = center}`;
  R3D offsets the part by the center, turned like the map meshes.
- **Audio**: the lock id is the Sound id.

Images still uploading or held for review (`tools/oaconv/upload-hold.txt`:
gibs, blood and flesh textures, player and head skins) stay out of the index
with only their size: the 2D renderer draws OA's white default for them and
the world keeps white parts. Re-running `resolve_ids.py` then `assemble.py`
picks them up.

Converter check: re-running `oaconv convert` into this worktree's `build/`
gave the same sha256 as `conv/build`'s manifest for every upload except
five: `images/textures/cosmo_sfx/decal2.png` and
`images/textures/symbols/redteam.png` (several source files - .tga, .jpg,
.pcx in different pk3s - map to one output path and the winner is not
deterministic) and `sound/sfx_00.ogg`, `sfx_01.ogg`, `sfx_02.ogg` (same
audio, the Ogg stream serial and page CRCs differ run to run). Nothing was
uploaded from here.

## Playtests in rbx-native

`start_stop_play` publishes a copy of the place (with rbx-native's probe
scripts added) over the play sandbox place configured in rbx-native's
settings, then starts Sober - the real Roblox client - and embeds it in the
editor. So the game runs on Roblox's servers and client; only the editor
around it is rbx-native. Steps used:

    assemble.py --launch --maps oa_dm1,oa_ctf2 --players sarge \
        --place place/openarena-play.rbxl --startup "<console text>"
    rbxstudio place/openarena-play.rbxl          # MCP beta on, isolated XDG config
    start_stop_play {is_start: true}
    user_keyboard_input / user_mouse_input / screen_capture / get_console_output
    execute_luau {datamodel_type: "Client"}      # read cg.predictedPlayerState, run console commands

FFA (`bot_enable 1; g_gametype 0; fraglimit 20; timelimit 10; map oa_dm1;
addbot sarge 2; addbot major 2; addbot tony 2`):

- main menu, single player level select and first connect draw
  (`docs/parity/play/menu_main.png`, `menu_sp.png`, `first_connect.png`);
- Multiplayer -> the local server: loading screen with the map's item icons
  (`play/loading.png`), then in game with the HUD (health, ammo, armor,
  scores, pickup line) and the first-person machinegun
  (`play/dm1_respawn.png`);
- movement: holding forward moved the predicted origin about 343 units in a
  second along the view yaw; walking over a box picked up Bullets (ammo
  100 -> 150, `play/dm1_pickup.png`);
- shooting: holding fire took ammo 124 -> 67 with brass, impact marks and
  the crosshair name of the bot being shot (`play/dm1_firing.png`);
- bots fight: the server log shows the kill feed, for example
  `Kill: 2 0 7: Tony killed Sarge by MOD_ROCKET_SPLASH`,
  `Kill: 1 2 7: Major killed Tony by MOD_ROCKET_SPLASH`,
  `Kill: 2 3 7: Tony killed UnnamedPlayer by MOD_ROCKET_SPLASH`;
- scoreboard: shown on death with the bots' scores
  (`play/dm1_fragged_scores.png`).

CTF (`g_gametype 4; capturelimit 8; devmap oa_ctf2; addbot sarge 2 red;
addbot major 2 blue; addbot tony 2 blue`): joins as spectator
(`play/ctf2_spectator.png`, the sky box draws), `team red` puts the player
at a red spawn with the CTF HUD (flag status, team scores) and Sarge's team
order "Yo, UnnamedPlayer get the flag!" (`play/ctf2_red.png`). Side by side
with OpenArena 0.8.8 (ioquake3 from vendor/ioq3, same QVMs and data,
`scripts/oa-ref.sh`, `setviewpos` to the same origin and yaw):
`docs/parity/ctf2_red_side.png`, and the same for the oa_dm1 spawn
corridor: `docs/parity/dm1_spawn_side.png` (ours left; a bot shows only
as its crosshair name and shadow). Once both maps' atlas pages had ids the
world, lightmaps and sky match the reference closely. In CTF the bots
traded team orders ("Their flag shall be ours.", "Yo, Major get the flag!"),
the red flag was taken and returned, and they fell into the void often
(`<world> killed Sarge by MOD_TRIGGER_HURT`, 9 such deaths in about a
minute), which still needs a comparison with OA's bots on that map.

Headless, every map was also run through the server with 4 bots for 60 game
seconds from the same Collision/Entities/Aas blobs the place carries
(`tests/bots/sim.luau`, now able to load maps without BSPs):
`docs/parity/sweep.txt`.

## Gaps

What does not reach parity, with the evidence. None of these is papered
over in the place.

### Roblox (the sandbox experience)

- **EditableMesh is refused**: every `AssetService:CreateEditableMesh`
  mesh in the play sandbox fails on use with "EditableMesh is not
  accessible. Go to the Security Tab in Experience Settings to enable this
  API." (client console). Player models, animated md3s and deforming
  shaders build EditableMeshes, so **players and bots are invisible** and
  those shaders draw static. The client now catches this once
  (`R3D.noEditableMesh`, `WorldFx` `editableRefused`) instead of failing
  every frame. The fix is the experience setting, which was not touched.
- Impact marks (bullet holes, scorches) draw as dark quads: the multiplicative
  blend of OA's mark shaders has no Roblox equivalent (`play/dm1_firing.png`).

### rbx-native

- **No save tool** over MCP: saving needs Ctrl+S sent to the editor window
  (XSendEvent).
- **`multi_edit` resolves paths case-insensitively** and refuses a script
  whose name differs from a sibling only in case; those go through
  `execute_luau`.
- **`execute_luau` in Edit cannot `require` a module that uses
  require-by-string** (`require("./x")`): "Attempted to call require with
  invalid argument(s)". The modules work in the playtest (real Roblox), so
  the place is only checked structurally in Edit.
- **`InitialSize` is not scriptable** in Edit, and `MeshId` is writable in
  Edit where Studio refuses it; the place sets `Size` on inserted parts and
  never writes `MeshId`.
- **Play publish limit**: rbx-native refuses to start a playtest when the
  place is over 10 MiB (`MAX_PUBLISH_BYTES` in `crates/rbx_play/src/inject.rs`,
  "Roblox's limit for a place published through Open Cloud"). Roblox's
  documentation gives 100 MB for places; the 10 MiB figure looks stale.
  The playtest place therefore carries two maps and one player model.
- **`user_keyboard_input` reaches the embedded client only while the editor's
  toplevel is the active window**, and keys go through the desktop's layout
  (AZERTY here: forward is sent as `Z`, strafe left as `Q`). The harness sets
  `_NET_ACTIVE_WINDOW` first.
- **`user_mouse_input` forgets the pointer position between calls**: a
  button step needs a `moveTo` in the same call.
- **`character_navigation` needs a Humanoid character**; OpenArena players
  are not Roblox characters (`CharacterAutoLoads = false`), so it does not
  apply.
- `get_console_output` keeps the newest 20000 characters only.
- The first `start_stop_play` after a launch sometimes answers "No Roblox
  client window appeared in time"; a second start works.
- `XDG_DATA_HOME` must stay the user's: Sober is a user flatpak and is not
  found otherwise.
- UIScale and `Folder:WaitForChild` are missing in rbx-native's own Luau
  runtime (known); the playtest runs in real Roblox, so they do not affect it.

### This port (found by the assembly)

- `oa_koth1` FFA: the bot router crashed,
  `src/server/bot/botlib/be_aas_route_2:270: attempt to perform arithmetic
  (add) on number and nil` (`lune run tests/bots/sim.luau oa_koth1 4 60 0`).
  Area 205 has 266 reversed links and `AAS_UpdateAreaRoutingCache` reads
  its 128-entry `startareatraveltimes` once per link (fixed, see
  `docs/bots-notes.md`).
- First connect / FirstConnect menu: `Menu_AddItem` read fields of items
  built as `{ generic = {} }` (fixed, `ui_qmenu2.luau`), and `rate_items`
  was a local where ui_firstconnect needs the shared table (fixed).
- The client sent no usercmds while PRIMED, so it never became ACTIVE; the
  cgame's area mask was a buffer where a 0-based table is read; the map name
  arrives as `maps/<map>.bsp` (all fixed). The engine's userinfo cvars
  (model, colors, rate, snaps...) were not registered, so the server saw an
  empty model (fixed in `Client.luau`).
- Menu backgrounds baked by the converter (`baked2d`) are not in the upload
  set: menus show OA's default image there.

## Publishing

Nothing was published and no place or universe was created (playtests only
overwrite the configured play sandbox place, as every rbx-native playtest
does). To publish:

- **Size**: 92.9 MB for all maps is under Roblox's 100 MB place limit but
  close, and that is with seven player models; every extra player model adds
  about 1.5 MB (14.9 MB with seven against 6.1 MB with one, two maps). Splitting into places per map pack (TeleportService) or
  loading map data from packages would leave room.
- **EditableMesh**: enable it in the experience's Security settings
  (check Roblox's current eligibility rules for EditableMesh in published
  experiences first).
- **Maturity questionnaire**: realistic-looking violence with weapons;
  blood and gibs exist but sit behind `com_blood` / `cg_gibs`; the held
  textures (gibs, blood, flesh, pentagram) await moderation and stay out
  until approved.
- **Held assets**: 268 files in `tools/oaconv/upload-hold.txt`; the place
  references none of them until they have ids.
- Audio: sound atlases upload last; until they have ids the game is silent.
