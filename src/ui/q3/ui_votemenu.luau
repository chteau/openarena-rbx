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
-- Luau port of code/q3_ui/ui_votemenu.c (OpenArena gamecode).

local U = require(script.Parent.U)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local VOTEMENU_BACK0 = "menu/" .. C.MENU_ART_DIR .. "/back_0"
local VOTEMENU_BACK1 = "menu/" .. C.MENU_ART_DIR .. "/back_1"
local ART_FIGHT0 = "menu/" .. C.MENU_ART_DIR .. "/accept_0"
local ART_FIGHT1 = "menu/" .. C.MENU_ART_DIR .. "/accept_1"
local ART_BACKGROUND = "menu/" .. C.MENU_ART_DIR .. "/addbotframe"

local votemenu_artlist = { [0] = VOTEMENU_BACK0, VOTEMENU_BACK1, ART_FIGHT0, ART_FIGHT1 }

local ID_BACK = 100
local ID_GO = 101
local ID_NEXTMAP = 102
local ID_RESTART = 103
local ID_DOWARMUP = 104
local ID_MAP = 105
local ID_KICK = 106
local ID_FRAG = 107
local ID_TIME = 108
local ID_GAMETYPE = 109
local ID_CUSTOM = 110
local ID_YES = 112
local ID_NO = 113

local VOTEMENU_MENU_VERTICAL_SPACING = 22

local s_votemenu_logic = {
	map_restart = false,
	nextmap = false,
	g_doWarmup = false,
	g_doWarmupEnabled = false,
	clientkick = false,
	map = false,
	gametype = false,
	fraglimit = false,
	timelimit = false,
	custom = false,
}

local ITEM_COUNT = 11

local s_items = {
	[0] = { id = ID_NEXTMAP, string = "Next map", enabled = function() return s_votemenu_logic.nextmap end },
	{ id = ID_RESTART, string = "Restart match", enabled = function() return s_votemenu_logic.map_restart end },
	{ id = ID_MAP, string = "Change map", enabled = function() return s_votemenu_logic.map end },
	{ id = ID_GAMETYPE, string = "Change gametype", enabled = function() return s_votemenu_logic.gametype end },
	{ id = ID_KICK, string = "Kick player", enabled = function() return s_votemenu_logic.clientkick end },
	{ id = ID_DOWARMUP, string = "Disable warmup", enabled = function() return s_votemenu_logic.g_doWarmup end },
	{ id = ID_FRAG, string = "Change fraglimit", enabled = function() return s_votemenu_logic.fraglimit end },
	{ id = ID_TIME, string = "Change timelimit", enabled = function() return s_votemenu_logic.timelimit end },
	{ id = ID_CUSTOM, string = "Custom vote", enabled = function() return s_votemenu_logic.custom end },
	{ id = ID_YES, string = "Vote yes", enabled = function() return true end },
	{ id = ID_NO, string = "Vote no", enabled = function() return true end },
}

local function newVotemenu()
	local m = {
		menu = T.menuframework_s(),
		banner = T.menutext_s(),
		back = T.menubitmap_s(),
		go = T.menubitmap_s(),
		bButtons = {},
		selection = 0,
	}
	for i = 0, ITEM_COUNT - 1 do
		m.bButtons[i] = T.menutext_s()
	end
	return m
end

local s_votemenu = newVotemenu()

local function VoteMenu_CheckVoteNames()
	local voteflags = Q.int(trap.Cvar_VariableValue("cg_voteflags"))
	s_votemenu_logic.map_restart = bit32.band(voteflags, C.VF_map_restart) ~= 0
	s_votemenu_logic.nextmap = bit32.band(voteflags, C.VF_nextmap) ~= 0
	s_votemenu_logic.map = bit32.band(voteflags, C.VF_map) ~= 0
	s_votemenu_logic.gametype = bit32.band(voteflags, C.VF_g_gametype) ~= 0
	--We never use "kick" in menues, always clientkick
	s_votemenu_logic.clientkick = bit32.band(voteflags, C.VF_clientkick) ~= 0
	s_votemenu_logic.g_doWarmup = bit32.band(voteflags, C.VF_g_doWarmup) ~= 0
	s_votemenu_logic.timelimit = bit32.band(voteflags, C.VF_timelimit) ~= 0
	s_votemenu_logic.fraglimit = bit32.band(voteflags, C.VF_fraglimit) ~= 0
	s_votemenu_logic.custom = bit32.band(voteflags, C.VF_custom) ~= 0
end

