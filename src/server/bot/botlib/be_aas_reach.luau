--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_aas_reach.c and be_aas_cluster.c, runtime part).

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
-- Luau port of be_aas_reach.c and be_aas_cluster.c (botlib/be_aas_reach.c and be_aas_cluster.c, runtime part): reachability queries and init.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")
local QS = require("../../../shared/q_shared")

-- returns the surface area of the given face
function B.AAS_FaceArea(face)
	local aasworld = B.aasworld
	local edgenum = aasworld.edgeindex[face.firstedge]
	local side = if edgenum < 0 then 1 else 0
	local edge = aasworld.edges[math.abs(edgenum)]
	local v = aasworld.vertexes[edge.v[side]]
	local d1 = { [0] = 0, 0, 0 }
	local d2 = { [0] = 0, 0, 0 }
	local cross = { [0] = 0, 0, 0 }

	local total = 0
	for i = 1, face.numedges - 2 do
		edgenum = aasworld.edgeindex[face.firstedge + i]
		side = if edgenum < 0 then 1 else 0
		edge = aasworld.edges[math.abs(edgenum)]
		Q.VectorSubtract(aasworld.vertexes[edge.v[side]], v, d1)
		Q.VectorSubtract(aasworld.vertexes[edge.v[1 - side]], v, d2)
		Q.CrossProduct(d1, d2, cross)
		total = Q.f(total + Q.f(0.5 * Q.VectorLength(cross)))
	end
	return total
end

-- returns the volume of an area
function B.AAS_AreaVolume(areanum)
	local aasworld = B.aasworld
	local corner = { [0] = 0, 0, 0 }

	local area = aasworld.areas[areanum]
	local facenum = aasworld.faceindex[area.firstface]
	local face = aasworld.faces[math.abs(facenum)]
	local edgenum = aasworld.edgeindex[face.firstedge]
	local edge = aasworld.edges[math.abs(edgenum)]
	--
	Q.VectorCopy(aasworld.vertexes[edge.v[0]], corner)

	--make tetrahedrons to all other faces
	local volume = 0
	for i = 0, area.numfaces - 1 do
		facenum = math.abs(aasworld.faceindex[area.firstface + i])
		face = aasworld.faces[facenum]
		local side = if face.backarea ~= areanum then 1 else 0
		local plane = aasworld.planes[bit32.bxor(face.planenum, side)]
		local d = Q.f(-Q.f(Q.DotProduct(corner, plane.normal) - plane.dist))
		local a = B.AAS_FaceArea(face)
		volume = Q.f(volume + Q.f(d * a))
	end

	volume = Q.f(volume / 3)
	return volume
end

function B.AAS_BestReachableLinkArea(areas)
	local link = areas
	while link ~= nil do
		if B.AAS_AreaGrounded(link.areanum) ~= 0 or B.AAS_AreaSwim(link.areanum) ~= 0 then
			return link.areanum
		end
		link = link.next_area
	end
	--
	link = areas
	while link ~= nil do
		if link.areanum ~= 0 then
			return link.areanum
		end
		--FIXME: this is a bad idea when the reachability is not yet
		-- calculated when the level items are loaded
		if B.AAS_AreaReachability(link.areanum) ~= 0 then
			return link.areanum
		end
		link = link.next_area
	end
	return 0
end

