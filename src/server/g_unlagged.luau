--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_unlagged.c).

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
-- Luau port of OpenArena 0.8.8's g_unlagged.c (gamecode 9e0f0c0). Unlagged: history storage, time shifting and server-side movement prediction.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local OVERCLIP = 1.001
local MAX_CLIP_PLANES = 5
local STEPSIZE = 18

--[[
============
G_ResetHistory

Clear out the given client's history (should be called when the teleport bit is flipped)
============
]]
function G.G_ResetHistory(ent)
	local client = ent.client
	-- fill up the history with data (assume the current position)
	client.historyHead = C.NUM_CLIENT_HISTORY - 1
	local i = client.historyHead
	local time = G.level.time
	while i >= 0 do
		Q.VectorCopy(ent.r.mins, client.history[i].mins)
		Q.VectorCopy(ent.r.maxs, client.history[i].maxs)
		Q.VectorCopy(ent.r.currentOrigin, client.history[i].currentOrigin)
		client.history[i].leveltime = time
		i -= 1
		time -= 50
	end
end

--[[
============
G_StoreHistory

Keep track of where the client's been
============
]]
function G.G_StoreHistory(ent)
	local client = ent.client
	client.historyHead += 1
	if client.historyHead >= C.NUM_CLIENT_HISTORY then
		client.historyHead = 0
	end

	local head = client.historyHead

	-- store all the collision-detection info and the time
	Q.VectorCopy(ent.r.mins, client.history[head].mins)
	Q.VectorCopy(ent.r.maxs, client.history[head].maxs)
	Q.VectorCopy(ent.s.pos.trBase, client.history[head].currentOrigin)
	Q.SnapVector(client.history[head].currentOrigin)
	client.history[head].leveltime = G.level.time
end

--[[
=============
TimeShiftLerp

Used below to interpolate between two previous vectors
Returns a vector "frac" times the distance between "start" and "end"
=============
]]
local function TimeShiftLerp(frac, start, finish, result)
	-- From CG_InterpolateEntityPosition in cg_ents.c; kept identical to avoid floating-point error
	result[0] = Q.f(start[0] + frac * (finish[0] - start[0]))
	result[1] = Q.f(start[1] + frac * (finish[1] - start[1]))
	result[2] = Q.f(start[2] + frac * (finish[2] - start[2]))
end

--[[
=================
G_TimeShiftClient

Move a client back to where he was at the specified "time"
=================
]]
function G.G_TimeShiftClient(ent, time, debug, debugger)
	local client = ent.client

	-- find two entries in the history whose times sandwich "time"
	-- assumes no two adjacent records have the same timestamp
	local j = client.historyHead
	local k = j
	repeat
		if client.history[j].leveltime <= time then
			break
		end
		k = j
		j -= 1
		if j < 0 then
			j = C.NUM_CLIENT_HISTORY - 1
		end
	until not (j ~= client.historyHead)

	-- if we got past the first iteration above, we've sandwiched (or wrapped)
	if j ~= k then
		-- make sure it doesn't get re-saved
		if client.saved.leveltime ~= G.level.time then
			-- save the current origin and bounding box
			Q.VectorCopy(ent.r.mins, client.saved.mins)
			Q.VectorCopy(ent.r.maxs, client.saved.maxs)
			Q.VectorCopy(ent.r.currentOrigin, client.saved.currentOrigin)
			client.saved.leveltime = G.level.time
		end

		-- if we haven't wrapped back to the head, we've sandwiched, so
		-- we shift the client's position back to where he was at "time"
		if j ~= client.historyHead then
			local frac = Q.f((time - client.history[j].leveltime)) /
				Q.f((client.history[k].leveltime - client.history[j].leveltime))
			frac = Q.f(frac)

			-- interpolate between the two origins to give position at time index "time"
			TimeShiftLerp(frac, client.history[j].currentOrigin, client.history[k].currentOrigin, ent.r.currentOrigin)

			-- lerp these too, just for fun (and ducking)
			TimeShiftLerp(frac, client.history[j].mins, client.history[k].mins, ent.r.mins)

			TimeShiftLerp(frac, client.history[j].maxs, client.history[k].maxs, ent.r.maxs)

			-- this will recalculate absmin and absmax
			G.trap_LinkEntity(ent)
		else
			-- we wrapped, so grab the earliest
			Q.VectorCopy(client.history[k].currentOrigin, ent.r.currentOrigin)
			Q.VectorCopy(client.history[k].mins, ent.r.mins)
			Q.VectorCopy(client.history[k].maxs, ent.r.maxs)

			-- this will recalculate absmin and absmax
			G.trap_LinkEntity(ent)
		end
	end
