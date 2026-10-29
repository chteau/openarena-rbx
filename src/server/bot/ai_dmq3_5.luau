--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/ai_dmq3.c, part 5 of 7).

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
-- Luau port of ai_dmq3.c, part 5 of 7. Flag/cube carrier queries, aiming, attack checks, map scripts, button goals.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local SF = G.FileStatics("ai_dmq3")

function G.BotTeamFlagCarrier(bs)
	local entinfo = S.aas_entityinfo_t()
	for i = 0, G.level.maxclients - 1 do
		if i == bs.client then
			continue
		end
		G.BotEntityInfo(i, entinfo)
		if not entinfo.valid then
			continue
		end
		if not G.EntityCarriesFlag(entinfo) then
			continue
		end
		if not G.BotSameTeam(bs, i) then
			continue
		end
		return i
	end
	return -1
end

function G.BotEnemyFlagCarrierVisible(bs)
	local entinfo = S.aas_entityinfo_t()
	for i = 0, G.level.maxclients - 1 do
		if i == bs.client then
			continue
		end
		G.BotEntityInfo(i, entinfo)
		if not entinfo.valid then
			continue
		end
		if not G.EntityCarriesFlag(entinfo) then
			continue
		end
		if G.BotSameTeam(bs, i) then
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

-- returns the teammates and enemies counts (C out-parameters)
function G.BotVisibleTeamMatesAndEnemies(bs, range)
	local teammates = 0
	local enemies = 0
	local entinfo = S.aas_entityinfo_t()
	local dir = Q.vec3()
	for i = 0, G.level.maxclients - 1 do
		if i == bs.client then
			continue
		end
		G.BotEntityInfo(i, entinfo)
		if not entinfo.valid then
			continue
		end
		if not G.EntityCarriesFlag(entinfo) then
			continue
		end
		Q.VectorSubtract(entinfo.origin, bs.origin, dir)
		if Q.DotProduct(dir, dir) > range * range then
			continue
		end
		local vis = G.BotEntityVisible(bs.entitynum, bs.eye, bs.viewangles, 360, i)
		if vis <= 0 then
			continue
		end
		if G.BotSameTeam(bs, i) then
			teammates += 1
		else
			enemies += 1
		end
	end
	return teammates, enemies
end

function G.BotTeamCubeCarrierVisible(bs)
	local entinfo = S.aas_entityinfo_t()
	for i = 0, G.level.maxclients - 1 do
		if i == bs.client then
			continue
		end
		G.BotEntityInfo(i, entinfo)
		if not entinfo.valid then
			continue
		end
		if not G.EntityCarriesCubes(entinfo) then
			continue
		end
		if not G.BotSameTeam(bs, i) then
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

function G.BotEnemyCubeCarrierVisible(bs)
	local entinfo = S.aas_entityinfo_t()
	for i = 0, G.level.maxclients - 1 do
		if i == bs.client then
			continue
		end
		G.BotEntityInfo(i, entinfo)
		if not entinfo.valid then
			continue
		end
		if not G.EntityCarriesCubes(entinfo) then
			continue
		end
		if G.BotSameTeam(bs, i) then
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

