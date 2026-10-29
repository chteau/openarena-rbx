--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of Quake III Arena source code.

Quake III Arena source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.SERVER

Quake III Arena source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Quake III Arena source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
]]
-- Luau port of code/q3_ui/ui_ingame.c (OpenArena 0.8.8, gamecode 9e0f0c0).

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local INGAME_FRAME = "menu/art_blueish/addbotframe"
local INGAME_MENU_VERTICAL_SPACING = 28

local ID_TEAM = 10
local ID_ADDBOTS = 11
local ID_REMOVEBOTS = 12
local ID_SETUP = 13
local ID_SERVERINFO = 14
local ID_LEAVEARENA = 15
local ID_RESTART = 16
local ID_QUIT = 17
local ID_RESUME = 18
local ID_TEAMORDERS = 19
local ID_VOTE = 20

local s_ingame

local function atoi(s)
	return Q.int(tonumber(s) or 0)
end

local function InGame_RestartAction(result)
	if not result then
		return
	end

	U.UI_PopMenu()
	trap.Cmd_ExecuteText(C.EXEC_APPEND, "map_restart 0\n")
end

local function InGame_QuitAction(result)
	if not result then
		return
	end
	U.UI_PopMenu()
	trap.Cmd_ExecuteText(C.EXEC_APPEND, "quit\n")
end

function U.InGame_Event(ptr, notification)
	if notification ~= C.QM_ACTIVATED then
		return
	end

	local id = ptr.generic.id
	if id == ID_TEAM then
		U.UI_TeamMainMenu()
	elseif id == ID_SETUP then
		U.UI_SetupMenu()
	elseif id == ID_LEAVEARENA then
		trap.Cmd_ExecuteText(C.EXEC_APPEND, "disconnect\n")
	elseif id == ID_RESTART then
		U.UI_ConfirmMenu("RESTART ARENA?", nil, InGame_RestartAction)
	elseif id == ID_QUIT then
		U.UI_ConfirmMenu("EXIT GAME?", nil, InGame_QuitAction)
	elseif id == ID_SERVERINFO then
		U.UI_ServerInfoMenu()
	elseif id == ID_ADDBOTS then
		U.UI_AddBotsMenu()
	elseif id == ID_REMOVEBOTS then
		U.UI_RemoveBotsMenu()
	elseif id == ID_TEAMORDERS then
		U.UI_TeamOrdersMenu()
	elseif id == ID_RESUME then
		U.UI_PopMenu()
	elseif id == ID_VOTE then
		U.UI_VoteMenuMenu()
	end
end

local function setupText(item, id, y, str)
	item.generic.type = C.MTYPE_PTEXT
	item.generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_PULSEIFFOCUS)
	item.generic.x = 320
	item.generic.y = y
	item.generic.id = id
	item.generic.callback = U.InGame_Event
	item.string = str
	item.color = U.color_red
	item.style = bit32.bor(C.UI_CENTER, C.UI_SMALLFONT)
end

local function gray(item)
	item.generic.flags = bit32.bor(item.generic.flags, C.QMF_GRAYED)
end

