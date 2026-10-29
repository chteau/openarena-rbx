# Client notes

How the OpenArena cgame and q3_ui C code became Luau, and how every engine
call lands on Roblox. `docs/ARCHITECTURE.md` is the contract above this.

## Layout

```
src/client/q/Consts.luau      every #define/enum of q_shared.h, surfaceflags.h, tr_types.h,
                              bg_public.h, cg_public.h, cg_local.h, keycodes.h, ui_local.h, challenges.h
src/client/q/Types.luau       a constructor per C struct (zeroed, 0-based arrays), copy/reset helpers
src/client/q/Q.luau           q_shared.c + q_math.c (vectors, angles, strings, info strings, colors)
src/client/adapters/BG.luau   bg_* used by the client: src/shared when it exists, a local fallback otherwise
src/client/adapters/CM.luau   collision (trap_CM_*): src/shared/cm when it exists, empty world otherwise
src/client/sys/*.luau         the "engine": cvars, commands, keys, input -> usercmd, net, renderer, sound
src/client/sys/Trap.luau      trap_* for cgame and ui, on top of sys/*
src/client/cg/G.luau          cgame globals + function namespace
src/client/cg/cg_*.luau       the cgame port, one module per C file (big files split in parts)
src/ui/Screen.luau            the 640x480 virtual screen math (cgame and q3_ui)
src/ui/q3/U.luau              q3_ui globals + function namespace
src/ui/q3/ui_*.luau           the q3_ui port
tests/                        lune tests (tests/run.luau runs them all)
```

## Porting rules (every ported file follows these)

1. **Header.** Keep the C file's GPL header comment verbatim (as a `--[[ ]]`
   block), then one line:
   `-- Luau port of code/<dir>/<file>.c (OpenArena 0.8.8, gamecode 9e0f0c0).`
2. **Non-MISSIONPACK build.** Port the `#ifndef MISSIONPACK` / `#else` side
   for baseoa, drop `#ifdef MISSIONPACK` code. Drop `Q3_VM`-only code.
3. **Modules and names.** Each module is a ModuleScript. Requires are relative
   to `script` (`require(script.Parent.G)`), never by string.
   - cgame: every non-static C global (variables *and* functions) lives in the
     shared namespace `G` (`src/client/cg/G.luau`) under its C name:
     `cg`, `cgs`, `cg_entities`, `cg_weapons`, `cg_items`, the vmCvar_t
     globals (`G.cg_fov.value`), and `function G.CG_DrawActiveFrame(...)`.
     Call other files' functions through `G` at call time (`G.CG_Foo(x)`),
     never cache them at load (load order is free, there are no cyclic requires).
   - `static` C functions/variables become `local` in their module.
   - q3_ui: the same with `U` (`src/ui/q3/U.luau`): `U.uis`, `U.UI_DrawString`.
   - Constants: `local C = require(.../q/Consts)` then `C.WP_ROCKET_LAUNCHER`.
   - q_shared/q_math: `local Q = require(.../q/Q)` then `Q.VectorMA(...)`,
     `Q.AngleVectors(...)`, `Q.colorWhite`, `Q.va(...)`.
   - Structs: `local T = require(.../q/Types)` then `T.refEntity_t()`.
   - Engine calls: `local trap = require(.../sys/Trap)`; `trap_X(...)` becomes
     `trap.X(...)` (`trap.R_DrawStretchPic`, `trap.S_StartSound`).
   - bg_*: `local BG = require(.../adapters/BG)`; `BG.BG_EvaluateTrajectory`,
     `BG.bg_itemlist`, `BG.Pmove`.
   - A module returns its own table only when the spec asks for it; cgame/ui
     modules register into `G`/`U` and end with `return G` / `return U`
     (Roblox refuses a module that returns nothing; the harness checks it).
4. **Arrays stay 0-based.** `vec3_t` is `{[0]=x, [1]=y, [2]=z}` (use
   `Q.vec3(x,y,z)`), `vec4_t`/colors the same, every C array keeps its C
   indices (`cg_entities[0]`..). `for (i = 0; i < n; i++)` is `for i = 0, n - 1 do`.
   Never use `#` or `ipairs` on them. Constants `C.PITCH = 0, C.YAW = 1, C.ROLL = 2`.
