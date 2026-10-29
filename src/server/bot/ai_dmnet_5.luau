--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/ai_dmnet.c, part 5 of 5).

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
-- Luau port of OpenArena 0.8.8's ai_dmnet.c (gamecode 9e0f0c0), part 5 of 5. Battle chase, retreat and NBG AI nodes.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

function G.AIEnter_Battle_Chase(bs, s)
	G.BotRecordNodeSwitch(bs, "battle chase", "", s)
	bs.chase_time = G.floattime
	bs.ainode = G.AINode_Battle_Chase
end

function G.AINode_Battle_Chase(bs)
	local goal = S.bot_goal_t()
	local target = Q.vec3()
	local dir = Q.vec3()
	local moveresult = S.bot_moveresult_t()
	local range

	if G.BotIsObserver(bs) then
		G.AIEnter_Observer(bs, "battle chase: observer")
		return 0
	end
	--if in the intermission
	if G.BotIntermission(bs) then
		G.AIEnter_Intermission(bs, "battle chase: intermission")
		return 0
	end
	--respawn if dead
	if G.BotIsDead(bs) then
		G.AIEnter_Respawn(bs, "battle chase: bot dead")
		return 0
	end
	--if no enemy
	if bs.enemy < 0 then
		G.AIEnter_Seek_LTG(bs, "battle chase: no enemy")
		return 0
	end
	--if the enemy is visible
	if G.BotEntityVisible(bs.entitynum, bs.eye, bs.viewangles, 360, bs.enemy) ~= 0 then
		G.AIEnter_Battle_Fight(bs, "battle chase")
		return 0
	end
	--if there is another enemy
	if G.BotFindEnemy(bs, -1) ~= 0 then
		G.AIEnter_Battle_Fight(bs, "battle chase: better enemy")
		return 0
	end
	--there is no last enemy area
	if bs.lastenemyareanum == 0 then
		G.AIEnter_Seek_LTG(bs, "battle chase: no enemy area")
		return 0
	end
	--
	bs.tfl = C.TFL_DEFAULT
	if G.bot_grapple.integer ~= 0 then bs.tfl = bit32.bor(bs.tfl, C.TFL_GRAPPLEHOOK) end
	--if in lava or slime the bot should be able to get out
	if G.BotInLavaOrSlime(bs) then bs.tfl = bit32.bor(bs.tfl, C.TFL_LAVA, C.TFL_SLIME) end
	--
	if G.BotCanAndWantsToRocketJump(bs) ~= 0 then
		bs.tfl = bit32.bor(bs.tfl, C.TFL_ROCKETJUMP)
	end
	--map specific code
	G.BotMapScripts(bs)
	--create the chase goal
	goal.entitynum = bs.enemy
	goal.areanum = bs.lastenemyareanum
	Q.VectorCopy(bs.lastenemyorigin, goal.origin)
	Q.VectorSet(goal.mins, -8, -8, -8)
	Q.VectorSet(goal.maxs, 8, 8, 8)
	--if the last seen enemy spot is reached the enemy could not be found
	if G.trap_BotTouchingGoal(bs.origin, goal) ~= 0 then bs.chase_time = 0 end
	--if there's no chase time left
	if bs.chase_time == 0 or bs.chase_time < G.floattime - 10 then
		G.AIEnter_Seek_LTG(bs, "battle chase: time out")
		return 0
	end
	--check for nearby goals periodicly
	if bs.check_time < G.floattime then
		bs.check_time = G.floattime + 1
		range = 150
		--
		if G.BotNearbyGoal(bs, bs.tfl, goal, range) ~= 0 then
			--the bot gets 5 seconds to pick up the nearby goal item
			bs.nbg_time = G.floattime + 0.1 * range + 1
			G.trap_BotResetLastAvoidReach(bs.ms)
			G.AIEnter_Battle_NBG(bs, "battle chase: nbg")
			return 0
		end
	end
	--
	G.BotUpdateBattleInventory(bs, bs.enemy)
	--initialize the movement state
	G.BotSetupForMovement(bs)
	--move towards the goal
	G.trap_BotMoveToGoal(moveresult, bs.ms, goal, bs.tfl)
	--if the movement failed
	if moveresult.failure ~= 0 then
		--reset the avoid reach, otherwise bot is stuck in current area
		G.trap_BotResetAvoidReach(bs.ms)
		bs.ltg_time = 0
	end
	--
	G.BotAIBlocked(bs, moveresult, 0)
	--
	if bit32.band(moveresult.flags, bit32.bor(C.MOVERESULT_MOVEMENTVIEWSET, C.MOVERESULT_MOVEMENTVIEW, C.MOVERESULT_SWIMVIEW)) ~= 0 then
		Q.VectorCopy(moveresult.ideal_viewangles, bs.ideal_viewangles)
	elseif bit32.band(bs.flags, C.BFL_IDEALVIEWSET) == 0 then
		if bs.chase_time > G.floattime - 2 then
			G.BotAimAtEnemy(bs)
		else
			if G.trap_BotMovementViewTarget(bs.ms, goal, bs.tfl, 300, target) ~= 0 then
				Q.VectorSubtract(target, bs.origin, dir)
				Q.vectoangles(dir, bs.ideal_viewangles)
			else
				Q.vectoangles(moveresult.movedir, bs.ideal_viewangles)
			end
		end
		bs.ideal_viewangles[2] = bs.ideal_viewangles[2] * 0.5
	end
	--if the weapon is used for the bot movement
	if bit32.band(moveresult.flags, C.MOVERESULT_MOVEMENTWEAPON) ~= 0 then bs.weaponnum = moveresult.weapon end
	--if the bot is in the area the enemy was last seen in
	if bs.areanum == bs.lastenemyareanum then bs.chase_time = 0 end
	--if the bot wants to retreat (the bot could have been damage during the chase)
	if G.BotWantsToRetreat(bs) ~= 0 then
		G.AIEnter_Battle_Retreat(bs, "battle chase: wants to retreat")
		return 1
	end
	return 1
