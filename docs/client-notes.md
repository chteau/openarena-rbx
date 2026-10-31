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
- q3_ui: `UI_DrawBackgroundPic` (menu backgrounds are one full-screen pic
  again; see "Widescreen" for how it covers a wide screen), `ui_browserHidePrivate`,
  `ui_pos_scorelimit`/`ui_pos_timelimit`, the 2018 copyright line, the
  `fixedlegs`/`fixedtorso` UI player options, the text-effect helpers,
  and the vote, start-server, controls, video, player and challenges menus
  as master changed them. `ui_options.c` (0.8.8 only) is not ported:
  nothing in 0.8.8 calls `UI_SystemConfigMenu`.

Kept although no C source has them: the engine layer (`sys/*`,
`ui_roblox.luau`) and the widescreen layout below.

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
| LAN_* | LAN (server browser over the Servers remote) | see ARCHITECTURE.md, "Multiplayer on Roblox servers" |
| CIN_*, PC_*, CD key, camera paths, GetEntityToken | Trap | inert (see "Walls") |

### 2D (R2D)

- Screen math lives in `src/ui/Screen.luau` only; see "Widescreen" below.
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
- Additive and filter stages of effects (sprites, marks, particles, beams,
  model surfaces, 2D) draw conv's alpha-blended stand-in for their blendFunc
  (`Assets.StageImage`: `<image>~<src>_<dst>`, see conv-notes "Blend
  stand-ins") when it has an id, and fold the stage colour's brightness
  into opacity (`ShaderFx.foldBrightness`: OA fades additive effects by
  darkening them). Beams keep `LightEmission = 1` for add, which with the
  stand-in is a true additive blend. Over black a stand-in matches OA; over
  bright surfaces additive effects come out dimmer than OA's (alpha blending
  can't brighten past the effect's colour) and coloured filters lose part of
  their tint. A MeshPart (md3 surfaces, map parts) drawing an alpha
  texture keeps a Transparency of at least 0.02
  (`ShaderFx.MESH_ALPHA_MIN`): at 0 Roblox ignores the texture's alpha and
  a stand-in's see-through texels draw black (muzzle flashes, impact
  rings, explosions showed black squares). Unbaked map surfaces (light beams, flames, glows, map decals)
  do the same in `WorldFx`: the part draws the stand-in of the stage whose
  image it wears, as a plain texture (no Neon), its brightness as opacity.
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
`m_pitch/m_yaw/sensitivity`. Roblox keeps Escape for its own menu (it can't be taken
over), so **P** is OA's Escape: it opens and closes the menu and backs out
of submenus, and the spectator hint says "press P". P still types a `p` in
the chat prompt, the console and menu text fields. Escape only reaches OA to
cancel the chat prompt or close the console. `F10` is also bound to
`togglemenu` when free. Gamepad and touch are not
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

## Chat

What players type is OA's chat on top of Roblox's text chat, so it is
filtered as Roblox requires. Roblox's own UI is off: `OAClient.client.luau`
turns off `TextChatService`'s chat window, input bar and bubbles first
thing and retries `SetCoreGuiEnabled(PlayerList / Chat, false)` until the
CoreGui takes it. Tab is OA's `+scores` (default.cfg).

The engine half follows ioquake3 (`vendor/ioq3/code/client`):

- **Notify lines** (`sys/Console.luau`, `cl_console.c` `CL_ConsolePrint`
  and `Con_DrawNotify`): lines wrap at `vidWidth / 8 - 2` columns at word
  boundaries (the rest of the word is measured at every character, like
  the C), colours carry over a wrap, and the last three finished lines plus
  the unfinished one show while younger than `con_notifytime` (3 s), in
  8x16 real pixels at the top left, below the safe-area inset (the Roblox
  topbar).
- **The prompt** (`sys/Chat.luau`, `Con_MessageMode*_f`, `Message_Key`,
  `Field_KeyDownEvent`/`Field_CharEvent`/`Field_VariableSizeDraw`):
  `messagemode` (T in 0.8.8's default.cfg), `messagemode2` (team; 0.8.8
  binds no key, the controls menu does), `messagemode3`/`4` (tell the
  crosshair player / last attacker). `say:` or `say_team:` and the field
  are big chars with the drop shadow at 640x480 (8, v * 480 / vidHeight +
  8), the field 30 (25 for team) characters wide with OA's scrolling,
  insert/overstrike cursor, Home/End/Del/arrows and ctrl-a/e/h/c. A key's
  own character is dropped when its bind changed the key catcher (ioq3
  runs the bind a frame later), so T doesn't type a t.
