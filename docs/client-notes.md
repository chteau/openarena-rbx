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
   block), then one line: `-- Luau port of code/<dir>/<file>.c (OpenArena gamecode).`
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

## Units and axes

Everything in `cg/`, `ui/` and `sys/Trap` stays in Quake units and axes (Z up).
`sys/Units.luau` converts at the Roblox boundary: 1 stud = 8 u,
Quake (x, y, z) -> Roblox (x, z, -y) / 8. Angles go through `AnglesToAxis` and
the axis is converted, never the Euler angles.

## Engine mapping (trap_* -> Roblox)

Filled in as each system lands; see the sections below.
