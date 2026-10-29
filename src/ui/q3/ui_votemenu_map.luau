--[[
===========================================================================
Copyright (C) 2009 Poul Sander

This file is part of the Open Arena source code.

Open Arena source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

Open Arena source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Open Arena source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
]]
-- Luau port of code/q3_ui/ui_votemenu_map.c (OpenArena 0.8.8, gamecode 9e0f0c0).

local U = require(script.Parent.U)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local ART_BACK0 = "menu/art_blueish/back_0"
local ART_BACK1 = "menu/art_blueish/back_1"
local ART_FIGHT0 = "menu/art_blueish/accept_0"
local ART_FIGHT1 = "menu/art_blueish/accept_1"
local ART_BACKGROUND = "menu/art_blueish/addbotframe"
local ART_ARROWS = "menu/art_blueish/arrows_vert_0"
local ART_ARROWUP = "menu/art_blueish/arrows_vert_top"
local ART_ARROWDOWN = "menu/art_blueish/arrows_vert_bot"

local ID_BACK = 10
local ID_GO = 11
local ID_UP = 13
local ID_DOWN = 14
local ID_MAPNAME0 = 20
local SIZE_OF_LIST = 10

local VOTEMAP_MENU_VERTICAL_SPACING = 20

local function newVotemenuMap()
	local m = {
		menu = T.menuframework_s(),
		arrows = T.menubitmap_s(),
		banner = T.menutext_s(),
		info = T.menutext_s(),
		up = T.menubitmap_s(),
		down = T.menubitmap_s(),
		go = T.menubitmap_s(),
		back = T.menubitmap_s(),
		maps = {},
		selected = 0,
	}
	for i = 0, SIZE_OF_LIST - 1 do
		m.maps[i] = T.menutext_s()
	end
	return m
end

local s_votemenu_map = newVotemenuMap()

if U.mappage == nil then
	local mappage = { pagenumber = 0, mapname = {} }
	for i = 0, SIZE_OF_LIST - 1 do
		mappage.mapname[i] = ""
	end
	U.mappage = mappage
end

local function VoteMapMenu_Event(ptr, event)
	local id = ptr.generic.id
	if id == ID_BACK then
		if event ~= C.QM_ACTIVATED then
			return
		end
		U.UI_PopMenu()
	elseif id == ID_GO then
		if event ~= C.QM_ACTIVATED then
			return
		end
		if s_votemenu_map.selected == 0 then
			return
		end
		local name = U.mappage.mapname[s_votemenu_map.selected - ID_MAPNAME0]
		if name == nil or name == "" then
			return
		end
		if Q.stricmp(name, "---") == 0 then
			return --Blank spaces have string "---"
		end
		trap.Cmd_ExecuteText(C.EXEC_APPEND, Q.va("callvote map %s", name))
		U.UI_PopMenu()
		U.UI_PopMenu()
	else
		if event ~= C.QM_ACTIVATED then
			return
		end
		if s_votemenu_map.selected ~= id then
			s_votemenu_map.selected = id
			U.UI_VoteMapMenuInternal()
		end
	end
end

local function UI_VoteMapMenu_UpEvent(ptr, event)
	if event ~= C.QM_ACTIVATED or U.mappage.pagenumber < 1 then
		return
	end

	trap.Cmd_ExecuteText(C.EXEC_APPEND, Q.va("getmappage %d", U.mappage.pagenumber - 1))
end

local function UI_VoteMapMenu_DownEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	trap.Cmd_ExecuteText(C.EXEC_APPEND, Q.va("getmappage %d", U.mappage.pagenumber + 1))
end

local function UI_VoteMapMenu_Draw()
	U.UI_DrawBannerString(320, 16, "CALL VOTE MAP", C.UI_CENTER, U.color_white)
	U.UI_DrawNamedPic(320 - 233, 240 - 166, 466, 332, ART_BACKGROUND)

	-- standard menu drawing
	U.Menu_Draw(s_votemenu_map.menu)
end

local function VoteMapMenu_Cache()
	trap.R_RegisterShaderNoMip(ART_BACK0)
	trap.R_RegisterShaderNoMip(ART_BACK1)
	trap.R_RegisterShaderNoMip(ART_FIGHT0)
	trap.R_RegisterShaderNoMip(ART_FIGHT1)
	trap.R_RegisterShaderNoMip(ART_BACKGROUND)
	trap.R_RegisterShaderNoMip(ART_ARROWS)
	trap.R_RegisterShaderNoMip(ART_ARROWUP)
	trap.R_RegisterShaderNoMip(ART_ARROWDOWN)
end