- **Sending**: Enter sends the line with `TextChannel:SendAsync` on
  `TextChatService.OAChat.Say` (Metadata `tell <n>` for messagemode3/4) or
  `.Team`, never as a `say` command. The server
  (`server/sv/chat_roblox.luau`) runs the game's own `G_Say` (or
  `Cmd_Tell_f`'s two calls) on the first `ShouldDeliverCallback` of the
  message, catching the `chat`/`tchat` commands it sends: every human it
  picked gets `rchat <MessageId> <chat|tchat> "<name prefix>"`, everyone
  else is refused delivery, so OA's team, tell and tourney rules decide who
  sees it. The client joins the prefix with the text Roblox delivered
  (`MessageReceived`, filtered for that viewer, or `SendAsync`'s own copy
  for the sender) and runs the cgame's `CG_ChatMessage`, the `chat`/`tchat`
  path of `CG_ServerCommand`: talk sound, `cg_teamChatsOnly`, the team chat
  box (`cg_teamChatHeight`, 0 by default as in 0.8.8) and the notify line.
  Bots G_Say picked get the line with the text filtered for broadcast
  (`TextService`), so their replies only ever quote filtered text.
- **Never unfiltered**: the engine refuses `say`, `say_team` and `tell` from
  players (`SV_ExecuteClientCommand`), so a console `say` goes nowhere;
  bots and the server (frags, "entered the game", bot chat from
  `botfiles/`) still print directly. A player's name is their Roblox
  display name (the username when it has characters OA's font lacks), set
  by the engine over the `name` cvar (`SV.RobloxName`).
- **Who can chat**: the server sets the Player attribute `OACanChat` from
  `TextChatService:CanUserChatAsync`; without it the messagemode commands
  open nothing.

Not 1:1: OA draws the prompt stretched to the screen (x * vidWidth / 640),
ours keeps the 640x480 scale uniform like the rest of the HUD; Escape
cancels the prompt but also opens Roblox's menu (Roblox keeps Escape);
paste (ctrl-v, shift-insert) does nothing (scripts can't read the
clipboard); 0.8.8 has no flood limit on say (it is commented out in
`ClientCommand`) and none was added, Roblox rate-limits `SendAsync`;
admin commands typed in chat (`g_adminParseSay`) run on the text as typed.

Live on 2026-10-30 (Sober through rbx-native's Play, rbx-native dev
56b8d364, the play sandbox): `docs/parity/chat/`, OA references in
`docs/parity/ref/chat_say.png` and `chat_team.png` (ioquake3 from
`vendor/ioq3` with 0.8.8's QVMs and data).

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

## Widescreen

OA 0.8.8 is laid out for 4:3 (its 640x480 virtual screen, cg_fov as a 4:3
FOV) and stretches the HUD over a wider screen. Roblox players use every
aspect, so the port lays out for each one instead; at 4:3 with no safe-area
insets everything lands exactly where 0.8.8 puts it (`tests/screen.test.luau`,
and every drawn label of the menu, HUD and scoreboard fixtures compared
against the stretch at 640x480 and 1024x768). There is no cvar for the old
stretch: `cg_wideScreenHud` is gone.

- **3D view, Hor+** (`Screen.fov`, called by `CG_CalcFov`): cg_fov,
  cg_zoomFov and the fixed 90 of intermission and `DF_FIXED_FOV` stay 4:3
  horizontal FOVs. The view keeps that 4:3 view's vertical FOV and widens
  the horizontal one with the aspect; narrower than 4:3 it keeps the
  horizontal FOV instead (Vert+), so no aspect sees less than 4:3:
  `fov_y = 2 atan(tan(fov/2) * max(3/4, h/w))`, `fov_x = 2 atan(tan(fov_y/2) * w/h)`.
  `zoomSensitivity` (from fov_y) and the gun's fov drop (from cg_fov) are
  unchanged; the view weapon is in the same scene, so it follows the camera.
- **HUD anchored, never stretched.** The 640x480 area scales uniformly by
  `s = min(safe width / 640, h / 480)` (so a narrow screen shrinks the HUD to
  fit), and each element is drawn under a placement
  (`G.CG_SetScreenPlacement`, the idea of Spearmint's `CG_SetScreenPlacement`):
  left/right/top/bottom keep the element's 4:3 offset from that edge of the
  safe area, centre uses the screen's centre, stretch fills the screen.
  `CG_Draw2D` sets them per element:

  | element | placement |
  |---|---|
  | status bar: team background | stretch, bottom |
  | status bar: ammo (and its icon) | left, bottom |
  | status bar: health, head, carried flag | centre, bottom |
  | status bar: armor, harvester skulls | right, bottom |
  | weapon select, spectator text | centre, bottom |
  | upper right stack (team overlay 1, FPS, timer, snapshot, attacker, speed, LMS/DOM/CTF-E status, follow) | right, top |
  | lower right stack (team overlay 2, score box, powerups), lagometer, disconnect icon | right, bottom |
  | lower left stack (team overlay 3, pickup notification), team chat box | left, bottom |
  | vote, team vote | left, top |
  | holdable item, persistant powerup, accuracy board | right, centre |
  | ammo/prox warnings, rewards, warmup, following | centre, top |
  | crosshair, crosshair names, center prints, scoreboard, intermission, info screen | centre |
  | tourney scoreboard backdrop | stretch |

  The console notify lines (obituaries, chat, "entered the game") are
  engine text in real pixels at the top left, moved in by the insets; the
  chat prompt below them is in 640x480 units pinned there ("Chat"). The levelshot of the info screen covers the screen
  (`Screen.cover`: cropped, not stretched). 0.8.8 has no 2D zoom mask or
  full-screen damage/powerup overlay; those effects are 3D, in the view.
- **Menus.** q3_ui stays a centred 4:3 layout (`uis.bias`, `uis.ybias` when
  narrower than 4:3). The full-screen backgrounds (`menuback*`, the connect
  screen) cover the whole screen (`U.UI_DrawBackground`), so there are no
  pillarbox bars. The cursor reaches every screen edge, side areas included
  (virtual x below 0 or past 640).
- **Live.** `Client` checks the viewport (`workspace.CurrentCamera.ViewportSize`)
  and the safe area every frame; on a change both the cgame and q3_ui re-read
  glconfig and redo their layout. The safe area is a probe ScreenGui with
  `ScreenInsets = CoreUISafeInsets` measured against the full-screen root
  (`ScreenInsets = None`, `SafeAreaCompatibility = None`), so notches and the
  Roblox topbar are kept clear; without `ScreenInsets` it falls back to
  `GuiService:GetGuiInset()`. In a Roblox client the topbar inset moves the
  top-anchored elements down even at 4:3.

Shots from rbx-native's editor (`scripts/parity.py --size WxH`):
`docs/parity/widescreen/{hud,scores,menu}_{16x9,21x9,4x3,3x4}.png`, drawn at
640x360, 640x274, 560x420 and 300x400 (the frame the fixture draws into is
the screen, so no window resize is needed). They show 2D only: edit mode has
no EditableMesh, so no 3D models.

## Roblox avatars

Players are drawn as their own Roblox avatar by default; bots, and players
whose avatar can't be built, keep their OA model. The avatar is visual
only: OA's player box (30x30x56 u standing, 40 u crouched) and pmove stay
authoritative, and nothing about gameplay reads the avatar.

| piece | where |
|---|---|
| build, replicate, `g_robloxAvatars` | `src/server/sv/avatars_roblox.luau` (called by `transport_roblox`) |
| local copies, scaling, placement, tracks, Highlight, headshot | `src/client/sys/Avatar.luau` |
| the maths (timing, track mapping, sampling, fit, feet, look) | `src/client/avatar/AvatarAnim.luau` |
| the R15 animation set (generated) | `src/client/avatar/anims/{Legs,Torso}.luau`, `tools/gen_avatar_anims.py` |
| cgame side (`CG_AvatarPlayer`, lerp frames, weapon, head icon) | `src/client/cg/cg_avatars.luau`; hooks in `CG_Player`, `CG_ResetPlayerEntity`, `CG_AddPlayerWeapon`, `CG_DrawHead` |
| trap calls | `trap.R_AvatarReady`, `R_AddAvatarToScene`, `R_AvatarTag`, `R_AvatarHeadShader`, `R_AvatarAnimations` |
| tests | `tests/avatar.test.luau` |

### Build

On connect the server asks for the player's `HumanoidDescription`
(`Players:GetHumanoidDescriptionFromUserId`) and builds an R15 model from
it (`Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)`),
so an R6 user gets an R15 body with their accessories, clothing, body
colours, face and bundle parts. Scripts are stripped. The model goes to
`ReplicatedStorage.OAAvatars` as `c<clientNum>` with a `UserId` attribute;
it is kept per UserId so a map change (the client reconnects) only clones
it again. A failure (a test player with a negative id, the avatar service
down) leaves the player on their OA model. `Players.CharacterAutoLoads`
stays false: these are never characters.

Avatars are always on. `g_robloxAvatars` and `cg_robloxAvatars`, which
could turn them off, are gone, and an old saved value of either is ignored.

### Local copies and scale

Each client prepares one copy per player (`Avatar.luau`, `prepare`): scripts
and force fields removed, and the joints made Motor6Ds. Today
`CreateHumanoidModelFromDescription` builds the physics-ready rig, where
every joint is an `AnimationConstraint` between two rig attachments plus a
`BallSocketConstraint` limit and there is no Motor6D at all (seen live: 15
AnimationConstraints, 14 ball sockets, 0 Motor6Ds). The local copy gets a
Motor6D per AnimationConstraint, same name, in `Part1`, with `C0`/`C1` the
two attachments' frames (Attachment1 = Attachment0 * Transform, as Part1 =
Part0 * C0 * Transform * C1^-1), and the constraints are removed, so both
rigs end up the same. A copy whose Humanoid, root or joints haven't
replicated yet is tried again a second later. Then `AutomaticScalingEnabled`
off, and it is measured at
rest by forward kinematics over its own Motor6Ds (no reliance on where the
parts happen to sit): sole (lowest foot bottom) to crown (top of `Head`),
leg length (hip joints to sole) and the hips' middle relative to the
`HumanoidRootPart`. It is scaled uniformly (`Model:ScaleTo`) so the crown
is at OA's standing model height: **53.24 u (6.66 studs)**, sarge's idle
legs + standing torso + head measured from the md3s (`gen_avatar_anims.py`
prints it), against the 56 u box. Accessories don't count towards the
height, so a tall hat stays a tall hat. Odd bodies: the scale is clamped to
0.2..5 so a degenerate measurement can't make a speck or a giant, and
since every pose is in leg-length units (below), short-legged, rthro and
tiny avatars all get the same angles and plant their feet with their own
leg length.

Every player entity drawn with an avatar (the player and each of their
corpses in the body queue) gets a clone of that copy in the world folder,
with every part `CanCollide/CanQuery/CanTouch = false`, `Massless`, the
root anchored and invisible; the Humanoid has no state machine
(`EvaluateStateMachine = false`), no name or health display, and keeps its
`Animator` only to play our tracks. An entity not drawn this frame is
unparented; one whose player left is destroyed.

### Placement

`CG_AvatarPlayer` runs `CG_PlayerAngles` unchanged and hands the engine
the interpolated/predicted `lerpOrigin`, the legs axis (yaw swing, lean)
and the torso and head axes relative to their parents. The engine puts the
hips' middle at the legs pose's position (in leg lengths over the box
floor, MINS z = -24 under the origin), turned by the pelvis rotation, and
the root part under it. The torso axis (yaw swing, 3/4 of the pitch, pain
twitch) is added to the Waist's C0 after the legs' own tag_torso turn; the
head axis to the Neck's C0. Transforms stay the animations'.

Feet: in a frame where sarge stands, the lower sole is snapped to the
floor (or kept as far above it as sarge's foot is, for a jump's tuck), and
nothing is allowed under the floor. The snap is what keeps the feet planted
when an avatar's thigh to shin ratio differs from sarge's. Dying and dead
(`BOTH_*`), the lowest part of the body, arms left out, is put on the floor,
up or down: the first live run showed a corpse held a stud in the air by a
hand the IK had put under the floor.

### The animation set

All 25 of 0.8.8's animation.cfg entries, plus the ones OA derives at load
(`LEGS_BACKCR`, `LEGS_BACKWALK`: the crouch walk and walk reversed;
`TORSO_GETFLAG`..`TORSO_NEGATIVE`: the gesture, five of them flip-flopping),
exactly as `CG_ParseAnimationFile` builds them: same frame counts, frame
rates and loops (`tests/avatar.test.luau` compares the two tables). A
`BOTH_*` animation has a legs clip and a torso clip. Sarge's numbers are
used whatever OA model the player picked, since the poses come from his.

`tools/gen_avatar_anims.py` makes them from sarge's md3s (re-run it after
changing it; `--check` fails when the committed data is stale):

- legs (`lower.md3`): hip, knee and foot vertex clusters picked on the idle
  frame and followed by vertex index through every frame, toe and heel
  thirds of each foot, and `tag_torso`. The pelvis rotation is the turn of
  the spine (hips' middle to tag_torso) from idle plus the hip line;
  each leg is two-bone IK to the foot cluster in leg-length units with the
  knee towards where sarge's knee is when that is within 60 degrees of
  where his toes point, else towards the toes (a near-straight md3 leg's
  knee wanders: followed blindly it twisted the idle right thigh 109
  degrees, which a blocky R15 leg shows plainly), the foot pitched along
  toe - heel;
  the hips' height and offset are ratios of sarge's leg length (23.2 u);
- the Waist's legs part is tag_torso relative to the pelvis;
- torso (`upper.md3`): the chest turns with the neck (`tag_head` origin's
  direction from standing) and twists with the shoulder clusters; the head
  is `tag_head`'s rotation; the right arm is IK to `tag_weapon` in arm
  lengths (sarge's arm, 17.6 u, is the longest shoulder to tag_weapon reach
  of any frame), the right hand takes `tag_weapon`'s rotation, so the gun's
  barrel is the hand's -Z; the left arm hangs relaxed at the hip in the
  gun animations, guards in front of the chest with the gauntlet
  (`TORSO_STAND2`, `TORSO_ATTACK2`) and mirrors the right arm across the
  legs' middle plane in the deaths.

Stride: in OA the planted foot slides against the ground. Measured in the
md3 (the foot's speed relative to the hips over frames where it is down),
sarge's run moves it at 262 u/s against pmove's 320; the back run at 124
for 320, the walk at 78 for 160 (half stick), the crouch walk at 53 for
80 (`pm_duckScale`). The generator stretches each cycle's foot travel by
speed / measured, at most 1.5: the run is matched (x1.22, no skating at
320 u/s), the others are stretched x1.5 and still slip some, since more
would straighten the legs past what the hips' height allows at OA's own
cadence (frame counts and rates are kept).

Contact sheets of the IK skeleton for every animation were checked during
development (a throwaway renderer, not committed): the run, walk and back
cycles alternate their feet, the crouches keep both feet down, the jump
tucks, the deaths fall and lie flat.

### Playback

Clips are KeyframeSequences built at run time from the data, one keyframe
per md3 frame (and the last one again one frame later, so a one-frame
stance still has a length), Linear poses, legs at `Movement` and torso at
`Action` priority, each touching only its own joints (the root and lower
torso poses are weight-0 placeholders). They are registered with
`AnimationClipProvider:RegisterActiveAnimationClip`; no asset is uploaded.
**In a live game this fails**: the playtest (real Roblox through
rbx-native's Play) raised "Usage error: RegisterActiveKeyframeSequence can
only be used in Solo mode." on the first registration, matching the API
page's "cannot be used outside of Studio". So on Roblox the avatars run in
the motors mode below; the Animator path stays for Studio's own playtests
and in case Roblox lifts the limit. Shipping Animator tracks would need the
clips uploaded as Animation assets, which this port doesn't do.

They are not played on Roblox's clock: OA's own lerp frames
(`CG_RunLerpFrame` on the avatar animation table, a lerp state per half
per entity in `cent.avatar`, including haste's 1.5x and the idle turn
shuffle) say which md3 frames to show, and each track is held there (speed
0, `TimePosition` set every frame). Neighbouring frames are one track at
an in-between time; a loop wrapping round or a change of animation is two
tracks (the same clip twice when it wraps), weighted backlerp and
1 - backlerp, which is OA's vertex lerp across the change. Legs and torso
blend independently because they are separate tracks on separate joints.

Fallback ("motors" mode): if the registration raises, or the first track
doesn't get a length within 5 s, the same poses (`AvatarAnim.sample`) are
written to the Motor6Ds' `Transform` every frame and the Animator is
removed. A rig whose joints are turned at rest (a C0 rotation over 2
degrees) always takes this path, since the clips are in the character's
axes. The client prints which path it took. This is the path live games
take (above); OA's lerp frames, the two-clip blend and the yaw/pitch split
are the same either way, since the motors get `AvatarAnim.sample`'s mix.

### Weapons, effects, teams

- The third-person weapon hangs from the right hand: the hand's frame
  (from the hand pose above) plus a grip offset (`GRIPS` in `Avatar.luau`,
  in hand units scaled with the avatar), handed to `CG_AddPlayerWeapon` as
  its parent with `avatarGrip` set, so the barrel, its spin, the muzzle
  flash, the rail/lightning origin and the weapon sounds work as before.
  The first-person view model is unchanged.
- Powerups: quad = a blue shell (red for the red team, as OA's
  `redQuadShader`) pulsing once a second, battlesuit = gold, regen = OA's
  red flash on the 100 ms tick, invisibility = 85% see-through, or not
  drawn at all with `DF_INVIS`. One `Highlight` per avatar.
- Teams (TDM, CTF and the other team modes): a red or blue outline and a
  15% tint, so the avatar stays recognisable. A shell takes the fill and
  keeps the team outline.
- Flags, persistent powerups, breath, dust, splash, shadows and the talk /
  disconnect sprites attach to stand-ins at the avatar's chest and head.
- Gibs and death: `com_blood` / `cg_gibs` rules are unchanged. A gibbed
  body becomes invisible in the game, so its avatar isn't drawn and the
  gibs fly as before; a corpse keeps its avatar lying in the death pose.
- Footsteps: OA's own (`EV_FOOTSTEP*` events from pmove), unchanged.

### Settings

- None: every player with an account is drawn as their Roblox avatar. The
  player settings menu says "Show players as: Roblox avatars" on a line
  that can't be changed, shows the player's own avatar (the
  `rbxthumb://type=Avatar` picture, `Avatar.LocalBodyShader`) where OA drew
  the model preview, and has no "model" button.
- A bot wears its OA model from the kept roster (`tools/oaconv/roster.json`)
  unless it is a friend-bot, which gets its friend's avatar through the same
  path (`docs/bots-notes.md`, "Friend-bots"). The player's own `model` only
  matters while their avatar loads or if it fails, and a dropped model is
  still refused by the server as before.

### Head icon

Every head icon of a client wearing a Roblox account (a player, a roster
bot or a friend-bot) is that account's
`rbxthumb://type=AvatarHeadShot&id=<id>&w=150&h=150` image (an implicit 2D
shader, `Assets.RegisterImage`, `Avatar.Headshot`): the status bar face,
the scoreboard heads, the attacker's head and the loading screen icons
(`CG_AvatarHeadShader`), whether the avatar or the OA model is drawn
(`cg_robloxAvatars`, `g_robloxAvatars`). The server publishes the account
of each client as the `OAAvatars` folder's `User<clientNum>` attribute (a
string) and the roster bots' accounts as `BotRoster` (`"grunt=1274097373
liz=..."`, empty with `g_botRoster 0`), which the single player level menu
uses for its opponents' faces; the player's own face there is their
headshot too. A client without an account keeps OA's 3D head or icon.

### Live run

On 2026-10-30, in real Roblox (Sober through rbx-native's Play, built from
rbx-native dev 56b8d364): a 4.5 MB place from `place/assemble.py --maps
oa_dm1 --players sarge,grism` with `bot_enable 1; g_gametype 0; devmap
oa_dm1; addbot sarge 1; addbot grism 1`. The client was driven over MCP
(`execute_luau` in the Client data model to run console commands:
`connect`, `cg_thirdPerson 1`, `setviewpos`, `+forward`, `+moveleft`,
`+moveup`, `+movedown`, `+attack`; `screen_capture`; `get_console_output`)
and killed from the Server data model with `G_Damage` (a plain `kill` is
-999, a gib). Pictures in `docs/parity/avatars/`:

- the server built Chee's avatar (`c2`, his UserId) and the client drew it
  in third person with its accessories (cap, butterflies, the party
  unicorn ring) and its Headless head: `idle.png`, `run.png`,
  `strafe.png`, `jump.png`, `crouch.png`, `shoot.png` (muzzle flash on the
  machinegun in the right hand);
- death: the BOTH_DEATH fall and the corpse on the floor
  (`death_falling.png`, `dead.png`, the scoreboard on top as in OA);
- head icon: the status bar and scoreboard show the avatar headshot
  (`back_hud_headshot.png`, bottom; `dead.png`, scoreboard);
- the setting line in the player menu (`menu.png`);
- `cg_robloxAvatars 0` unparented the avatar and `1` brought it back;
  `g_robloxAvatars 0` emptied `OAAvatars` within a second and `1` rebuilt
  it;
- bots: Sarge and Grism fought and fragged each other and the player, but
  OA models are **invisible in this sandbox**, so a bot shows only as its
  gun, shadow and name (`bot_alongside.png`, `shoot.png` on the right).
  The console's "no EditableMesh here" was one faceless surface turning
  EditableMesh off for the session, not the experience setting; the OA
  models stay invisible for want of their textures (`docs/assembly-notes.md`).

Found and fixed during the run: the AnimationConstraint rig (no Motor6Ds,
the copy was refused and the client drew OA models), a template cached as
missing before its parts had replicated, the RegisterActiveAnimationClip
limit (the fallback took over by itself), the twisted right thigh, and the
floating corpse.

Not seen live: team outlines, powerup shells and the grip of every weapon
(only the machinegun was carried); they are covered by `avatar.look` in the
tests and use the same paths as the shots above.

## Parity (docs/parity)

Reference shots come from OA 0.8.8's own QVMs and data (see "Walls" for the
engine), `scripts/oa-ref.sh <name> <console commands>` (for the in-game shots:
`devmap oa_dm1`, `wait 200`, then `give all` or `addbot sergei`,
`setviewpos 6000 6000 6000 0`, `cg_draw3dIcons 0`, `cg_drawGun 0`,
`r_drawworld 0`, `r_clear 1`, and `+scores` for the scoreboard); ours come from
`scripts/parity.py`, which pushes the modules into a running rbx-native
editor over MCP, runs a fixture from `src/client/dev/Scene.luau` and takes
`screen_capture`. Ours is drawn at 640x360 (the editor viewport is 962x453
and rbx-native has no `UIScale`), the reference is scaled down to match;
`*_side.png` is reference left, ours right. The push leaves out `src/shared`:
its require-by-string doesn't run in rbx-native's edit runtime, so the
fixtures use the client's fallback `bg_misc`. The editor may present its
viewport scaled in the capture; a 100 px marker measures that and ours is
resampled back (0.54 here), which softens it slightly. RMSE is ImageMagick's
normalised RMSE over the whole frame.

| shot | RMSE | what differs |
|---|---|---|
| `hud_side` (FFA, `give all`, `cg_draw3dIcons 0`) | 0.033 | item for item; the 3D head is the 2D icon in edit mode (no EditableMesh); console text is in real pixels, so at half size it is twice as big relative to the screen |
| `scores_side` (FFA, a skill 4 bot, `+scores`) | 0.055 | the same console note; otherwise item for item |
| `menu_side` (main menu) | 0.107 | no 3D banner model (edit mode); the background is the baked composite at time 0 (frozen `tcMod scroll`); no MISSION PACK item (no missionpack mod on Roblox); the cursor shows at (0,0) until the mouse moves; "Protocol: 68" in the reference comes from ioquake3 (our client reports 71, so it isn't drawn) |

## Walls

- **Reference engine.** `openarena.x86_64` needs `libSDL-1.2.so.0`, which
  this machine doesn't have (building sdl12-compat was refused). The
  references use an ioquake3 client built from `vendor/ioq3` with the
  `opengl1` renderer, running OA 0.8.8's own QVMs and pk3s
  (`OA_ENGINE=... scripts/oa-ref.sh`). Engine-side text (console, protocol)
  is ioquake3's. The build needs only the SDL2 runtime: cmake's `SDL2_DIR`
  can point at a two-line `SDL2Config.cmake` naming
  `code/thirdparty/SDL2-*/include` and the system `libSDL2-2.0.so.0`.
  The editor binary has to include the MCP server (rbx-native from late
  October 2026 on, Settings > Beta features > MCP server, or
  `{"enabled":["mcp-server"]}` in `<config>/rbx-native/beta.json`).
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
- **Out of scope on Roblox**: demos, mods, cinematics, CD keys
  (`ui_roblox.luau` answers those menus with a message). The server browser
  and "specify server" list Roblox servers (`docs/ARCHITECTURE.md`,
  "Multiplayer on Roblox servers");
  `quit`, `screenshot`, `vid_restart`, `snd_restart` are no-ops.
- **rbx-native gaps met on the way** (not walls for Roblox itself):
  `Folder:WaitForChild` is missing (the port indexes children directly),
  no `UIScale`, `ViewportFrame.CurrentCamera` can't be read back under lune.