5. **Truthiness.** 0 is true in Luau. A C test on an int/float (`if (x)`,
   `!x`, `x && y`, `while (n--)`) becomes an explicit comparison
   (`if x ~= 0`). `qboolean` is a Luau boolean (`qtrue`/`qfalse` ->
   `true`/`false`); when C mixes it with ints, convert with `Q.b2i`/`Q.i2b`.
   Strings: `if (s[0])` -> `if s ~= ""`. Pointers: `if (p)` -> `if p ~= nil`.
6. **Integers.** `(int)x` -> `Q.int(x)` (truncates toward zero). Int `/` ->
   `Q.idiv(a, b)` (truncates); `%` with possibly negative ints -> `math.fmod`.
   Bit ops -> `bit32.band/bor/bxor/bnot/lshift/rshift` (`bit32.arshift` for
   signed `>>`). `rand()` -> `Q.rand()` (0..0x7fff), `random()` -> `Q.random()`,
   `crandom()` -> `Q.crandom()`.
7. **Pointers and out-params.**
   - Struct pointers are table references. `&cg_entities[n]` -> `G.cg_entities[n]`.
   - `float *`/`int *` scalar out-params become extra return values
     (`x, y, w, h = G.CG_AdjustFrom640(x, y, w, h)`).
   - `vec3_t`/array out-params are mutated in place, exactly like C.
   - `char *buf, int size` out-params return a string
     (`trap.Cvar_VariableStringBuffer(name)` returns the value).
   - Struct assignment / `memcpy` -> `T.copy(src)` (deep copy) or
     `T.assign(dst, src)` (copies into an existing table, keeps references).
   - `memset(&s, 0, sizeof(s))` -> `T.reset(s, T.centity_t)` (or a fresh `T.x()`
     when no one else holds the reference).
8. **Strings.** `char[]` -> Luau strings. `Q_strncpyz(d, s, n)` -> assignment
   (truncate with `string.sub` when the limit matters). `va`/`Com_sprintf` ->
   `Q.va(fmt, ...)` (C format: `%i` is accepted). `strlen` -> `#s`,
   `s[i]` -> `string.byte(s, i + 1)`, `Q_stricmp(a,b) == 0` -> `Q.stricmp(a, b) == 0`.
   Colour escapes (`^1`) stay as they are.
9. **Floats.** Luau numbers are doubles; keep C's arithmetic order, don't
   "simplify" expressions. `M_PI` is `math.pi`. `sin/cos/atan2/sqrt/fabs/floor/ceil` -> `math.*`.
10. **Engine handles.** `qhandle_t`/`sfxHandle_t` are integers from
    `trap.R_RegisterShader`/`trap.S_RegisterSound`; 0 means "none".
11. **No Roblox API in ported files.** Only `sys/*` touches Roblox. A ported
    file that needs something the engine doesn't have adds a `trap.` call
    named after the C syscall, never a Roblox call.
12. **Comments.** Keep the C comments that explain behaviour. Don't add
    "ported from" notes per function.

13. **Split files.** A C file too big for one module is split into parts
    (`cg_weapons.luau`, `cg_weapons2.luau`, ...). In a split file *every*
    function and file-scope variable (static or not) is registered in `G`/`U`
    under its C name, so the parts can reach each other; each part says at
    the top which C line range it covers. In an unsplit file, statics are
    `local` (forward-declare with `local Foo` when C calls one before its
    definition).
14. **Globals defined in a file** (cvars, tables) are created by the module
    that defines them in C, at load: `G.cg_fov = T.vmCvar_t()` in cg_main,
    `G.cg_weapons` arrays live in `G.luau`. Data tables (`cvarTable`,
    `gametype names`, menu item arrays) stay with their C file.
15. **Engine entry points.** C `vmMain` is ported as `G.vmMain(command, ...)`
    (cgame) / `U.vmMain(command, ...)` (q3_ui) dispatching to the same
    functions, which are also callable directly (`G.CG_Init`,
    `G.CG_DrawActiveFrame`, `U.UI_Init`, `U.UI_Refresh`, `U.UI_KeyEvent`, ...).
16. **gameState_t** is `{configstrings = {[i] = string}}` (0-based, missing
    entries are `""`), not the C offset/data pair. `CG_ConfigString(i)`
    returns `cgs.gameState.configstrings[i] or ""`.
17. **q3_ui menu items.** An item struct (`menutext_s`, `menubitmap_s`, ...)
    is a table with its `menucommon_s` in `.generic`, as in C. C code that
    casts an item pointer to `menucommon_s*` reads `item.generic` in Luau:
    `((menucommon_s*)ptr)->flags` -> `ptr.generic.flags`. `menuframework_s.items`
    is a 0-based array of item tables. Callbacks keep C's
    `(void *ptr, int event)` and receive the item table.

