--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_cmds.c, part 1 of 3).

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
-- Luau port of g_cmds.c (part 1). Scoreboard/status messages and cheat commands.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SF = G.FileStatics("g_cmds")

--[[
==================
DeathmatchScoreboardMessage

==================
]]
function G.DeathmatchScoreboardMessage(ent)
	local entry
	local string_ = ""
	local stringlength
	local i, j
	local cl
	local numSorted, scoreFlags, accuracy, perfect
	local level = G.level

	-- don't send scores to bots, they don't parse it
	if bit32.band(ent.r.svFlags, C.SVF_BOT) ~= 0 then
		return
	end

	-- send the latest information on all clients
	stringlength = 0
	scoreFlags = 0

	numSorted = level.numConnectedClients

	i = 0
	while i < numSorted do
		local ping

		cl = level.clients[level.sortedClients[i]]

		if cl.pers.connected == C.CON_CONNECTING then
			ping = -1
		else
			--unlagged - true ping
			ping = if cl.pers.realPing < 999 then cl.pers.realPing else 999
		end

		if cl.accuracy_shots ~= 0 then
			accuracy = Q.idiv(cl.accuracy_hits * 100, cl.accuracy_shots)
		else
			accuracy = 0
		end
		perfect = if cl.ps.persistant[C.PERS_RANK] == 0 and cl.ps.persistant[C.PERS_KILLED] == 0 then 1 else 0

		if G.g_gametype.integer == C.GT_LMS then
			entry = QS.Com_sprintf(1024,
				" %i %i %i %i %i %i %i %i %i %i %i %i %i %i %i", level.sortedClients[i],
				cl.ps.persistant[C.PERS_SCORE], ping, Q.idiv(level.time - cl.pers.enterTime, 60000),
				scoreFlags, G.g_entities[level.sortedClients[i]].s.powerups, accuracy,
				cl.ps.persistant[C.PERS_IMPRESSIVE_COUNT],
				cl.ps.persistant[C.PERS_EXCELLENT_COUNT],
				cl.ps.persistant[C.PERS_GAUNTLET_FRAG_COUNT],
				cl.ps.persistant[C.PERS_DEFEND_COUNT],
				cl.ps.persistant[C.PERS_ASSIST_COUNT],
				perfect,
				cl.ps.persistant[C.PERS_CAPTURES],
				cl.pers.livesLeft + (if cl.isEliminated then 0 else 1))
		else
			entry = QS.Com_sprintf(1024,
				" %i %i %i %i %i %i %i %i %i %i %i %i %i %i %i", level.sortedClients[i],
				cl.ps.persistant[C.PERS_SCORE], ping, Q.idiv(level.time - cl.pers.enterTime, 60000),
				scoreFlags, G.g_entities[level.sortedClients[i]].s.powerups, accuracy,
				cl.ps.persistant[C.PERS_IMPRESSIVE_COUNT],
				cl.ps.persistant[C.PERS_EXCELLENT_COUNT],
				cl.ps.persistant[C.PERS_GAUNTLET_FRAG_COUNT],
				cl.ps.persistant[C.PERS_DEFEND_COUNT],
				cl.ps.persistant[C.PERS_ASSIST_COUNT],
				perfect,
				cl.ps.persistant[C.PERS_CAPTURES],
				cl.isEliminated)
		end
		j = #entry
		if stringlength + j > 1024 then
			break
		end
		string_ = string_ .. entry
		stringlength = stringlength + j
		i = i + 1
	end

	G.trap_SendServerCommand(ent.index, QS.va("scores %i %i %i %i%s", i,
		level.teamScores[C.TEAM_RED], level.teamScores[C.TEAM_BLUE], level.roundStartTime,
		string_))
end

