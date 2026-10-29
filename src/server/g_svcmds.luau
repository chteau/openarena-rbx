--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_svcmds.c).

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
-- Luau port of OpenArena 0.8.8's g_svcmds.c (gamecode 9e0f0c0). Commands that can be executed by the server console, but not remote clients.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local MAX_IPFILTERS = 1024

-- ipFilters[i] = { mask = unsigned, compare = unsigned }
local ipFilters = {}
for i = 0, MAX_IPFILTERS - 1 do
	ipFilters[i] = { mask = 0, compare = 0 }
end
local numIPFilters = 0

local function charAt(s, i)
	return string.byte(s, i + 1) or 0
end

local function packBytes(m)
	return bit32.bor(m[0], bit32.lshift(m[1], 8), bit32.lshift(m[2], 16), bit32.lshift(m[3], 24))
end

local function StringToFilter(s, f)
	local b = { [0] = 0, 0, 0, 0 }
	local m = { [0] = 0, 0, 0, 0 }
	local p = 0

	for i = 0, 3 do
		local c = charAt(s, p)
		if c < 48 or c > 57 then
			if c == 42 then -- 'match any'
				p += 1
				if charAt(s, p) == 0 then
					break
				end
				p += 1
				continue
			end
			G.G_Printf("Bad filter address: %s\n", string.sub(s, p + 1))
			return false
		end

		local start = p
		while charAt(s, p) >= 48 and charAt(s, p) <= 57 do
			p += 1
		end
		local num = string.sub(s, start + 1, p)
		b[i] = bit32.band(QS.atoi(num), 255)
		m[i] = 255

		if charAt(s, p) == 0 then
			break
		end
		p += 1
	end

	f.mask = packBytes(m)
	f.compare = packBytes(b)

	return true
end

local function UpdateIPBans()
	local iplist_final = ""

	for i = 0, numIPFilters - 1 do
		if ipFilters[i].compare == 0xffffffff then
			continue
		end

		local cmp = ipFilters[i].compare
		local msk = ipFilters[i].mask
		local ip = ""
		for j = 0, 3 do
			local mj = bit32.band(bit32.rshift(msk, 8 * j), 255)
			local bj = bit32.band(bit32.rshift(cmp, 8 * j), 255)
			if mj ~= 255 then
				ip = ip .. "*"
			else
				ip = ip .. QS.va("%i", bj)
			end
			ip = ip .. (if j < 3 then "." else " ")
		end
		if #iplist_final + #ip < C.MAX_CVAR_VALUE_STRING then
			iplist_final = iplist_final .. ip
		else
			G.Com_Printf("g_banIPs overflowed at MAX_CVAR_VALUE_STRING\n")
			break
		end
	end

	G.trap_Cvar_Set("g_banIPs", iplist_final)
end

function G.G_FilterPacket(from)
	local m = { [0] = 0, 0, 0, 0 }
	local i = 0
	local p = 0
	while charAt(from, p) ~= 0 and i < 4 do
		m[i] = 0
		while charAt(from, p) >= 48 and charAt(from, p) <= 57 do
			m[i] = bit32.band(m[i] * 10 + (charAt(from, p) - 48), 255)
			p += 1
		end
		if charAt(from, p) == 0 or charAt(from, p) == 58 then
			break
		end
		i += 1
		p += 1
	end

	local inp = packBytes(m)

	for k = 0, numIPFilters - 1 do
		if bit32.band(inp, ipFilters[k].mask) == ipFilters[k].compare then
			return G.g_filterBan.integer ~= 0
		end
	end

	return G.g_filterBan.integer == 0
end

local function AddIP(str)
	local i = 0
	while i < numIPFilters do
		if ipFilters[i].compare == 0xffffffff then
			break -- free spot
		end
		i += 1
	end
	if i == numIPFilters then
		if numIPFilters == MAX_IPFILTERS then
			G.G_Printf("IP filter list is full\n")
			return
		end
		numIPFilters += 1
	end

	if not StringToFilter(str, ipFilters[i]) then
		ipFilters[i].compare = 0xffffffff
	end

	UpdateIPBans()
end

function G.G_ProcessIPBans()
	local str = G.g_banIPs.string
	local t = 1
	local s = 1

	while t <= #str do
		local sp = string.find(str, " ", s, true)
		if sp == nil then
			break
		end
		local tok = string.sub(str, t, sp - 1)
		s = sp
		while string.byte(str, s) == 32 do
			s += 1
		end
		if tok ~= "" then
			AddIP(tok)
		end
		t = s
	end
end

function G.Svcmd_AddIP_f()
	if G.trap_Argc() < 2 then
		G.G_Printf("Usage:  addip <ip-mask>\n")
		return
	end

	local str = G.trap_Argv(1)

	AddIP(str)
end

function G.Svcmd_RemoveIP_f()
	local f = { mask = 0, compare = 0 }

	if G.trap_Argc() < 2 then
		G.G_Printf("Usage:  sv removeip <ip-mask>\n")
		return
	end

	local str = G.trap_Argv(1)

	if not StringToFilter(str, f) then
		return
	end

	for i = 0, numIPFilters - 1 do
		if ipFilters[i].mask == f.mask and ipFilters[i].compare == f.compare then
			ipFilters[i].compare = 0xffffffff
			G.G_Printf("Removed.\n")

			UpdateIPBans()
			return
		end
	end
	G.G_Printf("Didn't find %s.\n", str)
end