function G.BotAimAtEnemy(bs)
	local dist, f, aim_skill, aim_accuracy, speed, reactiontime
	local dir = Q.vec3()
	local bestorigin = Q.vec3()
	local end_ = Q.vec3()
	local start = Q.vec3()
	local groundtarget = Q.vec3()
	local cmdmove = Q.vec3()
	local enemyvelocity = Q.vec3()
	local mins = { [0] = -4, -4, -4 }
	local maxs = { [0] = 4, 4, 4 }
	local wi = S.weaponinfo_t()
	local entinfo = S.aas_entityinfo_t()
	local goal = S.bot_goal_t()
	local trace = S.bsp_trace_t()
	local target = Q.vec3()

	if bs.enemy < 0 then
		return
	end
	G.BotEntityInfo(bs.enemy, entinfo)
	if bs.enemy >= C.MAX_CLIENTS then
		Q.VectorCopy(entinfo.origin, target)
		if bs.enemy == G.redobelisk.entitynum or bs.enemy == G.blueobelisk.entitynum then
			target[2] += 32
		end
		Q.VectorSubtract(target, bs.eye, dir)
		Q.vectoangles(dir, bs.ideal_viewangles)
		Q.VectorCopy(target, bs.aimtarget)
		return
	end
	aim_skill = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_AIM_SKILL, 0, 1)
	aim_accuracy = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_AIM_ACCURACY, 0, 1)
	if aim_skill > 0.95 then
		reactiontime = 0.5 * G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_REACTIONTIME, 0, 1)
		if bs.enemysight_time > G.floattime - reactiontime then
			return
		end
		if bs.teleport_time > G.floattime - reactiontime then
			return
		end
	end

	G.trap_BotGetWeaponInfo(bs.ws, bs.weaponnum, wi)
	if wi.number == C.WP_MACHINEGUN then
		aim_accuracy = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_AIM_ACCURACY_MACHINEGUN, 0, 1)
	elseif wi.number == C.WP_SHOTGUN then
		aim_accuracy = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_AIM_ACCURACY_SHOTGUN, 0, 1)
	elseif wi.number == C.WP_GRENADE_LAUNCHER then
		aim_accuracy = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_AIM_ACCURACY_GRENADELAUNCHER, 0, 1)
		aim_skill = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_AIM_SKILL_GRENADELAUNCHER, 0, 1)
	elseif wi.number == C.WP_ROCKET_LAUNCHER then
		aim_accuracy = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_AIM_ACCURACY_ROCKETLAUNCHER, 0, 1)
		aim_skill = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_AIM_SKILL_ROCKETLAUNCHER, 0, 1)
	elseif wi.number == C.WP_LIGHTNING then
		aim_accuracy = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_AIM_ACCURACY_LIGHTNING, 0, 1)
	elseif wi.number == C.WP_RAILGUN then
		aim_accuracy = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_AIM_ACCURACY_RAILGUN, 0, 1)
	elseif wi.number == C.WP_PLASMAGUN then
		aim_accuracy = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_AIM_ACCURACY_PLASMAGUN, 0, 1)
		aim_skill = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_AIM_SKILL_PLASMAGUN, 0, 1)
	elseif wi.number == C.WP_BFG then
		aim_accuracy = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_AIM_ACCURACY_BFG10K, 0, 1)
		aim_skill = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_AIM_SKILL_BFG10K, 0, 1)
	end
	if aim_accuracy <= 0 then
		aim_accuracy = 0.0001
	end
	G.BotEntityInfo(bs.enemy, entinfo)
	if G.EntityIsInvisible(entinfo) then
		if Q.random() > 0.1 then
			aim_accuracy *= 0.4
		end
	end
	Q.VectorSubtract(entinfo.origin, entinfo.lastvisorigin, enemyvelocity)
	Q.VectorScale(enemyvelocity, 1 / entinfo.update_time, enemyvelocity)
	if bs.enemyposition_time < G.floattime then
		bs.enemyposition_time = G.floattime + 0.5
		Q.VectorCopy(enemyvelocity, bs.enemyvelocity)
		Q.VectorCopy(entinfo.origin, bs.enemyorigin)
	end
	if aim_skill < 0.9 then
		Q.VectorSubtract(entinfo.origin, bs.enemyorigin, dir)
		if Q.DotProduct(dir, dir) > 48 * 48 then
			if Q.DotProduct(bs.enemyvelocity, enemyvelocity) < 0 then
				aim_accuracy *= 0.7
			end
		end
	end
	local enemyvisible = Q.trunc(G.BotEntityVisible(bs.entitynum, bs.eye, bs.viewangles, 360, bs.enemy))
	if enemyvisible ~= 0 then
		Q.VectorCopy(entinfo.origin, bestorigin)
		bestorigin[2] += 8
		Q.VectorCopy(bs.origin, start)
		start[2] += bs.cur_ps.viewheight
		start[2] += wi.offset[2]
		G.BotAI_Trace(trace, start, mins, maxs, bestorigin, bs.entitynum, C.MASK_SHOT)
		if trace.fraction <= 1 and trace.ent ~= entinfo.number then
			bestorigin[2] += 16
		end
		if wi.speed ~= 0 then
			Q.VectorSubtract(bestorigin, bs.origin, dir)
			dist = Q.VectorLength(dir)
			Q.VectorSubtract(entinfo.origin, bs.enemyorigin, dir)
			if not (dist > 100 and Q.DotProduct(dir, dir) < 32 * 32) then
				if aim_skill > 0.8 and bs.cur_ps.weaponstate == C.WEAPON_READY then
					local move = S.aas_clientmove_t()
					local origin = Q.vec3()

					Q.VectorSubtract(entinfo.origin, bs.origin, dir)
					dist = Q.VectorLength(dir)
					Q.VectorSubtract(entinfo.origin, entinfo.lastvisorigin, dir)
					Q.VectorScale(dir, 1 / entinfo.update_time, dir)
					Q.VectorCopy(entinfo.origin, origin)
					origin[2] += 1
					Q.VectorClear(cmdmove)
					G.trap_AAS_PredictClientMovement(move, bs.enemy, origin,
						C.PRESENCE_CROUCH, false,
						dir, cmdmove, 0,
						Q.trunc(dist * 10 / wi.speed), 0.1, 0, 0, false)
					Q.VectorCopy(move.endpos, bestorigin)
				elseif aim_skill > 0.4 then
					Q.VectorSubtract(entinfo.origin, bs.origin, dir)
					dist = Q.VectorLength(dir)
					Q.VectorSubtract(entinfo.origin, entinfo.lastvisorigin, dir)
					dir[2] = 0
					speed = Q.VectorNormalize(dir) / entinfo.update_time
					Q.VectorMA(entinfo.origin, (dist / wi.speed) * speed, dir, bestorigin)
				end
			end
		end
		if aim_skill > 0.6 and bit32.band(wi.proj.damagetype, C.DAMAGETYPE_RADIAL) ~= 0 then
			if entinfo.origin[2] < bs.origin[2] + 16 then
				Q.VectorCopy(entinfo.origin, end_)
				end_[2] -= 64
				G.BotAI_Trace(trace, entinfo.origin, nil, nil, end_, entinfo.number, C.MASK_SHOT)
				Q.VectorCopy(bestorigin, groundtarget)
				if trace.startsolid then
					groundtarget[2] = entinfo.origin[2] - 16
				else
					groundtarget[2] = trace.endpos[2] - 8
				end
				G.BotAI_Trace(trace, start, nil, nil, groundtarget, bs.entitynum, C.MASK_SHOT)
				if math.abs(trace.endpos[2] - groundtarget[2]) < 50 then
					Q.VectorSubtract(trace.endpos, groundtarget, dir)
					if Q.DotProduct(dir, dir) < 60 * 60 then
						Q.VectorSubtract(trace.endpos, start, dir)
						if Q.DotProduct(dir, dir) > 100 * 100 then
							trace.endpos[2] += 1
							G.BotAI_Trace(trace, trace.endpos, nil, nil, entinfo.origin, entinfo.number, C.MASK_SHOT)
							if trace.fraction >= 1 then
								Q.VectorCopy(groundtarget, bestorigin)
							end
						end
					end
				end
			end
		end
		bestorigin[0] += 20 * Q.crandom() * (1 - aim_accuracy)
		bestorigin[1] += 20 * Q.crandom() * (1 - aim_accuracy)
		bestorigin[2] += 10 * Q.crandom() * (1 - aim_accuracy)
	else
		Q.VectorCopy(bs.lastenemyorigin, bestorigin)
		bestorigin[2] += 8
		if aim_skill > 0.5 then
			if wi.number == C.WP_BFG or wi.number == C.WP_ROCKET_LAUNCHER or wi.number == C.WP_GRENADE_LAUNCHER then
				goal.entitynum = bs.client
				goal.areanum = bs.areanum
				Q.VectorCopy(bs.eye, goal.origin)
				Q.VectorSet(goal.mins, -8, -8, -8)
				Q.VectorSet(goal.maxs, 8, 8, 8)
				if G.trap_BotPredictVisiblePosition(bs.lastenemyorigin, bs.lastenemyareanum, goal, C.TFL_DEFAULT, target) ~= 0 then
					Q.VectorSubtract(target, bs.eye, dir)
					if Q.DotProduct(dir, dir) > 80 * 80 then
						Q.VectorCopy(target, bestorigin)
						bestorigin[2] -= 20
					end
				end
				aim_accuracy = 1
			end
		end
	end
	if enemyvisible ~= 0 then
		G.BotAI_Trace(trace, bs.eye, nil, nil, bestorigin, bs.entitynum, C.MASK_SHOT)
		Q.VectorCopy(trace.endpos, bs.aimtarget)
	else
		Q.VectorCopy(bestorigin, bs.aimtarget)
	end
	Q.VectorSubtract(bestorigin, bs.eye, dir)
	if wi.number == C.WP_MACHINEGUN or wi.number == C.WP_SHOTGUN or wi.number == C.WP_LIGHTNING or wi.number == C.WP_RAILGUN then
		dist = Q.VectorLength(dir)
		if dist > 150 then
			dist = 150
		end
		f = 0.6 + dist / 150 * 0.4
		aim_accuracy *= f
	end
	if aim_accuracy < 0.8 then
		Q.VectorNormalize(dir)
		for i = 0, 2 do
			dir[i] += 0.3 * Q.crandom() * (1 - aim_accuracy)
		end
	end
	Q.vectoangles(dir, bs.ideal_viewangles)
	bs.ideal_viewangles[C.PITCH] += 6 * wi.vspread * Q.crandom() * (1 - aim_accuracy)
	bs.ideal_viewangles[C.PITCH] = Q.AngleMod(bs.ideal_viewangles[C.PITCH])
	bs.ideal_viewangles[C.YAW] += 6 * wi.hspread * Q.crandom() * (1 - aim_accuracy)
	bs.ideal_viewangles[C.YAW] = Q.AngleMod(bs.ideal_viewangles[C.YAW])
	if G.bot_challenge.integer ~= 0 then
		if aim_accuracy > 0.9 and bs.enemysight_time < G.floattime - 1 then
			if bs.ideal_viewangles[C.PITCH] > 180 then
				bs.ideal_viewangles[C.PITCH] -= 360
			end
			Q.VectorCopy(bs.ideal_viewangles, bs.viewangles)
			G.trap_EA_View(bs.client, bs.viewangles)
		end
	end
