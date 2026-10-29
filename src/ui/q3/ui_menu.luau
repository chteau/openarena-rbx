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
-- Luau port of code/q3_ui/ui_menu.c (OpenArena 0.8.8, gamecode 9e0f0c0).

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local ID_SINGLEPLAYER = 10
local ID_MULTIPLAYER = 11
local ID_SETUP = 12
local ID_DEMOS = 13
local ID_CHALLENGES = 14
local ID_TEAMARENA = 15
local ID_MODS = 16
local ID_EXIT = 17

local MAIN_BANNER_MODEL = "models/mapobjects/banner/banner5.md3"
local MAIN_MENU_VERTICAL_SPACING = 34

local function newMenu()
	return { items = {}, nitems = 0, cursor = 0, cursor_prev = 0 }
end

local function newText()
	return { generic = {}, string = "", color = nil, style = 0 }
end

local function newMain()
	return {
		menu = newMenu(),
		singleplayer = newText(),
		multiplayer = newText(),
		setup = newText(),
		demos = newText(),
		challenges = newText(),
		teamArena = newText(),
		mods = newText(),
		exit = newText(),
		bannerModel = 0,
	}
end

local s_main = newMain()
local s_errorMessage = { menu = newMenu(), errorMessage = "" }

function U.Main_MenuEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	local id = ptr.generic.id
	if id == ID_SINGLEPLAYER then
		U.UI_SPLevelMenu()
	elseif id == ID_MULTIPLAYER then
		if U.ui_setupchecked.integer ~= 0 then
			U.UI_ArenaServersMenu()
		else
			U.UI_FirstConnectMenu()
		end
	elseif id == ID_SETUP then
		U.UI_SetupMenu()
	elseif id == ID_DEMOS then
		U.UI_DemosMenu()
	elseif id == ID_CHALLENGES then
		U.UI_Challenges()
	elseif id == ID_MODS then
		U.UI_ModsMenu()
	elseif id == ID_TEAMARENA then
		trap.Cvar_Set("fs_game", "missionpack")
		trap.Cmd_ExecuteText(C.EXEC_APPEND, "vid_restart;")
	elseif id == ID_EXIT then
		U.UI_CreditMenu()
	end
end

function U.MainMenu_Cache()
	s_main.bannerModel = trap.R_RegisterModel(MAIN_BANNER_MODEL)
end

function U.ErrorMessage_Key(key)
	trap.Cvar_Set("com_errorMessage", "")
	U.UI_MainMenu()
	return U.menu_null_sound
end

-- this function is common to the main menu and errorMessage menu
local function Main_MenuDraw()
	local refdef = T.refdef_t()
	local ent = T.refEntity_t()
	local origin = Q.vec3(0, 0, 0)
	local angles = Q.vec3(0, 0, 0)
	local color = { [0] = 0.2, [1] = 0.2, [2] = 1.0, [3] = 1 }

	refdef.rdflags = C.RDF_NOWORLDMODEL

	Q.AxisClear(refdef.viewaxis)

	local x, y, w, h = U.UI_AdjustFrom640(0, 0, 640, 120)
	refdef.x = x
	refdef.y = y
	refdef.width = w
	refdef.height = h

	local adjust = 0
	refdef.fov_x = 60 + adjust
	refdef.fov_y = 19.6875 + adjust

	refdef.time = U.uis.realtime

	origin[0] = 300
	origin[1] = 0
	origin[2] = -32

	trap.R_ClearScene()

	adjust = 5.0 * math.sin(U.uis.realtime / 5000)
	Q.VectorSet(angles, 0, 180 + adjust, 0)
	Q.AnglesToAxis(angles, ent.axis)
	ent.hModel = s_main.bannerModel
	Q.VectorCopy(origin, ent.origin)
	Q.VectorCopy(origin, ent.lightingOrigin)
	ent.renderfx = bit32.bor(C.RF_LIGHTING_ORIGIN, C.RF_NOSHADOW)
	Q.VectorCopy(ent.origin, ent.oldorigin)

	trap.R_AddRefEntityToScene(ent)

	trap.R_RenderScene(refdef)

	if #s_errorMessage.errorMessage ~= 0 then
		U.UI_DrawProportionalString_AutoWrapped(320, 192, 600, 20, s_errorMessage.errorMessage,
			bit32.bor(C.UI_CENTER, C.UI_SMALLFONT, C.UI_DROPSHADOW), U.menu_text_color)
	else
		U.Menu_Draw(s_main.menu)
	end

	local fmt = bit32.bor(C.UI_CENTER, C.UI_SMALLFONT)
	U.UI_DrawProportionalString(320, 372, "", fmt, color)
	U.UI_DrawString(320, 400, "OpenArena(c) 2005-2012 OpenArena Team", fmt, color)
	U.UI_DrawString(320, 414, "OpenArena comes with ABSOLUTELY NO WARRANTY; this is free software", fmt, color)
	U.UI_DrawString(320, 428, "and you are welcome to redistribute it under certain conditions;", fmt, color)
	U.UI_DrawString(320, 444, "read COPYING for details.", fmt, color)

	-- 9e0f0c0 says "^7OAX" here; the 0.8.8 release ui.qvm draws "^70.8.8"
	U.UI_DrawString(640 - 40, 480 - 14, "^70.8.8", C.UI_SMALLFONT, color)
	if Q.int(trap.Cvar_VariableValue("protocol")) ~= 71 then
		U.UI_DrawString(0, 480 - 14, Q.va("^7Protocol: %i", Q.int(trap.Cvar_VariableValue("protocol"))), C.UI_SMALLFONT, color)
	end