function G.Svcmd_EntityList_f()
	for e = 1, G.level.num_entities - 1 do
		local check = G.g_entities[e]
		if not check.inuse then
			continue
		end
		G.G_Printf("%3i:", e)
		local t = check.s.eType
		if t == C.ET_GENERAL then
			G.G_Printf("ET_GENERAL          ")
		elseif t == C.ET_PLAYER then
			G.G_Printf("ET_PLAYER           ")
		elseif t == C.ET_ITEM then
			G.G_Printf("ET_ITEM             ")
		elseif t == C.ET_MISSILE then
			G.G_Printf("ET_MISSILE          ")
		elseif t == C.ET_MOVER then
			G.G_Printf("ET_MOVER            ")
		elseif t == C.ET_BEAM then
			G.G_Printf("ET_BEAM             ")
		elseif t == C.ET_PORTAL then
			G.G_Printf("ET_PORTAL           ")
		elseif t == C.ET_SPEAKER then
			G.G_Printf("ET_SPEAKER          ")
		elseif t == C.ET_PUSH_TRIGGER then
			G.G_Printf("ET_PUSH_TRIGGER     ")
		elseif t == C.ET_TELEPORT_TRIGGER then
			G.G_Printf("ET_TELEPORT_TRIGGER ")
		elseif t == C.ET_INVISIBLE then
			G.G_Printf("ET_INVISIBLE        ")
		elseif t == C.ET_GRAPPLE then
			G.G_Printf("ET_GRAPPLE          ")
		else
			G.G_Printf("%3i                 ", t)
		end
		if check.classname ~= nil then
			G.G_Printf("%s", check.classname)
		end
		G.G_Printf("\n")
	end
end

function G.ClientForString(s)
	-- numeric values are just slot numbers
	local c0 = charAt(s, 0)
	if c0 >= 48 and c0 <= 57 then
		local idnum = QS.atoi(s)
		if idnum < 0 or idnum >= G.level.maxclients then
			G.Com_Printf("Bad client slot: %i\n", idnum)
			return nil
		end

		local cl = G.level.clients[idnum]
		if cl.pers.connected == C.CON_DISCONNECTED then
			G.G_Printf("Client %i is not connected\n", idnum)
			return nil
		end
		return cl
	end

	-- check for a name match
	for i = 0, G.level.maxclients - 1 do
		local cl = G.level.clients[i]
		if cl.pers.connected == C.CON_DISCONNECTED then
			continue
		end
		if QS.Q_stricmp(cl.pers.netname, s) == 0 then
			return cl
		end
	end
	G.G_Printf("User %s is not on the server\n", s)

	return nil
end

function G.Svcmd_ForceTeam_f()
	-- find the player
	local str = G.trap_Argv(1)
	local cl = G.ClientForString(str)
	if cl == nil then
		return
	end

	-- set the team
	str = G.trap_Argv(2)
	G.SetTeam(G.g_entities[cl.index], str)
end

function G.ClientKick_f()
	local str = G.trap_Argv(1)

	for i = 0, #str - 1 do
		local c = charAt(str, i)
		if c < 48 or c > 57 then
			G.G_Printf("not a valid client number: \"%s\"\n", str)
			return
		end
	end

	local idnum = QS.atoi(str)

	--Local client
	if G.level.clients[idnum].pers.ip == "localhost" then
		G.G_Printf("Kick failed - local player\n")
		return
	end

	G.trap_DropClient(idnum, "was kicked")
end

function G.EndGame_f()
	G.ExitLevel()
end

-- Server Command Table
local svcmds = {
	{ "entityList", false, function() G.Svcmd_EntityList_f() end },
	{ "forceTeam", false, function() G.Svcmd_ForceTeam_f() end },
	{ "game_memory", false, function() G.Svcmd_GameMem_f() end },
	{ "addbot", false, function() G.Svcmd_AddBot_f() end },
	{ "botlist", false, function() G.Svcmd_BotList_f() end },
	{ "abort_podium", false, function() G.Svcmd_AbortPodium_f() end },
	{ "addip", false, function() G.Svcmd_AddIP_f() end },
	{ "removeip", false, function() G.Svcmd_RemoveIP_f() end },

	{ "listip", false, function() G.Svcmd_ListIP_f() end },
	{ "status", false, function() G.Svcmd_Status_f() end },
	{ "eject", false, function() G.Svcmd_EjectClient_f() end },
	{ "dumpuser", false, function() G.Svcmd_DumpUser_f() end },
	-- don't handle communication commands unless dedicated
	{ "cp", true, function() G.Svcmd_CenterPrint_f() end },
	{ "say_team", true, function() G.Svcmd_TeamMessage_f() end },
	{ "say", true, function() G.Svcmd_MessageWrapper() end },
	{ "chat", true, function() G.Svcmd_Chat_f() end },
	--Shuffle the teams
	{ "shuffle", false, function() G.ShuffleTeams() end },
	{ "clientkick_game", false, function() G.ClientKick_f() end },
	{ "endgamenow", false, function() G.EndGame_f() end },
}

function G.ConsoleCommand()
	local cmd = G.trap_Argv(0)

	for i = 1, #svcmds do
		local entry = svcmds[i]
		if QS.Q_stricmp(cmd, entry[1]) == 0 then
			if entry[2] and G.g_dedicated.integer == 0 then
				return false
			end
			entry[3]()
			return true
		end
	end
	-- see if this is an admin command
	if G.G_admin_cmd_check(nil, false) then
		return true
	end

	if G.g_dedicated.integer ~= 0 then
		G.G_Printf("unknown command: %s\n", cmd)
	end

	return false
end

return nil
