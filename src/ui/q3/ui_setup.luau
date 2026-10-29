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
-- Luau port of code/q3_ui/ui_setup.c (OpenArena gamecode).

local U = require(script.Parent.U)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local SETUP_MENU_VERTICAL_SPACING = 34

local ART_BACK0 = "menu/" .. C.MENU_ART_DIR .. "/back_0"
local ART_BACK1 = "menu/" .. C.MENU_ART_DIR .. "/back_1"
local ART_FRAMEL = "menu/" .. C.MENU_ART_DIR .. "/frame2_l"
local ART_FRAMER = "menu/" .. C.MENU_ART_DIR .. "/frame1_r"

local ID_CUSTOMIZEPLAYER = 10
local ID_CUSTOMIZECONTROLS = 11
local ID_SYSTEMCONFIG = 12
local ID_GAME = 13
local ID_DEFAULTS = 17
local ID_BACK = 18

local setupMenuInfo

local function Setup_ResetDefaults_Action(result)
	if not result then
		return
	end
	trap.Cmd_ExecuteText(C.EXEC_APPEND, "exec default.cfg\n")
	trap.Cmd_ExecuteText(C.EXEC_APPEND, "cvar_restart\n")
	trap.Cmd_ExecuteText(C.EXEC_APPEND, "vid_restart\n")
end

local function Setup_ResetDefaults_Draw()
	U.UI_DrawProportionalString(C.SCREEN_WIDTH / 2, 356 + C.PROP_HEIGHT * 0, "WARNING: This will reset *ALL*", bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), Q.colorYellow)
	U.UI_DrawProportionalString(C.SCREEN_WIDTH / 2, 356 + C.PROP_HEIGHT * 1, "options to their default values.", bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), Q.colorYellow)
end

local function UI_SetupMenu_Event(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	local id = ptr.generic.id
	if id == ID_CUSTOMIZEPLAYER then
		U.UI_PlayerSettingsMenu()
	elseif id == ID_CUSTOMIZECONTROLS then
		U.UI_ControlsMenu()
	elseif id == ID_SYSTEMCONFIG then
		U.UI_GraphicsOptionsMenu()
	elseif id == ID_GAME then
		U.UI_PreferencesMenu()
	elseif id == ID_DEFAULTS then
		U.UI_ConfirmMenu("SET TO DEFAULTS?", Setup_ResetDefaults_Draw, Setup_ResetDefaults_Action)
	elseif id == ID_BACK then
		U.UI_PopMenu()
	end
end

local function setupText(item, y, id, str)
	item.generic.type = C.MTYPE_PTEXT
	item.generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_PULSEIFFOCUS)
	item.generic.x = 320
	item.generic.y = y
	item.generic.id = id
	item.generic.callback = UI_SetupMenu_Event
	item.string = str
	item.color = Q.colorRed
	item.style = C.UI_CENTER
end

local function UI_SetupMenu_Init()
	U.UI_SetupMenu_Cache()

	setupMenuInfo = {
		menu = T.menuframework_s(),
		banner = T.menutext_s(),
		framel = T.menubitmap_s(),
		framer = T.menubitmap_s(),
		setupplayer = T.menutext_s(),
		setupcontrols = T.menutext_s(),
		setupsystem = T.menutext_s(),
		game = T.menutext_s(),
		defaults = T.menutext_s(),
		back = T.menubitmap_s(),
	}
	local info = setupMenuInfo
	info.menu.wrapAround = true
	info.menu.fullscreen = true

	info.banner.generic.type = C.MTYPE_BTEXT
	info.banner.generic.x = 320
	info.banner.generic.y = 16
	info.banner.string = "SETUP"
	info.banner.color = Q.colorWhite
	info.banner.style = C.UI_CENTER

	info.framel.generic.type = C.MTYPE_BITMAP
	info.framel.generic.name = ART_FRAMEL
	info.framel.generic.flags = C.QMF_INACTIVE
	info.framel.generic.x = 0
	info.framel.generic.y = 78
	info.framel.width = 256
	info.framel.height = 329

	info.framer.generic.type = C.MTYPE_BITMAP
	info.framer.generic.name = ART_FRAMER
	info.framer.generic.flags = C.QMF_INACTIVE
	info.framer.generic.x = 376
	info.framer.generic.y = 76
	info.framer.width = 256
	info.framer.height = 334

	local y = 134
	setupText(info.setupplayer, y, ID_CUSTOMIZEPLAYER, "PLAYER")

	y += SETUP_MENU_VERTICAL_SPACING
	setupText(info.setupcontrols, y, ID_CUSTOMIZECONTROLS, "CONTROLS")

	y += SETUP_MENU_VERTICAL_SPACING
	setupText(info.setupsystem, y, ID_SYSTEMCONFIG, "SYSTEM")

	y += SETUP_MENU_VERTICAL_SPACING
	setupText(info.game, y, ID_GAME, "GAME OPTIONS")

	if trap.Cvar_VariableValue("cl_paused") == 0 then
		y += SETUP_MENU_VERTICAL_SPACING
		setupText(info.defaults, y, ID_DEFAULTS, "DEFAULTS")
	end

	info.back.generic.type = C.MTYPE_BITMAP
	info.back.generic.name = ART_BACK0
	info.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	info.back.generic.id = ID_BACK
	info.back.generic.callback = UI_SetupMenu_Event
	info.back.generic.x = 0
	info.back.generic.y = 480 - 64
	info.back.width = 128
	info.back.height = 64
	info.back.focuspic = ART_BACK1

	U.Menu_AddItem(info.menu, info.banner)
	U.Menu_AddItem(info.menu, info.framel)
	U.Menu_AddItem(info.menu, info.framer)
	U.Menu_AddItem(info.menu, info.setupplayer)
	U.Menu_AddItem(info.menu, info.setupcontrols)
	U.Menu_AddItem(info.menu, info.setupsystem)
	U.Menu_AddItem(info.menu, info.game)
	if trap.Cvar_VariableValue("cl_paused") == 0 then
		U.Menu_AddItem(info.menu, info.defaults)
	end
	U.Menu_AddItem(info.menu, info.back)
end

function U.UI_SetupMenu_Cache()
	trap.R_RegisterShaderNoMip(ART_BACK0)
	trap.R_RegisterShaderNoMip(ART_BACK1)
	trap.R_RegisterShaderNoMip(ART_FRAMEL)
	trap.R_RegisterShaderNoMip(ART_FRAMER)
end

function U.UI_SetupMenu()
	UI_SetupMenu_Init()
	U.UI_PushMenu(setupMenuInfo.menu)
end

return U