--[[
==================
AccMessage

==================
]]
function G.AccMessage(ent)
	local acc = ent.client.accuracy
	local entry = QS.Com_sprintf(1024,
		" %i %i %i %i %i %i %i %i %i %i %i %i %i %i %i %i %i %i %i %i %i %i %i %i ",
		acc[C.WP_MACHINEGUN][0], acc[C.WP_MACHINEGUN][1],
		acc[C.WP_SHOTGUN][0], acc[C.WP_SHOTGUN][1],
		acc[C.WP_GRENADE_LAUNCHER][0], acc[C.WP_GRENADE_LAUNCHER][1],
		acc[C.WP_ROCKET_LAUNCHER][0], acc[C.WP_ROCKET_LAUNCHER][1],
		acc[C.WP_LIGHTNING][0], acc[C.WP_LIGHTNING][1],
		acc[C.WP_RAILGUN][0], acc[C.WP_RAILGUN][1],
		acc[C.WP_PLASMAGUN][0], acc[C.WP_PLASMAGUN][1],
		acc[C.WP_BFG][0], acc[C.WP_BFG][1],
		0, 0, --Hook
		acc[C.WP_NAILGUN][0], acc[C.WP_NAILGUN][1],
		0, 0,
		acc[C.WP_CHAINGUN][0], acc[C.WP_CHAINGUN][1])

	G.trap_SendServerCommand(ent.index, QS.va("accs%s", entry))
end

--[[
==================
DominationPointStatusMessage

==================
]]
function G.DominationPointStatusMessage(ent)
	local entry
	local string_ = ""
	local stringlength
	local j
	local level = G.level

	stringlength = 0

	local i = 0
	while i < C.MAX_DOMINATION_POINTS and i < level.domination_points_count do
		entry = QS.Com_sprintf(10, " %i", level.pointStatusDom[i])
		j = #entry
		if stringlength + j > 10 * C.MAX_DOMINATION_POINTS then
			break
		end
		string_ = string_ .. entry
		stringlength = stringlength + j
		i = i + 1
	end

	G.trap_SendServerCommand(ent.index, QS.va("domStatus %i%s", level.domination_points_count, string_))
end

--[[
==================
EliminationMessage

==================
]]
function G.EliminationMessage(ent)
	G.trap_SendServerCommand(ent.index, QS.va("elimination %i %i %i",
		G.level.teamScores[C.TEAM_RED], G.level.teamScores[C.TEAM_BLUE], G.level.roundStartTime))
end

function G.RespawnTimeMessage(ent, time)
	G.trap_SendServerCommand(ent.index, QS.va("respawn %i", time))
end

--[[
==================
DoubleDominationScoreTime

==================
]]
function G.DoubleDominationScoreTimeMessage(ent)
	G.trap_SendServerCommand(ent.index, QS.va("ddTakeAt %i", G.level.timeTaken + G.g_ddCaptureTime.integer * 1000))
end

--[[
==================
DominationPointNames
==================
]]
function G.DominationPointNamesMessage(ent)
	local M = C.MAX_DOMINATION_POINTS_NAMES
	local N = C.MAX_DOMINATION_POINTS
	local total = M * N
	local text = {}
	local nullFound
	for k = 0, total - 1 do
		text[k] = 0
	end
	for i = 0, N - 1 do
		-- Q_strncpyz(text + i*M, name, M-1)
		local name = G.level.domination_points_names[i]
		for k = 0, M - 3 do
			text[i * M + k] = string.byte(name, k + 1) or 0
		end
		text[i * M + M - 2] = 0
		if i ~= N - 1 then
			--Don't allow "/0"!
			nullFound = false
			for j = i * M, (i + 1) * M - 1 do
				if text[j] == 0 then
					nullFound = true
				end
				if nullFound then
					text[j] = 32
				end
			end
		end
		text[total - 2] = 0x19
		text[total - 1] = 0
	end
	local chars = {}
	for k = 0, total - 1 do
		if text[k] == 0 then
			break
		end
		table.insert(chars, string.char(text[k]))
	end
	G.trap_SendServerCommand(ent.index,
		QS.va("dompointnames %i \"%s\"", G.level.domination_points_count, table.concat(chars)))
end