end

function G.BotCheckAttack(bs)
	local points, reactiontime, fov, firethrottle
	local bsptrace = S.bsp_trace_t()
	local forward = Q.vec3()
	local right = Q.vec3()
	local start = Q.vec3()
	local end_ = Q.vec3()
	local dir = Q.vec3()
	local angles = Q.vec3()
	local wi = S.weaponinfo_t()
	local trace = S.bsp_trace_t()
	local entinfo = S.aas_entityinfo_t()
	local mins = { [0] = -8, -8, -8 }
	local maxs = { [0] = 8, 8, 8 }

	local attackentity = bs.enemy
	G.BotEntityInfo(attackentity, entinfo)
	if attackentity >= C.MAX_CLIENTS then
		if entinfo.number == G.redobelisk.entitynum or entinfo.number == G.blueobelisk.entitynum then
			local act = G.g_entities[entinfo.number].activator
			if act ~= nil and act.s.frame == 2 then
				return
			end
		end
	end
	reactiontime = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_REACTIONTIME, 0, 1)
	if bs.enemysight_time > G.floattime - reactiontime then
		return
	end
	if bs.teleport_time > G.floattime - reactiontime then
		return
	end
	if bs.weaponchange_time > G.floattime - 0.1 then
		return
	end
	if bs.firethrottlewait_time > G.floattime then
		return
	end
	firethrottle = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_FIRETHROTTLE, 0, 1)
	if bs.firethrottleshoot_time < G.floattime then
		if Q.random() > firethrottle then
			bs.firethrottlewait_time = G.floattime + firethrottle
			bs.firethrottleshoot_time = 0
		else
			bs.firethrottleshoot_time = G.floattime + 1 - firethrottle
			bs.firethrottlewait_time = 0
		end
	end
	Q.VectorSubtract(bs.aimtarget, bs.eye, dir)
	if bs.weaponnum == C.WP_GAUNTLET then
		if Q.DotProduct(dir, dir) > 60 * 60 then
			return
		end
	end
	if Q.DotProduct(dir, dir) < 100 * 100 then
		fov = 120
	else
		fov = 50
	end
	Q.vectoangles(dir, angles)
	if not G.InFieldOfVision(bs.viewangles, fov, angles) then
		return
	end
	G.BotAI_Trace(bsptrace, bs.eye, nil, nil, bs.aimtarget, bs.client, bit32.bor(C.CONTENTS_SOLID, C.CONTENTS_PLAYERCLIP))
	if bsptrace.fraction < 1 and bsptrace.ent ~= attackentity then
		return
	end

	G.trap_BotGetWeaponInfo(bs.ws, bs.weaponnum, wi)
	Q.VectorCopy(bs.origin, start)
	start[2] += bs.cur_ps.viewheight
	Q.AngleVectors(bs.viewangles, forward, right, nil)
	start[0] += forward[0] * wi.offset[0] + right[0] * wi.offset[1]
	start[1] += forward[1] * wi.offset[0] + right[1] * wi.offset[1]
	start[2] += forward[2] * wi.offset[0] + right[2] * wi.offset[1] + wi.offset[2]
	Q.VectorMA(start, 1000, forward, end_)
	Q.VectorMA(start, -12, forward, start)
	G.BotAI_Trace(trace, start, mins, maxs, end_, bs.entitynum, C.MASK_SHOT)
	if trace.ent >= 0 and trace.ent < C.MAX_CLIENTS then
		if trace.ent ~= attackentity then
			if G.BotSameTeam(bs, trace.ent) ~= 0 then
				return
			end
		end
	end
	if trace.ent ~= attackentity or attackentity >= C.MAX_CLIENTS then
		if bit32.band(wi.proj.damagetype, C.DAMAGETYPE_RADIAL) ~= 0 then
			if trace.fraction * 1000 < wi.proj.radius then
				points = (wi.proj.damage - 0.5 * trace.fraction * 1000) * 0.5
				if points > 0 then
					return
				end
			end
		end
	end
	if bit32.band(wi.flags, C.WFL_FIRERELEASED) ~= 0 then
		if bit32.band(bs.flags, C.BFL_ATTACKED) ~= 0 then
			G.trap_EA_Attack(bs.client)
		end
	else
		G.trap_EA_Attack(bs.client)
	end
	bs.flags = bit32.bxor(bs.flags, C.BFL_ATTACKED)
