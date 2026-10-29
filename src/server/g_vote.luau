--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_vote.c).

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
-- Luau port of g_vote.c. Vote permission checks, vote counting and custom vote files.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local MAX_VOTENAME_LENGTH = 14
local MAX_GAMETYPENAME_LENGTH = 5
local MAX_CUSTOM_VOTES = 12
local MAX_CUSTOMNAME = 32
local MAX_CUSTOMDISPLAYNAME = 50
local MAX_CUSTOMCOMMAND = 100

G.custom_vote_info = ""

function G.allowedVote(commandStr)
	local voteNames = G.trap_Cvar_VariableStringBuffer("g_voteNames")
	if QS.Q_strequal(voteNames, "*") then
		return true
	end
	local length = #commandStr
	if length > MAX_VOTENAME_LENGTH - 3 then
		return false
	end
	local tempStr = "/" .. commandStr .. "/"
	if QS.Q_stristr(voteNames, tempStr) ~= nil then
		return true
	else
		return false
	end
end

function G.getMappage(page)
	local result = S.t_mappage()
	local token
	local buffer = ""

	local _, file = G.trap_FS_FOpenFile(G.g_votemaps.string, C.FS_READ)
	if file ~= 0 then
		buffer = G.trap_FS_Read(C.MAX_MAPNAME_BUFFER, file)
		local pointer = QS.cursor(buffer)
		token = QS.COM_Parse(pointer)
		if token == "" and page == 0 then
			result.pagenumber = -1
			G.trap_FS_FCloseFile(file)
			return result
		end
		for _ = 0, C.MAPS_PER_PAGE * page - 1 do
			token = QS.COM_Parse(pointer)
		end
		if token == nil or token == "" then
			G.trap_FS_FCloseFile(file)
			return G.getMappage(0)
		end
		result.pagenumber = page
		local i = 0
		while i < C.MAPS_PER_PAGE and token ~= nil do
			result.mapname[i] = QS.Q_strncpyz(token, C.MAX_MAPNAME)
			token = QS.COM_Parse(pointer)
			i += 1
		end
		G.trap_FS_FCloseFile(file)
		return result
	end
	local nummaps, names = G.trap_FS_GetFileList("maps", ".bsp")

	if nummaps ~= 0 and nummaps <= C.MAPS_PER_PAGE * page then
		return G.getMappage(0)
	end

	result.pagenumber = page

	for i = 0, nummaps - 1 do
		local pointer = names[i]
		local maplen = #pointer
		if i >= C.MAPS_PER_PAGE * page and i < C.MAPS_PER_PAGE * (page + 1) then
			result.mapname[i - C.MAPS_PER_PAGE * page] = QS.Q_strncpyz(pointer, maplen - 3)
		end
	end
	return result
end

function G.allowedMap(mapname)
	local _, file = G.trap_FS_FOpenFile(QS.va("maps/%s.bsp", mapname), C.FS_READ)
	if file == 0 then
		return false
	end
	G.trap_FS_FCloseFile(file)

	_, file = G.trap_FS_FOpenFile(G.g_votemaps.string, C.FS_READ)

	if file == 0 then
		return true
	end
	local length = #mapname
	if length > C.MAX_MAPNAME_LENGTH - 3 then
		G.trap_FS_FCloseFile(file)
		return false
	end

	local buffer = G.trap_FS_Read(C.MAX_MAPS_TEXT, file)
	local found = false
	local pointer = QS.cursor(buffer)
	local token = QS.COM_Parse(pointer)
	while token ~= "" and not found do
		if QS.Q_strequal(token, mapname) then
			found = true
		end
		token = QS.COM_Parse(pointer)
	end

	G.trap_FS_FCloseFile(file)
	return found
end

function G.allowedGametype(gametypeStr)
	local voteGametypes = G.trap_Cvar_VariableStringBuffer("g_voteGametypes")
	if QS.Q_strequal(voteGametypes, "*") then
		return true
	end
	local length = #gametypeStr
	if length > MAX_GAMETYPENAME_LENGTH - 3 then
		return false
	end
	local tempStr = "/" .. gametypeStr .. "/"
	if QS.Q_stristr(voteGametypes, tempStr) ~= nil then
		return true
	else
		return false
	end