--[[
==================
YourTeamMessage
==================
]]
function G.YourTeamMessage(ent)
	local team = G.level.clients[ent.index].sess.sessionTeam

	if team == C.TEAM_RED then
		G.trap_SendServerCommand(ent.index, QS.va("team \"%s\"", G.g_redTeamClientNumbers.string))
	elseif team == C.TEAM_BLUE then
		G.trap_SendServerCommand(ent.index, QS.va("team \"%s\"", G.g_blueTeamClientNumbers.string))
	else
		G.trap_SendServerCommand(ent.index, "team \"all\"")
	end
end

--[[
==================
AttackingTeamMessage

==================
]]
function G.AttackingTeamMessage(ent)
	local team
	if Q.imod(G.level.eliminationSides + G.level.roundNumber, 2) == 0 then
		team = C.TEAM_RED
	else
		team = C.TEAM_BLUE
	end
	G.trap_SendServerCommand(ent.index, QS.va("attackingteam %i", team))
end

function G.ObeliskHealthMessage()
	if G.level.MustSendObeliskHealth then
		G.trap_SendServerCommand(-1, QS.va("oh %i %i", G.level.healthRedObelisk, G.level.healthBlueObelisk))
		G.level.MustSendObeliskHealth = false
	end
end

--[[
==================
ChallengeMessage

==================
]]
function G.ChallengeMessage(ent, challenge)
	if G.level.warmupTime ~= 0 then
		--We don't send anything doring warmup
		return
	end
	G.trap_SendServerCommand(ent.index, QS.va("ch %u", challenge))
	G.G_LogPrintf("Challenge: %i %i %i: Client %i got award %i\n", ent.index, challenge, 1, ent.index, challenge)
end

--[[
==================
SendCustomVoteCommands

==================
]]
function G.SendCustomVoteCommands(clientNum)
	G.trap_SendServerCommand(clientNum, QS.va("customvotes %s", G.custom_vote_info))
end

--[[
==================
Cmd_Score_f

Request current scoreboard information
==================
]]
function G.Cmd_Score_f(ent)
	G.DeathmatchScoreboardMessage(ent)
end

--[[
==================
 Cmd_Acc_f
 Request current scoreboard information
==================
]]
function G.Cmd_Acc_f(ent)
	G.AccMessage(ent)
end

--[[
==================
CheatsOk
==================
]]
function G.CheatsOk(ent)
	if G.g_cheats.integer == 0 then
		G.trap_SendServerCommand(ent.index, QS.va("print \"Cheats are not enabled on this server.\n\""))
		return false
	end
	if ent.health <= 0 then
		G.trap_SendServerCommand(ent.index, QS.va("print \"You must be alive to use this command.\n\""))
		return false
	end
	return true
end

--[[
==================
ConcatArgs
==================
]]
function G.ConcatArgs(start)
	local parts = {}
	local len = 0
	local c = G.trap_Argc()
	for i = start, c - 1 do
		local arg = G.trap_Argv(i)
		local tlen = #arg
		if len + tlen >= C.MAX_STRING_CHARS - 1 then
			break
		end
		table.insert(parts, arg)
		len = len + tlen
		if i ~= c - 1 then
			table.insert(parts, " ")
			len = len + 1
		end
	end

	return table.concat(parts)
end

--[[
==================
StringIsInteger
==================
]]
function G.StringIsInteger(s)
	local len = #s
	local foundDigit = false

	for i = 0, len - 1 do
		local ch = string.byte(s, i + 1)
		if ch < 48 or ch > 57 then
			return false
		end

		foundDigit = true
	end

	return foundDigit
end

--[[
==================
ClientNumberFromString

Returns a player number for either a number or name string
Returns -1 if invalid
==================
]]
function G.ClientNumberFromString(to, s, checkNums, checkNames)
	local cl
	local idnum
	local cleanName

	if checkNums then
		-- numeric values could be slot numbers
		if G.StringIsInteger(s) then
			idnum = QS.atoi(s)
			if idnum >= 0 and idnum < G.level.maxclients then
				cl = G.level.clients[idnum]
				if cl.pers.connected == C.CON_CONNECTED then
					return idnum
				end
			end
		end
	end

	if checkNames then
		-- check for a name match
		for n = 0, G.level.maxclients - 1 do
			cl = G.level.clients[n]
			if cl.pers.connected == C.CON_CONNECTED then
				cleanName = QS.Q_strncpyz(cl.pers.netname, C.MAX_STRING_CHARS)
				cleanName = QS.Q_CleanStr(cleanName)
				if QS.Q_stricmp(cleanName, s) == 0 then
					return n
				end
			end
		end
	end

	G.trap_SendServerCommand(to.index, QS.va("print \"User %s is not on the server\n\"", s))
	return -1
