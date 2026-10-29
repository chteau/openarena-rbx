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
-- Luau port of code/cgame/cg_event.c (OpenArena gamecode).
-- cg_event.c -- handle entity events at snapshot or playerstate transitions

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local trap = require(script.Parent.Parent.sys.Trap)
local BG = require(script.Parent.Parent.adapters.BG)

local band, bor, bnot, bxor, lshift = bit32.band, bit32.bor, bit32.bnot, bit32.bxor, bit32.lshift

--==========================================================================

--[[
===================
CG_PlaceString

Also called by scoreboard drawing
===================
]]
function G.CG_PlaceString(rank)
	local s, t
	if band(rank, C.RANK_TIED_FLAG) ~= 0 then
		rank = band(rank, bnot(C.RANK_TIED_FLAG))
		t = "Tied for "
	else
		t = ""
	end

	if rank == 1 then
		s = "^41st^7" -- draw in blue
	elseif rank == 2 then
		s = "^12nd^7" -- draw in red
	elseif rank == 3 then
		s = "^33rd^7" -- draw in yellow
	elseif rank == 11 then
		s = "11th"
	elseif rank == 12 then
		s = "12th"
	elseif rank == 13 then
		s = "13th"
	elseif rank % 10 == 1 then
		s = Q.va("%ist", rank)
	elseif rank % 10 == 2 then
		s = Q.va("%ind", rank)
	elseif rank % 10 == 3 then
		s = Q.va("%ird", rank)
	else
		s = Q.va("%ith", rank)
	end

	return string.sub(t .. s, 1, 63)
end

local function pushFrag()
	local cgs = G.cgs
	for i = 0, C.FRAGMSG_MAX - 2 do
		T.assign(cgs.fragMsg[i], cgs.fragMsg[i + 1])
	end
	T.reset(cgs.fragMsg[C.FRAGMSG_MAX - 1], T.fragInfo_t)
end

local worldMessages = {
	[C.MOD_SUICIDE] = "suicides",
	[C.MOD_FALLING] = "cratered",
	[C.MOD_CRUSH] = "was squished",
	[C.MOD_WATER] = "sank like a rock",
	[C.MOD_SLIME] = "melted",
	[C.MOD_LAVA] = "does a back flip into the lava",
	[C.MOD_TARGET_LASER] = "saw the light",
	[C.MOD_TRIGGER_HURT] = "was in the wrong place",
}

-- mod -> { message, message2, shader name }
local attackerMessages = {
	[C.MOD_GRAPPLE] = { "was caught by", "", "grapplehookShader" },
	[C.MOD_GAUNTLET] = { "was pummeled by", "", "gauntletShader" },
	[C.MOD_MACHINEGUN] = { "was machinegunned by", "", "machinegunShader" },
	[C.MOD_SHOTGUN] = { "was gunned down by", "", "shotgunShader" },
	[C.MOD_GRENADE] = { "ate", "'s grenade", "grenadeShader" },
	[C.MOD_GRENADE_SPLASH] = { "was shredded by", "'s shrapnel", "grenadeShader" },
	[C.MOD_ROCKET] = { "ate", "'s rocket", "rocketShader" },
	[C.MOD_ROCKET_SPLASH] = { "almost dodged", "'s rocket", "rocketShader" },
	[C.MOD_PLASMA] = { "was melted by", "'s plasmagun", "plasmaShader" },
	[C.MOD_PLASMA_SPLASH] = { "was melted by", "'s plasmagun", "plasmaShader" },
	[C.MOD_RAILGUN] = { "was railed by", "", "railgunShader" },
	[C.MOD_LIGHTNING] = { "was electrocuted by", "", "lightninggunShader" },
	[C.MOD_BFG] = { "was blasted by", "'s BFG", "bfgShader" },
	[C.MOD_BFG_SPLASH] = { "was blasted by", "'s BFG", "bfgShader" },
	[C.MOD_NAIL] = { "was nailed by", "", "nailgunShader" },
	[C.MOD_CHAINGUN] = { "got lead poisoning from", "'s Chaingun", "chaingunShader" },
	[C.MOD_PROXIMITY_MINE] = { "was too close to", "'s Prox Mine", "proxlauncherShader" },
	[C.MOD_KAMIKAZE] = { "falls to", "'s Kamikaze blast", "kamikazeShader" },
	[C.MOD_JUICED] = { "was juiced by", "", "proxlauncherShader" },
	[C.MOD_TELEFRAG] = { "tried to invade", "'s personal space", "skullShader" },
	[C.MOD_LAVA] = { "was given a hot bath by", "", "skullShader" },
	[C.MOD_SLIME] = { "was given a acid bath by", "", "skullShader" },
	[C.MOD_FALLING] = { "was given a small push by", "", "skullShader" },
	[C.MOD_TRIGGER_HURT] = { "was helped on the way by", "", "skullShader" },
	[C.MOD_CRUSH] = { "was crushed in", "'s trap", "skullShader" },
	[C.MOD_SUICIDE] = { "was too eager against", "", "skullShader" },
}

local function genderText(gender, female, neuter, male)
	if gender == C.GENDER_FEMALE then
		return female
	elseif gender == C.GENDER_NEUTER then
		return neuter
	end
	return male
end