end

function G.allowedTimelimit(limit)
	local min = G.g_voteMinTimelimit.integer
	local max = G.g_voteMaxTimelimit.integer
	if limit < min and limit ~= 0 then
		return false
	end
	if max ~= 0 and limit > max then
		return false
	end
	if limit == 0 and max > 0 then
		return false
	end
	return true
end

function G.allowedFraglimit(limit)
	local min = G.g_voteMinFraglimit.integer
	local max = G.g_voteMaxFraglimit.integer
	if limit < min and limit ~= 0 then
		return false
	end
	if max ~= 0 and limit > max then
		return false
	end
	if limit == 0 and max > 0 then
		return false
	end
	return true
end

-- Reads votecustom.cfg and collects the commands usable with "/callvote custom COMMAND".
function G.VoteParseCustomVotes()
	local _, file = G.trap_FS_FOpenFile(G.g_votecustom.string, C.FS_READ)

	if file == 0 then
		return 0
	end

	G.custom_vote_info = ""

	local commands = 0

	local buffer = G.trap_FS_Read(4 * 1024, file)

	local pointer = QS.cursor(buffer)

	while commands < MAX_CUSTOM_VOTES do
		local token = QS.COM_Parse(pointer)
		if token == "" then
			break
		end

		if token == "votecommand" then
			token = QS.COM_Parse(pointer)
			G.custom_vote_info = QS.Q_strcat(G.custom_vote_info, 1024, QS.va("%s ", token))
			commands += 1
		end
	end

	G.trap_FS_FCloseFile(file)

	return commands
end

function G.getCustomVote(votecommand)
	local result = S.t_customvote()

	local _, file = G.trap_FS_FOpenFile(G.g_votecustom.string, C.FS_READ)

	if file == 0 then
		return S.t_customvote()
	end

	local buffer = G.trap_FS_Read(4 * 1024, file)

	G.trap_FS_FCloseFile(file)

	local pointer = QS.cursor(buffer)

	while true do
		local token = QS.COM_Parse(pointer)
		if token == "" then
			break
		end

		if token ~= "{" then
			G.Com_Printf("Missing { in votecustom.cfg\n")
			break
		end

		result = S.t_customvote()

		while true do
			token = QS.COM_ParseExt(pointer, true)
			if token == "" then
				G.Com_Printf("Unexpected end of customvote.cfg\n")
				break
			end
			if token == "}" then
				break
			end
			local key = QS.Q_strncpyz(token, QS.MAX_TOKEN_CHARS)

			token = QS.COM_ParseExt(pointer, false)
			if token == "" then
				G.Com_Printf("Invalid/missing argument to %s in customvote.cfg\n", key)
			end
			if QS.Q_strequal(key, "votecommand") then
				result.votename = QS.Q_strncpyz(token, MAX_CUSTOMNAME)
			elseif QS.Q_strequal(key, "displayname") then
				result.displayname = QS.Q_strncpyz(token, MAX_CUSTOMDISPLAYNAME)
			elseif QS.Q_strequal(key, "command") then
				result.command = QS.Q_strncpyz(token, MAX_CUSTOMCOMMAND)
			else
				G.Com_Printf("Unknown key in customvote.cfg: %s\n", key)
			end
		end

		if QS.Q_strequal(result.votename, votecommand) then
			return result
		end
	end

	return S.t_customvote()
end

function G.whiteListedStr(str)
	local out = {}
	local destIndex = 0
	local sourceLength = #str
	local sourceIndex = 0
	while sourceIndex < sourceLength and destIndex < 1024 do
		local a = string.byte(str, sourceIndex + 1)
		if (a >= 97 and a <= 122) or (a >= 65 and a <= 90) or (a >= 48 and a <= 57) or a == 32 or a == 63 then
			destIndex += 1
			out[destIndex] = string.char(a)
		end
		sourceIndex += 1
	end
	if destIndex >= 1024 then
		destIndex = 1023
	end
	return table.concat(out, "", 1, destIndex)