-- derives the jump pad start, brush bounds and launch velocity of a trigger_push entity
local function AAS_GetJumpPadInfo(ent, areastart, absmins, absmaxs, velocity)
	local angles = { [0] = 0, 0, 0 }
	local mins = { [0] = 0, 0, 0 }
	local maxs = { [0] = 0, 0, 0 }
	local origin = { [0] = 0, 0, 0 }
	local teststart = { [0] = 0, 0, 0 }
	local ent2origin = { [0] = 0, 0, 0 }

	local _, speed = B.AAS_FloatForBSPEpairKey(ent, "speed")
	if speed == 0 then
		speed = 1000
	end
	--get the mins, maxs and origin of the model
	local _, model = B.AAS_ValueForBSPEpairKey(ent, "model", BC.MAX_EPAIRKEY)
	local modelnum
	if model ~= "" then
		modelnum = QS.atoi(string.sub(model, 2))
	else
		modelnum = 0
	end
	B.AAS_BSPModelMinsMaxsOrigin(modelnum, angles, mins, maxs, nil)
	Q.VectorAdd(mins, maxs, origin)
	Q.VectorScale(origin, 0.5, origin)
	Q.VectorCopy(mins, absmins)
	Q.VectorCopy(maxs, absmaxs)
	--get the start areas
	Q.VectorCopy(origin, teststart)
	teststart[2] = Q.f(teststart[2] + 64)
	local trace = B.AAS_TraceClientBBox(teststart, origin, BC.PRESENCE_CROUCH, -1)
	if trace.startsolid then
		B.botimport.Print(BC.PRT_MESSAGE, "trigger_push start solid\n")
		Q.VectorCopy(origin, areastart)
	else
		Q.VectorCopy(trace.endpos, areastart)
	end
	areastart[2] = Q.f(areastart[2] + 0.125)
	--get the target entity
	local _, target = B.AAS_ValueForBSPEpairKey(ent, "target", BC.MAX_EPAIRKEY)
	local ent2 = B.AAS_NextBSPEntity(0)
	while ent2 ~= 0 do
		local ok, targetname = B.AAS_ValueForBSPEpairKey(ent2, "targetname", BC.MAX_EPAIRKEY)
		if ok ~= 0 and targetname == target then
			break
		end
		ent2 = B.AAS_NextBSPEntity(ent2)
	end
	if ent2 == 0 then
		B.botimport.Print(BC.PRT_MESSAGE, "trigger_push without target entity %s\n", target)
		return 0
	end
	B.AAS_VectorForBSPEpairKey(ent2, "origin", ent2origin)
	--
	local height = Q.f(ent2origin[2] - origin[2])
	local gravity = B.aassettings.phys_gravity
	local time = Q.f(math.sqrt(Q.f(height / Q.f(0.5 * gravity))))
	if time == 0 then
		B.botimport.Print(BC.PRT_MESSAGE, "trigger_push without time\n")
		return 0
	end
	-- set s.origin2 to the push velocity
	Q.VectorSubtract(ent2origin, origin, velocity)
	local dist = Q.VectorNormalizeIoq3(velocity)
	local forward = Q.f(dist / time)
	Q.VectorScale(velocity, forward, velocity)
	velocity[2] = Q.f(time * gravity)
	return 1
end

function B.AAS_BestReachableFromJumpPadArea(origin, mins, maxs)
	local areastart = { [0] = 0, 0, 0 }
	local cmdmove = { [0] = 0, 0, 0 }
	local bboxmins = { [0] = 0, 0, 0 }
	local bboxmaxs = { [0] = 0, 0, 0 }
	local absmins = { [0] = 0, 0, 0 }
	local absmaxs = { [0] = 0, 0, 0 }
	local velocity = { [0] = 0, 0, 0 }

	local bot_visualizejumppads = Q.trunc(B.LibVarValue("bot_visualizejumppads", "0"))
	Q.VectorAdd(origin, mins, bboxmins)
	Q.VectorAdd(origin, maxs, bboxmaxs)
	local ent = B.AAS_NextBSPEntity(0)
	while ent ~= 0 do
		local ok, classname = B.AAS_ValueForBSPEpairKey(ent, "classname", BC.MAX_EPAIRKEY)
		if ok ~= 0 and classname == "trigger_push" and AAS_GetJumpPadInfo(ent, areastart, absmins, absmaxs, velocity) ~= 0 then
			--get the areas the jump pad brush is in
			local areas = B.AAS_LinkEntityClientBBox(absmins, absmaxs, -1, BC.PRESENCE_CROUCH)
			local link = areas
			while link ~= nil do
				if B.AAS_AreaJumpPad(link.areanum) ~= 0 then
					break
				end
				link = link.next_area
			end
			if link == nil then
				B.botimport.Print(BC.PRT_MESSAGE, "trigger_push not in any jump pad area\n")
				B.AAS_UnlinkFromAreas(areas)
			else
				Q.VectorSet(cmdmove, 0, 0, 0)
				local move = SB.aas_clientmove_t()
				B.AAS_ClientMovementHitBBox(move, -1, areastart, BC.PRESENCE_NORMAL, 0,
					velocity, cmdmove, 0, 30, Q.f(0.1), bboxmins, bboxmaxs, bot_visualizejumppads)
				if move.frames < 30 then
					local bestareanum = 0
					local bestareavolume = 0
					link = areas
					while link ~= nil do
						if B.AAS_AreaJumpPad(link.areanum) ~= 0 then
							local volume = B.AAS_AreaVolume(link.areanum)
							if volume >= bestareavolume then
								bestareanum = link.areanum
								bestareavolume = volume
							end
						end
						link = link.next_area
					end
					B.AAS_UnlinkFromAreas(areas)
					return bestareanum
				end
				B.AAS_UnlinkFromAreas(areas)
			end
		end
		ent = B.AAS_NextBSPEntity(ent)
	end
	return 0