end

local function UI_TeamArenaExists()
	local numdirs, dirlist = trap.FS_GetFileList("$modlist", "")
	for i = 0, numdirs - 1 do
		if dirlist[i] == "missionpack" then
			return true
		end
	end
	return false
end

local function setupItem(item, y, id, str, style)
	item.generic.type = C.MTYPE_PTEXT
	item.generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_PULSEIFFOCUS)
	item.generic.x = 320
	item.generic.y = y
	item.generic.id = id
	item.generic.callback = U.Main_MenuEvent
	item.string = str
	item.color = U.color_red
	item.style = style
end

--[[
The main menu only comes up when not in a game,
so make sure that the attract loop server is down
and that local cinematics are killed
]]
function U.UI_MainMenu()
	local teamArena = false
	local style = bit32.bor(C.UI_CENTER, C.UI_DROPSHADOW)

	trap.Cvar_Set("sv_killserver", "1")
	trap.Cvar_SetValue("handicap", 100)

	s_main = newMain()
	s_errorMessage = { menu = newMenu(), errorMessage = "" }

	U.MainMenu_Cache()

	s_errorMessage.errorMessage = trap.Cvar_VariableStringBuffer("com_errorMessage")
	if #s_errorMessage.errorMessage ~= 0 then
		s_errorMessage.menu.draw = Main_MenuDraw
		s_errorMessage.menu.key = U.ErrorMessage_Key
		s_errorMessage.menu.fullscreen = true
		s_errorMessage.menu.wrapAround = true
		s_errorMessage.menu.showlogo = true

		trap.Key_SetCatcher(C.KEYCATCH_UI)
		U.uis.menusp = 0
		U.UI_PushMenu(s_errorMessage.menu)

		return
	end

	s_main.menu.draw = Main_MenuDraw
	s_main.menu.fullscreen = true
	s_main.menu.wrapAround = true
	s_main.menu.showlogo = true

	local y = 134
	setupItem(s_main.singleplayer, y, ID_SINGLEPLAYER, "SINGLE PLAYER", style)

	y += MAIN_MENU_VERTICAL_SPACING
	setupItem(s_main.multiplayer, y, ID_MULTIPLAYER, "MULTIPLAYER", style)

	y += MAIN_MENU_VERTICAL_SPACING
	setupItem(s_main.setup, y, ID_SETUP, "SETUP", style)

	y += MAIN_MENU_VERTICAL_SPACING
	setupItem(s_main.demos, y, ID_DEMOS, "DEMOS", style)

	y += MAIN_MENU_VERTICAL_SPACING
	setupItem(s_main.challenges, y, ID_CHALLENGES, "STATISTICS", style)

	if UI_TeamArenaExists() then
		teamArena = true
		y += MAIN_MENU_VERTICAL_SPACING
		setupItem(s_main.teamArena, y, ID_TEAMARENA, "MISSION PACK", style)
	end

	y += MAIN_MENU_VERTICAL_SPACING
	setupItem(s_main.mods, y, ID_MODS, "MODS", style)

	y += MAIN_MENU_VERTICAL_SPACING
	setupItem(s_main.exit, y, ID_EXIT, "EXIT", style)

	U.Menu_AddItem(s_main.menu, s_main.singleplayer)
	U.Menu_AddItem(s_main.menu, s_main.multiplayer)
	U.Menu_AddItem(s_main.menu, s_main.setup)
	U.Menu_AddItem(s_main.menu, s_main.demos)
	U.Menu_AddItem(s_main.menu, s_main.challenges)
	if teamArena then
		U.Menu_AddItem(s_main.menu, s_main.teamArena)
	end
	U.Menu_AddItem(s_main.menu, s_main.mods)
	U.Menu_AddItem(s_main.menu, s_main.exit)

	trap.Key_SetCatcher(C.KEYCATCH_UI)
	U.uis.menusp = 0
	U.UI_PushMenu(s_main.menu)
end

return U