## Source revision: OpenArena 0.8.8

The port follows `vendor/gamecode-088` (gamecode `9e0f0c0`, 2012-01-28), the
source of the QVMs in 0.8.8's `pak6-patch088.pk3`. It was first ported from
`vendor/gamecode` (OA master, 2025) and then aligned file by file with
`git -C vendor/gamecode diff -w 9e0f0c0 HEAD -- code/cgame code/q3_ui`
(and the headers, `q_shared.c`, `bg_misc.c`). `cg_marks.c` is split since
0.8.8 carries Q3's particle system in it: `cg_marks.luau` (mark polys),
`cg_marks2.luau` / `cg_marks3.luau` (particles).

Master-only things removed:

- cgame cvars: `cg_bob`, `cg_bobmodel`, `cg_kickScale`, `cg_viewnudge`,
  `cg_muzzleflashStyle`, `cg_alternateShell`, `cg_obituaryOutput`,
  `cg_deathcam`, `cg_cameramode`, `cg_cameraEyes*`, `cg_modelEyes_*`,
  `cg_leiDebug`, `cg_leiChibi`, `cg_leiWidescreen`, `g_enableQ`,
  `g_enableFS`; `cg_hitSound` is 0.8.8's `cg_hitsound` again and
  `com_cameraMode` (`cg_cameraMode`) is back.
- cgame features: frag messages (`CG_DrawFragMessage*`, `fragInfo_t`,
  `FRAGMSG_*`, the frag icon shaders), eye models and eye-file parsing
  (`CG_ParseEyesFile`, `CG_Draw3DModelEyes`, `eyepos`, `head` lerp frames),
  floating names / sprites over the world, the SCRIPTHUD loading screen
  (`CG_DrawLoadingScreen`, `CG_Update*Fraction`), the countdown timer and
  possession string, `CG_BestWeapon_f`, `CG_GetCVar`, the muzzle flash
  styles (`flashModel_type*`, `MuzzleFlashStyleQ1`), lazy weapon bob,
  `onepiece` (`g_enableFS`) models, the engine particle syscalls
  (`trap_R_LFX_ParticleEffect`, `trap_R_GetViewPosition`) and the `LFX_*`
  effects; 0.8.8's own particles (`CG_ParticleExplosion`, `CG_LeiSparks`,
  `CG_LeiPuff`, ... behind `cg_leiEnhancement`) are back in their place.
- Layout and data: the score box starts at `480 - ICON_SIZE` (master: 472),
  `CG_DrawOldTourneyScoreboard`, `NUM_CROSSHAIRS 99`, default team model
  `sergei` / head `*sergei`, team names "Vim supporters" / "Emacs
  supporters", the extra footstep and impact sounds (`FOOTSTEP_SNOW`..,
  `IMPACTSOUND_GLASS`.., `SURF_SNOW`.., `EV_FOOTSTEP_WOOD`..), the
  Possession gametype (`GT_POSSESSION`), map-info gametype support.
- q3_ui: `UI_DrawBackgroundPic` (menu backgrounds are a 640x480 handle pic
  again, so they pillarbox), `ui_browserHidePrivate`,
  `ui_pos_scorelimit`/`ui_pos_timelimit`, the 2018 copyright line, the
  `fixedlegs`/`fixedtorso` UI player options, the text-effect helpers,
  and the vote, start-server, controls, video, player and challenges menus
  as master changed them. `ui_options.c` (0.8.8 only) is not ported:
  nothing in 0.8.8 calls `UI_SystemConfigMenu`.

Kept although no C source has them: the engine layer (`sys/*`,
`ui_roblox.luau`) and the opt-in `cg_wideScreenHud` (default 0).

The release `ui.qvm` is not byte-for-byte `9e0f0c0`: it draws `^70.8.8` in
the main menu's corner where the source says `^7OAX` (ported as the QVM
draws it), and it lacks the `ui_writemappools` command (kept, harmless).

## Units and axes

Everything in `cg/`, `ui/` and `sys/Trap` stays in Quake units and axes (Z up).
`sys/Units.luau` converts at the Roblox boundary: 1 stud = 8 u,
Quake (x, y, z) -> Roblox (x, z, -y) / 8. Angles go through `AnglesToAxis` and
the axis is converted, never the Euler angles.

## Engine mapping (trap_* -> Roblox)

`sys/Trap.luau` is the whole cgame + q3_ui syscall table; argument changes
(out-params, buffers) follow rule 7. Where each family lands:

