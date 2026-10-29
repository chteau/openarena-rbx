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
-- Luau port of code/cgame/cg_playerstate.c (OpenArena gamecode).
-- cg_playerstate.c -- this file acts on changes in a new playerState_t
-- With normal play, this will be done after local prediction, but when
-- following another player or playing back a demo, it will be checked
-- when the snapshot transitions like all the other entities

local G = require(script.Parent.G)
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local Q = require(script.Parent.Parent.q.Q)
local trap = require(script.Parent.Parent.sys.Trap)

-- If the ammo has gone low enough to generate the warning, play a sound
function G.CG_CheckAmmo()
	local cg = G.cg

	-- see about how many seconds of ammo we have remaining
	local weapons = cg.snap.ps.stats[C.STAT_WEAPONS]
	local total = 0
	for i = C.WP_MACHINEGUN, C.WP_NUM_WEAPONS - 1 do
		if bit32.band(weapons, bit32.lshift(1, i)) == 0 or i == C.WP_GRAPPLING_HOOK then
			continue
		end
		if
			i == C.WP_ROCKET_LAUNCHER
			or i == C.WP_GRENADE_LAUNCHER
			or i == C.WP_RAILGUN
			or i == C.WP_SHOTGUN
			or i == C.WP_PROX_LAUNCHER
		then
			total += cg.snap.ps.ammo[i] * 1000
		else
			total += cg.snap.ps.ammo[i] * 200
		end
		if total >= 5000 then
			cg.lowAmmoWarning = 0
			return
		end
	end

	local previous = cg.lowAmmoWarning

	if total == 0 then
		cg.lowAmmoWarning = 2
	else
		cg.lowAmmoWarning = 1
	end

	-- play a sound on transitions
	if cg.lowAmmoWarning ~= previous then
		trap.S_StartLocalSound(G.cgs.media.noAmmoSound, C.CHAN_LOCAL_SOUND)
	end
end

function G.CG_DamageFeedback(yawByte, pitchByte, damage)
	local cg = G.cg

	-- show the attacking player's head and name in corner
	cg.attackerTime = cg.time

	-- the lower on health you are, the greater the view kick will be
	local health = cg.snap.ps.stats[C.STAT_HEALTH]
	local scale
	if health < 40 then
		scale = 1
	else
		scale = 40.0 / health
	end
	local kick = damage * scale

	if kick < 5 then
		kick = 5
	end
	if kick > 10 then
		kick = 10
	end

	-- if yaw and pitch are both 255, make the damage always centered (falling, etc)
	if yawByte == 255 and pitchByte == 255 then
		cg.damageX = 0
		cg.damageY = 0
		cg.v_dmg_roll = 0
		cg.v_dmg_pitch = -kick
	else
		-- positional
		local pitch = pitchByte / 255.0 * 360
		local yaw = yawByte / 255.0 * 360

		local angles = Q.vec3(pitch, yaw, 0)
		local dir = Q.vec3(0, 0, 0)

		Q.AngleVectors(angles, dir, nil, nil)
		Q.VectorSubtract(Q.vec3(0, 0, 0), dir, dir)

		local viewaxis = cg.refdef.viewaxis
		local front = Q.DotProduct(dir, viewaxis[0])
		local left = Q.DotProduct(dir, viewaxis[1])
		local up = Q.DotProduct(dir, viewaxis[2])

		dir[0] = front
		dir[1] = left
		dir[2] = 0
		local dist = Q.VectorLength(dir)
		if dist < 0.1 then
			dist = 0.1
		end

		cg.v_dmg_roll = kick * left

		cg.v_dmg_pitch = -kick * front

		if front <= 0.1 then
			front = 0.1
		end
		cg.damageX = -left / front
		cg.damageY = up / dist
	end

	-- clamp the position
	if cg.damageX > 1.0 then
		cg.damageX = 1.0
	end
	if cg.damageX < -1.0 then
		cg.damageX = -1.0
	end

	if cg.damageY > 1.0 then
		cg.damageY = 1.0
	end
	if cg.damageY < -1.0 then
		cg.damageY = -1.0
	end

	-- don't let the screen flashes vary as much
	if kick > 10 then
		kick = 10
	end
	cg.damageValue = kick
	cg.v_dmg_time = cg.time + C.DAMAGE_TIME
	cg.damageTime = cg.snap.serverTime
end

