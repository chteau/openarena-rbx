--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_utils.c).

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
-- Luau port of OpenArena 0.8.8's g_utils.c (gamecode 9e0f0c0). Misc utility functions for the game module.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local MAX_SHADER_REMAPS = 128

local remapCount = 0
local remappedShaders = {}
for i = 0, MAX_SHADER_REMAPS - 1 do
	remappedShaders[i] = { oldShader = "", newShader = "", timeOffset = 0 }
end

function G.AddRemap(oldShader, newShader, timeOffset)
	for i = 0, remapCount - 1 do
		if QS.Q_stricmp(oldShader, remappedShaders[i].oldShader) == 0 then
			-- found it, just update this one
			remappedShaders[i].newShader = newShader
			remappedShaders[i].timeOffset = Q.f(timeOffset)
			return
		end
	end
	if remapCount < MAX_SHADER_REMAPS then
		remappedShaders[remapCount].newShader = newShader
		remappedShaders[remapCount].oldShader = oldShader
		remappedShaders[remapCount].timeOffset = Q.f(timeOffset)
		remapCount += 1
	end
end

function G.BuildShaderStateConfig()
	local buff = ""

	for i = 0, remapCount - 1 do
		local out = QS.Com_sprintf((C.MAX_QPATH * 2) + 5, "%s=%s:%5.2f@", remappedShaders[i].oldShader, remappedShaders[i].newShader, remappedShaders[i].timeOffset)
		buff = QS.Q_strcat(buff, C.MAX_STRING_CHARS * 4, out)
	end
	return buff
end

--[[
=========================================================================

model / sound configstring indexes

=========================================================================
]]

function G.G_FindConfigstringIndex(name, start, max, create)
	if name == nil or name == "" then
		return 0
	end

	local i = 1
	while i < max do
		local s = G.trap_GetConfigstring(start + i)
		if s == "" then
			break
		end
		if s == name then
			return i
		end
		i += 1
	end

	if not create then
		return 0
	end

	if i == max then
		G.G_Error("G_FindConfigstringIndex: overflow")
	end

	G.trap_SetConfigstring(start + i, name)

	return i
end

function G.G_ModelIndex(name)
	return G.G_FindConfigstringIndex(name, C.CS_MODELS, C.MAX_MODELS, true)
end

function G.G_SoundIndex(name)
	return G.G_FindConfigstringIndex(name, C.CS_SOUNDS, C.MAX_SOUNDS, true)
end

--=====================================================================

-- Broadcasts a command to only a specific team
function G.G_TeamCommand(team, cmd)
	local level = G.level
	for i = 0, level.maxclients - 1 do
		if level.clients[i].pers.connected == C.CON_CONNECTED then
			if level.clients[i].sess.sessionTeam == team then
				G.trap_SendServerCommand(i, QS.va("%s", cmd))
			end
		end
	end
end

--[[
Searches all active entities for the next one that holds
the matching string at fieldofs (field name here) in the structure.

Searches beginning at the entity after from, or the beginning if NULL
NULL will be returned if the end of the list is reached.
]]
function G.G_Find(from, fieldname, match)
	local idx
	if from == nil then
		idx = 0
	else
		idx = from.index + 1
	end

	while idx < G.level.num_entities do
		local e = G.g_entities[idx]
		if e.inuse then
			local s = e[fieldname]
			if s ~= nil then
				if QS.Q_stricmp(s, match) == 0 then
					return e
				end
			end
		end
		idx += 1
	end

	return nil
end

-- Selects a random entity from among the targets
local MAXCHOICES = 32

function G.G_PickTarget(targetname)
	local ent = nil
	local num_choices = 0
	local choice = {}

	if targetname == nil then
		G.G_Printf("G_PickTarget called with NULL targetname\n")
		return nil
	end

	while true do
		ent = G.G_Find(ent, "targetname", targetname)
		if ent == nil then
			break
		end
		choice[num_choices] = ent
		num_choices += 1
		if num_choices == MAXCHOICES then
			break
		end
	end

	if num_choices == 0 then
		G.G_Printf("G_PickTarget: target %s not found\n", targetname)
		return nil
	end

	return choice[Q.imod(Q.rand(), num_choices)]
