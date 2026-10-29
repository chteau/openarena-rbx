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
-- Luau port of code/cgame/cg_predict.c (OpenArena 0.8.8, gamecode 9e0f0c0).
--
-- cg_predict.c -- this file generates cg.predictedPlayerState by either
-- interpolating between snapshots from the server or locally predicting
-- ahead the client's movement.
-- It also handles local physics interaction, like fragments bouncing off walls

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local trap = require(script.Parent.Parent.sys.Trap)
local BG = require(script.Parent.Parent.adapters.BG)

local cg_pmove = T.pmove_t()

local cg_numSolidEntities = 0
local cg_solidEntities = {}
local cg_numTriggerEntities = 0
local cg_triggerEntities = {}

--[[
====================
CG_BuildSolidList

When a new cg.snap has been set, this function builds a sublist
of the entities that are actually solid, to make for more
efficient collision detection
====================
]]
function G.CG_BuildSolidList()
	local cg = G.cg
	cg_numSolidEntities = 0
	cg_numTriggerEntities = 0

	local snap
	if cg.nextSnap ~= nil and not cg.nextFrameTeleport and not cg.thisFrameTeleport then
		snap = cg.nextSnap
	else
		snap = cg.snap
	end

	for i = 0, snap.numEntities - 1 do
		local cent = G.cg_entities[snap.entities[i].number]
		local ent = cent.currentState

		if ent.eType == C.ET_ITEM or ent.eType == C.ET_PUSH_TRIGGER or ent.eType == C.ET_TELEPORT_TRIGGER then
			cg_triggerEntities[cg_numTriggerEntities] = cent
			cg_numTriggerEntities += 1
			continue
		end

		if cent.nextState.solid ~= 0 then
			cg_solidEntities[cg_numSolidEntities] = cent
			cg_numSolidEntities += 1
			continue
		end
	end
end

local function CG_ClipMoveToEntities(start, mins, maxs, endp, skipNumber, mask, tr)
	local bmins = Q.vec3(0, 0, 0)
	local bmaxs = Q.vec3(0, 0, 0)
	local origin = Q.vec3(0, 0, 0)
	local angles = Q.vec3(0, 0, 0)
	local trace = T.trace_t()

	for i = 0, cg_numSolidEntities - 1 do
		local cent = cg_solidEntities[i]
		local ent = cent.currentState

		if ent.number == skipNumber then
			continue
		end

		local cmodel
		if ent.solid == C.SOLID_BMODEL then
			-- special value for bmodel
			cmodel = trap.CM_InlineModel(ent.modelindex)
			Q.VectorCopy(cent.lerpAngles, angles)
			BG.BG_EvaluateTrajectory(cent.currentState.pos, G.cg.physicsTime, origin)
		else
			-- encoded bbox
			local x = bit32.band(ent.solid, 255)
			local zd = bit32.band(bit32.rshift(ent.solid, 8), 255)
			local zu = bit32.band(bit32.rshift(ent.solid, 16), 255) - 32

			bmins[0] = -x
			bmins[1] = -x
			bmaxs[0] = x
			bmaxs[1] = x
			bmins[2] = -zd
			bmaxs[2] = zu

			cmodel = trap.CM_TempBoxModel(bmins, bmaxs)
			Q.VectorCopy(Q.vec3_origin, angles)
			Q.VectorCopy(cent.lerpOrigin, origin)
		end

		trap.CM_TransformedBoxTrace(trace, start, endp, mins, maxs, cmodel, mask, origin, angles)

		if trace.allsolid or trace.fraction < tr.fraction then
			trace.entityNum = ent.number
			T.assign(tr, trace)
		elseif trace.startsolid then
			tr.startsolid = true
		end
		if tr.allsolid then
			return
		end
	end
end

function G.CG_Trace(result, start, mins, maxs, endp, skipNumber, mask)
	local t = T.trace_t()

	trap.CM_BoxTrace(t, start, endp, mins, maxs, 0, mask)
	if t.fraction ~= 1.0 then
		t.entityNum = C.ENTITYNUM_WORLD
	else
		t.entityNum = C.ENTITYNUM_NONE
	end
	-- check all other solid models
	CG_ClipMoveToEntities(start, mins, maxs, endp, skipNumber, mask, t)

	T.assign(result, t)
