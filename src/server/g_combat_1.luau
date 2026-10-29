--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_combat.c, part 1 of 2).

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
-- Luau port of g_combat.c, part 1: scoring, item tossing, player death.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SF = G.FileStatics("g_combat")

-- challenge ids from challenges.h (not provided by g_defs)
local CH = {
	GENERAL_TOTALKILLS = 0,
	GENERAL_TOTALDEATHS = 1,
	WEAPON_GAUNTLET_KILLS = 2,
	WEAPON_MACHINEGUN_KILLS = 3,
	WEAPON_SHOTGUN_KILLS = 4,
	WEAPON_GRANADE_KILLS = 5,
	WEAPON_ROCKET_KILLS = 6,
	WEAPON_LIGHTNING_KILLS = 7,
	WEAPON_PLASMA_KILLS = 8,
	WEAPON_RAIL_KILLS = 9,
	WEAPON_INSTANT_RAIL_KILLS = 10,
	WEAPON_BFG_KILLS = 11,
	WEAPON_NAILGUN_KILLS = 12,
	WEAPON_CHAINGUN_KILLS = 13,
	WEAPON_MINE_KILLS = 14,
	WEAPON_GRAPPLE_KILLS = 15,
	WEAPON_PUSH_KILLS = 16,
	WEAPON_CRUSH_KILLS = 17,
	WEAPON_TELEFRAG_KILLS = 18,
	POWERUP_QUAD_KILL = 19,
	POWERUP_COUNTER_QUAD = 20,
	POWERUP_SPEED_KILL = 21,
	POWERUP_COUNTER_SPEED = 22,
	POWERUP_INVIS_KILL = 23,
	POWERUP_COUNTER_INVIS = 24,
	POWERUP_FLIGHT_KILL = 25,
	POWERUP_COUNTER_FLIGHT = 26,
	POWERUP_COUNTER_ENVIR = 27,
	POWERUP_COUNTER_REGEN = 28,
	POWERUP_COUNTER_MULTI = 29,
	POWERUP_MULTI_KILL = 30,
	AWARD_EXCELLENT = 31,
}

-- these are just for logging, the client prints its own messages
SF.modNames = {
	[0] = "MOD_UNKNOWN",
	"MOD_SHOTGUN",
	"MOD_GAUNTLET",
	"MOD_MACHINEGUN",
	"MOD_GRENADE",
	"MOD_GRENADE_SPLASH",
	"MOD_ROCKET",
	"MOD_ROCKET_SPLASH",
	"MOD_PLASMA",
	"MOD_PLASMA_SPLASH",
	"MOD_RAILGUN",
	"MOD_LIGHTNING",
	"MOD_BFG",
	"MOD_BFG_SPLASH",
	"MOD_WATER",
	"MOD_SLIME",
	"MOD_LAVA",
	"MOD_CRUSH",
	"MOD_TELEFRAG",
	"MOD_FALLING",
	"MOD_SUICIDE",
	"MOD_TARGET_LASER",
	"MOD_TRIGGER_HURT",
	"MOD_NAIL",
	"MOD_CHAINGUN",
	"MOD_PROXIMITY_MINE",
	"MOD_KAMIKAZE",
	"MOD_JUICED",
	"MOD_GRAPPLE",
}
SF.modNamesCount = 29

-- static int i inside player_die's normal-death branch
SF.deathAnimIndex = 0

--[[
============
ScorePlum
============
]]
function G.ScorePlum(ent, origin, score)
	local plum = G.G_TempEntity(origin, C.EV_SCOREPLUM)
	-- only send this temp entity to a single client
	plum.r.svFlags = bit32.bor(plum.r.svFlags, C.SVF_SINGLECLIENT)
	plum.r.singleClient = ent.s.number
	--
	plum.s.otherEntityNum = ent.s.number
	plum.s.time = score
end

