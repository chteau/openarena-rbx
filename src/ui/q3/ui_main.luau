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
-- Luau port of code/q3_ui/ui_main.c (OpenArena 0.8.8, gamecode 9e0f0c0).

local U = require(script.Parent.U)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local function toInt(v: any): number
	if type(v) == "boolean" then
		return Q.b2i(v)
	end
	if v == nil then
		return 0
	end
	return v
end

--[[
================
vmMain

This is the only way control passes into the module.
================
]]
function U.vmMain(command, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11)
	if command == C.UI_GETAPIVERSION then
		return C.UI_API_VERSION
	elseif command == C.UI_INIT then
		U.UI_Init()
		return 0
	elseif command == C.UI_SHUTDOWN then
		U.UI_Shutdown()
		return 0
	elseif command == C.UI_KEY_EVENT then
		U.UI_KeyEvent(arg0, arg1)
		return 0
	elseif command == C.UI_MOUSE_EVENT then
		U.UI_MouseEvent(arg0, arg1)
		return 0
	elseif command == C.UI_REFRESH then
		U.UI_Refresh(arg0)
		return 0
	elseif command == C.UI_IS_FULLSCREEN then
		return toInt(U.UI_IsFullscreen())
	elseif command == C.UI_SET_ACTIVE_MENU then
		U.UI_SetActiveMenu(arg0)
		return 0
	elseif command == C.UI_CONSOLE_COMMAND then
		return toInt(U.UI_ConsoleCommand(arg0))
	elseif command == C.UI_DRAW_CONNECT_SCREEN then
		U.UI_DrawConnectScreen(arg0)
		return 0
	elseif command == C.UI_HASUNIQUECDKEY then -- mod authors need to observe this
		return 1
	end

	return -1
end

--[[
================
cvars
================
]]

local A = C.CVAR_ARCHIVE