--[[
=============
CG_Obituary
=============
]]
local function CG_Obituary(ent)
	local cgs = G.cgs
	local cg = G.cg
	local media = cgs.media
	local mod = ent.eventParm
	local target = ent.otherEntityNum
	local attacker = ent.otherEntityNum2
	local message, message2
	local attackerInfo
	local causeShader
	local lastFrag = cgs.fragMsg[C.FRAGMSG_MAX - 1]
	local outputMode = G.cg_obituaryOutput.integer

	if target < 0 or target >= C.MAX_CLIENTS then
		G.CG_Error("CG_Obituary: target out of range")
	end
	local ci = cgs.clientinfo[target]

	if attacker < 0 or attacker >= C.MAX_CLIENTS then
		attacker = C.ENTITYNUM_WORLD
		attackerInfo = nil
	else
		attackerInfo = G.CG_ConfigString(C.CS_PLAYERS + attacker)
	end

	local targetInfo = G.CG_ConfigString(C.CS_PLAYERS + target)
	local targetName = string.sub(Q.Info_ValueForKey(targetInfo, "n"), 1, 30) .. "^7"

	message2 = ""

	-- check for single client messages
	causeShader = media.skullShader
	if attacker ~= C.ENTITYNUM_WORLD then
		message = nil
	else
		message = worldMessages[mod]
	end

	if attacker == target then
		local gender = ci.gender
		if mod == C.MOD_KAMIKAZE then
			message = "goes out with a bang"
			causeShader = media.kamikazeShader
		elseif mod == C.MOD_GRENADE_SPLASH then
			message = genderText(
				gender,
				"tripped on her own grenade",
				"tripped on their own grenade",
				"tripped on his own grenade"
			)
			causeShader = media.grenadeShader
		elseif mod == C.MOD_ROCKET_SPLASH then
			message = genderText(gender, "blew herself up", "blew themself up", "blew himself up")
			causeShader = media.rocketShader
		elseif mod == C.MOD_PLASMA_SPLASH then
			message = genderText(gender, "melted herself", "melted themself", "melted himself")
			causeShader = media.plasmaShader
		elseif mod == C.MOD_BFG_SPLASH then
			message = "should have used a smaller gun"
			causeShader = media.bfgShader
		elseif mod == C.MOD_PROXIMITY_MINE then
			message = genderText(gender, "found her prox mine", "found their prox mine", "found his prox mine")
			causeShader = media.proxlauncherShader
		else
			message = genderText(gender, "killed herself", "killed themself", "killed himself")
			causeShader = media.skullShader
		end
	end

	-- If a suicide happens while disconnecting
	-- then we might not have a targetName
	if message ~= nil and #targetName ~= 0 then
		if outputMode == 1 or outputMode == 4 then
			G.CG_Printf(Q.va("%s %s.\n", targetName, message))
		end
		if outputMode >= 2 then
			pushFrag()
			lastFrag.targetName = string.sub(targetName, 1, 31)
			lastFrag.causeShader = causeShader
			lastFrag.fragTime = cg.time
			lastFrag.teamFrag = false
			lastFrag.message = string.sub(Q.va("%s %s.", targetName, message), 1, 199)
		end

		return
	end

	-- check for kill messages from the current clientNum
	if attacker == cg.snap.ps.clientNum then
		local s
		if cgs.gametype < C.GT_TEAM then
			s = Q.va(
				"You fragged %s\n%s place with %i",
				targetName,
				G.CG_PlaceString(cg.snap.ps.persistant[C.PERS_RANK] + 1),
				cg.snap.ps.persistant[C.PERS_SCORE]
			)
		else
			if ent.generic1 ~= 0 then
				s = Q.va("You fragged your ^1TEAMMATE^7 %s", targetName)
			else
				s = Q.va("You fragged %s", targetName)
			end
		end
		G.CG_CenterPrint(s, C.SCREEN_HEIGHT * 0.30, Q.int(C.BIGCHAR_WIDTH * G.cg_fragmsgsize.value))
	end

	-- check for double client messages
	local attackerName
	if attackerInfo == nil then
		attacker = C.ENTITYNUM_WORLD
		attackerName = "noname"
	else
		attackerName = string.sub(Q.Info_ValueForKey(attackerInfo, "n"), 1, 30) .. "^7"
		-- check for kill messages about the current clientNum
		if target == cg.snap.ps.clientNum then
			cg.killerName = string.sub(attackerName, 1, 31)
		end
	end

	if attacker ~= C.ENTITYNUM_WORLD then
		local entry = attackerMessages[mod]
		if entry ~= nil then
			message, message2, causeShader = entry[1], entry[2], media[entry[3]]
		else
			message = "was killed by"
			causeShader = media.skullShader
		end

		if ent.generic1 ~= 0 then
			message = "was killed by ^1TEAMMATE^7"
			message2 = ""
		end

		if outputMode == 1 or outputMode == 4 then
			G.CG_Printf(Q.va("%s %s %s%s\n", targetName, message, attackerName, message2))
		end
		if outputMode >= 2 then
			pushFrag()
			lastFrag.teamFrag = ent.generic1 ~= 0
			lastFrag.targetName = string.sub(targetName, 1, 31)
			lastFrag.attackerName = string.sub(attackerName, 1, 31)
			lastFrag.causeShader = causeShader
			lastFrag.fragTime = cg.time
			lastFrag.message = string.sub(Q.va("%s %s %s%s.", targetName, message, attackerName, message2), 1, 199)
		end

		return
	end

	-- we don't know what it was
	if outputMode == 1 or outputMode == 4 then
		G.CG_Printf(Q.va("%s died.\n", targetName))
	end
	if outputMode >= 2 then
		pushFrag()
		lastFrag.targetName = string.sub(targetName, 1, 31)
		lastFrag.attackerName = string.sub(attackerName, 1, 31)
		lastFrag.causeShader = media.skullShader
		lastFrag.fragTime = cg.time
		lastFrag.message = string.sub(Q.va("%s died.", targetName), 1, 199)
	end
end

--==========================================================================

