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
-- Luau port of code/q3_ui/ui_specifyserver.c (OpenArena 0.8.8, gamecode 9e0f0c0).

local U = require(script.Parent.U)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local bor = bit32.bor

--[[
*********************************************************************************
	SPECIFY SERVER
*********************************************************************************
]]

local SPECIFYSERVER_FRAMEL = "menu/art_blueish/frame2_l"
local SPECIFYSERVER_FRAMER = "menu/art_blueish/frame1_r"
local SPECIFYSERVER_BACK0 = "menu/art_blueish/back_0"
local SPECIFYSERVER_BACK1 = "menu/art_blueish/back_1"
local SPECIFYSERVER_FIGHT0 = "menu/art_blueish/fight_0"
local SPECIFYSERVER_FIGHT1 = "menu/art_blueish/fight_1"

local ID_SPECIFYSERVERBACK = 102
local ID_SPECIFYSERVERGO = 103

local specifyserver_artlist = {
	[0] = SPECIFYSERVER_FRAMEL,
	SPECIFYSERVER_FRAMER,
	SPECIFYSERVER_BACK0,
	SPECIFYSERVER_BACK1,
	SPECIFYSERVER_FIGHT0,
	SPECIFYSERVER_FIGHT1,
}

-- specifyserver_t, zeroed
local function newSpecifyserver()
	return {
		menu = T.menuframework_s(),
		banner = T.menutext_s(),
		framel = T.menubitmap_s(),
		framer = T.menubitmap_s(),
		domain = T.menufield_s(),
		port = T.menufield_s(),
		go = T.menubitmap_s(),
		back = T.menubitmap_s(),
	}
end

local s_specifyserver = newSpecifyserver()

--[[
=================
SpecifyServer_Event
=================
]]
local function SpecifyServer_Event(ptr, event)
	local id = ptr.generic.id
	if id == ID_SPECIFYSERVERGO then
		if event ~= C.QM_ACTIVATED then
			return
		end

		if s_specifyserver.domain.field.buffer ~= "" then
			local buff = s_specifyserver.domain.field.buffer
			if s_specifyserver.port.field.buffer ~= "" then
				buff ..= string.sub(Q.va(":%s", s_specifyserver.port.field.buffer), 1, 127)
			end

			trap.Cmd_ExecuteText(C.EXEC_APPEND, Q.va("connect %s\n", buff))
		end
	elseif id == ID_SPECIFYSERVERBACK then
		if event ~= C.QM_ACTIVATED then
			return
		end

		U.UI_PopMenu()
	end
end

--[[
=================
SpecifyServer_MenuInit
=================
]]
function U.SpecifyServer_MenuInit()
	-- zero set all our globals
	s_specifyserver = newSpecifyserver()

	U.SpecifyServer_Cache()

	s_specifyserver.menu.wrapAround = true
	s_specifyserver.menu.fullscreen = true

	s_specifyserver.banner.generic.type = C.MTYPE_BTEXT
	s_specifyserver.banner.generic.x = 320
	s_specifyserver.banner.generic.y = 16
	s_specifyserver.banner.string = "SPECIFY SERVER"
	s_specifyserver.banner.color = U.color_white
	s_specifyserver.banner.style = C.UI_CENTER

	s_specifyserver.framel.generic.type = C.MTYPE_BITMAP
	s_specifyserver.framel.generic.name = SPECIFYSERVER_FRAMEL
	s_specifyserver.framel.generic.flags = C.QMF_INACTIVE
	s_specifyserver.framel.generic.x = 0
	s_specifyserver.framel.generic.y = 78
	s_specifyserver.framel.width = 256
	s_specifyserver.framel.height = 329

	s_specifyserver.framer.generic.type = C.MTYPE_BITMAP
	s_specifyserver.framer.generic.name = SPECIFYSERVER_FRAMER
	s_specifyserver.framer.generic.flags = C.QMF_INACTIVE
	s_specifyserver.framer.generic.x = 376
	s_specifyserver.framer.generic.y = 76
	s_specifyserver.framer.width = 256
	s_specifyserver.framer.height = 334

	s_specifyserver.domain.generic.type = C.MTYPE_FIELD
	s_specifyserver.domain.generic.name = "Address:"
	s_specifyserver.domain.generic.flags = bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	s_specifyserver.domain.generic.x = 206
	s_specifyserver.domain.generic.y = 220
	s_specifyserver.domain.field.widthInChars = 38
	s_specifyserver.domain.field.maxchars = 80

	s_specifyserver.port.generic.type = C.MTYPE_FIELD
	s_specifyserver.port.generic.name = "Port:"
	s_specifyserver.port.generic.flags = bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT, C.QMF_NUMBERSONLY)
	s_specifyserver.port.generic.x = 206
	s_specifyserver.port.generic.y = 250
	s_specifyserver.port.field.widthInChars = 6
	s_specifyserver.port.field.maxchars = 5

	s_specifyserver.go.generic.type = C.MTYPE_BITMAP
	s_specifyserver.go.generic.name = SPECIFYSERVER_FIGHT0
	s_specifyserver.go.generic.flags = bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s_specifyserver.go.generic.callback = SpecifyServer_Event
	s_specifyserver.go.generic.id = ID_SPECIFYSERVERGO
	s_specifyserver.go.generic.x = 640
	s_specifyserver.go.generic.y = 480 - 64
	s_specifyserver.go.width = 128
	s_specifyserver.go.height = 64
	s_specifyserver.go.focuspic = SPECIFYSERVER_FIGHT1

	s_specifyserver.back.generic.type = C.MTYPE_BITMAP
	s_specifyserver.back.generic.name = SPECIFYSERVER_BACK0
	s_specifyserver.back.generic.flags = bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s_specifyserver.back.generic.callback = SpecifyServer_Event
	s_specifyserver.back.generic.id = ID_SPECIFYSERVERBACK
	s_specifyserver.back.generic.x = 0
	s_specifyserver.back.generic.y = 480 - 64
	s_specifyserver.back.width = 128
	s_specifyserver.back.height = 64
	s_specifyserver.back.focuspic = SPECIFYSERVER_BACK1

	U.Menu_AddItem(s_specifyserver.menu, s_specifyserver.banner)
	U.Menu_AddItem(s_specifyserver.menu, s_specifyserver.framel)
	U.Menu_AddItem(s_specifyserver.menu, s_specifyserver.framer)
	U.Menu_AddItem(s_specifyserver.menu, s_specifyserver.domain)
	U.Menu_AddItem(s_specifyserver.menu, s_specifyserver.port)
	U.Menu_AddItem(s_specifyserver.menu, s_specifyserver.go)
	U.Menu_AddItem(s_specifyserver.menu, s_specifyserver.back)

	s_specifyserver.port.field.buffer = string.sub(Q.va("%i", 27960), 1, 5)
end

--[[
=================
SpecifyServer_Cache
=================
]]
function U.SpecifyServer_Cache()
	-- touch all our pics
	local i = 0
	while specifyserver_artlist[i] ~= nil do
		trap.R_RegisterShaderNoMip(specifyserver_artlist[i])
		i += 1
	end
end

--[[
=================
UI_SpecifyServerMenu
=================
]]
function U.UI_SpecifyServerMenu()
	U.SpecifyServer_MenuInit()
	U.UI_PushMenu(s_specifyserver.menu)
end

return U
