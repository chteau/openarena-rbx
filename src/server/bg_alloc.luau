--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/bg_alloc.c).

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
-- The C game module carves its allocations out of a fixed 256 KiB pool
-- (BG_Alloc/BG_Free). Luau tables are garbage collected, so BG_Alloc
-- became plain table construction in the port and the pool has nothing to
-- set up; game_memory reports the Lua heap instead.

local G = require("./g_local")

function G.BG_InitMemory() end

function G.Svcmd_GameMem_f()
	local kb = gcinfo()
	G.G_Printf("Game memory status: %i KiB in use by the Luau heap\n", kb)
end

return G