local function VoteMenu_Event(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	local id = ptr.generic.id
	if id == ID_BACK then
		U.UI_PopMenu()
	elseif id == ID_NEXTMAP then
		trap.Cmd_ExecuteText(C.EXEC_APPEND, "callvote nextmap")
		U.UI_PopMenu()
	elseif id == ID_RESTART then
		trap.Cmd_ExecuteText(C.EXEC_APPEND, "callvote map_restart")
		U.UI_PopMenu()
	elseif id == ID_DOWARMUP then
		if s_votemenu_logic.g_doWarmupEnabled then
			trap.Cmd_ExecuteText(C.EXEC_APPEND, "callvote g_doWarmup 0")
		else
			trap.Cmd_ExecuteText(C.EXEC_APPEND, "callvote g_doWarmup 1")
		end
		U.UI_PopMenu()
	elseif id == ID_FRAG then
		U.UI_VoteFraglimitMenu()
		--Don't pop! It will do a double pop if successfull
	elseif id == ID_CUSTOM then
		U.UI_VoteCustomMenu()
	elseif id == ID_TIME then
		U.UI_VoteTimelimitMenu()
	elseif id == ID_GAMETYPE then
		U.UI_VoteGametypeMenu()
	elseif id == ID_KICK then
		U.UI_VoteKickMenu()
	elseif id == ID_MAP then
		U.UI_VoteMapMenu()
	elseif id == ID_YES then
		trap.Cmd_ExecuteText(C.EXEC_APPEND, "vote yes")
		U.UI_PopMenu()
	elseif id == ID_NO then
		trap.Cmd_ExecuteText(C.EXEC_APPEND, "vote no")
		U.UI_PopMenu()
	end
end

local function VoteMenu_Cache()
	-- touch all our pics
	local i = 0
	while votemenu_artlist[i] ~= nil do
		trap.R_RegisterShaderNoMip(votemenu_artlist[i])
		i += 1
	end

	--Check all names
	VoteMenu_CheckVoteNames()
end

local function UI_VoteMenu_Draw()
	U.UI_DrawBannerString(320, 16, "CALL VOTE", C.UI_CENTER, U.color_white)
	U.UI_DrawNamedPic(320 - 233, 240 - 166, 466, 332, ART_BACKGROUND)

	-- standard menu drawing
	U.Menu_Draw(s_votemenu.menu)
end

local function UI_SetGeneticDefaults(generic, type)
	generic.type = type
	generic.x = 320
	generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_PULSEIFFOCUS)
end

local function UI_SetMenuTextDefaults(mt)
	UI_SetGeneticDefaults(mt.generic, C.MTYPE_PTEXT)
	mt.style = bit32.bor(C.UI_CENTER, C.UI_SMALLFONT)
	mt.color = U.color_red
end

local function UI_SetTextEffect(mt, enabled, currentSelection)
	if not enabled then
		mt.generic.flags = bit32.bor(mt.generic.flags, C.QMF_INACTIVE, C.QMF_GRAYED)
	else
		if currentSelection == mt.generic.id then
			mt.color = U.color_orange
		end
	end
end

-- Used then forcing a redraw
function U.UI_VoteMenuMenuInternal()
	VoteMenu_Cache()

	s_votemenu.menu.wrapAround = true
	s_votemenu.menu.fullscreen = false
	s_votemenu.menu.draw = UI_VoteMenu_Draw

	s_votemenu.banner.generic.type = C.MTYPE_BTEXT
	s_votemenu.banner.generic.x = 320
	s_votemenu.banner.generic.y = 16
	s_votemenu.banner.string = "CALL VOTE"
	s_votemenu.banner.color = U.color_white
	s_votemenu.banner.style = C.UI_CENTER

	local y = 98
	for i = 0, ITEM_COUNT - 1 do
		local b = s_votemenu.bButtons[i]
		b.generic.id = s_items[i].id
		UI_SetMenuTextDefaults(b)
		UI_SetTextEffect(b, s_items[i].enabled(), s_votemenu.selection)
		b.generic.y = y
		b.generic.callback = VoteMenu_Event
		b.string = s_items[i].string

		y += VOTEMENU_MENU_VERTICAL_SPACING
	end
	if s_votemenu_logic.g_doWarmupEnabled then
		for i = 0, ITEM_COUNT - 1 do
			if s_votemenu.bButtons[i].generic.id == ID_DOWARMUP then
				s_votemenu.bButtons[i].string = "Enable warmup"
			end
		end
	end

	s_votemenu.back.generic.type = C.MTYPE_BITMAP
	s_votemenu.back.generic.name = VOTEMENU_BACK0
	s_votemenu.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s_votemenu.back.generic.callback = VoteMenu_Event
	s_votemenu.back.generic.id = ID_BACK
	s_votemenu.back.generic.x = 320 - 128
	s_votemenu.back.generic.y = 256 + 128 - 64 + VOTEMENU_MENU_VERTICAL_SPACING * 2
	s_votemenu.back.width = 128
	s_votemenu.back.height = 64
	s_votemenu.back.focuspic = VOTEMENU_BACK1

	s_votemenu.go.generic.type = C.MTYPE_BITMAP
	s_votemenu.go.generic.name = ART_FIGHT0
	s_votemenu.go.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s_votemenu.go.generic.callback = VoteMenu_Event
	s_votemenu.go.generic.id = ID_GO
	s_votemenu.go.generic.x = 320
	s_votemenu.go.generic.y = 256 + 128 - 64 + VOTEMENU_MENU_VERTICAL_SPACING * 2
	s_votemenu.go.width = 128
	s_votemenu.go.height = 64
	s_votemenu.go.focuspic = ART_FIGHT1
end

-- Called from outside
function U.UI_VoteMenuMenu()
	-- zero set all our globals
	s_votemenu = newVotemenu()
	local serverinfo = trap.GetConfigString(C.CS_SERVERINFO)
	s_votemenu_logic.g_doWarmupEnabled = Q.int(tonumber(Q.Info_ValueForKey(serverinfo, "g_doWarmup")) or 0) ~= 0
	U.UI_VoteMenuMenuInternal()

	U.Menu_AddItem(s_votemenu.menu, s_votemenu.banner)
	U.Menu_AddItem(s_votemenu.menu, s_votemenu.back)
	for i = 0, ITEM_COUNT - 1 do
		U.Menu_AddItem(s_votemenu.menu, s_votemenu.bButtons[i])
	end

	U.UI_PushMenu(s_votemenu.menu)
end

return U
