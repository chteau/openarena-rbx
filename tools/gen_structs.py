#!/usr/bin/env python3
"""Generate Luau constructors and copy functions for the C structs the
gamecode passes around (playerState_t, entityState_t, gentity_t, ...).

C zero-initialises with memset; the Luau port needs every numeric field to
exist as 0 (nil would make arithmetic throw), every qboolean as false, every
vec3_t as a 0-based {[0]=0,0,0}, every char array as "". Pointers and
function pointers default to nil. `copy_<T>(dst, src)` mirrors C struct
assignment: value members are copied deeply, pointers by reference.

Usage: tools/gen_structs.py
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_consts  # noqa: E402

ROOT = gen_consts.ROOT
GC = gen_consts.GC
IOQ = ROOT / "vendor/ioq3/code"

TARGETS = [
    ("src/shared/structs.luau", [GC / "qcommon/q_shared.h", GC / "game/bg_public.h", GC / "game/bg_local.h"],
     ["cplane_t", "trace_t", "trajectory_t", "playerState_t", "entityState_t", "usercmd_t", "pmove_t",
      "animation_t", "pml_t", "vmCvar_t", "orientation_t", "mapinfo_result_t"], None),
    ("src/server/g_structs.luau", [GC / "game/g_public.h", GC / "game/g_local.h", GC / "game/g_admin.h",
                                   GC / "game/g_killspree.h"],
     ["entityShared_t", "gentity_t", "playerTeamState_t", "clientSession_t", "clientPersistant_t",
      "clientHistory_t", "gclient_t", "level_locals_t", "bot_settings_t", "t_mappage", "t_customvote",
      "g_admin_level_t", "g_admin_admin_t", "g_admin_ban_t", "g_admin_command_t", "g_admin_namelog_t",
      "g_admin_warning_t", "killspree_t", "deathspree_t", "multikill_t"], "../shared/structs"),
]

SCALARS = {"int", "unsigned", "short", "byte", "float", "vec_t", "double", "long", "char", "signed",
           "clipHandle_t", "fileHandle_t", "sfxHandle_t", "qhandle_t", "unsigned int", "signed char"}
VECS = {"vec3_t": 3, "vec4_t": 4, "vec2_t": 2, "vec5_t": 5}
ALIASES = {"gentity_s": "gentity_t", "gclient_s": "gclient_t", "playerState_s": "playerState_t",
           "entityState_s": "entityState_t", "usercmd_s": "usercmd_t", "trace_s": "trace_t"}


def collect(paths):
    """Return {name: body} for every struct typedef, plus the set of enum type names."""
    structs, enums = {}, set()
    for p in paths:
        text = gen_consts.strip_comments(p.read_text(errors="replace"))
        for m in re.finditer(r"typedef\s+enum\s*\w*\s*\{[\s\S]*?\}\s*(\w+)\s*;", text):
            enums.add(m.group(1))
        for m in re.finditer(r"typedef\s+struct\s*(\w*)\s*\{([\s\S]*?)\}\s*(\w+)\s*;", text):
            structs[m.group(3)] = m.group(2)
            if m.group(1):
                ALIASES[m.group(1)] = m.group(3)
        for m in re.finditer(r"^struct\s+(\w+)\s*\{([\s\S]*?)^\};", text, re.M):
            structs[ALIASES.get(m.group(1), m.group(1))] = m.group(2)
    return structs, enums


def fields(body, ev):
    out = []
    for decl in body.split(";"):
        decl = " ".join(decl.split())
        if not decl or decl.startswith("#"):
            continue
        if "(" in decl:  # function pointer
            m = re.search(r"\(\s*\*\s*(\w+)\s*\)", decl)
            if m:
                out.append((m.group(1), "ptr", []))
            continue
        decl = re.sub(r"^(const|struct|volatile)\s+", "", decl)
        m = re.match(r"((?:unsigned |signed )?\w+)\s+(.*)$", decl)
        if not m:
            continue
        ctype, rest = m.group(1), m.group(2)
        ctype = ALIASES.get(ctype, ctype)
        for d in rest.split(","):
            d = d.strip()
            ptr = d.startswith("*")
            d = d.lstrip("* ")
            dm = re.match(r"(\w+)((?:\s*\[[^\]]*\])*)", d)
            if not dm:
                continue
            name = dm.group(1)
            dims = [ev(x) for x in re.findall(r"\[([^\]]*)\]", dm.group(2))]
            if any(x is None for x in dims):
                raise SystemExit(f"cannot size {name}: {dm.group(2)}")
            out.append((name, "ptr" if ptr else ctype, dims))
    return out


def default(ctype, dims, structs, enums):
    """Luau expression for a zeroed value of this type."""
    if ctype == "char" and dims:
        inner = dims[:-1]
        if not inner:
            return '""'
        return arr(inner, '""')
    if ctype == "ptr":
        # an array of pointers: 0-based table(s) of nil slots
        if dims:
            return arr(dims[:-1], "{}") if len(dims) > 1 else "{}"
        return None
    if ctype == "qboolean":
        base = "false"
    elif ctype in VECS:
        base = "vec3()" if ctype == "vec3_t" else f"vecN({VECS[ctype]})"
    elif ctype in SCALARS or ctype in enums or ctype.endswith("_t") and ctype not in structs:
        base = "0"
    elif ctype in structs:
        base = f"S.{ctype}()"
    else:
        raise SystemExit(f"unknown type {ctype}")
    return arr(dims, base) if dims else base


def arr(dims, base):
    if not dims:
        return base
    inner = arr(dims[1:], base)
    return f"arr({dims[0]}, function() return {inner} end)"


def copy_stmt(name, ctype, dims, structs, enums, depth=0):
    """Luau statement copying src.name into dst.name with C value semantics."""
    if ctype == "ptr":
        if dims:
            # copy the pointer values, never what they point to
            return f"ptrcopy(d.{name}, s.{name}, {len(dims)})"
        return f"d.{name} = s.{name}"
    if ctype == "char" and len(dims) <= 1:
        return f"d.{name} = s.{name}"
    if not dims:
        if ctype in VECS:
            n = VECS[ctype]
            return " ".join(f"d.{name}[{i}] = s.{name}[{i}];" for i in range(n))
        if ctype in structs:
            return f"S.copy_{ctype}(d.{name}, s.{name})"
        return f"d.{name} = s.{name}"
    return f"deepcopy(d.{name}, s.{name})"


def main():
    known = {}
    for paths in gen_consts.TARGETS.values():
        gen_consts.parse(paths, known)
    ev = gen_consts.Evaluator(known)
    all_structs, all_enums = {}, set()
    for _, paths, _, _ in TARGETS:
        s, e = collect(paths)
        all_structs.update(s)
        all_enums |= e
    for target, paths, names, base in TARGETS:
        lines = [
            "-- Generated by tools/gen_structs.py from the struct definitions in "
            + ", ".join(str(p.relative_to(ROOT / "vendor")) for p in paths) + ".",
            "-- Do not edit by hand. GPL-2.0 like the headers it is derived from",
            "-- (Copyright (C) 1999-2005 Id Software, Inc., and the OpenArena team).",
            "",
        ]
        if base:
            lines.append(f'local S = setmetatable({{}}, {{ __index = require("{base}") }})')
        else:
            lines.append("local S = {}")
        lines += [
            "",
            "local function vec3() return { [0] = 0, 0, 0 } end",
            "local function vecN(n) local t = { [0] = 0 } for i = 1, n - 1 do t[i] = 0 end return t end",
            "local function arr(n, f) local t = { [0] = f() } for i = 1, n - 1 do t[i] = f() end return t end",
            "-- arrays and nested value structs only ever hold values, so a plain recursive copy is C assignment",
            "local function deepcopy(d, s)",
            "\tfor k, v in s do",
            "\t\tif type(v) == \"table\" and type(d[k]) == \"table\" then deepcopy(d[k], v) else d[k] = v end",
            "\tend",
            "end",
            "S.deepcopy = deepcopy",
            "-- arrays of pointers: copy the references (depth = number of dimensions)",
            "local function ptrcopy(d, s, depth)",
            "\tif depth > 1 then for k, v in s do ptrcopy(d[k], v, depth - 1) end return end",
            "\ttable.clear(d)",
            "\tfor k, v in s do d[k] = v end",
            "end",
            "S.arr = arr",
            "",
        ]
        for name in names:
            body = all_structs[name]
            fl = fields(body, ev)
            lines.append(f"function S.{name}()")
            lines.append("\treturn {")
            for fname, ctype, dims in fl:
                v = default(ctype, dims, all_structs, all_enums)
                if v is not None:
                    lines.append(f"\t\t{fname} = {v},")
            lines.append("\t}")
            lines.append("end")
            lines.append(f"function S.copy_{name}(d, s)")
            for fname, ctype, dims in fl:
                lines.append("\t" + copy_stmt(fname, ctype, dims, all_structs, all_enums))
            lines.append("\treturn d")
            lines.append("end")
            lines.append("")
        lines.append("return S\n")
        (ROOT / target).write_text("\n".join(lines))
        print(f"{target}: {len(names)} structs")


if __name__ == "__main__":
    main()
