--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_svcmds_ext.c).

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
===========================================================================
]]
--!native
-- Luau port of OpenArena 0.8.8's g_svcmds_ext.c (gamecode 9e0f0c0). Extra server console commands (status, say_team, cp, eject ...).

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local S_COLOR_CYAN = "^5"

--[[
============
Svcmd_status_f
Does Server Status from Console
============
]]
function G.Svcmd_Status_f()
	G.G_Printf("slot score ping address               rate     name\n")
	G.G_Printf("---- ----- ---- -------               ----     ----\n")
	local level = G.level
	for i = 0, level.maxclients - 1 do
		local cl = level.clients[i]
		if cl.pers.connected == C.CON_DISCONNECTED then
			continue
		end

		G.G_Printf("%-4d ", i)
		G.G_Printf("%-5d ", cl.ps.persistant[C.PERS_SCORE])

		if cl.pers.connected == C.CON_CONNECTING then
			G.G_Printf("CNCT ")
		else
			G.G_Printf("%-4d ", cl.ps.ping)
		end

		local userinfo = G.trap_GetUserinfo(i)
		G.G_Printf("%-21s ", QS.Info_ValueForKey(userinfo, "ip"))
		G.G_Printf("%-8d ", QS.Info_ValueForKey(userinfo, "rate"))
		G.G_Printf("%s\n", cl.pers.netname)
	end
end

--[[
============
Svcmd_TeamMessage_f
Sends a Chat Message to a Team from the Console
============
]]
function G.Svcmd_TeamMessage_f()
	if G.trap_Argc() < 3 then
		G.G_Printf("usage: say_team <team> <message>\n")
		return
	end

	local teamNum = string.sub(G.trap_Argv(1), 1, 1)
	local team = G.G_TeamFromString(teamNum)

	if team == C.TEAM_NUM_TEAMS then
		G.G_Printf("say_team: invalid team \"%s\"\n", teamNum)
		return
	end

	local prefix = BG.BG_TeamName(team)
	prefix = QS.va("[%c] ", string.byte(string.upper(string.sub(prefix, 1, 1))) or 0)

	G.G_TeamCommand(team, QS.va("tchat \"(console): " .. S_COLOR_CYAN .. "%s\"", G.ConcatArgs(2)))
	G.G_LogPrintf("sayteam: %sconsole: " .. S_COLOR_CYAN .. "%s\n", prefix, G.ConcatArgs(2))
end

--[[
============
Svcmd_CenterPrint_f
Does a CenterPrint from the Console
============
]]
function G.Svcmd_CenterPrint_f()
	if G.trap_Argc() < 2 then
		G.G_Printf("usage: cp <message>\n")
		return
	end

	G.trap_SendServerCommand(-1, QS.va("cp \"%s\"", G.ConcatArgs(1)))
end

--[[
============
Svcmd_BannerPrint_f
Does a BannerPrint from the Console
KK-OAX Commented out in g_svccmds.c, so right now it's useless.
============
]]
function G.Svcmd_BannerPrint_f()
	if G.trap_Argc() < 2 then
		G.G_Printf("usage: bp <message>\n")
		return
	end

	G.trap_SendServerCommand(-1, QS.va("bp \"%s\"", G.ConcatArgs(1)))
end

--[[
============
Svcmd_EjectClient_f
Kicks a Client from Console
============
]]
function G.Svcmd_EjectClient_f()
	if G.trap_Argc() < 2 then
		G.G_Printf("usage: eject <player|-1> <reason>\n")
		return
	end

	local name = G.trap_Argv(1)
	local reason = G.ConcatArgs(2)

	if QS.atoi(name) == -1 then
		for i = 0, G.level.maxclients - 1 do
			if G.level.clients[i].pers.connected == C.CON_DISCONNECTED then
				continue
			end
			if G.level.clients[i].pers.localClient then
				continue
			end
			G.trap_DropClient(i, reason)
		end
	else
		local cl = G.ClientForString(name)
		if cl == nil then
			return
		end
		if cl.pers.localClient then
			G.G_Printf("eject: cannot eject local clients\n")
			return
		end
		G.trap_DropClient(cl.index, reason)
	end
end

--[[
============
Svcmd_DumpUser_f
Shows User Info
============
]]
function G.Svcmd_DumpUser_f()
	if G.trap_Argc() ~= 2 then
		G.G_Printf("usage: dumpuser <player>\n")
		return
	end

	local name = G.trap_Argv(1)
	local cl = G.ClientForString(name)
	if cl == nil then
		return
	end

	local userinfo = G.trap_GetUserinfo(cl.index)
	local info = QS.cursor(userinfo)
	G.G_Printf("userinfo\n--------\n")
	while true do
		local key, value = QS.Info_NextPair(info)
		if info.pos > #userinfo then
			return
		end

		G.G_Printf("%-20s%s\n", key, value)
	end
end

function G.Svcmd_Chat_f()
	G.trap_SendServerCommand(-1, QS.va("chat \"%s\"", G.ConcatArgs(1)))
	G.G_LogPrintf("chat: %s\n", G.ConcatArgs(1))
end

--[[
=============
Svcmd_ListIP_f
Dumb Wrapper for the trap_Send command
=============
]]
function G.Svcmd_ListIP_f()
	G.trap_SendConsoleCommand(C.EXEC_NOW, "g_banIPs\n")
end

--[[
=============
Svcmd_MessageWrapper
Dumb wrapper for "a" and "m" and "say"
=============
]]
function G.Svcmd_MessageWrapper()
	local cmd = string.sub(G.trap_Argv(0), 1, 4)
	if QS.Q_stricmp(cmd, "say") == 0 then
		G.G_Say(nil, nil, C.SAY_ALL, G.ConcatArgs(1))
	end
end

return nil
