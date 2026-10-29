--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/ai_dmq3.c, part 4 of 7).

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
-- Luau port of OpenArena 0.8.8's ai_dmq3.c (gamecode 9e0f0c0), part 4 of 7. Bot combat decisions, attack movement, enemy finding and visibility.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local SF = G.FileStatics("ai_dmq3")

local IDEAL_ATTACKDIST = 140

local function Square(x)
	return x * x
end

function G.BotWantsToChase(bs)
	local entinfo = S.aas_entityinfo_t()

	if G.gametype == C.GT_CTF or G.gametype == C.GT_CTF_ELIMINATION then
		if G.BotCTFCarryingFlag(bs) ~= 0 then
			return 0
		end
		G.BotEntityInfo(bs.enemy, entinfo)
		if G.EntityCarriesFlag(entinfo) then
			return 1
		end
	elseif G.gametype == C.GT_1FCTF then
		if G.Bot1FCTFCarryingFlag(bs) ~= 0 then
			return 0
		end
		G.BotEntityInfo(bs.enemy, entinfo)
		if G.EntityCarriesFlag(entinfo) then
			return 1
		end
	elseif G.gametype == C.GT_OBELISK then
		if bs.ltgtype == C.LTG_ATTACKENEMYBASE then
			if bs.enemy ~= G.redobelisk.entitynum and bs.enemy ~= G.blueobelisk.entitynum then
				return 0
			end
		end
	elseif G.gametype == C.GT_HARVESTER then
		if G.BotHarvesterCarryingCubes(bs) ~= 0 then
			return 0
		end

		G.BotEntityInfo(bs.enemy, entinfo)
		if G.EntityCarriesCubes(entinfo) then
			return 1
		end
	end
	if bs.ltgtype == C.LTG_GETFLAG then
		return 0
	end
	if G.BotAggression(bs) > 50 then
		return 1
	end
	return 0
end

function G.BotWantsToHelp(bs)
	return 1
end

function G.BotCanAndWantsToRocketJump(bs)
	if G.bot_rocketjump.integer == 0 then return 0 end
	if bs.inventory[C.INVENTORY_ROCKETLAUNCHER] <= 0 then return 0 end
	if bs.inventory[C.INVENTORY_ROCKETS] < 3 then return 0 end
	if (G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_CTF_ELIMINATION or G.g_gametype.integer == C.GT_LMS)
			and G.g_elimination_selfdamage.integer == 0 then
		return 1
	end
	if bs.inventory[C.INVENTORY_QUAD] ~= 0 then return 0 end
	if bs.inventory[C.INVENTORY_HEALTH] < 60 then return 0 end
	if bs.inventory[C.INVENTORY_HEALTH] < 90 then
		if bs.inventory[C.INVENTORY_ARMOR] < 40 then return 0 end
	end
	local rocketjumper = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_WEAPONJUMPING, 0, 1)
	if rocketjumper < 0.5 then return 0 end
	return 1
end

function G.BotHasPersistantPowerupAndWeapon(bs)
	if bs.inventory[C.INVENTORY_HEALTH] < 60 then return 0 end
	if bs.inventory[C.INVENTORY_HEALTH] < 80 then
		if bs.inventory[C.INVENTORY_ARMOR] < 40 then return 0 end
	end
	if bs.inventory[C.INVENTORY_BFG10K] > 0 and
			bs.inventory[C.INVENTORY_BFGAMMO] > 7 then return 1 end
	if bs.inventory[C.INVENTORY_RAILGUN] > 0 and
			bs.inventory[C.INVENTORY_SLUGS] > 5 then return 1 end
	if bs.inventory[C.INVENTORY_LIGHTNING] > 0 and
			bs.inventory[C.INVENTORY_LIGHTNINGAMMO] > 50 then return 1 end
	if bs.inventory[C.INVENTORY_ROCKETLAUNCHER] > 0 and
			bs.inventory[C.INVENTORY_ROCKETS] > 5 then return 1 end
	if bs.inventory[C.INVENTORY_NAILGUN] > 0 and
			bs.inventory[C.INVENTORY_NAILS] > 5 then return 1 end
	if bs.inventory[C.INVENTORY_PROXLAUNCHER] > 0 and
			bs.inventory[C.INVENTORY_MINES] > 5 then return 1 end
	if bs.inventory[C.INVENTORY_CHAINGUN] > 0 and
			bs.inventory[C.INVENTORY_BELT] > 40 then return 1 end
	if bs.inventory[C.INVENTORY_PLASMAGUN] > 0 and
			bs.inventory[C.INVENTORY_CELLS] > 20 then return 1 end
	return 0