end

--[[
=====================
G_TimeShiftAllClients

Move ALL clients back to where they were at the specified "time",
except for "skip"
=====================
]]
function G.G_TimeShiftAllClients(time, skip)
	local debug = (skip ~= nil and skip.client ~= nil and skip.s.weapon == C.WP_RAILGUN)

	-- for every client
	for i = 0, C.MAX_CLIENTS - 1 do
		local ent = G.g_entities[i]
		if ent.client ~= nil and ent.inuse and ent.client.sess.sessionTeam < C.TEAM_SPECTATOR and ent ~= skip then
			G.G_TimeShiftClient(ent, time, debug, skip)
		end
	end
end

--[[
================
G_DoTimeShiftFor

Decide what time to shift everyone back to, and do it
================
]]
function G.G_DoTimeShiftFor(ent)
	local wpflags = {}
	for w = 0, C.WP_NUM_WEAPONS - 1 do
		wpflags[w] = 0
	end
	wpflags[2] = 2
	wpflags[3] = 4
	wpflags[6] = 8
	wpflags[7] = 16
	wpflags[11] = 32
	wpflags[13] = 64

	local wpflag = wpflags[ent.client.ps.weapon]
	local time

	-- don't time shift for mistakes or bots
	if not ent.inuse or ent.client == nil or bit32.band(ent.r.svFlags, C.SVF_BOT) ~= 0 then
		return
	end

	-- if it's enabled server-side and the client wants it or wants it for this weapon
	if G.g_delagHitscan.integer ~= 0 and (bit32.band(ent.client.pers.delag, 1) ~= 0 or bit32.band(ent.client.pers.delag, wpflag) ~= 0) then
		-- do the full lag compensation, except what the client nudges
		time = ent.client.attackTime + ent.client.pers.cmdTimeNudge
		-- Give the lightning gun some handicap (lag was part of weapon balance in VQ3)
		if ent.client.ps.weapon == C.WP_LIGHTNING and G.g_lagLightning.integer ~= 0 then
			time += 50
		end
	else
		-- do just 50ms
		time = G.level.previousTime + ent.client.frameOffset
	end

	G.G_TimeShiftAllClients(time, ent)
end

--[[
===================
G_UnTimeShiftClient

Move a client back to where he was before the time shift
===================
]]
function G.G_UnTimeShiftClient(ent)
	-- if it was saved
	if ent.client.saved.leveltime == G.level.time then
		-- move it back
		Q.VectorCopy(ent.client.saved.mins, ent.r.mins)
		Q.VectorCopy(ent.client.saved.maxs, ent.r.maxs)
		Q.VectorCopy(ent.client.saved.currentOrigin, ent.r.currentOrigin)
		ent.client.saved.leveltime = 0

		-- this will recalculate absmin and absmax
		G.trap_LinkEntity(ent)
	end
end

--[[
=======================
G_UnTimeShiftAllClients

Move ALL the clients back to where they were before the time shift,
except for "skip"
=======================
]]
function G.G_UnTimeShiftAllClients(skip)
	for i = 0, C.MAX_CLIENTS - 1 do
		local ent = G.g_entities[i]
		if ent.client ~= nil and ent.inuse and ent.client.sess.sessionTeam < C.TEAM_SPECTATOR and ent ~= skip then
			G.G_UnTimeShiftClient(ent)
		end
	end
end