end

--[[
"activator" should be set to the entity that initiated the firing.

Search for (string)targetname in all entities that
match (string)self.target and call their .use function
]]
function G.G_UseTargets(ent, activator)
	if ent == nil then
		return
	end

	if ent.targetShaderName ~= nil and ent.targetShaderNewName ~= nil then
		local f = Q.f(G.level.time * 0.001)
		G.AddRemap(ent.targetShaderName, ent.targetShaderNewName, f)
		G.trap_SetConfigstring(C.CS_SHADERSTATE, G.BuildShaderStateConfig())
	end

	if ent.target == nil then
		return
	end

	local t = nil
	while true do
		t = G.G_Find(t, "targetname", ent.target)
		if t == nil then
			break
		end
		if t == ent then
			G.G_Printf("WARNING: Entity used itself.\n")
		else
			if t.use ~= nil then
				t.use(t, ent, activator)
			end
		end
		if not ent.inuse then
			G.G_Printf("entity was removed while using targets\n")
			return
		end
	end
end

-- This is just a convenience function
-- for making temporary vectors for function calls
local tv_index = 0
local tv_vecs = {}
for i = 0, 7 do
	tv_vecs[i] = Q.vec3()
end

function G.tv(x, y, z)
	-- use an array so that multiple tempvectors won't collide
	-- for a while
	local v = tv_vecs[tv_index]
	tv_index = bit32.band(tv_index + 1, 7)

	v[0] = Q.f(x)
	v[1] = Q.f(y)
	v[2] = Q.f(z)

	return v
end

-- This is just a convenience function
-- for printing vectors
function G.vtos(v)
	return QS.Com_sprintf(32, "(%i %i %i)", Q.trunc(v[0]), Q.trunc(v[1]), Q.trunc(v[2]))
end

local VEC_UP = Q.vec3()
VEC_UP[1] = -1
local MOVEDIR_UP = Q.vec3()
MOVEDIR_UP[2] = 1
local VEC_DOWN = Q.vec3()
VEC_DOWN[1] = -2
local MOVEDIR_DOWN = Q.vec3()
MOVEDIR_DOWN[2] = -1

--[[
The editor only specifies a single value for angles (yaw),
but we have special constants to generate an up or down direction.
Angles will be cleared, because it is being used to represent a direction
instead of an orientation.
]]
function G.G_SetMovedir(angles, movedir)
	if Q.VectorCompare(angles, VEC_UP) then
		Q.VectorCopy(MOVEDIR_UP, movedir)
	elseif Q.VectorCompare(angles, VEC_DOWN) then
		Q.VectorCopy(MOVEDIR_DOWN, movedir)
	else
		Q.AngleVectors(angles, movedir, nil, nil)
	end
	Q.VectorClear(angles)
end

function G.vectoyaw(vec)
	local yaw

	if vec[C.YAW] == 0 and vec[C.PITCH] == 0 then
		yaw = 0
	else
		if vec[C.PITCH] ~= 0 then
			yaw = math.atan2(vec[C.YAW], vec[C.PITCH]) * 180 / math.pi
		elseif vec[C.YAW] > 0 then
			yaw = 90
		else
			yaw = 270
		end
		if yaw < 0 then
			yaw += 360
		end
	end

	return yaw
end

function G.G_InitGentity(e)
	e.inuse = true
	e.classname = "noclass"
	e.s.number = e.index
	e.r.ownerNum = C.ENTITYNUM_NONE
end

