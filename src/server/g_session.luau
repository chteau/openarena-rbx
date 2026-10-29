--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_session.c).

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
-- Luau port of g_session.c. Session data persisted across level loads via cvars.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local function G_WriteClientSessionData(client)
	local s = QS.va("%i %i %i %i %i %i %i",
		client.sess.sessionTeam,
		client.sess.spectatorNum,
		client.sess.spectatorState,
		client.sess.spectatorClient,
		client.sess.wins,
		client.sess.losses,
		client.sess.teamLeader)

	local var = QS.va("session%i", client.index)

	G.trap_Cvar_Set(var, s)
end

function G.G_ReadSessionData(client)
	local var = QS.va("session%i", client.index)
	local s = G.trap_Cvar_VariableStringBuffer(var)

	-- sscanf: stop at the first token that is not an integer
	local vals = {}
	for tok in string.gmatch(s, "%S+") do
		if not string.match(tok, "^[+-]?%d+$") then
			break
		end
		table.insert(vals, QS.atoi(tok))
		if #vals == 7 then
			break
		end
	end

	if vals[1] ~= nil then client.sess.sessionTeam = vals[1] end
	if vals[2] ~= nil then client.sess.spectatorNum = vals[2] end
	if vals[3] ~= nil then client.sess.spectatorState = vals[3] end
	if vals[4] ~= nil then client.sess.spectatorClient = vals[4] end
	if vals[5] ~= nil then client.sess.wins = vals[5] end
	if vals[6] ~= nil then client.sess.losses = vals[6] end
	if vals[7] ~= nil then client.sess.teamLeader = vals[7] ~= 0 end
end

function G.G_InitSessionData(client, userinfo)
	local sess = client.sess

	local value = QS.Info_ValueForKey(userinfo, "teampref")
	if value == "" and G.g_localTeamPref.string ~= "" and client.pers.localClient then
		value = G.g_localTeamPref.string
		G.trap_Cvar_Set("g_localTeamPref", "")
	end

	if G.g_gametype.integer >= C.GT_TEAM and G.g_ffa_gt ~= 1 then
		if G.g_teamAutoJoin.integer ~= 0 and bit32.band(G.g_entities[client.index].r.svFlags, C.SVF_BOT) == 0 then
			sess.sessionTeam = G.PickTeam(-1)
			G.BroadcastTeamChange(client, -1)
		else
			sess.sessionTeam = C.TEAM_SPECTATOR
		end
	else
		value = QS.Info_ValueForKey(userinfo, "team")
		if string.sub(value, 1, 1) == "s" then
			sess.sessionTeam = C.TEAM_SPECTATOR
		else
			if G.g_gametype.integer == C.GT_TOURNAMENT then
				if G.level.numNonSpectatorClients >= 2 then
					sess.sessionTeam = C.TEAM_SPECTATOR
				else
					sess.sessionTeam = C.TEAM_FREE
				end
			else
				if G.g_maxGameClients.integer > 0 and G.level.numNonSpectatorClients >= G.g_maxGameClients.integer then
					sess.sessionTeam = C.TEAM_SPECTATOR
				else
					sess.sessionTeam = C.TEAM_FREE
				end
			end
		end
	end

	sess.spectatorState = C.SPECTATOR_FREE
	G.AddTournamentQueue(client)

	G_WriteClientSessionData(client)
end

function G.G_InitWorldSession()
	local s = G.trap_Cvar_VariableStringBuffer("session")
	local gt = QS.atoi(s)

	if G.g_gametype.integer ~= gt then
		G.level.newSession = true
		G.G_Printf("Gametype changed, clearing session data.\n")
	end
end

function G.G_WriteSessionData()
	G.trap_Cvar_Set("session", QS.va("%i", G.g_gametype.integer))

	for i = 0, G.level.maxclients - 1 do
		if G.level.clients[i].pers.connected == C.CON_CONNECTED then
			G_WriteClientSessionData(G.level.clients[i])
		end
	end
end

return nil
