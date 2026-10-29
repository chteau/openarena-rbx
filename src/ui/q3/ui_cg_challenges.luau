--[[
===========================================================================
Copyright (C) 2008 Poul Sander

This file is part of Open Arena source code.

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
-- Luau port of code/cgame/cg_challenges.c (OpenArena gamecode), as the q3_ui
-- module links it: the ui VM keeps its own copy of the challenge table.

local U = require(script.Parent.U)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local FILENAME = "challenges.dat"

-- The challengeTable is of constant size so there is room for more challenges being added in the furture
local challengeTable = {}
for i = 0, C.CHALLENGES_MAX - 1 do
	challengeTable[i] = 0
end
local challengesInitialized = false

-- This function initializes the challenge system. It has no effect if the system is already intialized.
function U.challenges_init()
	if challengesInitialized then
		return
	end

	local tableSize = C.CHALLENGES_MAX * 4
	local fileLen, file = trap.FS_FOpenFile(FILENAME, C.FS_READ)

	-- If the file not is big enough to contain all challenges then initialize from zero
	if fileLen < tableSize then
		trap.FS_FCloseFile(file)
		for i = 0, C.CHALLENGES_MAX - 1 do
			challengeTable[i] = 0
		end
		challengesInitialized = true
		return
	end

	local data = trap.FS_Read(tableSize, file)
	for i = 0, C.CHALLENGES_MAX - 1 do
		challengeTable[i] = string.unpack("<I4", data, i * 4 + 1)
	end

	trap.FS_FCloseFile(file)
	challengesInitialized = true
end

-- This functions saves the challenges. It should be called from the shutdown function
function U.challenges_save()
	if not challengesInitialized then
		return
	end
	local fileStatus, file = trap.FS_FOpenFile(FILENAME, C.FS_WRITE)
	if fileStatus < 0 then
		U.Com_Printf("Failed to open challenges.dat for writing\n")
		return
	end
	for i = 0, C.CHALLENGES_MAX - 1 do
		trap.FS_Write(string.pack("<I4", challengeTable[i]), 4, file)
	end

	trap.FS_FCloseFile(file)
	-- changes after this will most likely not be saved anyway.
	challengesInitialized = false
	U.Com_Printf("Wrote challenges.cfg\n")
end

-- Get the number of times a given challenge has been completed
function U.getChallenge(challenge)
	U.challenges_init()
	if challenge >= C.CHALLENGES_MAX then
		return 0
	end
	return challengeTable[challenge]
end

function U.addChallenge(challenge)
	if challenge >= C.CHALLENGES_MAX then
		U.Com_Printf(string.format("Challenge #%u is >=CHALLENGES_MAX\n", challenge))
		return
	end
	U.challenges_init()
	challengeTable[challenge] = bit32.band(challengeTable[challenge] + 1, 0xFFFFFFFF)
end

return U