--[[
============
AddScore

Adds score to both the client and his team
============
]]
function G.AddScore(ent, origin, score)
	if ent.client == nil then
		return
	end
	-- no scoring during pre-match warmup
	if G.level.warmupTime ~= 0 then
		return
	end

	--No scoring during intermission
	if G.level.intermissiontime ~= 0 then
		return
	end
	-- show score plum
	if G.level.numNonSpectatorClients < 3 and score < 0 and (G.g_gametype.integer < C.GT_TEAM or G.g_ffa_gt == 1) then
		for i = 0, G.level.maxclients - 1 do
			if G.level.clients[i].pers.connected ~= C.CON_CONNECTED then
				continue --Client was not connected
			end

			if G.level.clients[i].sess.sessionTeam == C.TEAM_SPECTATOR then
				continue --Don't give anything to spectators
			end

			if G.g_entities[i] == ent then
				continue --Don't award dead one
			end

			G.level.clients[i].ps.persistant[C.PERS_SCORE] -= score
			G.ScorePlum(ent, origin, -score)
		end
	else
		G.ScorePlum(ent, origin, score)
		--
		ent.client.ps.persistant[C.PERS_SCORE] += score
		if G.g_gametype.integer == C.GT_TEAM then
			local team = ent.client.ps.persistant[C.PERS_TEAM]
			G.level.teamScores[team] += score
			G.G_LogPrintf("TeamScore: %i %i: Team %d now has %d points\n",
				team, G.level.teamScores[team], team, G.level.teamScores[team])
		end
	end
	G.G_LogPrintf("PlayerScore: %i %i: %s now has %d points\n",
		ent.s.number, ent.client.ps.persistant[C.PERS_SCORE], ent.client.pers.netname, ent.client.ps.persistant[C.PERS_SCORE])
	G.CalculateRanks()
end

--[[
=================
TossClientItems

Toss the weapon and powerups for the killed player
=================
]]
function G.TossClientItems(self)
	-- drop the weapon if not a gauntlet or machinegun
	local weapon = self.s.weapon

	--Never drop in elimination or last man standing mode!
	if G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_LMS then
		return
	end

	-- make a special check to see if they are changing to a new
	-- weapon that isn't the mg or gauntlet.  Without this, a client
	-- can pick up a weapon, be killed, and not drop the weapon because
	-- their weapon change hasn't completed yet and they are still holding the MG.
	if weapon == C.WP_MACHINEGUN or weapon == C.WP_GRAPPLING_HOOK then
		if self.client.ps.weaponstate == C.WEAPON_DROPPING then
			weapon = self.client.pers.cmd.weapon
		end
		if bit32.band(self.client.ps.stats[C.STAT_WEAPONS], bit32.lshift(1, weapon)) == 0 then
			weapon = C.WP_NONE
		end
	end

	if G.g_instantgib.integer ~= 0 or G.g_rockets.integer ~= 0 or G.g_gametype.integer == C.GT_CTF_ELIMINATION or G.g_elimination_allgametypes.integer ~= 0 then
		--Nothing!
	elseif weapon > C.WP_MACHINEGUN and weapon ~= C.WP_GRAPPLING_HOOK and
		self.client.ps.ammo[weapon] ~= 0 then
		-- find the item type for this weapon
		local item = BG.BG_FindItemForWeapon(weapon)

		-- spawn the item
		G.Drop_Item(self, item, 0)
	end

	-- drop all the powerups if not in teamplay
	if G.g_gametype.integer ~= C.GT_TEAM then
		local angle = 45
		for i = 1, C.PW_NUM_POWERUPS - 1 do
			if self.client.ps.powerups[i] > G.level.time then
				local item = BG.BG_FindItemForPowerup(i)
				if item == nil then
					continue
				end
				local drop = G.Drop_Item(self, item, angle)
				-- decide how many seconds it has left
				drop.count = Q.idiv(self.client.ps.powerups[i] - G.level.time, 1000)
				if drop.count < 1 then
					drop.count = 1
				end
				angle += 45
			end
		end
	end
end

--[[
=================
TossClientCubes
=================
]]
function G.TossClientCubesValues(angles, origin, velocity)
	angles[C.YAW] = Q.imod(G.level.time, 360)
	angles[C.PITCH] = 0 -- always forward
	angles[C.ROLL] = 0

	Q.AngleVectors(angles, velocity, nil, nil)
	Q.VectorScale(velocity, 150, velocity)
	velocity[2] = Q.f(velocity[2] + (200 + Q.crandom() * 50))

	if G.neutralObelisk ~= nil then
		Q.VectorCopy(G.neutralObelisk.s.pos.trBase, origin)
		origin[2] = Q.f(origin[2] + 44)
	else
		Q.VectorClear(origin)
	end
end

