--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of Quake III Arena source code.

Quake III Arena source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

Quake III Arena source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Quake III Arena source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
]]
-- Luau port of code/q3_ui/ui_sparena.c (OpenArena gamecode).

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

function U.UI_SPArena_Start(arenaInfo)
	local n = Q.int(trap.Cvar_VariableValue("sv_maxclients"))
	if n < 8 then
		trap.Cvar_SetValue("sv_maxclients", 8)
	end

	local level = Q.int(tonumber(Q.Info_ValueForKey(arenaInfo, "num")) or 0)
	local txt = Q.Info_ValueForKey(arenaInfo, "special")
	if txt ~= "" then
		if txt == "training" then
			level = -4
		elseif txt == "final" then
			level = U.UI_GetNumSPTiers() * C.ARENAS_PER_TIER
		end
	end
	trap.Cvar_SetValue("ui_spSelection", level)

	local map = Q.Info_ValueForKey(arenaInfo, "map")
	trap.Cmd_ExecuteText(C.EXEC_APPEND, Q.va("spmap %s\n", map))
end

return U
