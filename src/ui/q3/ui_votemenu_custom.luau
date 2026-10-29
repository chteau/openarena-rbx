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
-- Luau port of code/q3_ui/ui_votemenu_custom.c (OpenArena 0.8.8, gamecode 9e0f0c0).

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local VOTEMENU_BACK0 = "menu/art_blueish/back_0"
local VOTEMENU_BACK1 = "menu/art_blueish/back_1"
local ART_FIGHT0 = "menu/art_blueish/accept_0"
local ART_FIGHT1 = "menu/art_blueish/accept_1"
local ART_BACKGROUND = "menu/art_blueish/addbotframe"

local votemenu_custom_artlist = { [0] = VOTEMENU_BACK0, VOTEMENU_BACK1, ART_FIGHT0, ART_FIGHT1 }

local ID_BACK = 100
local ID_GO = 101
local ID_CUSTOM0 = 102

local CUSTOM_MENU_VERTICAL_SPACING = 19
local CUSTOM_MENU_MAX_ENTRIES = 12

local function item()
	return { generic = {} }
end

local function newState()
	local s = {
		menu = { items = {}, nitems = 0 },
		banner = item(),
		back = item(),
		go = item(),
		bEntry = {},
		text = {},
		selection = 0,
	}
	for i = 0, CUSTOM_MENU_MAX_ENTRIES - 1 do
		s.bEntry[i] = item()
		s.text[i] = ""
	end
	return s
end

local s_votemenu_custom = newState()

local function VoteMenu_custom_Event(ptr, event)
	local id = ptr.generic.id
	if id == ID_BACK then
		if event ~= C.QM_ACTIVATED then
			return
		end
		U.UI_PopMenu()
	elseif id == ID_GO then
		if event ~= C.QM_ACTIVATED or s_votemenu_custom.selection == 0 then
			return
		end
		trap.Cmd_ExecuteText(
			C.EXEC_APPEND,
			Q.va("callvote custom %s", s_votemenu_custom.bEntry[s_votemenu_custom.selection - ID_CUSTOM0].string)
		)
		U.UI_PopMenu()
		U.UI_PopMenu()
	else
		if event ~= C.QM_ACTIVATED then
			return
		end
		if s_votemenu_custom.selection ~= id then
			s_votemenu_custom.selection = id
			U.UI_VoteCustomMenuInternal()
		end
	end
end

local function setCustomMenutext(menu, y, id, text)
	menu.generic.type = C.MTYPE_PTEXT
	menu.color = Q.colorRed
	menu.generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_PULSEIFFOCUS)
	if #text < 1 then
		menu.generic.flags = bit32.bor(menu.generic.flags, C.QMF_INACTIVE, C.QMF_GRAYED)
	elseif s_votemenu_custom.selection == id then
		menu.color = U.color_orange
	end
	menu.generic.x = 320
	menu.generic.y = y
	menu.generic.id = id
	menu.generic.callback = VoteMenu_custom_Event
	menu.string = text
	menu.style = bit32.bor(C.UI_CENTER, C.UI_SMALLFONT)
end

local function VoteMenu_Custom_Cache()
	-- touch all our pics
	for i = 0, 3 do
		trap.R_RegisterShaderNoMip(votemenu_custom_artlist[i])
	end
end

local function UI_VoteMenu_Custom_Draw()
	U.UI_DrawBannerString(320, 16, "CALL VOTE CUSTOM", C.UI_CENTER, Q.colorWhite)
	U.UI_DrawNamedPic(320 - 233, 240 - 166, 466, 332, ART_BACKGROUND)

	-- standard menu drawing
	U.Menu_Draw(s_votemenu_custom.menu)
end

-- COM_Parse: next whitespace-delimited or quoted token of s from pos (1-based)
local function nextToken(s, pos)
	local _, e = string.find(s, "^%s*", pos)
	pos = e + 1
	if pos > #s then
		return "", pos
	end
	if string.sub(s, pos, pos) == '"' then
		local close = string.find(s, '"', pos + 1, true)
		if close == nil then
			return string.sub(s, pos + 1), #s + 1
		end
		return string.sub(s, pos + 1, close - 1), close + 1
	end
	local _, te = string.find(s, "^%S+", pos)
	return string.sub(s, pos, te), te + 1
end

--[[
UI_VoteCustomMenuInternal
 *Used then forcing a redraw
]]
function U.UI_VoteCustomMenuInternal()
	local s = s_votemenu_custom

	VoteMenu_Custom_Cache()

	local custominfo = trap.Cvar_VariableStringBuffer("cg_vote_custom_commands")

	s.menu.wrapAround = true
	s.menu.fullscreen = false
	s.menu.draw = UI_VoteMenu_Custom_Draw

	s.banner.generic.type = C.MTYPE_BTEXT
	s.banner.generic.x = 320
	s.banner.generic.y = 16
	s.banner.string = "CALL VOTE CUSTOM"
	s.banner.color = Q.colorWhite
	s.banner.style = C.UI_CENTER

	local pointer = 1
	local y = 98
	for i = 0, CUSTOM_MENU_MAX_ENTRIES - 1 do
		local token
		token, pointer = nextToken(custominfo, pointer)
		s.text[i] = string.sub(token, 1, 31)
		setCustomMenutext(s.bEntry[i], y, ID_CUSTOM0 + i, s.text[i])
		y += CUSTOM_MENU_VERTICAL_SPACING
	end

	s.back.generic.type = C.MTYPE_BITMAP
	s.back.generic.name = VOTEMENU_BACK0
	s.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.back.generic.callback = VoteMenu_custom_Event
	s.back.generic.id = ID_BACK
	s.back.generic.x = 320 - 128
	s.back.generic.y = 256 + 128 - 64
	s.back.width = 128
	s.back.height = 64
	s.back.focuspic = VOTEMENU_BACK1

	s.go.generic.type = C.MTYPE_BITMAP
	s.go.generic.name = ART_FIGHT0
	s.go.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.go.generic.callback = VoteMenu_custom_Event
	s.go.generic.id = ID_GO
	s.go.generic.x = 320
	s.go.generic.y = 256 + 128 - 64
	s.go.width = 128
	s.go.height = 64
	s.go.focuspic = ART_FIGHT1
end

--[[
UI_VoteCustomMenu
 *Called from outside
]]
function U.UI_VoteCustomMenu()
	-- zero set all our globals
	s_votemenu_custom = newState()
	local s = s_votemenu_custom

	U.UI_VoteCustomMenuInternal()

	U.Menu_AddItem(s.menu, s.banner)
	U.Menu_AddItem(s.menu, s.back)
	U.Menu_AddItem(s.menu, s.go)
	for i = 0, CUSTOM_MENU_MAX_ENTRIES - 1 do
		U.Menu_AddItem(s.menu, s.bEntry[i])
	end

	U.UI_PushMenu(s.menu)
end

return U