function G.TossClientCubes(self)
	local item
	local velocity = Q.vec3()
	local angles = Q.vec3()
	local origin = Q.vec3()

	self.client.ps.generic1 = 0

	-- this should never happen but we should never
	-- get the server to crash due to skull being spawned in
	if not G.G_EntitiesFree() then
		return
	end

	if self.client.sess.sessionTeam == C.TEAM_RED then
		item = BG.BG_FindItem("Red Cube")
	else
		item = BG.BG_FindItem("Blue Cube")
	end

	G.TossClientCubesValues(angles, origin, velocity)

	if G.g_harvesterFromBodies.integer ~= 0 then
		Q.VectorCopy(self.s.pos.trBase, origin)
	end

	local drop = G.LaunchItem(item, origin, velocity)

	drop.nextthink = G.level.time + G.g_cubeTimeout.integer * 1000
	drop.think = G.G_FreeEntity
	drop.spawnflags = self.client.sess.sessionTeam
end

--[[
=================
TossClientPersistantPowerups
=================
]]
function G.TossClientPersistantPowerups(ent)
	if ent.client == nil then
		return
	end

	if ent.client.persistantPowerup == nil then
		return
	end

	local powerup = ent.client.persistantPowerup

	powerup.r.svFlags = bit32.band(powerup.r.svFlags, bit32.bnot(C.SVF_NOCLIENT))
	powerup.s.eFlags = bit32.band(powerup.s.eFlags, bit32.bnot(C.EF_NODRAW))
	powerup.r.contents = C.CONTENTS_TRIGGER
	G.trap_LinkEntity(powerup)

	ent.client.ps.stats[C.STAT_PERSISTANT_POWERUP] = 0
	ent.client.persistantPowerup = nil
end

--[[
==================
LookAtKiller
==================
]]
function G.LookAtKiller(self, inflictor, attacker)
	local dir = Q.vec3()

	if attacker ~= nil and attacker ~= self then
		Q.VectorSubtract(attacker.s.pos.trBase, self.s.pos.trBase, dir)
	elseif inflictor ~= nil and inflictor ~= self then
		Q.VectorSubtract(inflictor.s.pos.trBase, self.s.pos.trBase, dir)
	else
		self.client.ps.stats[C.STAT_DEAD_YAW] = Q.trunc(self.s.angles[C.YAW])
		return
	end

	self.client.ps.stats[C.STAT_DEAD_YAW] = Q.trunc(G.vectoyaw(dir))

	G.vectoyaw(dir)
end

--[[
==================
GibEntity
==================
]]
function G.GibEntity(self, killer)
	--if this entity still has kamikaze
	if bit32.band(self.s.eFlags, C.EF_KAMIKAZE) ~= 0 then
		-- check if there is a kamikaze timer around for this owner
		for i = 0, C.MAX_GENTITIES - 1 do
			local ent = G.g_entities[i]
			if not ent.inuse then
				continue
			end
			if ent.activator ~= self then
				continue
			end
			if ent.classname ~= "kamikaze timer" then
				continue
			end
			G.G_FreeEntity(ent)
			break
		end
	end
	G.G_AddEvent(self, C.EV_GIB_PLAYER, killer)
	self.takedamage = false
	self.s.eType = C.ET_INVISIBLE
	self.r.contents = 0
end

--[[
==================
body_die
==================
]]
function G.body_die(self, inflictor, attacker, damage, meansOfDeath)
	if self.health > C.GIB_HEALTH then
		return
	end
	if G.g_blood.integer == 0 then
		self.health = C.GIB_HEALTH + 1
		return
	end

	G.GibEntity(self, 0)
end

--[[
==================
Kamikaze_DeathActivate
==================
]]
function G.Kamikaze_DeathActivate(ent)
	G.G_StartKamikaze(ent)
	G.G_FreeEntity(ent)
end

--[[
==================
Kamikaze_DeathTimer
==================
]]
function G.Kamikaze_DeathTimer(self)
	local ent = G.G_Spawn()
	ent.classname = "kamikaze timer"
	Q.VectorCopy(self.s.pos.trBase, ent.s.pos.trBase)
	ent.r.svFlags = bit32.bor(ent.r.svFlags, C.SVF_NOCLIENT)
	ent.think = G.Kamikaze_DeathActivate
	ent.nextthink = G.level.time + 5 * 1000

	ent.activator = self
end

