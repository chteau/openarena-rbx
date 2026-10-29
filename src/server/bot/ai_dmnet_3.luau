--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/ai_dmnet.c, part 3 of 5).

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
-- Luau port of OpenArena 0.8.8's ai_dmnet.c (gamecode 9e0f0c0), part 3 of 5. Long term goal, intermission/observer/stand/respawn nodes, activate weapon, BotClearPath.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local SF = G.FileStatics("ai_dmnet")

function G.BotLongTermGoal(bs, tfl, retreat, goal)
	local entinfo = S.aas_entityinfo_t()
	local dir = Q.vec3()

	if bs.lead_time > 0 and retreat == 0 then
		if bs.lead_time < G.floattime then
			G.BotAI_BotInitialChat(bs, "lead_stop", G.EasyClientName(bs.lead_teammate, C.MAX_MESSAGE_SIZE), nil)
			G.trap_BotEnterChat(bs.cs, bs.teammate, C.CHAT_TELL)
			bs.lead_time = 0
			return G.BotGetLongTermGoal(bs, tfl, retreat, goal)
		end
		if bs.leadmessage_time < 0 and -bs.leadmessage_time < G.floattime then
			G.BotAI_BotInitialChat(bs, "followme", G.EasyClientName(bs.lead_teammate, C.MAX_MESSAGE_SIZE), nil)
			G.trap_BotEnterChat(bs.cs, bs.teammate, C.CHAT_TELL)
			bs.leadmessage_time = G.floattime
		end
		G.BotEntityInfo(bs.lead_teammate, entinfo)
		if entinfo.valid ~= 0 then
			local areanum = G.BotPointAreaNum(entinfo.origin)
			if areanum ~= 0 and G.trap_AAS_AreaReachability(areanum) ~= 0 then
				bs.lead_teamgoal.entitynum = bs.lead_teammate
				bs.lead_teamgoal.areanum = areanum
				Q.VectorCopy(entinfo.origin, bs.lead_teamgoal.origin)
				Q.VectorSet(bs.lead_teamgoal.mins, -8, -8, -8)
				Q.VectorSet(bs.lead_teamgoal.maxs, 8, 8, 8)
			end
		end
		if G.BotEntityVisible(bs.entitynum, bs.eye, bs.viewangles, 360, bs.lead_teammate) ~= 0 then
			bs.leadvisible_time = G.floattime
		end
		if bs.leadvisible_time < G.floattime - 1 then
			bs.leadbackup_time = G.floattime + 2
		end
		Q.VectorSubtract(bs.origin, bs.lead_teamgoal.origin, dir)
		local squaredist = Q.VectorLengthSquared(dir)
		if bs.leadbackup_time > G.floattime then
			if bs.leadmessage_time < G.floattime - 20 then
				G.BotAI_BotInitialChat(bs, "followme", G.EasyClientName(bs.lead_teammate, C.MAX_MESSAGE_SIZE), nil)
				G.trap_BotEnterChat(bs.cs, bs.teammate, C.CHAT_TELL)
				bs.leadmessage_time = G.floattime
			end
			if squaredist < 100 * 100 then
				bs.leadbackup_time = 0
			end
			S.copy_bot_goal_t(goal, bs.lead_teamgoal)
			return 1
		else
			if squaredist > 500 * 500 then
				if bs.leadmessage_time < G.floattime - 20 then
					G.BotAI_BotInitialChat(bs, "followme", G.EasyClientName(bs.lead_teammate, C.MAX_MESSAGE_SIZE), nil)
					G.trap_BotEnterChat(bs.cs, bs.teammate, C.CHAT_TELL)
					bs.leadmessage_time = G.floattime
				end
				Q.VectorSubtract(entinfo.origin, bs.origin, dir)
				Q.vectoangles(dir, bs.ideal_viewangles)
				bs.ideal_viewangles[2] = bs.ideal_viewangles[2] * 0.5
				return 0
			end
		end
	end
	return G.BotGetLongTermGoal(bs, tfl, retreat, goal)
end

function G.AIEnter_Intermission(bs, s)
	G.BotRecordNodeSwitch(bs, "intermission", "", s)
	G.BotResetState(bs)
	if G.BotChat_EndLevel(bs) ~= 0 then
		G.trap_BotEnterChat(bs.cs, 0, bs.chatto)
	end
	bs.ainode = G.AINode_Intermission
end

function G.AINode_Intermission(bs)
	if not G.BotIntermission(bs) then
		if G.BotChat_StartLevel(bs) ~= 0 then
			bs.stand_time = G.floattime + G.BotChatTime(bs)
		else
			bs.stand_time = G.floattime + 2
		end
		G.AIEnter_Stand(bs, "intermission: chat")
	end
	return 1
end