end

function G.AIEnter_Battle_Retreat(bs, s)
	G.BotRecordNodeSwitch(bs, "battle retreat", "", s)
	bs.ainode = G.AINode_Battle_Retreat
end

function G.AINode_Battle_Retreat(bs)
	local goal = S.bot_goal_t()
	local entinfo = S.aas_entityinfo_t()
	local moveresult = S.bot_moveresult_t()
	local target = Q.vec3()
	local dir = Q.vec3()
	local attack_skill, range
	local areanum

	if G.BotIsObserver(bs) then
		G.AIEnter_Observer(bs, "battle retreat: observer")
		return 0
	end
	--if in the intermission
	if G.BotIntermission(bs) then
		G.AIEnter_Intermission(bs, "battle retreat: intermission")
		return 0
	end
	--respawn if dead
	if G.BotIsDead(bs) then
		G.AIEnter_Respawn(bs, "battle retreat: bot dead")
		return 0
	end
	--if no enemy
	if bs.enemy < 0 then
		G.AIEnter_Seek_LTG(bs, "battle retreat: no enemy")
		return 0
	end
	--
	G.BotEntityInfo(bs.enemy, entinfo)
	if G.EntityIsDead(entinfo) then
		G.AIEnter_Seek_LTG(bs, "battle retreat: enemy dead")
		return 0
	end
	--if there is another better enemy
	G.BotFindEnemy(bs, bs.enemy)
	--
	bs.tfl = C.TFL_DEFAULT
	if G.bot_grapple.integer ~= 0 then bs.tfl = bit32.bor(bs.tfl, C.TFL_GRAPPLEHOOK) end
	--if in lava or slime the bot should be able to get out
	if G.BotInLavaOrSlime(bs) then bs.tfl = bit32.bor(bs.tfl, C.TFL_LAVA, C.TFL_SLIME) end
	--map specific code
	G.BotMapScripts(bs)
	--update the attack inventory values
	G.BotUpdateBattleInventory(bs, bs.enemy)
	--if the bot doesn't want to retreat anymore... probably picked up some nice items
	if G.BotWantsToChase(bs) ~= 0 then
		--empty the goal stack, when chasing, only the enemy is the goal
		G.trap_BotEmptyGoalStack(bs.gs)
		--go chase the enemy
		G.AIEnter_Battle_Chase(bs, "battle retreat: wants to chase")
		return 0
	end
	--update the last time the enemy was visible
	if G.BotEntityVisible(bs.entitynum, bs.eye, bs.viewangles, 360, bs.enemy) ~= 0 then
		bs.enemyvisible_time = G.floattime
		Q.VectorCopy(entinfo.origin, target)
		-- if not a player enemy
		if bs.enemy >= C.MAX_CLIENTS then
			-- if attacking an obelisk
			if bs.enemy == G.redobelisk.entitynum or
				bs.enemy == G.blueobelisk.entitynum then
				target[2] = target[2] + 16
			end
		end
		--update the reachability area and origin if possible
		areanum = G.BotPointAreaNum(target)
		if areanum ~= 0 and G.trap_AAS_AreaReachability(areanum) ~= 0 then
			Q.VectorCopy(target, bs.lastenemyorigin)
			bs.lastenemyareanum = areanum
		end
	end
	--if the enemy is NOT visible for 4 seconds
	if bs.enemyvisible_time < G.floattime - 4 then
		G.AIEnter_Seek_LTG(bs, "battle retreat: lost enemy")
		return 0
	--else if the enemy is NOT visible
	elseif bs.enemyvisible_time < G.floattime then
		--if there is another enemy
		if G.BotFindEnemy(bs, -1) ~= 0 then
			G.AIEnter_Battle_Fight(bs, "battle retreat: another enemy")
			return 0
		end
	end
	--
	G.BotTeamGoals(bs, 1)
	--use holdable items
	G.BotBattleUseItems(bs)
	--get the current long term goal while retreating
	if G.BotLongTermGoal(bs, bs.tfl, 1, goal) == 0 then
		G.AIEnter_Battle_SuicidalFight(bs, "battle retreat: no way out")
		return 0
	end
	--check for nearby goals periodicly
	if bs.check_time < G.floattime then
		bs.check_time = G.floattime + 1
		range = 150

		if G.gametype == C.GT_CTF or G.gametype == C.GT_CTF_ELIMINATION then
			--if carrying a flag the bot shouldn't be distracted too much
			if G.BotCTFCarryingFlag(bs) ~= 0 then
				range = 50
			end
		elseif G.gametype == C.GT_1FCTF then
			if G.Bot1FCTFCarryingFlag(bs) ~= 0 then
				range = 50
			end
		elseif G.gametype == C.GT_HARVESTER then
			if G.BotHarvesterCarryingCubes(bs) ~= 0 then
				range = 80
			end
		end
		--
		if G.BotNearbyGoal(bs, bs.tfl, goal, range) ~= 0 then
			G.trap_BotResetLastAvoidReach(bs.ms)
			--time the bot gets to pick up the nearby goal item
			bs.nbg_time = G.floattime + range / 100 + 1
			G.AIEnter_Battle_NBG(bs, "battle retreat: nbg")
			return 0
		end
	end
	--initialize the movement state
	G.BotSetupForMovement(bs)
	--move towards the goal
	G.trap_BotMoveToGoal(moveresult, bs.ms, goal, bs.tfl)
	--if the movement failed
	if moveresult.failure ~= 0 then
		--reset the avoid reach, otherwise bot is stuck in current area
		G.trap_BotResetAvoidReach(bs.ms)
		bs.ltg_time = 0
	end
	--
	G.BotAIBlocked(bs, moveresult, 0)
	--choose the best weapon to fight with
	G.BotChooseWeapon(bs)
	--if the view is fixed for the movement
	if bit32.band(moveresult.flags, bit32.bor(C.MOVERESULT_MOVEMENTVIEW, C.MOVERESULT_SWIMVIEW)) ~= 0 then
		Q.VectorCopy(moveresult.ideal_viewangles, bs.ideal_viewangles)
	elseif bit32.band(moveresult.flags, C.MOVERESULT_MOVEMENTVIEWSET) == 0
		and bit32.band(bs.flags, C.BFL_IDEALVIEWSET) == 0 then
		attack_skill = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_ATTACK_SKILL, 0, 1)
		--if the bot is skilled anough
		if attack_skill > 0.3 then
			G.BotAimAtEnemy(bs)
		else
			if G.trap_BotMovementViewTarget(bs.ms, goal, bs.tfl, 300, target) ~= 0 then
				Q.VectorSubtract(target, bs.origin, dir)
				Q.vectoangles(dir, bs.ideal_viewangles)
			else
				Q.vectoangles(moveresult.movedir, bs.ideal_viewangles)
			end
			bs.ideal_viewangles[2] = bs.ideal_viewangles[2] * 0.5
		end
	end
	--if the weapon is used for the bot movement
	if bit32.band(moveresult.flags, C.MOVERESULT_MOVEMENTWEAPON) ~= 0 then bs.weaponnum = moveresult.weapon end
	--attack the enemy if possible
	G.BotCheckAttack(bs)
	--
	return 1