end

function G.CheckVote()
	local level = G.level
	if level.voteExecuteTime ~= 0 and level.voteExecuteTime < level.time then
		level.voteExecuteTime = 0
		G.trap_SendConsoleCommand(C.EXEC_APPEND, QS.va("%s\n", level.voteString))
	end
	if level.voteTime == 0 then
		return
	end
	if level.time - level.voteTime >= C.VOTE_TIME then
		if bit32.band(G.g_dmflags.integer, C.DF_LIGHT_VOTING) ~= 0 then
			if level.voteYes > level.voteNo * 2 then
				G.trap_SendServerCommand(-1, QS.va("print \"Vote passed. At least 2 of 3 voted yes (%s)\n\"", G.whiteListedStr(level.voteDisplayString)))
				level.voteExecuteTime = level.time + 3000
			else
				if level.voteYes > level.voteNo and level.voteYes >= 2 and (level.voteYes * 10) > (level.numVotingClients * 3) then
					G.trap_SendServerCommand(-1, QS.va("print \"Vote passed. More yes than no. (%s)\n\"", G.whiteListedStr(level.voteDisplayString)))
					level.voteExecuteTime = level.time + 3000
				else
					G.trap_SendServerCommand(-1, QS.va("print \"Vote failed. (%s)\n\"", G.whiteListedStr(level.voteDisplayString)))
				end
			end
		else
			G.trap_SendServerCommand(-1, QS.va("print \"Vote failed. (%s)\n\"", G.whiteListedStr(level.voteDisplayString)))
		end
	else
		if level.voteYes > Q.idiv(level.numVotingClients, 2) then
			G.trap_SendServerCommand(-1, QS.va("print \"Vote passed. (%s)\n\"", G.whiteListedStr(level.voteDisplayString)))
			level.voteExecuteTime = level.time + 3000
		elseif level.voteNo >= Q.idiv(level.numVotingClients, 2) then
			G.trap_SendServerCommand(-1, QS.va("print \"Vote failed. (%s)\n\"", G.whiteListedStr(level.voteDisplayString)))
		else
			return
		end
	end
	level.voteTime = 0
	G.trap_SetConfigstring(C.CS_VOTE_TIME, "")
end

function G.ForceFail()
	local level = G.level
	level.voteTime = 0
	level.voteExecuteTime = 0
	level.voteString = ""
	level.voteDisplayString = ""
	level.voteKickClient = -1
	level.voteKickType = 0
	G.trap_SetConfigstring(C.CS_VOTE_TIME, "")
	G.trap_SetConfigstring(C.CS_VOTE_STRING, "")
	G.trap_SetConfigstring(C.CS_VOTE_YES, "")
	G.trap_SetConfigstring(C.CS_VOTE_NO, "")
end

-- Iterates through all the clients and counts the votes
function G.CountVotes()
	local level = G.level
	local yes = 0
	local no = 0

	level.numVotingClients = 0

	for i = 0, level.maxclients - 1 do
		if level.clients[i].pers.connected ~= C.CON_CONNECTED then
			continue
		end

		if level.clients[i].sess.sessionTeam == C.TEAM_SPECTATOR then
			continue
		end

		if bit32.band(G.g_entities[i].r.svFlags, C.SVF_BOT) ~= 0 then
			continue
		end

		level.numVotingClients += 1

		if level.clients[i].vote > 0 then
			yes += 1
		end

		if level.clients[i].vote < 0 then
			no += 1
		end
	end

	if level.voteYes ~= yes then
		level.voteYes = yes
		G.trap_SetConfigstring(C.CS_VOTE_YES, QS.va("%i", level.voteYes))
	end

	if level.voteNo ~= no then
		level.voteNo = no
		G.trap_SetConfigstring(C.CS_VOTE_NO, QS.va("%i", level.voteNo))
	end
end

function G.ClientLeaving(clientNumber)
	if clientNumber == G.level.voteKickClient then
		G.ForceFail()
	end
end

return nil