--[[
===============
CG_UseItem
===============
]]
local function CG_UseItem(cent)
	local cg = G.cg
	local cgs = G.cgs
	local es = cent.currentState

	local itemNum = band(es.event, bnot(C.EV_EVENT_BITS)) - C.EV_USE_ITEM0
	if itemNum < 0 or itemNum > C.HI_NUM_HOLDABLE then
		itemNum = 0
	end

	-- print a message if the local player
	if es.number == cg.snap.ps.clientNum then
		if itemNum == 0 then
			G.CG_CenterPrint("No item to use", C.SCREEN_HEIGHT * 0.30, C.BIGCHAR_WIDTH)
		else
			local item = BG.BG_FindItemForHoldable(itemNum)
			G.CG_CenterPrint(Q.va("Use %s", item.pickup_name), C.SCREEN_HEIGHT * 0.30, C.BIGCHAR_WIDTH)
		end
	end

	if itemNum == C.HI_TELEPORTER or itemNum == C.HI_KAMIKAZE or itemNum == C.HI_PORTAL then
		return
	elseif itemNum == C.HI_MEDKIT then
		local clientNum = cent.currentState.clientNum
		if clientNum >= 0 and clientNum < C.MAX_CLIENTS then
			local ci = cgs.clientinfo[clientNum]
			ci.medkitUsageTime = cg.time
		end
		trap.S_StartSound(nil, es.number, C.CHAN_BODY, cgs.media.medkitSound)
	elseif itemNum == C.HI_INVULNERABILITY then
		trap.S_StartSound(nil, es.number, C.CHAN_BODY, cgs.media.useInvulnerabilitySound)
	else
		trap.S_StartSound(nil, es.number, C.CHAN_BODY, cgs.media.useNothingSound)
	end
end

--[[
 Function to check if a new is better according to cg_weaponOrder
 If the order is unspecified (at least one of the weapons are not specified in cg_weaponOrder) the result is false
 @return true if newWeapon is placed after currentWeapon in cg_weaponOrder. False otherwise
]]
local function CG_WeaponHigher(currentWeapon, newWeapon)
	local order = G.cg_weaponOrder.string
	local currentScore = string.find(order, Q.va("/%i/", currentWeapon), 1, true)
	local newScore = string.find(order, Q.va("/%i/", newWeapon), 1, true)
	if newScore == nil or currentScore == nil then
		return false
	end
	return newScore > currentScore
end

--[[
================
CG_ItemPickup

A new item was picked up this frame
================
]]
local function CG_ItemPickup(itemNum)
	local cg = G.cg
	local itemlist = BG.bg_itemlist
	local autoswitch = G.cg_autoswitch.integer
	cg.itemPickup = itemNum
	cg.itemPickupTime = cg.time
	cg.itemPickupBlendTime = cg.time
	-- see if it should be the grabbed weapon
	if itemlist[itemNum].giType == C.IT_WEAPON then
		local tag = itemlist[itemNum].giTag
		local owned = band(cg.snap.ps.stats[C.STAT_WEAPONS], lshift(1, tag)) ~= 0
		local select = false
		if autoswitch == 1 and tag ~= C.WP_MACHINEGUN then
			select = true
		end
		if autoswitch == 2 and not owned then
			select = true
		end
		if autoswitch == 3 and CG_WeaponHigher(cg.weaponSelect, tag) then
			select = true
		end
		if autoswitch == 4 and not owned and CG_WeaponHigher(cg.weaponSelect, tag) then
			select = true
		end
		if select then
			cg.weaponSelectTime = cg.time
			cg.weaponSelect = tag
		end
	end
end

--[[
================
CG_WaterLevel

Returns waterlevel for entity origin
================
]]
function G.CG_WaterLevel(cent)
	local viewheight
	local anim = band(cent.currentState.legsAnim, bnot(C.ANIM_TOGGLEBIT))

	if anim == C.LEGS_WALKCR or anim == C.LEGS_IDLECR then
		viewheight = C.CROUCH_VIEWHEIGHT
	else
		if G.cg_enableQ.integer ~= 0 then
			viewheight = C.QUACK_VIEWHEIGHT
		else
			viewheight = C.DEFAULT_VIEWHEIGHT
		end
	end

	--
	-- get waterlevel, accounting for ducking
	--
	local waterlevel = 0
	local point = Q.vec3(
		cent.lerpOrigin[0],
		cent.lerpOrigin[1],
		cent.lerpOrigin[2] + C.MINS_Z + 1
	)
	local contents = G.CG_PointContents(point, -1)

	if band(contents, C.MASK_WATER) ~= 0 then
		local sample2 = viewheight - C.MINS_Z
		local sample1 = Q.idiv(sample2, 2)
		waterlevel = 1
		point[2] = cent.lerpOrigin[2] + C.MINS_Z + sample1
		contents = G.CG_PointContents(point, -1)

		if band(contents, C.MASK_WATER) ~= 0 then
			waterlevel = 2
			point[2] = cent.lerpOrigin[2] + C.MINS_Z + sample2
			contents = G.CG_PointContents(point, -1)

			if band(contents, C.MASK_WATER) ~= 0 then
				waterlevel = 3
			end
		end
	end

	return waterlevel
end