end

function G.BotMapScripts(bs)
	local entinfo = S.aas_entityinfo_t()
	local dir = Q.vec3()

	local info = G.trap_GetServerinfo()
	local mapname = QS.Q_strncpyz(QS.Info_ValueForKey(info, "mapname"), 128)

	if QS.Q_strequal(mapname, "q3tourney6") or QS.Q_strequal(mapname, "q3tourney6_ctf") or QS.Q_strequal(mapname, "mpq3tourney6") then
		local mins = { [0] = 694, 200, 480 }
		local maxs = { [0] = 968, 472, 680 }
		local buttonorg = { [0] = 304, 352, 920 }
		bs.tfl = bit32.band(bs.tfl, bit32.bnot(C.TFL_FUNCBOB))
		if QS.Q_strequal(mapname, "mpq3tourney6") then
			mins[2] += 64
			maxs[2] += 64
		end
		if bs.origin[0] > mins[0] and bs.origin[0] < maxs[0] then
			if bs.origin[1] > mins[1] and bs.origin[1] < maxs[1] then
				if bs.origin[2] > mins[2] and bs.origin[2] < maxs[2] then
					return
				end
			end
		end
		local shootbutton = false
		for i = 0, G.level.maxclients - 1 do
			if i == bs.client then
				continue
			end
			G.BotEntityInfo(i, entinfo)
			if not entinfo.valid then
				continue
			end
			if G.EntityIsDead(entinfo) or entinfo.number == bs.entitynum then
				continue
			end
			if entinfo.origin[0] > mins[0] and entinfo.origin[0] < maxs[0] then
				if entinfo.origin[1] > mins[1] and entinfo.origin[1] < maxs[1] then
					if entinfo.origin[2] > mins[2] and entinfo.origin[2] < maxs[2] then
						if G.BotSameTeam(bs, i) ~= 0 then
							shootbutton = false
							break
						elseif bs.enemy == i then
							shootbutton = true
						end
					end
				end
			end
		end
		if shootbutton then
			bs.flags = bit32.bor(bs.flags, C.BFL_IDEALVIEWSET)
			Q.VectorSubtract(buttonorg, bs.eye, dir)
			Q.vectoangles(dir, bs.ideal_viewangles)
			local aim_accuracy = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_AIM_ACCURACY, 0, 1)
			bs.ideal_viewangles[C.PITCH] += 8 * Q.crandom() * (1 - aim_accuracy)
			bs.ideal_viewangles[C.PITCH] = Q.AngleMod(bs.ideal_viewangles[C.PITCH])
			bs.ideal_viewangles[C.YAW] += 8 * Q.crandom() * (1 - aim_accuracy)
			bs.ideal_viewangles[C.YAW] = Q.AngleMod(bs.ideal_viewangles[C.YAW])
			if G.InFieldOfVision(bs.viewangles, 20, bs.ideal_viewangles) then
				G.trap_EA_Attack(bs.client)
			end
		end
	end