end

function B.AAS_BestReachableArea(origin, mins, maxs, goalorigin)
	local aasworld = B.aasworld
	local absmins = { [0] = 0, 0, 0 }
	local absmaxs = { [0] = 0, 0, 0 }
	local start = { [0] = 0, 0, 0 }
	local end_ = { [0] = 0, 0, 0 }

	if aasworld.loaded == 0 then
		B.botimport.Print(BC.PRT_ERROR, "AAS_BestReachableArea: aas not loaded\n")
		return 0
	end
	--find a point in an area
	Q.VectorCopy(origin, start)
	local areanum = B.AAS_PointAreaNum(start)
	--while no area found fudge around a little
	local i = 0
	while i < 5 and areanum == 0 do
		local j = 0
		while j < 5 and areanum == 0 do
			local k = -1
			while k <= 1 and areanum == 0 do
				local l = -1
				while l <= 1 and areanum == 0 do
					Q.VectorCopy(origin, start)
					start[0] = Q.f(start[0] + Q.f(j * 4 * k))
					start[1] = Q.f(start[1] + Q.f(j * 4 * l))
					start[2] = Q.f(start[2] + Q.f(i * 4))
					areanum = B.AAS_PointAreaNum(start)
					l = l + 1
				end
				k = k + 1
			end
			j = j + 1
		end
		i = i + 1
	end
	--if an area was found
	if areanum ~= 0 then
		--drop client bbox down and try again
		Q.VectorCopy(start, end_)
		start[2] = Q.f(start[2] + 0.25)
		end_[2] = Q.f(end_[2] - 50)
		local trace = B.AAS_TraceClientBBox(start, end_, BC.PRESENCE_CROUCH, -1)
		if not trace.startsolid then
			areanum = B.AAS_PointAreaNum(trace.endpos)
			Q.VectorCopy(trace.endpos, goalorigin)
			--FIXME: cannot enable next line right now because the reachability
			-- does not have to be calculated when the level items are loaded
			if areanum ~= 0 then
				return areanum
			end
		else
			--it can very well happen that the AAS_PointAreaNum function tells that
			--a point is in an area and that starting an AAS_TraceClientBBox from that
			--point will return trace.startsolid qtrue
			Q.VectorCopy(start, goalorigin)
			return areanum
		end
	end
	--NOTE: the goal origin does not have to be in the goal area
	-- because the bot will have to move towards the item origin anyway
	Q.VectorCopy(origin, goalorigin)
	--
	Q.VectorAdd(origin, mins, absmins)
	Q.VectorAdd(origin, maxs, absmaxs)
	--link an invalid (-1) entity
	local areas = B.AAS_LinkEntityClientBBox(absmins, absmaxs, -1, BC.PRESENCE_CROUCH)
	--get the reachable link area
	areanum = B.AAS_BestReachableLinkArea(areas)
	--unlink the invalid entity
	B.AAS_UnlinkFromAreas(areas)
	--
	return areanum
end

-- returns the number of reachability links of the area
function B.AAS_AreaReachability(areanum)
	local aasworld = B.aasworld
	if areanum < 0 or areanum >= aasworld.numareas then
		B.AAS_Error("AAS_AreaReachability: areanum %d out of range\n", areanum)
		return 0
	end
	return aasworld.areasettings[areanum].numreachableareas
end