end

function G.AIEnter_Battle_NBG(bs, s)
	G.BotRecordNodeSwitch(bs, "battle NBG", "", s)
	bs.ainode = G.AINode_Battle_NBG
end

function G.AINode_Battle_NBG(bs)
	local areanum
	local goal = S.bot_goal_t()
	local entinfo = S.aas_entityinfo_t()
	local moveresult = S.bot_moveresult_t()
	local attack_skill
	local target = Q.vec3()
	local dir = Q.vec3()

	if G.BotIsObserver(bs) then
		G.AIEnter_Observer(bs, "battle nbg: observer")
		return 0
	end
	--if in the intermission
	if G.BotIntermission(bs) then
		G.AIEnter_Intermission(bs, "battle nbg: intermission")
		return 0
	end
	--respawn if dead
	if G.BotIsDead(bs) then
		G.AIEnter_Respawn(bs, "battle nbg: bot dead")
		return 0
	end
	--if no enemy
	if bs.enemy < 0 then
		G.AIEnter_Seek_NBG(bs, "battle nbg: no enemy")
		return 0
	end
	--
	G.BotEntityInfo(bs.enemy, entinfo)
	if G.EntityIsDead(entinfo) then
		G.AIEnter_Seek_NBG(bs, "battle nbg: enemy dead")
		return 0
	end
	--
	bs.tfl = C.TFL_DEFAULT
	if G.bot_grapple.integer ~= 0 then bs.tfl = bit32.bor(bs.tfl, C.TFL_GRAPPLEHOOK) end
	--if in lava or slime the bot should be able to get out
	if G.BotInLavaOrSlime(bs) then bs.tfl = bit32.bor(bs.tfl, C.TFL_LAVA, C.TFL_SLIME) end
	--
	if G.BotCanAndWantsToRocketJump(bs) ~= 0 then
		bs.tfl = bit32.bor(bs.tfl, C.TFL_ROCKETJUMP)
	end
	--map specific code
	G.BotMapScripts(bs)
	--update the last time the enemy was visible
	if G.BotEntityVisible(bs.entitynum, bs.eye, bs.viewangles, 360, bs.enemy) ~= 0 then
		bs.enemyvisible_time = G.floattime
		Q.VectorCopy(entinfo.origin, target)
		-- if not a player enemy
		if bs.enemy >= C.MAX_CLIENTS then
			-- if attacking an obelisk
			if bs.enemy == G.redobelisk.entitynum or
				bs.enemy == G.blueobelisk.entitynum then
				target[2] = target[2] + 16
			end
		end
		--update the reachability area and origin if possible
		areanum = G.BotPointAreaNum(target)
		if areanum ~= 0 and G.trap_AAS_AreaReachability(areanum) ~= 0 then
			Q.VectorCopy(target, bs.lastenemyorigin)
			bs.lastenemyareanum = areanum
		end
	end
	--if the bot has no goal or touches the current goal
	if G.trap_BotGetTopGoal(bs.gs, goal) == 0 then
		bs.nbg_time = 0
	elseif G.BotReachedGoal(bs, goal) ~= 0 then
		bs.nbg_time = 0
	end
	--
	if bs.nbg_time < G.floattime then
		--pop the current goal from the stack
		G.trap_BotPopGoal(bs.gs)
		--if the bot still has a goal
		if G.trap_BotGetTopGoal(bs.gs, goal) ~= 0 then
			G.AIEnter_Battle_Retreat(bs, "battle nbg: time out")
		else
			G.AIEnter_Battle_Fight(bs, "battle nbg: time out")
		end
		--
		return 0
	end
	--initialize the movement state
	G.BotSetupForMovement(bs)
	--move towards the goal
	G.trap_BotMoveToGoal(moveresult, bs.ms, goal, bs.tfl)
	--if the movement failed
	if moveresult.failure ~= 0 then
		--reset the avoid reach, otherwise bot is stuck in current area
		G.trap_BotResetAvoidReach(bs.ms)
		bs.nbg_time = 0
	end
	--
	G.BotAIBlocked(bs, moveresult, 0)
	--update the attack inventory values
	G.BotUpdateBattleInventory(bs, bs.enemy)
	--choose the best weapon to fight with
	G.BotChooseWeapon(bs)
	--if the view is fixed for the movement
	if bit32.band(moveresult.flags, bit32.bor(C.MOVERESULT_MOVEMENTVIEW, C.MOVERESULT_SWIMVIEW)) ~= 0 then
		Q.VectorCopy(moveresult.ideal_viewangles, bs.ideal_viewangles)
	elseif bit32.band(moveresult.flags, C.MOVERESULT_MOVEMENTVIEWSET) == 0
		and bit32.band(bs.flags, C.BFL_IDEALVIEWSET) == 0 then
		attack_skill = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_ATTACK_SKILL, 0, 1)
		--if the bot is skilled anough and the enemy is visible
		if attack_skill > 0.3 then
			G.BotAimAtEnemy(bs)
		else
			if G.trap_BotMovementViewTarget(bs.ms, goal, bs.tfl, 300, target) ~= 0 then
				Q.VectorSubtract(target, bs.origin, dir)
				Q.vectoangles(dir, bs.ideal_viewangles)
			else
				Q.vectoangles(moveresult.movedir, bs.ideal_viewangles)
			end
			bs.ideal_viewangles[2] = bs.ideal_viewangles[2] * 0.5
		end
	end
	--if the weapon is used for the bot movement
	if bit32.band(moveresult.flags, C.MOVERESULT_MOVEMENTWEAPON) ~= 0 then bs.weaponnum = moveresult.weapon end
	--attack the enemy if possible
	G.BotCheckAttack(bs)
	--
	return 1
end

return nil