end

function G.BotGoCamp(bs, goal)
	bs.decisionmaker = bs.client
	bs.teammessage_time = 0
	bs.ltgtype = C.LTG_CAMP
	S.copy_bot_goal_t(bs.teamgoal, goal)
	local camper = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_CAMPER, 0, 1)
	if camper > 0.99 then
		bs.teamgoal_time = G.floattime + 99999
	else
		bs.teamgoal_time = G.floattime + 120 + 180 * camper + Q.random() * 15
	end
	bs.camp_time = G.floattime
	bs.teammate = 0
	bs.arrive_time = 1
end

function G.BotWantsToCamp(bs)
	local goal = S.bot_goal_t()
	local bestgoal = S.bot_goal_t()

	local camper = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_CAMPER, 0, 1)
	if camper < 0.1 then return 0 end
	if bs.ltgtype == C.LTG_TEAMHELP or
			bs.ltgtype == C.LTG_TEAMACCOMPANY or
			bs.ltgtype == C.LTG_DEFENDKEYAREA or
			bs.ltgtype == C.LTG_GETFLAG or
			bs.ltgtype == C.LTG_RUSHBASE or
			bs.ltgtype == C.LTG_CAMP or
			bs.ltgtype == C.LTG_CAMPORDER or
			bs.ltgtype == C.LTG_PATROL then
		return 0
	end
	if bs.camp_time > G.floattime - 60 + 300 * (1 - camper) then return 0 end
	if Q.random() > camper then
		bs.camp_time = G.floattime
		return 0
	end
	if G.BotAggression(bs) < 50 then return 0 end
	if (bs.inventory[C.INVENTORY_ROCKETLAUNCHER] <= 0 or bs.inventory[C.INVENTORY_ROCKETS] < 10) and
			(bs.inventory[C.INVENTORY_RAILGUN] <= 0 or bs.inventory[C.INVENTORY_SLUGS] < 10) and
			(bs.inventory[C.INVENTORY_BFG10K] <= 0 or bs.inventory[C.INVENTORY_BFGAMMO] < 10) then
		return 0
	end
	local besttraveltime = 99999
	local cs = G.trap_BotGetNextCampSpotGoal(0, goal)
	while cs ~= 0 do
		local traveltime = G.trap_AAS_AreaTravelTimeToGoalArea(bs.areanum, bs.origin, goal.areanum, C.TFL_DEFAULT)
		if traveltime ~= 0 and traveltime < besttraveltime then
			besttraveltime = traveltime
			S.copy_bot_goal_t(bestgoal, goal)
		end
		cs = G.trap_BotGetNextCampSpotGoal(cs, goal)
	end
	if besttraveltime > 150 then return 0 end
	G.BotGoCamp(bs, bestgoal)
	bs.ordered = 0
	return 1
end

function G.BotDontAvoid(bs, itemname)
	local goal = S.bot_goal_t()

	local num = G.trap_BotGetLevelItemGoal(-1, itemname, goal)
	while num >= 0 do
		G.trap_BotRemoveFromAvoidGoals(bs.gs, goal.number)
		num = G.trap_BotGetLevelItemGoal(num, itemname, goal)
	end
end

function G.BotGoForPowerups(bs)
	G.BotDontAvoid(bs, "Quad Damage")
	G.BotDontAvoid(bs, "Regeneration")
	G.BotDontAvoid(bs, "Battle Suit")
	G.BotDontAvoid(bs, "Speed")
	G.BotDontAvoid(bs, "Invisibility")
	bs.ltg_time = 0