-- A respawn happened this snapshot
function G.CG_Respawn()
	local cg = G.cg

	-- no error decay on player movement
	cg.thisFrameTeleport = true

	-- display weapons available
	cg.weaponSelectTime = cg.time

	-- select the weapon the server says we are using
	cg.weaponSelect = cg.snap.ps.weapon
end

function G.CG_CheckPlayerstateEvents(ps, ops)
	local cg = G.cg

	if ps.externalEvent ~= 0 and ps.externalEvent ~= ops.externalEvent then
		local cent = G.cg_entities[ps.clientNum]
		cent.currentState.event = ps.externalEvent
		cent.currentState.eventParm = ps.externalEventParm
		G.CG_EntityEvent(cent, cent.lerpOrigin)
	end

	local cent = cg.predictedPlayerEntity
	-- go through the predictable events buffer
	for i = ps.eventSequence - C.MAX_PS_EVENTS, ps.eventSequence - 1 do
		local slot = bit32.band(i, C.MAX_PS_EVENTS - 1)
		-- if we have a new predictable event
		if
			i >= ops.eventSequence
			-- or the server told us to play another event instead of a predicted event we already issued
			-- or something the server told us changed our prediction causing a different event
			or (i > ops.eventSequence - C.MAX_PS_EVENTS and ps.events[slot] ~= ops.events[slot])
		then
			local event = ps.events[slot]
			cent.currentState.event = event
			cent.currentState.eventParm = ps.eventParms[slot]
			G.CG_EntityEvent(cent, cent.lerpOrigin)

			cg.predictableEvents[bit32.band(i, C.MAX_PREDICTED_EVENTS - 1)] = event

			cg.eventSequence += 1
		end
	end
end

function G.CG_CheckChangedPredictableEvents(ps)
	local cg = G.cg

	local cent = cg.predictedPlayerEntity
	for i = ps.eventSequence - C.MAX_PS_EVENTS, ps.eventSequence - 1 do
		if i >= cg.eventSequence then
			continue
		end
		-- if this event is not further back in than the maximum predictable events we remember
		if i > cg.eventSequence - C.MAX_PREDICTED_EVENTS then
			local slot = bit32.band(i, C.MAX_PS_EVENTS - 1)
			local pslot = bit32.band(i, C.MAX_PREDICTED_EVENTS - 1)
			-- if the new playerstate event is different from a previously predicted one
			if ps.events[slot] ~= cg.predictableEvents[pslot] then
				local event = ps.events[slot]
				cent.currentState.event = event
				cent.currentState.eventParm = ps.eventParms[slot]
				G.CG_EntityEvent(cent, cent.lerpOrigin)

				cg.predictableEvents[pslot] = event

				if G.cg_showmiss.integer ~= 0 then
					G.CG_Printf("WARNING: changed predicted event\n")
				end
			end
		end
	end
end

local function pushReward(sfx, shader, rewardCount)
	local cg = G.cg
	if cg.rewardStack < (C.MAX_REWARDSTACK - 1) then
		cg.rewardStack += 1
		cg.rewardSound[cg.rewardStack] = sfx
		cg.rewardShader[cg.rewardStack] = shader
		cg.rewardCount[cg.rewardStack] = rewardCount
	end
end