local function setMapMenutext(menu, y, id, text)
	menu.generic.type = C.MTYPE_PTEXT
	menu.color = U.color_red
	menu.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	if s_votemenu_map.selected == id then
		menu.color = U.color_orange
	end
	menu.generic.x = 320 - 80
	menu.generic.y = y
	menu.generic.id = id
	menu.generic.callback = VoteMapMenu_Event
	menu.string = text
	menu.style = bit32.bor(C.UI_LEFT, C.UI_SMALLFONT)
end

-- Used then forcing a redraw
function U.UI_VoteMapMenuInternal()
	local s = s_votemenu_map
	local mp = U.mappage

	s.menu.wrapAround = true
	s.menu.fullscreen = false
	s.menu.draw = UI_VoteMapMenu_Draw

	s.banner.generic.type = C.MTYPE_BTEXT
	s.banner.generic.x = 320
	s.banner.generic.y = 16
	s.banner.string = "CALL VOTE MAP"
	s.banner.color = U.color_white
	s.banner.style = C.UI_CENTER

	s.info.generic.type = C.MTYPE_TEXT
	s.info.generic.x = 320
	s.info.generic.y = 48
	s.info.string = Q.va("Page %d", mp.pagenumber + 1)
	s.info.color = U.color_white
	s.info.style = C.UI_CENTER

	s.arrows.generic.type = C.MTYPE_BITMAP
	s.arrows.generic.name = ART_ARROWS
	s.arrows.generic.flags = C.QMF_INACTIVE
	s.arrows.generic.x = 200 - 40
	s.arrows.generic.y = 128 + 30
	s.arrows.width = 64
	s.arrows.height = 128

	local y = 98
	setMapMenutext(s.maps[0], y, ID_MAPNAME0, mp.mapname[0])
	for i = 1, SIZE_OF_LIST - 1 do
		y += VOTEMAP_MENU_VERTICAL_SPACING
		setMapMenutext(s.maps[i], y, ID_MAPNAME0 + i, mp.mapname[i])
	end
	y += VOTEMAP_MENU_VERTICAL_SPACING + 8
	s.info.generic.y = y

	s.up.generic.type = C.MTYPE_BITMAP
	s.up.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.up.generic.x = 200 - 40
	s.up.generic.y = 128 + 30
	s.up.generic.id = ID_UP
	s.up.generic.callback = UI_VoteMapMenu_UpEvent
	s.up.width = 64
	s.up.height = 64
	s.up.focuspic = ART_ARROWUP

	s.down.generic.type = C.MTYPE_BITMAP
	s.down.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.down.generic.x = 200 - 40
	s.down.generic.y = 128 + 30 + 64
	s.down.generic.id = ID_DOWN
	s.down.generic.callback = UI_VoteMapMenu_DownEvent
	s.down.width = 64
	s.down.height = 64
	s.down.focuspic = ART_ARROWDOWN

	s.go.generic.type = C.MTYPE_BITMAP
	s.go.generic.name = ART_FIGHT0
	s.go.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.go.generic.id = ID_GO
	s.go.generic.callback = VoteMapMenu_Event
	s.go.generic.x = 320 + 128 - 128
	s.go.generic.y = 256 + 128 - 64
	s.go.width = 128
	s.go.height = 64
	s.go.focuspic = ART_FIGHT1

	s.back.generic.type = C.MTYPE_BITMAP
	s.back.generic.name = ART_BACK0
	s.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.back.generic.id = ID_BACK
	s.back.generic.callback = VoteMapMenu_Event
	s.back.generic.x = 320 - 128
	s.back.generic.y = 256 + 128 - 64
	s.back.width = 128
	s.back.height = 64
	s.back.focuspic = ART_BACK1
end

-- Called from outside
function U.UI_VoteMapMenu()
	VoteMapMenu_Cache()
	s_votemenu_map = newVotemenuMap()

	U.UI_VoteMapMenuInternal()

	--We need to initialize the list or it will be impossible to click on the items
	for i = 0, SIZE_OF_LIST - 1 do
		U.mappage.mapname[i] = "----"
	end
	trap.Cmd_ExecuteText(C.EXEC_APPEND, "getmappage 0")
	trap.Cvar_Set("cl_paused", "0") --We cannot send server commands while paused!

	local s = s_votemenu_map
	U.Menu_AddItem(s.menu, s.banner)
	U.Menu_AddItem(s.menu, s.info)
	U.Menu_AddItem(s.menu, s.back)
	U.Menu_AddItem(s.menu, s.go)
	U.Menu_AddItem(s.menu, s.arrows)
	U.Menu_AddItem(s.menu, s.down)
	U.Menu_AddItem(s.menu, s.up)
	for i = 0, SIZE_OF_LIST - 1 do
		U.Menu_AddItem(s.menu, s.maps[i])
	end

	U.UI_PushMenu(s.menu)
end

return U
