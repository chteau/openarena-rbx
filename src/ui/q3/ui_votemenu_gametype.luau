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
-- Luau port of code/q3_ui/ui_votemenu_gametype.c (OpenArena 0.8.8, gamecode 9e0f0c0).

local U = require(script.Parent.U)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local VOTEMENU_BACK0 = "menu/art_blueish/back_0"
local VOTEMENU_BACK1 = "menu/art_blueish/back_1"
local ART_FIGHT0 = "menu/art_blueish/accept_0"
local ART_FIGHT1 = "menu/art_blueish/accept_1"
local ART_BACKGROUND = "menu/art_blueish/addbotframe"

local votemenu_Gametype_artlist = { [0] = VOTEMENU_BACK0, VOTEMENU_BACK1, ART_FIGHT0, ART_FIGHT1 }

local ID_BACK = 100
local ID_GO = 101
local ID_FFA = 102
local ID_Tourney = 103
local ID_TDM = 104
local ID_CTF = 105
local ID_1FCTF = 106
local ID_Overload = 107
local ID_Harvester = 108
local ID_Elimination = 109
local ID_CTFe = 110
local ID_LMS = 111
local ID_DOUBLED = 112
local ID_DOM = 113

local Gametype_MENU_VERTICAL_SPACING = 19

-- Button / allowed-flag keys in menu order, with their gametype number and label.
local BUTTONS = {
	{ key = "FFA", id = ID_FFA, gt = 0, text = "Free for all" },
	{ key = "Tourney", id = ID_Tourney, gt = 1, text = "Tournament" },
	{ key = "TDM", id = ID_TDM, gt = 3, text = "Team Deathmatch" },
	{ key = "CTF", id = ID_CTF, gt = 4, text = "Capture the flag" },
	{ key = "_1FCTF", id = ID_1FCTF, gt = 5, text = "One flag capture" },
	{ key = "Overload", id = ID_Overload, gt = 6, text = "Overload" },
	{ key = "Harvester", id = ID_Harvester, gt = 7, text = "Harvester" },
	{ key = "Elimination", id = ID_Elimination, gt = 8, text = "Elimination" },
	{ key = "CTFe", id = ID_CTFe, gt = 9, text = "CTF Elimination" },
	{ key = "LMS", id = ID_LMS, gt = 10, text = "Last man standing" },
	{ key = "DOUBLED", id = ID_DOUBLED, gt = 11, text = "Double Domination" },
	{ key = "DOM", id = ID_DOM, gt = 12, text = "Domination" },
}

local function newVotemenu()
	local m = {
		menu = T.menuframework_s(),
		banner = T.menutext_s(),
		back = T.menubitmap_s(),
		go = T.menubitmap_s(),
		buttons = {},
		allowed = {},
		selection = 0,
	}
	for _, b in BUTTONS do
		m.buttons[b.key] = T.menutext_s()
		m.allowed[b.key] = false
	end
	return m
end

local s_votemenu_Gametype = newVotemenu()

local function VoteMenu_Gametype_Event(ptr, event)
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
		for _, b in BUTTONS do
			if b.id == s_votemenu_Gametype.selection then
				trap.Cmd_ExecuteText(C.EXEC_APPEND, "callvote g_gametype " .. b.gt)
				U.UI_PopMenu()
				U.UI_PopMenu()
				return
			end
		end
	else
		if event ~= C.QM_ACTIVATED then
			return
		end
		if s_votemenu_Gametype.selection ~= id then
			s_votemenu_Gametype.selection = id
			U.UI_VoteGametypeMenuInternal()
		end
	end
end

local function setGametypeMenutext(menu, y, id, active, text)
	menu.generic.type = C.MTYPE_PTEXT
	menu.color = U.color_red
	menu.generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_PULSEIFFOCUS)
	if not active then
		menu.generic.flags = bit32.bor(menu.generic.flags, C.QMF_INACTIVE, C.QMF_GRAYED)
	elseif s_votemenu_Gametype.selection == id then
		menu.color = U.color_orange
	end
	menu.generic.x = 320
	menu.generic.y = y
	menu.generic.id = id
	menu.generic.callback = VoteMenu_Gametype_Event
	menu.string = text
	menu.style = bit32.bor(C.UI_CENTER, C.UI_SMALLFONT)
end

local function VoteMenu_Gametype_Cache()
	-- touch all our pics
	local i = 0
	while votemenu_Gametype_artlist[i] ~= nil do
		trap.R_RegisterShaderNoMip(votemenu_Gametype_artlist[i])
		i += 1
	end
end

local function UI_VoteMenu_Gametype_Draw()
	U.UI_DrawBannerString(320, 16, "CALL VOTE GAMETYPE", C.UI_CENTER, U.color_white)
	U.UI_DrawNamedPic(320 - 233, 240 - 166, 466, 332, ART_BACKGROUND)

	-- standard menu drawing
	U.Menu_Draw(s_votemenu_Gametype.menu)
end

-- Used then forcing a redraw
function U.UI_VoteGametypeMenuInternal()
	local s = s_votemenu_Gametype

	VoteMenu_Gametype_Cache()

	s.menu.wrapAround = true
	s.menu.fullscreen = false
	s.menu.draw = UI_VoteMenu_Gametype_Draw

	s.banner.generic.type = C.MTYPE_BTEXT
	s.banner.generic.x = 320
	s.banner.generic.y = 16
	s.banner.string = "CALL VOTE GAMETYPE"
	s.banner.color = U.color_white
	s.banner.style = C.UI_CENTER

	local y = 98
	for _, b in BUTTONS do
		setGametypeMenutext(s.buttons[b.key], y, b.id, s.allowed[b.key], b.text)
		y += Gametype_MENU_VERTICAL_SPACING
	end

	s.back.generic.type = C.MTYPE_BITMAP
	s.back.generic.name = VOTEMENU_BACK0
	s.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.back.generic.callback = VoteMenu_Gametype_Event
	s.back.generic.id = ID_BACK
	s.back.generic.x = 320 - 128
	s.back.generic.y = 256 + 128 - 64
	s.back.width = 128
	s.back.height = 64
	s.back.focuspic = VOTEMENU_BACK1

	s.go.generic.type = C.MTYPE_BITMAP
	s.go.generic.name = ART_FIGHT0
	s.go.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.go.generic.callback = VoteMenu_Gametype_Event
	s.go.generic.id = ID_GO
	s.go.generic.x = 320
	s.go.generic.y = 256 + 128 - 64
	s.go.width = 128
	s.go.height = 64
	s.go.focuspic = ART_FIGHT1
end

-- Called from outside
function U.UI_VoteGametypeMenu()
	-- zero set all our globals
	s_votemenu_Gametype = newVotemenu()
	local s = s_votemenu_Gametype
	local serverinfo = trap.GetConfigString(C.CS_SERVERINFO)
	local gametypeinfo = Q.Info_ValueForKey(serverinfo, "g_voteGametypes")
	if Q.stricmp(gametypeinfo, "*") == 0 then
		for _, b in BUTTONS do
			s.allowed[b.key] = true
		end
	else
		for _, b in BUTTONS do
			s.allowed[b.key] = string.find(string.lower(gametypeinfo), "/" .. b.gt .. "/", 1, true) ~= nil
		end
	end

	U.UI_VoteGametypeMenuInternal()

	U.Menu_AddItem(s.menu, s.banner)
	U.Menu_AddItem(s.menu, s.back)
	U.Menu_AddItem(s.menu, s.go)
	for _, b in BUTTONS do
		U.Menu_AddItem(s.menu, s.buttons[b.key])
	end

	U.UI_PushMenu(s.menu)
end

return U