end

--[[
==================
Cmd_Give_f

Give items to a client
==================
]]
function G.Cmd_Give_f(ent)
	local name
	local it
	local give_all
	local it_ent
	local trace

	if not G.CheatsOk(ent) then
		return
	end

	name = G.ConcatArgs(1)

	if QS.Q_strequal(name, "all") then
		give_all = true
	else
		give_all = false
	end

	if give_all or QS.Q_strequal(name, "health") then
		ent.health = ent.client.ps.stats[C.STAT_MAX_HEALTH]
		if not give_all then
			return
		end
	end

	if give_all or QS.Q_strequal(name, "weapons") then
		ent.client.ps.stats[C.STAT_WEAPONS] = bit32.lshift(1, C.WP_NUM_WEAPONS) - 1 -
			bit32.lshift(1, C.WP_GRAPPLING_HOOK) - bit32.lshift(1, C.WP_NONE)
		if not give_all then
			return
		end
	end

	if give_all or QS.Q_strequal(name, "ammo") then
		for i = 0, C.MAX_WEAPONS - 1 do
			ent.client.ps.ammo[i] = 999
		end
		if not give_all then
			return
		end
	end

	if give_all or QS.Q_strequal(name, "armor") then
		ent.client.ps.stats[C.STAT_ARMOR] = 200

		if not give_all then
			return
		end
	end

	if QS.Q_strequal(name, "excellent") then
		ent.client.ps.persistant[C.PERS_EXCELLENT_COUNT] += 1
		return
	end
	if QS.Q_strequal(name, "impressive") then
		ent.client.ps.persistant[C.PERS_IMPRESSIVE_COUNT] += 1
		return
	end
	if QS.Q_strequal(name, "gauntletaward") then
		ent.client.ps.persistant[C.PERS_GAUNTLET_FRAG_COUNT] += 1
		return
	end
	if QS.Q_strequal(name, "defend") then
		ent.client.ps.persistant[C.PERS_DEFEND_COUNT] += 1
		return
	end
	if QS.Q_strequal(name, "assist") then
		ent.client.ps.persistant[C.PERS_ASSIST_COUNT] += 1
		return
	end

	-- spawn a specific item right on the player
	if not give_all then
		it = BG.BG_FindItem(name)
		if it == nil then
			return
		end

		it_ent = G.G_Spawn()
		Q.VectorCopy(ent.r.currentOrigin, it_ent.s.origin)
		it_ent.classname = it.classname
		G.G_SpawnItem(it_ent, it)
		G.FinishSpawningItem(it_ent)
		trace = S.trace_t()
		G.Touch_Item(it_ent, ent, trace)
		if it_ent.inuse then
			G.G_FreeEntity(it_ent)
		end
	end
end

--[[
==================
Cmd_God_f

Sets client to godmode

argv(0) god
==================
]]
function G.Cmd_God_f(ent)
	local msg

	if not G.CheatsOk(ent) then
		return
	end

	ent.flags = bit32.bxor(ent.flags, C.FL_GODMODE)
	if bit32.band(ent.flags, C.FL_GODMODE) == 0 then
		msg = "godmode OFF\n"
	else
		msg = "godmode ON\n"
	end

	G.trap_SendServerCommand(ent.index, QS.va("print \"%s\"", msg))
end

--[[
==================
Cmd_Notarget_f

Sets client to notarget

argv(0) notarget
==================
]]
function G.Cmd_Notarget_f(ent)
	local msg

	if not G.CheatsOk(ent) then
		return
	end

	ent.flags = bit32.bxor(ent.flags, C.FL_NOTARGET)
	if bit32.band(ent.flags, C.FL_NOTARGET) == 0 then
		msg = "notarget OFF\n"
	else
		msg = "notarget ON\n"
	end

	G.trap_SendServerCommand(ent.index, QS.va("print \"%s\"", msg))
