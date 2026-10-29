--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of Quake III Arena source code.

Quake III Arena source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

Quake III Arena source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Quake III Arena source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
]]
-- Luau port of code/cgame/cg_snapshot.c (OpenArena gamecode).
-- cg_snapshot.c -- things that happen on snapshot transition,
-- not necessarily every single rendered frame

local G = require(script.Parent.G)
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local Q = require(script.Parent.Parent.q.Q)
local trap = require(script.Parent.Parent.sys.Trap)
local BG = require(script.Parent.Parent.adapters.BG)

local function CG_ResetEntity(cent)
	-- if the previous snapshot this entity was updated in is at least
	-- an event window back in time then we can reset the previous event
	if cent.snapShotTime < G.cg.time - C.EVENT_VALID_MSEC then
		cent.previousEvent = 0
	end

	cent.trailTime = G.cg.snap.serverTime

	Q.VectorCopy(cent.currentState.origin, cent.lerpOrigin)
	Q.VectorCopy(cent.currentState.angles, cent.lerpAngles)
	if cent.currentState.eType == C.ET_PLAYER then
		G.CG_ResetPlayerEntity(cent)
	end
end

-- cent->nextState is moved to cent->currentState and events are fired
function G.CG_TransitionEntity(cent)
	T.assign(cent.currentState, cent.nextState)
	cent.currentValid = true

	-- reset if the entity wasn't in the last frame or was teleported
	if not cent.interpolate then
		CG_ResetEntity(cent)
	end

	-- clear the next state.  if will be set by the next CG_SetNextSnap
	cent.interpolate = false

	-- check for events
	G.CG_CheckEvents(cent)
end

-- This will only happen on the very first snapshot, or
-- on tourney restarts.  All other times will use
-- CG_TransitionSnapshot instead.
function G.CG_SetInitialSnapshot(snap)
	local cg = G.cg
	cg.snap = snap

	BG.BG_PlayerStateToEntityState(snap.ps, G.cg_entities[snap.ps.clientNum].currentState, false)

	-- sort out solid entities
	G.CG_BuildSolidList()

	G.CG_ExecuteNewServerCommands(snap.serverCommandSequence)

	-- set our local weapon selection pointer to
	-- what the server has indicated the current weapon is
	G.CG_Respawn()

	for i = 0, cg.snap.numEntities - 1 do
		local state = cg.snap.entities[i]
		local cent = G.cg_entities[state.number]

		T.assign(cent.currentState, state)
		cent.interpolate = false
		cent.currentValid = true

		CG_ResetEntity(cent)

		-- check for events
		G.CG_CheckEvents(cent)
	end
end

-- The transition point from snap to nextSnap has passed
local function CG_TransitionSnapshot()
	local cg = G.cg

	if cg.snap == nil then
		G.CG_Error("CG_TransitionSnapshot: NULL cg.snap")
	end
	if cg.nextSnap == nil then
		G.CG_Error("CG_TransitionSnapshot: NULL cg.nextSnap")
	end

	-- execute any server string commands before transitioning entities
	G.CG_ExecuteNewServerCommands(cg.nextSnap.serverCommandSequence)

	-- clear the currentValid flag for all entities in the existing snapshot
	for i = 0, cg.snap.numEntities - 1 do
		local cent = G.cg_entities[cg.snap.entities[i].number]
		cent.currentValid = false
	end

	-- move nextSnap to snap and do the transitions
	local oldFrame = cg.snap
	cg.snap = cg.nextSnap

	BG.BG_PlayerStateToEntityState(cg.snap.ps, G.cg_entities[cg.snap.ps.clientNum].currentState, false)
	G.cg_entities[cg.snap.ps.clientNum].interpolate = false

	for i = 0, cg.snap.numEntities - 1 do
		local cent = G.cg_entities[cg.snap.entities[i].number]
		G.CG_TransitionEntity(cent)

		-- remember time of snapshot this entity was last updated in
		cent.snapShotTime = cg.snap.serverTime
	end

	cg.nextSnap = nil

	-- check for playerstate transition events
	if oldFrame ~= nil then
		local ops = oldFrame.ps
		local ps = cg.snap.ps
		-- teleporting checks are irrespective of prediction
		if bit32.band(bit32.bxor(ps.eFlags, ops.eFlags), C.EF_TELEPORT_BIT) ~= 0 then
			cg.thisFrameTeleport = true -- will be cleared by prediction code
		end

		-- if we are not doing client side movement prediction for any
		-- reason, then the client events and view changes will be issued now
		if
			cg.demoPlayback
			or bit32.band(cg.snap.ps.pm_flags, C.PMF_FOLLOW) ~= 0
			or G.cg_nopredict.integer ~= 0
			or G.cg_synchronousClients.integer ~= 0
		then
			G.CG_TransitionPlayerState(ps, ops)
		end
	end
end

