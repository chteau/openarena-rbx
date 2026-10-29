--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/ai_dmnet.c).

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
-- Luau port of ai_dmnet.c, part 4 of 5. Seek (activate entity, NBG, LTG) and battle fight nodes.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local SF = G.FileStatics("ai_dmnet")

function G.AINode_Seek_ActivateEntity(bs)
	local target = Q.vec3()
	local dir = Q.vec3()
	local ideal_viewangles = Q.vec3()
	local moveresult = S.bot_moveresult_t()
	local bsptrace = S.bsp_trace_t()
	local entinfo = S.aas_entityinfo_t()

	if G.BotIsObserver(bs) then
		G.BotClearActivateGoalStack(bs)
		G.AIEnter_Observer(bs, "active entity: observer")
		return 0
	end
	--if in the intermission
	if G.BotIntermission(bs) then
		G.BotClearActivateGoalStack(bs)
		G.AIEnter_Intermission(bs, "activate entity: intermission")
		return 0
	end
	--respawn if dead
	if G.BotIsDead(bs) then
		G.BotClearActivateGoalStack(bs)
		G.AIEnter_Respawn(bs, "activate entity: bot dead")
		return 0
	end
	--
	bs.tfl = C.TFL_DEFAULT
	if G.bot_grapple.integer ~= 0 then bs.tfl = bit32.bor(bs.tfl, C.TFL_GRAPPLEHOOK) end
	-- if in lava or slime the bot should be able to get out
	if G.BotInLavaOrSlime(bs) then bs.tfl = bit32.bor(bs.tfl, C.TFL_LAVA, C.TFL_SLIME) end
	-- map specific code
	G.BotMapScripts(bs)
	-- no enemy
	bs.enemy = -1
	-- if the bot has no activate goal
	if bs.activatestack == nil then
		G.BotClearActivateGoalStack(bs)
		G.AIEnter_Seek_NBG(bs, "activate entity: no goal")
		return 0
	end
	--
	local goal = bs.activatestack.goal
	-- initialize target being visible to false
	local targetvisible = false
	-- if the bot has to shoot at a target to activate something
	if bs.activatestack.shoot ~= 0 then
		--
		G.BotAI_Trace(bsptrace, bs.eye, nil, nil, bs.activatestack.target, bs.entitynum, C.MASK_SHOT)
		-- if the shootable entity is visible from the current position
		if bsptrace.fraction >= 1.0 or bsptrace.ent == goal.entitynum then
			targetvisible = true
			-- if holding the right weapon
			if bs.cur_ps.weapon == bs.activatestack.weapon then
				Q.VectorSubtract(bs.activatestack.target, bs.eye, dir)
				Q.vectoangles(dir, ideal_viewangles)
				-- if the bot is pretty close with it's aim
				if G.InFieldOfVision(bs.viewangles, 20, ideal_viewangles) then
					G.trap_EA_Attack(bs.client)
				end
			end
		end
	end
	-- if the shoot target is visible
	if targetvisible then
		-- get the entity info of the entity the bot is shooting at
		G.BotEntityInfo(goal.entitynum, entinfo)
		-- if the entity the bot shoots at moved
		if not Q.VectorCompare(bs.activatestack.origin, entinfo.origin) then
			bs.activatestack.time = 0
		end
		-- if the activate goal has been activated or the bot takes too long
		if bs.activatestack.time < G.floattime then
			G.BotPopFromActivateGoalStack(bs)
			-- if there are more activate goals on the stack
			if bs.activatestack ~= nil then
				bs.activatestack.time = G.floattime + 10
				return 0
			end
			G.AIEnter_Seek_NBG(bs, "activate entity: time out")
			return 0
		end
		S.copy_bot_moveresult_t(moveresult, S.bot_moveresult_t())
	else
		-- if the bot has no goal
		if goal == nil then
			bs.activatestack.time = 0
		-- if the bot does not have a shoot goal
		elseif bs.activatestack.shoot == 0 then
			--if the bot touches the current goal
			if G.trap_BotTouchingGoal(bs.origin, goal) ~= 0 then
				bs.activatestack.time = 0
			end
		end
		-- if the activate goal has been activated or the bot takes too long
		if bs.activatestack.time < G.floattime then
			G.BotPopFromActivateGoalStack(bs)
			-- if there are more activate goals on the stack
			if bs.activatestack ~= nil then
				bs.activatestack.time = G.floattime + 10
				return 0
			end
			G.AIEnter_Seek_NBG(bs, "activate entity: activated")
			return 0
		end
		--predict obstacles
		if G.BotAIPredictObstacles(bs, goal) ~= 0 then
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
			--
			bs.activatestack.time = 0
		end
		--check if the bot is blocked
		G.BotAIBlocked(bs, moveresult, 1)
	end
	--
	G.BotClearPath(bs, moveresult)
	-- if the bot has to shoot to activate
	if bs.activatestack.shoot ~= 0 then
		-- if the view angles aren't yet used for the movement
		if bit32.band(moveresult.flags, C.MOVERESULT_MOVEMENTVIEW) == 0 then
			Q.VectorSubtract(bs.activatestack.target, bs.eye, dir)
			Q.vectoangles(dir, moveresult.ideal_viewangles)
			moveresult.flags = bit32.bor(moveresult.flags, C.MOVERESULT_MOVEMENTVIEW)
		end
		-- if there's no weapon yet used for the movement
		if bit32.band(moveresult.flags, C.MOVERESULT_MOVEMENTWEAPON) == 0 then
			moveresult.flags = bit32.bor(moveresult.flags, C.MOVERESULT_MOVEMENTWEAPON)
			--
			bs.activatestack.weapon = G.BotSelectActivateWeapon(bs)
			if bs.activatestack.weapon == -1 then
				--FIXME: find a decent weapon first
				bs.activatestack.weapon = 0
			end
			moveresult.weapon = bs.activatestack.weapon
		end
	end
	-- if the ideal view angles are set for movement
	if bit32.band(moveresult.flags, bit32.bor(C.MOVERESULT_MOVEMENTVIEWSET, C.MOVERESULT_MOVEMENTVIEW, C.MOVERESULT_SWIMVIEW)) ~= 0 then
		Q.VectorCopy(moveresult.ideal_viewangles, bs.ideal_viewangles)
	-- if waiting for something
	elseif bit32.band(moveresult.flags, C.MOVERESULT_WAITING) ~= 0 then
		if Q.random() < bs.thinktime * 0.8 then
			G.BotRoamGoal(bs, target)
			Q.VectorSubtract(target, bs.origin, dir)
			Q.vectoangles(dir, bs.ideal_viewangles)
			bs.ideal_viewangles[2] = bs.ideal_viewangles[2] * 0.5
		end
	elseif bit32.band(bs.flags, C.BFL_IDEALVIEWSET) == 0 then
		if G.trap_BotMovementViewTarget(bs.ms, goal, bs.tfl, 300, target) ~= 0 then
			Q.VectorSubtract(target, bs.origin, dir)
			Q.vectoangles(dir, bs.ideal_viewangles)
		else
			Q.vectoangles(moveresult.movedir, bs.ideal_viewangles)
		end
		bs.ideal_viewangles[2] = bs.ideal_viewangles[2] * 0.5
	end
	-- if the weapon is used for the bot movement
	if bit32.band(moveresult.flags, C.MOVERESULT_MOVEMENTWEAPON) ~= 0 then
		bs.weaponnum = moveresult.weapon
	end
	-- if there is an enemy
	if G.BotFindEnemy(bs, -1) ~= 0 then
		if G.BotWantsToRetreat(bs) ~= 0 then
			--keep the current long term goal and retreat
			G.AIEnter_Battle_NBG(bs, "activate entity: found enemy")
		else
			G.trap_BotResetLastAvoidReach(bs.ms)
			--empty the goal stack
			G.trap_BotEmptyGoalStack(bs.gs)
			--go fight
			G.AIEnter_Battle_Fight(bs, "activate entity: found enemy")
		end
		G.BotClearActivateGoalStack(bs)
	end
	return 1