function G.CG_CheckLocalSounds(ps, ops)
	local cg = G.cg
	local cgs = G.cgs
	local media = cgs.media
	local pers = ps.persistant
	local opers = ops.persistant

	-- don't play the sounds if the player just changed teams
	if pers[C.PERS_TEAM] ~= opers[C.PERS_TEAM] then
		return
	end

	-- hit changes
	if pers[C.PERS_HITS] > opers[C.PERS_HITS] then
		trap.S_StartLocalSound(media.hitSound, C.CHAN_LOCAL_SOUND)
	elseif pers[C.PERS_HITS] < opers[C.PERS_HITS] then
		trap.S_StartLocalSound(media.hitTeamSound, C.CHAN_LOCAL_SOUND)
	end

	-- health changes of more than -1 should make pain sounds
	if ps.stats[C.STAT_HEALTH] < ops.stats[C.STAT_HEALTH] - 1 then
		if ps.stats[C.STAT_HEALTH] > 0 then
			G.CG_PainEvent(cg.predictedPlayerEntity, ps.stats[C.STAT_HEALTH])
		end
	end

	-- if we are going into the intermission, don't start any voices
	if cg.intermissionStarted then
		return
	end

	-- reward sounds
	local reward = false
	if pers[C.PERS_CAPTURES] ~= opers[C.PERS_CAPTURES] then
		pushReward(media.captureAwardSound, media.medalCapture, pers[C.PERS_CAPTURES])
		reward = true
	end
	if pers[C.PERS_IMPRESSIVE_COUNT] ~= opers[C.PERS_IMPRESSIVE_COUNT] then
		pushReward(media.impressiveSound, media.medalImpressive, pers[C.PERS_IMPRESSIVE_COUNT])
		reward = true
	end
	--KK-OAX We Just Won't Draw The Excellent Stuff if Multikills are Enabled!!!
	local altExcellent = cgs.altExcellent
	if altExcellent == 0 or altExcellent == false or altExcellent == nil then
		if pers[C.PERS_EXCELLENT_COUNT] ~= opers[C.PERS_EXCELLENT_COUNT] then
			pushReward(media.excellentSound, media.medalExcellent, pers[C.PERS_EXCELLENT_COUNT])
			reward = true
		end
	end
	if pers[C.PERS_GAUNTLET_FRAG_COUNT] ~= opers[C.PERS_GAUNTLET_FRAG_COUNT] then
		pushReward(media.humiliationSound, media.medalGauntlet, pers[C.PERS_GAUNTLET_FRAG_COUNT])
		reward = true
	end
	if pers[C.PERS_DEFEND_COUNT] ~= opers[C.PERS_DEFEND_COUNT] then
		pushReward(media.defendSound, media.medalDefend, pers[C.PERS_DEFEND_COUNT])
		reward = true
	end
	if pers[C.PERS_ASSIST_COUNT] ~= opers[C.PERS_ASSIST_COUNT] then
		pushReward(media.assistSound, media.medalAssist, pers[C.PERS_ASSIST_COUNT])
		reward = true
	end
	-- if any of the player event bits changed
	if pers[C.PERS_PLAYEREVENTS] ~= opers[C.PERS_PLAYEREVENTS] then
		local pe = pers[C.PERS_PLAYEREVENTS]
		local ope = opers[C.PERS_PLAYEREVENTS]
		if bit32.band(pe, C.PLAYEREVENT_DENIEDREWARD) ~= bit32.band(ope, C.PLAYEREVENT_DENIEDREWARD) then
			trap.S_StartLocalSound(media.deniedSound, C.CHAN_ANNOUNCER)
		elseif bit32.band(pe, C.PLAYEREVENT_GAUNTLETREWARD) ~= bit32.band(ope, C.PLAYEREVENT_GAUNTLETREWARD) then
			trap.S_StartLocalSound(media.humiliationSound, C.CHAN_ANNOUNCER)
		elseif bit32.band(pe, C.PLAYEREVENT_HOLYSHIT) ~= bit32.band(ope, C.PLAYEREVENT_HOLYSHIT) then
			trap.S_StartLocalSound(media.holyShitSound, C.CHAN_ANNOUNCER)
		end
		reward = true
	end

	-- check for flag pickup
	if cgs.gametype > C.GT_TEAM then
		local pw, opw = ps.powerups, ops.powerups
		if
			(pw[C.PW_REDFLAG] ~= opw[C.PW_REDFLAG] and pw[C.PW_REDFLAG] ~= 0)
			or (pw[C.PW_BLUEFLAG] ~= opw[C.PW_BLUEFLAG] and pw[C.PW_BLUEFLAG] ~= 0)
			or (pw[C.PW_NEUTRALFLAG] ~= opw[C.PW_NEUTRALFLAG] and pw[C.PW_NEUTRALFLAG] ~= 0)
		then
			trap.S_StartLocalSound(media.youHaveFlagSound, C.CHAN_ANNOUNCER)
		end
	end

	-- lead changes
	if not reward then
		if cg.warmup == 0 then
			-- never play lead changes during warmup
			if pers[C.PERS_RANK] ~= opers[C.PERS_RANK] then
				if cgs.gametype < C.GT_TEAM or cgs.ffa_gt == 1 then
					if pers[C.PERS_RANK] == 0 then
						G.CG_AddBufferedSound(media.takenLeadSound)
					elseif pers[C.PERS_RANK] == C.RANK_TIED_FLAG and cgs.gametype ~= C.GT_POSSESSION then
						G.CG_AddBufferedSound(media.tiedLeadSound)
					elseif
						pers[C.PERS_RANK] ~= C.RANK_TIED_FLAG
						and bit32.band(opers[C.PERS_RANK], bit32.bnot(C.RANK_TIED_FLAG)) == 0
					then
						G.CG_AddBufferedSound(media.lostLeadSound)
					end
				end
			end
		end
	end

	-- timelimit warnings
	if cgs.timelimit > 0 and cgs.timelimit <= 1000 then
		local msec = cg.time - cgs.levelStartTime
		if bit32.band(cg.timelimitWarnings, 4) == 0 and msec > (cgs.timelimit * 60 + 2) * 1000 then
			cg.timelimitWarnings = bit32.bor(cg.timelimitWarnings, 1, 2, 4)
			trap.S_StartLocalSound(media.suddenDeathSound, C.CHAN_ANNOUNCER)
		elseif bit32.band(cg.timelimitWarnings, 2) == 0 and msec > (cgs.timelimit - 1) * 60 * 1000 then
			cg.timelimitWarnings = bit32.bor(cg.timelimitWarnings, 1, 2)
			trap.S_StartLocalSound(media.oneMinuteSound, C.CHAN_ANNOUNCER)
		elseif cgs.timelimit > 5 and bit32.band(cg.timelimitWarnings, 1) == 0 and msec > (cgs.timelimit - 5) * 60 * 1000 then
			cg.timelimitWarnings = bit32.bor(cg.timelimitWarnings, 1)
			trap.S_StartLocalSound(media.fiveMinuteSound, C.CHAN_ANNOUNCER)
		end
	end

	-- fraglimit warnings
	if cgs.fraglimit > 0 and cgs.gametype < C.GT_CTF then
		local highScore = cgs.scores1

		if cgs.gametype == C.GT_TEAM and cgs.scores2 > highScore then
			highScore = cgs.scores2
		end

		if bit32.band(cg.fraglimitWarnings, 4) == 0 and highScore == (cgs.fraglimit - 1) then
			cg.fraglimitWarnings = bit32.bor(cg.fraglimitWarnings, 1, 2, 4)
			G.CG_AddBufferedSound(media.oneFragSound)
		elseif cgs.fraglimit > 2 and bit32.band(cg.fraglimitWarnings, 2) == 0 and highScore == (cgs.fraglimit - 2) then
			cg.fraglimitWarnings = bit32.bor(cg.fraglimitWarnings, 1, 2)
			G.CG_AddBufferedSound(media.twoFragSound)
		elseif cgs.fraglimit > 3 and bit32.band(cg.fraglimitWarnings, 1) == 0 and highScore == (cgs.fraglimit - 3) then
			cg.fraglimitWarnings = bit32.bor(cg.fraglimitWarnings, 1)
			G.CG_AddBufferedSound(media.threeFragSound)
		end
	end