end

function G.CG_PointContents(point, passEntityNum)
	local contents = trap.CM_PointContents(point, 0)

	for i = 0, cg_numSolidEntities - 1 do
		local cent = cg_solidEntities[i]
		local ent = cent.currentState

		if ent.number == passEntityNum then
			continue
		end

		if ent.solid ~= C.SOLID_BMODEL then -- special value for bmodel
			continue
		end

		local cmodel = trap.CM_InlineModel(ent.modelindex)
		if cmodel == 0 then
			continue
		end

		contents = bit32.bor(contents, trap.CM_TransformedPointContents(point, cmodel, cent.lerpOrigin, cent.lerpAngles))
	end

	return contents
end

--[[
========================
CG_InterpolatePlayerState

Generates cg.predictedPlayerState by interpolating between
cg.snap->player_state and cg.nextFrame->player_state
========================
]]
local function CG_InterpolatePlayerState(grabAngles)
	local cg = G.cg
	local out = cg.predictedPlayerState
	local prev = cg.snap
	local next = cg.nextSnap

	T.assign(out, cg.snap.ps)

	-- if we are still allowing local input, short circuit the view angles
	if grabAngles then
		local cmd = T.usercmd_t()
		local cmdNum = trap.GetCurrentCmdNumber()
		trap.GetUserCmd(cmdNum, cmd)

		BG.PM_UpdateViewAngles(out, cmd)
	end

	-- if the next frame is a teleport, we can't lerp to it
	if cg.nextFrameTeleport then
		return
	end

	if next == nil or next.serverTime <= prev.serverTime then
		return
	end

	local f = (cg.time - prev.serverTime) / (next.serverTime - prev.serverTime)

	local i = next.ps.bobCycle
	if i < prev.ps.bobCycle then
		i += 256 -- handle wraparound
	end
	out.bobCycle = Q.int(prev.ps.bobCycle + f * (i - prev.ps.bobCycle))

	for j = 0, 2 do
		out.origin[j] = prev.ps.origin[j] + f * (next.ps.origin[j] - prev.ps.origin[j])
		if not grabAngles then
			out.viewangles[j] = Q.LerpAngle(prev.ps.viewangles[j], next.ps.viewangles[j], f)
		end
		out.velocity[j] = prev.ps.velocity[j] + f * (next.ps.velocity[j] - prev.ps.velocity[j])
	end
end