--[[
================
CG_PainEvent

Also called by playerstate transition
================
]]
function G.CG_PainEvent(cent, health)
	local cg = G.cg

	-- don't do more than two pain sounds a second
	if cg.time - cent.pe.painTime < 500 then
		return
	end

	local snd
	if health < 25 then
		snd = "*pain25_1.wav"
	elseif health < 50 then
		snd = "*pain50_1.wav"
	elseif health < 75 then
		snd = "*pain75_1.wav"
	else
		snd = "*pain100_1.wav"
	end
	-- play a gurp sound instead of a normal pain sound
	local number = cent.currentState.number
	if G.CG_WaterLevel(cent) == 3 then
		if band(Q.rand(), 1) ~= 0 then
			trap.S_StartSound(nil, number, C.CHAN_VOICE, G.CG_CustomSound(number, "sound/player/gurp1.wav"))
		else
			trap.S_StartSound(nil, number, C.CHAN_VOICE, G.CG_CustomSound(number, "sound/player/gurp2.wav"))
		end
	else
		trap.S_StartSound(nil, number, C.CHAN_VOICE, G.CG_CustomSound(number, snd))
	end
	-- save pain time for programitic twitch animation
	cent.pe.painTime = cg.time
	cent.pe.painDirection = bxor(cent.pe.painDirection, 1)
end

local footstepEvents = {
	[C.EV_FOOTSTEP_METAL] = C.FOOTSTEP_METAL,
	[C.EV_FOOTSTEP_SNOW] = C.FOOTSTEP_SNOW,
	[C.EV_FOOTSTEP_WOOD] = C.FOOTSTEP_WOOD,
	[C.EV_FOOTSTEP_SAND] = C.FOOTSTEP_SAND,
	[C.EV_FOOTSTEP_GRAVEL] = C.FOOTSTEP_GRAVEL,
	[C.EV_FOOTSTEP_FOILAGE] = C.FOOTSTEP_FOILAGE,
	[C.EV_FOOTSTEP_ICE] = C.FOOTSTEP_ICE,
	[C.EV_FOOTSTEP_GLASS] = C.FOOTSTEP_GLASS,
	[C.EV_FOOTSPLASH] = C.FOOTSTEP_SPLASH,
	[C.EV_FOOTWADE] = C.FOOTSTEP_SPLASH,
	[C.EV_SWIM] = C.FOOTSTEP_SPLASH,
}

local function teamSoundEvent(parm)
	local cg = G.cg
	local cgs = G.cgs
	local media = cgs.media
	local team = cg.snap.ps.persistant[C.PERS_TEAM]
	local add = G.CG_AddBufferedSound

	if parm == C.GTS_RED_CAPTURE then
		if team == C.TEAM_RED then
			add(media.captureYourTeamSound)
		else
			add(media.captureOpponentSound)
		end
	elseif parm == C.GTS_BLUE_CAPTURE then
		if team == C.TEAM_BLUE then
			add(media.captureYourTeamSound)
		else
			add(media.captureOpponentSound)
		end
	elseif parm == C.GTS_RED_RETURN then
		if team == C.TEAM_RED then
			add(media.returnYourTeamSound)
		else
			add(media.returnOpponentSound)
		end
		add(media.blueFlagReturnedSound)
	elseif parm == C.GTS_BLUE_RETURN then
		if team == C.TEAM_BLUE then
			add(media.returnYourTeamSound)
		else
			add(media.returnOpponentSound)
		end
		add(media.redFlagReturnedSound)
	elseif parm == C.GTS_RED_TAKEN then
		-- if this player picked up the flag then a sound is played in CG_CheckLocalSounds
		local pw = cg.snap.ps.powerups
		if pw[C.PW_BLUEFLAG] ~= 0 or pw[C.PW_NEUTRALFLAG] ~= 0 then
			return
		end
		if team == C.TEAM_BLUE then
			if cgs.gametype == C.GT_1FCTF then
				add(media.yourTeamTookTheFlagSound)
			else
				add(media.enemyTookYourFlagSound)
			end
		elseif team == C.TEAM_RED then
			if cgs.gametype == C.GT_1FCTF then
				add(media.enemyTookTheFlagSound)
			else
				add(media.yourTeamTookEnemyFlagSound)
			end
		end
	elseif parm == C.GTS_BLUE_TAKEN then
		local pw = cg.snap.ps.powerups
		if pw[C.PW_REDFLAG] ~= 0 or pw[C.PW_NEUTRALFLAG] ~= 0 then
			return
		end
		if team == C.TEAM_RED then
			if cgs.gametype == C.GT_1FCTF then
				add(media.yourTeamTookTheFlagSound)
			else
				add(media.enemyTookYourFlagSound)
			end
		elseif team == C.TEAM_BLUE then
			if cgs.gametype == C.GT_1FCTF then
				add(media.enemyTookTheFlagSound)
			else
				add(media.yourTeamTookEnemyFlagSound)
			end
		end
	elseif parm == C.GTS_REDOBELISK_ATTACKED then
		if team == C.TEAM_RED then
			add(media.yourBaseIsUnderAttackSound)
		end
	elseif parm == C.GTS_BLUEOBELISK_ATTACKED then
		if team == C.TEAM_BLUE then
			add(media.yourBaseIsUnderAttackSound)
		end
	elseif parm == C.GTS_REDTEAM_SCORED then
		add(media.redScoredSound)
	elseif parm == C.GTS_BLUETEAM_SCORED then
		add(media.blueScoredSound)
	elseif parm == C.GTS_REDTEAM_TOOK_LEAD then
		add(media.redLeadsSound)
	elseif parm == C.GTS_BLUETEAM_TOOK_LEAD then
		add(media.blueLeadsSound)
	elseif parm == C.GTS_TEAMS_ARE_TIED then
		add(media.teamsTiedSound)
	elseif parm == C.GTS_KAMIKAZE then
		trap.S_StartLocalSound(media.kamikazeFarSound, C.CHAN_ANNOUNCER)
	end
end

local function debugName(name)
	if G.cg_debugEvents.integer ~= 0 then
		G.CG_Printf(name .. "\n")
	end
end