function U.InGame_MenuInit()
	s_ingame = {
		menu = T.menuframework_s(),
		frame = T.menubitmap_s(),
		team = T.menutext_s(),
		setup = T.menutext_s(),
		server = T.menutext_s(),
		leave = T.menutext_s(),
		restart = T.menutext_s(),
		addbots = T.menutext_s(),
		removebots = T.menutext_s(),
		teamorders = T.menutext_s(),
		quit = T.menutext_s(),
		resume = T.menutext_s(),
		vote = T.menutext_s(),
	}

	U.InGame_Cache()

	s_ingame.menu.wrapAround = true
	s_ingame.menu.fullscreen = false

	s_ingame.frame.generic.type = C.MTYPE_BITMAP
	s_ingame.frame.generic.flags = C.QMF_INACTIVE
	s_ingame.frame.generic.name = INGAME_FRAME
	s_ingame.frame.generic.x = 320 - 233
	s_ingame.frame.generic.y = 240 - 166
	s_ingame.frame.width = 466
	s_ingame.frame.height = 332

	local y = 88
	setupText(s_ingame.team, ID_TEAM, y, "START")

	y += INGAME_MENU_VERTICAL_SPACING
	setupText(s_ingame.addbots, ID_ADDBOTS, y, "ADD BOTS")
	if trap.Cvar_VariableValue("sv_running") == 0 or trap.Cvar_VariableValue("bot_enable") == 0 or trap.Cvar_VariableValue("g_gametype") == C.GT_SINGLE_PLAYER then
		gray(s_ingame.addbots)
	end

	y += INGAME_MENU_VERTICAL_SPACING
	setupText(s_ingame.removebots, ID_REMOVEBOTS, y, "REMOVE BOTS")
	if trap.Cvar_VariableValue("sv_running") == 0 or trap.Cvar_VariableValue("bot_enable") == 0 or trap.Cvar_VariableValue("g_gametype") == C.GT_SINGLE_PLAYER then
		gray(s_ingame.removebots)
	end

	y += INGAME_MENU_VERTICAL_SPACING
	setupText(s_ingame.teamorders, ID_TEAMORDERS, y, "TEAM ORDERS")
	if not (trap.Cvar_VariableValue("g_gametype") >= C.GT_TEAM) or trap.Cvar_VariableValue("g_gametype") == C.GT_LMS then
		gray(s_ingame.teamorders)
	else
		local cs = T.uiClientState_t()
		trap.GetClientState(cs)
		local info = trap.GetConfigString(C.CS_PLAYERS + cs.clientNum)
		local team = atoi(Q.Info_ValueForKey(info, "t"))
		if team == C.TEAM_SPECTATOR then
			gray(s_ingame.teamorders)
		end
	end

	y += INGAME_MENU_VERTICAL_SPACING
	setupText(s_ingame.vote, ID_VOTE, y, "CALL VOTE")
	local info = trap.GetConfigString(C.CS_SERVERINFO)
	if atoi(Q.Info_ValueForKey(info, "g_allowVote")) == 0 or trap.Cvar_VariableValue("g_gametype") == C.GT_SINGLE_PLAYER then
		gray(s_ingame.vote)
	end

	y += INGAME_MENU_VERTICAL_SPACING
	setupText(s_ingame.setup, ID_SETUP, y, "SETUP")

	y += INGAME_MENU_VERTICAL_SPACING
	setupText(s_ingame.server, ID_SERVERINFO, y, "SERVER INFO")

	y += INGAME_MENU_VERTICAL_SPACING
	setupText(s_ingame.restart, ID_RESTART, y, "RESTART ARENA")
	if trap.Cvar_VariableValue("sv_running") == 0 then
		gray(s_ingame.restart)
	end

	y += INGAME_MENU_VERTICAL_SPACING
	setupText(s_ingame.resume, ID_RESUME, y, "RESUME GAME")

	y += INGAME_MENU_VERTICAL_SPACING
	setupText(s_ingame.leave, ID_LEAVEARENA, y, "LEAVE ARENA")

	y += INGAME_MENU_VERTICAL_SPACING
	setupText(s_ingame.quit, ID_QUIT, y, "EXIT GAME")

	U.Menu_AddItem(s_ingame.menu, s_ingame.frame)
	U.Menu_AddItem(s_ingame.menu, s_ingame.team)
	U.Menu_AddItem(s_ingame.menu, s_ingame.addbots)
	U.Menu_AddItem(s_ingame.menu, s_ingame.removebots)
	U.Menu_AddItem(s_ingame.menu, s_ingame.teamorders)
	U.Menu_AddItem(s_ingame.menu, s_ingame.vote)
	U.Menu_AddItem(s_ingame.menu, s_ingame.setup)
	U.Menu_AddItem(s_ingame.menu, s_ingame.server)
	U.Menu_AddItem(s_ingame.menu, s_ingame.restart)
	U.Menu_AddItem(s_ingame.menu, s_ingame.resume)
	U.Menu_AddItem(s_ingame.menu, s_ingame.leave)
	U.Menu_AddItem(s_ingame.menu, s_ingame.quit)
end

function U.InGame_Cache()
	trap.R_RegisterShaderNoMip(INGAME_FRAME)
end

function U.UI_InGameMenu()
	-- force as top level menu
	U.uis.menusp = 0

	-- set menu cursor to a nice location
	U.uis.cursorx = 319
	U.uis.cursory = 80

	U.InGame_MenuInit()
	U.UI_PushMenu(s_ingame.menu)
end

return U