local function CG_TouchItem(cent)
	local cg = G.cg
	local cgs = G.cgs

	if cgs.gametype == C.GT_ELIMINATION or cgs.gametype == C.GT_LMS then
		return -- No weapon pickup in elimination
	end

	local canBePicked = true

	local np = cgs.nopickup
	if np == true or (type(np) == "number" and np ~= 0) or cgs.gametype == C.GT_CTF_ELIMINATION then
		canBePicked = false
	end

	if G.cg_predictItems.integer == 0 then
		return
	end
	if not BG.BG_PlayerTouchesItem(cg.predictedPlayerState, cent.currentState, cg.time) then
		return
	end

	-- never pick an item up twice in a prediction
	if cent.miscTime == cg.time then
		return
	end

	if not BG.BG_CanItemBeGrabbed(cgs.gametype, cent.currentState, cg.predictedPlayerState) then
		return -- can't hold it
	end

	local item = BG.bg_itemlist[cent.currentState.modelindex]
	local ps = cg.predictedPlayerState

	-- Special case for flags.
	-- We don't predict touching our own flag
	if cgs.gametype == C.GT_1FCTF then
		if item.giTag ~= C.PW_NEUTRALFLAG then
			return
		end
	end
	if cgs.gametype == C.GT_CTF or cgs.gametype == C.GT_CTF_ELIMINATION or cgs.gametype == C.GT_HARVESTER then
		if ps.persistant[C.PERS_TEAM] == C.TEAM_RED and item.giTag == C.PW_REDFLAG then
			return
		end
		if ps.persistant[C.PERS_TEAM] == C.TEAM_BLUE and item.giTag == C.PW_BLUEFLAG then
			return
		end
		-- Even in instantgib, we can predict our enemy flag
		if
			ps.persistant[C.PERS_TEAM] == C.TEAM_RED
			and item.giTag == C.PW_BLUEFLAG
			and (bit32.band(cgs.elimflags, C.EF_ONEWAY) == 0 or cgs.attackingTeam == C.TEAM_RED)
		then
			canBePicked = true
		end
		if
			ps.persistant[C.PERS_TEAM] == C.TEAM_BLUE
			and item.giTag == C.PW_REDFLAG
			and (bit32.band(cgs.elimflags, C.EF_ONEWAY) == 0 or cgs.attackingTeam == C.TEAM_BLUE)
		then
			canBePicked = true
		end
		if item.giTag == C.WP_RAILGUN then
			canBePicked = false
		end
		if item.giTag == C.WP_PLASMAGUN then
			canBePicked = false
		end
	end

	-- Currently we don't predict anything in Double Domination because it looks like we take a flag
	if cgs.gametype == C.GT_DOUBLE_D then
		if cgs.redflag == C.TEAM_NONE then
			return -- Can never pick if just one flag is NONE (because then the other is too)
		end
		if item.giTag == C.PW_REDFLAG then -- at point A
			if cgs.redflag ~= ps.persistant[C.PERS_TEAM] then -- not already taken
				trap.S_StartLocalSound(cgs.media.hitSound, C.CHAN_ANNOUNCER)
			end
			return
		end
		if item.giTag == C.PW_BLUEFLAG then -- at point B
			if cgs.blueflag ~= ps.persistant[C.PERS_TEAM] then -- already taken
				trap.S_StartLocalSound(cgs.media.hitSound, C.CHAN_ANNOUNCER)
			end
			return
		end
	end

	-- grab it
	if canBePicked then
		BG.BG_AddPredictableEventToPlayerstate(C.EV_ITEM_PICKUP, cent.currentState.modelindex, cg.predictedPlayerState)

		-- remove it from the frame so it won't be drawn
		cent.currentState.eFlags = bit32.bor(cent.currentState.eFlags, C.EF_NODRAW)

		-- don't touch it again this prediction
		cent.miscTime = cg.time

		-- if its a weapon, give them some predicted ammo so the autoswitch will work
		if item.giType == C.IT_WEAPON then
			ps.stats[C.STAT_WEAPONS] = bit32.bor(ps.stats[C.STAT_WEAPONS], bit32.lshift(1, item.giTag))
			if ps.ammo[item.giTag] == 0 then
				ps.ammo[item.giTag] = 1
			end
		end
	end
end

--[[
=========================
CG_TouchTriggerPrediction

Predict push triggers and items
=========================
]]
local function CG_TouchTriggerPrediction()
	local cg = G.cg
	local ps = cg.predictedPlayerState
	local trace = T.trace_t()

	-- dead clients don't activate triggers
	if ps.stats[C.STAT_HEALTH] <= 0 then
		return
	end

	local spectator = ps.pm_type == C.PM_SPECTATOR

	if ps.pm_type ~= C.PM_NORMAL and not spectator then
		return
	end

	for i = 0, cg_numTriggerEntities - 1 do
		local cent = cg_triggerEntities[i]
		local ent = cent.currentState

		if ent.eType == C.ET_ITEM and not spectator then
			CG_TouchItem(cent)
			continue
		end

		if ent.solid ~= C.SOLID_BMODEL then
			continue
		end

		local cmodel = trap.CM_InlineModel(ent.modelindex)
		if cmodel == 0 then
			continue
		end

		trap.CM_BoxTrace(trace, ps.origin, ps.origin, cg_pmove.mins, cg_pmove.maxs, cmodel, -1)

		if not trace.startsolid then
			continue
		end

		if ent.eType == C.ET_TELEPORT_TRIGGER then
			cg.hyperspace = true
		elseif ent.eType == C.ET_PUSH_TRIGGER then
			BG.BG_TouchJumpPad(ps, ent)
		end
	end

	-- if we didn't touch a jump pad this pmove frame
	if ps.jumppad_frame ~= ps.pmove_framecount then
		ps.jumppad_frame = 0
		ps.jumppad_ent = 0
	end
end

--unlagged - optimized prediction
local function ABS(x)
	return if x < 0 then -x else x
end

