--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/ai_dmnet.c, part 2 of 5).

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
-- Luau port of ai_dmnet.c, part 2 of 5. BotGetLongTermGoal.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local SF = G.FileStatics("ai_dmnet")

-- voice chat names from ui/menudef.h
local VC = {
	YES = "yes",
	ONDEFENSE = "ondefense",
	INPOSITION = "inposition",
	ONGETFLAG = "ongetflag",
	ONRETURNFLAG = "onreturnflag",
	ONOFFENSE = "onoffense",
}

function G.BotGetLongTermGoal(bs, tfl, retreat, goal)
	local target = Q.vec3()
	local dir = Q.vec3()
	local dir2 = Q.vec3()
	local netname
	local buf
	local areanum
	local croucher
	local entinfo = S.aas_entityinfo_t()
	local botinfo = S.aas_entityinfo_t()

	if bs.ltgtype == C.LTG_TEAMHELP and not retreat then
		--check for bot typing status message
		if bs.teammessage_time ~= 0 and bs.teammessage_time < G.floattime then
			netname = G.EasyClientName(bs.teammate, C.MAX_NETNAME)
			G.BotAI_BotInitialChat(bs, "help_start", netname)
			G.trap_BotEnterChat(bs.cs, bs.decisionmaker, C.CHAT_TELL)
			G.BotVoiceChatOnly(bs, bs.decisionmaker, VC.YES)
			G.trap_EA_Action(bs.client, C.ACTION_AFFIRMATIVE)
			bs.teammessage_time = 0
		end
		--if trying to help the team mate for more than a minute
		if bs.teamgoal_time < G.floattime then
			bs.ltgtype = 0
		end
		--if the team mate IS visible for quite some time
		if bs.teammatevisible_time < G.floattime - 10 then bs.ltgtype = 0 end
		--get entity information of the companion
		G.BotEntityInfo(bs.teammate, entinfo)
		--if the team mate is visible
		if G.BotEntityVisible(bs.entitynum, bs.eye, bs.viewangles, 360, bs.teammate) ~= 0 then
			--if close just stand still there
			Q.VectorSubtract(entinfo.origin, bs.origin, dir)
			if Q.VectorLengthSquared(dir) < 100 * 100 then
				G.trap_BotResetAvoidReach(bs.ms)
				return 0
			end
		else
			--last time the bot was NOT visible
			bs.teammatevisible_time = G.floattime
		end
		--if the entity information is valid (entity in PVS)
		if entinfo.valid ~= 0 then
			areanum = G.BotPointAreaNum(entinfo.origin)
			if areanum ~= 0 and G.trap_AAS_AreaReachability(areanum) ~= 0 then
				--update team goal
				bs.teamgoal.entitynum = bs.teammate
				bs.teamgoal.areanum = areanum
				Q.VectorCopy(entinfo.origin, bs.teamgoal.origin)
				Q.VectorSet(bs.teamgoal.mins, -8, -8, -8)
				Q.VectorSet(bs.teamgoal.maxs, 8, 8, 8)
			end
		end
		S.copy_bot_goal_t(goal, bs.teamgoal)
		return 1
	end
	--if the bot accompanies someone
	if bs.ltgtype == C.LTG_TEAMACCOMPANY and not retreat then
		--check for bot typing status message
		if bs.teammessage_time ~= 0 and bs.teammessage_time < G.floattime then
			netname = G.EasyClientName(bs.teammate, C.MAX_NETNAME)
			G.BotAI_BotInitialChat(bs, "accompany_start", netname)
			G.trap_BotEnterChat(bs.cs, bs.decisionmaker, C.CHAT_TELL)
			G.BotVoiceChatOnly(bs, bs.decisionmaker, VC.YES)
			G.trap_EA_Action(bs.client, C.ACTION_AFFIRMATIVE)
			bs.teammessage_time = 0
		end
		--if accompanying the companion for 3 minutes
		if bs.teamgoal_time < G.floattime then
			netname = G.EasyClientName(bs.teammate, C.MAX_NETNAME)
			G.BotAI_BotInitialChat(bs, "accompany_stop", netname)
			G.trap_BotEnterChat(bs.cs, bs.teammate, C.CHAT_TELL)
			bs.ltgtype = 0
		end
		--get entity information of the companion
		G.BotEntityInfo(bs.teammate, entinfo)
		--if the companion is visible
		if G.BotEntityVisible(bs.entitynum, bs.eye, bs.viewangles, 360, bs.teammate) ~= 0 then
			--update visible time
			bs.teammatevisible_time = G.floattime
			Q.VectorSubtract(entinfo.origin, bs.origin, dir)
			if Q.VectorLengthSquared(dir) < bs.formation_dist * bs.formation_dist then
				--
				-- if the client being followed bumps into this bot then
				-- the bot should back up
				G.BotEntityInfo(bs.entitynum, botinfo)
				-- if the followed client is not standing ontop of the bot
				if botinfo.origin[2] + botinfo.maxs[2] > entinfo.origin[2] + entinfo.mins[2] then
					-- if the bounding boxes touch each other
					if botinfo.origin[0] + botinfo.maxs[0] > entinfo.origin[0] + entinfo.mins[0] - 4 and
						botinfo.origin[0] + botinfo.mins[0] < entinfo.origin[0] + entinfo.maxs[0] + 4 then
						if botinfo.origin[1] + botinfo.maxs[1] > entinfo.origin[1] + entinfo.mins[1] - 4 and
							botinfo.origin[1] + botinfo.mins[1] < entinfo.origin[1] + entinfo.maxs[1] + 4 then
							if botinfo.origin[2] + botinfo.maxs[2] > entinfo.origin[2] + entinfo.mins[2] - 4 and
								botinfo.origin[2] + botinfo.mins[2] < entinfo.origin[2] + entinfo.maxs[2] + 4 then
								-- if the followed client looks in the direction of this bot
								Q.AngleVectors(entinfo.angles, dir, nil, nil)
								dir[2] = 0
								Q.VectorNormalize(dir)
								Q.VectorSubtract(bs.origin, entinfo.origin, dir2)
								Q.VectorNormalize(dir2)
								if Q.DotProduct(dir, dir2) > 0.7 then
									-- back up
									G.BotSetupForMovement(bs)
									G.trap_BotMoveInDirection(bs.ms, dir2, 400, C.MOVE_WALK)
								end
							end
						end
					end
				end
				--check if the bot wants to crouch
				--don't crouch if crouched less than 5 seconds ago
				if bs.attackcrouch_time < G.floattime - 5 then
					croucher = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_CROUCHER, 0, 1)
					if Q.random() < bs.thinktime * croucher then
						bs.attackcrouch_time = G.floattime + 5 + croucher * 15
					end
				end
				--don't crouch when swimming
				if G.trap_AAS_Swimming(bs.origin) ~= 0 then bs.attackcrouch_time = G.floattime - 1 end
				--if not arrived yet or arived some time ago
				if bs.arrive_time < G.floattime - 2 then
					--if not arrived yet
					if bs.arrive_time == 0 then
						G.trap_EA_Gesture(bs.client)
						netname = G.EasyClientName(bs.teammate, C.MAX_NETNAME)
						G.BotAI_BotInitialChat(bs, "accompany_arrive", netname)
						G.trap_BotEnterChat(bs.cs, bs.teammate, C.CHAT_TELL)
						bs.arrive_time = G.floattime
					--if the bot wants to crouch
					elseif bs.attackcrouch_time > G.floattime then
						G.trap_EA_Crouch(bs.client)
					--else do some model taunts
					elseif Q.random() < bs.thinktime * 0.05 then
						--do a gesture :)
						G.trap_EA_Gesture(bs.client)
					end
				end
				--if just arrived look at the companion
				if bs.arrive_time > G.floattime - 2 then
					Q.VectorSubtract(entinfo.origin, bs.origin, dir)
					Q.vectoangles(dir, bs.ideal_viewangles)
					bs.ideal_viewangles[2] = bs.ideal_viewangles[2] * 0.5
				--else look strategically around for enemies
				elseif Q.random() < bs.thinktime * 0.8 then
					G.BotRoamGoal(bs, target)
					Q.VectorSubtract(target, bs.origin, dir)
					Q.vectoangles(dir, bs.ideal_viewangles)
					bs.ideal_viewangles[2] = bs.ideal_viewangles[2] * 0.5
				end
				--check if the bot wants to go for air
				if G.BotGoForAir(bs, bs.tfl, bs.teamgoal, 400) ~= 0 then
					G.trap_BotResetLastAvoidReach(bs.ms)
					--time the bot gets to pick up the nearby goal item
					bs.nbg_time = G.floattime + 8
					G.AIEnter_Seek_NBG(bs, "BotLongTermGoal: go for air")
					return 0
				end
				--
				G.trap_BotResetAvoidReach(bs.ms)
				return 0
			end
		end
		--if the entity information is valid (entity in PVS)
		if entinfo.valid ~= 0 then
			areanum = G.BotPointAreaNum(entinfo.origin)
			if areanum ~= 0 and G.trap_AAS_AreaReachability(areanum) ~= 0 then
				--update team goal
				bs.teamgoal.entitynum = bs.teammate
				bs.teamgoal.areanum = areanum
				Q.VectorCopy(entinfo.origin, bs.teamgoal.origin)
				Q.VectorSet(bs.teamgoal.mins, -8, -8, -8)
				Q.VectorSet(bs.teamgoal.maxs, 8, 8, 8)
			end
		end
		--the goal the bot should go for
		S.copy_bot_goal_t(goal, bs.teamgoal)
		--if the companion is NOT visible for too long
		if bs.teammatevisible_time < G.floattime - 60 then
			netname = G.EasyClientName(bs.teammate, C.MAX_NETNAME)
			G.BotAI_BotInitialChat(bs, "accompany_cannotfind", netname)
			G.trap_BotEnterChat(bs.cs, bs.teammate, C.CHAT_TELL)
			bs.ltgtype = 0
			-- just to make sure the bot won't spam this message
			bs.teammatevisible_time = G.floattime
		end
		return 1
	end
	--
	if bs.ltgtype == C.LTG_DEFENDKEYAREA then
		if G.trap_AAS_AreaTravelTimeToGoalArea(bs.areanum, bs.origin,
				bs.teamgoal.areanum, C.TFL_DEFAULT) > bs.defendaway_range then
			bs.defendaway_time = 0
		end
	end
	--For double domination
	if bs.ltgtype == C.LTG_POINTA and
				bs.defendaway_time < G.floattime then
		--check for bot typing status message
		if bs.teammessage_time ~= 0 and bs.teammessage_time < G.floattime then
			buf = G.trap_BotGoalName(bs.teamgoal.number, C.MAX_MESSAGE_SIZE)
			G.BotAI_BotInitialChat(bs, "dd_start_pointa", buf)
			G.trap_BotEnterChat(bs.cs, 0, C.CHAT_TEAM)
			bs.teammessage_time = 0
		end
		--set the bot goal
		S.copy_bot_goal_t(goal, G.ctf_redflag)
		--if very close... go away for some time
		Q.VectorSubtract(goal.origin, bs.origin, dir)
		if Q.VectorLengthSquared(dir) < 70 * 70 then
			G.trap_BotResetAvoidReach(bs.ms)
			bs.defendaway_time = G.floattime + 3 + 3 * Q.random()
			if G.BotHasPersistantPowerupAndWeapon(bs) ~= 0 then
				bs.defendaway_range = 100
			else
				bs.defendaway_range = 350
			end
		end
		return 1
	end
	if bs.ltgtype == C.LTG_POINTB and
				bs.defendaway_time < G.floattime then
		--check for bot typing status message
		if bs.teammessage_time ~= 0 and bs.teammessage_time < G.floattime then
			buf = G.trap_BotGoalName(bs.teamgoal.number, C.MAX_MESSAGE_SIZE)
			G.BotAI_BotInitialChat(bs, "dd_start_pointb", buf)
			G.trap_BotEnterChat(bs.cs, 0, C.CHAT_TEAM)
			bs.teammessage_time = 0
		end
		--set the bot goal
		S.copy_bot_goal_t(goal, G.ctf_blueflag)
		--if very close... go away for some time
		Q.VectorSubtract(goal.origin, bs.origin, dir)
		if Q.VectorLengthSquared(dir) < 70 * 70 then
			G.trap_BotResetAvoidReach(bs.ms)
			bs.defendaway_time = G.floattime + 3 + 3 * Q.random()
			if G.BotHasPersistantPowerupAndWeapon(bs) ~= 0 then
				bs.defendaway_range = 100
			else
				bs.defendaway_range = 350
			end
		end
		return 1
	end
	--if defending a key area
	if bs.ltgtype == C.LTG_DEFENDKEYAREA and not retreat and
				bs.defendaway_time < G.floattime then
		--check for bot typing status message
		if bs.teammessage_time ~= 0 and bs.teammessage_time < G.floattime then
			buf = G.trap_BotGoalName(bs.teamgoal.number, C.MAX_MESSAGE_SIZE)
			G.BotAI_BotInitialChat(bs, "defend_start", buf)
			G.trap_BotEnterChat(bs.cs, 0, C.CHAT_TEAM)
			G.BotVoiceChatOnly(bs, -1, VC.ONDEFENSE)
			bs.teammessage_time = 0
		end
		--set the bot goal
		S.copy_bot_goal_t(goal, bs.teamgoal)
		--stop after 2 minutes
		if bs.teamgoal_time < G.floattime then
			buf = G.trap_BotGoalName(bs.teamgoal.number, C.MAX_MESSAGE_SIZE)
			G.BotAI_BotInitialChat(bs, "defend_stop", buf)
			G.trap_BotEnterChat(bs.cs, 0, C.CHAT_TEAM)
			bs.ltgtype = 0
		end
		--if very close... go away for some time
		Q.VectorSubtract(goal.origin, bs.origin, dir)
		if Q.VectorLengthSquared(dir) < 70 * 70 then
			G.trap_BotResetAvoidReach(bs.ms)
			bs.defendaway_time = G.floattime + 3 + 3 * Q.random()
			if G.BotHasPersistantPowerupAndWeapon(bs) ~= 0 then
				bs.defendaway_range = 100
			else
				bs.defendaway_range = 350
			end
		end
		return 1
	end
	--going to kill someone
	if bs.ltgtype == C.LTG_KILL and not retreat then
		--check for bot typing status message
		if bs.teammessage_time ~= 0 and bs.teammessage_time < G.floattime then
			buf = G.EasyClientName(bs.teamgoal.entitynum, C.MAX_MESSAGE_SIZE)
			G.BotAI_BotInitialChat(bs, "kill_start", buf)
			G.trap_BotEnterChat(bs.cs, bs.decisionmaker, C.CHAT_TELL)
			bs.teammessage_time = 0
		end
		--
		if bs.killedenemy_time > bs.teamgoal_time - C.TEAM_KILL_SOMEONE and bs.lastkilledplayer == bs.teamgoal.entitynum then
			buf = G.EasyClientName(bs.teamgoal.entitynum, C.MAX_MESSAGE_SIZE)
			G.BotAI_BotInitialChat(bs, "kill_done", buf)
			G.trap_BotEnterChat(bs.cs, bs.decisionmaker, C.CHAT_TELL)
			bs.ltgtype = 0
		end
		--
		if bs.teamgoal_time < G.floattime then
			bs.ltgtype = 0
		end
		--just roam around
		return G.BotGetItemLongTermGoal(bs, tfl, goal)
	end
	--get an item
	if bs.ltgtype == C.LTG_GETITEM and not retreat then
		--check for bot typing status message
		if bs.teammessage_time ~= 0 and bs.teammessage_time < G.floattime then
			buf = G.trap_BotGoalName(bs.teamgoal.number, C.MAX_MESSAGE_SIZE)
			G.BotAI_BotInitialChat(bs, "getitem_start", buf)
			G.trap_BotEnterChat(bs.cs, bs.decisionmaker, C.CHAT_TELL)
			G.BotVoiceChatOnly(bs, bs.decisionmaker, VC.YES)
			G.trap_EA_Action(bs.client, C.ACTION_AFFIRMATIVE)
			bs.teammessage_time = 0
		end
		--set the bot goal
		S.copy_bot_goal_t(goal, bs.teamgoal)
		--stop after some time
		if bs.teamgoal_time < G.floattime then
			bs.ltgtype = 0
		end
		--
		if G.trap_BotItemGoalInVisButNotVisible(bs.entitynum, bs.eye, bs.viewangles, goal) ~= 0 then
			buf = G.trap_BotGoalName(bs.teamgoal.number, C.MAX_MESSAGE_SIZE)
			G.BotAI_BotInitialChat(bs, "getitem_notthere", buf)
			G.trap_BotEnterChat(bs.cs, bs.decisionmaker, C.CHAT_TELL)
			bs.ltgtype = 0
		elseif G.BotReachedGoal(bs, goal) ~= 0 then
			buf = G.trap_BotGoalName(bs.teamgoal.number, C.MAX_MESSAGE_SIZE)
			G.BotAI_BotInitialChat(bs, "getitem_gotit", buf)
			G.trap_BotEnterChat(bs.cs, bs.decisionmaker, C.CHAT_TELL)
			bs.ltgtype = 0
		end
		return 1
	end
	--if camping somewhere
	if (bs.ltgtype == C.LTG_CAMP or bs.ltgtype == C.LTG_CAMPORDER) and not retreat then
		--check for bot typing status message
		if bs.teammessage_time ~= 0 and bs.teammessage_time < G.floattime then
			if bs.ltgtype == C.LTG_CAMPORDER then
				netname = G.EasyClientName(bs.teammate, C.MAX_NETNAME)
				G.BotAI_BotInitialChat(bs, "camp_start", netname)
				G.trap_BotEnterChat(bs.cs, bs.decisionmaker, C.CHAT_TELL)
				G.BotVoiceChatOnly(bs, bs.decisionmaker, VC.YES)
				G.trap_EA_Action(bs.client, C.ACTION_AFFIRMATIVE)
			end
			bs.teammessage_time = 0
		end
		--set the bot goal
		S.copy_bot_goal_t(goal, bs.teamgoal)
		--
		if bs.teamgoal_time < G.floattime then
			if bs.ltgtype == C.LTG_CAMPORDER then
				G.BotAI_BotInitialChat(bs, "camp_stop")
				G.trap_BotEnterChat(bs.cs, bs.decisionmaker, C.CHAT_TELL)
			end
			bs.ltgtype = 0
		end
		--if really near the camp spot
		Q.VectorSubtract(goal.origin, bs.origin, dir)
		if Q.VectorLengthSquared(dir) < 60 * 60 then
			--if not arrived yet
			if bs.arrive_time == 0 then
				if bs.ltgtype == C.LTG_CAMPORDER then
					netname = G.EasyClientName(bs.teammate, C.MAX_NETNAME)
					G.BotAI_BotInitialChat(bs, "camp_arrive", netname)
					G.trap_BotEnterChat(bs.cs, bs.decisionmaker, C.CHAT_TELL)
					G.BotVoiceChatOnly(bs, bs.decisionmaker, VC.INPOSITION)
				end
				bs.arrive_time = G.floattime
			end
			--look strategically around for enemies
			if Q.random() < bs.thinktime * 0.8 then
				G.BotRoamGoal(bs, target)
				Q.VectorSubtract(target, bs.origin, dir)
				Q.vectoangles(dir, bs.ideal_viewangles)
				bs.ideal_viewangles[2] = bs.ideal_viewangles[2] * 0.5
			end
			--check if the bot wants to crouch
			--don't crouch if crouched less than 5 seconds ago
			if bs.attackcrouch_time < G.floattime - 5 then
				croucher = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_CROUCHER, 0, 1)
				if Q.random() < bs.thinktime * croucher then
					bs.attackcrouch_time = G.floattime + 5 + croucher * 15
				end
			end
			--if the bot wants to crouch
			if bs.attackcrouch_time > G.floattime then
				G.trap_EA_Crouch(bs.client)
			end
			--don't crouch when swimming
			if G.trap_AAS_Swimming(bs.origin) ~= 0 then bs.attackcrouch_time = G.floattime - 1 end
			--make sure the bot is not gonna drown
			if bit32.band(G.trap_PointContents(bs.eye, bs.entitynum), bit32.bor(C.CONTENTS_WATER, C.CONTENTS_SLIME, C.CONTENTS_LAVA)) ~= 0 then
				if bs.ltgtype == C.LTG_CAMPORDER then
					G.BotAI_BotInitialChat(bs, "camp_stop")
					G.trap_BotEnterChat(bs.cs, bs.decisionmaker, C.CHAT_TELL)
					--
					if bs.lastgoal_ltgtype == C.LTG_CAMPORDER then
						bs.lastgoal_ltgtype = 0
					end
				end
				bs.ltgtype = 0
			end
			--
			if bs.camp_range > 0 then
				--FIXME: move around a bit
			end
			--
			G.trap_BotResetAvoidReach(bs.ms)
			return 0
		end
		return 1
	end
	--patrolling along several waypoints
	if bs.ltgtype == C.LTG_PATROL and not retreat then
		--check for bot typing status message
		if bs.teammessage_time ~= 0 and bs.teammessage_time < G.floattime then
			buf = ""
			local wp = bs.patrolpoints
			while wp ~= nil do
				buf = buf .. wp.name
				if wp.next ~= nil then buf = buf .. " to " end
				wp = wp.next
			end
			G.BotAI_BotInitialChat(bs, "patrol_start", buf)
			G.trap_BotEnterChat(bs.cs, bs.decisionmaker, C.CHAT_TELL)
			G.BotVoiceChatOnly(bs, bs.decisionmaker, VC.YES)
			G.trap_EA_Action(bs.client, C.ACTION_AFFIRMATIVE)
			bs.teammessage_time = 0
		end
		--
		if bs.curpatrolpoint == nil then
			bs.ltgtype = 0
			return 0
		end
		--if the bot touches the current goal
		if G.trap_BotTouchingGoal(bs.origin, bs.curpatrolpoint.goal) ~= 0 then
			if bit32.band(bs.patrolflags, C.PATROL_BACK) ~= 0 then
				if bs.curpatrolpoint.prev ~= nil then
					bs.curpatrolpoint = bs.curpatrolpoint.prev
				else
					bs.curpatrolpoint = bs.curpatrolpoint.next
					bs.patrolflags = bit32.band(bs.patrolflags, bit32.bnot(C.PATROL_BACK))
				end
			else
				if bs.curpatrolpoint.next ~= nil then
					bs.curpatrolpoint = bs.curpatrolpoint.next
				else
					bs.curpatrolpoint = bs.curpatrolpoint.prev
					bs.patrolflags = bit32.bor(bs.patrolflags, C.PATROL_BACK)
				end
			end
		end
		--stop after 5 minutes
		if bs.teamgoal_time < G.floattime then
			G.BotAI_BotInitialChat(bs, "patrol_stop")
			G.trap_BotEnterChat(bs.cs, bs.decisionmaker, C.CHAT_TELL)
			bs.ltgtype = 0
		end
		if bs.curpatrolpoint == nil then
			bs.ltgtype = 0
			return 0
		end
		S.copy_bot_goal_t(goal, bs.curpatrolpoint.goal)
		return 1
	end

	if G.gametype == C.GT_CTF or G.gametype == C.GT_CTF_ELIMINATION then
		--if going for enemy flag
		if bs.ltgtype == C.LTG_GETFLAG then
			--check for bot typing status message
			if bs.teammessage_time ~= 0 and bs.teammessage_time < G.floattime then
				G.BotAI_BotInitialChat(bs, "captureflag_start")
				G.trap_BotEnterChat(bs.cs, 0, C.CHAT_TEAM)
				G.BotVoiceChatOnly(bs, -1, VC.ONGETFLAG)
				bs.teammessage_time = 0
			end
			--
			local team = G.BotTeam(bs)
			if team == C.TEAM_RED then
				S.copy_bot_goal_t(goal, G.ctf_blueflag)
			elseif team == C.TEAM_BLUE then
				S.copy_bot_goal_t(goal, G.ctf_redflag)
			else
				bs.ltgtype = 0
				return 0
			end
			--if touching the flag
			if G.trap_BotTouchingGoal(bs.origin, goal) ~= 0 then
				-- make sure the bot knows the flag isn't there anymore
				local team2 = G.BotTeam(bs)
				if team2 == C.TEAM_RED then
					bs.blueflagstatus = 1
				elseif team2 == C.TEAM_BLUE then
					bs.redflagstatus = 1
				end
				bs.ltgtype = 0
			end
			--stop after 3 minutes
			if bs.teamgoal_time < G.floattime then
				bs.ltgtype = 0
			end
			G.BotAlternateRoute(bs, goal)
			return 1
		end
		--if rushing to the base
		if bs.ltgtype == C.LTG_RUSHBASE and bs.rushbaseaway_time < G.floattime then
			local team = G.BotTeam(bs)
			if team == C.TEAM_RED then
				S.copy_bot_goal_t(goal, G.ctf_redflag)
			elseif team == C.TEAM_BLUE then
				S.copy_bot_goal_t(goal, G.ctf_blueflag)
			else
				bs.ltgtype = 0
				return 0
			end
			--if not carrying the flag anymore
			if G.BotCTFCarryingFlag(bs) == 0 then bs.ltgtype = 0 end
			--quit rushing after 2 minutes
			if bs.teamgoal_time < G.floattime then bs.ltgtype = 0 end
			--if touching the base flag the bot should loose the enemy flag
			if G.trap_BotTouchingGoal(bs.origin, goal) ~= 0 then
				--if the bot is still carrying the enemy flag then the
				--base flag is gone, now just walk near the base a bit
				if G.BotCTFCarryingFlag(bs) ~= 0 then
					G.trap_BotResetAvoidReach(bs.ms)
					bs.rushbaseaway_time = G.floattime + 5 + 10 * Q.random()
					--FIXME: add chat to tell the others to get back the flag
				else
					bs.ltgtype = 0
				end
			end
			G.BotAlternateRoute(bs, goal)
			return 1
		end
		--returning flag
		if bs.ltgtype == C.LTG_RETURNFLAG then
			--check for bot typing status message
			if bs.teammessage_time ~= 0 and bs.teammessage_time < G.floattime then
				G.BotAI_BotInitialChat(bs, "returnflag_start")
				G.trap_BotEnterChat(bs.cs, 0, C.CHAT_TEAM)
				G.BotVoiceChatOnly(bs, -1, VC.ONRETURNFLAG)
				bs.teammessage_time = 0
			end
			--
			local team = G.BotTeam(bs)
			if team == C.TEAM_RED then
				S.copy_bot_goal_t(goal, G.ctf_blueflag)
			elseif team == C.TEAM_BLUE then
				S.copy_bot_goal_t(goal, G.ctf_redflag)
			else
				bs.ltgtype = 0
				return 0
			end
			--if touching the flag
			if G.trap_BotTouchingGoal(bs.origin, goal) ~= 0 then bs.ltgtype = 0 end
			--stop after 3 minutes
			if bs.teamgoal_time < G.floattime then
				bs.ltgtype = 0
			end
			G.BotAlternateRoute(bs, goal)
			return 1
		end
	elseif G.gametype == C.GT_1FCTF then
		if bs.ltgtype == C.LTG_GETFLAG then
			--check for bot typing status message
			if bs.teammessage_time ~= 0 and bs.teammessage_time < G.floattime then
				G.BotAI_BotInitialChat(bs, "captureflag_start")
				G.trap_BotEnterChat(bs.cs, 0, C.CHAT_TEAM)
				G.BotVoiceChatOnly(bs, -1, VC.ONGETFLAG)
				bs.teammessage_time = 0
			end
			S.copy_bot_goal_t(goal, G.ctf_neutralflag)
			--if touching the flag
			if G.trap_BotTouchingGoal(bs.origin, goal) ~= 0 then
				bs.ltgtype = 0
			end
			--stop after 3 minutes
			if bs.teamgoal_time < G.floattime then
				bs.ltgtype = 0
			end
			return 1
		end
		--if rushing to the base
		if bs.ltgtype == C.LTG_RUSHBASE then
			local team = G.BotTeam(bs)
			if team == C.TEAM_RED then
				S.copy_bot_goal_t(goal, G.ctf_blueflag)
			elseif team == C.TEAM_BLUE then
				S.copy_bot_goal_t(goal, G.ctf_redflag)
			else
				bs.ltgtype = 0
				return 0
			end
			--if not carrying the flag anymore
			if G.Bot1FCTFCarryingFlag(bs) == 0 then
				bs.ltgtype = 0
			end
			--quit rushing after 2 minutes
			if bs.teamgoal_time < G.floattime then
				bs.ltgtype = 0
			end
			--if touching the base flag the bot should loose the enemy flag
			if G.trap_BotTouchingGoal(bs.origin, goal) ~= 0 then
				bs.ltgtype = 0
			end
			G.BotAlternateRoute(bs, goal)
			return 1
		end
		--attack the enemy base
		if bs.ltgtype == C.LTG_ATTACKENEMYBASE and
				bs.attackaway_time < G.floattime then
			--check for bot typing status message
			if bs.teammessage_time ~= 0 and bs.teammessage_time < G.floattime then
				G.BotAI_BotInitialChat(bs, "attackenemybase_start")
				G.trap_BotEnterChat(bs.cs, 0, C.CHAT_TEAM)
				G.BotVoiceChatOnly(bs, -1, VC.ONOFFENSE)
				bs.teammessage_time = 0
			end
			local team = G.BotTeam(bs)
			if team == C.TEAM_RED then
				S.copy_bot_goal_t(goal, G.ctf_blueflag)
			elseif team == C.TEAM_BLUE then
				S.copy_bot_goal_t(goal, G.ctf_redflag)
			else
				bs.ltgtype = 0
				return 0
			end
			--quit rushing after 2 minutes
			if bs.teamgoal_time < G.floattime then
				bs.ltgtype = 0
			end
			--if touching the base flag the bot should loose the enemy flag
			if G.trap_BotTouchingGoal(bs.origin, goal) ~= 0 then
				bs.attackaway_time = G.floattime + 2 + 5 * Q.random()
			end
			return 1
		end
		--returning flag
		if bs.ltgtype == C.LTG_RETURNFLAG then
			--check for bot typing status message
			if bs.teammessage_time ~= 0 and bs.teammessage_time < G.floattime then
				G.BotAI_BotInitialChat(bs, "returnflag_start")
				G.trap_BotEnterChat(bs.cs, 0, C.CHAT_TEAM)
				G.BotVoiceChatOnly(bs, -1, VC.ONRETURNFLAG)
				bs.teammessage_time = 0
			end
			--
			if bs.teamgoal_time < G.floattime then
				bs.ltgtype = 0
			end
			--just roam around
			return G.BotGetItemLongTermGoal(bs, tfl, goal)
		end
	elseif G.gametype == C.GT_OBELISK then
		if bs.ltgtype == C.LTG_ATTACKENEMYBASE and
				bs.attackaway_time < G.floattime then
			--check for bot typing status message
			if bs.teammessage_time ~= 0 and bs.teammessage_time < G.floattime then
				G.BotAI_BotInitialChat(bs, "attackenemybase_start")
				G.trap_BotEnterChat(bs.cs, 0, C.CHAT_TEAM)
				G.BotVoiceChatOnly(bs, -1, VC.ONOFFENSE)
				bs.teammessage_time = 0
			end
			local team = G.BotTeam(bs)
			if team == C.TEAM_RED then
				S.copy_bot_goal_t(goal, G.blueobelisk)
			elseif team == C.TEAM_BLUE then
				S.copy_bot_goal_t(goal, G.redobelisk)
			else
				bs.ltgtype = 0
				return 0
			end
			--if the bot no longer wants to attack the obelisk
			if G.BotFeelingBad(bs) > 50 then
				return G.BotGetItemLongTermGoal(bs, tfl, goal)
			end
			--if touching the obelisk
			if G.trap_BotTouchingGoal(bs.origin, goal) ~= 0 then
				bs.attackaway_time = G.floattime + 3 + 5 * Q.random()
			end
			-- or very close to the obelisk
			Q.VectorSubtract(bs.origin, goal.origin, dir)
			if Q.VectorLengthSquared(dir) < 60 * 60 then
				bs.attackaway_time = G.floattime + 3 + 5 * Q.random()
			end
			--quit rushing after 2 minutes
			if bs.teamgoal_time < G.floattime then
				bs.ltgtype = 0
			end
			G.BotAlternateRoute(bs, goal)
			--just move towards the obelisk
			return 1
		end
	elseif G.gametype == C.GT_HARVESTER then
		--if rushing to the base
		if bs.ltgtype == C.LTG_RUSHBASE then
			local team = G.BotTeam(bs)
			if team == C.TEAM_RED then
				S.copy_bot_goal_t(goal, G.blueobelisk)
			elseif team == C.TEAM_BLUE then
				S.copy_bot_goal_t(goal, G.redobelisk)
			else
				G.BotGoHarvest(bs)
				return 0
			end
			--if not carrying any cubes
			if G.BotHarvesterCarryingCubes(bs) == 0 then
				G.BotGoHarvest(bs)
				return 0
			end
			--quit rushing after 2 minutes
			if bs.teamgoal_time < G.floattime then
				G.BotGoHarvest(bs)
				return 0
			end
			--if touching the base flag the bot should loose the enemy flag
			if G.trap_BotTouchingGoal(bs.origin, goal) ~= 0 then
				G.BotGoHarvest(bs)
				return 0
			end
			G.BotAlternateRoute(bs, goal)
			return 1
		end
		--attack the enemy base
		if bs.ltgtype == C.LTG_ATTACKENEMYBASE and
				bs.attackaway_time < G.floattime then
			--check for bot typing status message
			if bs.teammessage_time ~= 0 and bs.teammessage_time < G.floattime then
				G.BotAI_BotInitialChat(bs, "attackenemybase_start")
				G.trap_BotEnterChat(bs.cs, 0, C.CHAT_TEAM)
				G.BotVoiceChatOnly(bs, -1, VC.ONOFFENSE)
				bs.teammessage_time = 0
			end
			local team = G.BotTeam(bs)
			if team == C.TEAM_RED then
				S.copy_bot_goal_t(goal, G.blueobelisk)
			elseif team == C.TEAM_BLUE then
				S.copy_bot_goal_t(goal, G.redobelisk)
			else
				bs.ltgtype = 0
				return 0
			end
			--quit rushing after 2 minutes
			if bs.teamgoal_time < G.floattime then
				bs.ltgtype = 0
			end
			--if touching the base flag the bot should loose the enemy flag
			if G.trap_BotTouchingGoal(bs.origin, goal) ~= 0 then
				bs.attackaway_time = G.floattime + 2 + 5 * Q.random()
			end
			return 1
		end
		--harvest cubes
		if bs.ltgtype == C.LTG_HARVEST and
			bs.harvestaway_time < G.floattime then
			--check for bot typing status message
			if bs.teammessage_time ~= 0 and bs.teammessage_time < G.floattime then
				G.BotAI_BotInitialChat(bs, "harvest_start")
				G.trap_BotEnterChat(bs.cs, 0, C.CHAT_TEAM)
				G.BotVoiceChatOnly(bs, -1, VC.ONOFFENSE)
				bs.teammessage_time = 0
			end
			S.copy_bot_goal_t(goal, G.neutralobelisk)
			--
			if bs.teamgoal_time < G.floattime then
				bs.ltgtype = 0
			end
			--
			if G.trap_BotTouchingGoal(bs.origin, goal) ~= 0 then
				bs.harvestaway_time = G.floattime + 4 + 3 * Q.random()
			end
			return 1
		end
	end
	--normal goal stuff
	return G.BotGetItemLongTermGoal(bs, tfl, goal)
end

return nil