end

function G.BotRoamGoal(bs, goal)
	local dir = Q.vec3()
	local bestorg = Q.vec3()
	local belowbestorg = Q.vec3()
	local trace = S.bsp_trace_t()

	for i = 0, 9 do
		Q.VectorCopy(bs.origin, bestorg)
		local rnd = Q.random()
		if rnd > 0.25 then
			if Q.random() < 0.5 then
				bestorg[0] -= 800 * Q.random() + 100
			else
				bestorg[0] += 800 * Q.random() + 100
			end
		end
		if rnd < 0.75 then
			if Q.random() < 0.5 then
				bestorg[1] -= 800 * Q.random() + 100
			else
				bestorg[1] += 800 * Q.random() + 100
			end
		end
		bestorg[2] += 2 * 48 * Q.crandom()
		G.BotAI_Trace(trace, bs.origin, nil, nil, bestorg, bs.entitynum, C.MASK_SOLID)
		Q.VectorSubtract(trace.endpos, bs.origin, dir)
		local len = Q.VectorNormalize(dir)
		if len > 200 then
			Q.VectorScale(dir, len * trace.fraction - 40, dir)
			Q.VectorAdd(bs.origin, dir, bestorg)
			belowbestorg[0] = bestorg[0]
			belowbestorg[1] = bestorg[1]
			belowbestorg[2] = bestorg[2] - 800
			G.BotAI_Trace(trace, bestorg, nil, nil, belowbestorg, bs.entitynum, C.MASK_SOLID)
			if trace.startsolid == 0 then
				trace.endpos[2] += 1
				local pc = G.trap_PointContents(trace.endpos, bs.entitynum)
				if bit32.band(pc, bit32.bor(C.CONTENTS_LAVA, C.CONTENTS_SLIME)) == 0 then
					Q.VectorCopy(bestorg, goal)
					return
				end
			end
		end
	end
	Q.VectorCopy(bestorg, goal)
end

