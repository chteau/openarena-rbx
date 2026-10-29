--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_active.c, part 2 of 2).

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
-- Luau port of OpenArena 0.8.8's g_active.c (gamecode 9e0f0c0) (part 2). Client think, end frame and spectator frame handling.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SF = G.FileStatics("g_active")

-- part 1 helpers may be static (SF) or global (G); resolve when called
local function P1(name)
	local f = SF[name]
	if f == nil then
		f = G[name]
	end
	return f
end

function SF.StuckInOtherClient(ent)
	local ent2
	for i = 0, C.MAX_CLIENTS - 1 do
		ent2 = G.g_entities[i]
		if ent2 == ent then
			continue
		end
		if not ent2.inuse then
			continue
		end
		if ent2.client == nil then
			continue
		end
		if ent2.health <= 0 then
			continue
		end
		--
		if ent2.r.absmin[0] > ent.r.absmax[0] then
			continue
		end
		if ent2.r.absmin[1] > ent.r.absmax[1] then
			continue
		end
		if ent2.r.absmin[2] > ent.r.absmax[2] then
			continue
		end
		if ent2.r.absmax[0] < ent.r.absmin[0] then
			continue
		end
		if ent2.r.absmax[1] < ent.r.absmin[1] then
			continue
		end
		if ent2.r.absmax[2] < ent.r.absmin[2] then
			continue
		end
		return true
	end
	return false
end

--[[
==============
SendPendingPredictableEvents
==============
]]
function G.SendPendingPredictableEvents(ps)
	-- if there are still events pending
	if ps.entityEventSequence < ps.eventSequence then
		-- create a temporary entity for this event which is sent to everyone
		-- except the client who generated the event
		local seq = bit32.band(ps.entityEventSequence, C.MAX_PS_EVENTS - 1)
		local event = bit32.bor(ps.events[seq], bit32.lshift(bit32.band(ps.entityEventSequence, 3), 8))
		-- set external event to zero before calling BG_PlayerStateToEntityState
		local extEvent = ps.externalEvent
		ps.externalEvent = 0
		-- create temporary entity for event
		local t = G.G_TempEntity(ps.origin, event)
		local number = t.s.number
		BG.BG_PlayerStateToEntityState(ps, t.s, true)
		t.s.number = number
		t.s.eType = C.ET_EVENTS + event
		t.s.eFlags = bit32.bor(t.s.eFlags, C.EF_PLAYER_EVENT)
		t.s.otherEntityNum = ps.clientNum
		-- send to everyone except the client who generated the event
		t.r.svFlags = bit32.bor(t.r.svFlags, C.SVF_NOTSINGLECLIENT)
		t.r.singleClient = ps.clientNum
		-- set back external event
		ps.externalEvent = extEvent
	end
end