local function IsUnacceptableError(ps, pps)
	local delta = Q.vec3(0, 0, 0)

	if pps.pm_type ~= ps.pm_type or pps.pm_flags ~= ps.pm_flags or pps.pm_time ~= ps.pm_time then
		return 1
	end

	Q.VectorSubtract(pps.origin, ps.origin, delta)
	if Q.VectorLengthSquared(delta) > 0.1 * 0.1 then
		if G.cg_showmiss.integer ~= 0 then
			G.CG_Printf(Q.va("delta: %.2f  ", Q.VectorLength(delta)))
		end
		return 2
	end

	Q.VectorSubtract(pps.velocity, ps.velocity, delta)
	if Q.VectorLengthSquared(delta) > 0.1 * 0.1 then
		if G.cg_showmiss.integer ~= 0 then
			G.CG_Printf(Q.va("delta: %.2f  ", Q.VectorLength(delta)))
		end
		return 3
	end

	if
		pps.weaponTime ~= ps.weaponTime
		or pps.gravity ~= ps.gravity
		or pps.speed ~= ps.speed
		or pps.delta_angles[0] ~= ps.delta_angles[0]
		or pps.delta_angles[1] ~= ps.delta_angles[1]
		or pps.delta_angles[2] ~= ps.delta_angles[2]
		or pps.groundEntityNum ~= ps.groundEntityNum
	then
		return 4
	end

	if
		pps.legsTimer ~= ps.legsTimer
		or pps.legsAnim ~= ps.legsAnim
		or pps.torsoTimer ~= ps.torsoTimer
		or pps.torsoAnim ~= ps.torsoAnim
		or pps.movementDir ~= ps.movementDir
	then
		return 5
	end

	Q.VectorSubtract(pps.grapplePoint, ps.grapplePoint, delta)
	if Q.VectorLengthSquared(delta) > 0.1 * 0.1 then
		return 6
	end

	if pps.eFlags ~= ps.eFlags then
		return 7
	end

	if pps.eventSequence ~= ps.eventSequence then
		return 8
	end

	for i = 0, C.MAX_PS_EVENTS - 1 do
		if pps.events[i] ~= ps.events[i] or pps.eventParms[i] ~= ps.eventParms[i] then
			return 9
		end
	end

	if
		pps.externalEvent ~= ps.externalEvent
		or pps.externalEventParm ~= ps.externalEventParm
		or pps.externalEventTime ~= ps.externalEventTime
	then
		return 10
	end

	if pps.clientNum ~= ps.clientNum or pps.weapon ~= ps.weapon or pps.weaponstate ~= ps.weaponstate then
		return 11
	end

	if
		ABS(pps.viewangles[0] - ps.viewangles[0]) > 1.0
		or ABS(pps.viewangles[1] - ps.viewangles[1]) > 1.0
		or ABS(pps.viewangles[2] - ps.viewangles[2]) > 1.0
	then
		return 12
	end

	if pps.viewheight ~= ps.viewheight then
		return 13
	end

	if
		pps.damageEvent ~= ps.damageEvent
		or pps.damageYaw ~= ps.damageYaw
		or pps.damagePitch ~= ps.damagePitch
		or pps.damageCount ~= ps.damageCount
	then
		return 14
	end

	for i = 0, C.MAX_STATS - 1 do
		if pps.stats[i] ~= ps.stats[i] then
			return 15
		end
	end

	for i = 0, C.MAX_PERSISTANT - 1 do
		if pps.persistant[i] ~= ps.persistant[i] then
			return 16
		end
	end

	for i = 0, C.MAX_POWERUPS - 1 do
		if pps.powerups[i] ~= ps.powerups[i] then
			return 17
		end
	end

	for i = 0, C.MAX_WEAPONS - 1 do
		if pps.ammo[i] ~= ps.ammo[i] then
			return 18
		end
	end

	if pps.generic1 ~= ps.generic1 or pps.loopSound ~= ps.loopSound or pps.jumppad_ent ~= ps.jumppad_ent then
		return 19
	end

	return 0
end
--unlagged - optimized prediction