--[[
==============
CG_EntityEvent

An entity has an event value
also called by CG_CheckPlayerstateEvents
==============
]]
function G.CG_EntityEvent(cent, position)
	local cg = G.cg
	local cgs = G.cgs
	local media = cgs.media
	local es = cent.currentState
	local event = band(es.event, bnot(C.EV_EVENT_BITS))
	local dir = Q.vec3(0, 0, 0)

	if G.cg_debugEvents.integer ~= 0 then
		G.CG_Printf(Q.va("ent:%3i  event:%3i ", es.number, event))
	end

	if event == 0 then
		debugName("ZEROEVENT")
		return
	end

	local clientNum = es.clientNum
	if clientNum < 0 or clientNum >= C.MAX_CLIENTS then
		clientNum = 0
	end
	local ci = cgs.clientinfo[clientNum]

	if event == C.EV_FOOTSTEP then
		debugName("EV_FOOTSTEP")
		if G.cg_footsteps.integer ~= 0 then
			trap.S_StartSound(nil, es.number, C.CHAN_BODY, media.footsteps[ci.footsteps][band(Q.rand(), 3)])
		end
	elseif footstepEvents[event] ~= nil then
		debugName("EV_FOOTSTEP_x")
		if G.cg_footsteps.integer ~= 0 then
			trap.S_StartSound(nil, es.number, C.CHAN_BODY, media.footsteps[footstepEvents[event]][band(Q.rand(), 3)])
		end
	elseif event == C.EV_FALL_SHORT then
		debugName("EV_FALL_SHORT")
		trap.S_StartSound(nil, es.number, C.CHAN_AUTO, media.landSound)
		if clientNum == cg.predictedPlayerState.clientNum then
			-- smooth landing z changes
			cg.landChange = -8
			cg.landTime = cg.time
		end
	elseif event == C.EV_FALL_MEDIUM then
		debugName("EV_FALL_MEDIUM")
		-- use normal pain sound
		trap.S_StartSound(nil, es.number, C.CHAN_VOICE, G.CG_CustomSound(es.number, "*pain100_1.wav"))
		if clientNum == cg.predictedPlayerState.clientNum then
			cg.landChange = -16
			cg.landTime = cg.time
		end
	elseif event == C.EV_FALL_FAR then
		debugName("EV_FALL_FAR")
		trap.S_StartSound(nil, es.number, C.CHAN_AUTO, G.CG_CustomSound(es.number, "*fall1.wav"))
		cent.pe.painTime = cg.time -- don't play a pain sound right after this
		if clientNum == cg.predictedPlayerState.clientNum then
			cg.landChange = -24
			cg.landTime = cg.time
		end
	elseif event == C.EV_STEP_4 or event == C.EV_STEP_8 or event == C.EV_STEP_12 or event == C.EV_STEP_16 then
		-- smooth out step up transitions
		debugName("EV_STEP")
		if clientNum ~= cg.predictedPlayerState.clientNum then
			return
		end
		-- if we are interpolating, we don't need to smooth steps
		if
			cg.demoPlayback
			or band(cg.snap.ps.pm_flags, C.PMF_FOLLOW) ~= 0
			or G.cg_nopredict.integer ~= 0
			or G.cg_synchronousClients.integer ~= 0
		then
			return
		end
		-- check for stepping up before a previous step is completed
		local delta = cg.time - cg.stepTime
		local oldStep
		if delta < C.STEP_TIME then
			oldStep = cg.stepChange * (C.STEP_TIME - delta) / C.STEP_TIME
		else
			oldStep = 0
		end

		-- add this amount
		local step = 4 * (event - C.EV_STEP_4 + 1)
		cg.stepChange = oldStep + step
		if cg.stepChange > C.MAX_STEP_CHANGE then
			cg.stepChange = C.MAX_STEP_CHANGE
		end
		cg.stepTime = cg.time
	elseif event == C.EV_JUMP_PAD then
		debugName("EV_JUMP_PAD")
		local up = Q.vec3(0, 0, 1)
		G.CG_SmokePuff(cent.lerpOrigin, up, 32, 1, 1, 1, 0.33, 1000, cg.time, 0, C.LEF_PUFF_DONT_SCALE, media.smokePuffShader)

		-- boing sound at origin, jump sound on player
		trap.S_StartSound(cent.lerpOrigin, -1, C.CHAN_VOICE, media.jumpPadSound)
		trap.S_StartSound(nil, es.number, C.CHAN_VOICE, G.CG_CustomSound(es.number, "*jump1.wav"))
	elseif event == C.EV_JUMP then
		debugName("EV_JUMP")
		trap.S_StartSound(nil, es.number, C.CHAN_VOICE, G.CG_CustomSound(es.number, "*jump1.wav"))
	elseif event == C.EV_TAUNT then
		debugName("EV_TAUNT")
		trap.S_StartSound(nil, es.number, C.CHAN_VOICE, G.CG_CustomSound(es.number, "*taunt.wav"))
	elseif event == C.EV_WATER_TOUCH then
		debugName("EV_WATER_TOUCH")
		trap.S_StartSound(nil, es.number, C.CHAN_AUTO, media.watrInSound)
	elseif event == C.EV_WATER_LEAVE then
		debugName("EV_WATER_LEAVE")
		trap.S_StartSound(nil, es.number, C.CHAN_AUTO, media.watrOutSound)
	elseif event == C.EV_WATER_UNDER then
		debugName("EV_WATER_UNDER")
		trap.S_StartSound(nil, es.number, C.CHAN_AUTO, media.watrUnSound)
	elseif event == C.EV_WATER_CLEAR then
		debugName("EV_WATER_CLEAR")
		trap.S_StartSound(nil, es.number, C.CHAN_AUTO, G.CG_CustomSound(es.number, "*gasp.wav"))
	elseif event == C.EV_ITEM_PICKUP then
		debugName("EV_ITEM_PICKUP")
		local index = es.eventParm -- player predicted

		if index < 1 or index >= BG.bg_numItems then
			return
		end
		local item = BG.bg_itemlist[index]

		-- powerups and team items will have a separate global sound, this one
		-- will be played at prediction time
		if item.giType == C.IT_POWERUP or item.giType == C.IT_TEAM then
			trap.S_StartSound(nil, es.number, C.CHAN_AUTO, media.n_healthSound)
		elseif item.giType == C.IT_PERSISTANT_POWERUP then
			if item.giTag == C.PW_SCOUT then
				trap.S_StartSound(nil, es.number, C.CHAN_AUTO, media.scoutSound)
			elseif item.giTag == C.PW_GUARD then
				trap.S_StartSound(nil, es.number, C.CHAN_AUTO, media.guardSound)
			elseif item.giTag == C.PW_DOUBLER then
				trap.S_StartSound(nil, es.number, C.CHAN_AUTO, media.doublerSound)
			elseif item.giTag == C.PW_AMMOREGEN then
				trap.S_StartSound(nil, es.number, C.CHAN_AUTO, media.ammoregenSound)
			end
		else
			trap.S_StartSound(nil, es.number, C.CHAN_AUTO, trap.S_RegisterSound(item.pickup_sound, false))
		end

		-- show icon and name on status bar
		if es.number == cg.snap.ps.clientNum then
			CG_ItemPickup(index)
		end
	elseif event == C.EV_GLOBAL_ITEM_PICKUP then
		debugName("EV_GLOBAL_ITEM_PICKUP")
		local index = es.eventParm -- player predicted

		if index < 1 or index >= BG.bg_numItems then
			return
		end
		local item = BG.bg_itemlist[index]
		-- powerup pickups are global
		if item.pickup_sound ~= nil and item.pickup_sound ~= "" then
			trap.S_StartSound(nil, cg.snap.ps.clientNum, C.CHAN_AUTO, trap.S_RegisterSound(item.pickup_sound, false))
		end

		-- show icon and name on status bar
		if es.number == cg.snap.ps.clientNum then
			CG_ItemPickup(index)
		end

	--
	-- weapon events
	--
	elseif event == C.EV_NOAMMO then
		debugName("EV_NOAMMO")
		if es.number == cg.snap.ps.clientNum then
			G.CG_OutOfAmmoChange()
		end
	elseif event == C.EV_CHANGE_WEAPON then
		debugName("EV_CHANGE_WEAPON")
		trap.S_StartSound(nil, es.number, C.CHAN_AUTO, media.selectSound)
	elseif event == C.EV_FIRE_WEAPON then
		debugName("EV_FIRE_WEAPON")
		G.CG_FireWeapon(cent)
	elseif event >= C.EV_USE_ITEM0 and event <= C.EV_USE_ITEM15 then
		debugName("EV_USE_ITEMx")
		CG_UseItem(cent)

	--
	-- other events
	--
	elseif event == C.EV_PLAYER_TELEPORT_IN then
		debugName("EV_PLAYER_TELEPORT_IN")
		trap.S_StartSound(nil, es.number, C.CHAN_AUTO, media.teleInSound)
		if G.cg_leiEnhancement.integer ~= 0 then
			trap.R_LFX_ParticleEffect(18, cent.lerpOrigin, cent.currentState.angles)
		else
			G.CG_SpawnEffect(position)
		end
	elseif event == C.EV_PLAYER_TELEPORT_OUT then
		debugName("EV_PLAYER_TELEPORT_OUT")
		trap.S_StartSound(nil, es.number, C.CHAN_AUTO, media.teleOutSound)
		if G.cg_leiEnhancement.integer ~= 0 then
			trap.R_LFX_ParticleEffect(18, cent.lerpOrigin, cent.currentState.angles)
		else
			G.CG_SpawnEffect(position)
		end
	elseif event == C.EV_ITEM_POP then
		debugName("EV_ITEM_POP")
		trap.S_StartSound(nil, es.number, C.CHAN_AUTO, media.respawnSound)
	elseif event == C.EV_ITEM_RESPAWN then
		debugName("EV_ITEM_RESPAWN")
		cent.miscTime = cg.time -- scale up from this
		trap.S_StartSound(nil, es.number, C.CHAN_AUTO, media.respawnSound)

		if G.cg_leiEnhancement.integer ~= 0 then
			trap.R_LFX_ParticleEffect(41, cent.lerpOrigin, cent.currentState.angles)
		end
	elseif event == C.EV_GRENADE_BOUNCE then
		debugName("EV_GRENADE_BOUNCE")
		if band(Q.rand(), 1) ~= 0 then
			trap.S_StartSound(nil, es.number, C.CHAN_AUTO, media.hgrenb1aSound)
		else
			trap.S_StartSound(nil, es.number, C.CHAN_AUTO, media.hgrenb2aSound)
		end
	elseif event == C.EV_PROXIMITY_MINE_STICK then
		debugName("EV_PROXIMITY_MINE_STICK")
		if band(es.eventParm, C.SURF_FLESH) ~= 0 then
			trap.S_StartSound(nil, es.number, C.CHAN_AUTO, media.wstbimplSound)
		elseif band(es.eventParm, C.SURF_METALSTEPS) ~= 0 then
			trap.S_StartSound(nil, es.number, C.CHAN_AUTO, media.wstbimpmSound)
		else
			trap.S_StartSound(nil, es.number, C.CHAN_AUTO, media.wstbimpdSound)
		end
	elseif event == C.EV_PROXIMITY_MINE_TRIGGER then
		debugName("EV_PROXIMITY_MINE_TRIGGER")
		trap.S_StartSound(nil, es.number, C.CHAN_AUTO, media.wstbactvSound)
	elseif event == C.EV_KAMIKAZE then
		debugName("EV_KAMIKAZE")
		G.CG_KamikazeEffect(cent.lerpOrigin)
	elseif event == C.EV_OBELISKEXPLODE then
		debugName("EV_OBELISKEXPLODE")
		if G.cg_leiEnhancement.integer ~= 0 then
			trap.R_LFX_ParticleEffect(17, cent.lerpOrigin, cent.currentState.angles)
		else
			G.CG_ObeliskExplode(cent.lerpOrigin, es.eventParm)
		end
	elseif event == C.EV_OBELISKPAIN then
		debugName("EV_OBELISKPAIN")
		G.CG_ObeliskPain(cent.lerpOrigin)
	elseif event == C.EV_INVUL_IMPACT then
		debugName("EV_INVUL_IMPACT")
		if G.cg_leiEnhancement.integer ~= 0 then
			trap.R_LFX_ParticleEffect(42, cent.lerpOrigin, cent.currentState.angles)
		else
			G.CG_InvulnerabilityImpact(cent.lerpOrigin, cent.currentState.angles)
		end
	elseif event == C.EV_JUICED then
		debugName("EV_JUICED")
		G.CG_InvulnerabilityJuiced(cent.lerpOrigin)
	elseif event == C.EV_LIGHTNINGBOLT then
		debugName("EV_LIGHTNINGBOLT")
		G.CG_LightningBoltBeam(es.origin2, es.pos.trBase)
	elseif event == C.EV_SCOREPLUM then
		debugName("EV_SCOREPLUM")
		G.CG_ScorePlum(cent.currentState.otherEntityNum, cent.lerpOrigin, cent.currentState.time)

	--
	-- missile impacts
	--
	elseif event == C.EV_MISSILE_HIT then
		debugName("EV_MISSILE_HIT")
		Q.ByteToDir(es.eventParm, dir)
		G.CG_MissileHitPlayer(es.weapon, position, dir, es.otherEntityNum)
	elseif event == C.EV_MISSILE_MISS then
		debugName("EV_MISSILE_MISS")
		Q.ByteToDir(es.eventParm, dir)
		G.CG_MissileHitWall(es.weapon, 0, position, dir, C.IMPACTSOUND_DEFAULT)
	elseif event == C.EV_MISSILE_MISS_METAL then
		debugName("EV_MISSILE_MISS_METAL")
		Q.ByteToDir(es.eventParm, dir)
		G.CG_MissileHitWall(es.weapon, 0, position, dir, C.IMPACTSOUND_METAL)
	elseif event == C.EV_RAILTRAIL then
		debugName("EV_RAILTRAIL")
		cent.currentState.weapon = C.WP_RAILGUN
		-- if the client is us, unlagged is on server-side, and we've got it client-side
		local d = G.cg_delag.integer
		if
			es.clientNum == cg.predictedPlayerState.clientNum
			and cgs.delagHitscan ~= 0
			and (band(d, 1) ~= 0 or band(d, 16) ~= 0)
		then
			-- do nothing, because it was already predicted
		else
			if es.clientNum == cg.snap.ps.clientNum and not cg.renderingThirdPerson then
				if G.cg_drawGun.integer == 2 then
					Q.VectorMA(es.origin2, 8, cg.refdef.viewaxis[1], es.origin2)
				elseif G.cg_drawGun.integer == 3 then
					Q.VectorMA(es.origin2, 4, cg.refdef.viewaxis[1], es.origin2)
				end
			end

			-- draw a rail trail, because it wasn't predicted
			G.CG_RailTrail(ci, es.origin2, es.pos.trBase)

			-- if the end was on a nomark surface, don't make an explosion
			if es.eventParm ~= 255 then
				Q.ByteToDir(es.eventParm, dir)
				G.CG_MissileHitWall(es.weapon, es.clientNum, position, dir, C.IMPACTSOUND_DEFAULT)
			end
		end
	elseif event == C.EV_BULLET_HIT_WALL then
		debugName("EV_BULLET_HIT_WALL")
		local d = G.cg_delag.integer
		if
			es.clientNum == cg.predictedPlayerState.clientNum
			and cgs.delagHitscan ~= 0
			and (band(d, 1) ~= 0 or band(d, 2) ~= 0)
		then
			-- do nothing, because it was already predicted
		else
			-- do the bullet, because it wasn't predicted
			Q.ByteToDir(es.eventParm, dir)
			G.CG_Bullet(es.pos.trBase, es.otherEntityNum, dir, false, C.ENTITYNUM_WORLD)
		end
	elseif event == C.EV_BULLET_HIT_FLESH then
		debugName("EV_BULLET_HIT_FLESH")
		local d = G.cg_delag.integer
		if
			es.clientNum == cg.predictedPlayerState.clientNum
			and cgs.delagHitscan ~= 0
			and (band(d, 1) ~= 0 or band(d, 2) ~= 0)
		then
			-- do nothing, because it was already predicted
		else
			-- do the bullet, because it wasn't predicted
			G.CG_Bullet(es.pos.trBase, es.otherEntityNum, dir, true, es.eventParm)
		end
	elseif event == C.EV_SHOTGUN then
		debugName("EV_SHOTGUN")
		local d = G.cg_delag.integer
		if
			es.otherEntityNum == cg.predictedPlayerState.clientNum
			and cgs.delagHitscan ~= 0
			and (band(d, 1) ~= 0 or band(d, 4) ~= 0)
		then
			-- do nothing, because it was already predicted
		else
			-- do the shotgun pattern, because it wasn't predicted
			G.CG_ShotgunFire(es)
		end
	elseif event == C.EV_GENERAL_SOUND then
		debugName("EV_GENERAL_SOUND")
		local snd = cgs.gameSounds[es.eventParm] or 0
		if snd ~= 0 then
			trap.S_StartSound(nil, es.number, C.CHAN_VOICE, snd)
		else
			local s = G.CG_ConfigString(C.CS_SOUNDS + es.eventParm)
			trap.S_StartSound(nil, es.number, C.CHAN_VOICE, G.CG_CustomSound(es.number, s))
		end
	elseif event == C.EV_GLOBAL_SOUND then -- play from the player's head so it never diminishes
		debugName("EV_GLOBAL_SOUND")
		local snd = cgs.gameSounds[es.eventParm] or 0
		if snd ~= 0 then
			trap.S_StartSound(nil, cg.snap.ps.clientNum, C.CHAN_AUTO, snd)
		else
			local s = G.CG_ConfigString(C.CS_SOUNDS + es.eventParm)
			trap.S_StartSound(nil, cg.snap.ps.clientNum, C.CHAN_AUTO, G.CG_CustomSound(es.number, s))
		end
	elseif event == C.EV_GLOBAL_TEAM_SOUND then -- play from the player's head so it never diminishes
		debugName("EV_GLOBAL_TEAM_SOUND")
		teamSoundEvent(es.eventParm)
	elseif event == C.EV_PAIN then
		-- local player sounds are triggered in CG_CheckLocalSounds,
		-- so ignore events on the player
		debugName("EV_PAIN")
		if cent.currentState.number ~= cg.snap.ps.clientNum then
			G.CG_PainEvent(cent, es.eventParm)
		end
	elseif event == C.EV_DEATH1 or event == C.EV_DEATH2 or event == C.EV_DEATH3 then
		debugName("EV_DEATHx")

		if G.CG_WaterLevel(cent) == 3 then
			trap.S_StartSound(nil, es.number, C.CHAN_VOICE, G.CG_CustomSound(es.number, "*drown.wav"))
		else
			trap.S_StartSound(
				nil,
				es.number,
				C.CHAN_VOICE,
				G.CG_CustomSound(es.number, Q.va("*death%i.wav", event - C.EV_DEATH1 + 1))
			)
		end
	elseif event == C.EV_OBITUARY then
		debugName("EV_OBITUARY")
		CG_Obituary(es)

	--
	-- powerup events
	--
	elseif event == C.EV_POWERUP_QUAD then
		debugName("EV_POWERUP_QUAD")
		if es.number == cg.snap.ps.clientNum then
			cg.powerupActive = C.PW_QUAD
			cg.powerupTime = cg.time
		end
		trap.S_StartSound(nil, es.number, C.CHAN_ITEM, media.quadSound)
	elseif event == C.EV_POWERUP_BATTLESUIT then
		debugName("EV_POWERUP_BATTLESUIT")
		if es.number == cg.snap.ps.clientNum then
			cg.powerupActive = C.PW_BATTLESUIT
			cg.powerupTime = cg.time
		end
		trap.S_StartSound(nil, es.number, C.CHAN_ITEM, media.protectSound)
	elseif event == C.EV_POWERUP_REGEN then
		debugName("EV_POWERUP_REGEN")
		if es.number == cg.snap.ps.clientNum then
			cg.powerupActive = C.PW_REGEN
			cg.powerupTime = cg.time
		end
		trap.S_StartSound(nil, es.number, C.CHAN_ITEM, media.regenSound)
	elseif event == C.EV_GIB_PLAYER then
		debugName("EV_GIB_PLAYER")
		-- don't play gib sound when using the kamikaze because it interferes
		-- with the kamikaze sound, downside is that the gib sound will also
		-- not be played when someone is gibbed while just carrying the kamikaze
		if band(es.eFlags, C.EF_KAMIKAZE) == 0 then
			trap.S_StartSound(nil, es.number, C.CHAN_BODY, media.gibSound)
		end
		G.CG_GibPlayer(cent.lerpOrigin)
		if G.cg_leiEnhancement.integer ~= 0 then
			trap.R_LFX_ParticleEffect(16, cent.lerpOrigin, cent.currentState.angles)
		end
	elseif event == C.EV_STOPLOOPINGSOUND then
		debugName("EV_STOPLOOPINGSOUND")
		trap.S_StopLoopingSound(es.number)
		es.loopSound = 0
	elseif event == C.EV_DEBUG_LINE then
		debugName("EV_DEBUG_LINE")
		G.CG_Beam(cent)
	else
		debugName("UNKNOWN")
		G.CG_Error(Q.va("Unknown event: %i", event))
	end
end

--[[
==============
CG_CheckEvents

==============
]]
function G.CG_CheckEvents(cent)
	local cg = G.cg
	-- check for event-only entities
	if cent.currentState.eType > C.ET_EVENTS then
		if cent.previousEvent ~= 0 then
			return -- already fired
		end
		-- if this is a player event set the entity number of the client entity number
		if band(cent.currentState.eFlags, C.EF_PLAYER_EVENT) ~= 0 then
			cent.currentState.number = cent.currentState.otherEntityNum
		end

		cent.previousEvent = 1

		cent.currentState.event = cent.currentState.eType - C.ET_EVENTS
	else
		-- check for events riding with another entity
		if cent.currentState.event == cent.previousEvent then
			return
		end
		cent.previousEvent = cent.currentState.event
		if band(cent.currentState.event, bnot(C.EV_EVENT_BITS)) == 0 then
			return
		end
	end

	-- calculate the position at exactly the frame time
	BG.BG_EvaluateTrajectory(cent.currentState.pos, cg.snap.serverTime, cent.lerpOrigin)
	G.CG_SetEntitySoundPosition(cent)

	G.CG_EntityEvent(cent, cent.lerpOrigin)
end

return G