--[[
==============
ClientThink_real

This will be called once for each client frame, which will
usually be a couple times for each server frame on fast clients.

If "g_synchronousClients 1" is set, this will be called exactly
once for each server frame, which makes for smooth demo recording.
==============
]]
function G.ClientThink_real(ent)
	local level = G.level
	local client = ent.client

	-- don't think if the client is not yet connected (and thus not yet spawned in)
	if client.pers.connected ~= C.CON_CONNECTED then
		return
	end
	-- mark the time, so the connection sprite can be removed
	local ucmd = ent.client.pers.cmd

	-- sanity check the command time to prevent speedup cheating
	if ucmd.serverTime > level.time + 200 then
		ucmd.serverTime = level.time + 200
	end
	if ucmd.serverTime < level.time - 1000 then
		ucmd.serverTime = level.time - 1000
	end

	--unlagged - backward reconciliation #4
	-- frameOffset should be about the number of milliseconds into a frame
	-- this command packet was received, depending on how fast the server
	-- does a G_RunFrame()
	client.frameOffset = G.trap_Milliseconds() - level.frameStartTime

	--unlagged - true ping
	-- save the estimated ping in a queue for averaging later

	-- we use level.previousTime to account for 50ms lag correction
	-- besides, this will turn out numbers more like what players are used to
	client.pers.pingsamples[client.pers.samplehead] = level.previousTime + client.frameOffset - ucmd.serverTime
	client.pers.samplehead += 1
	if client.pers.samplehead >= C.NUM_PING_SAMPLES then
		client.pers.samplehead -= C.NUM_PING_SAMPLES
	end

	-- initialize the real ping
	if G.g_truePing.integer ~= 0 then
		local sum = 0

		-- get an average of the samples we saved up
		for i = 0, C.NUM_PING_SAMPLES - 1 do
			sum += client.pers.pingsamples[i]
		end

		client.pers.realPing = Q.idiv(sum, C.NUM_PING_SAMPLES)
	else
		-- if g_truePing is off, use the normal ping
		client.pers.realPing = client.ps.ping
	end

	--unlagged - backward reconciliation #4
	-- save the command time *before* pmove_fixed messes with the serverTime,
	-- and *after* lag simulation messes with it :)
	-- attackTime will be used for backward reconciliation later (time shift)
	client.attackTime = ucmd.serverTime

	--unlagged - smooth clients #1
	-- keep track of this for later - we'll use this to decide whether or not
	-- to send extrapolated positions for this client
	client.lastUpdateFrame = level.framenum

	--unlagged - true ping
	-- make sure the true ping is over 0 - with cl_timenudge it can be less
	if client.pers.realPing < 0 then
		client.pers.realPing = 0
	end

	local msec = ucmd.serverTime - client.ps.commandTime
	-- following others may result in bad times, but we still want
	-- to check for follow toggles
	if msec < 1 and client.sess.spectatorState ~= C.SPECTATOR_FOLLOW then
		return
	end
	if msec > 200 then
		msec = 200
	end

	if G.pmove_msec.integer < 8 then
		G.trap_Cvar_Set("pmove_msec", "8")
	elseif G.pmove_msec.integer > 33 then
		G.trap_Cvar_Set("pmove_msec", "33")
	end

	if G.pmove_fixed.integer ~= 0 or client.pers.pmoveFixed then
		ucmd.serverTime = Q.idiv(ucmd.serverTime + G.pmove_msec.integer - 1, G.pmove_msec.integer) * G.pmove_msec.integer
	end

	--
	-- check for exiting intermission
	--
	if level.intermissiontime ~= 0 then
		P1("ClientIntermissionThink")(client)
		return
	end

	-- spectators don't do much
	if client.sess.sessionTeam == C.TEAM_SPECTATOR or client.isEliminated then
		if client.sess.spectatorState == C.SPECTATOR_SCOREBOARD then
			return
		end
		P1("SpectatorThink")(ent, ucmd)
		return
	end

	-- check for inactivity timer, but never drop the local client of a non-dedicated server
	if not P1("ClientInactivityTimer")(client) then
		return
	end

	-- clear the rewards if time
	if level.time > client.rewardTime then
		client.ps.eFlags = bit32.band(client.ps.eFlags, bit32.bnot(bit32.bor(C.EF_AWARD_IMPRESSIVE, C.EF_AWARD_EXCELLENT, C.EF_AWARD_GAUNTLET, C.EF_AWARD_ASSIST, C.EF_AWARD_DEFEND, C.EF_AWARD_CAP)))
	end

	if client.noclip then
		client.ps.pm_type = C.PM_NOCLIP
	elseif client.ps.stats[C.STAT_HEALTH] <= 0 then
		client.ps.pm_type = C.PM_DEAD
	else
		client.ps.pm_type = C.PM_NORMAL
	end

	client.ps.gravity = Q.trunc(G.g_gravity.value * G.g_gravityModifier.value)

	-- set speed
	client.ps.speed = Q.trunc(G.g_speed.value)

	if BG.bg_itemlist[client.ps.stats[C.STAT_PERSISTANT_POWERUP]].giTag == C.PW_SCOUT then
		client.ps.speed = Q.trunc(client.ps.speed * 1.5)
	elseif client.ps.powerups[C.PW_HASTE] ~= 0 then
		client.ps.speed = Q.trunc(client.ps.speed * 1.3)
	end

	-- Let go of the hook if we aren't firing
	if client.ps.weapon == C.WP_GRAPPLING_HOOK and client.hook ~= nil and bit32.band(ucmd.buttons, C.BUTTON_ATTACK) == 0 then
		G.Weapon_HookFree(client.hook)
	end

	-- set up for pmove
	local oldEventSequence = client.ps.eventSequence

	local pm = S.pmove_t()

	-- check for the hit-scan gauntlet, don't let the action
	-- go through as an attack unless it actually hits something
	if client.ps.weapon == C.WP_GAUNTLET and bit32.band(ucmd.buttons, C.BUTTON_TALK) == 0
		and bit32.band(ucmd.buttons, C.BUTTON_ATTACK) ~= 0 and client.ps.weaponTime <= 0 then
		pm.gauntletHit = G.CheckGauntletAttack(ent)
	end

	if bit32.band(ent.flags, C.FL_FORCE_GESTURE) ~= 0 then
		ent.flags = bit32.band(ent.flags, bit32.bnot(C.FL_FORCE_GESTURE))
		ent.client.pers.cmd.buttons = bit32.bor(ent.client.pers.cmd.buttons, C.BUTTON_GESTURE)
	end

	-- check for invulnerability expansion before doing the Pmove
	if client.ps.powerups[C.PW_INVULNERABILITY] ~= 0 then
		if bit32.band(client.ps.pm_flags, C.PMF_INVULEXPAND) == 0 then
			local mins = Q.vec3()
			local maxs = Q.vec3()
			local oldmins = Q.vec3()
			local oldmaxs = Q.vec3()
			mins[0], mins[1], mins[2] = -42, -42, -42
			maxs[0], maxs[1], maxs[2] = 42, 42, 42

			Q.VectorCopy(ent.r.mins, oldmins)
			Q.VectorCopy(ent.r.maxs, oldmaxs)
			-- expand
			Q.VectorCopy(mins, ent.r.mins)
			Q.VectorCopy(maxs, ent.r.maxs)
			G.trap_LinkEntity(ent)
			-- check if this would get anyone stuck in this player
			if not SF.StuckInOtherClient(ent) then
				-- set flag so the expanded size will be set in PM_CheckDuck
				client.ps.pm_flags = bit32.bor(client.ps.pm_flags, C.PMF_INVULEXPAND)
			end
			-- set back
			Q.VectorCopy(oldmins, ent.r.mins)
			Q.VectorCopy(oldmaxs, ent.r.maxs)
			G.trap_LinkEntity(ent)
		end
	end

	pm.ps = client.ps
	S.copy_usercmd_t(pm.cmd, ucmd)
	if pm.ps.pm_type == C.PM_DEAD then
		pm.tracemask = bit32.band(C.MASK_PLAYERSOLID, bit32.bnot(C.CONTENTS_BODY))
	elseif bit32.band(ent.r.svFlags, C.SVF_BOT) ~= 0 then
		pm.tracemask = bit32.bor(C.MASK_PLAYERSOLID, C.CONTENTS_BOTCLIP)
	else
		pm.tracemask = C.MASK_PLAYERSOLID
	end
	pm.trace = function(results, start, mins, maxs, endpos, passEntityNum, contentmask)
		G.trap_Trace(results, start, mins, maxs, endpos, passEntityNum, contentmask)
	end
	pm.pointcontents = function(point, passEntityNum)
		return G.trap_PointContents(point, passEntityNum)
	end
	pm.debugLevel = G.g_debugMove.integer
	pm.noFootsteps = bit32.band(G.g_dmflags.integer, C.DF_NO_FOOTSTEPS) > 0

	pm.pmove_fixed = bit32.bor(G.pmove_fixed.integer, if client.pers.pmoveFixed then 1 else 0)
	pm.pmove_msec = G.pmove_msec.integer
	pm.pmove_float = G.pmove_float.integer
	pm.pmove_flags = G.g_dmflags.integer

	Q.VectorCopy(client.ps.origin, client.oldOrigin)

	BG.Pmove(pm)

	-- save results of pmove
	if ent.client.ps.eventSequence ~= oldEventSequence then
		ent.eventTime = level.time
	end
	--unlagged - smooth clients #2
	-- clients no longer do extrapolation if cg_smoothClients is 1, because
	-- skip correction is all handled server-side now
	-- since that's the case, it makes no sense to store the extra info
	-- in the client's snapshot entity, so let's save a little bandwidth
	BG.BG_PlayerStateToEntityState(ent.client.ps, ent.s, true)
	G.SendPendingPredictableEvents(ent.client.ps)

	if bit32.band(ent.client.ps.eFlags, C.EF_FIRING) == 0 then
		client.fireHeld = false -- for grapple
	end

	-- use the snapped origin for linking so it matches client predicted versions
	Q.VectorCopy(ent.s.pos.trBase, ent.r.currentOrigin)

	Q.VectorCopy(pm.mins, ent.r.mins)
	Q.VectorCopy(pm.maxs, ent.r.maxs)

	ent.waterlevel = pm.waterlevel
	ent.watertype = pm.watertype

	-- execute client events
	P1("ClientEvents")(ent, oldEventSequence)

	-- link entity now, after any personal teleporters have been used
	G.trap_LinkEntity(ent)
	if not ent.client.noclip then
		G.G_TouchTriggers(ent)
	end

	-- NOTE: now copy the exact origin over otherwise clients can be snapped into solid
	Q.VectorCopy(ent.client.ps.origin, ent.r.currentOrigin)

	--test for solid areas in the AAS file
	G.BotTestAAS(ent.r.currentOrigin)

	-- touch other objects
	P1("ClientImpacts")(ent, pm)

	-- save results of triggers and client events
	if ent.client.ps.eventSequence ~= oldEventSequence then
		ent.eventTime = level.time
	end

	-- swap and latch button actions
	client.oldbuttons = client.buttons
	client.buttons = ucmd.buttons
	client.latched_buttons = bit32.bor(client.latched_buttons, bit32.band(client.buttons, bit32.bnot(client.oldbuttons)))

	-- check for respawning
	if client.ps.stats[C.STAT_HEALTH] <= 0 then
		-- wait for the attack button to be pressed
		-- forcerespawn is to prevent users from waiting out powerups
		-- In Last man standing, we force a quick respawn, since
		-- the player must be able to loose health
		-- pressing attack or use is the normal respawn method
		if level.time > client.respawnTime
			and ((G.g_forcerespawn.integer > 0
				and level.time - client.respawnTime > G.g_forcerespawn.integer * 1000)
				or ((G.g_gametype.integer == C.GT_LMS
					or G.g_gametype.integer == C.GT_ELIMINATION
					or G.g_gametype.integer == C.GT_CTF_ELIMINATION)
					and level.time - client.respawnTime > 0)
				or bit32.band(ucmd.buttons, bit32.bor(C.BUTTON_ATTACK, C.BUTTON_USE_HOLDABLE)) ~= 0) then
			G.ClientRespawn(ent)
		end
		return
	end

	if pm.waterlevel <= 1 and pm.ps.groundEntityNum ~= C.ENTITYNUM_NONE and client.lastSentFlyingTime + 500 > level.time then
		if bit32.band(pm.ps.pm_flags, C.PMF_TIME_KNOCKBACK) == 0 then
			client.lastSentFlying = -1
		end
	end

	-- perform once-a-second actions
	P1("ClientTimerActions")(ent, msec)
