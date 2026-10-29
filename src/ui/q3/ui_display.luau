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
-- Luau port of code/q3_ui/ui_display.c (OpenArena gamecode).

local U = require(script.Parent.U)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local ART_FRAMEL = "menu/" .. C.MENU_ART_DIR .. "/frame2_l"
local ART_FRAMER = "menu/" .. C.MENU_ART_DIR .. "/frame1_r"
local ART_BACK0 = "menu/" .. C.MENU_ART_DIR .. "/back_0"
local ART_BACK1 = "menu/" .. C.MENU_ART_DIR .. "/back_1"

local ID_GRAPHICS = 10
local ID_DISPLAY = 11
local ID_SOUND = 12
local ID_NETWORK = 13
local ID_BRIGHTNESS = 14
local ID_SCREENSIZE = 15
local ID_BACK = 16

local displayOptionsInfo

local function UI_DisplayOptionsMenu_Event(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	local id = ptr.generic.id
	if id == ID_GRAPHICS then
		U.UI_PopMenu()
		U.UI_GraphicsOptionsMenu()
	elseif id == ID_DISPLAY then
	elseif id == ID_SOUND then
		U.UI_PopMenu()
		U.UI_SoundOptionsMenu()
	elseif id == ID_NETWORK then
		U.UI_PopMenu()
		U.UI_NetworkOptionsMenu()
	elseif id == ID_BRIGHTNESS then
		trap.Cvar_SetValue("r_gamma", displayOptionsInfo.brightness.curvalue / 10.0)
	elseif id == ID_SCREENSIZE then
		trap.Cvar_SetValue("cg_viewsize", displayOptionsInfo.screensize.curvalue * 10)
	elseif id == ID_BACK then
		U.UI_PopMenu()
	end
end

local function UI_DisplayOptionsMenu_Init()
	displayOptionsInfo = {
		menu = T.menuframework_s(),
		banner = T.menutext_s(),
		framel = T.menubitmap_s(),
		framer = T.menubitmap_s(),
		graphics = T.menutext_s(),
		display = T.menutext_s(),
		sound = T.menutext_s(),
		network = T.menutext_s(),
		brightness = T.menuslider_s(),
		screensize = T.menuslider_s(),
		back = T.menubitmap_s(),
	}
	local info = displayOptionsInfo

	U.UI_DisplayOptionsMenu_Cache()
	info.menu.wrapAround = true
	info.menu.fullscreen = true

	info.banner.generic.type = C.MTYPE_BTEXT
	info.banner.generic.flags = C.QMF_CENTER_JUSTIFY
	info.banner.generic.x = 320
	info.banner.generic.y = 16
	info.banner.string = "SYSTEM SETUP"
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

	info.graphics.generic.type = C.MTYPE_PTEXT
	info.graphics.generic.flags = bit32.bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	info.graphics.generic.id = ID_GRAPHICS
	info.graphics.generic.callback = UI_DisplayOptionsMenu_Event
	info.graphics.generic.x = 216
	info.graphics.generic.y = 240 - 2 * C.PROP_HEIGHT
	info.graphics.string = "GRAPHICS"
	info.graphics.style = C.UI_RIGHT
	info.graphics.color = Q.colorRed

	info.display.generic.type = C.MTYPE_PTEXT
	info.display.generic.flags = C.QMF_RIGHT_JUSTIFY
	info.display.generic.id = ID_DISPLAY
	info.display.generic.callback = UI_DisplayOptionsMenu_Event
	info.display.generic.x = 216
	info.display.generic.y = 240 - C.PROP_HEIGHT
	info.display.string = "DISPLAY"
	info.display.style = C.UI_RIGHT
	info.display.color = Q.colorRed

	info.sound.generic.type = C.MTYPE_PTEXT
	info.sound.generic.flags = bit32.bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	info.sound.generic.id = ID_SOUND
	info.sound.generic.callback = UI_DisplayOptionsMenu_Event
	info.sound.generic.x = 216
	info.sound.generic.y = 240
	info.sound.string = "SOUND"
	info.sound.style = C.UI_RIGHT
	info.sound.color = Q.colorRed

	info.network.generic.type = C.MTYPE_PTEXT
	info.network.generic.flags = bit32.bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	info.network.generic.id = ID_NETWORK
	info.network.generic.callback = UI_DisplayOptionsMenu_Event
	info.network.generic.x = 216
	info.network.generic.y = 240 + C.PROP_HEIGHT
	info.network.string = "NETWORK"
	info.network.style = C.UI_RIGHT
	info.network.color = Q.colorRed

	local y = 240 - 1 * (C.BIGCHAR_HEIGHT + 2)
	info.brightness.generic.type = C.MTYPE_SLIDER
	info.brightness.generic.name = "Brightness:"
	info.brightness.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	info.brightness.generic.callback = UI_DisplayOptionsMenu_Event
	info.brightness.generic.id = ID_BRIGHTNESS
	info.brightness.generic.x = 400
	info.brightness.generic.y = y
	info.brightness.minvalue = 5
	info.brightness.maxvalue = 20
	if not U.uis.glconfig.deviceSupportsGamma then
		info.brightness.generic.flags = bit32.bor(info.brightness.generic.flags, C.QMF_GRAYED)
	end

	y += C.BIGCHAR_HEIGHT + 2
	info.screensize.generic.type = C.MTYPE_SLIDER
	info.screensize.generic.name = "Screen Size:"
	info.screensize.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	info.screensize.generic.callback = UI_DisplayOptionsMenu_Event
	info.screensize.generic.id = ID_SCREENSIZE
	info.screensize.generic.x = 400
	info.screensize.generic.y = y
	info.screensize.minvalue = 3
	info.screensize.maxvalue = 10

	info.back.generic.type = C.MTYPE_BITMAP
	info.back.generic.name = ART_BACK0
	info.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	info.back.generic.callback = UI_DisplayOptionsMenu_Event
	info.back.generic.id = ID_BACK
	info.back.generic.x = 0
	info.back.generic.y = 480 - 64
	info.back.width = 128
	info.back.height = 64
	info.back.focuspic = ART_BACK1

	U.Menu_AddItem(info.menu, info.banner)
	U.Menu_AddItem(info.menu, info.framel)
	U.Menu_AddItem(info.menu, info.framer)
	U.Menu_AddItem(info.menu, info.graphics)
	U.Menu_AddItem(info.menu, info.display)
	U.Menu_AddItem(info.menu, info.sound)
	U.Menu_AddItem(info.menu, info.network)
	U.Menu_AddItem(info.menu, info.brightness)
	U.Menu_AddItem(info.menu, info.screensize)
	U.Menu_AddItem(info.menu, info.back)

	info.brightness.curvalue = trap.Cvar_VariableValue("r_gamma") * 10
	info.screensize.curvalue = trap.Cvar_VariableValue("cg_viewsize") / 10
end

function U.UI_DisplayOptionsMenu_Cache()
	trap.R_RegisterShaderNoMip(ART_FRAMEL)
	trap.R_RegisterShaderNoMip(ART_FRAMER)
	trap.R_RegisterShaderNoMip(ART_BACK0)
	trap.R_RegisterShaderNoMip(ART_BACK1)
end

function U.UI_DisplayOptionsMenu()
	UI_DisplayOptionsMenu_Init()
	U.UI_PushMenu(displayOptionsInfo.menu)
	U.Menu_SetCursorToItem(displayOptionsInfo.menu, displayOptionsInfo.display)
end

return U
