--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_local.h, game/bg_public.h, qcommon/q_shared.h).

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
===========================================================================
]]
--!native
-- Every numeric #define and enum the game module sees (q_shared.h,
-- surfaceflags.h, bg_public.h, bg_local.h, g_local.h, g_team.h, g_public.h)
-- in one table, so ported code writes C.NAME for any of them.

local C = {}
for k, v in require("../shared/consts") do
	C[k] = v
end
for k, v in require("./g_consts") do
	C[k] = v
end
table.freeze(C)
return C