end

function G.AIEnter_Seek_NBG(bs, s)
	local goal = S.bot_goal_t()

	if G.trap_BotGetTopGoal(bs.gs, goal) ~= 0 then
		local buf = G.trap_BotGoalName(goal.number, 144)
		G.BotRecordNodeSwitch(bs, "seek NBG", buf, s)
	else
		G.BotRecordNodeSwitch(bs, "seek NBG", "no goal", s)
	end
	bs.ainode = G.AINode_Seek_NBG
end

function G.AINode_Seek_NBG(bs)
	local goal = S.bot_goal_t()
	local target = Q.vec3()
	local dir = Q.vec3()
	local moveresult = S.bot_moveresult_t()

	if G.BotIsObserver(bs) then
		G.AIEnter_Observer(bs, "seek nbg: observer")
		return 0
	end
	--if in the intermission
	if G.BotIntermission(bs) then
		G.AIEnter_Intermission(bs, "seek nbg: intermision")
		return 0
	end
	--respawn if dead
	if G.BotIsDead(bs) then
		G.AIEnter_Respawn(bs, "seek nbg: bot dead")
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
	--no enemy
	bs.enemy = -1
	--if the bot has no goal
	if G.trap_BotGetTopGoal(bs.gs, goal) == 0 then
		bs.nbg_time = 0
	--if the bot touches the current goal
	elseif G.BotReachedGoal(bs, goal) ~= 0 then
		G.BotChooseWeapon(bs)
		bs.nbg_time = 0
	end
	--
	if bs.nbg_time < G.floattime then
		--pop the current goal from the stack
		G.trap_BotPopGoal(bs.gs)
		--check for new nearby items right away
		--NOTE: we canNOT reset the check_time to zero because it would create an endless loop of node switches
		bs.check_time = G.floattime + 0.05
		--go back to seek ltg
		G.AIEnter_Seek_LTG(bs, "seek nbg: time out")
		return 0
	end
	--predict obstacles
	if G.BotAIPredictObstacles(bs, goal) ~= 0 then
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
	--check if the bot is blocked
	G.BotAIBlocked(bs, moveresult, 1)
	--
	G.BotClearPath(bs, moveresult)
	--if the viewangles are used for the movement
	if bit32.band(moveresult.flags, bit32.bor(C.MOVERESULT_MOVEMENTVIEWSET, C.MOVERESULT_MOVEMENTVIEW, C.MOVERESULT_SWIMVIEW)) ~= 0 then
		Q.VectorCopy(moveresult.ideal_viewangles, bs.ideal_viewangles)
	--if waiting for something
	elseif bit32.band(moveresult.flags, C.MOVERESULT_WAITING) ~= 0 then
		if Q.random() < bs.thinktime * 0.8 then
			G.BotRoamGoal(bs, target)
			Q.VectorSubtract(target, bs.origin, dir)
			Q.vectoangles(dir, bs.ideal_viewangles)
			bs.ideal_viewangles[2] = bs.ideal_viewangles[2] * 0.5
		end
	elseif bit32.band(bs.flags, C.BFL_IDEALVIEWSET) == 0 then
		if G.trap_BotGetSecondGoal(bs.gs, goal) == 0 then G.trap_BotGetTopGoal(bs.gs, goal) end
		if G.trap_BotMovementViewTarget(bs.ms, goal, bs.tfl, 300, target) ~= 0 then
			Q.VectorSubtract(target, bs.origin, dir)
			Q.vectoangles(dir, bs.ideal_viewangles)
		--FIXME: look at cluster portals?
		else
			Q.vectoangles(moveresult.movedir, bs.ideal_viewangles)
		end
		bs.ideal_viewangles[2] = bs.ideal_viewangles[2] * 0.5
	end
	--if the weapon is used for the bot movement
	if bit32.band(moveresult.flags, C.MOVERESULT_MOVEMENTWEAPON) ~= 0 then bs.weaponnum = moveresult.weapon end
	--if there is an enemy
	if G.BotFindEnemy(bs, -1) ~= 0 then
		if G.BotWantsToRetreat(bs) ~= 0 then
			--keep the current long term goal and retreat
			G.AIEnter_Battle_NBG(bs, "seek nbg: found enemy")
		else
			G.trap_BotResetLastAvoidReach(bs.ms)
			--empty the goal stack
			G.trap_BotEmptyGoalStack(bs.gs)
			--go fight
			G.AIEnter_Battle_Fight(bs, "seek nbg: found enemy")
		end
	end
	return 1