| trap family | engine module | Roblox side |
|---|---|---|
| Print / Error / Milliseconds / RealTime | Console, Clock | `print`, `os.clock`/`os.date` |
| Cvar_* , Argc/Argv/Args, AddCommand, SendConsoleCommand, Cmd_ExecuteText | Cvar, Cmd | pure Luau (cvar table, command buffer with `wait`) |
| Key_* , catchers, bindings | Keys | `UserInputService` events via `Client` (KeyCode -> Q3 keynum table) |
| GetUserCmd / GetCurrentCmdNumber / SetUserCmdValue | Input (cl_input) | mouse delta from `InputChanged`, `MouseBehavior.LockCenter` |
| GetGameState / GetSnapshot / GetServerCommand / GetCurrentSnapshotNumber / SendClientCommand | Net | `Net.Receive*` from the transport, `Net.transport` out |
| CM_* | adapters/CM | feat/game's `src/shared/Collision` when present |
| R_RegisterShader/Model/Skin, R_LerpTag, R_ModelBounds, R_RemapShader | Assets, Md3, ShaderParse | asset index + FS pack |
| R_SetColor / R_DrawStretchPic | R2D | pooled `ImageLabel`s, one per shader stage |
| R_ClearScene / AddRefEntity / AddPoly / AddLight / RenderScene | R3D | `EditableMesh` MeshParts, `BillboardGui`, `Beam`, decal parts, `PointLight`, `Camera` (Scriptable); `RDF_NOWORLDMODEL` scenes in a `ViewportFrame` |
| R_LoadWorldMap | WorldFx | animates the map's non-baked parts, `Lighting.Sky`, fog |
| S_* | Snd | `Sound` with `PlaybackRegion` into the atlases, `Attachment` emitters, `SoundService:SetListener` |
| FS_* | FS | read-only pack (`Files` module) + in-memory writes |
| UpdateScreen | Client.UpdateScreen | redraws; see "Walls" |
| CIN_*, PC_*, LAN_*, CD key, camera paths, GetEntityToken | Trap | inert (see "Walls") |

### 2D (R2D)

- Screen math lives in `src/ui/Screen.luau` only. The cgame HUD stretches
  to the screen like OA 0.8.8 (`xscale = w/640`, no bias); `cg_wideScreenHud 1`
  (new, archived, default 0) switches to leilei's 4:3-centred layout.
  q3_ui always centres 4:3 (`uis.bias`).
- A stretch pic is one `ImageLabel` per shader stage: UVs map to
  `ImageRectOffset/Size`, `R_SetColor` x `rgbGen/alphaGen` to
  `ImageColor3/ImageTransparency`. UVs past 0..1 are cut into one label per
  texture repeat (exact wrap); over 16 cells the label tiles instead.
  Flipped UVs swap the rect (rbx-native ignores a negative rect size).
- Implicit shaders (an image with no script) are vertex-coloured and
  alpha-blended, as `R_FindShader` makes them for 2D.
- Stage blends: opaque and `blend` are exact; `add` is drawn alpha-blended
  with brightness as opacity; `filter` / `gl_dst_color` stages can't be
  done per pixel by GUI objects. The full-screen menu backgrounds that rely
  on them (`menuback`, `menuback_blueish`, `menubacknologo*`) are composited
  by `scripts/client-dev-assets.py` at time 0 (`index.baked2d`), so their
  slow `tcMod scroll` is frozen.
- `tcMod rotate` on a 2D stage sets `Rotation` (best fit: rotates the
  label, not the texture inside it).

### 3D (R3D, WorldFx)

- Units: rule "Units and axes" above. Models: one `EditableMesh` per MD3
  surface (`(-y, z, -x)/8` local, winding reversed), frames by rewriting
  positions, colours by `SetFaceColors`; conv's baked meshes
  (`index.meshes["model#surface"]`) are used instead when present.
- Sprites -> `BillboardGui`, rail/lightning beams -> `Beam`, marks/polys ->
  a thin part with a `Decal`, dlights -> `PointLight`.
- Map surfaces: conv bakes opaque static shaders into atlas meshes. A
  MeshPart that needs animation carries `OAShader` (+ optional `OAStage`)
  attributes, or is named after a `map.json` mesh whose `class` isn't
  `opaque` (then `index.maps[map].meshes` gives the shader). WorldFx maps:
  `tcMod scroll/rotate/scale/stretch/turb/transform` -> UV rewrite on an
  EditableMesh copy; `animMap` -> `TextureID` swap; `rgbGen/alphaGen wave` ->
  vertex colour or `Transparency`; `deformVertexes wave/move/bulge` -> vertex
  positions; `blendFunc add` -> `Neon` + transparency.