--[[
==================
G_UndoTimeShiftFor

Put everyone except for this client back where they were
==================
]]
function G.G_UndoTimeShiftFor(ent)
	-- don't un-time shift for mistakes or bots
	if not ent.inuse or ent.client == nil or bit32.band(ent.r.svFlags, C.SVF_BOT) ~= 0 then
		return
	end

	G.G_UnTimeShiftAllClients(ent)
end

--[[
===========================
G_PredictPlayerClipVelocity

Slide on the impacting surface
===========================
]]
function G.G_PredictPlayerClipVelocity(vin, normal, out)
	-- find the magnitude of the vector "in" along "normal"
	local backoff = Q.f(Q.DotProduct(vin, normal))

	-- tilt the plane a bit to avoid floating-point error issues
	if backoff < 0 then
		backoff = Q.f(backoff * OVERCLIP)
	else
		backoff = Q.f(backoff / OVERCLIP)
	end

	-- slide along
	Q.VectorMA(vin, -backoff, normal, out)
end

--[[
========================
G_PredictPlayerSlideMove

Advance the given entity frametime seconds, sliding as appropriate
========================
]]
function G.G_PredictPlayerSlideMove(ent, frametime)
	local dir = Q.vec3()
	local d
	local planes = {}
	for p = 0, MAX_CLIP_PLANES - 1 do
		planes[p] = Q.vec3()
	end
	local primal_velocity = Q.vec3()
	local velocity = Q.vec3()
	local origin = Q.vec3()
	local clipVelocity = Q.vec3()
	local trace = S.trace_t()
	local end_ = Q.vec3()
	local time_left
	local into
	local endVelocity = Q.vec3()
	local endClipVelocity = Q.vec3()

	local numbumps = 4

	Q.VectorCopy(ent.s.pos.trDelta, primal_velocity)
	Q.VectorCopy(primal_velocity, velocity)
	Q.VectorCopy(ent.s.pos.trBase, origin)

	Q.VectorCopy(velocity, endVelocity)

	time_left = frametime

	local numplanes = 0

	local bumpcount = 0
	while bumpcount < numbumps do
		-- calculate position we are trying to move to
		Q.VectorMA(origin, time_left, velocity, end_)

		-- see if we can make it there
		G.trap_Trace(trace, origin, ent.r.mins, ent.r.maxs, end_, ent.s.number, ent.clipmask)

		if trace.allsolid then
			-- entity is completely trapped in another solid
			Q.VectorClear(velocity)
			Q.VectorCopy(origin, ent.s.pos.trBase)
			return true
		end

		if trace.fraction > 0 then
			-- actually covered some distance
			Q.VectorCopy(trace.endpos, origin)
		end

		if trace.fraction == 1 then
			break -- moved the entire distance
		end

		time_left -= time_left * trace.fraction

		if numplanes >= MAX_CLIP_PLANES then
			-- this shouldn't really happen
			Q.VectorClear(velocity)
			Q.VectorCopy(origin, ent.s.pos.trBase)
			return true
		end

		--
		-- if this is the same plane we hit before, nudge velocity
		-- out along it, which fixes some epsilon issues with
		-- non-axial planes
		--
		local i = 0
		while i < numplanes do
			if Q.DotProduct(trace.plane.normal, planes[i]) > 0.99 then
				Q.VectorAdd(trace.plane.normal, velocity, velocity)
				break
			end
			i += 1
		end

		if i < numplanes then
			bumpcount += 1
			continue
		end

		Q.VectorCopy(trace.plane.normal, planes[numplanes])
		numplanes += 1

		--
		-- modify velocity so it parallels all of the clip planes
		--

		-- find a plane that it enters
		i = 0
		while i < numplanes do
			into = Q.DotProduct(velocity, planes[i])
			if into >= 0.1 then
				i += 1
				continue -- move doesn't interact with the plane
			end

			-- slide along the plane
			G.G_PredictPlayerClipVelocity(velocity, planes[i], clipVelocity)

			-- slide along the plane
			G.G_PredictPlayerClipVelocity(endVelocity, planes[i], endClipVelocity)

			-- see if there is a second plane that the new move enters
			for j = 0, numplanes - 1 do
				if j == i then
					continue
				end

				if Q.DotProduct(clipVelocity, planes[j]) >= 0.1 then
					continue -- move doesn't interact with the plane
				end

				-- try clipping the move to the plane
				G.G_PredictPlayerClipVelocity(clipVelocity, planes[j], clipVelocity)
				G.G_PredictPlayerClipVelocity(endClipVelocity, planes[j], endClipVelocity)

				-- see if it goes back into the first clip plane
				if Q.DotProduct(clipVelocity, planes[i]) >= 0 then
					continue
				end

				-- slide the original velocity along the crease
				Q.CrossProduct(planes[i], planes[j], dir)
				Q.VectorNormalize(dir)
				d = Q.DotProduct(dir, velocity)
				Q.VectorScale(dir, d, clipVelocity)

				Q.CrossProduct(planes[i], planes[j], dir)
				Q.VectorNormalize(dir)
				d = Q.DotProduct(dir, endVelocity)
				Q.VectorScale(dir, d, endClipVelocity)

				-- see if there is a third plane the the new move enters
				for k = 0, numplanes - 1 do
					if k == i or k == j then
						continue
					end

					if Q.DotProduct(clipVelocity, planes[k]) >= 0.1 then
						continue -- move doesn't interact with the plane
					end

					-- stop dead at a tripple plane interaction
					Q.VectorClear(velocity)
					Q.VectorCopy(origin, ent.s.pos.trBase)
					return true
				end
			end

			-- if we have fixed all interactions, try another move
			Q.VectorCopy(clipVelocity, velocity)
			Q.VectorCopy(endClipVelocity, endVelocity)
			break
		end

		bumpcount += 1
	end

	Q.VectorCopy(endVelocity, velocity)
	Q.VectorCopy(origin, ent.s.pos.trBase)

	return (bumpcount ~= 0)