function G.BotAttackMove(bs, tfl)
	local forward = Q.vec3()
	local backward = Q.vec3()
	local sideward = Q.vec3()
	local hordir = Q.vec3()
	local up = Q.vec3()
	up[2] = 1
	local entinfo = S.aas_entityinfo_t()
	local moveresult = S.bot_moveresult_t()
	local goal = S.bot_goal_t()

	local attackentity = bs.enemy
	if bs.attackchase_time > G.floattime then
		goal.entitynum = attackentity
		goal.areanum = bs.lastenemyareanum
		Q.VectorCopy(bs.lastenemyorigin, goal.origin)
		Q.VectorSet(goal.mins, -8, -8, -8)
		Q.VectorSet(goal.maxs, 8, 8, 8)
		G.BotSetupForMovement(bs)
		G.trap_BotMoveToGoal(moveresult, bs.ms, goal, tfl)
		return moveresult
	end
	local attack_skill = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_ATTACK_SKILL, 0, 1)
	local jumper = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_JUMPER, 0, 1)
	local croucher = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_CROUCHER, 0, 1)
	if attack_skill < 0.2 then return moveresult end
	G.BotSetupForMovement(bs)
	G.BotEntityInfo(attackentity, entinfo)
	Q.VectorSubtract(entinfo.origin, bs.origin, forward)
	local dist = Q.VectorNormalize(forward)
	Q.VectorNegate(forward, backward)
	local movetype = C.MOVE_WALK
	if bs.attackcrouch_time < G.floattime - 1 then
		if Q.random() < jumper then
			movetype = C.MOVE_JUMP
		elseif bs.attackcrouch_time < G.floattime - 1 and Q.random() < croucher then
			bs.attackcrouch_time = G.floattime + croucher * 5
		end
	end
	if bs.attackcrouch_time > G.floattime then movetype = C.MOVE_CROUCH end
	if movetype == C.MOVE_JUMP then
		if bs.attackjump_time > G.floattime then
			movetype = C.MOVE_WALK
		else
			bs.attackjump_time = G.floattime + 1
		end
	end
	local attack_dist, attack_range
	if bs.cur_ps.weapon == C.WP_GAUNTLET then
		attack_dist = 0
		attack_range = 0
	else
		attack_dist = IDEAL_ATTACKDIST
		attack_range = 40
	end
	if attack_skill <= 0.4 then
		if dist > attack_dist + attack_range then
			if G.trap_BotMoveInDirection(bs.ms, forward, 400, movetype) ~= 0 then return moveresult end
		end
		if dist < attack_dist - attack_range then
			if G.trap_BotMoveInDirection(bs.ms, backward, 400, movetype) ~= 0 then return moveresult end
		end
		return moveresult
	end
	bs.attackstrafe_time += bs.thinktime
	local strafechange_time = 0.4 + (1 - attack_skill) * 0.2
	if attack_skill > 0.7 then strafechange_time += Q.crandom() * 0.2 end
	if bs.attackstrafe_time > strafechange_time then
		if Q.random() > 0.935 then
			bs.flags = bit32.bxor(bs.flags, C.BFL_STRAFERIGHT)
			bs.attackstrafe_time = 0
		end
	end
	for i = 0, 1 do
		hordir[0] = forward[0]
		hordir[1] = forward[1]
		hordir[2] = 0
		Q.VectorNormalize(hordir)
		Q.CrossProduct(hordir, up, sideward)
		if bit32.band(bs.flags, C.BFL_STRAFERIGHT) ~= 0 then Q.VectorNegate(sideward, sideward) end
		if Q.random() > 0.9 then
			Q.VectorAdd(sideward, backward, sideward)
		else
			if dist > attack_dist + attack_range then
				Q.VectorAdd(sideward, forward, sideward)
			elseif dist < attack_dist - attack_range then
				Q.VectorAdd(sideward, backward, sideward)
			end
		end
		if G.trap_BotMoveInDirection(bs.ms, sideward, 400, movetype) ~= 0 then
			return moveresult
		end
		bs.flags = bit32.bxor(bs.flags, C.BFL_STRAFERIGHT)
		bs.attackstrafe_time = 0
	end
	return moveresult
end

function G.BotSameTeam(bs, entnum)
	if bs.client < 0 or bs.client >= C.MAX_CLIENTS then
		return 0
	end
	if entnum < 0 or entnum >= C.MAX_CLIENTS then
		return 0
	end
	if G.gametype >= C.GT_TEAM and G.g_ffa_gt ~= 1 then
		if G.level.clients[bs.client].sess.sessionTeam == G.level.clients[entnum].sess.sessionTeam then return 1 end
	end
	return 0
end

function G.InFieldOfVision(viewangles, fov, angles)
	for i = 0, 1 do
		local angle = Q.AngleMod(viewangles[i])
		angles[i] = Q.AngleMod(angles[i])
		local diff = angles[i] - angle
		if angles[i] > angle then
			if diff > 180.0 then diff -= 360.0 end
		else
			if diff < -180.0 then diff += 360.0 end
		end
		if diff > 0 then
			if diff > fov * 0.5 then return false end
		else
			if diff < -fov * 0.5 then return false end
		end
	end
	return true
end

