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

## Content notes for Roblox

- OA has blood and gibs (`cg_gibs`, `com_blood`). These are kept behind
  the same cvars. Chee decides the maturity questionnaire answers at publish.
- EditableMesh in a published game needs the owner to be ID-verified.