end

--[[
==================
ClientThink

A new command has arrived from the client
==================
]]
function G.ClientThink(clientNum)
	local ent = G.g_entities[clientNum]
	G.trap_GetUsercmd(clientNum, ent.client.pers.cmd)

	if bit32.band(ent.r.svFlags, C.SVF_BOT) == 0 and G.g_synchronousClients.integer == 0 then
		G.ClientThink_real(ent)
	end
end

function G.G_RunClient(ent)
	if bit32.band(ent.r.svFlags, C.SVF_BOT) == 0 and G.g_synchronousClients.integer == 0 then
		return
	end
	ent.client.pers.cmd.serverTime = G.level.time
	G.ClientThink_real(ent)
end

--[[
==================
SpectatorClientEndFrame

==================
]]
function G.SpectatorClientEndFrame(ent)
	local level = G.level
	local preservedScore = {}

	-- if we are doing a chase cam or a remote view, grab the latest info
	if ent.client.sess.spectatorState == C.SPECTATOR_FOLLOW then
		local clientNum = ent.client.sess.spectatorClient

		-- team follow1 and team follow2 go to whatever clients are playing
		if clientNum == -1 then
			clientNum = level.follow1
		elseif clientNum == -2 then
			clientNum = level.follow2
		end
		if clientNum >= 0 then
			local cl = level.clients[clientNum]
			if cl.pers.connected == C.CON_CONNECTED and cl.sess.sessionTeam ~= C.TEAM_SPECTATOR then
				local votedMask = bit32.bor(C.EF_VOTED, C.EF_TEAMVOTED)
				local flags = bit32.bor(bit32.band(cl.ps.eFlags, bit32.bnot(votedMask)), bit32.band(ent.client.ps.eFlags, votedMask))
				--this is here LMS/Elimination goes wrong with player follow
				if ent.client.sess.sessionTeam ~= C.TEAM_SPECTATOR then
					for i = 0, C.MAX_PERSISTANT - 1 do
						preservedScore[i] = ent.client.ps.persistant[i]
					end
					S.copy_playerState_t(ent.client.ps, cl.ps)
					for i = 0, C.MAX_PERSISTANT - 1 do
						ent.client.ps.persistant[i] = preservedScore[i]
					end
				else
					S.copy_playerState_t(ent.client.ps, cl.ps)
				end
				ent.client.ps.pm_flags = bit32.bor(ent.client.ps.pm_flags, C.PMF_FOLLOW)
				ent.client.ps.eFlags = flags
				return
			else
				-- drop them to free spectators unless they are dedicated camera followers
				if ent.client.sess.spectatorClient >= 0 then
					ent.client.sess.spectatorState = C.SPECTATOR_FREE
					G.ClientBegin(ent.client.index)
				end
			end
		end
	end

	if ent.client.sess.spectatorState == C.SPECTATOR_SCOREBOARD then
		ent.client.ps.pm_flags = bit32.bor(ent.client.ps.pm_flags, C.PMF_SCOREBOARD)
	else
		ent.client.ps.pm_flags = bit32.band(ent.client.ps.pm_flags, bit32.bnot(C.PMF_SCOREBOARD))
	end