- Sky: `skyparms` box -> `Lighting.Sky` (rt -> SkyboxRt, lf -> SkyboxFt,
  bk -> SkyboxLf, ft -> SkyboxBk, up/dn as is; the in-face rotation of each
  image is unverified until a converted map runs in a client). Fog volumes: with the view
  inside one, `Lighting.FogColor/FogEnd` from its `fogparms` (best fit: Roblox
  fog is global and linear).

### Sound (Snd)

`S_RegisterSound` always returns a handle (a missing sound plays nothing,
like Q3). Each sound is a slice of an atlas (`index.sounds[path] =
{id, start, len}`; conv's `{atlas, start, length}` is accepted with
`index.atlases[atlas]` giving the upload id). Positional sounds sit on an
`Attachment` with linear roll-off, full volume to 80 u and silent at
80 + 1250 u (Q3's `SOUND_FULLVOLUME`/`SOUND_ATTENUATE`). Looping sounds are
re-declared every frame and dropped when not refreshed. The announcer is a
local sound; music uses `index.music`, `s_volume` and `s_musicvolume`.

### Input

`default.cfg` from the pack sets OA's binds. Roblox `KeyCode`s map to Q3
keynums; mouse look comes from `InputChanged` deltas through `cl_input`'s
`m_pitch/m_yaw/sensitivity`. Roblox keeps Escape for its own menu, so
`F10` is also bound to `togglemenu` when free. Gamepad and touch are not
mapped yet: they need `UserInputType.Gamepad1`/touch events turned into
`K_JOY*`/`K_AUX*` keys and analog `usercmd` moves (later work).

## Assets for development

`scripts/client-dev-assets.py` builds, straight from the pk3s:

- `build/client/Files/` (FS pack: cfg, skin, shader, arena, bot scripts,
  and the list of every data path), split in parts under 190k characters;
- `build/client/AssetIndex/`: 2D images as `rbxasset://openarena/<path>.png`
  (rbx-native resolves them from its asset cache), MD3 models
  (`md3b64`; player models without surfaces unless `OA_DEV_FULL_MODELS=1`),
  and the baked menu backgrounds.

TGA files are written without their TGA 2.0 footer first: OA's menu art
declares "no alpha" there while the pixels carry it, and ImageMagick
trusts it (Q3 doesn't), which drew black boxes behind icons.

## Integration points

- **feat/game (`src/shared`)**: `adapters/BG` takes `src/shared/BG.luau`
  (Pmove, PM_UpdateViewAngles, bg_misc) when present; `adapters/CM` takes
  `src/shared/Collision.luau` and loads a map from `CM.loadLumps(name)`,
  which the place's boot code sets (lumps from conv's collision blob through
  `cm/bsp.luau`). Checked: `OA_SHARED=<game>/src/shared lune run tests/smoke`
  runs the HUD/scoreboard with the real pmove. The harness understands
  require-by-string (`require("./bg/bg_pmove")`) for this.
- **net (feat/game, `docs/formats/net.md` not written yet)**: the transport
  calls `Net.ReceiveGamestate(cs, seq, clientNum)`,
  `Net.ReceiveServerCommand(seq, text)` and `Net.ReceiveSnapshot(n, snap)`
  (snapshot_t shape from `q/Types`), and gets `Net.transport.connect(userinfo)`,
  `.disconnect()`, `.command(reliableSequence, text)`, `.usercmds(cmds)`.
- **feat/conv**: MD3 `OAM3` buffers load as `index.models[name] = {oam3 =
  buffer}` (checked equal to raw MD3 on rocketl); `sound_index.json` shape
  accepted; map meshes by `map.json` names; sky/fog per map in
  `index.maps[name].{sky,fogs,meshes}`. The client parses the shader
  scripts from the FS pack itself (same source as `shaders.json`).
- **light grid (feat/conv)**: `sys/LightGrid.luau` ports
  `R_SetupEntityLightingGrid` and the colour shift of `R_LoadLightGrid`
  (`r_mapOverBrightBits 2` over `r_overBrightBits 1`, the split conv bakes
  lightmaps with). The place's boot code sets
  `LightGrid.loadGrid = function(map) return lightgrid, blob end`, the
  `map.json` `lightgrid` record (`origin`, `size`, `bounds`) and the
  `LightGrid` blob joined from its chunk modules (`LightGrid.join`);
  `R_LoadWorldMap` calls it. Without a grid `R_LightForPoint` returns 0 and
  a neutral light.
- **server votes**: q3_ui's `map`/`devmap`/`spmap` and the start-server menu
  become `callvote g_gametype N` + `callvote map X`; the server has to
  accept them.

## Parity (docs/parity)

Reference shots come from OA 0.8.8's own QVMs and data (see "Walls" for the
engine), `scripts/oa-ref.sh <name> <console commands>`; ours come from
`scripts/parity.py`, which pushes the modules into a running rbx-native
editor over MCP, runs a fixture from `src/client/dev/Scene.luau` and takes
`screen_capture`. Ours is drawn at 640x360 (the editor viewport is 962x453
and rbx-native has no `UIScale`), the reference is scaled down to match;
`*_side.png` is reference left, ours right. The editor may present its
viewport scaled in the capture; a 100 px marker measures that and ours is
resampled back (0.54 here), which softens it slightly. RMSE is ImageMagick's
normalised RMSE over the whole frame.