function G.BotEntityVisible(viewer, eye, viewangles, fov, ent)
	local trace = S.bsp_trace_t()
	local entinfo = S.aas_entityinfo_t()
	local dir = Q.vec3()
	local entangles = Q.vec3()
	local start = Q.vec3()
	local end_ = Q.vec3()
	local middle = Q.vec3()
	local LWS = bit32.bor(C.CONTENTS_LAVA, C.CONTENTS_SLIME, C.CONTENTS_WATER)

	G.BotEntityInfo(ent, entinfo)
	Q.VectorAdd(entinfo.mins, entinfo.maxs, middle)
	Q.VectorScale(middle, 0.5, middle)
	Q.VectorAdd(entinfo.origin, middle, middle)
	Q.VectorSubtract(middle, eye, dir)
	Q.vectoangles(dir, entangles)
	if not G.InFieldOfVision(viewangles, fov, entangles) then return 0 end
	local pc = G.trap_AAS_PointContents(eye)
	local infog = bit32.band(pc, C.CONTENTS_FOG)
	local inwater = bit32.band(pc, LWS)
	local bestvis = 0
	for i = 0, 2 do
		local contents_mask = bit32.bor(C.CONTENTS_SOLID, C.CONTENTS_PLAYERCLIP)
		local passent = viewer
		local hitent = ent
		Q.VectorCopy(eye, start)
		Q.VectorCopy(middle, end_)
		if bit32.band(G.trap_AAS_PointContents(middle), LWS) ~= 0 then
			contents_mask = bit32.bor(contents_mask, LWS)
		end
		if inwater ~= 0 then
			if bit32.band(contents_mask, LWS) == 0 then
				passent = ent
				hitent = viewer
				Q.VectorCopy(middle, start)
				Q.VectorCopy(eye, end_)
			end
			contents_mask = bit32.bxor(contents_mask, LWS)
		end
		G.BotAI_Trace(trace, start, nil, nil, end_, passent, contents_mask)
		local waterfactor = 1.0
		if bit32.band(trace.contents, LWS) ~= 0 then
			contents_mask = bit32.band(contents_mask, bit32.bnot(LWS))
			G.BotAI_Trace(trace, trace.endpos, nil, nil, end_, passent, contents_mask)
			waterfactor = 0.5
		end
		if trace.fraction >= 1 or trace.ent == hitent then
			local squaredfogdist
			local otherinfog = bit32.band(G.trap_AAS_PointContents(middle), C.CONTENTS_FOG)
			if infog ~= 0 and otherinfog ~= 0 then
				Q.VectorSubtract(trace.endpos, eye, dir)
				squaredfogdist = Q.VectorLengthSquared(dir)
			elseif infog ~= 0 then
				Q.VectorCopy(trace.endpos, start)
				G.BotAI_Trace(trace, start, nil, nil, eye, viewer, C.CONTENTS_FOG)
				Q.VectorSubtract(eye, trace.endpos, dir)
				squaredfogdist = Q.VectorLengthSquared(dir)
			elseif otherinfog ~= 0 then
				Q.VectorCopy(trace.endpos, end_)
				G.BotAI_Trace(trace, eye, nil, nil, end_, viewer, C.CONTENTS_FOG)
				Q.VectorSubtract(end_, trace.endpos, dir)
				squaredfogdist = Q.VectorLengthSquared(dir)
			else
				squaredfogdist = 0
			end
			local vis = 1 / (if (squaredfogdist * 0.001) < 1 then 1 else (squaredfogdist * 0.001))
			vis *= waterfactor
			if vis > bestvis then bestvis = vis end
			if bestvis >= 0.95 then return bestvis end
		end
		if i == 0 then
			middle[2] += entinfo.mins[2]
		elseif i == 1 then
			middle[2] += entinfo.maxs[2] - entinfo.mins[2]
		end
	end
	return bestvis
end