--[[
Either finds a free entity, or allocates a new one.

  The slots from 0 to MAX_CLIENTS-1 are always reserved for clients, and will
never be used by anything else.

Try to avoid reusing an entity that was recently freed, because it
can cause the client to think the entity morphed into something else
instead of being removed and recreated, which can cause interpolated
angles and bad trails.
]]
function G.G_Spawn()
	local level = G.level

	local i = 0
	for force = 0, 1 do
		-- if we go through all entities and can't find one to free,
		-- override the normal minimum times before use
		i = C.MAX_CLIENTS
		while i < level.num_entities do
			local e = G.g_entities[i]
			if not e.inuse then
				-- the first couple seconds of server time can involve a lot of
				-- freeing and allocating, so relax the replacement policy
				if not (force == 0 and e.freetime > level.startTime + 2000 and level.time - e.freetime < 1000) then
					-- reuse this slot
					G.G_InitGentity(e)
					return e
				end
			end
			i += 1
		end
		if i ~= C.MAX_GENTITIES then
			break
		end
	end
	if i == C.ENTITYNUM_MAX_NORMAL then
		for j = 0, C.MAX_GENTITIES - 1 do
			G.G_Printf("%4i: %s\n", j, G.g_entities[j].classname)
		end
		G.G_Error("G_Spawn: no free entities")
	end

	local e = G.g_entities[level.num_entities]

	-- open up a new slot
	level.num_entities += 1

	-- let the server system know that there are more entities
	G.trap_LocateGameData(G.g_entities, level.num_entities, level.clients)

	G.G_InitGentity(e)
	return e
end

function G.G_EntitiesFree()
	local level = G.level

	for i = C.MAX_CLIENTS, level.num_entities - 1 do
		if not G.g_entities[i].inuse then
			-- slot available
			return true
		end
	end
	return false
end

-- Marks the entity as free
function G.G_FreeEntity(ed)
	G.trap_UnlinkEntity(ed) -- unlink from world

	if ed.neverFree then
		return
	end

	G.G_ClearEntity(ed)
	ed.classname = "freed"
	ed.freetime = G.level.time
	ed.inuse = false
end

--[[
Spawns an event entity that will be auto-removed
The origin will be snapped to save net bandwidth, so care
must be taken if the origin is right on a surface (snap towards start vector first)
]]
function G.G_TempEntity(origin, event)
	local snapped = Q.vec3()

	local e = G.G_Spawn()
	e.s.eType = C.ET_EVENTS + event

	e.classname = "tempEntity"
	e.eventTime = G.level.time
	e.freeAfterEvent = true

	Q.VectorCopy(origin, snapped)
	Q.SnapVector(snapped) -- save network bandwidth
	G.G_SetOrigin(e, snapped)

	-- find cluster for PVS
	G.trap_LinkEntity(e)

	return e
end

--[[
==============================================================================

Kill box

==============================================================================
]]

-- Kills all entities that would touch the proposed new positioning
-- of ent.  Ent should be unlinked before calling this!
function G.G_KillBox(ent)
	local touch = {}
	local mins = Q.vec3()
	local maxs = Q.vec3()

	Q.VectorAdd(ent.client.ps.origin, ent.r.mins, mins)
	Q.VectorAdd(ent.client.ps.origin, ent.r.maxs, maxs)
	local num = G.trap_EntitiesInBox(mins, maxs, touch, C.MAX_GENTITIES)

	for i = 0, num - 1 do
		local hit = G.g_entities[touch[i]]
		if hit.client ~= nil then
			-- nail it
			G.G_Damage(hit, ent, ent, nil, nil,
				100000, C.DAMAGE_NO_PROTECTION, C.MOD_TELEFRAG)
		end
	end
end

--==============================================================================

--[[
Use for non-pmove events that would also be predicted on the
client side: jumppads and item pickups
Adds an event+parm and twiddles the event counter
]]
function G.G_AddPredictableEvent(ent, event, eventParm)
	if ent.client == nil then
		return
	end
	BG.BG_AddPredictableEventToPlayerstate(event, eventParm, ent.client.ps)
