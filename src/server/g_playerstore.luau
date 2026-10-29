--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_playerstore.c).

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
-- Luau port of g_playerstore.c. Remembers persistant stats of leaving players by guid.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local MAX_PLAYERS_STORED = 32
local GUID_SIZE = 32

local function newEntry()
	local e = { guid = "", age = 0, persistant = {}, timePlayed = 0, accuracy = {} }
	for i = 0, C.MAX_PERSISTANT - 1 do
		e.persistant[i] = 0
	end
	for i = 0, C.WP_NUM_WEAPONS - 1 do
		e.accuracy[i] = { [0] = 0, 0 }
	end
	return e
end

local playerstore = {}
for i = 0, MAX_PLAYERS_STORED - 1 do
	playerstore[i] = newEntry()
end

local nextAge = 0

function G.LogAcc(clientNum)
	local buffer = QS.Com_sprintf(1024, "Accuracy: %i ", clientNum)
	local first = true
	local cl = G.level.clients[clientNum]
	for i = 0, C.WP_NUM_WEAPONS - 1 do
		local tmp = QS.va("%sf%i\\%i\\h%i\\%i", if first then "" else "\\", i, cl.accuracy[i][0], i, cl.accuracy[i][1])
		if #tmp + #buffer + 1 + 1 < 1024 then
			buffer = buffer .. tmp
		end
		first = false
	end
	G.G_LogPrintf("%s\n", buffer)
end

function G.PlayerStoreInit()
	for i = 0, MAX_PLAYERS_STORED - 1 do
		playerstore[i] = newEntry()
	end
	nextAge = 1
end

function G.PlayerStore_store(guid, ps)
	local place2store = -1
	local lowestAge = 32000
	G.LogAcc(ps.clientNum)
	if #guid < 32 then
		G.G_LogPrintf("Playerstore: Failed to store player. Invalid guid: %s\n", guid)
		return
	end
	for i = 0, MAX_PLAYERS_STORED - 1 do
		if QS.Q_strequal(guid, playerstore[i].guid) then
			place2store = i
		end
	end

	if place2store < 0 then
		for i = 0, MAX_PLAYERS_STORED - 1 do
			if playerstore[i].age < lowestAge then
				place2store = i
				lowestAge = playerstore[i].age
			end
		end
	end

	if place2store < 0 then
		place2store = 0
	end
	local e = playerstore[place2store]
	e.age = nextAge
	nextAge += 1
	e.guid = QS.Q_strncpyz(guid, GUID_SIZE + 1)
	for i = 0, C.MAX_PERSISTANT - 1 do
		e.persistant[i] = ps.persistant[i]
	end
	local cl = G.level.clients[ps.clientNum]
	for i = 0, C.WP_NUM_WEAPONS - 1 do
		e.accuracy[i][0] = cl.accuracy[i][0]
		e.accuracy[i][1] = cl.accuracy[i][1]
	end
	e.timePlayed = G.level.time - cl.pers.enterTime
	G.G_LogPrintf("Playerstore: Stored player with guid: %s in %u\n", e.guid, place2store)
end

function G.PlayerStore_restore(guid, ps)
	if #guid < 32 then
		G.G_LogPrintf("Playerstore: Failed to restore player. Invalid guid: %s\n", guid)
		return
	end
	for i = 0, MAX_PLAYERS_STORED - 1 do
		local e = playerstore[i]
		if QS.Q_strequaln(guid, e.guid, GUID_SIZE) and e.age ~= -1 then
			for j = 0, C.MAX_PERSISTANT - 1 do
				ps.persistant[j] = e.persistant[j]
			end
			local cl = G.level.clients[ps.clientNum]
			for j = 0, C.WP_NUM_WEAPONS - 1 do
				cl.accuracy[j][0] = e.accuracy[j][0]
				cl.accuracy[j][1] = e.accuracy[j][1]
			end
			cl.pers.enterTime = G.level.time - e.timePlayed
			if ps.persistant[C.PERS_SCORE] < 0 then
				ps.persistant[C.PERS_SCORE] = 0
			end
			e.age = -1
			G.G_LogPrintf("Restored player with guid: %s\n", guid)
			return
		end
	end
	G.G_LogPrintf("Playerstore: Nothing to restore. Guid: %s\n", guid)
end

return nil