-- { global name, cvar name, default, flags }; a nil global name is a cvar without a vmCvar
local cvarTable = {
	{ "ui_ffa_fraglimit", "ui_ffa_fraglimit", "20", A },
	{ "ui_ffa_timelimit", "ui_ffa_timelimit", "0", A },

	{ "ui_tourney_fraglimit", "ui_tourney_fraglimit", "0", A },
	{ "ui_tourney_timelimit", "ui_tourney_timelimit", "15", A },

	{ "ui_team_fraglimit", "ui_team_fraglimit", "0", A },
	{ "ui_team_timelimit", "ui_team_timelimit", "20", A },
	{ "ui_team_friendly", "ui_team_friendly", "1", A },

	{ "ui_ctf_capturelimit", "ui_ctf_capturelimit", "8", A },
	{ "ui_ctf_timelimit", "ui_ctf_timelimit", "30", A },
	{ "ui_ctf_friendly", "ui_ctf_friendly", "0", A },

	{ "ui_1fctf_capturelimit", "ui_1fctf_capturelimit", "8", A },
	{ "ui_1fctf_timelimit", "ui_1fctf_timelimit", "30", A },
	{ "ui_1fctf_friendly", "ui_1fctf_friendly", "0", A },

	{ "ui_overload_capturelimit", "ui_overload_capturelimit", "8", A },
	{ "ui_overload_timelimit", "ui_overload_timelimit", "30", A },
	{ "ui_overload_friendly", "ui_overload_friendly", "0", A },

	{ "ui_harvester_capturelimit", "ui_harvester_capturelimit", "20", A },
	{ "ui_harvester_timelimit", "ui_harvester_timelimit", "30", A },
	{ "ui_harvester_friendly", "ui_harvester_friendly", "0", A },

	{ "ui_elimination_capturelimit", "ui_elimination_capturelimit", "8", A },
	{ "ui_elimination_timelimit", "ui_elimination_timelimit", "20", A },

	{ "ui_ctf_elimination_capturelimit", "ui_ctf_elimination_capturelimit", "8", A },
	{ "ui_ctf_elimination_timelimit", "ui_ctf_elimination_timelimit", "30", A },

	{ "ui_lms_fraglimit", "ui_lms_fraglimit", "20", A },
	{ "ui_lms_timelimit", "ui_lms_timelimit", "0", A },

	{ "ui_dd_capturelimit", "ui_dd_capturelimit", "8", A },
	{ "ui_dd_timelimit", "ui_dd_timelimit", "30", A },
	{ "ui_dd_friendly", "ui_dd_friendly", "0", A },

	{ "ui_dom_capturelimit", "ui_dom_capturelimit", "500", A },
	{ "ui_dom_timelimit", "ui_dom_timelimit", "30", A },
	{ "ui_dom_friendly", "ui_dom_friendly", "0", A },

	{ "ui_arenasFile", "g_arenasFile", "", bit32.bor(C.CVAR_INIT, C.CVAR_ROM) },
	{ "ui_botsFile", "g_botsFile", "", bit32.bor(C.CVAR_INIT, C.CVAR_ROM) },
	{ "ui_spScores1", "g_spScores1", "", bit32.bor(A, C.CVAR_ROM) },
	{ "ui_spScores2", "g_spScores2", "", bit32.bor(A, C.CVAR_ROM) },
	{ "ui_spScores3", "g_spScores3", "", bit32.bor(A, C.CVAR_ROM) },
	{ "ui_spScores4", "g_spScores4", "", bit32.bor(A, C.CVAR_ROM) },
	{ "ui_spScores5", "g_spScores5", "", bit32.bor(A, C.CVAR_ROM) },
	{ "ui_spAwards", "g_spAwards", "", bit32.bor(A, C.CVAR_ROM) },
	{ "ui_spVideos", "g_spVideos", "", bit32.bor(A, C.CVAR_ROM) },
	{ "ui_spSkill", "g_spSkill", "2", bit32.bor(A, C.CVAR_LATCH) },

	{ "ui_spSelection", "ui_spSelection", "", C.CVAR_ROM },

	{ "ui_browserMaster", "ui_browserMaster", "0", A },
	{ "ui_browserGameType", "ui_browserGameType", "0", A },
	{ "ui_browserSortKey", "ui_browserSortKey", "4", A },
	{ "ui_browserShowFull", "ui_browserShowFull", "1", A },
	{ "ui_browserShowEmpty", "ui_browserShowEmpty", "1", A },

	{ "ui_brassTime", "cg_brassTime", "2500", A },
	{ "ui_drawCrosshair", "cg_drawCrosshair", "4", A },
	{ "ui_drawCrosshairNames", "cg_drawCrosshairNames", "1", A },
	{ "ui_marks", "cg_marks", "1", A },
}

for n = 1, 16 do
	table.insert(cvarTable, { "ui_server" .. n, "server" .. n, "", A })
end

table.insert(cvarTable, { "ui_browserOnlyHumans", "ui_browserOnlyHumans", "0", A })
table.insert(cvarTable, { "ui_setupchecked", "ui_setupchecked", "0", A })

local cvarTableSize = #cvarTable

for _, cv in cvarTable do
	U[cv[1]] = T.vmCvar_t()
end

local function cvarOf(cv)
	return U[cv[1]]
end

--[[
=================
UI_RegisterCvars
=================
]]
function U.UI_RegisterCvars()
	for i = 1, cvarTableSize do
		local cv = cvarTable[i]
		trap.Cvar_Register(cvarOf(cv), cv[2], cv[3], cv[4])
	end
end

--[[
=================
UI_UpdateCvars
=================
]]
function U.UI_UpdateCvars()
	for i = 1, cvarTableSize do
		trap.Cvar_Update(cvarOf(cvarTable[i]))
	end
end

--[[
==================
 * UI_SetDefaultCvar
 * If the cvar is blank it will be set to value
 * This is only good for cvars that cannot naturally be blank
==================
]]
function U.UI_SetDefaultCvar(cvar, value)
	if #U.UI_Cvar_VariableString(cvar) == 0 then
		trap.Cvar_Set(cvar, value)
	end
end

return U