function G.BotFindEnemy(bs, curenemy)
	local entinfo = S.aas_entityinfo_t()
	local curenemyinfo = S.aas_entityinfo_t()
	local dir = Q.vec3()
	local angles = Q.vec3()
	local cursquaredist

	local alertness = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_ALERTNESS, 0, 1)
	local easyfragger = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_EASY_FRAGGER, 0, 1)
	local healthdecrease = if bs.lasthealth > bs.inventory[C.INVENTORY_HEALTH] then 1 else 0
	bs.lasthealth = bs.inventory[C.INVENTORY_HEALTH]
	if curenemy >= 0 then
		G.BotEntityInfo(curenemy, curenemyinfo)
		if G.EntityCarriesFlag(curenemyinfo) then return 0 end
		Q.VectorSubtract(curenemyinfo.origin, bs.origin, dir)
		cursquaredist = Q.VectorLengthSquared(dir)
	else
		cursquaredist = 0
	end
	if G.gametype == C.GT_OBELISK then
		local target = Q.vec3()
		local goal
		local trace = S.bsp_trace_t()

		if G.BotTeam(bs) == C.TEAM_RED then
			goal = G.blueobelisk
		else
			goal = G.redobelisk
		end
		Q.VectorCopy(goal.origin, target)
		target[2] += 1
		G.BotAI_Trace(trace, bs.eye, nil, nil, target, bs.client, C.CONTENTS_SOLID)
		if trace.fraction >= 1 or trace.ent == goal.entitynum then
			if goal.entitynum == bs.enemy then
				return 0
			end
			bs.enemy = goal.entitynum
			bs.enemysight_time = G.floattime
			bs.enemysuicide = 0
			bs.enemydeath_time = 0
			bs.enemyvisible_time = G.floattime
			return 1
		end
	end
	for i = 0, math.min(G.maxclients, C.MAX_CLIENTS) - 1 do
		if i == bs.client then continue end
		if i == curenemy then continue end
		G.BotEntityInfo(i, entinfo)
		if entinfo.valid == 0 then continue end
		if G.EntityIsDead(entinfo) or entinfo.number == bs.entitynum then continue end
		if G.EntityIsInvisible(entinfo) and not G.EntityIsShooting(entinfo) then
			continue
		end
		if bit32.band(G.g_entities[i].flags, C.FL_NOTARGET) ~= 0 then continue end
		if easyfragger < 0.5 and G.EntityIsChatting(entinfo) then continue end
		if G.lastteleport_time > G.floattime - 3 then
			Q.VectorSubtract(entinfo.origin, G.lastteleport_origin, dir)
			if Q.VectorLengthSquared(dir) < Square(70) then continue end
		end
		Q.VectorSubtract(entinfo.origin, bs.origin, dir)
		local squaredist = Q.VectorLengthSquared(dir)
		if not G.EntityCarriesFlag(entinfo) then
			if curenemy >= 0 and squaredist > cursquaredist then continue end
		end
		if squaredist > Square(900.0 + alertness * 4000.0) then continue end
		if G.BotSameTeam(bs, i) ~= 0 then continue end
		local f
		if curenemy < 0 and (healthdecrease ~= 0 or G.EntityIsShooting(entinfo)) then
			f = 360
		else
			f = 90 + 90 - (90 - (if squaredist > Square(810) then Square(810) else squaredist) / (810 * 9))
		end
		local vis = G.BotEntityVisible(bs.entitynum, bs.eye, bs.viewangles, f, i)
		if vis <= 0 then continue end
		if curenemy < 0 and squaredist > Square(100) and healthdecrease == 0 and not G.EntityIsShooting(entinfo) then
			Q.VectorSubtract(bs.origin, entinfo.origin, dir)
			Q.vectoangles(dir, angles)
			if not G.InFieldOfVision(entinfo.angles, 90, angles) then
				G.BotUpdateBattleInventory(bs, i)
				if G.BotWantsToRetreat(bs) ~= 0 then continue end
			end
		end
		bs.enemy = entinfo.number
		if curenemy >= 0 then
			bs.enemysight_time = G.floattime - 2
		else
			bs.enemysight_time = G.floattime
		end
		bs.enemysuicide = 0
		bs.enemydeath_time = 0
		bs.enemyvisible_time = G.floattime
		return 1
	end
	return 0
end

function G.BotTeamFlagCarrierVisible(bs)
	local entinfo = S.aas_entityinfo_t()

	for i = 0, math.min(G.maxclients, C.MAX_CLIENTS) - 1 do
		if i == bs.client then
			continue
		end
		G.BotEntityInfo(i, entinfo)
		if entinfo.valid == 0 then
			continue
		end
		if not G.EntityCarriesFlag(entinfo) then
			continue
		end
		if G.BotSameTeam(bs, i) == 0 then
			continue
		end
		local vis = G.BotEntityVisible(bs.entitynum, bs.eye, bs.viewangles, 360, i)
		if vis <= 0 then
			continue
		end
		return i
	end
	return -1
end

return nil
