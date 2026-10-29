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
-- Luau port of code/q3_ui/ui_votemenu_kick.c (OpenArena 0.8.8, gamecode 9e0f0c0).

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
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
local ID_PLAYERNAME0 = 20
local SIZE_OF_LIST = 10
local SIZE_OF_NAME = 32
local VOTEKICK_MENU_VERTICAL_SPACING = 20

local function item()
	return { generic = {} }
end

local function newState()
	local s = {
		menu = { items = {}, nitems = 0 },
		arrows = item(),
		banner = item(),
		up = item(),
		down = item(),
		players = {},
		go = item(),
		back = item(),
		numPlayers = 0,
		selected = 0,
		startIndex = 0,
		players_profiles = {},
	}
	for i = 0, SIZE_OF_LIST - 1 do
		s.players[i] = item()
	end
	for i = 0, C.MAX_CLIENTS + SIZE_OF_LIST do
		s.players_profiles[i] = { id = 0, name = "" }
	end
	return s
end

local s_votemenu_kick = newState()

local function populatePlayerList()
	s_votemenu_kick.numPlayers = 0
	for i = 0, C.MAX_CLIENTS - 1 do
		local playerinfo = trap.GetConfigString(C.CS_PLAYERS + i)
		if #playerinfo ~= 0 then
			local p = s_votemenu_kick.players_profiles[s_votemenu_kick.numPlayers]
			p.id = i
			p.name = string.sub(Q.Info_ValueForKey(playerinfo, "n"), 1, SIZE_OF_NAME - 2)
			s_votemenu_kick.numPlayers += 1
		end
	end
end

local function VoteKickMenu_Event(ptr, event)
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
		if s_votemenu_kick.selected == 0 then
			return
		end
		trap.Cmd_ExecuteText(
			C.EXEC_APPEND,
			Q.va(
				"callvote clientkick %d",
				s_votemenu_kick.players_profiles[(s_votemenu_kick.selected - 20) + s_votemenu_kick.startIndex].id
			)
		)
		U.UI_PopMenu()
		U.UI_PopMenu()
	else
		if event ~= C.QM_ACTIVATED then
			return
		end
		if s_votemenu_kick.selected ~= id then
			s_votemenu_kick.selected = id
			U.UI_VoteKickMenuInternal()
		end
	end
end

local function UI_VoteKickMenu_UpEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end
	if s_votemenu_kick.startIndex > 0 then
		s_votemenu_kick.startIndex -= 1
	end
	U.UI_VoteKickMenuInternal()
end

local function UI_VoteKickMenu_DownEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end
	if s_votemenu_kick.startIndex + SIZE_OF_LIST < s_votemenu_kick.numPlayers then
		s_votemenu_kick.startIndex += 1
	end
	U.UI_VoteKickMenuInternal()
end

local function UI_VoteKickMenu_Draw()
	U.UI_DrawBannerString(320, 16, "CALL VOTE KICK", C.UI_CENTER, Q.colorWhite)
	U.UI_DrawNamedPic(320 - 233, 240 - 166, 466, 332, ART_BACKGROUND)

	-- standard menu drawing
	U.Menu_Draw(s_votemenu_kick.menu)
end

local function VoteKickMenu_Cache()
	trap.R_RegisterShaderNoMip(ART_BACK0)
	trap.R_RegisterShaderNoMip(ART_BACK1)
	trap.R_RegisterShaderNoMip(ART_FIGHT0)
	trap.R_RegisterShaderNoMip(ART_FIGHT1)
	trap.R_RegisterShaderNoMip(ART_BACKGROUND)
	trap.R_RegisterShaderNoMip(ART_ARROWS)
	trap.R_RegisterShaderNoMip(ART_ARROWUP)
	trap.R_RegisterShaderNoMip(ART_ARROWDOWN)
end