end

function G.AIEnter_Seek_LTG(bs, s)
	local goal = S.bot_goal_t()

	if G.trap_BotGetTopGoal(bs.gs, goal) ~= 0 then
		local buf = G.trap_BotGoalName(goal.number, 144)
		G.BotRecordNodeSwitch(bs, "seek LTG", buf, s)
	else
		G.BotRecordNodeSwitch(bs, "seek LTG", "no goal", s)
	end
	bs.ainode = G.AINode_Seek_LTG
end

function G.AINode_Seek_LTG(bs)
	local goal = S.bot_goal_t()
	local target = Q.vec3()
	local dir = Q.vec3()
	local moveresult = S.bot_moveresult_t()
	local range

	if G.BotIsObserver(bs) then
		G.AIEnter_Observer(bs, "seek ltg: observer")
		return 0
	end
	--if in the intermission
	if G.BotIntermission(bs) then
		G.AIEnter_Intermission(bs, "seek ltg: intermission")
		return 0
	end
	--respawn if dead
	if G.BotIsDead(bs) then
		G.AIEnter_Respawn(bs, "seek ltg: bot dead")
		return 0
	end
	--
	if G.BotChat_Random(bs) ~= 0 then
		bs.stand_time = G.floattime + G.BotChatTime(bs)
		G.AIEnter_Stand(bs, "seek ltg: random chat")
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
	--no enemy
	bs.enemy = -1
	--
	if bs.killedenemy_time > G.floattime - 2 then
		if Q.random() < bs.thinktime * 1 then
			G.trap_EA_Gesture(bs.client)
		end
	end
	--if there is an enemy
	if G.BotFindEnemy(bs, -1) ~= 0 then
		if G.BotWantsToRetreat(bs) ~= 0 then
			--keep the current long term goal and retreat
			G.AIEnter_Battle_Retreat(bs, "seek ltg: found enemy")
			return 0
		else
			G.trap_BotResetLastAvoidReach(bs.ms)
			--empty the goal stack
			G.trap_BotEmptyGoalStack(bs.gs)
			--go fight
			G.AIEnter_Battle_Fight(bs, "seek ltg: found enemy")
			return 0
		end
	end
	--
	G.BotTeamGoals(bs, 0)
	--get the current long term goal
	if G.BotLongTermGoal(bs, bs.tfl, 0, goal) == 0 then
		return 1
	end
	--check for nearby goals periodicly
	if bs.check_time < G.floattime then
		bs.check_time = G.floattime + 0.5
		--check if the bot wants to camp
		G.BotWantsToCamp(bs)
		--
		if bs.ltgtype == C.LTG_DEFENDKEYAREA then range = 400
		else range = 150 end
		--
		if G.gametype == C.GT_CTF or G.gametype == C.GT_CTF_ELIMINATION then
			--if carrying a flag the bot shouldn't be distracted too much
			if G.BotCTFCarryingFlag(bs) ~= 0 then
				range = 50
			end
		-- original condition "gametype == GT_1FCTF || GT_POSSESSION" is always true (GT_POSSESSION is a nonzero constant)
		elseif G.gametype == C.GT_1FCTF or true then
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
			bs.nbg_time = G.floattime + 4 + range * 0.01
			G.AIEnter_Seek_NBG(bs, "ltg seek: nbg")
			return 0
		end
	end
	--predict obstacles
	if G.BotAIPredictObstacles(bs, goal) ~= 0 then
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
		bs.ltg_time = 0
	end
	--
	G.BotAIBlocked(bs, moveresult, 1)
	--
	G.BotClearPath(bs, moveresult)
	--if the viewangles are used for the movement
	if bit32.band(moveresult.flags, bit32.bor(C.MOVERESULT_MOVEMENTVIEWSET, C.MOVERESULT_MOVEMENTVIEW, C.MOVERESULT_SWIMVIEW)) ~= 0 then
		Q.VectorCopy(moveresult.ideal_viewangles, bs.ideal_viewangles)
	--if waiting for something
	elseif bit32.band(moveresult.flags, C.MOVERESULT_WAITING) ~= 0 then
		if Q.random() < bs.thinktime * 0.8 then
			G.BotRoamGoal(bs, target)
			Q.VectorSubtract(target, bs.origin, dir)
			Q.vectoangles(dir, bs.ideal_viewangles)
			bs.ideal_viewangles[2] = bs.ideal_viewangles[2] * 0.5
		end
	elseif bit32.band(bs.flags, C.BFL_IDEALVIEWSET) == 0 then
		if G.trap_BotMovementViewTarget(bs.ms, goal, bs.tfl, 300, target) ~= 0 then
			Q.VectorSubtract(target, bs.origin, dir)
			Q.vectoangles(dir, bs.ideal_viewangles)
		--FIXME: look at cluster portals?
		elseif Q.VectorLengthSquared(moveresult.movedir) ~= 0 then
			Q.vectoangles(moveresult.movedir, bs.ideal_viewangles)
		elseif Q.random() < bs.thinktime * 0.8 then
			G.BotRoamGoal(bs, target)
			Q.VectorSubtract(target, bs.origin, dir)
			Q.vectoangles(dir, bs.ideal_viewangles)
			bs.ideal_viewangles[2] = bs.ideal_viewangles[2] * 0.5
		end
		bs.ideal_viewangles[2] = bs.ideal_viewangles[2] * 0.5
	end
	--if the weapon is used for the bot movement
	if bit32.band(moveresult.flags, C.MOVERESULT_MOVEMENTWEAPON) ~= 0 then bs.weaponnum = moveresult.weapon end
	--
	return 1
