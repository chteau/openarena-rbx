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
-- Luau port of code/q3_ui/ui_votemenu_fraglimit.c (OpenArena 0.8.8, gamecode 9e0f0c0).

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local VOTEMENU_BACK0 = "menu/art_blueish/back_0"
local VOTEMENU_BACK1 = "menu/art_blueish/back_1"
local ART_FIGHT0 = "menu/art_blueish/accept_0"
local ART_FIGHT1 = "menu/art_blueish/accept_1"
local ART_BACKGROUND = "menu/art_blueish/addbotframe"

local votemenu_fraglmit_artlist = { [0] = VOTEMENU_BACK0, VOTEMENU_BACK1, ART_FIGHT0, ART_FIGHT1 }

local ID_BACK = 100
local ID_GO = 101
local ID_50 = 102
local ID_10 = 103
local ID_15 = 104
local ID_20 = 105
local ID_30 = 106
local ID_40 = 107
local ID_INF = 108

local FRAGLIMIT_MENU_VERTICAL_SPACING = 28

local function item()
	return { generic = {} }
end

local function newState()
	return {
		menu = { items = {}, nitems = 0 },
		banner = item(),
		back = item(),
		go = item(),
		bLimit50 = item(),
		bLimit10 = item(),
		bLimit15 = item(),
		bLimit20 = item(),
		bLimit30 = item(),
		bLimit40 = item(),
		bLimitInf = item(),
		min = 0,
		max = 0,
		selection = 0,
	}
end

local s_votemenu_fraglmit = newState()

local callLimits = {
	[ID_10] = "callvote fraglimit 10",
	[ID_15] = "callvote fraglimit 15",
	[ID_20] = "callvote fraglimit 20",
	[ID_30] = "callvote fraglimit 30",
	[ID_40] = "callvote fraglimit 40",
	[ID_50] = "callvote fraglimit 50",
	[ID_INF] = "callvote fraglimit 0",
}

local function VoteMenu_Fraglimit_Event(ptr, event)
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
		local cmd = callLimits[s_votemenu_fraglmit.selection]
		if cmd ~= nil then
			trap.Cmd_ExecuteText(C.EXEC_APPEND, cmd)
			U.UI_PopMenu()
			U.UI_PopMenu()
		end
	else
		if event ~= C.QM_ACTIVATED then
			return
		end
		if s_votemenu_fraglmit.selection ~= id then
			s_votemenu_fraglmit.selection = id
			U.UI_VoteFraglimitMenuInternal()
		end
	end
end

local function setMenutext(menu, y, id, value, text)
	local s = s_votemenu_fraglmit
	menu.generic.type = C.MTYPE_PTEXT
	menu.color = Q.colorRed
	menu.generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_PULSEIFFOCUS)
	if
		(s.min > value and value ~= 0)
		or (s.max < value and s.max ~= 0)
		or (s.max ~= 0 and value == 0)
	then
		menu.generic.flags = bit32.bor(menu.generic.flags, C.QMF_INACTIVE, C.QMF_GRAYED)
	elseif s.selection == id then
		menu.color = U.color_orange
	end
	menu.generic.x = 320
	menu.generic.y = y
	menu.generic.id = id
	menu.generic.callback = VoteMenu_Fraglimit_Event
	menu.string = text
	menu.style = bit32.bor(C.UI_CENTER, C.UI_SMALLFONT)
end

local function VoteMenu_Fraglimit_Cache()
	-- touch all our pics
	for i = 0, 3 do
		trap.R_RegisterShaderNoMip(votemenu_fraglmit_artlist[i])
	end
end

local function UI_VoteMenu_Fraglimit_Draw()
	U.UI_DrawBannerString(320, 16, "CALL VOTE - FRAGLIMIT", C.UI_CENTER, Q.colorWhite)
	U.UI_DrawNamedPic(320 - 233, 240 - 166, 466, 332, ART_BACKGROUND)

	-- standard menu drawing
	U.Menu_Draw(s_votemenu_fraglmit.menu)