--[[
==================
CheckAlmostCapture
==================
]]
function G.CheckAlmostCapture(self, attacker)
	local classname
	local dir = Q.vec3()

	-- if this player was carrying a flag
	if self.client.ps.powerups[C.PW_REDFLAG] ~= 0 or
		self.client.ps.powerups[C.PW_BLUEFLAG] ~= 0 or
		self.client.ps.powerups[C.PW_NEUTRALFLAG] ~= 0 then
		-- get the goal flag this player should have been going for
		if G.g_gametype.integer == C.GT_CTF or G.g_gametype.integer == C.GT_CTF_ELIMINATION then
			if self.client.sess.sessionTeam == C.TEAM_BLUE then
				classname = "team_CTF_blueflag"
			else
				classname = "team_CTF_redflag"
			end
		else
			if self.client.sess.sessionTeam == C.TEAM_BLUE then
				classname = "team_CTF_redflag"
			else
				classname = "team_CTF_blueflag"
			end
		end
		local ent = nil
		repeat
			ent = G.G_Find(ent, "classname", classname)
		until not (ent ~= nil and bit32.band(ent.flags, C.FL_DROPPED_ITEM) ~= 0)
		-- if we found the destination flag and it's not picked up
		if ent ~= nil and bit32.band(ent.r.svFlags, C.SVF_NOCLIENT) == 0 then
			-- if the player was *very* close
			Q.VectorSubtract(self.client.ps.origin, ent.s.origin, dir)
			if Q.VectorLength(dir) < 200 then
				self.client.ps.persistant[C.PERS_PLAYEREVENTS] = bit32.bxor(self.client.ps.persistant[C.PERS_PLAYEREVENTS], C.PLAYEREVENT_HOLYSHIT)
				if attacker.client ~= nil then
					attacker.client.ps.persistant[C.PERS_PLAYEREVENTS] = bit32.bxor(attacker.client.ps.persistant[C.PERS_PLAYEREVENTS], C.PLAYEREVENT_HOLYSHIT)
				end
			end
		end
	end
end

--[[
==================
CheckAlmostScored
==================
]]
function G.CheckAlmostScored(self, attacker)
	local classname
	local dir = Q.vec3()

	-- if the player was carrying cubes
	if self.client.ps.generic1 ~= 0 then
		if self.client.sess.sessionTeam == C.TEAM_BLUE then
			classname = "team_redobelisk"
		else
			classname = "team_blueobelisk"
		end
		local ent = G.G_Find(nil, "classname", classname)
		-- if we found the destination obelisk
		if ent ~= nil then
			-- if the player was *very* close
			Q.VectorSubtract(self.client.ps.origin, ent.s.origin, dir)
			if Q.VectorLength(dir) < 200 then
				self.client.ps.persistant[C.PERS_PLAYEREVENTS] = bit32.bxor(self.client.ps.persistant[C.PERS_PLAYEREVENTS], C.PLAYEREVENT_HOLYSHIT)
				if attacker.client ~= nil then
					attacker.client.ps.persistant[C.PERS_PLAYEREVENTS] = bit32.bxor(attacker.client.ps.persistant[C.PERS_PLAYEREVENTS], C.PLAYEREVENT_HOLYSHIT)
				end
			end
		end
	end
end