end

--[[
==================
Cmd_Noclip_f

argv(0) noclip
==================
]]
function G.Cmd_Noclip_f(ent)
	local msg

	if not G.CheatsOk(ent) then
		return
	end

	if ent.client.noclip then
		msg = "noclip OFF\n"
	else
		msg = "noclip ON\n"
	end
	ent.client.noclip = not ent.client.noclip

	G.trap_SendServerCommand(ent.index, QS.va("print \"%s\"", msg))
end

--[[
==================
Cmd_LevelShot_f

This is just to help generate the level pictures
for the menus.  It goes to the intermission immediately
and sends over a command to the client to resize the view,
hide the scoreboard, and take a special screenshot
==================
]]
function G.Cmd_LevelShot_f(ent)
	if not G.CheatsOk(ent) then
		return
	end

	-- doesn't work in single player
	if G.g_gametype.integer ~= 0 then
		G.trap_SendServerCommand(ent.index,
			"print \"Must be in g_gametype 0 for levelshot\n\"")
		return
	end

	if not ent.client.pers.localClient then
		G.trap_SendServerCommand(ent.index,
			"print \"The levelshot command must be executed by a local client\n\"")
		return
	end

	G.BeginIntermission()
	G.trap_SendServerCommand(ent.index, "clientLevelShot")
end

--[[
==================
Cmd_LevelShot_f

This is just to help generate the level pictures
for the menus.  It goes to the intermission immediately
and sends over a command to the client to resize the view,
hide the scoreboard, and take a special screenshot
==================
]]
function G.Cmd_TeamTask_f(ent)
	local userinfo
	local arg
	local task
	local client = ent.client.index

	if G.trap_Argc() ~= 2 then
		return
	end
	arg = G.trap_Argv(1)
	task = QS.atoi(arg)

	userinfo = G.trap_GetUserinfo(client)
	userinfo = QS.Info_SetValueForKey(userinfo, "teamtask", QS.va("%d", task))
	G.trap_SetUserinfo(client, userinfo)
	G.ClientUserinfoChanged(client)
end

--[[
=================
Cmd_Kill_f
=================
]]
function G.Cmd_Kill_f(ent)
	if ent.client.sess.sessionTeam == C.TEAM_SPECTATOR or ent.client.isEliminated then
		return
	end
	if ent.health <= 0 then
		return
	end
	ent.flags = bit32.band(ent.flags, bit32.bnot(C.FL_GODMODE))
	ent.health = -999
	ent.client.ps.stats[C.STAT_HEALTH] = ent.health
	if ent.client.lastSentFlying > -1 then
		--If player is in the air because of knockback we give credit to the person who sent it flying
		G.player_die(ent, ent, G.g_entities[ent.client.lastSentFlying], 100000, C.MOD_FALLING)
	else
		G.player_die(ent, ent, ent, 100000, C.MOD_SUICIDE)
	end
end

--[[
=================
BroadcastTeamChange

Let everyone know about a team change
=================
]]
function G.BroadcastTeamChange(client, oldTeam)
	if client.sess.sessionTeam == C.TEAM_RED then
		G.trap_SendServerCommand(-1, QS.va("cp \"%s^7 joined the red team.\n\"",
			client.pers.netname))
	elseif client.sess.sessionTeam == C.TEAM_BLUE then
		G.trap_SendServerCommand(-1, QS.va("cp \"%s^7 joined the blue team.\n\"",
			client.pers.netname))
	elseif client.sess.sessionTeam == C.TEAM_SPECTATOR and oldTeam ~= C.TEAM_SPECTATOR then
		G.trap_SendServerCommand(-1, QS.va("cp \"%s^7 joined the spectators.\n\"",
			client.pers.netname))
	elseif client.sess.sessionTeam == C.TEAM_FREE then
		G.trap_SendServerCommand(-1, QS.va("cp \"%s^7 joined the battle.\n\"",
			client.pers.netname))
	end
end

return nil
