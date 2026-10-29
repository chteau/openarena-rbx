--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_cmds.c).

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
-- Luau port of g_cmds.c, part 3 of 3: voting, viewpos, mappage and the ClientCommand dispatcher.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SF = G.FileStatics("g_cmds")

-- handlers may be static (SF) or global (G) in other parts; resolved when called
local function cmdfn(name)
	return function(ent)
		local f = G[name] or SF[name]
		f(ent)
	end
end

SF.gameNames = {
	[0] = "Free For All",
	"Tournament",
	"Single Player",
	"Team Deathmatch",
	"Capture the Flag",
	"One Flag CTF",
	"Overload",
	"Harvester",
	"Elimination",
	"CTF Elimination",
	"Last Man Standing",
	"Double Domination",
	"Domination",
	"Possession",
}

function G.Cmd_Where_f(ent)
	G.trap_SendServerCommand(ent.index, QS.va("print \"%s\n\"", G.vtos(ent.r.currentOrigin)))
end

local function hasSepChar(s)
	return string.find(s, "[\n\r;]") ~= nil
end

function G.Cmd_CallVote_f(ent)
	local i
	local buffer

	if G.g_allowVote.integer == 0 then
		G.trap_SendServerCommand(ent.index, "print \"Voting not allowed here.\n\"")
		return
	end

	if G.level.voteTime ~= 0 then
		G.trap_SendServerCommand(ent.index, "print \"A vote is already in progress.\n\"")
		return
	end
	if ent.client.pers.voteCount >= G.g_maxvotes.integer then
		G.trap_SendServerCommand(ent.index, "print \"You have called the maximum number of votes.\n\"")
		return
	end
	if ent.client.sess.sessionTeam == C.TEAM_SPECTATOR then
		G.trap_SendServerCommand(ent.index, "print \"Not allowed to call a vote as spectator.\n\"")
		return
	end

	local arg1 = G.trap_Argv(1)
	local arg2 = G.trap_Argv(2)

	if hasSepChar(arg2) then
		G.trap_SendServerCommand(ent.index, "print \"Invalid vote string.\n\"")
		return
	end

	if QS.Q_strequal(arg1, "map_restart") then
	elseif QS.Q_strequal(arg1, "nextmap") then
	elseif QS.Q_strequal(arg1, "map") then
	elseif QS.Q_strequal(arg1, "g_gametype") then
	elseif QS.Q_strequal(arg1, "kick") then
	elseif QS.Q_strequal(arg1, "clientkick") then
	elseif QS.Q_strequal(arg1, "g_doWarmup") then
	elseif QS.Q_strequal(arg1, "timelimit") then
	elseif QS.Q_strequal(arg1, "fraglimit") then
	elseif QS.Q_strequal(arg1, "custom") then
	elseif QS.Q_strequal(arg1, "shuffle") then
	else
		G.trap_SendServerCommand(ent.index, "print \"Invalid vote string.\n\"")
		buffer = "print \"Vote commands are: "
		if G.allowedVote("map_restart") ~= 0 then
			buffer = buffer .. "map_restart, "
		end
		if G.allowedVote("nextmap") ~= 0 then
			buffer = buffer .. "nextmap, "
		end
		if G.allowedVote("map") ~= 0 then
			buffer = buffer .. "map <mapname>, "
		end
		if G.allowedVote("g_gametype") ~= 0 then
			buffer = buffer .. "g_gametype <n>, "
		end
		if G.allowedVote("kick") ~= 0 then
			buffer = buffer .. "kick <player>, "
		end
		if G.allowedVote("clientkick") ~= 0 then
			buffer = buffer .. "clientkick <clientnum>, "
		end
		if G.allowedVote("g_doWarmup") ~= 0 then
			buffer = buffer .. "g_doWarmup, "
		end
		if G.allowedVote("timelimit") ~= 0 then
			buffer = buffer .. "timelimit <time>, "
		end
		if G.allowedVote("fraglimit") ~= 0 then
			buffer = buffer .. "fraglimit <frags>, "
		end
		if G.allowedVote("shuffle") ~= 0 then
			buffer = buffer .. "shuffle, "
		end
		if G.allowedVote("custom") ~= 0 then
			buffer = buffer .. "custom <special>, "
		end
		buffer = string.sub(buffer, 1, #buffer - 2)
		buffer = buffer .. ".\""
		G.trap_SendServerCommand(ent.index, buffer)
		return
	end

	if G.allowedVote(arg1) == 0 then
		G.trap_SendServerCommand(ent.index, "print \"Not allowed here.\n\"")
		buffer = "print \"Vote commands are: "
		if G.allowedVote("map_restart") ~= 0 then
			buffer = buffer .. "map_restart, "
		end
		if G.allowedVote("nextmap") ~= 0 then
			buffer = buffer .. "nextmap, "
		end
		if G.allowedVote("map") ~= 0 then
			buffer = buffer .. "map <mapname>, "
		end
		if G.allowedVote("g_gametype") ~= 0 then
			buffer = buffer .. "g_gametype <n>, "
		end
		if G.allowedVote("kick") ~= 0 then
			buffer = buffer .. "kick <player>, "
		end
		if G.allowedVote("clientkick") ~= 0 then
			buffer = buffer .. "clientkick <clientnum>, "
		end
		if G.allowedVote("shuffle") ~= 0 then
			buffer = buffer .. "shuffle, "
		end
		if G.allowedVote("g_doWarmup") ~= 0 then
			buffer = buffer .. "g_doWarmup, "
		end
		if G.allowedVote("timelimit") ~= 0 then
			buffer = buffer .. "timelimit <time>, "
		end
		if G.allowedVote("fraglimit") ~= 0 then
			buffer = buffer .. "fraglimit <frags>, "
		end
		if G.allowedVote("custom") ~= 0 then
			buffer = buffer .. "custom <special>, "
		end
		buffer = string.sub(buffer, 1, #buffer - 2)
		buffer = buffer .. ".\""
		G.trap_SendServerCommand(ent.index, buffer)
		return
	end

	local level = G.level

	-- if there is still a vote to be executed
	if level.voteExecuteTime ~= 0 then
		-- don't start a vote when map change or restart is in progress
		if QS.Q_stricmpn(level.voteString, "map", 3) == 0
			or QS.Q_stricmpn(level.voteString, "nextmap", 7) == 0 then
			G.trap_SendServerCommand(ent.index, "print \"Vote after map change.\n\"")
			return
		end

		level.voteExecuteTime = 0
		G.trap_SendConsoleCommand(C.EXEC_APPEND, QS.va("%s\n", level.voteString))
	end

	level.voteKickClient = -1 -- not a client
	level.voteKickType = 0 -- not a ban
	level.voteDisplayString = ""

	-- special case for g_gametype, check for bad values
	if QS.Q_strequal(arg1, "g_gametype") then
		i = QS.atoi(arg2)
		if i == C.GT_SINGLE_PLAYER or i < C.GT_FFA or i >= C.GT_MAX_GAME_TYPE then
			G.trap_SendServerCommand(ent.index, "print \"Invalid gametype.\n\"")
			return
		end

		if i == G.g_gametype.integer then
			G.trap_SendServerCommand(ent.index, "print \"This is current gametype\n\"")
			return
		end

		if G.allowedGametype(arg2) == 0 then
			G.trap_SendServerCommand(ent.index, "print \"Gametype is not available.\n\"")
			return
		end

		local s = G.trap_Cvar_VariableStringBuffer("nextmap")
		if s ~= "" then
			level.voteString = QS.Com_sprintf(C.MAX_STRING_CHARS, "%s %d; map_restart; set nextmap \"%s\"", arg1, i, s)
			level.voteDisplayString = QS.Com_sprintf(C.MAX_STRING_CHARS, "Change gametype to: %s?", SF.gameNames[i])
		else
			level.voteString = QS.Com_sprintf(C.MAX_STRING_CHARS, "%s %d; map_restart", arg1, i)
			level.voteDisplayString = QS.Com_sprintf(C.MAX_STRING_CHARS, "Change gametype to: %s?", SF.gameNames[i])
		end
	elseif QS.Q_strequal(arg1, "map") then
		-- special case for map changes, we want to reset the nextmap setting
		-- this allows a player to change maps, but not upset the map rotation
		if G.allowedMap(arg2) == 0 then
			G.trap_SendServerCommand(ent.index, "print \"Map is not available.\n\"")
			return
		end

		local s = G.trap_Cvar_VariableStringBuffer("nextmap")
		if s ~= "" then
			level.voteString = QS.Com_sprintf(C.MAX_STRING_CHARS, "%s %s; set nextmap \"%s\"", arg1, arg2, s)
		else
			level.voteString = QS.Com_sprintf(C.MAX_STRING_CHARS, "%s %s", arg1, arg2)
		end
		level.voteDisplayString = QS.Com_sprintf(C.MAX_STRING_CHARS, "Change map to: %s?", arg2)
	elseif QS.Q_strequal(arg1, "nextmap") then
		if G.g_autonextmap.integer ~= 0 then
			level.voteString = QS.Com_sprintf(C.MAX_STRING_CHARS, "endgamenow")
		else
			local s = G.trap_Cvar_VariableStringBuffer("nextmap")
			if s == "" then
				G.trap_SendServerCommand(ent.index, "print \"nextmap not set.\n\"")
				return
			end
			level.voteString = QS.Com_sprintf(C.MAX_STRING_CHARS, "vstr nextmap")
		end
		level.voteDisplayString = QS.Com_sprintf(C.MAX_STRING_CHARS, "%s", "Next map?")
	elseif QS.Q_strequal(arg1, "fraglimit") then
		i = QS.atoi(arg2)
		if G.allowedFraglimit(i) == 0 then
			G.trap_SendServerCommand(ent.index, "print \"Cannot set fraglimit.\n\"")
			return
		end

		level.voteString = QS.Com_sprintf(C.MAX_STRING_CHARS, "%s \"%d\"", arg1, i)
		if i ~= 0 then
			level.voteDisplayString = QS.Com_sprintf(C.MAX_STRING_CHARS, "Change fraglimit to: %d", i)
		else
			level.voteDisplayString = QS.Com_sprintf(C.MAX_STRING_CHARS, "Remove fraglimit?")
		end
	elseif QS.Q_strequal(arg1, "timelimit") then
		i = QS.atoi(arg2)
		if G.allowedTimelimit(i) == 0 then
			G.trap_SendServerCommand(ent.index, "print \"Cannot set timelimit.\n\"")
			return
		end

		level.voteString = QS.Com_sprintf(C.MAX_STRING_CHARS, "%s \"%d\"", arg1, i)
		if i ~= 0 then
			level.voteDisplayString = QS.Com_sprintf(C.MAX_STRING_CHARS, "Change timelimit to: %d", i)
		else
			level.voteDisplayString = QS.Com_sprintf(C.MAX_STRING_CHARS, "Remove timelimit?")
		end
	elseif QS.Q_strequal(arg1, "map_restart") then
		level.voteString = QS.Com_sprintf(C.MAX_STRING_CHARS, "map_restart")
		level.voteDisplayString = QS.Com_sprintf(C.MAX_STRING_CHARS, "Restart map?")
	elseif QS.Q_strequal(arg1, "g_doWarmup") then
		i = QS.atoi(arg2)
		if i ~= 0 then
			level.voteString = QS.Com_sprintf(C.MAX_STRING_CHARS, "g_doWarmup \"1\"")
			level.voteDisplayString = QS.Com_sprintf(C.MAX_STRING_CHARS, "Enable warmup?")
		else
			level.voteString = QS.Com_sprintf(C.MAX_STRING_CHARS, "g_doWarmup \"0\"")
			level.voteDisplayString = QS.Com_sprintf(C.MAX_STRING_CHARS, "Disable warmup?")
		end
	elseif QS.Q_strequal(arg1, "clientkick") then
		i = QS.atoi(arg2)

		if i >= C.MAX_CLIENTS then -- Only numbers <128 is clients
			G.trap_SendServerCommand(ent.index, "print \"Cannot kick that number.\n\"")
			return
		end
		level.voteKickClient = i
		if G.g_voteBan.integer < 1 then
			level.voteString = QS.Com_sprintf(C.MAX_STRING_CHARS, "clientkick_game \"%d\"", i)
		else
			level.voteString = QS.Com_sprintf(C.MAX_STRING_CHARS, "!ban \"%d\" \"%dm\" \"Banned by public vote\"", i, G.g_voteBan.integer)
			level.voteKickType = 1 -- ban
		end
		level.voteDisplayString = QS.Com_sprintf(C.MAX_STRING_CHARS, "Kick %s?", level.clients[i].pers.netname)
	elseif QS.Q_strequal(arg1, "shuffle") then
		if G.g_gametype.integer < C.GT_TEAM or G.g_ffa_gt == 1 then -- Not a team game
			G.trap_SendServerCommand(ent.index, "print \"Can only be used in team games.\n\"")
			return
		end

		level.voteString = QS.Com_sprintf(C.MAX_STRING_CHARS, "shuffle")
		level.voteDisplayString = QS.Com_sprintf(C.MAX_STRING_CHARS, "Shuffle teams?")
	elseif QS.Q_strequal(arg1, "kick") then
		i = 0
		while true do
			local e = G.g_entities[i]
			if e ~= nil and e.client ~= nil and QS.Q_strequal(arg2, e.client.pers.netname) then
				break
			end
			-- Not client i, try next
			i = i + 1
			if i >= C.MAX_CLIENTS then -- Only numbers <128 is clients
				G.trap_SendServerCommand(ent.index, "print \"Cannot find the playername. Try clientkick instead.\n\"")
				return
			end
		end
		level.voteKickClient = i
		if G.g_voteBan.integer < 1 then
			level.voteString = QS.Com_sprintf(C.MAX_STRING_CHARS, "clientkick_game \"%d\"", i)
		else
			level.voteString = QS.Com_sprintf(C.MAX_STRING_CHARS, "!ban \"%d\" \"%dm\" \"Banned by public vote\"", i, G.g_voteBan.integer)
			level.voteKickType = 1 -- ban
		end
		level.voteDisplayString = QS.Com_sprintf(C.MAX_STRING_CHARS, "Kick %s?", level.clients[i].pers.netname)
	elseif QS.Q_strequal(arg1, "custom") then
		-- There must always be a test to ensure that length(arg2) is non-zero or the client might be able to execute random commands.
		if #arg2 < 1 then
			G.trap_SendServerCommand(ent.index, QS.va("print \"Custom vote commands are: %s\n\"", G.custom_vote_info))
			return
		end
		local customvote = G.getCustomVote(arg2)
		if not QS.Q_strequal(customvote.votename, arg2) then
			G.trap_SendServerCommand(ent.index, "print \"Command could not be found\n\"")
			return
		end
		level.voteString = QS.Com_sprintf(C.MAX_STRING_CHARS, "%s", customvote.command)
		if #customvote.displayname ~= 0 then
			level.voteDisplayString = QS.Com_sprintf(C.MAX_STRING_CHARS, "%s", customvote.displayname)
		else
			level.voteDisplayString = QS.Com_sprintf(C.MAX_STRING_CHARS, "%s", customvote.command)
		end
	else
		G.trap_SendServerCommand(ent.index, "print \"Server vality check failed, appears to be my fault. Sorry\n\"")
		return
	end

	ent.client.pers.voteCount = ent.client.pers.voteCount + 1
	G.trap_SendServerCommand(-1, QS.va("print \"%s called a vote (%s).\n\"", ent.client.pers.netname, G.whiteListedStr(level.voteDisplayString)))

	-- start the voting, the caller automatically votes yes
	level.voteTime = level.time
	level.voteYes = 1
	level.voteNo = 0

	for j = 0, level.maxclients - 1 do
		level.clients[j].ps.eFlags = bit32.band(level.clients[j].ps.eFlags, bit32.bnot(C.EF_VOTED))
		level.clients[j].vote = 0
	end
	ent.client.ps.eFlags = bit32.bor(ent.client.ps.eFlags, C.EF_VOTED)
	ent.client.vote = 1
	-- Do a first count to make sure that numvotingclients is correct!
	G.CountVotes()

	G.trap_SetConfigstring(C.CS_VOTE_TIME, QS.va("%i", level.voteTime))
	G.trap_SetConfigstring(C.CS_VOTE_STRING, level.voteDisplayString)
	G.trap_SetConfigstring(C.CS_VOTE_YES, QS.va("%i", level.voteYes))
	G.trap_SetConfigstring(C.CS_VOTE_NO, QS.va("%i", level.voteNo))
end

function G.Cmd_Vote_f(ent)
	if G.level.voteTime == 0 then
		G.trap_SendServerCommand(ent.index, "print \"No vote in progress.\n\"")
		return
	end
	if ent.client.sess.sessionTeam == C.TEAM_SPECTATOR then
		G.trap_SendServerCommand(ent.index, "print \"Not allowed to vote as spectator.\n\"")
		return
	end

	G.trap_SendServerCommand(ent.index, "print \"Vote cast.\n\"")

	ent.client.ps.eFlags = bit32.bor(ent.client.ps.eFlags, C.EF_VOTED)

	local msg = G.trap_Argv(1)

	if string.byte(msg, 1) == string.byte("y") or string.byte(msg, 2) == string.byte("Y") or string.byte(msg, 2) == string.byte("1") then
		ent.client.vote = 1
	else
		ent.client.vote = -1
	end

	-- Re count the votes
	G.CountVotes()

	-- a majority will be determined in CheckVote, which will also account
	-- for players entering or leaving
end

function G.Cmd_CallTeamVote_f(ent)
	local i, cs_offset

	local team = ent.client.sess.sessionTeam
	if team == C.TEAM_RED then
		cs_offset = 0
	elseif team == C.TEAM_BLUE then
		cs_offset = 1
	else
		return
	end

	if G.g_allowVote.integer == 0 then
		G.trap_SendServerCommand(ent.index, "print \"Voting not allowed here.\n\"")
		return
	end

	if G.level.teamVoteTime[cs_offset] ~= 0 then
		G.trap_SendServerCommand(ent.index, "print \"A team vote is already in progress.\n\"")
		return
	end
	if ent.client.pers.teamVoteCount >= G.g_maxvotes.integer then
		G.trap_SendServerCommand(ent.index, "print \"You have called the maximum number of team votes.\n\"")
		return
	end
	if ent.client.sess.sessionTeam == C.TEAM_SPECTATOR then
		G.trap_SendServerCommand(ent.index, "print \"Not allowed to call a vote as spectator.\n\"")
		return
	end

	-- make sure it is a valid command to vote on
	local arg1 = G.trap_Argv(1)
	local arg2 = ""
	i = 2
	while i < G.trap_Argc() do
		if i > 2 then
			arg2 = arg2 .. " "
		end
		arg2 = arg2 .. G.trap_Argv(i)
		i = i + 1
	end
	arg2 = QS.Q_strncpyz(arg2, C.MAX_STRING_TOKENS)

	if hasSepChar(arg2) then
		G.trap_SendServerCommand(ent.index, "print \"Invalid vote string.\n\"")
		return
	end

	if QS.Q_strequal(arg1, "leader") then
		if arg2 == "" then
			i = ent.client.ps.clientNum
		else
			-- numeric values are just slot numbers
			i = 0
			while i < 3 do
				local ch = string.byte(arg2, i + 1) or 0
				if ch == 0 or ch < 48 or ch > 57 then
					break
				end
				i = i + 1
			end
			if i >= 3 or (string.byte(arg2, i + 1) or 0) == 0 then
				i = QS.atoi(arg2)
				if i < 0 or i >= G.level.maxclients then
					G.trap_SendServerCommand(ent.index, QS.va("print \"Bad client slot: %i\n\"", i))
					return
				end

				if not G.g_entities[i].inuse then
					G.trap_SendServerCommand(ent.index, QS.va("print \"Client %i is not active\n\"", i))
					return
				end
			else
				local leader = QS.Q_strncpyz(arg2, C.MAX_NETNAME)
				leader = QS.Q_CleanStr(leader)
				i = 0
				while i < G.level.maxclients do
					local cl = G.level.clients[i]
					if cl.pers.connected ~= C.CON_DISCONNECTED and cl.sess.sessionTeam == team then
						local netname = QS.Q_strncpyz(cl.pers.netname, C.MAX_NETNAME)
						netname = QS.Q_CleanStr(netname)
						if QS.Q_strequal(netname, leader) then
							break
						end
					end
					i = i + 1
				end
				if i >= G.level.maxclients then
					G.trap_SendServerCommand(ent.index, QS.va("print \"%s is not a valid player on your team.\n\"", arg2))
					return
				end
			end
		end
		arg2 = QS.Com_sprintf(C.MAX_STRING_TOKENS, "%d", i)
	else
		G.trap_SendServerCommand(ent.index, "print \"Invalid vote string.\n\"")
		G.trap_SendServerCommand(ent.index, "print \"Team vote commands are: leader <player>.\n\"")
		return
	end

	local level = G.level
	level.teamVoteString[cs_offset] = QS.Com_sprintf(C.MAX_STRING_CHARS, "%s %s", arg1, arg2)

	for j = 0, level.maxclients - 1 do
		if level.clients[j].pers.connected ~= C.CON_DISCONNECTED then
			if level.clients[j].sess.sessionTeam == team then
				G.trap_SendServerCommand(j, QS.va("print \"%s called a team vote.\n\"", ent.client.pers.netname))
			end
		end
	end

	-- start the voting, the caller automatically votes yes
	level.teamVoteTime[cs_offset] = level.time
	level.teamVoteYes[cs_offset] = 1
	level.teamVoteNo[cs_offset] = 0

	for j = 0, level.maxclients - 1 do
		if level.clients[j].sess.sessionTeam == team then
			level.clients[j].ps.eFlags = bit32.band(level.clients[j].ps.eFlags, bit32.bnot(C.EF_TEAMVOTED))
		end
	end
	ent.client.ps.eFlags = bit32.bor(ent.client.ps.eFlags, C.EF_TEAMVOTED)

	G.trap_SetConfigstring(C.CS_TEAMVOTE_TIME + cs_offset, QS.va("%i", level.teamVoteTime[cs_offset]))
	G.trap_SetConfigstring(C.CS_TEAMVOTE_STRING + cs_offset, level.teamVoteString[cs_offset])
	G.trap_SetConfigstring(C.CS_TEAMVOTE_YES + cs_offset, QS.va("%i", level.teamVoteYes[cs_offset]))
	G.trap_SetConfigstring(C.CS_TEAMVOTE_NO + cs_offset, QS.va("%i", level.teamVoteNo[cs_offset]))
end

function G.Cmd_TeamVote_f(ent)
	local cs_offset

	local team = ent.client.sess.sessionTeam
	if team == C.TEAM_RED then
		cs_offset = 0
	elseif team == C.TEAM_BLUE then
		cs_offset = 1
	else
		return
	end

	if G.level.teamVoteTime[cs_offset] == 0 then
		G.trap_SendServerCommand(ent.index, "print \"No team vote in progress.\n\"")
		return
	end
	if bit32.band(ent.client.ps.eFlags, C.EF_TEAMVOTED) ~= 0 then
		G.trap_SendServerCommand(ent.index, "print \"Team vote already cast.\n\"")
		return
	end
	if ent.client.sess.sessionTeam == C.TEAM_SPECTATOR then
		G.trap_SendServerCommand(ent.index, "print \"Not allowed to vote as spectator.\n\"")
		return
	end

	G.trap_SendServerCommand(ent.index, "print \"Team vote cast.\n\"")

	ent.client.ps.eFlags = bit32.bor(ent.client.ps.eFlags, C.EF_TEAMVOTED)

	local msg = G.trap_Argv(1)

	if string.byte(msg, 1) == string.byte("y") or string.byte(msg, 2) == string.byte("Y") or string.byte(msg, 2) == string.byte("1") then
		G.level.teamVoteYes[cs_offset] = G.level.teamVoteYes[cs_offset] + 1
		G.trap_SetConfigstring(C.CS_TEAMVOTE_YES + cs_offset, QS.va("%i", G.level.teamVoteYes[cs_offset]))
	else
		G.level.teamVoteNo[cs_offset] = G.level.teamVoteNo[cs_offset] + 1
		G.trap_SetConfigstring(C.CS_TEAMVOTE_NO + cs_offset, QS.va("%i", G.level.teamVoteNo[cs_offset]))
	end

	-- a majority will be determined in TeamCheckVote, which will also account
	-- for players entering or leaving
end

function G.Cmd_SetViewpos_f(ent)
	local origin = Q.vec3()
	local angles = Q.vec3()

	if G.g_cheats.integer == 0 then
		G.trap_SendServerCommand(ent.index, QS.va("print \"Cheats are not enabled on this server.\n\""))
		return
	end
	if G.trap_Argc() ~= 5 then
		G.trap_SendServerCommand(ent.index, QS.va("print \"usage: setviewpos x y z yaw\n\""))
		return
	end

	Q.VectorClear(angles)
	for i = 0, 2 do
		local buffer = G.trap_Argv(i + 1)
		origin[i] = QS.atof(buffer)
	end

	local buffer = G.trap_Argv(4)
	angles[C.YAW] = QS.atof(buffer)

	G.TeleportPlayer(ent, origin, angles)
end

function G.Cmd_GetMappage_f(ent)
	local arg = G.trap_Argv(1)
	local page = G.getMappage(QS.atoi(arg))
	local str = QS.Q_strncpyz(QS.va("mappage %d %s %s %s %s %s %s %s %s %s %s", page.pagenumber, page.mapname[0],
		page.mapname[1], page.mapname[2], page.mapname[3], page.mapname[4], page.mapname[5],
		page.mapname[6], page.mapname[7], page.mapname[8], page.mapname[9]), (C.MAX_MAPNAME + 1) * C.MAPS_PER_PAGE + 1)
	G.trap_SendServerCommand(ent.index, str)
end

-- KK-OAX This is the table that ClientCommands runs the console entry against.
G.cmds = {
	-- normal commands
	[0] = { cmdName = "team", cmdFlags = 0, cmdHandler = cmdfn("Cmd_Team_f") },
	{ cmdName = "vote", cmdFlags = 0, cmdHandler = cmdfn("Cmd_Vote_f") },

	-- communication commands
	{ cmdName = "tell", cmdFlags = C.CMD_MESSAGE, cmdHandler = cmdfn("Cmd_Tell_f") },
	{ cmdName = "callvote", cmdFlags = C.CMD_MESSAGE, cmdHandler = cmdfn("Cmd_CallVote_f") },
	{ cmdName = "callteamvote", cmdFlags = bit32.bor(C.CMD_MESSAGE, C.CMD_TEAM), cmdHandler = cmdfn("Cmd_CallTeamVote_f") },
	-- can be used even during intermission
	{ cmdName = "say", cmdFlags = bit32.bor(C.CMD_MESSAGE, C.CMD_INTERMISSION), cmdHandler = cmdfn("Cmd_Say_f") },
	{ cmdName = "say_team", cmdFlags = bit32.bor(C.CMD_MESSAGE, C.CMD_INTERMISSION), cmdHandler = cmdfn("Cmd_Say_f") },
	{ cmdName = "vsay", cmdFlags = bit32.bor(C.CMD_MESSAGE, C.CMD_INTERMISSION), cmdHandler = cmdfn("Cmd_Voice_f") },
	{ cmdName = "vsay_team", cmdFlags = bit32.bor(C.CMD_MESSAGE, C.CMD_INTERMISSION), cmdHandler = cmdfn("Cmd_Voice_f") },
	{ cmdName = "vsay_local", cmdFlags = bit32.bor(C.CMD_MESSAGE, C.CMD_INTERMISSION), cmdHandler = cmdfn("Cmd_Voice_f") },
	{ cmdName = "vtell", cmdFlags = bit32.bor(C.CMD_MESSAGE, C.CMD_INTERMISSION), cmdHandler = cmdfn("Cmd_VoiceTell_f") },
	{ cmdName = "vosay", cmdFlags = bit32.bor(C.CMD_MESSAGE, C.CMD_INTERMISSION), cmdHandler = cmdfn("Cmd_Voice_f") },
	{ cmdName = "vosay_team", cmdFlags = bit32.bor(C.CMD_MESSAGE, C.CMD_INTERMISSION), cmdHandler = cmdfn("Cmd_Voice_f") },
	{ cmdName = "vosay_local", cmdFlags = bit32.bor(C.CMD_MESSAGE, C.CMD_INTERMISSION), cmdHandler = cmdfn("Cmd_Voice_f") },
	{ cmdName = "votell", cmdFlags = bit32.bor(C.CMD_MESSAGE, C.CMD_INTERMISSION), cmdHandler = cmdfn("Cmd_VoiceTell_f") },
	{ cmdName = "vtaunt", cmdFlags = bit32.bor(C.CMD_MESSAGE, C.CMD_INTERMISSION), cmdHandler = cmdfn("Cmd_VoiceTaunt_f") },

	{ cmdName = "score", cmdFlags = C.CMD_INTERMISSION, cmdHandler = cmdfn("Cmd_Score_f") },
	{ cmdName = "acc", cmdFlags = C.CMD_INTERMISSION, cmdHandler = cmdfn("Cmd_Acc_f") },

	-- cheats
	{ cmdName = "give", cmdFlags = bit32.bor(C.CMD_CHEAT, C.CMD_LIVING), cmdHandler = cmdfn("Cmd_Give_f") },
	{ cmdName = "god", cmdFlags = bit32.bor(C.CMD_CHEAT, C.CMD_LIVING), cmdHandler = cmdfn("Cmd_God_f") },
	{ cmdName = "notarget", cmdFlags = bit32.bor(C.CMD_CHEAT, C.CMD_LIVING), cmdHandler = cmdfn("Cmd_Notarget_f") },
	{ cmdName = "levelshot", cmdFlags = C.CMD_CHEAT, cmdHandler = cmdfn("Cmd_LevelShot_f") },
	{ cmdName = "setviewpos", cmdFlags = C.CMD_CHEAT, cmdHandler = cmdfn("Cmd_SetViewpos_f") },
	{ cmdName = "noclip", cmdFlags = C.CMD_CHEAT, cmdHandler = cmdfn("Cmd_Noclip_f") },

	{ cmdName = "kill", cmdFlags = bit32.bor(C.CMD_TEAM, C.CMD_LIVING), cmdHandler = cmdfn("Cmd_Kill_f") },
	{ cmdName = "where", cmdFlags = 0, cmdHandler = cmdfn("Cmd_Where_f") },

	-- game commands

	{ cmdName = "follow", cmdFlags = C.CMD_NOTEAM, cmdHandler = cmdfn("Cmd_Follow_f") },
	{ cmdName = "follownext", cmdFlags = C.CMD_NOTEAM, cmdHandler = cmdfn("Cmd_FollowCycle_f") },
	{ cmdName = "followprev", cmdFlags = C.CMD_NOTEAM, cmdHandler = cmdfn("Cmd_FollowCycle_f") },

	{ cmdName = "teamvote", cmdFlags = C.CMD_TEAM, cmdHandler = cmdfn("Cmd_TeamVote_f") },
	{ cmdName = "teamtask", cmdFlags = C.CMD_TEAM, cmdHandler = cmdfn("Cmd_TeamTask_f") },
	-- KK-OAX
	{ cmdName = "freespectator", cmdFlags = C.CMD_NOTEAM, cmdHandler = cmdfn("StopFollowing") },
	{ cmdName = "getmappage", cmdFlags = 0, cmdHandler = cmdfn("Cmd_GetMappage_f") },
	{ cmdName = "gc", cmdFlags = 0, cmdHandler = cmdfn("Cmd_GameCommand_f") },
}

SF.numCmds = 0
while G.cmds[SF.numCmds] ~= nil do
	SF.numCmds = SF.numCmds + 1
end

-- KK-OAX, Takes the client command and runs it through a loop which matches
-- it against the table.
function G.ClientCommand(clientNum)
	local ent = G.g_entities[clientNum]
	if ent.client == nil or ent.client.pers.connected ~= C.CON_CONNECTED then
		if ent.client ~= nil and ent.client.pers.localClient then
			-- Handle early team command sent by UI when starting a local
			-- team play game.
			local cmd = G.trap_Argv(0)
			if QS.Q_stricmp(cmd, "team") == 0 then
				G.Cmd_Team_f(ent)
			end
		end
		return -- not fully in game yet
	end

	local cmd = G.trap_Argv(0)
	local cmds = G.cmds
	local numCmds = SF.numCmds

	local i = 0
	while i < numCmds do
		if QS.Q_strequal(cmd, cmds[i].cmdName) then
			break
		end
		i = i + 1
	end

	if i == numCmds then
		-- KK-OAX Admin Command Check
		if not G.G_admin_cmd_check(ent, false) then
			G.trap_SendServerCommand(clientNum, QS.va("print \"Unknown command %s\n\"", cmd))
		end
		return
	end

	local flags = cmds[i].cmdFlags

	-- do tests here to reduce the amount of repeated code
	if bit32.band(flags, C.CMD_INTERMISSION) == 0 and G.level.intermissiontime ~= 0 then
		return
	end

	if bit32.band(flags, C.CMD_CHEAT) ~= 0 and G.g_cheats.integer == 0 then
		G.trap_SendServerCommand(clientNum, "print \"Cheats are not enabled on this server\n\"")
		return
	end

	-- KK-OAX Do I need to change this for FFA gametype?
	if bit32.band(flags, C.CMD_TEAM) ~= 0 and ent.client.sess.sessionTeam == C.TEAM_SPECTATOR then
		G.trap_SendServerCommand(clientNum, "print \"Join a team first\n\"")
		return
	end

	if (bit32.band(flags, C.CMD_NOTEAM) ~= 0
		or (bit32.band(flags, C.CMD_CHEAT_TEAM) ~= 0 and G.g_cheats.integer == 0))
		and ent.client.sess.sessionTeam ~= C.TEAM_NONE then
		G.trap_SendServerCommand(clientNum, "print \"Cannot use this command when on a team\n\"")
		return
	end

	if bit32.band(flags, C.CMD_RED) ~= 0 and ent.client.sess.sessionTeam ~= C.TEAM_RED then
		G.trap_SendServerCommand(clientNum, "print \"Must be on the Red Team to use this command\n\"")
		return
	end

	if bit32.band(flags, C.CMD_BLUE) ~= 0 and ent.client.sess.sessionTeam ~= C.TEAM_BLUE then
		G.trap_SendServerCommand(clientNum, "print \"Must be on the Blue Team to use this command\n\"")
		return
	end

	if ent.client.ps.pm_type == C.PM_DEAD and bit32.band(flags, C.CMD_LIVING) ~= 0 then
		G.trap_SendServerCommand(clientNum, "print \"Must be alive to use this command\n\"")
		return
	end

	cmds[i].cmdHandler(ent)
end

return nil
