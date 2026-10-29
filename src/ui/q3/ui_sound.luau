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
-- Luau port of code/q3_ui/ui_sound.c (OpenArena 0.8.8, gamecode 9e0f0c0).

local U = require(script.Parent.U)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local ART_FRAMEL = "menu/art_blueish/frame2_l"
local ART_FRAMER = "menu/art_blueish/frame1_r"
local ART_BACK0 = "menu/art_blueish/back_0"
local ART_BACK1 = "menu/art_blueish/back_1"

local ID_GRAPHICS = 10
local ID_DISPLAY = 11
local ID_SOUND = 12
local ID_NETWORK = 13
local ID_EFFECTSVOLUME = 14
local ID_MUSICVOLUME = 15
local ID_QUALITY = 16
local ID_OPENAL = 18
local ID_BACK = 19

local quality_items = { [0] = "Low", [1] = "High" }

local soundOptionsInfo

local function UI_SoundOptionsMenu_Event(ptr, event)
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
	elseif id == ID_NETWORK then
		U.UI_PopMenu()
		U.UI_NetworkOptionsMenu()
	elseif id == ID_EFFECTSVOLUME then
		trap.Cvar_SetValue("s_volume", soundOptionsInfo.sfxvolume.curvalue / 10)
	elseif id == ID_MUSICVOLUME then
		trap.Cvar_SetValue("s_musicvolume", soundOptionsInfo.musicvolume.curvalue / 10)
	elseif id == ID_QUALITY then
		if soundOptionsInfo.quality.curvalue ~= 0 then
			trap.Cvar_SetValue("s_khz", 22)
			trap.Cvar_SetValue("s_compression", 0)
		else
			trap.Cvar_SetValue("s_khz", 11)
			trap.Cvar_SetValue("s_compression", 1)
		end
		U.UI_ForceMenuOff()
		trap.Cmd_ExecuteText(C.EXEC_APPEND, "snd_restart\n")
	elseif id == ID_OPENAL then
		if soundOptionsInfo.openal.curvalue ~= 0 then
			trap.Cmd_ExecuteText(C.EXEC_NOW, "s_useopenal 1\n")
		else
			trap.Cmd_ExecuteText(C.EXEC_NOW, "s_useopenal 0\n")
		end
		soundOptionsInfo.openal.curvalue = Q.int(trap.Cvar_VariableValue("s_useopenal"))
	elseif id == ID_BACK then
		U.UI_PopMenu()
	end
end

