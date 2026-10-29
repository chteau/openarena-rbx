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
-- Luau port of code/q3_ui/ui_serverinfo.c (OpenArena 0.8.8, gamecode 9e0f0c0).

local U = require(script.Parent.U)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local Q = require(script.Parent.Parent.Parent.client.q.Q)

local SERVERINFO_FRAMEL = "menu/art_blueish/frame2_l"
local SERVERINFO_FRAMER = "menu/art_blueish/frame1_r"
local SERVERINFO_BACK0 = "menu/art_blueish/back_0"
local SERVERINFO_BACK1 = "menu/art_blueish/back_1"

local serverinfo_artlist = {
	[0] = SERVERINFO_FRAMEL,
	SERVERINFO_FRAMER,
	SERVERINFO_BACK0,
	SERVERINFO_BACK1,
}

local ID_ADD = 100
local ID_BACK = 101

local function newMenu()
	return { items = {}, nitems = 0, cursor = 0, cursor_prev = 0, wrapAround = false, fullscreen = false }
end

local function newItem()
	return { generic = { flags = 0, id = 0, x = 0, y = 0 } }
end

local s_serverinfo = {
	menu = newMenu(),
	banner = newItem(),
	framel = newItem(),
	framer = newItem(),
	back = newItem(),
	add = newItem(),
	info = "",
	numlines = 0,
}

-- Returns remaining string, key, value ("" key at the end).
local function Info_NextPair(s)
	if string.sub(s, 1, 1) == "\\" then
		s = string.sub(s, 2)
	end
	if s == "" then
		return "", "", ""
	end
	local sep = string.find(s, "\\", 1, true)
	if sep == nil then
		return "", s, ""
	end
	local key = string.sub(s, 1, sep - 1)
	s = string.sub(s, sep + 1)
	local nxt = string.find(s, "\\", 1, true)
	if nxt == nil then
		return "", key, s
	end
	return string.sub(s, nxt), key, string.sub(s, 1, nxt - 1)
end

-- Add current server to favorites
function U.Favorites_Add()
	local serverbuff = trap.Cvar_VariableStringBuffer("cl_currentServerAddress")
	if serverbuff == "" then
		return
	end

	local best = 0
	for i = 0, C.MAX_FAVORITESERVERS - 1 do
		local adrstr = trap.Cvar_VariableStringBuffer(string.format("server%d", i + 1))
		if Q.stricmp(serverbuff, adrstr) == 0 then
			-- already in list
			return
		end

		-- use first empty or non-numeric available slot
		local c = string.byte(adrstr, 1)
		if (c == nil or c < 48 or c > 57) and best == 0 then
			best = i + 1
		end
	end

	if best ~= 0 then
		trap.Cvar_Set(string.format("server%d", best), serverbuff)
	end
end

local function ServerInfo_Event(ptr, event)
	local id = ptr.generic.id
	if id == ID_ADD then
		if event ~= C.QM_ACTIVATED then
			return
		end
		U.Favorites_Add()
		U.UI_PopMenu()
	elseif id == ID_BACK then
		if event ~= C.QM_ACTIVATED then
			return
		end
		U.UI_PopMenu()
	end
end

local function ServerInfo_MenuDraw()
	local i = 0
	local y = C.SCREEN_HEIGHT / 2 - s_serverinfo.numlines * C.SMALLCHAR_HEIGHT / 2 - 20
	local s = s_serverinfo.info
	while s ~= "" and i < s_serverinfo.numlines do
		local key, value
		s, key, value = Info_NextPair(s)
		if key == "" then
			break
		end

		key = key .. ":"

		U.UI_DrawString(C.SCREEN_WIDTH * 0.50 - 8, y, key, bit32.bor(C.UI_RIGHT, C.UI_SMALLFONT), U.color_red)
		U.UI_DrawString(C.SCREEN_WIDTH * 0.50 + 8, y, value, bit32.bor(C.UI_LEFT, C.UI_SMALLFONT), U.text_color_normal)

		y += C.SMALLCHAR_HEIGHT
		i += 1
	end

	U.Menu_Draw(s_serverinfo.menu)
end

local function ServerInfo_MenuKey(key)
	return U.Menu_DefaultKey(s_serverinfo.menu, key)
end