-- A new snapshot has just been read in from the client system.
local function CG_SetNextSnap(snap)
	local cg = G.cg

	cg.nextSnap = snap

	BG.BG_PlayerStateToEntityState(snap.ps, G.cg_entities[snap.ps.clientNum].nextState, false)
	G.cg_entities[cg.snap.ps.clientNum].interpolate = true

	-- check for extrapolation errors
	for num = 0, snap.numEntities - 1 do
		local es = snap.entities[num]
		local cent = G.cg_entities[es.number]

		T.assign(cent.nextState, es)

		-- if this frame is a teleport, or the entity wasn't in the
		-- previous frame, don't interpolate
		if not cent.currentValid or bit32.band(bit32.bxor(cent.currentState.eFlags, es.eFlags), C.EF_TELEPORT_BIT) ~= 0 then
			cent.interpolate = false
		else
			cent.interpolate = true
		end
	end

	-- if the next frame is a teleport for the playerstate, we
	-- can't interpolate during demos
	if cg.snap ~= nil and bit32.band(bit32.bxor(snap.ps.eFlags, cg.snap.ps.eFlags), C.EF_TELEPORT_BIT) ~= 0 then
		cg.nextFrameTeleport = true
	else
		cg.nextFrameTeleport = false
	end

	-- if changing follow mode, don't interpolate
	if cg.snap ~= nil and cg.nextSnap.ps.clientNum ~= cg.snap.ps.clientNum then
		cg.nextFrameTeleport = true
	end

	-- if changing server restarts, don't interpolate
	if cg.snap ~= nil and bit32.band(bit32.bxor(cg.nextSnap.snapFlags, cg.snap.snapFlags), C.SNAPFLAG_SERVERCOUNT) ~= 0 then
		cg.nextFrameTeleport = true
	end

	-- sort out solid entities
	G.CG_BuildSolidList()
end

-- This is the only place new snapshots are requested
-- This may increment cgs.processedSnapshotNum multiple
-- times if the client system fails to return a
-- valid snapshot.
local function CG_ReadNextSnapshot()
	local cg = G.cg
	local cgs = G.cgs

	if cg.latestSnapshotNum > cgs.processedSnapshotNum + 1000 then
		G.CG_Printf(Q.va("WARNING: CG_ReadNextSnapshot: way out of range, %i > %i", cg.latestSnapshotNum, cgs.processedSnapshotNum))
	end

	while cgs.processedSnapshotNum < cg.latestSnapshotNum do
		-- decide which of the two slots to load it into
		local dest
		if cg.snap == cg.activeSnapshots[0] then
			dest = cg.activeSnapshots[1]
		else
			dest = cg.activeSnapshots[0]
		end

		-- try to read the snapshot from the client system
		cgs.processedSnapshotNum += 1
		local r = trap.GetSnapshot(cgs.processedSnapshotNum, dest)

		-- if it succeeded, return
		if r then
			G.CG_AddLagometerSnapshotInfo(dest)
			return dest
		end

		-- a GetSnapshot will return failure if the snapshot
		-- never arrived, or  is so old that its entities
		-- have been shoved off the end of the circular
		-- buffer in the client system.

		-- record as a dropped packet
		G.CG_AddLagometerSnapshotInfo(nil)

		-- If there are additional snapshots, continue trying to
		-- read them.
	end

	-- nothing left to read
	return nil
end

-- We are trying to set up a renderable view, so determine
-- what the simulated time is, and try to get snapshots
-- both before and after that time if available.
--
-- If we don't have a valid cg.snap after exiting this function,
-- then a 3D game view cannot be rendered.  This should only happen
-- right after the initial connection.  After cg.snap has been valid
-- once, it will never turn invalid.
--
-- Even if cg.snap is valid, cg.nextSnap may not be, if the snapshot
-- hasn't arrived yet (it becomes an extrapolating situation instead
-- of an interpolating one)
function G.CG_ProcessSnapshots()
	local cg = G.cg

	-- see what the latest snapshot the client system has is
	local n, t = trap.GetCurrentSnapshotNumber()
	cg.latestSnapshotTime = t
	if n ~= cg.latestSnapshotNum then
		if n < cg.latestSnapshotNum then
			-- this should never happen
			G.CG_Error("CG_ProcessSnapshots: n < cg.latestSnapshotNum")
		end
		cg.latestSnapshotNum = n
	end

	-- If we have yet to receive a snapshot, check for it.
	-- Once we have gotten the first snapshot, cg.snap will
	-- always have valid data for the rest of the game
	while cg.snap == nil do
		local snap = CG_ReadNextSnapshot()
		if snap == nil then
			-- we can't continue until we get a snapshot
			return
		end

		-- set our weapon selection to what
		-- the playerstate is currently using
		if bit32.band(snap.snapFlags, C.SNAPFLAG_NOT_ACTIVE) == 0 then
			G.CG_SetInitialSnapshot(snap)
		end
	end

	-- loop until we either have a valid nextSnap with a serverTime
	-- greater than cg.time to interpolate towards, or we run
	-- out of available snapshots
	while true do
		-- if we don't have a nextframe, try and read a new one in
		if cg.nextSnap == nil then
			local snap = CG_ReadNextSnapshot()

			-- if we still don't have a nextframe, we will just have to
			-- extrapolate
			if snap == nil then
				break
			end

			CG_SetNextSnap(snap)

			-- if time went backwards, we have a level restart
			if cg.nextSnap.serverTime < cg.snap.serverTime then
				G.CG_Error("CG_ProcessSnapshots: Server time went backwards")
			end
		end

		-- if our time is < nextFrame's, we have a nice interpolating state
		if cg.time >= cg.snap.serverTime and cg.time < cg.nextSnap.serverTime then
			break
		end

		-- we have passed the transition from nextFrame to frame
		CG_TransitionSnapshot()
	end

	-- assert our valid conditions upon exiting
	if cg.snap == nil then
		G.CG_Error("CG_ProcessSnapshots: cg.snap == NULL")
	end
	if cg.time < cg.snap.serverTime then
		-- this can happen right after a vid_restart
		cg.time = cg.snap.serverTime
	end
	if cg.nextSnap ~= nil and cg.nextSnap.serverTime <= cg.time then
		G.CG_Error("CG_ProcessSnapshots: cg.nextSnap->serverTime <= cg.time")
	end
end

return G