--[[
==================
player_die
==================
]]
function G.player_die(self, inflictor, attacker, damage, meansOfDeath)
	local ent
	local anim
	local contents
	local killer
	local i, counter2
	local killerName
	local obit

	if self.client == nil or self.client.ps.pm_type == C.PM_DEAD then
		return
	end

	if G.level.intermissiontime ~= 0 then
		return
	end

	--unlagged - backward reconciliation #2
	-- make sure the body shows up in the client's current position
	G.G_UnTimeShiftClient(self)
	--KK-OAX Here is where we run the streak logic.
	G.G_RunStreakLogic(attacker, self)

	-- check for an almost capture
	G.CheckAlmostCapture(self, attacker)
	-- check for a player that almost brought in cubes
	G.CheckAlmostScored(self, attacker)

	if self.client == nil then
		return
	end
	if self.client.hook ~= nil then
		G.Weapon_HookFree(self.client.hook)
	end
	if bit32.band(self.client.ps.eFlags, C.EF_TICKING) ~= 0 and self.activator ~= nil then
		self.client.ps.eFlags = bit32.band(self.client.ps.eFlags, bit32.bnot(C.EF_TICKING))
		self.activator.think = G.G_FreeEntity
		self.activator.nextthink = G.level.time
	end
	self.client.ps.pm_type = C.PM_DEAD

	if attacker ~= nil then
		killer = attacker.s.number
		if attacker.client ~= nil then
			killerName = attacker.client.pers.netname
		else
			killerName = "<non-client>"
		end
	else
		killer = C.ENTITYNUM_WORLD
		killerName = "<world>"
	end

	if killer < 0 or killer >= C.MAX_CLIENTS then
		killer = C.ENTITYNUM_WORLD
		killerName = "<world>"
	end

	if meansOfDeath < 0 or meansOfDeath >= SF.modNamesCount then
		obit = "<bad obituary>"
	else
		obit = SF.modNames[meansOfDeath]
	end

	G.G_LogPrintf("Kill: %i %i %i: %s killed %s by %s\n",
		killer, self.s.number, meansOfDeath, killerName,
		self.client.pers.netname, obit)

	-- broadcast the death event to everyone
	ent = G.G_TempEntity(self.r.currentOrigin, C.EV_OBITUARY)
	ent.s.eventParm = meansOfDeath
	ent.s.otherEntityNum = self.s.number
	ent.s.otherEntityNum2 = killer
	--Sago: Hmmm... generic? Can I transmit anything I like? Like if it is a team kill? Let's try
	ent.s.generic1 = if G.OnSameTeam(self, attacker) then 1 else 0
	if not ((G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_CTF_ELIMINATION) and G.level.time < G.level.roundStartTime) then
		ent.r.svFlags = C.SVF_BROADCAST -- send to everyone (if not an elimination gametype during active warmup)
	else
		ent.r.svFlags = C.SVF_NOCLIENT
	end

	self.enemy = attacker

	self.client.ps.persistant[C.PERS_KILLED] += 1

	if attacker ~= nil and attacker.client ~= nil then
		attacker.client.lastkilled_client = self.s.number

		if attacker == self or G.OnSameTeam(self, attacker) then
			if G.g_gametype.integer ~= C.GT_LMS and G.g_gametype.integer ~= C.GT_POSSESSION and not ((G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_CTF_ELIMINATION) and G.level.time < G.level.roundStartTime) then
				if (G.g_gametype.integer < C.GT_TEAM and G.g_ffa_gt ~= 1 and self.client.ps.persistant[C.PERS_SCORE] > 0) or G.level.numNonSpectatorClients < 3 then
					--Cannot get negative scores by suicide
					G.AddScore(attacker, self.r.currentOrigin, -1)
				end
			end
		else
			if G.g_gametype.integer ~= C.GT_LMS and G.g_gametype.integer ~= C.GT_POSSESSION then
				G.AddScore(attacker, self.r.currentOrigin, 1)
			end

			if meansOfDeath == C.MOD_GAUNTLET then

				-- Attack gets a challenge complete:
				if bit32.band(attacker.r.svFlags, C.SVF_BOT) == 0 and bit32.band(self.r.svFlags, C.SVF_BOT) == 0 then
					G.ChallengeMessage(attacker, CH.WEAPON_GAUNTLET_KILLS)
				end

				-- play humiliation on player
				attacker.client.ps.persistant[C.PERS_GAUNTLET_FRAG_COUNT] += 1
				G.G_LogPrintf("Award: %i %i: %s gained the %s award!\n", attacker.client.ps.clientNum, 0, attacker.client.pers.netname, "GAUNTLET")

				-- add the sprite over the player's head
				attacker.client.ps.eFlags = bit32.band(attacker.client.ps.eFlags, bit32.bnot(bit32.bor(C.EF_AWARD_IMPRESSIVE, C.EF_AWARD_EXCELLENT, C.EF_AWARD_GAUNTLET, C.EF_AWARD_ASSIST, C.EF_AWARD_DEFEND, C.EF_AWARD_CAP)))
				attacker.client.ps.eFlags = bit32.bor(attacker.client.ps.eFlags, C.EF_AWARD_GAUNTLET)
				attacker.client.rewardTime = G.level.time + C.REWARD_SPRITE_TIME

				-- also play humiliation on target
				self.client.ps.persistant[C.PERS_PLAYEREVENTS] = bit32.bxor(self.client.ps.persistant[C.PERS_PLAYEREVENTS], C.PLAYEREVENT_GAUNTLETREWARD)
			end

			--If neither attacker or taget is bots and not the same
			if bit32.band(attacker.r.svFlags, C.SVF_BOT) == 0 and bit32.band(self.r.svFlags, C.SVF_BOT) == 0 and self ~= attacker then
				if meansOfDeath == C.MOD_GAUNTLET then
					G.ChallengeMessage(attacker, CH.WEAPON_GAUNTLET_KILLS)
				elseif meansOfDeath == C.MOD_MACHINEGUN then
					G.ChallengeMessage(attacker, CH.WEAPON_MACHINEGUN_KILLS)
				elseif meansOfDeath == C.MOD_SHOTGUN then
					G.ChallengeMessage(attacker, CH.WEAPON_SHOTGUN_KILLS)
				elseif meansOfDeath == C.MOD_GRENADE or meansOfDeath == C.MOD_GRENADE_SPLASH then
					G.ChallengeMessage(attacker, CH.WEAPON_GRANADE_KILLS)
				elseif meansOfDeath == C.MOD_ROCKET or meansOfDeath == C.MOD_ROCKET_SPLASH then
					G.ChallengeMessage(attacker, CH.WEAPON_ROCKET_KILLS)
				elseif meansOfDeath == C.MOD_LIGHTNING then
					G.ChallengeMessage(attacker, CH.WEAPON_LIGHTNING_KILLS)
				elseif meansOfDeath == C.MOD_PLASMA or meansOfDeath == C.MOD_PLASMA_SPLASH then
					G.ChallengeMessage(attacker, CH.WEAPON_PLASMA_KILLS)
				elseif meansOfDeath == C.MOD_RAILGUN then
					if G.g_instantgib.integer ~= 0 then
						G.ChallengeMessage(attacker, CH.WEAPON_INSTANT_RAIL_KILLS)
					else
						G.ChallengeMessage(attacker, CH.WEAPON_RAIL_KILLS)
					end
				elseif meansOfDeath == C.MOD_BFG or meansOfDeath == C.MOD_BFG_SPLASH then
					G.ChallengeMessage(attacker, CH.WEAPON_BFG_KILLS)
				elseif meansOfDeath == C.MOD_NAIL then
					G.ChallengeMessage(attacker, CH.WEAPON_NAILGUN_KILLS)
				elseif meansOfDeath == C.MOD_CHAINGUN then
					G.ChallengeMessage(attacker, CH.WEAPON_CHAINGUN_KILLS)
				elseif meansOfDeath == C.MOD_PROXIMITY_MINE then
					G.ChallengeMessage(attacker, CH.WEAPON_MINE_KILLS)
				elseif meansOfDeath == C.MOD_GRAPPLE then
					G.ChallengeMessage(attacker, CH.WEAPON_GRAPPLE_KILLS)
				elseif meansOfDeath == C.MOD_LAVA or meansOfDeath == C.MOD_SLIME or meansOfDeath == C.MOD_TRIGGER_HURT or meansOfDeath == C.MOD_FALLING then
					G.ChallengeMessage(attacker, CH.WEAPON_PUSH_KILLS)
				elseif meansOfDeath == C.MOD_CRUSH then
					G.ChallengeMessage(attacker, CH.WEAPON_CRUSH_KILLS)
				elseif meansOfDeath == C.MOD_TELEFRAG then
					G.ChallengeMessage(attacker, CH.WEAPON_TELEFRAG_KILLS)
				end
				G.ChallengeMessage(attacker, CH.GENERAL_TOTALKILLS)
				G.ChallengeMessage(self, CH.GENERAL_TOTALDEATHS)

				--Lets count number of powerups:
				i = 0
				counter2 = 0

				if attacker.client.ps.powerups[C.PW_QUAD] ~= 0 then
					G.ChallengeMessage(attacker, CH.POWERUP_QUAD_KILL)
					counter2 += 1
				end
				if self.client.ps.powerups[C.PW_QUAD] ~= 0 then
					G.ChallengeMessage(attacker, CH.POWERUP_COUNTER_QUAD)
					i += 1
				end

				if attacker.client.ps.powerups[C.PW_HASTE] ~= 0 then
					G.ChallengeMessage(attacker, CH.POWERUP_SPEED_KILL)
					counter2 += 1
				end
				if self.client.ps.powerups[C.PW_HASTE] ~= 0 then
					G.ChallengeMessage(attacker, CH.POWERUP_COUNTER_SPEED)
					i += 1
				end

				if attacker.client.ps.powerups[C.PW_INVIS] ~= 0 then
					G.ChallengeMessage(attacker, CH.POWERUP_INVIS_KILL)
					counter2 += 1
				end
				if self.client.ps.powerups[C.PW_INVIS] ~= 0 then
					G.ChallengeMessage(attacker, CH.POWERUP_COUNTER_INVIS)
					i += 1
				end

				if attacker.client.ps.powerups[C.PW_FLIGHT] ~= 0 then
					G.ChallengeMessage(attacker, CH.POWERUP_FLIGHT_KILL)
					counter2 += 1
				end
				if self.client.ps.powerups[C.PW_FLIGHT] ~= 0 then
					G.ChallengeMessage(attacker, CH.POWERUP_COUNTER_FLIGHT)
					i += 1
				end

				if self.client.ps.powerups[C.PW_BATTLESUIT] ~= 0 then
					G.ChallengeMessage(attacker, CH.POWERUP_COUNTER_ENVIR)
					i += 1
				end

				if self.client.ps.powerups[C.PW_REGEN] ~= 0 then
					G.ChallengeMessage(attacker, CH.POWERUP_COUNTER_REGEN)
					i += 1
				end

				if i > 1 then --The target had more than one powerup
					G.ChallengeMessage(attacker, CH.POWERUP_COUNTER_MULTI)
				end
				if counter2 > 1 then --The attacker has more than one powerup
					G.ChallengeMessage(attacker, CH.POWERUP_MULTI_KILL)
				end
			end

			-- check for two kills in a short amount of time
			-- if this is close enough to the last kill, give a reward sound
			if G.level.time - attacker.client.lastKillTime < C.CARNAGE_REWARD_TIME then
				-- KK-OAX
				-- Check if Multikills are enabled
				if G.g_altExcellent.integer ~= 0 then
					attacker.client.pers.multiKillCount += 1
					G.G_checkForMultiKill(attacker)
				end -- play excellent on player
				attacker.client.ps.persistant[C.PERS_EXCELLENT_COUNT] += 1
				G.G_LogPrintf("Award: %i %i: %s gained the %s award!\n", attacker.client.ps.clientNum, 1, attacker.client.pers.netname, "EXCELLENT")
				if not G.level.hadBots then --There has not been any bots
					G.ChallengeMessage(attacker, CH.AWARD_EXCELLENT)
				end
				-- add the sprite over the player's head
				attacker.client.ps.eFlags = bit32.band(attacker.client.ps.eFlags, bit32.bnot(bit32.bor(C.EF_AWARD_IMPRESSIVE, C.EF_AWARD_EXCELLENT, C.EF_AWARD_GAUNTLET, C.EF_AWARD_ASSIST, C.EF_AWARD_DEFEND, C.EF_AWARD_CAP)))
				attacker.client.ps.eFlags = bit32.bor(attacker.client.ps.eFlags, C.EF_AWARD_EXCELLENT)
				attacker.client.rewardTime = G.level.time + C.REWARD_SPRITE_TIME
			else
				--KK-OAX Clear multikill count
				--Must be 1 so the correct number of kills are displayed to the clients.
				attacker.client.pers.multiKillCount = 1
			end
			attacker.client.lastKillTime = G.level.time
		end
	else
		if G.g_gametype.integer ~= C.GT_LMS and G.g_gametype.integer ~= C.GT_POSSESSION and
			not ((G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_CTF_ELIMINATION) and G.level.time < G.level.roundStartTime) then
			if self.client.ps.persistant[C.PERS_SCORE] > 0 or G.level.numNonSpectatorClients < 3 then
				--Cannot get negative scores by suicide
				G.AddScore(self, self.r.currentOrigin, -1)
			end
		end
	end

	-- Add team bonuses
	G.Team_FragBonuses(self, inflictor, attacker)

	-- if I committed suicide, the flag does not fall, it returns.
	if meansOfDeath == C.MOD_SUICIDE then
		if self.client.ps.powerups[C.PW_NEUTRALFLAG] ~= 0 then -- only happens in One Flag CTF
			G.Team_ReturnFlag(C.TEAM_FREE)
			self.client.ps.powerups[C.PW_NEUTRALFLAG] = 0
		elseif self.client.ps.powerups[C.PW_REDFLAG] ~= 0 then -- only happens in standard CTF
			G.Team_ReturnFlag(C.TEAM_RED)
			self.client.ps.powerups[C.PW_REDFLAG] = 0
		elseif self.client.ps.powerups[C.PW_BLUEFLAG] ~= 0 then -- only happens in standard CTF
			G.Team_ReturnFlag(C.TEAM_BLUE)
			self.client.ps.powerups[C.PW_BLUEFLAG] = 0
		end
	end
	G.TossClientPersistantPowerups(self)
	if G.g_gametype.integer == C.GT_HARVESTER then
		G.TossClientCubes(self)
	end
	-- if client is in a nodrop area, don't drop anything (but return CTF flags!)
	G.TossClientItems(self)

	G.Cmd_Score_f(self) -- show scores
	-- send updated scores to any clients that are following this one,
	-- or they would get stale scoreboards
	i = 0
	while i < G.level.maxclients do
		local client = G.level.clients[i]
		if client.pers.connected ~= C.CON_CONNECTED then
			i += 1
			continue
		end
		if client.sess.sessionTeam ~= C.TEAM_SPECTATOR then
			i += 1
			continue
		end
		if client.sess.spectatorClient == self.s.number then
			G.Cmd_Score_f(G.g_entities[i])
		end
		i += 1
	end

	self.takedamage = true -- can still be gibbed

	self.s.weapon = C.WP_NONE
	self.s.powerups = 0
	self.r.contents = C.CONTENTS_CORPSE

	self.s.angles[0] = 0
	self.s.angles[2] = 0
	G.LookAtKiller(self, inflictor, attacker)

	Q.VectorCopy(self.s.angles, self.client.ps.viewangles)

	self.s.loopSound = 0

	self.r.maxs[2] = -8

	-- don't allow respawn until the death anim is done
	-- g_forcerespawn may force spawning at some later time
	self.client.respawnTime = G.level.time + 1700 + i
	if G.g_respawntime.integer > 0 then
		i = 0
		while self.client.respawnTime > i * G.g_respawntime.integer * 1000 do
			i += 1
		end

		self.client.respawnTime = i * G.g_respawntime.integer * 1000
	end
	--However during warm up, we should respawn quicker!
	if G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_CTF_ELIMINATION or G.g_gametype.integer == C.GT_LMS then
		if G.level.time <= G.level.roundStartTime and G.level.time > G.level.roundStartTime - 1000 * G.g_elimination_activewarmup.integer then
			self.client.respawnTime = G.level.time + Q.imod(Q.rand(), 800)
		end
	end

	G.RespawnTimeMessage(self, self.client.respawnTime)

	-- remove powerups
	for j = 0, C.MAX_POWERUPS - 1 do
		self.client.ps.powerups[j] = 0
	end

	-- never gib in a nodrop
	contents = G.trap_PointContents(self.r.currentOrigin, -1)

	if (self.health <= C.GIB_HEALTH and bit32.band(contents, C.CONTENTS_NODROP) == 0 and G.g_blood.integer ~= 0) or meansOfDeath == C.MOD_SUICIDE then
		-- gib death
		G.GibEntity(self, killer)
	else
		-- normal death
		local di = SF.deathAnimIndex

		if di == 0 then
			anim = C.BOTH_DEATH1
		elseif di == 1 then
			anim = C.BOTH_DEATH2
		else
			anim = C.BOTH_DEATH3
		end

		-- for the no-blood option, we need to prevent the health
		-- from going to gib level
		if self.health <= C.GIB_HEALTH then
			self.health = C.GIB_HEALTH + 1
		end

		self.client.ps.legsAnim =
			bit32.bor(bit32.bxor(bit32.band(self.client.ps.legsAnim, C.ANIM_TOGGLEBIT), C.ANIM_TOGGLEBIT), anim)
		self.client.ps.torsoAnim =
			bit32.bor(bit32.bxor(bit32.band(self.client.ps.torsoAnim, C.ANIM_TOGGLEBIT), C.ANIM_TOGGLEBIT), anim)

		G.G_AddEvent(self, C.EV_DEATH1 + di, killer)

		-- the body can still be gibbed
		self.die = G.body_die

		-- globally cycle through the different death animations
		SF.deathAnimIndex = (di + 1) % 3

		if bit32.band(self.s.eFlags, C.EF_KAMIKAZE) ~= 0 then
			G.Kamikaze_DeathTimer(self)
		end
	end

	G.trap_LinkEntity(self)
end

return nil