local function setKickMenutext(menu, y, id, active, text)
	menu.generic.type = C.MTYPE_PTEXT
	menu.color = Q.colorRed
	menu.generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_PULSEIFFOCUS)
	if not active then
		menu.generic.flags = bit32.bor(menu.generic.flags, C.QMF_INACTIVE, C.QMF_GRAYED)
	elseif s_votemenu_kick.selected == id then
		menu.color = U.color_orange
	end
	menu.generic.x = 320
	menu.generic.y = y
	menu.generic.id = id
	menu.generic.callback = VoteKickMenu_Event
	menu.string = text
	menu.style = bit32.bor(C.UI_CENTER, C.UI_SMALLFONT)
end

--[[
UI_VoteKickMenuInternal
 *Used then forcing a redraw
]]
function U.UI_VoteKickMenuInternal()
	local s = s_votemenu_kick
	s.menu.wrapAround = true
	s.menu.fullscreen = false
	s.menu.draw = UI_VoteKickMenu_Draw

	s.banner.generic.type = C.MTYPE_BTEXT
	s.banner.generic.x = 320
	s.banner.generic.y = 16
	s.banner.string = "CALL VOTE KICK"
	s.banner.color = Q.colorWhite
	s.banner.style = C.UI_CENTER

	s.arrows.generic.type = C.MTYPE_BITMAP
	s.arrows.generic.name = ART_ARROWS
	s.arrows.generic.flags = C.QMF_INACTIVE
	s.arrows.generic.x = 200
	s.arrows.generic.y = 128
	s.arrows.width = 64
	s.arrows.height = 128

	local y = 98
	for i = 0, SIZE_OF_LIST - 1 do
		setKickMenutext(
			s.players[i],
			y,
			ID_PLAYERNAME0 + i,
			s.startIndex + i < s.numPlayers,
			s.players_profiles[s.startIndex + i].name
		)
		y += VOTEKICK_MENU_VERTICAL_SPACING
	end

	s.up.generic.type = C.MTYPE_BITMAP
	s.up.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.up.generic.x = 200
	s.up.generic.y = 128
	s.up.generic.id = ID_UP
	s.up.generic.callback = UI_VoteKickMenu_UpEvent
	s.up.width = 64
	s.up.height = 64
	s.up.focuspic = ART_ARROWUP

	s.down.generic.type = C.MTYPE_BITMAP
	s.down.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.down.generic.x = 200
	s.down.generic.y = 128 + 64
	s.down.generic.id = ID_DOWN
	s.down.generic.callback = UI_VoteKickMenu_DownEvent
	s.down.width = 64
	s.down.height = 64
	s.down.focuspic = ART_ARROWDOWN

	s.go.generic.type = C.MTYPE_BITMAP
	s.go.generic.name = ART_FIGHT0
	s.go.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.go.generic.id = ID_GO
	s.go.generic.callback = VoteKickMenu_Event
	s.go.generic.x = 320 + 128 - 128
	s.go.generic.y = 256 + 128 - 64
	s.go.width = 128
	s.go.height = 64
	s.go.focuspic = ART_FIGHT1

	s.back.generic.type = C.MTYPE_BITMAP
	s.back.generic.name = ART_BACK0
	s.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.back.generic.id = ID_BACK
	s.back.generic.callback = VoteKickMenu_Event
	s.back.generic.x = 320 - 128
	s.back.generic.y = 256 + 128 - 64
	s.back.width = 128
	s.back.height = 64
	s.back.focuspic = ART_BACK1
end

--[[
UI_VoteKickMenu
 *Called from outside
]]
function U.UI_VoteKickMenu()
	VoteKickMenu_Cache()
	s_votemenu_kick = newState()
	populatePlayerList()

	U.UI_VoteKickMenuInternal()

	local s = s_votemenu_kick
	U.Menu_AddItem(s.menu, s.banner)
	U.Menu_AddItem(s.menu, s.back)
	U.Menu_AddItem(s.menu, s.go)
	U.Menu_AddItem(s.menu, s.arrows)
	U.Menu_AddItem(s.menu, s.down)
	U.Menu_AddItem(s.menu, s.up)
	for i = 0, SIZE_OF_LIST - 1 do
		U.Menu_AddItem(s.menu, s.players[i])
	end

	U.UI_PushMenu(s.menu)
end

return U
