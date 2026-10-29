--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_aas_bspq3.c).

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
-- Luau port of be_aas_bspq3.c: BSP, environment sampling and BSP entity parsing.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local QS = require("../../../shared/q_shared")

local MAX_BSPENTITIES = 2048

local function newBspWorld()
	local entities = {}
	for i = 0, MAX_BSPENTITIES - 1 do
		entities[i] = { epairs = nil }
	end
	return {
		loaded = 0,
		entdatasize = 0,
		dentdata = nil,
		numentities = 0,
		entities = entities,
	}
end

--global bsp
local bspworld = newBspWorld()
B.bspworld = bspworld

function B.AAS_Trace(start, mins, maxs, end_, passent, contentmask)
	local bsptrace = SB.bsp_trace_t()
	B.botimport.Trace(bsptrace, start, mins, maxs, end_, passent, contentmask)
	return bsptrace
end

function B.AAS_PointContents(point)
	return B.botimport.PointContents(point)
end

function B.AAS_EntityCollision(entnum, start, boxmins, boxmaxs, end_, contentmask, trace)
	local enttrace = SB.bsp_trace_t()

	B.botimport.EntityTrace(enttrace, start, boxmins, boxmaxs, end_, entnum, contentmask)
	if enttrace.fraction < trace.fraction then
		SB.copy_bsp_trace_t(trace, enttrace)
		return true
	end
	return false
end

function B.AAS_inPVS(p1, p2)
	return B.botimport.inPVS(p1, p2)
end

function B.AAS_inPHS(p1, p2)
	return true
end

function B.AAS_BSPModelMinsMaxsOrigin(modelnum, angles, mins, maxs, origin)
	B.botimport.BSPModelMinsMaxsOrigin(modelnum, angles, mins, maxs, origin)
end

function B.AAS_UnlinkFromBSPLeaves(leaves) end

function B.AAS_BSPLinkEntity(absmins, absmaxs, entnum, modelnum)
	return nil
end

function B.AAS_BoxEntities(absmins, absmaxs, list, maxcount)
	return 0
end

function B.AAS_NextBSPEntity(ent)
	ent = ent + 1
	if ent >= 1 and ent < bspworld.numentities then
		return ent
	end
	return 0
end

function B.AAS_BSPEntityInRange(ent)
	if ent <= 0 or ent >= bspworld.numentities then
		B.botimport.Print(BC.PRT_MESSAGE, "bsp entity out of range\n")
		return 0
	end
	return 1
end

function B.AAS_ValueForBSPEpairKey(ent, key, size)
	local value = ""
	if B.AAS_BSPEntityInRange(ent) == 0 then
		return 0, value
	end
	local epair = bspworld.entities[ent].epairs
	while epair ~= nil do
		if epair.key == key then
			value = QS.Q_strncpyz(epair.value, size)
			return 1, value
		end
		epair = epair.next
	end
	return 0, value
end

function B.AAS_VectorForBSPEpairKey(ent, key, v)
	v[0], v[1], v[2] = 0, 0, 0
	local ok, buf = B.AAS_ValueForBSPEpairKey(ent, key, BC.MAX_EPAIRKEY)
	if ok == 0 then
		return 0
	end
	--scanf into doubles, then assign, so it is vec_t size independent
	local vals = { 0, 0, 0 }
	local n = 0
	for word in string.gmatch(buf, "%S+") do
		if n >= 3 then
			break
		end
		n = n + 1
		vals[n] = QS.atof(word)
	end
	v[0] = vals[1]
	v[1] = vals[2]
	v[2] = vals[3]
	return 1
end

function B.AAS_FloatForBSPEpairKey(ent, key)
	local ok, buf = B.AAS_ValueForBSPEpairKey(ent, key, BC.MAX_EPAIRKEY)
	if ok == 0 then
		return 0, 0
	end
	return 1, QS.atof(buf)
end

function B.AAS_IntForBSPEpairKey(ent, key)
	local ok, buf = B.AAS_ValueForBSPEpairKey(ent, key, BC.MAX_EPAIRKEY)
	if ok == 0 then
		return 0, 0
	end
	return 1, QS.atoi(buf)
end

function B.AAS_FreeBSPEntities()
	for i = 1, bspworld.numentities - 1 do
		local ent = bspworld.entities[i]
		local epair = ent.epairs
		while epair ~= nil do
			local nextepair = epair.next
			epair.key = nil
			epair.value = nil
			epair = nextepair
		end
	end
	bspworld.numentities = 0
end

function B.AAS_ParseBSPEntities()
	local token = SB.token_t()

	local script = B.LoadScriptMemory(bspworld.dentdata, bspworld.entdatasize, "entdata")
	B.SetScriptFlags(script, bit32.bor(BC.SCFL_NOSTRINGWHITESPACES, BC.SCFL_NOSTRINGESCAPECHARS))

	bspworld.numentities = 1

	while B.PS_ReadToken(script, token) ~= 0 do
		if token.string ~= "{" then
			B.ScriptError(script, "invalid %s", token.string)
			B.AAS_FreeBSPEntities()
			B.FreeScript(script)
			return
		end
		if bspworld.numentities >= MAX_BSPENTITIES then
			B.botimport.Print(BC.PRT_MESSAGE, "too many entities in BSP file\n")
			break
		end
		local ent = bspworld.entities[bspworld.numentities]
		bspworld.numentities = bspworld.numentities + 1
		ent.epairs = nil
		while B.PS_ReadToken(script, token) ~= 0 do
			if token.string == "}" then
				break
			end
			local epair = { key = nil, value = nil, next = ent.epairs }
			ent.epairs = epair
			if token.type ~= BC.TT_STRING then
				B.ScriptError(script, "invalid %s", token.string)
				B.AAS_FreeBSPEntities()
				B.FreeScript(script)
				return
			end
			token.string = B.StripDoubleQuotes(token.string)
			epair.key = token.string
			if B.PS_ExpectTokenType(script, BC.TT_STRING, 0, token) == 0 then
				B.AAS_FreeBSPEntities()
				B.FreeScript(script)
				return
			end
			token.string = B.StripDoubleQuotes(token.string)
			epair.value = token.string
		end
		if token.string ~= "}" then
			B.ScriptError(script, "missing }")
			B.AAS_FreeBSPEntities()
			B.FreeScript(script)
			return
		end
	end
	B.FreeScript(script)
end

function B.AAS_BSPTraceLight(start, end_, endpos)
	return 0, 0, 0, 0
end

function B.AAS_DumpBSPData()
	B.AAS_FreeBSPEntities()

	bspworld.dentdata = nil
	bspworld.entdatasize = 0
	--
	bspworld.loaded = 0
	bspworld.numentities = 0
	for i = 0, MAX_BSPENTITIES - 1 do
		bspworld.entities[i].epairs = nil
	end
end

function B.AAS_LoadBSPFile()
	B.AAS_DumpBSPData()
	local data = B.botimport.BSPEntityData()
	bspworld.entdatasize = #data + 1
	bspworld.dentdata = data .. "\0"
	B.AAS_ParseBSPEntities()
	bspworld.loaded = 1
	return BC.BLERR_NOERROR
end

return nil