end

-- bk001205 - made these static
SF.VEC_UP = { [0] = 0, -1, 0 }
SF.MOVEDIR_UP = { [0] = 0, 0, 1 }
SF.VEC_DOWN = { [0] = 0, -2, 0 }
SF.MOVEDIR_DOWN = { [0] = 0, 0, -1 }

function G.BotSetMovedir(angles, movedir)
	if Q.VectorCompare(angles, SF.VEC_UP) then
		Q.VectorCopy(SF.MOVEDIR_UP, movedir)
	elseif Q.VectorCompare(angles, SF.VEC_DOWN) then
		Q.VectorCopy(SF.MOVEDIR_DOWN, movedir)
	else
		Q.AngleVectors(angles, movedir, nil, nil)
	end
end

function G.BotModelMinsMaxs(modelindex, eType, contents, mins, maxs)
	for i = 0, G.level.num_entities - 1 do
		local ent = G.g_entities[i]
		if not ent.inuse then
			continue
		end
		if eType ~= 0 and ent.s.eType ~= eType then
			continue
		end
		if contents ~= 0 and ent.r.contents ~= contents then
			continue
		end
		if ent.s.modelindex == modelindex then
			if mins ~= nil then
				Q.VectorAdd(ent.r.currentOrigin, ent.r.mins, mins)
			end
			if maxs ~= nil then
				Q.VectorAdd(ent.r.currentOrigin, ent.r.maxs, maxs)
			end
			return i
		end
	end
	if mins ~= nil then
		Q.VectorClear(mins)
	end
	if maxs ~= nil then
		Q.VectorClear(maxs)
	end
	return 0
