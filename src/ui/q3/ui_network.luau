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
-- Luau port of code/q3_ui/ui_network.c (OpenArena gamecode).

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local ART_FRAMEL = "menu/" .. C.MENU_ART_DIR .. "/frame2_l"
local ART_FRAMER = "menu/" .. C.MENU_ART_DIR .. "/frame1_r"
local ART_BACK0 = "menu/" .. C.MENU_ART_DIR .. "/back_0"
local ART_BACK1 = "menu/" .. C.MENU_ART_DIR .. "/back_1"

local ID_GRAPHICS = 10
local ID_DISPLAY = 11
local ID_SOUND = 12
local ID_NETWORK = 13
local ID_RATE = 14
local ID_ALLOWDOWNLOAD = 15
local ID_LAGOMETER = 16
local ID_BACK = 17

local rate_items = {
	[0] = "<= 28.8K",
	"33.6K",
	"56K",
	"ISDN",
	"LAN/Cable/xDSL",
}

local networkOptionsInfo

local function newItem()
	return { generic = {} }
end

local function UI_NetworkOptionsMenu_Event(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	local id = ptr.generic.id
	if id == ID_GRAPHICS then
		U.UI_PopMenu()
		U.UI_GraphicsOptionsMenu()
	elseif id == ID_DISPLAY then
		U.UI_PopMenu()
		U.UI_DisplayOptionsMenu()
	elseif id == ID_SOUND then
		U.UI_PopMenu()
		U.UI_SoundOptionsMenu()
	elseif id == ID_NETWORK then
	elseif id == ID_RATE then
		local cv = networkOptionsInfo.rate.curvalue
		if cv == 0 then
			trap.Cvar_SetValue("rate", 2500)
		elseif cv == 1 then
			trap.Cvar_SetValue("rate", 3000)
		elseif cv == 2 then
			trap.Cvar_SetValue("rate", 4000)
		elseif cv == 3 then
			trap.Cvar_SetValue("rate", 5000)
		elseif cv == 4 then
			trap.Cvar_SetValue("rate", 25000)
		end
	elseif id == ID_ALLOWDOWNLOAD then
		trap.Cvar_SetValue("cl_allowDownload", networkOptionsInfo.allowdownload.curvalue)
		trap.Cvar_SetValue("sv_allowDownload", networkOptionsInfo.allowdownload.curvalue)
	elseif id == ID_LAGOMETER then
		trap.Cvar_SetValue("cg_lagometer", networkOptionsInfo.lagometer.curvalue)
	elseif id == ID_BACK then
		U.UI_PopMenu()
	end
end

local function UI_NetworkOptionsMenu_Init()
	networkOptionsInfo = {
		menu = { items = {}, nitems = 0 },
		banner = newItem(),
		framel = newItem(),
		framer = newItem(),
		graphics = newItem(),
		display = newItem(),
		sound = newItem(),
		network = newItem(),
		rate = newItem(),
		allowdownload = newItem(),
		lagometer = newItem(),
		back = newItem(),
	}
	local info = networkOptionsInfo

	U.UI_NetworkOptionsMenu_Cache()
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
	info.graphics.generic.callback = UI_NetworkOptionsMenu_Event
	info.graphics.generic.x = 216
	info.graphics.generic.y = 240 - 2 * C.PROP_HEIGHT
	info.graphics.string = "GRAPHICS"
	info.graphics.style = C.UI_RIGHT
	info.graphics.color = Q.colorRed

	info.display.generic.type = C.MTYPE_PTEXT
	info.display.generic.flags = bit32.bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	info.display.generic.id = ID_DISPLAY
	info.display.generic.callback = UI_NetworkOptionsMenu_Event
	info.display.generic.x = 216
	info.display.generic.y = 240 - C.PROP_HEIGHT
	info.display.string = "DISPLAY"
	info.display.style = C.UI_RIGHT
	info.display.color = Q.colorRed

	info.sound.generic.type = C.MTYPE_PTEXT
	info.sound.generic.flags = bit32.bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	info.sound.generic.id = ID_SOUND
	info.sound.generic.callback = UI_NetworkOptionsMenu_Event
	info.sound.generic.x = 216
	info.sound.generic.y = 240
	info.sound.string = "SOUND"
	info.sound.style = C.UI_RIGHT
	info.sound.color = Q.colorRed

	info.network.generic.type = C.MTYPE_PTEXT
	info.network.generic.flags = C.QMF_RIGHT_JUSTIFY
	info.network.generic.id = ID_NETWORK
	info.network.generic.callback = UI_NetworkOptionsMenu_Event
	info.network.generic.x = 216
	info.network.generic.y = 240 + C.PROP_HEIGHT
	info.network.string = "NETWORK"
	info.network.style = C.UI_RIGHT
	info.network.color = Q.colorRed

	local y = 240 - 1 * (C.BIGCHAR_HEIGHT + 2)
	info.rate.generic.type = C.MTYPE_SPINCONTROL
	info.rate.generic.name = "Data Rate:"
	info.rate.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	info.rate.generic.callback = UI_NetworkOptionsMenu_Event
	info.rate.generic.id = ID_RATE
	info.rate.generic.x = 400
	info.rate.generic.y = y
	info.rate.itemnames = rate_items
	info.rate.curvalue = 0

	y += C.BIGCHAR_HEIGHT + 2
	info.allowdownload.generic.type = C.MTYPE_RADIOBUTTON
	info.allowdownload.generic.name = "Auto Downloading:"
	info.allowdownload.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	info.allowdownload.generic.callback = UI_NetworkOptionsMenu_Event
	info.allowdownload.generic.id = ID_ALLOWDOWNLOAD
	info.allowdownload.generic.x = 400
	info.allowdownload.generic.y = y

	y += C.BIGCHAR_HEIGHT + 2
	info.lagometer.generic.type = C.MTYPE_RADIOBUTTON
	info.lagometer.generic.name = "Lagometer:"
	info.lagometer.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	info.lagometer.generic.callback = UI_NetworkOptionsMenu_Event
	info.lagometer.generic.id = ID_LAGOMETER
	info.lagometer.generic.x = 400
	info.lagometer.generic.y = y

	info.back.generic.type = C.MTYPE_BITMAP
	info.back.generic.name = ART_BACK0
	info.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	info.back.generic.callback = UI_NetworkOptionsMenu_Event
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
	U.Menu_AddItem(info.menu, info.rate)
	U.Menu_AddItem(info.menu, info.allowdownload)
	U.Menu_AddItem(info.menu, info.lagometer)
	U.Menu_AddItem(info.menu, info.back)

	local rate = Q.int(trap.Cvar_VariableValue("rate"))
	if rate <= 2500 then
		info.rate.curvalue = 0
	elseif rate <= 3000 then
		info.rate.curvalue = 1
	elseif rate <= 4000 then
		info.rate.curvalue = 2
	elseif rate <= 5000 then
		info.rate.curvalue = 3
	else
		info.rate.curvalue = 4
	end

	info.allowdownload.curvalue = Q.b2i(trap.Cvar_VariableValue("cl_allowDownload") ~= 0)
	info.lagometer.curvalue = Q.b2i(trap.Cvar_VariableValue("cg_lagometer") ~= 0)
end

function U.UI_NetworkOptionsMenu_Cache()
	trap.R_RegisterShaderNoMip(ART_FRAMEL)
	trap.R_RegisterShaderNoMip(ART_FRAMER)
	trap.R_RegisterShaderNoMip(ART_BACK0)
	trap.R_RegisterShaderNoMip(ART_BACK1)
end

function U.UI_NetworkOptionsMenu()
	UI_NetworkOptionsMenu_Init()
	U.UI_PushMenu(networkOptionsInfo.menu)
	U.Menu_SetCursorToItem(networkOptionsInfo.menu, networkOptionsInfo.network)
end

return U