end

--[[
UI_VoteFraglimitMenuInternal
 *Used then forcing a redraw
]]
function U.UI_VoteFraglimitMenuInternal()
	local s = s_votemenu_fraglmit

	VoteMenu_Fraglimit_Cache()

	s.menu.wrapAround = true
	s.menu.fullscreen = false
	s.menu.draw = UI_VoteMenu_Fraglimit_Draw

	s.banner.generic.type = C.MTYPE_BTEXT
	s.banner.generic.x = 320
	s.banner.generic.y = 16
	s.banner.string = "CALL VOTE - FRAGLIMIT"
	s.banner.color = Q.colorWhite
	s.banner.style = C.UI_CENTER

	local y = 98
	setMenutext(s.bLimit10, y, ID_10, 10, "10")
	y += FRAGLIMIT_MENU_VERTICAL_SPACING
	setMenutext(s.bLimit15, y, ID_15, 15, "15")
	y += FRAGLIMIT_MENU_VERTICAL_SPACING
	setMenutext(s.bLimit20, y, ID_20, 20, "20")
	y += FRAGLIMIT_MENU_VERTICAL_SPACING
	setMenutext(s.bLimit30, y, ID_30, 30, "30")
	y += FRAGLIMIT_MENU_VERTICAL_SPACING
	setMenutext(s.bLimit40, y, ID_40, 40, "40")
	y += FRAGLIMIT_MENU_VERTICAL_SPACING
	setMenutext(s.bLimit50, y, ID_50, 50, "50")
	y += FRAGLIMIT_MENU_VERTICAL_SPACING
	setMenutext(s.bLimitInf, y, ID_INF, 0, "No limit")

	s.back.generic.type = C.MTYPE_BITMAP
	s.back.generic.name = VOTEMENU_BACK0
	s.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.back.generic.callback = VoteMenu_Fraglimit_Event
	s.back.generic.id = ID_BACK
	s.back.generic.x = 320 - 128
	s.back.generic.y = 256 + 128 - 64
	s.back.width = 128
	s.back.height = 64
	s.back.focuspic = VOTEMENU_BACK1

	s.go.generic.type = C.MTYPE_BITMAP
	s.go.generic.name = ART_FIGHT0
	s.go.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.go.generic.callback = VoteMenu_Fraglimit_Event
	s.go.generic.id = ID_GO
	s.go.generic.x = 320
	s.go.generic.y = 256 + 128 - 64
	s.go.width = 128
	s.go.height = 64
	s.go.focuspic = ART_FIGHT1
end

--[[
UI_VoteFraglimitMenu
 *Called from outside
]]
function U.UI_VoteFraglimitMenu()
	-- zero set all our globals
	s_votemenu_fraglmit = newState()
	local s = s_votemenu_fraglmit
	local serverinfo = trap.GetConfigString(C.CS_SERVERINFO)
	s.min = Q.int(tonumber(Q.Info_ValueForKey(serverinfo, "g_voteMinFraglimit")) or 0)
	s.max = Q.int(tonumber(Q.Info_ValueForKey(serverinfo, "g_voteMaxFraglimit")) or 0)
	U.UI_VoteFraglimitMenuInternal()

	U.Menu_AddItem(s.menu, s.banner)
	U.Menu_AddItem(s.menu, s.back)
	U.Menu_AddItem(s.menu, s.go)
	U.Menu_AddItem(s.menu, s.bLimit10)
	U.Menu_AddItem(s.menu, s.bLimit15)
	U.Menu_AddItem(s.menu, s.bLimit20)
	U.Menu_AddItem(s.menu, s.bLimit30)
	U.Menu_AddItem(s.menu, s.bLimit40)
	U.Menu_AddItem(s.menu, s.bLimit50)
	U.Menu_AddItem(s.menu, s.bLimitInf)

	U.UI_PushMenu(s.menu)
end

return U
