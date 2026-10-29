--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_possession.c).

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
-- Luau port of g_possession.c. Possession gametype neutral flag handling.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local possessionFlag = nil

local function Possession_create_neutral_obelisk(target)
	if possessionFlag ~= nil then
		return
	end
	local it = BG.BG_FindItem("Neutral Flag")
	possessionFlag = G.G_Spawn()
	Q.VectorCopy(target.r.currentOrigin, possessionFlag.s.origin)
	possessionFlag.classname = it.classname
	G.G_SpawnItem(possessionFlag, it)
	G.FinishSpawningItem(possessionFlag)
	G.Team_SetFlagStatus(C.TEAM_FREE, C.FLAG_ATBASE)
end

local function EntityFilterNoBotsOrHumanOnly(item)
	if bit32.band(item.flags, C.FL_NO_BOTS) ~= 0 or bit32.band(item.flags, C.FL_NO_HUMANS) ~= 0 then
		return false
	end
	return true
end

function G.Possession_SpawnFlag()
	if possessionFlag ~= nil then
		return
	end
	local ent = G.SelectRandomEntity("team_CTF_neutralflag")
	if ent ~= nil then
		possessionFlag = ent
		G.G_LogPrintf("Info: The map contains a white flag. We do not spawn a new one.\n")
		return
	end
	if ent == nil then
		ent = G.SelectRandomEntity("domination_point")
	end
	if ent == nil then
		ent = G.SelectRandomEntityFilter("info_player_deathmatch", EntityFilterNoBotsOrHumanOnly)
	end
	if ent == nil then
		ent = G.g_entities[0]
	end
	Possession_create_neutral_obelisk(ent)
end

function G.Possession_TouchFlag(other)
	local cl = other.client
	cl.ps.powerups[C.PW_NEUTRALFLAG] = 2147483647
	cl.pers.teamState.flagsince = G.level.time
	G.G_LogPrintf("POS: %i %i: %s^7 took the flag\n", other.s.number, 3, cl.pers.netname)
	return -1
end

return nil