end

function G.AIEnter_Battle_Fight(bs, s)
	G.BotRecordNodeSwitch(bs, "battle fight", "", s)
	G.trap_BotResetLastAvoidReach(bs.ms)
	bs.ainode = G.AINode_Battle_Fight
	bs.flags = bit32.band(bs.flags, bit32.bnot(C.BFL_FIGHTSUICIDAL))
end

function G.AIEnter_Battle_SuicidalFight(bs, s)
	G.BotRecordNodeSwitch(bs, "battle fight", "", s)
	G.trap_BotResetLastAvoidReach(bs.ms)
	bs.ainode = G.AINode_Battle_Fight
	bs.flags = bit32.bor(bs.flags, C.BFL_FIGHTSUICIDAL)
end

function G.AINode_Battle_Fight(bs)
	local target = Q.vec3()
	local entinfo = S.aas_entityinfo_t()
	local moveresult

	if G.BotIsObserver(bs) then
		G.AIEnter_Observer(bs, "battle fight: observer")
		return 0
	end

	--if in the intermission
	if G.BotIntermission(bs) then
		G.AIEnter_Intermission(bs, "battle fight: intermission")
		return 0
	end
	--respawn if dead
	if G.BotIsDead(bs) then
		G.AIEnter_Respawn(bs, "battle fight: bot dead")
		return 0
	end
	--if there is another better enemy
	G.BotFindEnemy(bs, bs.enemy)
	--if no enemy
	if bs.enemy < 0 then
		G.AIEnter_Seek_LTG(bs, "battle fight: no enemy")
		return 0
	end
	--
	G.BotEntityInfo(bs.enemy, entinfo)
	--if the enemy is dead
	if bs.enemydeath_time ~= 0 then
		if bs.enemydeath_time < G.floattime - 1.0 then
			bs.enemydeath_time = 0
			if bs.enemysuicide ~= 0 then
				G.BotChat_EnemySuicide(bs)
			end
			if bs.lastkilledplayer == bs.enemy and G.BotChat_Kill(bs) ~= 0 then
				bs.stand_time = G.floattime + G.BotChatTime(bs)
				G.AIEnter_Stand(bs, "battle fight: enemy dead")
			else
				bs.ltg_time = 0
				G.AIEnter_Seek_LTG(bs, "battle fight: enemy dead")
			end
			return 0
		end
	else
		if G.EntityIsDead(entinfo) then
			bs.enemydeath_time = G.floattime
		end
	end
	--if the enemy is invisible and not shooting the bot looses track easily
	if G.EntityIsInvisible(entinfo) and not G.EntityIsShooting(entinfo) then
		if Q.random() < 0.2 then
			G.AIEnter_Seek_LTG(bs, "battle fight: invisible")
			return 0
		end
	end
	--
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
	local areanum = G.BotPointAreaNum(target)
	if areanum ~= 0 and G.trap_AAS_AreaReachability(areanum) ~= 0 then
		Q.VectorCopy(target, bs.lastenemyorigin)
		bs.lastenemyareanum = areanum
	end
	--update the attack inventory values
	G.BotUpdateBattleInventory(bs, bs.enemy)
	--if the bot's health decreased
	if bs.lastframe_health > bs.inventory[C.INVENTORY_HEALTH] then
		if G.BotChat_HitNoDeath(bs) ~= 0 then
			bs.stand_time = G.floattime + G.BotChatTime(bs)
			G.AIEnter_Stand(bs, "battle fight: chat health decreased")
			return 0
		end
	end
	--if the bot hit someone
	if bs.cur_ps.persistant[C.PERS_HITS] > bs.lasthitcount then
		if G.BotChat_HitNoKill(bs) ~= 0 then
			bs.stand_time = G.floattime + G.BotChatTime(bs)
			G.AIEnter_Stand(bs, "battle fight: chat hit someone")
			return 0
		end
	end
	--if the enemy is not visible
	if G.BotEntityVisible(bs.entitynum, bs.eye, bs.viewangles, 360, bs.enemy) == 0 then
		if bs.enemy == G.redobelisk.entitynum or bs.enemy == G.blueobelisk.entitynum then
			G.AIEnter_Battle_Chase(bs, "battle fight: obelisk out of sight")
			return 0
		end
		if G.BotWantsToChase(bs) ~= 0 then
			G.AIEnter_Battle_Chase(bs, "battle fight: enemy out of sight")
			return 0
		else
			G.AIEnter_Seek_LTG(bs, "battle fight: enemy out of sight")
			return 0
		end
	end
	--use holdable items
	G.BotBattleUseItems(bs)
	--
	bs.tfl = C.TFL_DEFAULT
	if G.bot_grapple.integer ~= 0 then bs.tfl = bit32.bor(bs.tfl, C.TFL_GRAPPLEHOOK) end
	--if in lava or slime the bot should be able to get out
	if G.BotInLavaOrSlime(bs) then bs.tfl = bit32.bor(bs.tfl, C.TFL_LAVA, C.TFL_SLIME) end
	--
	if G.BotCanAndWantsToRocketJump(bs) ~= 0 then
		bs.tfl = bit32.bor(bs.tfl, C.TFL_ROCKETJUMP)
	end
	--choose the best weapon to fight with
	G.BotChooseWeapon(bs)
	--do attack movements
	moveresult = G.BotAttackMove(bs, bs.tfl)
	--if the movement failed
	if moveresult.failure ~= 0 then
		--reset the avoid reach, otherwise bot is stuck in current area
		G.trap_BotResetAvoidReach(bs.ms)
		bs.ltg_time = 0
	end
	--
	G.BotAIBlocked(bs, moveresult, 0)
	--aim at the enemy
	G.BotAimAtEnemy(bs)
	--attack the enemy if possible
	G.BotCheckAttack(bs)
	--if the bot wants to retreat
	if bit32.band(bs.flags, C.BFL_FIGHTSUICIDAL) == 0 then
		if G.BotWantsToRetreat(bs) ~= 0 then
			G.AIEnter_Battle_Retreat(bs, "battle fight: wants to retreat")
			return 1
		end
	end
	return 1
end

return nil
