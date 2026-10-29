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
-- Luau port of code/q3_ui/ui_votemenu.c (OpenArena 0.8.8, gamecode 9e0f0c0).

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
local ID_SHUFFLE = 111

local VOTEMENU_MENU_VERTICAL_SPACING = 22

local function newVotemenu()
	return {
		menu = T.menuframework_s(),
		banner = T.menutext_s(),
		back = T.menubitmap_s(),
		go = T.menubitmap_s(),

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
		shuffle = false,

		bMapRestart = T.menutext_s(),
		bNextmap = T.menutext_s(),
		bDoWarmup = T.menutext_s(),
		bKick = T.menutext_s(),
		bMap = T.menutext_s(),
		bGametype = T.menutext_s(),
		bTimelimit = T.menutext_s(),
		bFraglimit = T.menutext_s(),
		bShuffle = T.menutext_s(),
		bCustom = T.menutext_s(),

		selection = 0,
	}
end

local s_votemenu = newVotemenu()

local function VoteMenu_CheckVoteNames()
	local voteflags = Q.int(trap.Cvar_VariableValue("cg_voteflags"))
	s_votemenu.map_restart = bit32.band(voteflags, C.VF_map_restart) ~= 0
	s_votemenu.nextmap = bit32.band(voteflags, C.VF_nextmap) ~= 0
	s_votemenu.map = bit32.band(voteflags, C.VF_map) ~= 0
	s_votemenu.gametype = bit32.band(voteflags, C.VF_g_gametype) ~= 0
	--We never use "kick" in menues, always clientkick
	s_votemenu.clientkick = bit32.band(voteflags, C.VF_clientkick) ~= 0
	s_votemenu.g_doWarmup = bit32.band(voteflags, C.VF_g_doWarmup) ~= 0
	s_votemenu.timelimit = bit32.band(voteflags, C.VF_timelimit) ~= 0
	s_votemenu.fraglimit = bit32.band(voteflags, C.VF_fraglimit) ~= 0
	s_votemenu.custom = bit32.band(voteflags, C.VF_custom) ~= 0
	s_votemenu.shuffle = bit32.band(voteflags, C.VF_shuffle) ~= 0
end

local function VoteMenu_Event(ptr, event)
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
		local sel = s_votemenu.selection
		if sel == ID_NEXTMAP then
			trap.Cmd_ExecuteText(C.EXEC_APPEND, "callvote nextmap")
			U.UI_PopMenu()
		elseif sel == ID_RESTART then
			trap.Cmd_ExecuteText(C.EXEC_APPEND, "callvote map_restart")
			U.UI_PopMenu()
		elseif sel == ID_DOWARMUP then
			if s_votemenu.g_doWarmupEnabled then
				trap.Cmd_ExecuteText(C.EXEC_APPEND, "callvote g_doWarmup 0")
			else
				trap.Cmd_ExecuteText(C.EXEC_APPEND, "callvote g_doWarmup 1")
			end
			U.UI_PopMenu()
		elseif sel == ID_SHUFFLE then
			trap.Cmd_ExecuteText(C.EXEC_APPEND, "callvote shuffle")
			U.UI_PopMenu()
		elseif sel == ID_FRAG then
			U.UI_VoteFraglimitMenu()
			--Don't pop! It will do a double pop if successfull
		elseif sel == ID_CUSTOM then
			U.UI_VoteCustomMenu()
		elseif sel == ID_TIME then
			U.UI_VoteTimelimitMenu()
		elseif sel == ID_GAMETYPE then
			U.UI_VoteGametypeMenu()
		elseif sel == ID_KICK then
			U.UI_VoteKickMenu()
		elseif sel == ID_MAP then
			U.UI_VoteMapMenu()
		end
	else
		if event ~= C.QM_ACTIVATED then
			return
		end
		if s_votemenu.selection ~= id then
			s_votemenu.selection = id
			U.UI_VoteMenuMenuInternal()
		end
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