--[[
=================
CG_PredictPlayerState

Generates cg.predictedPlayerState for the current cg.time
cg.predictedPlayerState is guaranteed to be valid after exiting.

For demo playback, this will be an interpolation between two valid
playerState_t.

For normal gameplay, it will be the result of predicted usercmd_t on
top of the most recent playerState_t received from the server.

Each new snapshot will usually have one or more new usercmd over the last,
but we simulate all unacknowledged commands each time, not just the new ones.
This means that on an internet connection, quite a few pmoves may be issued
each frame.

OPTIMIZE: don't re-simulate unless the newly arrived snapshot playerState_t
differs from the predicted one.  Would require saving all intermediate
playerState_t during prediction.

We detect prediction errors and allow them to be decayed off over several frames
to ease the jerk.
=================
]]
function G.CG_PredictPlayerState()
	local cg = G.cg
	local cgs = G.cgs
	local stateIndex = 0
	local predictCmd = 0

	cg.hyperspace = false -- will be set if touching a trigger_teleport

	-- if this is the first frame we must guarantee
	-- predictedPlayerState is valid even if there is some
	-- other error condition
	if not cg.validPPS then
		cg.validPPS = true
		T.assign(cg.predictedPlayerState, cg.snap.ps)
	end

	-- demo playback just copies the moves
	if cg.demoPlayback or bit32.band(cg.snap.ps.pm_flags, C.PMF_FOLLOW) ~= 0 then
		CG_InterpolatePlayerState(false)
		return
	end

	-- non-predicting local movement will grab the latest angles
	if G.cg_nopredict.integer ~= 0 or G.cg_synchronousClients.integer ~= 0 or not BG.hasPmove then
		CG_InterpolatePlayerState(true)
		return
	end

	-- prepare for pmove
	cg_pmove.ps = cg.predictedPlayerState
	cg_pmove.trace = G.CG_Trace
	cg_pmove.pointcontents = G.CG_PointContents
	if cg_pmove.ps.pm_type == C.PM_DEAD then
		cg_pmove.tracemask = bit32.band(C.MASK_PLAYERSOLID, bit32.bnot(C.CONTENTS_BODY))
	else
		cg_pmove.tracemask = C.MASK_PLAYERSOLID
	end
	if cg.snap.ps.persistant[C.PERS_TEAM] == C.TEAM_SPECTATOR then
		cg_pmove.tracemask = bit32.band(cg_pmove.tracemask, bit32.bnot(C.CONTENTS_BODY)) -- spectators can fly through bodies
	end
	cg_pmove.noFootsteps = bit32.band(cgs.dmflags, C.DF_NO_FOOTSTEPS) > 0

	-- save the state before the pmove so we can detect transitions
	local oldPlayerState = T.copy(cg.predictedPlayerState)

	local current = trap.GetCurrentCmdNumber()

	-- if we don't have the commands right after the snapshot, we
	-- can't accurately predict a current position, so just freeze at
	-- the last good position we had
	local cmdNum = current - C.CMD_BACKUP + 1
	local oldestCmd = T.usercmd_t()
	trap.GetUserCmd(cmdNum, oldestCmd)
	if oldestCmd.serverTime > cg.snap.ps.commandTime and oldestCmd.serverTime < cg.time then -- special check for map_restart
		if G.cg_showmiss.integer ~= 0 then
			G.CG_Printf("exceeded PACKET_BACKUP on commands\n")
		end
		return
	end

	-- get the latest command so we can know which commands are from previous map_restarts
	local latestCmd = T.usercmd_t()
	trap.GetUserCmd(current, latestCmd)

	-- get the most recent information we have, even if
	-- the server time is beyond our current cg.time,
	-- because predicted player positions are going to
	-- be ahead of everything else anyway
	if cg.nextSnap ~= nil and not cg.nextFrameTeleport and not cg.thisFrameTeleport then
		T.assign(cg.predictedPlayerState, cg.nextSnap.ps)
		cg.physicsTime = cg.nextSnap.serverTime
	else
		T.assign(cg.predictedPlayerState, cg.snap.ps)
		cg.physicsTime = cg.snap.serverTime
	end

	if G.pmove_msec.integer < 8 then
		trap.Cvar_Set("pmove_msec", "8")
	elseif G.pmove_msec.integer > 33 then
		trap.Cvar_Set("pmove_msec", "33")
	end

	cg_pmove.pmove_fixed = G.pmove_fixed.integer
	cg_pmove.pmove_msec = G.pmove_msec.integer
	cg_pmove.pmove_float = G.pmove_float.integer
	cg_pmove.pmove_flags = cgs.dmflags

	--unlagged - optimized prediction
	if G.cg_optimizePrediction.integer ~= 0 then
		if cg.nextFrameTeleport or cg.thisFrameTeleport then
			-- do a full predict
			cg.lastPredictedCommand = 0
			cg.stateTail = cg.stateHead
			predictCmd = current - C.CMD_BACKUP + 1
		-- cg.physicsTime is the current snapshot's serverTime
		-- if it's the same as the last one
		elseif cg.physicsTime == cg.lastServerTime then
			-- we have no new information, so do an incremental predict
			predictCmd = cg.lastPredictedCommand + 1
		else
			-- we have a new snapshot
			local error = true

			-- loop through the saved states queue
			local i = cg.stateHead
			while i ~= cg.stateTail do
				-- if we find a predicted state whose commandTime matches the snapshot player state's commandTime
				if cg.savedPmoveStates[i].commandTime == cg.predictedPlayerState.commandTime then
					-- make sure the state differences are acceptable
					local errorcode = IsUnacceptableError(cg.predictedPlayerState, cg.savedPmoveStates[i])

					-- too much change?
					if errorcode ~= 0 then
						if G.cg_showmiss.integer ~= 0 then
							G.CG_Printf(Q.va("errorcode %d at %d\n", errorcode, cg.time))
						end
						-- yeah, so do a full predict
						break
					end

					-- this one is almost exact, so we'll copy it in as the starting point
					T.assign(cg_pmove.ps, cg.savedPmoveStates[i])
					-- advance the head
					cg.stateHead = (i + 1) % C.NUM_SAVED_STATES

					-- set the next command to predict
					predictCmd = cg.lastPredictedCommand + 1

					-- a saved state matched, so flag it
					error = false
					break
				end
				i = (i + 1) % C.NUM_SAVED_STATES
			end

			-- if no saved states matched
			if error then
				-- do a full predict
				cg.lastPredictedCommand = 0
				cg.stateTail = cg.stateHead
				predictCmd = current - C.CMD_BACKUP + 1
			end
		end

		-- keep track of the server time of the last snapshot so we
		-- know when we're starting from a new one in future calls
		cg.lastServerTime = cg.physicsTime
		stateIndex = cg.stateHead
	end
	--unlagged - optimized prediction

	-- run cmds
	local moved = false
	for n = current - C.CMD_BACKUP + 1, current do
		cmdNum = n
		-- get the command
		trap.GetUserCmd(cmdNum, cg_pmove.cmd)

		if cg_pmove.pmove_fixed ~= 0 then
			BG.PM_UpdateViewAngles(cg_pmove.ps, cg_pmove.cmd)
		end

		-- don't do anything if the time is before the snapshot player time
		if cg_pmove.cmd.serverTime <= cg.predictedPlayerState.commandTime then
			continue
		end

		-- don't do anything if the command was from a previous map_restart
		if cg_pmove.cmd.serverTime > latestCmd.serverTime then
			continue
		end

		-- check for a prediction error from last frame
		-- on a lan, this will often be the exact value
		-- from the snapshot, but on a wan we will have
		-- to predict several commands to get to the point
		-- we want to compare
		if cg.predictedPlayerState.commandTime == oldPlayerState.commandTime then
			local delta = Q.vec3(0, 0, 0)

			if cg.thisFrameTeleport then
				-- a teleport will not cause an error decay
				Q.VectorClear(cg.predictedError)
				if G.cg_showmiss.integer ~= 0 then
					G.CG_Printf("PredictionTeleport\n")
				end
				cg.thisFrameTeleport = false
			else
				local adjusted = Q.vec3(0, 0, 0)
				local new_angles = Q.vec3(0, 0, 0)
				G.CG_AdjustPositionForMover(
					cg.predictedPlayerState.origin,
					cg.predictedPlayerState.groundEntityNum,
					cg.physicsTime,
					cg.oldTime,
					adjusted,
					cg.predictedPlayerState.viewangles,
					new_angles
				)

				if G.cg_showmiss.integer ~= 0 then
					if not Q.VectorCompare(oldPlayerState.origin, adjusted) then
						G.CG_Printf("prediction error\n")
					end
				end
				Q.VectorSubtract(oldPlayerState.origin, adjusted, delta)
				local len = Q.VectorLength(delta)
				if len > 0.1 then
					if G.cg_showmiss.integer ~= 0 then
						G.CG_Printf(Q.va("Prediction miss: %f\n", len))
					end
					if G.cg_errorDecay.integer ~= 0 then
						local t = cg.time - cg.predictedErrorTime
						local f = (G.cg_errorDecay.value - t) / G.cg_errorDecay.value
						if f < 0 then
							f = 0
						end
						if f > 0 and G.cg_showmiss.integer ~= 0 then
							G.CG_Printf(Q.va("Double prediction decay: %f\n", f))
						end
						Q.VectorScale(cg.predictedError, f, cg.predictedError)
					else
						Q.VectorClear(cg.predictedError)
					end
					Q.VectorAdd(delta, cg.predictedError, cg.predictedError)
					cg.predictedErrorTime = cg.oldTime
				end
			end
		end

		-- don't predict gauntlet firing, which is only supposed to happen
		-- when it actually inflicts damage
		cg_pmove.gauntletHit = false

		if cg_pmove.pmove_fixed ~= 0 then
			cg_pmove.cmd.serverTime = Q.idiv(cg_pmove.cmd.serverTime + G.pmove_msec.integer - 1, G.pmove_msec.integer)
				* G.pmove_msec.integer
		end

		--unlagged - optimized prediction
		if G.cg_optimizePrediction.integer ~= 0 then
			-- if we need to predict this command, or we've run out of space in the saved states queue
			if cmdNum >= predictCmd or (stateIndex + 1) % C.NUM_SAVED_STATES == cg.stateHead then
				-- run the Pmove
				BG.Pmove(cg_pmove)

				-- record the last predicted command
				cg.lastPredictedCommand = cmdNum

				-- if we haven't run out of space in the saved states queue
				if (stateIndex + 1) % C.NUM_SAVED_STATES ~= cg.stateHead then
					-- save the state for the false case (of cmdNum >= predictCmd)
					-- in later calls to this function
					T.assign(cg.savedPmoveStates[stateIndex], cg_pmove.ps)
					stateIndex = (stateIndex + 1) % C.NUM_SAVED_STATES
					cg.stateTail = stateIndex
				end
			else
				if
					G.cg_showmiss.integer ~= 0
					and cg.savedPmoveStates[stateIndex].commandTime ~= cg_pmove.cmd.serverTime
				then
					-- this should ONLY happen just after changing the value of pmove_fixed
					G.CG_Printf("saved state miss\n")
				end

				-- play back the command from the saved states
				T.assign(cg_pmove.ps, cg.savedPmoveStates[stateIndex])

				-- go to the next element in the saved states array
				stateIndex = (stateIndex + 1) % C.NUM_SAVED_STATES
			end
		else
			-- run the Pmove
			BG.Pmove(cg_pmove)
		end
		--unlagged - optimized prediction

		moved = true

		-- add push trigger movement effects
		CG_TouchTriggerPrediction()
	end

	if G.cg_showmiss.integer > 1 then
		G.CG_Printf(Q.va("[%i : %i] ", cg_pmove.cmd.serverTime, cg.time))
	end

	if not moved then
		if G.cg_showmiss.integer ~= 0 then
			G.CG_Printf("not moved\n")
		end
		return
	end

	-- adjust for the movement of the groundentity
	G.CG_AdjustPositionForMover(
		cg.predictedPlayerState.origin,
		cg.predictedPlayerState.groundEntityNum,
		cg.physicsTime,
		cg.time,
		cg.predictedPlayerState.origin,
		cg.predictedPlayerState.viewangles,
		cg.predictedPlayerState.viewangles
	)

	if G.cg_showmiss.integer ~= 0 then
		if cg.predictedPlayerState.eventSequence > oldPlayerState.eventSequence + C.MAX_PS_EVENTS then
			G.CG_Printf("WARNING: dropped event\n")
		end
	end

	-- fire events and other transition triggered things
	G.CG_TransitionPlayerState(cg.predictedPlayerState, oldPlayerState)

	if G.cg_showmiss.integer ~= 0 then
		if cg.eventSequence > cg.predictedPlayerState.eventSequence then
			G.CG_Printf("WARNING: double event\n")
			cg.eventSequence = cg.predictedPlayerState.eventSequence
		end
	end
end

return G