function U.ServerInfo_Cache()
	-- touch all our pics
	local i = 0
	while serverinfo_artlist[i] ~= nil do
		trap.R_RegisterShaderNoMip(serverinfo_artlist[i])
		i += 1
	end
end

function U.UI_ServerInfoMenu()
	-- zero set all our globals
	s_serverinfo.menu = newMenu()
	s_serverinfo.banner = newItem()
	s_serverinfo.framel = newItem()
	s_serverinfo.framer = newItem()
	s_serverinfo.back = newItem()
	s_serverinfo.add = newItem()
	s_serverinfo.info = ""
	s_serverinfo.numlines = 0

	U.ServerInfo_Cache()

	s_serverinfo.menu.draw = ServerInfo_MenuDraw
	s_serverinfo.menu.key = ServerInfo_MenuKey
	s_serverinfo.menu.wrapAround = true
	s_serverinfo.menu.fullscreen = true

	s_serverinfo.banner.generic.type = C.MTYPE_BTEXT
	s_serverinfo.banner.generic.x = 320
	s_serverinfo.banner.generic.y = 16
	s_serverinfo.banner.string = "SERVER INFO"
	s_serverinfo.banner.color = U.color_white
	s_serverinfo.banner.style = C.UI_CENTER

	s_serverinfo.framel.generic.type = C.MTYPE_BITMAP
	s_serverinfo.framel.generic.name = SERVERINFO_FRAMEL
	s_serverinfo.framel.generic.flags = C.QMF_INACTIVE
	s_serverinfo.framel.generic.x = 0
	s_serverinfo.framel.generic.y = 78
	s_serverinfo.framel.width = 256
	s_serverinfo.framel.height = 329

	s_serverinfo.framer.generic.type = C.MTYPE_BITMAP
	s_serverinfo.framer.generic.name = SERVERINFO_FRAMER
	s_serverinfo.framer.generic.flags = C.QMF_INACTIVE
	s_serverinfo.framer.generic.x = 376
	s_serverinfo.framer.generic.y = 76
	s_serverinfo.framer.width = 256
	s_serverinfo.framer.height = 334

	s_serverinfo.add.generic.type = C.MTYPE_PTEXT
	s_serverinfo.add.generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s_serverinfo.add.generic.callback = ServerInfo_Event
	s_serverinfo.add.generic.id = ID_ADD
	s_serverinfo.add.generic.x = 320
	s_serverinfo.add.generic.y = 371
	s_serverinfo.add.string = "ADD TO FAVORITES"
	s_serverinfo.add.style = bit32.bor(C.UI_CENTER, C.UI_SMALLFONT)
	s_serverinfo.add.color = U.color_red
	if trap.Cvar_VariableValue("sv_running") ~= 0 then
		s_serverinfo.add.generic.flags = bit32.bor(s_serverinfo.add.generic.flags, C.QMF_GRAYED)
	end

	s_serverinfo.back.generic.type = C.MTYPE_BITMAP
	s_serverinfo.back.generic.name = SERVERINFO_BACK0
	s_serverinfo.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s_serverinfo.back.generic.callback = ServerInfo_Event
	s_serverinfo.back.generic.id = ID_BACK
	s_serverinfo.back.generic.x = 0
	s_serverinfo.back.generic.y = 480 - 64
	s_serverinfo.back.width = 128
	s_serverinfo.back.height = 64
	s_serverinfo.back.focuspic = SERVERINFO_BACK1

	s_serverinfo.info = trap.GetConfigString(C.CS_SERVERINFO)

	s_serverinfo.numlines = 0
	local s = s_serverinfo.info
	while s ~= "" do
		local key
		s, key = Info_NextPair(s)
		if key == "" then
			break
		end
		s_serverinfo.numlines += 1
	end

	if s_serverinfo.numlines > 16 then
		s_serverinfo.numlines = 16
	end

	U.Menu_AddItem(s_serverinfo.menu, s_serverinfo.banner)
	U.Menu_AddItem(s_serverinfo.menu, s_serverinfo.framel)
	U.Menu_AddItem(s_serverinfo.menu, s_serverinfo.framer)
	U.Menu_AddItem(s_serverinfo.menu, s_serverinfo.add)
	U.Menu_AddItem(s_serverinfo.menu, s_serverinfo.back)

	U.UI_PushMenu(s_serverinfo.menu)
end

return U