local function setButton(b, y, id, string, enabled)
	b.generic.type = C.MTYPE_PTEXT
	b.color = U.color_red
	b.generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_PULSEIFFOCUS)
	if not enabled then
		b.generic.flags = bit32.bor(b.generic.flags, C.QMF_INACTIVE, C.QMF_GRAYED)
	elseif s_votemenu.selection == id then
		b.color = U.color_orange
	end
	b.generic.x = 320
	b.generic.y = y
	b.generic.id = id
	b.generic.callback = VoteMenu_Event
	b.string = string
	b.style = bit32.bor(C.UI_CENTER, C.UI_SMALLFONT)
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
	setButton(s_votemenu.bNextmap, y, ID_NEXTMAP, "Next map", s_votemenu.nextmap)

	y += VOTEMENU_MENU_VERTICAL_SPACING
	setButton(s_votemenu.bMapRestart, y, ID_RESTART, "Restart match", s_votemenu.map_restart)

	y += VOTEMENU_MENU_VERTICAL_SPACING
	setButton(s_votemenu.bShuffle, y, ID_SHUFFLE, "Shuffle teams", s_votemenu.map_restart)

	y += VOTEMENU_MENU_VERTICAL_SPACING
	setButton(s_votemenu.bMap, y, ID_MAP, "Change map", s_votemenu.map)

	y += VOTEMENU_MENU_VERTICAL_SPACING
	setButton(s_votemenu.bGametype, y, ID_GAMETYPE, "Change gametype", s_votemenu.gametype)

	y += VOTEMENU_MENU_VERTICAL_SPACING
	setButton(s_votemenu.bKick, y, ID_KICK, "Kick player", s_votemenu.clientkick)

	y += VOTEMENU_MENU_VERTICAL_SPACING
	setButton(
		s_votemenu.bDoWarmup,
		y,
		ID_DOWARMUP,
		s_votemenu.g_doWarmupEnabled and "Disable warmup" or "Enable warmup",
		s_votemenu.g_doWarmup
	)

	y += VOTEMENU_MENU_VERTICAL_SPACING
	setButton(s_votemenu.bFraglimit, y, ID_FRAG, "Change fraglimit", s_votemenu.fraglimit)

	y += VOTEMENU_MENU_VERTICAL_SPACING
	setButton(s_votemenu.bTimelimit, y, ID_TIME, "Change timelimit", s_votemenu.timelimit)

	y += VOTEMENU_MENU_VERTICAL_SPACING
	setButton(s_votemenu.bCustom, y, ID_CUSTOM, "Custom vote", s_votemenu.custom)

	s_votemenu.back.generic.type = C.MTYPE_BITMAP
	s_votemenu.back.generic.name = VOTEMENU_BACK0
	s_votemenu.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s_votemenu.back.generic.callback = VoteMenu_Event
	s_votemenu.back.generic.id = ID_BACK
	s_votemenu.back.generic.x = 320 - 128
	s_votemenu.back.generic.y = 256 + 128 - 64
	s_votemenu.back.width = 128
	s_votemenu.back.height = 64
	s_votemenu.back.focuspic = VOTEMENU_BACK1

	s_votemenu.go.generic.type = C.MTYPE_BITMAP
	s_votemenu.go.generic.name = ART_FIGHT0
	s_votemenu.go.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s_votemenu.go.generic.callback = VoteMenu_Event
	s_votemenu.go.generic.id = ID_GO
	s_votemenu.go.generic.x = 320
	s_votemenu.go.generic.y = 256 + 128 - 64
	s_votemenu.go.width = 128
	s_votemenu.go.height = 64
	s_votemenu.go.focuspic = ART_FIGHT1
end

-- Called from outside
function U.UI_VoteMenuMenu()
	-- zero set all our globals
	s_votemenu = newVotemenu()
	local serverinfo = trap.GetConfigString(C.CS_SERVERINFO)
	s_votemenu.g_doWarmupEnabled = Q.int(tonumber(Q.Info_ValueForKey(serverinfo, "g_doWarmup")) or 0) ~= 0
	U.UI_VoteMenuMenuInternal()

	U.Menu_AddItem(s_votemenu.menu, s_votemenu.banner)
	U.Menu_AddItem(s_votemenu.menu, s_votemenu.back)
	U.Menu_AddItem(s_votemenu.menu, s_votemenu.go)
	U.Menu_AddItem(s_votemenu.menu, s_votemenu.bNextmap)
	U.Menu_AddItem(s_votemenu.menu, s_votemenu.bMapRestart)
	U.Menu_AddItem(s_votemenu.menu, s_votemenu.bShuffle)
	U.Menu_AddItem(s_votemenu.menu, s_votemenu.bMap)
	U.Menu_AddItem(s_votemenu.menu, s_votemenu.bGametype)
	U.Menu_AddItem(s_votemenu.menu, s_votemenu.bKick)
	U.Menu_AddItem(s_votemenu.menu, s_votemenu.bDoWarmup)
	U.Menu_AddItem(s_votemenu.menu, s_votemenu.bFraglimit)
	U.Menu_AddItem(s_votemenu.menu, s_votemenu.bTimelimit)
	U.Menu_AddItem(s_votemenu.menu, s_votemenu.bCustom)

	U.UI_PushMenu(s_votemenu.menu)
end

return U