| shot | RMSE | what differs |
|---|---|---|
| `hud_side` (FFA, `give all`, `cg_draw3dIcons 0`) | 0.039 | score box 8 virtual units higher (the vendored gamecode's `CG_DrawLowerRight` starts at `472 - ICON_SIZE`; 0.8.8's QVM uses 480); 3D head is the 2D icon in edit mode (no EditableMesh); console text is in real pixels, so at half size it is twice as big relative to the screen |
| `scores_side` (FFA, 2 players, `+scores`) | 0.055 | same console/score box notes; otherwise item for item |
| `menu_side` (main menu) | 0.117 | no 3D banner model (edit mode); background is the baked composite at time 0 and fills 16:9 (the vendored code draws it at `vidWidth`, 0.8.8's QVM pillarboxes); no MISSION PACK item (no missionpack mod on Roblox); copyright year and colours follow the vendored gamecode (2018 colour set); the cursor shows at (0,0) until the mouse moves; "Protocol: 68" in the reference comes from ioquake3 (our client reports 71, so it isn't drawn) |

## Walls

- **Reference engine.** `openarena.x86_64` needs `libSDL-1.2.so.0`, which
  this machine doesn't have (building sdl12-compat was refused). The
  references use an ioquake3 client built from `vendor/ioq3` with the
  `opengl1` renderer, running OA 0.8.8's own QVMs and pk3s
  (`OA_ENGINE=... scripts/oa-ref.sh`). Engine-side text (console, protocol)
  is ioquake3's.
- **No EditableMesh in rbx-native's edit runtime** (`AssetService:
  CreateEditableMesh` errors there and under lune). MD3 surfaces then don't
  draw (one warning); the parity shots can't show 3D models. In a running
  Roblox client they build normally.
- **Additive / multiplicative blending.** Roblox has neither for GUI nor
  parts. See the 2D and 3D mappings above for the stand-ins.
- **Portals and mirrors** (`misc_portal_surface`): a second scene render
  into a surface needs a render target; the closest Roblox has is a
  `ViewportFrame` on a `SurfaceGui`, which can only show cloned parts, not
  the live world. Portal surfaces draw their fallback texture.
- **Marks** (`trap_CM_MarkFragments`) aren't clipped to the BSP's draw
  surfaces (the client has baked meshes, not surfaces): a mark is the
  projected quad on the plane it hit and can overhang an edge.
- **Lighting of models**: `R_LightForPoint` (`CG_LightVerts`) reads conv's
  light grid (`sys/LightGrid.luau`, see Integration points). The md3
  meshes themselves are still lit by Roblox, not by the grid.
- **trap_UpdateScreen during loading**: Roblox presents only when the script
  yields; CG_Init runs in one frame, so its loading screen is built but not
  seen unless loading spans frames.
- **Out of scope on Roblox**: demos, mods, the server browser and "specify
  server", cinematics, CD keys (`ui_roblox.luau` answers those menus: the
  MULTIPLAYER entry joins the place's match, the rest show a message);
  `quit`, `screenshot`, `vid_restart`, `snd_restart` are no-ops.
- **rbx-native gaps met on the way** (not walls for Roblox itself):
  `Folder:WaitForChild` is missing (the port indexes children directly),
  no `UIScale`, `ViewportFrame.CurrentCamera` can't be read back under lune.