-- returns the surface area of all ground faces together of the area
function B.AAS_AreaGroundFaceArea(areanum)
	local aasworld = B.aasworld
	local total = 0
	local area = aasworld.areas[areanum]
	for i = 0, area.numfaces - 1 do
		local face = aasworld.faces[math.abs(aasworld.faceindex[area.firstface + i])]
		if bit32.band(face.faceflags, BC.FACE_GROUND) ~= 0 then
			total = Q.f(total + B.AAS_FaceArea(face))
		end
	end
	return total
end

-- returns true if a player can only crouch in the area
function B.AAS_AreaCrouch(areanum)
	if bit32.band(B.aasworld.areasettings[areanum].presencetype, BC.PRESENCE_NORMAL) == 0 then
		return 1
	else
		return 0
	end
end

-- returns qtrue if it is possible to swim in the area
function B.AAS_AreaSwim(areanum)
	if bit32.band(B.aasworld.areasettings[areanum].areaflags, BC.AREA_LIQUID) ~= 0 then
		return 1
	else
		return 0
	end
end

-- returns qtrue if the area contains a liquid
function B.AAS_AreaLiquid(areanum)
	if bit32.band(B.aasworld.areasettings[areanum].areaflags, BC.AREA_LIQUID) ~= 0 then
		return 1
	else
		return 0
	end
end

function B.AAS_AreaLava(areanum)
	return bit32.band(B.aasworld.areasettings[areanum].contents, BC.AREACONTENTS_LAVA)
end

function B.AAS_AreaSlime(areanum)
	return bit32.band(B.aasworld.areasettings[areanum].contents, BC.AREACONTENTS_SLIME)
end

-- returns qtrue if the area contains ground faces
function B.AAS_AreaGrounded(areanum)
	return bit32.band(B.aasworld.areasettings[areanum].areaflags, BC.AREA_GROUNDED)
end

-- returns true if the area contains ladder faces
function B.AAS_AreaLadder(areanum)
	return bit32.band(B.aasworld.areasettings[areanum].areaflags, BC.AREA_LADDER)
end

function B.AAS_AreaJumpPad(areanum)
	return bit32.band(B.aasworld.areasettings[areanum].contents, BC.AREACONTENTS_JUMPPAD)
end

function B.AAS_AreaTeleporter(areanum)
	return bit32.band(B.aasworld.areasettings[areanum].contents, BC.AREACONTENTS_TELEPORTER)
end

function B.AAS_AreaClusterPortal(areanum)
	return bit32.band(B.aasworld.areasettings[areanum].contents, BC.AREACONTENTS_CLUSTERPORTAL)
end

function B.AAS_AreaDoNotEnter(areanum)
	return bit32.band(B.aasworld.areasettings[areanum].contents, BC.AREACONTENTS_DONOTENTER)
end

function B.AAS_ContinueInitReachability(time)
	local aasworld = B.aasworld

	if aasworld.loaded == 0 then
		return 0
	end
	--if reachability is calculated for all areas
	if aasworld.numreachabilityareas >= aasworld.numareas + 2 then
		return 0
	end
	B.botimport.Print(BC.PRT_ERROR, "AAS reachability calculation is not supported\n")
	aasworld.numreachabilityareas = aasworld.numareas + 2
	return 0
end

function B.AAS_InitReachability()
	local aasworld = B.aasworld

	if aasworld.loaded == 0 then
		return
	end

	if aasworld.reachabilitysize ~= 0 then
		if Q.trunc(B.LibVarGetValue("forcereachability")) == 0 then
			aasworld.numreachabilityareas = aasworld.numareas + 2
			return
		end
	end
	B.botimport.Print(BC.PRT_ERROR, "AAS reachability calculation is not supported\n")
	aasworld.numreachabilityareas = aasworld.numareas + 2
end

function B.AAS_InitClustering()
	local aasworld = B.aasworld

	if aasworld.loaded == 0 then
		return
	end
	--if there are clusters
	if aasworld.numclusters >= 1 then
		--if clustering isn't forced
		if Q.trunc(B.LibVarGetValue("forceclustering")) == 0 and Q.trunc(B.LibVarGetValue("forcereachability")) == 0 then
			return
		end
	end
	B.botimport.Print(BC.PRT_ERROR, "AAS clustering calculation is not supported\n")
	aasworld.numreachabilityareas = aasworld.numareas + 2
end

return nil