function G.AIEnter_Observer(bs, s)
	G.BotRecordNodeSwitch(bs, "observer", "", s)
	G.BotResetState(bs)
	bs.ainode = G.AINode_Observer
end

function G.AINode_Observer(bs)
	if not G.BotIsObserver(bs) then
		G.AIEnter_Stand(bs, "observer: left observer")
	end
	return 1
end

function G.AIEnter_Stand(bs, s)
	G.BotRecordNodeSwitch(bs, "stand", "", s)
	bs.standfindenemy_time = G.floattime + 1
	bs.ainode = G.AINode_Stand
end

function G.AINode_Stand(bs)
	if bs.lastframe_health > bs.inventory[C.INVENTORY_HEALTH] then
		if G.BotChat_HitTalking(bs) ~= 0 then
			bs.standfindenemy_time = G.floattime + G.BotChatTime(bs) + 0.1
			bs.stand_time = G.floattime + G.BotChatTime(bs) + 0.1
		end
	end
	if bs.standfindenemy_time < G.floattime then
		if G.BotFindEnemy(bs, -1) ~= 0 then
			G.AIEnter_Battle_Fight(bs, "stand: found enemy")
			return 0
		end
		bs.standfindenemy_time = G.floattime + 1
	end
	G.trap_EA_Talk(bs.client)
	if bs.stand_time < G.floattime then
		G.trap_BotEnterChat(bs.cs, 0, bs.chatto)
		G.AIEnter_Seek_LTG(bs, "stand: time out")
		return 0
	end
	return 1
end

function G.AIEnter_Respawn(bs, s)
	G.BotRecordNodeSwitch(bs, "respawn", "", s)
	G.trap_BotResetMoveState(bs.ms)
	G.trap_BotResetGoalState(bs.gs)
	G.trap_BotResetAvoidGoals(bs.gs)
	G.trap_BotResetAvoidReach(bs.ms)
	if G.BotChat_Death(bs) ~= 0 then
		bs.respawn_time = G.floattime + G.BotChatTime(bs)
		bs.respawnchat_time = G.floattime
	else
		bs.respawn_time = G.floattime + 1 + Q.random()
		bs.respawnchat_time = 0
	end
	bs.respawn_wait = 0
	bs.ainode = G.AINode_Respawn
end

function G.AINode_Respawn(bs)
	if bs.respawn_wait ~= 0 then
		if not G.BotIsDead(bs) then
			G.AIEnter_Seek_LTG(bs, "respawn: respawned")
		else
			G.trap_EA_Respawn(bs.client)
		end
	elseif bs.respawn_time < G.floattime then
		bs.respawn_wait = 1
		G.trap_EA_Respawn(bs.client)
		if bs.respawnchat_time ~= 0 then
			G.trap_BotEnterChat(bs.cs, 0, bs.chatto)
			bs.enemy = -1
		end
	end
	if bs.respawnchat_time ~= 0 and bs.respawnchat_time < G.floattime - 0.5 then
		G.trap_EA_Talk(bs.client)
	end
	return 1
end

function G.BotSelectActivateWeapon(bs)
	local inv = bs.inventory
	if inv[C.INVENTORY_MACHINEGUN] > 0 and inv[C.INVENTORY_BULLETS] > 0 then
		return C.WEAPONINDEX_MACHINEGUN
	elseif inv[C.INVENTORY_SHOTGUN] > 0 and inv[C.INVENTORY_SHELLS] > 0 then
		return C.WEAPONINDEX_SHOTGUN
	elseif inv[C.INVENTORY_PLASMAGUN] > 0 and inv[C.INVENTORY_CELLS] > 0 then
		return C.WEAPONINDEX_PLASMAGUN
	elseif inv[C.INVENTORY_LIGHTNING] > 0 and inv[C.INVENTORY_LIGHTNINGAMMO] > 0 then
		return C.WEAPONINDEX_LIGHTNING
	elseif inv[C.INVENTORY_CHAINGUN] > 0 and inv[C.INVENTORY_BELT] > 0 then
		return C.WEAPONINDEX_CHAINGUN
	elseif inv[C.INVENTORY_NAILGUN] > 0 and inv[C.INVENTORY_NAILS] > 0 then
		return C.WEAPONINDEX_NAILGUN
	elseif inv[C.INVENTORY_PROXLAUNCHER] > 0 and inv[C.INVENTORY_MINES] > 0 then
		return C.WEAPONINDEX_PROXLAUNCHER
	elseif inv[C.INVENTORY_GRENADELAUNCHER] > 0 and inv[C.INVENTORY_GRENADES] > 0 then
		return C.WEAPONINDEX_GRENADE_LAUNCHER
	elseif inv[C.INVENTORY_RAILGUN] > 0 and inv[C.INVENTORY_SLUGS] > 0 then
		return C.WEAPONINDEX_RAILGUN
	elseif inv[C.INVENTORY_ROCKETLAUNCHER] > 0 and inv[C.INVENTORY_ROCKETS] > 0 then
		return C.WEAPONINDEX_ROCKET_LAUNCHER
	elseif inv[C.INVENTORY_BFG10K] > 0 and inv[C.INVENTORY_BFGAMMO] > 0 then
		return C.WEAPONINDEX_BFG
	else
		return -1
	end