end

-- Adds an event+parm and twiddles the event counter
function G.G_AddEvent(ent, event, eventParm)
	local bits

	if event == 0 then
		G.G_Printf("G_AddEvent: zero event added for entity %i\n", ent.s.number)
		return
	end

	-- clients need to add the event in playerState_t instead of entityState_t
	if ent.client ~= nil then
		local ps = ent.client.ps
		bits = bit32.band(ps.externalEvent, C.EV_EVENT_BITS)
		bits = bit32.band(bits + C.EV_EVENT_BIT1, C.EV_EVENT_BITS)
		ps.externalEvent = bit32.bor(event, bits)
		ps.externalEventParm = eventParm
		ps.externalEventTime = G.level.time
	else
		bits = bit32.band(ent.s.event, C.EV_EVENT_BITS)
		bits = bit32.band(bits + C.EV_EVENT_BIT1, C.EV_EVENT_BITS)
		ent.s.event = bit32.bor(event, bits)
		ent.s.eventParm = eventParm
	end
	ent.eventTime = G.level.time
end

function G.G_Sound(ent, channel, soundIndex)
	local te = G.G_TempEntity(ent.r.currentOrigin, C.EV_GENERAL_SOUND)
	te.s.eventParm = soundIndex
end

-- KK-OAX G_SoundIndex must first be called.
function G.G_GlobalSound(soundIndex)
	-- Let's avoid the S_FindName error if soundIndex is 0.
	-- Sago: And let's check that the sound index is within the allowed range.
	if soundIndex <= 0 or soundIndex >= C.MAX_SOUNDS then
		return
	end
	-- Spawn a Temporary Entity at the origin point for Intermission with the event EV_GLOBAL_SOUND
	local te = G.G_TempEntity(G.level.intermission_origin, C.EV_GLOBAL_SOUND)
	-- Add the soundIndex to the parameters for the EV_GLOBAL_SOUND event we are calling
	te.s.eventParm = soundIndex
	-- Broadcast the sound event.
	te.r.svFlags = bit32.bor(te.r.svFlags, C.SVF_BROADCAST)
end

--==============================================================================

-- Sets the pos trajectory for a fixed position
function G.G_SetOrigin(ent, origin)
	Q.VectorCopy(origin, ent.s.pos.trBase)
	ent.s.pos.trType = C.TR_STATIONARY
	ent.s.pos.trTime = 0
	ent.s.pos.trDuration = 0
	Q.VectorClear(ent.s.pos.trDelta)

	Q.VectorCopy(origin, ent.r.currentOrigin)
end

--[[
  debug polygons only work when running a local game
  with r_debugSurface set to 2
]]
function G.DebugLine(start, end_, color)
	local points = { [0] = Q.vec3(), Q.vec3(), Q.vec3(), Q.vec3() }
	local dir = Q.vec3()
	local cross = Q.vec3()
	local up = Q.vec3()
	up[2] = 1

	Q.VectorCopy(start, points[0])
	Q.VectorCopy(start, points[1])
	Q.VectorCopy(end_, points[2])
	Q.VectorCopy(end_, points[3])

	Q.VectorSubtract(end_, start, dir)
	Q.VectorNormalize(dir)
	local dot = Q.DotProduct(dir, up)
	if dot > 0.99 or dot < -0.99 then
		Q.VectorSet(cross, 1, 0, 0)
	else
		Q.CrossProduct(dir, up, cross)
	end

	Q.VectorNormalize(cross)

	Q.VectorMA(points[0], 2, cross, points[0])
	Q.VectorMA(points[1], -2, cross, points[1])
	Q.VectorMA(points[2], -2, cross, points[2])
	Q.VectorMA(points[3], 2, cross, points[3])

	return G.trap_DebugPolygonCreate(color, 4, points)
end

return nil