end

--[[
==============
ClientEndFrame

Called at the end of each server frame for each connected client
A fast client will have multiple ClientThink for each ClientEdFrame,
while a slow client may have multiple ClientEndFrame between ClientThink.
==============
]]
function G.ClientEndFrame(ent)
	local level = G.level

	if ent.client.sess.sessionTeam == C.TEAM_SPECTATOR or ent.client.isEliminated then
		G.SpectatorClientEndFrame(ent)
		return
	end

	-- turn off any expired powerups
	for i = 0, C.MAX_POWERUPS - 1 do
		if ent.client.ps.powerups[i] < level.time then
			ent.client.ps.powerups[i] = 0
		end
	end

	-- set powerup for player animation
	if BG.bg_itemlist[ent.client.ps.stats[C.STAT_PERSISTANT_POWERUP]].giTag == C.PW_GUARD then
		ent.client.ps.powerups[C.PW_GUARD] = level.time
	end
	if BG.bg_itemlist[ent.client.ps.stats[C.STAT_PERSISTANT_POWERUP]].giTag == C.PW_SCOUT then
		ent.client.ps.powerups[C.PW_SCOUT] = level.time
	end
	if BG.bg_itemlist[ent.client.ps.stats[C.STAT_PERSISTANT_POWERUP]].giTag == C.PW_DOUBLER then
		ent.client.ps.powerups[C.PW_DOUBLER] = level.time
	end
	if BG.bg_itemlist[ent.client.ps.stats[C.STAT_PERSISTANT_POWERUP]].giTag == C.PW_AMMOREGEN then
		ent.client.ps.powerups[C.PW_AMMOREGEN] = level.time
	end
	if ent.client.invulnerabilityTime > level.time then
		ent.client.ps.powerups[C.PW_INVULNERABILITY] = level.time
	end

	--
	-- If the end of unit layout is displayed, don't give
	-- the player any normal movement attributes
	--
	if level.intermissiontime ~= 0 then
		return
	end

	-- burn from lava, etc
	P1("P_WorldEffects")(ent)

	-- apply all the damage taken this frame
	P1("P_DamageFeedback")(ent)

	ent.client.ps.stats[C.STAT_HEALTH] = ent.health -- FIXME: get rid of ent->health...

	P1("G_SetClientSound")(ent)

	--Unlagged: Always do the else clause
	BG.BG_PlayerStateToEntityState(ent.client.ps, ent.s, true)
	G.SendPendingPredictableEvents(ent.client.ps)

	--unlagged - smooth clients #1
	-- mark as not missing updates initially
	ent.client.ps.eFlags = bit32.band(ent.client.ps.eFlags, bit32.bnot(C.EF_CONNECTION))

	-- see how many frames the client has missed
	local frames = level.framenum - ent.client.lastUpdateFrame - 1

	-- don't extrapolate more than two frames
	if frames > 2 then
		frames = 2

		-- if they missed more than two in a row, show the phone jack
		ent.client.ps.eFlags = bit32.bor(ent.client.ps.eFlags, C.EF_CONNECTION)
		ent.s.eFlags = bit32.bor(ent.s.eFlags, C.EF_CONNECTION)
	end

	-- did the client miss any frames?
	if frames > 0 and G.g_smoothClients.integer ~= 0 then
		-- yep, missed one or more, so extrapolate the player's movement
		G.G_PredictPlayerMove(ent, frames / G.sv_fps.integer)
		-- save network bandwidth
		Q.SnapVector(ent.s.pos.trBase)
	end

	--unlagged - backward reconciliation #1
	-- store the client's position for backward reconciliation later
	G.G_StoreHistory(ent)
end

return nil
