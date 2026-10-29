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
-- Luau port of code/q3_ui/ui_team.c (OpenArena gamecode).

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local TEAMMAIN_FRAME = "menu/" .. C.MENU_ART_DIR .. "/cut_frame"

local ID_JOINRED = 100
local ID_JOINBLUE = 101
local ID_JOINGAME = 102
local ID_SPECTATE = 103

local s_teammain

local function TeamMain_MenuEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	local id = ptr.generic.id
	if id == ID_JOINRED then
		trap.Cmd_ExecuteText(C.EXEC_APPEND, "cmd team red\n")
		U.UI_ForceMenuOff()
	elseif id == ID_JOINBLUE then
		trap.Cmd_ExecuteText(C.EXEC_APPEND, "cmd team blue\n")
		U.UI_ForceMenuOff()
	elseif id == ID_JOINGAME then
		trap.Cmd_ExecuteText(C.EXEC_APPEND, "cmd team free\n")
		U.UI_ForceMenuOff()
	elseif id == ID_SPECTATE then
		trap.Cmd_ExecuteText(C.EXEC_APPEND, "cmd team spectator\n")
		U.UI_ForceMenuOff()
	end
end

local function setupText(item, id, y, str)
	item.generic.type = C.MTYPE_PTEXT
	item.generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_PULSEIFFOCUS)
	item.generic.id = id
	item.generic.callback = TeamMain_MenuEvent
	item.generic.x = 320
	item.generic.y = y
	item.string = str
	item.style = bit32.bor(C.UI_CENTER, C.UI_SMALLFONT)
	item.color = Q.colorRed
end

function U.TeamMain_MenuInit()
	s_teammain = {
		menu = T.menuframework_s(),
		frame = T.menubitmap_s(),
		joinred = T.menutext_s(),
		joinblue = T.menutext_s(),
		joingame = T.menutext_s(),
		spectate = T.menutext_s(),
	}

	U.TeamMain_Cache()

	s_teammain.menu.wrapAround = true
	s_teammain.menu.fullscreen = false

	s_teammain.frame.generic.type = C.MTYPE_BITMAP
	s_teammain.frame.generic.flags = C.QMF_INACTIVE
	s_teammain.frame.generic.name = TEAMMAIN_FRAME
	s_teammain.frame.generic.x = 142
	s_teammain.frame.generic.y = 118
	s_teammain.frame.width = 359
	s_teammain.frame.height = 256

	local y = 194

	setupText(s_teammain.joinred, ID_JOINRED, y, "JOIN RED")
	y += 20
	setupText(s_teammain.joinblue, ID_JOINBLUE, y, "JOIN BLUE")
	y += 20
	setupText(s_teammain.joingame, ID_JOINGAME, y, "JOIN GAME")
	y += 20
	setupText(s_teammain.spectate, ID_SPECTATE, y, "SPECTATE")
	y += 20

	local info = trap.GetConfigString(C.CS_SERVERINFO)
	local gametype = Q.int(tonumber(Q.Info_ValueForKey(info, "g_gametype")) or 0)

	-- set initial states
	if
		gametype == C.GT_SINGLE_PLAYER
		or gametype == C.GT_FFA
		or gametype == C.GT_LMS
		or gametype == C.GT_POSSESSION
		or gametype == C.GT_TOURNAMENT
	then
		s_teammain.joinred.generic.flags = bit32.bor(s_teammain.joinred.generic.flags, C.QMF_GRAYED)
		s_teammain.joinblue.generic.flags = bit32.bor(s_teammain.joinblue.generic.flags, C.QMF_GRAYED)
	else
		s_teammain.joingame.string = "AUTO JOIN GAME"
	end

	U.Menu_AddItem(s_teammain.menu, s_teammain.frame)
	U.Menu_AddItem(s_teammain.menu, s_teammain.joinred)
	U.Menu_AddItem(s_teammain.menu, s_teammain.joinblue)
	U.Menu_AddItem(s_teammain.menu, s_teammain.joingame)
	U.Menu_AddItem(s_teammain.menu, s_teammain.spectate)
end

function U.TeamMain_Cache()
	trap.R_RegisterShaderNoMip(TEAMMAIN_FRAME)
end

function U.UI_TeamMainMenu()
	U.TeamMain_MenuInit()
	U.UI_PushMenu(s_teammain.menu)
end

return U
