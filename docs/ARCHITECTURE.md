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

## Content notes for Roblox

- OA has blood and gibs (`cg_gibs`, `com_blood`). These are kept behind
  the same cvars. Chee decides the maturity questionnaire answers at publish.
- EditableMesh in a published game needs the owner to be ID-verified.