end

function G.CG_TransitionPlayerState(ps, ops)
	local cg = G.cg

	-- check for changing follow mode
	if ps.clientNum ~= ops.clientNum then
		cg.thisFrameTeleport = true
		-- make sure we don't get any unwanted transition effects
		T.assign(ops, ps)
	end

	-- damage events (player is getting wounded)
	if ps.damageEvent ~= ops.damageEvent and ps.damageCount ~= 0 then
		G.CG_DamageFeedback(ps.damageYaw, ps.damagePitch, ps.damageCount)
	end

	-- respawning
	if ps.persistant[C.PERS_SPAWN_COUNT] ~= ops.persistant[C.PERS_SPAWN_COUNT] then
		G.CG_Respawn()
	end

	if cg.mapRestart then
		G.CG_Respawn()
		cg.mapRestart = false
	end

	if cg.snap.ps.pm_type ~= C.PM_INTERMISSION and ps.persistant[C.PERS_TEAM] ~= C.TEAM_SPECTATOR then
		G.CG_CheckLocalSounds(ps, ops)
	end

	-- check for going low on ammo
	G.CG_CheckAmmo()

	-- run events
	G.CG_CheckPlayerstateEvents(ps, ops)

	-- smooth the ducking viewheight change
	if ps.viewheight ~= ops.viewheight then
		cg.duckChange = ps.viewheight - ops.viewheight
		cg.duckTime = cg.time
	end
end

return G