end

function G.BotFuncButtonActivateGoal(bs, bspent, activategoal)
	local areas = {}
	local points = {}
	for k = 0, 9 do
		areas[k] = 0
		points[k] = Q.vec3()
	end
	local size = Q.vec3()
	local start = Q.vec3()
	local end_ = Q.vec3()
	local mins = Q.vec3()
	local maxs = Q.vec3()
	local angles = Q.vec3()
	local movedir = Q.vec3()
	local origin = Q.vec3()
	local goalorigin = Q.vec3()
	local bboxmins = Q.vec3()
	local bboxmaxs = Q.vec3()
	local extramins = { [0] = 1, 1, 1 }
	local extramaxs = { [0] = -1, -1, -1 }
	local bsptrace = S.bsp_trace_t()
	local ok, lip, angle, health, dist, numareas, i

	activategoal.shoot = 0
	Q.VectorClear(activategoal.target)
	local model
	ok, model = G.trap_AAS_ValueForBSPEpairKey(bspent, "model", 128)
	if model == "" then
		return 0
	end
	local modelindex = QS.atoi(string.sub(model, 2))
	if modelindex == 0 then
		return 0
	end
	local entitynum = G.BotModelMinsMaxs(modelindex, C.ET_MOVER, 0, mins, maxs)
	ok, lip = G.trap_AAS_FloatForBSPEpairKey(bspent, "lip")
	if lip == 0 then
		lip = 4
	end
	ok, angle = G.trap_AAS_FloatForBSPEpairKey(bspent, "angle")
	Q.VectorSet(angles, 0, angle, 0)
	G.BotSetMovedir(angles, movedir)
	Q.VectorSubtract(maxs, mins, size)
	Q.VectorAdd(mins, maxs, origin)
	Q.VectorScale(origin, 0.5, origin)
	dist = math.abs(movedir[0]) * size[0] + math.abs(movedir[1]) * size[1] + math.abs(movedir[2]) * size[2]
	dist *= 0.5
	ok, health = G.trap_AAS_FloatForBSPEpairKey(bspent, "health")
	if health ~= 0 then
		Q.VectorMA(origin, -dist, movedir, goalorigin)
		Q.VectorCopy(goalorigin, activategoal.target)
		activategoal.shoot = 1
		G.BotAI_Trace(bsptrace, bs.eye, nil, nil, goalorigin, bs.entitynum, C.MASK_SHOT)
		if bsptrace.fraction >= 1.0 or bsptrace.ent == entitynum then
			activategoal.goal.entitynum = entitynum
			activategoal.goal.number = 0
			activategoal.goal.flags = 0
			Q.VectorCopy(bs.origin, activategoal.goal.origin)
			activategoal.goal.areanum = bs.areanum
			Q.VectorSet(activategoal.goal.mins, -8, -8, -8)
			Q.VectorSet(activategoal.goal.maxs, 8, 8, 8)
			return 1
		else
			G.trap_AAS_PresenceTypeBoundingBox(C.PRESENCE_CROUCH, bboxmins, bboxmaxs)
			for j = 0, 2 do
				if movedir[j] < 0 then
					dist += math.abs(movedir[j]) * math.abs(bboxmaxs[j])
				else
					dist += math.abs(movedir[j]) * math.abs(bboxmins[j])
				end
			end
			Q.VectorMA(origin, -dist, movedir, goalorigin)
			Q.VectorCopy(goalorigin, start)
			start[2] += 24
			Q.VectorCopy(start, end_)
			end_[2] -= 512
			numareas = G.trap_AAS_TraceAreas(start, end_, areas, points, 10)
			i = numareas - 1
			while i >= 0 do
				if G.trap_AAS_AreaReachability(areas[i]) ~= 0 then
					break
				end
				i -= 1
			end
			if i >= 0 then
				Q.VectorCopy(points[i], activategoal.goal.origin)
				activategoal.goal.areanum = areas[i]
				Q.VectorSet(activategoal.goal.mins, 8, 8, 8)
				Q.VectorSet(activategoal.goal.maxs, -8, -8, -8)
				for j = 0, 2 do
					if movedir[j] < 0 then
						activategoal.goal.maxs[j] += math.abs(movedir[j]) * math.abs(extramaxs[j])
					else
						activategoal.goal.mins[j] += math.abs(movedir[j]) * math.abs(extramins[j])
					end
				end
				activategoal.goal.entitynum = entitynum
				activategoal.goal.number = 0
				activategoal.goal.flags = 0
				return 1
			end
		end
		return 0
	else
		G.trap_AAS_PresenceTypeBoundingBox(C.PRESENCE_CROUCH, bboxmins, bboxmaxs)
		for j = 0, 2 do
			if movedir[j] < 0 then
				dist += math.abs(movedir[j]) * math.abs(bboxmaxs[j])
			else
				dist += math.abs(movedir[j]) * math.abs(bboxmins[j])
			end
		end
		Q.VectorMA(origin, -dist, movedir, goalorigin)
		Q.VectorCopy(goalorigin, start)
		start[2] += 24
		Q.VectorCopy(start, end_)
		end_[2] -= 100
		numareas = G.trap_AAS_TraceAreas(start, end_, areas, nil, 10)
		i = 0
		while i < numareas do
			if G.trap_AAS_AreaReachability(areas[i]) ~= 0 then
				break
			end
			i += 1
		end
		if i < numareas then
			Q.VectorCopy(origin, activategoal.goal.origin)
			activategoal.goal.areanum = areas[i]
			Q.VectorSubtract(mins, origin, activategoal.goal.mins)
			Q.VectorSubtract(maxs, origin, activategoal.goal.maxs)
			for j = 0, 2 do
				if movedir[j] < 0 then
					activategoal.goal.maxs[j] += math.abs(movedir[j]) * math.abs(extramaxs[j])
				else
					activategoal.goal.mins[j] += math.abs(movedir[j]) * math.abs(extramins[j])
				end
			end
			activategoal.goal.entitynum = entitynum
			activategoal.goal.number = 0
			activategoal.goal.flags = 0
			return 1
		end
	end
	return 0
end

return nil