end

--[[
============================
G_PredictPlayerStepSlideMove

Advance the given entity frametime seconds, stepping and sliding as appropriate
============================
]]
function G.G_PredictPlayerStepSlideMove(ent, frametime)
	local start_o = Q.vec3()
	local start_v = Q.vec3()
	local down = Q.vec3()
	local up = Q.vec3()
	local trace = S.trace_t()
	local stepSize

	Q.VectorCopy(ent.s.pos.trBase, start_o)
	Q.VectorCopy(ent.s.pos.trDelta, start_v)

	if not G.G_PredictPlayerSlideMove(ent, frametime) then
		-- not clipped, so forget stepping
		return
	end

	Q.VectorCopy(start_o, up)
	up[2] += STEPSIZE

	-- test the player position if they were a stepheight higher
	G.trap_Trace(trace, start_o, ent.r.mins, ent.r.maxs, up, ent.s.number, ent.clipmask)
	if trace.allsolid then
		return -- can't step up
	end

	stepSize = Q.f(trace.endpos[2] - start_o[2])

	-- try slidemove from this position
	Q.VectorCopy(trace.endpos, ent.s.pos.trBase)
	Q.VectorCopy(start_v, ent.s.pos.trDelta)

	G.G_PredictPlayerSlideMove(ent, frametime)

	-- push down the final amount
	Q.VectorCopy(ent.s.pos.trBase, down)
	down[2] -= stepSize
	G.trap_Trace(trace, ent.s.pos.trBase, ent.r.mins, ent.r.maxs, down, ent.s.number, ent.clipmask)
	if not trace.allsolid then
		Q.VectorCopy(trace.endpos, ent.s.pos.trBase)
	end
	if trace.fraction < 1.0 then
		G.G_PredictPlayerClipVelocity(ent.s.pos.trDelta, trace.plane.normal, ent.s.pos.trDelta)
	end
end

--[[
===================
G_PredictPlayerMove

Advance the given entity frametime seconds, stepping and sliding as appropriate

This is the entry point to the server-side-only prediction code
===================
]]
function G.G_PredictPlayerMove(ent, frametime)
	G.G_PredictPlayerStepSlideMove(ent, frametime)
end

return nil