local function UI_SoundOptionsMenu_Init()
	soundOptionsInfo = {
		menu = T.menuframework_s(),
		banner = T.menutext_s(),
		framel = T.menubitmap_s(),
		framer = T.menubitmap_s(),
		graphics = T.menutext_s(),
		display = T.menutext_s(),
		sound = T.menutext_s(),
		network = T.menutext_s(),
		sfxvolume = T.menuslider_s(),
		musicvolume = T.menuslider_s(),
		quality = T.menulist_s(),
		openal = T.menuradiobutton_s(),
		back = T.menubitmap_s(),
	}
	local info = soundOptionsInfo

	U.UI_SoundOptionsMenu_Cache()
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
	info.graphics.generic.callback = UI_SoundOptionsMenu_Event
	info.graphics.generic.x = 216
	info.graphics.generic.y = 240 - 2 * C.PROP_HEIGHT
	info.graphics.string = "GRAPHICS"
	info.graphics.style = C.UI_RIGHT
	info.graphics.color = Q.colorRed

	info.display.generic.type = C.MTYPE_PTEXT
	info.display.generic.flags = bit32.bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	info.display.generic.id = ID_DISPLAY
	info.display.generic.callback = UI_SoundOptionsMenu_Event
	info.display.generic.x = 216
	info.display.generic.y = 240 - C.PROP_HEIGHT
	info.display.string = "DISPLAY"
	info.display.style = C.UI_RIGHT
	info.display.color = Q.colorRed

	info.sound.generic.type = C.MTYPE_PTEXT
	info.sound.generic.flags = C.QMF_RIGHT_JUSTIFY
	info.sound.generic.id = ID_SOUND
	info.sound.generic.callback = UI_SoundOptionsMenu_Event
	info.sound.generic.x = 216
	info.sound.generic.y = 240
	info.sound.string = "SOUND"
	info.sound.style = C.UI_RIGHT
	info.sound.color = Q.colorRed

	info.network.generic.type = C.MTYPE_PTEXT
	info.network.generic.flags = bit32.bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	info.network.generic.id = ID_NETWORK
	info.network.generic.callback = UI_SoundOptionsMenu_Event
	info.network.generic.x = 216
	info.network.generic.y = 240 + C.PROP_HEIGHT
	info.network.string = "NETWORK"
	info.network.style = C.UI_RIGHT
	info.network.color = Q.colorRed

	local y = Q.int(240 - 1.5 * (C.BIGCHAR_HEIGHT + 2))
	info.sfxvolume.generic.type = C.MTYPE_SLIDER
	info.sfxvolume.generic.name = "Effects Volume:"
	info.sfxvolume.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	info.sfxvolume.generic.callback = UI_SoundOptionsMenu_Event
	info.sfxvolume.generic.id = ID_EFFECTSVOLUME
	info.sfxvolume.generic.x = 400
	info.sfxvolume.generic.y = y
	info.sfxvolume.minvalue = 0
	info.sfxvolume.maxvalue = 10

	y += C.BIGCHAR_HEIGHT + 2
	info.musicvolume.generic.type = C.MTYPE_SLIDER
	info.musicvolume.generic.name = "Music Volume:"
	info.musicvolume.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	info.musicvolume.generic.callback = UI_SoundOptionsMenu_Event
	info.musicvolume.generic.id = ID_MUSICVOLUME
	info.musicvolume.generic.x = 400
	info.musicvolume.generic.y = y
	info.musicvolume.minvalue = 0
	info.musicvolume.maxvalue = 10

	y += C.BIGCHAR_HEIGHT + 2
	info.quality.generic.type = C.MTYPE_SPINCONTROL
	info.quality.generic.name = "Sound Quality:"
	info.quality.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	info.quality.generic.callback = UI_SoundOptionsMenu_Event
	info.quality.generic.id = ID_QUALITY
	info.quality.generic.x = 400
	info.quality.generic.y = y
	info.quality.itemnames = quality_items

	y += C.BIGCHAR_HEIGHT + 2
	info.openal.generic.type = C.MTYPE_RADIOBUTTON
	info.openal.generic.name = "OpenAL:"
	info.openal.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	info.openal.generic.callback = UI_SoundOptionsMenu_Event
	info.openal.generic.id = ID_OPENAL
	info.openal.generic.x = 400
	info.openal.generic.y = y

	info.back.generic.type = C.MTYPE_BITMAP
	info.back.generic.name = ART_BACK0
	info.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	info.back.generic.callback = UI_SoundOptionsMenu_Event
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
	U.Menu_AddItem(info.menu, info.sfxvolume)
	U.Menu_AddItem(info.menu, info.musicvolume)
	U.Menu_AddItem(info.menu, info.quality)
	U.Menu_AddItem(info.menu, info.openal)
	U.Menu_AddItem(info.menu, info.back)

	info.sfxvolume.curvalue = trap.Cvar_VariableValue("s_volume") * 10
	info.musicvolume.curvalue = trap.Cvar_VariableValue("s_musicvolume") * 10
	info.quality.curvalue = if trap.Cvar_VariableValue("s_compression") == 0 then 1 else 0
	info.openal.curvalue = Q.int(trap.Cvar_VariableValue("s_useopenal"))
end

function U.UI_SoundOptionsMenu_Cache()
	trap.R_RegisterShaderNoMip(ART_FRAMEL)
	trap.R_RegisterShaderNoMip(ART_FRAMER)
	trap.R_RegisterShaderNoMip(ART_BACK0)
	trap.R_RegisterShaderNoMip(ART_BACK1)
end

function U.UI_SoundOptionsMenu()
	UI_SoundOptionsMenu_Init()
	U.UI_PushMenu(soundOptionsInfo.menu)
	U.Menu_SetCursorToItem(soundOptionsInfo.menu, soundOptionsInfo.sound)
end

return U
