--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/ai_dmq3.c, part 3 of 7).

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
-- Luau port of ai_dmq3.c, part 3 of 7. Client names, inventory, item use, waypoints, aggression.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local SF = G.FileStatics("ai_dmq3")

local KAMIKAZE_DIST = 1024
local MAX_WAYPOINTS = 128
-- menudef.h voice chat names (not in the shared defs)
local VOICECHAT_WANTONOFFENSE = "wantonoffense"
local VOICECHAT_WANTONDEFENSE = "wantondefense"
-- bg_public.h gametype_t value (not in the shared defs)
local GT_POSSESSION = 13

local function b2i(b)
	if b then
		return 1
	end
	return 0
end

function G.EasyClientName(client, size)
	local name = G.ClientName(client, 128)
	local out = {}
	for i = 1, #name do
		out[i] = string.char(bit32.band(string.byte(name, i), 127))
	end
	name = table.concat(out)
	--remove all spaces
	name = string.gsub(name, " ", "")
	--check for [x] and ]x[ clan names
	local str1 = string.find(name, "[", 1, true)
	local str2 = string.find(name, "]", 1, true)
	if str1 and str2 then
		if str2 > str1 then
			name = string.sub(name, 1, str1 - 1) .. string.sub(name, str2 + 1)
		else
			name = string.sub(name, 1, str2 - 1) .. string.sub(name, str1 + 1)
		end
	end
	--remove Mr prefix
	local c0 = string.byte(name, 1) or 0
	local c1 = string.byte(name, 2) or 0
	if (c0 == 109 or c0 == 77) and (c1 == 114 or c1 == 82) then
		name = string.sub(name, 3)
	end
	--only allow lower case alphabet characters
	local res = {}
	for i = 1, #name do
		local c = string.byte(name, i)
		if (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95 then
			res[#res + 1] = string.char(c)
		elseif c >= 65 and c <= 90 then
			res[#res + 1] = string.char(c + 32)
		end
	end
	return QS.Q_strncpyz(table.concat(res), size)
end

function G.BotSynonymContext(bs)
	local gametype = G.gametype
	local context = bit32.bor(C.CONTEXT_NORMAL, C.CONTEXT_NEARBYITEM, C.CONTEXT_NAMES)
	--
	if gametype == C.GT_CTF or gametype == C.GT_CTF_ELIMINATION or gametype == C.GT_1FCTF then
		if G.BotTeam(bs) == C.TEAM_RED then
			context = bit32.bor(context, C.CONTEXT_CTFREDTEAM)
		else
			context = bit32.bor(context, C.CONTEXT_CTFBLUETEAM)
		end
	elseif gametype == C.GT_OBELISK then
		if G.BotTeam(bs) == C.TEAM_RED then
			context = bit32.bor(context, C.CONTEXT_OBELISKREDTEAM)
		else
			context = bit32.bor(context, C.CONTEXT_OBELISKBLUETEAM)
		end
	elseif gametype == C.GT_HARVESTER then
		if G.BotTeam(bs) == C.TEAM_RED then
			context = bit32.bor(context, C.CONTEXT_HARVESTERREDTEAM)
		else
			context = bit32.bor(context, C.CONTEXT_HARVESTERBLUETEAM)
		end
	end
	return context
end

function G.BotChooseWeapon(bs)
	local newweaponnum

	if bs.cur_ps.weaponstate == C.WEAPON_RAISING or bs.cur_ps.weaponstate == C.WEAPON_DROPPING then
		G.trap_EA_SelectWeapon(bs.client, bs.weaponnum)
	else
		if G.g_instantgib.integer ~= 0 then
			newweaponnum = C.WP_RAILGUN
		elseif G.g_rockets.integer ~= 0 then
			newweaponnum = C.WP_ROCKET_LAUNCHER
		else
			newweaponnum = G.trap_BotChooseBestFightWeapon(bs.ws, bs.inventory)
		end
		if bs.weaponnum ~= newweaponnum then
			bs.weaponchange_time = G.floattime
		end
		bs.weaponnum = newweaponnum
		G.trap_EA_SelectWeapon(bs.client, bs.weaponnum)
	end
end

function G.BotSetupForMovement(bs)
	local initmove = S.bot_initmove_t()

	Q.VectorCopy(bs.cur_ps.origin, initmove.origin)
	Q.VectorCopy(bs.cur_ps.velocity, initmove.velocity)
	Q.VectorClear(initmove.viewoffset)
	initmove.viewoffset[2] = initmove.viewoffset[2] + bs.cur_ps.viewheight
	initmove.entitynum = bs.entitynum
	initmove.client = bs.client
	initmove.thinktime = bs.thinktime
	--set the onground flag
	if bs.cur_ps.groundEntityNum ~= C.ENTITYNUM_NONE then
		initmove.or_moveflags = bit32.bor(initmove.or_moveflags, C.MFL_ONGROUND)
	end
	--set the teleported flag
	if bit32.band(bs.cur_ps.pm_flags, C.PMF_TIME_KNOCKBACK) ~= 0 and bs.cur_ps.pm_time > 0 then
		initmove.or_moveflags = bit32.bor(initmove.or_moveflags, C.MFL_TELEPORTED)
	end
	--set the waterjump flag
	if bit32.band(bs.cur_ps.pm_flags, C.PMF_TIME_WATERJUMP) ~= 0 and bs.cur_ps.pm_time > 0 then
		initmove.or_moveflags = bit32.bor(initmove.or_moveflags, C.MFL_WATERJUMP)
	end
	--set presence type
	if bit32.band(bs.cur_ps.pm_flags, C.PMF_DUCKED) ~= 0 then
		initmove.presencetype = C.PRESENCE_CROUCH
	else
		initmove.presencetype = C.PRESENCE_NORMAL
	end
	--
	if bs.walker > 0.5 then
		initmove.or_moveflags = bit32.bor(initmove.or_moveflags, C.MFL_WALK)
	end
	--
	Q.VectorCopy(bs.viewangles, initmove.viewangles)
	--
	G.trap_BotInitMoveState(bs.ms, initmove)
end

function G.BotCheckItemPickup(bs, oldinventory)
	local gametype = G.gametype
	if gametype <= C.GT_TEAM and G.g_ffa_gt == 0 then
		return
	end

	local offence = -1
	-- go into offence if picked up the kamikaze or invulnerability
	if oldinventory[C.INVENTORY_KAMIKAZE] == 0 and bs.inventory[C.INVENTORY_KAMIKAZE] >= 1 then
		offence = 1
	end
	if oldinventory[C.INVENTORY_INVULNERABILITY] == 0 and bs.inventory[C.INVENTORY_INVULNERABILITY] >= 1 then
		offence = 1
	end
	-- if not already wearing the kamikaze or invulnerability
	if bs.inventory[C.INVENTORY_KAMIKAZE] == 0 and bs.inventory[C.INVENTORY_INVULNERABILITY] == 0 then
		if oldinventory[C.INVENTORY_SCOUT] == 0 and bs.inventory[C.INVENTORY_SCOUT] >= 1 then
			offence = 1
		end
		if oldinventory[C.INVENTORY_GUARD] == 0 and bs.inventory[C.INVENTORY_GUARD] >= 1 then
			offence = 1
		end
		if oldinventory[C.INVENTORY_DOUBLER] == 0 and bs.inventory[C.INVENTORY_DOUBLER] >= 1 then
			offence = 0
		end
		if oldinventory[C.INVENTORY_AMMOREGEN] == 0 and bs.inventory[C.INVENTORY_AMMOREGEN] >= 1 then
			offence = 0
		end
	end

	if offence >= 0 then
		local leader = G.ClientFromName(bs.teamleader)
		if offence ~= 0 then
			if bit32.band(bs.teamtaskpreference, C.TEAMTP_ATTACKER) == 0 then
				-- if we have a bot team leader
				if G.BotTeamLeader(bs) ~= 0 then
					-- tell the leader we want to be on offence
					G.BotVoiceChat(bs, leader, VOICECHAT_WANTONOFFENSE)
				elseif G.g_spSkill.integer <= 3 then
					if
						bs.ltgtype ~= C.LTG_GETFLAG
						and bs.ltgtype ~= C.LTG_ATTACKENEMYBASE
						and bs.ltgtype ~= C.LTG_HARVEST
						and (
							(gametype ~= C.GT_CTF and gametype ~= C.GT_CTF_ELIMINATION)
							or (bs.redflagstatus == 0 and bs.blueflagstatus == 0)
						)
						and (gametype ~= C.GT_1FCTF or bs.neutralflagstatus == 0)
					then
						-- tell the leader we want to be on offence
						G.BotVoiceChat(bs, leader, VOICECHAT_WANTONOFFENSE)
					end
					bs.teamtaskpreference = bit32.bor(bs.teamtaskpreference, C.TEAMTP_ATTACKER)
				end
			end
			bs.teamtaskpreference = bit32.band(bs.teamtaskpreference, bit32.bnot(C.TEAMTP_DEFENDER))
		else
			if bit32.band(bs.teamtaskpreference, C.TEAMTP_DEFENDER) == 0 then
				-- if we have a bot team leader
				if G.BotTeamLeader(bs) ~= 0 then
					-- tell the leader we want to be on defense
					G.BotVoiceChat(bs, -1, VOICECHAT_WANTONDEFENSE)
				elseif
					G.g_spSkill.integer <= 3
					and bs.ltgtype ~= C.LTG_DEFENDKEYAREA
					and (
						(gametype ~= C.GT_CTF and gametype ~= C.GT_CTF_ELIMINATION)
						or (bs.redflagstatus == 0 and bs.blueflagstatus == 0)
					)
					and (gametype ~= C.GT_1FCTF or bs.neutralflagstatus == 0)
				then
					-- tell the leader we want to be on defense
					G.BotVoiceChat(bs, -1, VOICECHAT_WANTONDEFENSE)
				end
				bs.teamtaskpreference = bit32.bor(bs.teamtaskpreference, C.TEAMTP_DEFENDER)
			end
			bs.teamtaskpreference = bit32.band(bs.teamtaskpreference, bit32.bnot(C.TEAMTP_ATTACKER))
		end
	end
end

function G.BotUpdateInventory(bs)
	local oldinventory = {}
	for i = 0, C.MAX_ITEMS - 1 do
		oldinventory[i] = bs.inventory[i]
	end
	local inv = bs.inventory
	local ps = bs.cur_ps
	local function hasWeapon(wp)
		return b2i(bit32.band(ps.stats[C.STAT_WEAPONS], bit32.lshift(1, wp)) ~= 0)
	end
	--armor
	inv[C.INVENTORY_ARMOR] = ps.stats[C.STAT_ARMOR]
	--weapons
	inv[C.INVENTORY_GAUNTLET] = hasWeapon(C.WP_GAUNTLET)
	inv[C.INVENTORY_SHOTGUN] = hasWeapon(C.WP_SHOTGUN)
	inv[C.INVENTORY_MACHINEGUN] = hasWeapon(C.WP_MACHINEGUN)
	inv[C.INVENTORY_GRENADELAUNCHER] = hasWeapon(C.WP_GRENADE_LAUNCHER)
	inv[C.INVENTORY_ROCKETLAUNCHER] = hasWeapon(C.WP_ROCKET_LAUNCHER)
	inv[C.INVENTORY_LIGHTNING] = hasWeapon(C.WP_LIGHTNING)
	inv[C.INVENTORY_RAILGUN] = hasWeapon(C.WP_RAILGUN)
	inv[C.INVENTORY_PLASMAGUN] = hasWeapon(C.WP_PLASMAGUN)
	inv[C.INVENTORY_BFG10K] = hasWeapon(C.WP_BFG)
	inv[C.INVENTORY_GRAPPLINGHOOK] = hasWeapon(C.WP_GRAPPLING_HOOK)
	inv[C.INVENTORY_NAILGUN] = hasWeapon(C.WP_NAILGUN)
	inv[C.INVENTORY_PROXLAUNCHER] = hasWeapon(C.WP_PROX_LAUNCHER)
	inv[C.INVENTORY_CHAINGUN] = hasWeapon(C.WP_CHAINGUN)
	--ammo
	inv[C.INVENTORY_SHELLS] = ps.ammo[C.WP_SHOTGUN]
	inv[C.INVENTORY_BULLETS] = ps.ammo[C.WP_MACHINEGUN]
	inv[C.INVENTORY_GRENADES] = ps.ammo[C.WP_GRENADE_LAUNCHER]
	inv[C.INVENTORY_CELLS] = ps.ammo[C.WP_PLASMAGUN]
	inv[C.INVENTORY_LIGHTNINGAMMO] = ps.ammo[C.WP_LIGHTNING]
	inv[C.INVENTORY_ROCKETS] = ps.ammo[C.WP_ROCKET_LAUNCHER]
	inv[C.INVENTORY_SLUGS] = ps.ammo[C.WP_RAILGUN]
	inv[C.INVENTORY_BFGAMMO] = ps.ammo[C.WP_BFG]
	inv[C.INVENTORY_NAILS] = ps.ammo[C.WP_NAILGUN]
	inv[C.INVENTORY_MINES] = ps.ammo[C.WP_PROX_LAUNCHER]
	inv[C.INVENTORY_BELT] = ps.ammo[C.WP_CHAINGUN]
	--powerups
	inv[C.INVENTORY_HEALTH] = ps.stats[C.STAT_HEALTH]
	inv[C.INVENTORY_TELEPORTER] = b2i(ps.stats[C.STAT_HOLDABLE_ITEM] == C.MODELINDEX_TELEPORTER)
	inv[C.INVENTORY_MEDKIT] = b2i(ps.stats[C.STAT_HOLDABLE_ITEM] == C.MODELINDEX_MEDKIT)
	inv[C.INVENTORY_KAMIKAZE] = b2i(ps.stats[C.STAT_HOLDABLE_ITEM] == C.MODELINDEX_KAMIKAZE)
	inv[C.INVENTORY_PORTAL] = b2i(ps.stats[C.STAT_HOLDABLE_ITEM] == C.MODELINDEX_PORTAL)
	inv[C.INVENTORY_INVULNERABILITY] = b2i(ps.stats[C.STAT_HOLDABLE_ITEM] == C.MODELINDEX_INVULNERABILITY)
	inv[C.INVENTORY_QUAD] = b2i(ps.powerups[C.PW_QUAD] ~= 0)
	inv[C.INVENTORY_ENVIRONMENTSUIT] = b2i(ps.powerups[C.PW_BATTLESUIT] ~= 0)
	inv[C.INVENTORY_HASTE] = b2i(ps.powerups[C.PW_HASTE] ~= 0)
	inv[C.INVENTORY_INVISIBILITY] = b2i(ps.powerups[C.PW_INVIS] ~= 0)
	inv[C.INVENTORY_REGEN] = b2i(ps.powerups[C.PW_REGEN] ~= 0)
	inv[C.INVENTORY_FLIGHT] = b2i(ps.powerups[C.PW_FLIGHT] ~= 0)
	inv[C.INVENTORY_SCOUT] = b2i(ps.stats[C.STAT_PERSISTANT_POWERUP] == C.MODELINDEX_SCOUT)
	inv[C.INVENTORY_GUARD] = b2i(ps.stats[C.STAT_PERSISTANT_POWERUP] == C.MODELINDEX_GUARD)
	inv[C.INVENTORY_DOUBLER] = b2i(ps.stats[C.STAT_PERSISTANT_POWERUP] == C.MODELINDEX_DOUBLER)
	inv[C.INVENTORY_AMMOREGEN] = b2i(ps.stats[C.STAT_PERSISTANT_POWERUP] == C.MODELINDEX_AMMOREGEN)
	inv[C.INVENTORY_REDFLAG] = b2i(ps.powerups[C.PW_REDFLAG] ~= 0)
	inv[C.INVENTORY_BLUEFLAG] = b2i(ps.powerups[C.PW_BLUEFLAG] ~= 0)
	inv[C.INVENTORY_NEUTRALFLAG] = b2i(ps.powerups[C.PW_NEUTRALFLAG] ~= 0)
	if G.BotTeam(bs) == C.TEAM_RED then
		inv[C.INVENTORY_REDCUBE] = ps.generic1
		inv[C.INVENTORY_BLUECUBE] = 0
	else
		inv[C.INVENTORY_REDCUBE] = 0
		inv[C.INVENTORY_BLUECUBE] = ps.generic1
	end
	G.BotCheckItemPickup(bs, oldinventory)
end

function G.BotUpdateBattleInventory(bs, enemy)
	local dir = Q.vec3()
	local entinfo = S.aas_entityinfo_t()

	G.BotEntityInfo(enemy, entinfo)
	Q.VectorSubtract(entinfo.origin, bs.origin, dir)
	bs.inventory[C.ENEMY_HEIGHT] = Q.trunc(dir[2])
	dir[2] = 0
	bs.inventory[C.ENEMY_HORIZONTAL_DIST] = Q.trunc(Q.VectorLength(dir))
	--FIXME: add num visible enemies and num visible team mates to the inventory
end

local function sq(x)
	return x * x
end

function G.BotUseKamikaze(bs)
	local gametype = G.gametype
	local entinfo = S.aas_entityinfo_t()
	local dir = Q.vec3()
	local target = Q.vec3()
	local goal
	local trace = S.bsp_trace_t()

	--if the bot has no kamikaze
	if bs.inventory[C.INVENTORY_KAMIKAZE] <= 0 then
		return
	end
	if bs.kamikaze_time > G.floattime then
		return
	end
	bs.kamikaze_time = G.floattime + 0.2
	if gametype == C.GT_CTF or gametype == C.GT_CTF_ELIMINATION then
		--never use kamikaze if the team flag carrier is visible
		if G.BotCTFCarryingFlag(bs) ~= 0 then
			return
		end
		local c = G.BotTeamFlagCarrierVisible(bs)
		if c >= 0 then
			G.BotEntityInfo(c, entinfo)
			Q.VectorSubtract(entinfo.origin, bs.origin, dir)
			if Q.VectorLengthSquared(dir) < sq(KAMIKAZE_DIST) then
				return
			end
		end
		c = G.BotEnemyFlagCarrierVisible(bs)
		if c >= 0 then
			G.BotEntityInfo(c, entinfo)
			Q.VectorSubtract(entinfo.origin, bs.origin, dir)
			if Q.VectorLengthSquared(dir) < sq(KAMIKAZE_DIST) then
				G.trap_EA_Use(bs.client)
				return
			end
		end
	elseif gametype == C.GT_1FCTF then
		--never use kamikaze if the team flag carrier is visible
		if G.Bot1FCTFCarryingFlag(bs) ~= 0 then
			return
		end
		local c = G.BotTeamFlagCarrierVisible(bs)
		if c >= 0 then
			G.BotEntityInfo(c, entinfo)
			Q.VectorSubtract(entinfo.origin, bs.origin, dir)
			if Q.VectorLengthSquared(dir) < sq(KAMIKAZE_DIST) then
				return
			end
		end
		c = G.BotEnemyFlagCarrierVisible(bs)
		if c >= 0 then
			G.BotEntityInfo(c, entinfo)
			Q.VectorSubtract(entinfo.origin, bs.origin, dir)
			if Q.VectorLengthSquared(dir) < sq(KAMIKAZE_DIST) then
				G.trap_EA_Use(bs.client)
				return
			end
		end
	elseif gametype == C.GT_OBELISK then
		if G.BotTeam(bs) == C.TEAM_RED then
			goal = G.blueobelisk
		else
			goal = G.redobelisk
		end
		--if the obelisk is visible
		Q.VectorCopy(goal.origin, target)
		target[2] = target[2] + 1
		Q.VectorSubtract(bs.origin, target, dir)
		if Q.VectorLengthSquared(dir) < sq(KAMIKAZE_DIST * 0.9) then
			G.BotAI_Trace(trace, bs.eye, nil, nil, target, bs.client, C.CONTENTS_SOLID)
			if trace.fraction >= 1 or trace.ent == goal.entitynum then
				G.trap_EA_Use(bs.client)
				return
			end
		end
	elseif gametype == C.GT_HARVESTER then
		--
		if G.BotHarvesterCarryingCubes(bs) ~= 0 then
			return
		end
		--never use kamikaze if a team mate carrying cubes is visible
		local c = G.BotTeamCubeCarrierVisible(bs)
		if c >= 0 then
			G.BotEntityInfo(c, entinfo)
			Q.VectorSubtract(entinfo.origin, bs.origin, dir)
			if Q.VectorLengthSquared(dir) < sq(KAMIKAZE_DIST) then
				return
			end
		end
		c = G.BotEnemyCubeCarrierVisible(bs)
		if c >= 0 then
			G.BotEntityInfo(c, entinfo)
			Q.VectorSubtract(entinfo.origin, bs.origin, dir)
			if Q.VectorLengthSquared(dir) < sq(KAMIKAZE_DIST) then
				G.trap_EA_Use(bs.client)
				return
			end
		end
	end
	--
	local teammates, enemies = G.BotVisibleTeamMatesAndEnemies(bs, KAMIKAZE_DIST)
	--
	if enemies > 2 and enemies > teammates + 1 then
		G.trap_EA_Use(bs.client)
		return
	end
end

function G.BotUseInvulnerability(bs)
	local gametype = G.gametype
	local dir = Q.vec3()
	local target = Q.vec3()
	local goal
	local trace = S.bsp_trace_t()

	--if the bot has no invulnerability
	if bs.inventory[C.INVENTORY_INVULNERABILITY] <= 0 then
		return
	end
	if bs.invulnerability_time > G.floattime then
		return
	end
	bs.invulnerability_time = G.floattime + 0.2
	if gametype == C.GT_CTF or gametype == C.GT_CTF_ELIMINATION then
		--never use kamikaze if the team flag carrier is visible
		if G.BotCTFCarryingFlag(bs) ~= 0 then
			return
		end
		local c = G.BotEnemyFlagCarrierVisible(bs)
		if c >= 0 then
			return
		end
		--if near enemy flag and the flag is visible
		if G.BotTeam(bs) == C.TEAM_RED then
			goal = G.ctf_blueflag
		else
			goal = G.ctf_redflag
		end
		--if the obelisk is visible
		Q.VectorCopy(goal.origin, target)
		target[2] = target[2] + 1
		Q.VectorSubtract(bs.origin, target, dir)
		if Q.VectorLengthSquared(dir) < sq(200) then
			G.BotAI_Trace(trace, bs.eye, nil, nil, target, bs.client, C.CONTENTS_SOLID)
			if trace.fraction >= 1 or trace.ent == goal.entitynum then
				G.trap_EA_Use(bs.client)
				return
			end
		end
	elseif gametype == C.GT_1FCTF then
		--never use kamikaze if the team flag carrier is visible
		if G.Bot1FCTFCarryingFlag(bs) ~= 0 then
			return
		end
		local c = G.BotEnemyFlagCarrierVisible(bs)
		if c >= 0 then
			return
		end
		--if near enemy flag and the flag is visible
		if G.BotTeam(bs) == C.TEAM_RED then
			goal = G.ctf_blueflag
		else
			goal = G.ctf_redflag
		end
		--if the obelisk is visible
		Q.VectorCopy(goal.origin, target)
		target[2] = target[2] + 1
		Q.VectorSubtract(bs.origin, target, dir)
		if Q.VectorLengthSquared(dir) < sq(200) then
			G.BotAI_Trace(trace, bs.eye, nil, nil, target, bs.client, C.CONTENTS_SOLID)
			if trace.fraction >= 1 or trace.ent == goal.entitynum then
				G.trap_EA_Use(bs.client)
				return
			end
		end
	elseif gametype == C.GT_OBELISK then
		if G.BotTeam(bs) == C.TEAM_RED then
			goal = G.blueobelisk
		else
			goal = G.redobelisk
		end
		--if the obelisk is visible
		Q.VectorCopy(goal.origin, target)
		target[2] = target[2] + 1
		Q.VectorSubtract(bs.origin, target, dir)
		if Q.VectorLengthSquared(dir) < sq(300) then
			G.BotAI_Trace(trace, bs.eye, nil, nil, target, bs.client, C.CONTENTS_SOLID)
			if trace.fraction >= 1 or trace.ent == goal.entitynum then
				G.trap_EA_Use(bs.client)
				return
			end
		end
	elseif gametype == C.GT_HARVESTER then
		--
		if G.BotHarvesterCarryingCubes(bs) ~= 0 then
			return
		end
		local c = G.BotEnemyCubeCarrierVisible(bs)
		if c >= 0 then
			return
		end
		--if near enemy base and enemy base is visible
		if G.BotTeam(bs) == C.TEAM_RED then
			goal = G.blueobelisk
		else
			goal = G.redobelisk
		end
		--if the obelisk is visible
		Q.VectorCopy(goal.origin, target)
		target[2] = target[2] + 1
		Q.VectorSubtract(bs.origin, target, dir)
		if Q.VectorLengthSquared(dir) < sq(200) then
			G.BotAI_Trace(trace, bs.eye, nil, nil, target, bs.client, C.CONTENTS_SOLID)
			if trace.fraction >= 1 or trace.ent == goal.entitynum then
				G.trap_EA_Use(bs.client)
				return
			end
		end
	end
end

function G.BotBattleUseItems(bs)
	if bs.inventory[C.INVENTORY_HEALTH] < 40 then
		if bs.inventory[C.INVENTORY_TELEPORTER] > 0 then
			if
				G.BotCTFCarryingFlag(bs) == 0
				and G.Bot1FCTFCarryingFlag(bs) == 0
				and G.BotHarvesterCarryingCubes(bs) == 0
			then
				G.trap_EA_Use(bs.client)
			end
		end
	end
	if bs.inventory[C.INVENTORY_HEALTH] < 60 then
		if bs.inventory[C.INVENTORY_MEDKIT] > 0 then
			G.trap_EA_Use(bs.client)
		end
	end
	G.BotUseKamikaze(bs)
	G.BotUseInvulnerability(bs)
end

function G.BotSetTeleportTime(bs)
	if bit32.band(bit32.bxor(bs.cur_ps.eFlags, bs.last_eFlags), C.EF_TELEPORT_BIT) ~= 0 then
		bs.teleport_time = G.floattime
	end
	bs.last_eFlags = bs.cur_ps.eFlags
end

function G.BotIsDead(bs)
	return bs.cur_ps.pm_type == C.PM_DEAD
end

function G.BotIsObserver(bs)
	if bs.cur_ps.pm_type == C.PM_SPECTATOR then
		return true
	end
	local buf = G.trap_GetConfigstring(C.CS_PLAYERS + bs.client)
	if QS.atoi(QS.Info_ValueForKey(buf, "t")) == C.TEAM_SPECTATOR then
		return true
	end
	return false
end

function G.BotIntermission(bs)
	--NOTE: we shouldn't be looking at the game code...
	if G.level.intermissiontime ~= 0 then
		return true
	end
	return bs.cur_ps.pm_type == C.PM_FREEZE or bs.cur_ps.pm_type == C.PM_INTERMISSION
end

function G.BotInLavaOrSlime(bs)
	local feet = Q.vec3()

	Q.VectorCopy(bs.origin, feet)
	feet[2] = feet[2] - 23
	return bit32.band(G.trap_AAS_PointContents(feet), bit32.bor(C.CONTENTS_LAVA, C.CONTENTS_SLIME)) ~= 0
end

function G.BotCreateWayPoint(name, origin, areanum)
	local waypointmins = Q.vec3()
	local waypointmaxs = Q.vec3()
	for i = 0, 2 do
		waypointmins[i] = -8
		waypointmaxs[i] = 8
	end

	local wp = SF.botai_freewaypoints
	if wp == nil then
		G.BotAI_Print(C.PRT_WARNING, "BotCreateWayPoint: Out of waypoints\n")
		return nil
	end
	SF.botai_freewaypoints = SF.botai_freewaypoints.next

	wp.name = QS.Q_strncpyz(name, 32)
	Q.VectorCopy(origin, wp.goal.origin)
	Q.VectorCopy(waypointmins, wp.goal.mins)
	Q.VectorCopy(waypointmaxs, wp.goal.maxs)
	wp.goal.areanum = areanum
	wp.next = nil
	wp.prev = nil
	return wp
end

function G.BotFindWayPoint(waypoints, name)
	local wp = waypoints
	while wp ~= nil do
		if QS.Q_strequal(wp.name, name) then
			return wp
		end
		wp = wp.next
	end
	return nil
end

function G.BotFreeWaypoints(wp)
	while wp ~= nil do
		local nextwp = wp.next
		wp.next = SF.botai_freewaypoints
		SF.botai_freewaypoints = wp
		wp = nextwp
	end
end

function G.BotInitWaypoints()
	SF.botai_freewaypoints = nil
	for i = 0, MAX_WAYPOINTS - 1 do
		SF.botai_waypoints[i].next = SF.botai_freewaypoints
		SF.botai_freewaypoints = SF.botai_waypoints[i]
	end
end

function G.TeamPlayIsOn()
	return b2i(G.gametype >= C.GT_TEAM and G.g_ffa_gt ~= 1)
end

function G.BotAggression(bs)
	local inv = bs.inventory
	--if the bot has quad
	if inv[C.INVENTORY_QUAD] ~= 0 then
		--if the bot is not holding the gauntlet or the enemy is really nearby
		if bs.weaponnum ~= C.WP_GAUNTLET or inv[C.ENEMY_HORIZONTAL_DIST] < 80 then
			return 70
		end
	end
	--if the enemy is located way higher than the bot
	if inv[C.ENEMY_HEIGHT] > 200 then
		return 0
	end
	--if the bot is very low on health
	if inv[C.INVENTORY_HEALTH] < 60 then
		return 0
	end
	--if the bot is low on health
	if inv[C.INVENTORY_HEALTH] < 80 then
		--if the bot has insufficient armor
		if inv[C.INVENTORY_ARMOR] < 40 then
			return 0
		end
	end
	--if the bot can use the bfg
	if inv[C.INVENTORY_BFG10K] > 0 and inv[C.INVENTORY_BFGAMMO] > 7 then
		return 100
	end
	--if the bot can use the railgun
	if inv[C.INVENTORY_RAILGUN] > 0 and inv[C.INVENTORY_SLUGS] > 5 then
		return 95
	end
	--if the bot can use the lightning gun
	if inv[C.INVENTORY_LIGHTNING] > 0 and inv[C.INVENTORY_LIGHTNINGAMMO] > 50 then
		return 90
	end
	--if the bot can use the rocketlauncher
	if inv[C.INVENTORY_ROCKETLAUNCHER] > 0 and inv[C.INVENTORY_ROCKETS] > 5 then
		return 90
	end
	--if the bot can use the plasmagun
	if inv[C.INVENTORY_PLASMAGUN] > 0 and inv[C.INVENTORY_CELLS] > 40 then
		return 85
	end
	--if the bot can use the grenade launcher
	if inv[C.INVENTORY_GRENADELAUNCHER] > 0 and inv[C.INVENTORY_GRENADES] > 10 then
		return 80
	end
	--if the bot can use the shotgun
	if inv[C.INVENTORY_SHOTGUN] > 0 and inv[C.INVENTORY_SHELLS] > 10 then
		return 50
	end
	--otherwise the bot is not feeling too good
	return 0
end

function G.BotFeelingBad(bs)
	if bs.weaponnum == C.WP_GAUNTLET then
		return 100
	end
	if bs.inventory[C.INVENTORY_HEALTH] < 40 then
		return 100
	end
	if bs.weaponnum == C.WP_MACHINEGUN then
		return 90
	end
	if bs.inventory[C.INVENTORY_HEALTH] < 60 then
		return 80
	end
	return 0
end

function G.BotWantsToRetreat(bs)
	local gametype = G.gametype
	local entinfo = S.aas_entityinfo_t()

	if gametype == C.GT_CTF or gametype == C.GT_CTF_ELIMINATION then
		--always retreat when carrying a CTF flag
		if G.BotCTFCarryingFlag(bs) ~= 0 then
			return 1
		end
	elseif gametype == C.GT_1FCTF or gametype == GT_POSSESSION then
		--if carrying the flag then always retreat
		if G.Bot1FCTFCarryingFlag(bs) ~= 0 then
			return 1
		end
	elseif gametype == C.GT_OBELISK then
		--the bots should be dedicated to attacking the enemy obelisk
		if bs.ltgtype == C.LTG_ATTACKENEMYBASE then
			if bs.enemy ~= G.redobelisk.entitynum and bs.enemy ~= G.blueobelisk.entitynum then
				return 1
			end
		end
		if G.BotFeelingBad(bs) > 50 then
			return 1
		end
		return 0
	elseif gametype == C.GT_HARVESTER then
		--if carrying cubes then always retreat
		if G.BotHarvesterCarryingCubes(bs) ~= 0 then
			return 1
		end
	end
	--
	if bs.enemy >= 0 then
		--if the enemy is carrying a flag
		G.BotEntityInfo(bs.enemy, entinfo)
		-- if the enemy is carrying a flag
		if G.EntityCarriesFlag(entinfo) then
			return 0
		end
		-- if the enemy is carrying cubes
		if G.EntityCarriesCubes(entinfo) then
			return 0
		end
	end
	--if the bot is getting the flag
	if bs.ltgtype == C.LTG_GETFLAG then
		return 1
	end
	--
	if G.BotAggression(bs) < 50 then
		return 1
	end
	return 0
end

return nil