end

function G.BotClearPath(bs, moveresult)
	local target = Q.vec3()
	local dir = Q.vec3()
	local bsptrace = S.bsp_trace_t()
	local state = S.entityState_t()
	local viewOrWeapon = bit32.bor(C.MOVERESULT_MOVEMENTVIEW, C.MOVERESULT_MOVEMENTWEAPON)

	if bs.kamikazebody ~= 0 then
		if bit32.band(moveresult.flags, viewOrWeapon) == 0 then
			G.BotAI_GetEntityState(bs.kamikazebody, state)
			Q.VectorCopy(state.pos.trBase, target)
			target[2] = target[2] + 8
			Q.VectorSubtract(target, bs.eye, dir)
			Q.vectoangles(dir, moveresult.ideal_viewangles)
			moveresult.weapon = G.BotSelectActivateWeapon(bs)
			if moveresult.weapon == -1 then
				moveresult.weapon = 0
			end
			if moveresult.weapon ~= 0 then
				moveresult.flags = bit32.bor(moveresult.flags, C.MOVERESULT_MOVEMENTWEAPON, C.MOVERESULT_MOVEMENTVIEW)
				if bs.cur_ps.weapon == moveresult.weapon then
					if G.InFieldOfVision(bs.viewangles, 20, moveresult.ideal_viewangles) then
						G.BotAI_Trace(bsptrace, bs.eye, nil, nil, target, bs.entitynum, C.MASK_SHOT)
						if bsptrace.fraction >= 1.0 or bsptrace.ent == state.number then
							G.trap_EA_Attack(bs.client)
						end
					end
				end
			end
		end
	end
	if bit32.band(moveresult.flags, C.MOVERESULT_BLOCKEDBYAVOIDSPOT) ~= 0 then
		bs.blockedbyavoidspot_time = G.floattime + 5
	end
	if bs.blockedbyavoidspot_time > G.floattime and bit32.band(moveresult.flags, viewOrWeapon) == 0 then
		local bestdist = 300
		local bestmine = -1
		for i = 0, bs.numproxmines - 1 do
			G.BotAI_GetEntityState(bs.proxmines[i], state)
			Q.VectorSubtract(state.pos.trBase, bs.origin, dir)
			local dist = Q.VectorLength(dir)
			if dist < bestdist then
				bestdist = dist
				bestmine = i
			end
		end
		if bestmine ~= -1 then
			G.BotAI_GetEntityState(bs.proxmines[bestmine], state)
			Q.VectorCopy(state.pos.trBase, target)
			target[2] = target[2] + 2
			Q.VectorSubtract(target, bs.eye, dir)
			Q.vectoangles(dir, moveresult.ideal_viewangles)
			if bs.inventory[C.INVENTORY_PLASMAGUN] > 0 and bs.inventory[C.INVENTORY_CELLS] > 0 then
				moveresult.weapon = C.WEAPONINDEX_PLASMAGUN
			elseif bs.inventory[C.INVENTORY_ROCKETLAUNCHER] > 0 and bs.inventory[C.INVENTORY_ROCKETS] > 0 then
				moveresult.weapon = C.WEAPONINDEX_ROCKET_LAUNCHER
			elseif bs.inventory[C.INVENTORY_BFG10K] > 0 and bs.inventory[C.INVENTORY_BFGAMMO] > 0 then
				moveresult.weapon = C.WEAPONINDEX_BFG
			else
				moveresult.weapon = 0
			end
			if moveresult.weapon ~= 0 then
				moveresult.flags = bit32.bor(moveresult.flags, C.MOVERESULT_MOVEMENTWEAPON, C.MOVERESULT_MOVEMENTVIEW)
				if bs.cur_ps.weapon == moveresult.weapon then
					if G.InFieldOfVision(bs.viewangles, 20, moveresult.ideal_viewangles) then
						G.BotAI_Trace(bsptrace, bs.eye, nil, nil, target, bs.entitynum, C.MASK_SHOT)
						if bsptrace.fraction >= 1.0 or bsptrace.ent == state.number then
							G.trap_EA_Attack(bs.client)
						end
					end
				end
			end
		end
	end
end

function G.AIEnter_Seek_ActivateEntity(bs, s)
	G.BotRecordNodeSwitch(bs, "activate entity", "", s)
	bs.ainode = G.AINode_Seek_ActivateEntity
end

return nil
