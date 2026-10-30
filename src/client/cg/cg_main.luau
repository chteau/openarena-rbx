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
-- Luau port of code/cgame/cg_main.c (OpenArena 0.8.8, gamecode 9e0f0c0).
-- This part covers C lines 1-991 of the 0.8.8 source.

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local trap = require(script.Parent.Parent.sys.Trap)
local BG = require(script.Parent.Parent.adapters.BG)

G.forceModelModificationCount = -1

--[[
================
vmMain

This is the only way control passes into the module.
================
]]
function G.vmMain(command, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11)
	if command == C.CG_INIT then
		G.CG_Init(arg0, arg1, arg2)
		return 0
	elseif command == C.CG_SHUTDOWN then
		G.CG_Shutdown()
		return 0
	elseif command == C.CG_CONSOLE_COMMAND then
		return Q.b2i(G.CG_ConsoleCommand())
	elseif command == C.CG_DRAW_ACTIVE_FRAME then
		G.CG_DrawActiveFrame(arg0, arg1, arg2)
		G.CG_FairCvars()
		return 0
	elseif command == C.CG_CROSSHAIR_PLAYER then
		return G.CG_CrosshairPlayer()
	elseif command == C.CG_LAST_ATTACKER then
		return G.CG_LastAttacker()
	elseif command == C.CG_KEY_EVENT then
		G.CG_KeyEvent(arg0, arg1)
		return 0
	elseif command == C.CG_MOUSE_EVENT then
		G.CG_MouseEvent(arg0, arg1)
		return 0
	elseif command == C.CG_EVENT_HANDLING then
		G.CG_EventHandling(arg0)
		return 0
	else
		G.CG_Error("vmMain: unknown command %i", command)
	end
	return -1
end

-- vmCvar_t globals declared outside the cvarTable
G.cg_hudFiles = T.vmCvar_t()
G.cg_gun_frame = T.vmCvar_t()

-- { global name, cvar name, default, flags }
local cvarDefs = {
	{ "cg_ignore", "cg_ignore", "0", 0 }, -- used for debugging
	{ "cg_autoswitch", "cg_autoswitch", "1", C.CVAR_ARCHIVE },
	{ "cg_drawGun", "cg_drawGun", "1", C.CVAR_ARCHIVE },
	{ "cg_zoomFov", "cg_zoomfov", "22.5", C.CVAR_ARCHIVE },
	{ "cg_fov", "cg_fov", "90", C.CVAR_ARCHIVE },
	{ "cg_viewsize", "cg_viewsize", "100", C.CVAR_ARCHIVE },
	{ "cg_shadows", "cg_shadows", "1", C.CVAR_ARCHIVE },
	{ "cg_gibs", "cg_gibs", "1", C.CVAR_ARCHIVE },
	{ "cg_draw2D", "cg_draw2D", "1", C.CVAR_ARCHIVE },
	{ "cg_drawStatus", "cg_drawStatus", "1", C.CVAR_ARCHIVE },
	{ "cg_drawTimer", "cg_drawTimer", "0", C.CVAR_ARCHIVE },
	{ "cg_drawFPS", "cg_drawFPS", "0", C.CVAR_ARCHIVE },
	{ "cg_drawSnapshot", "cg_drawSnapshot", "0", C.CVAR_ARCHIVE },
	{ "cg_draw3dIcons", "cg_draw3dIcons", "1", C.CVAR_ARCHIVE },
	{ "cg_drawIcons", "cg_drawIcons", "1", C.CVAR_ARCHIVE },
	{ "cg_drawAmmoWarning", "cg_drawAmmoWarning", "1", C.CVAR_ARCHIVE },
	{ "cg_drawAttacker", "cg_drawAttacker", "1", C.CVAR_ARCHIVE },
	{ "cg_drawSpeed", "cg_drawSpeed", "0", C.CVAR_ARCHIVE },
	{ "cg_drawCrosshair", "cg_drawCrosshair", "4", C.CVAR_ARCHIVE },
	{ "cg_drawCrosshairNames", "cg_drawCrosshairNames", "1", C.CVAR_ARCHIVE },
	{ "cg_drawRewards", "cg_drawRewards", "1", C.CVAR_ARCHIVE },
	{ "cg_crosshairSize", "cg_crosshairSize", "24", C.CVAR_ARCHIVE },
	{ "cg_crosshairHealth", "cg_crosshairHealth", "1", C.CVAR_ARCHIVE },
	{ "cg_crosshairX", "cg_crosshairX", "0", C.CVAR_ARCHIVE },
	{ "cg_crosshairY", "cg_crosshairY", "0", C.CVAR_ARCHIVE },
	{ "cg_brassTime", "cg_brassTime", "2500", C.CVAR_ARCHIVE },
	{ "cg_simpleItems", "cg_simpleItems", "0", C.CVAR_ARCHIVE },
	{ "cg_addMarks", "cg_marks", "1", C.CVAR_ARCHIVE },
	{ "cg_lagometer", "cg_lagometer", "1", C.CVAR_ARCHIVE },
	{ "cg_railTrailTime", "cg_railTrailTime", "600", C.CVAR_ARCHIVE },
	{ "cg_gun_x", "cg_gunX", "0", C.CVAR_CHEAT },
	{ "cg_gun_y", "cg_gunY", "0", C.CVAR_CHEAT },
	{ "cg_gun_z", "cg_gunZ", "0", C.CVAR_CHEAT },
	{ "cg_centertime", "cg_centertime", "3", C.CVAR_CHEAT },
	{ "cg_runpitch", "cg_runpitch", "0.002", C.CVAR_ARCHIVE },
	{ "cg_runroll", "cg_runroll", "0.005", C.CVAR_ARCHIVE },
	{ "cg_bobup", "cg_bobup", "0.005", C.CVAR_CHEAT },
	{ "cg_bobpitch", "cg_bobpitch", "0.002", C.CVAR_ARCHIVE },
	{ "cg_bobroll", "cg_bobroll", "0.002", C.CVAR_ARCHIVE },
	{ "cg_swingSpeed", "cg_swingSpeed", "0.3", C.CVAR_CHEAT },
	{ "cg_animSpeed", "cg_animspeed", "1", C.CVAR_CHEAT },
	{ "cg_debugAnim", "cg_debuganim", "0", C.CVAR_CHEAT },
	{ "cg_debugPosition", "cg_debugposition", "0", C.CVAR_CHEAT },
	{ "cg_debugEvents", "cg_debugevents", "0", C.CVAR_CHEAT },
	{ "cg_errorDecay", "cg_errordecay", "100", 0 },
	{ "cg_nopredict", "cg_nopredict", "0", 0 },
	{ "cg_noPlayerAnims", "cg_noplayeranims", "0", C.CVAR_CHEAT },
	{ "cg_showmiss", "cg_showmiss", "0", 0 },
	{ "cg_footsteps", "cg_footsteps", "1", C.CVAR_CHEAT },
	{ "cg_tracerChance", "cg_tracerchance", "0.4", C.CVAR_CHEAT },
	{ "cg_tracerWidth", "cg_tracerwidth", "1", C.CVAR_CHEAT },
	{ "cg_tracerLength", "cg_tracerlength", "100", C.CVAR_CHEAT },
	{ "cg_thirdPersonRange", "cg_thirdPersonRange", "40", C.CVAR_CHEAT },
	{ "cg_thirdPersonAngle", "cg_thirdPersonAngle", "0", C.CVAR_CHEAT },
	{ "cg_thirdPerson", "cg_thirdPerson", "0", 0 },
	{ "cg_teamChatTime", "cg_teamChatTime", "3000", C.CVAR_ARCHIVE },
	{ "cg_teamChatHeight", "cg_teamChatHeight", "0", C.CVAR_ARCHIVE },
	{ "cg_forceModel", "cg_forceModel", "0", C.CVAR_ARCHIVE },
	-- not in OA: draw players who have one as their Roblox avatar (cg_avatars.luau)
	{ "cg_robloxAvatars", "cg_robloxAvatars", "1", C.CVAR_ARCHIVE },
	{ "cg_predictItems", "cg_predictItems", "1", C.CVAR_ARCHIVE },
	{ "cg_deferPlayers", "cg_deferPlayers", "1", C.CVAR_ARCHIVE },
	{ "cg_drawTeamOverlay", "cg_drawTeamOverlay", "0", C.CVAR_ARCHIVE },
	{ "cg_teamOverlayUserinfo", "teamoverlay", "0", bit32.bor(C.CVAR_ROM, C.CVAR_USERINFO) },
	{ "cg_stats", "cg_stats", "0", 0 },
	{ "cg_drawFriend", "cg_drawFriend", "1", C.CVAR_ARCHIVE },
	{ "cg_teamChatsOnly", "cg_teamChatsOnly", "0", C.CVAR_ARCHIVE },
	{ "cg_noVoiceChats", "cg_noVoiceChats", "0", C.CVAR_ARCHIVE },
	{ "cg_noVoiceText", "cg_noVoiceText", "0", C.CVAR_ARCHIVE },
	-- the following variables are created in other parts of the system,
	-- but we also reference them here
	{ "cg_buildScript", "com_buildScript", "0", 0 }, -- force loading of all possible data amd error on failures
	{ "cg_paused", "cl_paused", "0", C.CVAR_ROM },
	{ "cg_blood", "com_blood", "1", C.CVAR_ARCHIVE },
	{ "cg_alwaysWeaponBar", "cg_alwaysWeaponBar", "0", C.CVAR_ARCHIVE }, --Elimination
	{ "cg_hitsound", "cg_hitsound", "0", C.CVAR_ARCHIVE },
	{ "cg_voip_teamonly", "cg_voipTeamOnly", "1", C.CVAR_ARCHIVE },
	{ "cg_voteflags", "cg_voteflags", "*", C.CVAR_ROM },
	{ "cg_cyclegrapple", "cg_cyclegrapple", "1", C.CVAR_ARCHIVE },
	{ "cg_vote_custom_commands", "cg_vote_custom_commands", "", C.CVAR_ROM },
	{ "cg_synchronousClients", "g_synchronousClients", "0", C.CVAR_SYSTEMINFO }, -- communicated by systeminfo

	{ "cg_autovertex", "cg_autovertex", "0", C.CVAR_ARCHIVE },
	{ "cg_enableDust", "g_enableDust", "0", C.CVAR_SERVERINFO },
	{ "cg_enableBreath", "g_enableBreath", "0", C.CVAR_SERVERINFO },
	{ "cg_obeliskRespawnDelay", "g_obeliskRespawnDelay", "10", C.CVAR_SERVERINFO },

	{ "cg_cameraOrbit", "cg_cameraOrbit", "0", C.CVAR_CHEAT },
	{ "cg_cameraOrbitDelay", "cg_cameraOrbitDelay", "50", C.CVAR_ARCHIVE },
	{ "cg_timescaleFadeEnd", "cg_timescaleFadeEnd", "1", 0 },
	{ "cg_timescaleFadeSpeed", "cg_timescaleFadeSpeed", "0", 0 },
	{ "cg_timescale", "timescale", "1", 0 },
	{ "cg_scorePlum", "cg_scorePlums", "1", bit32.bor(C.CVAR_USERINFO, C.CVAR_ARCHIVE) },
	{ "cg_cameraMode", "com_cameraMode", "0", C.CVAR_CHEAT },

	{ "pmove_fixed", "pmove_fixed", "0", C.CVAR_SYSTEMINFO },
	{ "pmove_msec", "pmove_msec", "11", C.CVAR_SYSTEMINFO },
	{ "pmove_float", "pmove_float", "1", C.CVAR_SYSTEMINFO },
	{ "cg_noTaunt", "cg_noTaunt", "0", C.CVAR_ARCHIVE },
	{ "cg_noProjectileTrail", "cg_noProjectileTrail", "0", C.CVAR_ARCHIVE },
	{ "cg_smallFont", "ui_smallFont", "0.25", C.CVAR_ARCHIVE },
	{ "cg_bigFont", "ui_bigFont", "0.4", C.CVAR_ARCHIVE },
	{ "cg_oldRail", "cg_oldRail", "0", C.CVAR_ARCHIVE },
	{ "cg_oldRocket", "cg_oldRocket", "1", C.CVAR_ARCHIVE },
	{ "cg_leiEnhancement", "cg_leiEnhancement", "0", C.CVAR_ARCHIVE },
	{ "cg_leiGoreNoise", "cg_leiGoreNoise", "0", C.CVAR_ARCHIVE },
	{ "cg_leiBrassNoise", "cg_leiBrassNoise", "0", C.CVAR_ARCHIVE },
	{ "cg_leiSuperGoreyAwesome", "cg_leiSuperGoreyAwesome", "0", C.CVAR_ARCHIVE },
	{ "cg_oldPlasma", "cg_oldPlasma", "1", C.CVAR_ARCHIVE },
	--unlagged - client options
	{ "cg_delag", "cg_delag", "1", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_USERINFO) },
	{ "cg_cmdTimeNudge", "cg_cmdTimeNudge", "0", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_USERINFO) },
	-- this will be automagically copied from the server
	{ "sv_fps", "sv_fps", "20", C.CVAR_SYSTEMINFO },
	{ "cg_projectileNudge", "cg_projectileNudge", "0", C.CVAR_ARCHIVE },
	{ "cg_optimizePrediction", "cg_optimizePrediction", "1", C.CVAR_ARCHIVE },
	{ "cl_timeNudge", "cl_timeNudge", "0", C.CVAR_ARCHIVE },
	--unlagged - client options
	{ "cg_trueLightning", "cg_trueLightning", "0.0", C.CVAR_ARCHIVE },
	{ "cg_music", "cg_music", "", C.CVAR_ARCHIVE },

	{ "cg_fragmsgsize", "cg_fragmsgsize", "1.0", C.CVAR_ARCHIVE },
	{ "cg_crosshairPulse", "cg_crosshairPulse", "1", C.CVAR_ARCHIVE },

	{ "cg_differentCrosshairs", "cg_differentCrosshairs", "0", C.CVAR_ARCHIVE },
}

for n = 1, 13 do
	table.insert(cvarDefs, { "cg_ch" .. n, "cg_ch" .. n, "1", C.CVAR_ARCHIVE })
	table.insert(cvarDefs, { "cg_ch" .. n .. "size", "cg_ch" .. n .. "size", "24", C.CVAR_ARCHIVE })
end

local tail = {
	{ "cg_crosshairColorRed", "cg_crosshairColorRed", "1.0", C.CVAR_ARCHIVE },
	{ "cg_crosshairColorGreen", "cg_crosshairColorGreen", "1.0", C.CVAR_ARCHIVE },
	{ "cg_crosshairColorBlue", "cg_crosshairColorBlue", "1.0", C.CVAR_ARCHIVE },

	{ "cg_weaponBarStyle", "cg_weaponBarStyle", "0", C.CVAR_ARCHIVE },
	{ "cg_weaponOrder", "cg_weaponOrder", "/1/2/4/3/6/7/8/9/5/", C.CVAR_ARCHIVE },
	{ "cg_chatBeep", "cg_chatBeep", "1", C.CVAR_ARCHIVE },
	{ "cg_teamChatBeep", "cg_teamChatBeep", "1", C.CVAR_ARCHIVE },
}
for _, def in tail do
	table.insert(cvarDefs, def)
end

-- 0-based, entries { vmCvar, cvarName, defaultString, cvarFlags }
local cvarTable = {}
local cvarTableSize = #cvarDefs
for i = 0, cvarTableSize - 1 do
	local def = cvarDefs[i + 1]
	if G[def[1]] == nil then
		G[def[1]] = T.vmCvar_t()
	end
	cvarTable[i] = {
		vmCvar = G[def[1]],
		cvarName = def[2],
		defaultString = def[3],
		cvarFlags = def[4],
	}
end
G.cvarTable = cvarTable
G.cvarTableSize = cvarTableSize

--[[
=================
CG_RegisterCvars
=================
]]
function G.CG_RegisterCvars()
	for i = 0, cvarTableSize - 1 do
		local cv = cvarTable[i]
		trap.Cvar_Register(cv.vmCvar, cv.cvarName, cv.defaultString, cv.cvarFlags)
	end

	-- see if we are also running the server on this machine
	local var = trap.Cvar_VariableStringBuffer("sv_running")
	G.cgs.localServer = Q.int(tonumber(var) or 0)

	G.forceModelModificationCount = G.cg_forceModel.modificationCount

	local userArchive = bit32.bor(C.CVAR_USERINFO, C.CVAR_ARCHIVE)
	trap.Cvar_Register(nil, "model", C.DEFAULT_MODEL, userArchive)
	trap.Cvar_Register(nil, "headmodel", C.DEFAULT_MODEL, userArchive)
	trap.Cvar_Register(nil, "team_model", C.DEFAULT_TEAM_MODEL, userArchive)
	trap.Cvar_Register(nil, "team_headmodel", C.DEFAULT_TEAM_HEAD, userArchive)
end

--[[
===================
CG_ForceModelChange
===================
]]
function G.CG_ForceModelChange()
	for i = 0, C.MAX_CLIENTS - 1 do
		local clientInfo = G.CG_ConfigString(C.CS_PLAYERS + i)
		if clientInfo ~= "" then
			G.CG_NewClientInfo(i)
		end
	end
end

--[[
=================
CG_UpdateCvars
=================
]]
function G.CG_UpdateCvars()
	for i = 0, cvarTableSize - 1 do
		local cv = cvarTable[i]
		--unlagged - client options
		-- clamp the value between 0 and 999
		-- negative values would suck - people could conceivably shoot other
		-- players *long* after they had left the area, on purpose
		if cv.vmCvar == G.cg_cmdTimeNudge then
			G.CG_Cvar_ClampInt(cv.cvarName, cv.vmCvar, 0, 999)
		-- cl_timenudge less than -50 or greater than 50 doesn't actually
		-- do anything more than -50 or 50
		elseif cv.vmCvar == G.cl_timeNudge then
			G.CG_Cvar_ClampInt(cv.cvarName, cv.vmCvar, -50, 50)
		elseif cv.vmCvar == G.cg_errorDecay then
			G.CG_Cvar_ClampInt(cv.cvarName, cv.vmCvar, 0, 250)
		end
		trap.Cvar_Update(cv.vmCvar)
	end

	-- check for modications here

	-- If team overlay is on, ask for updates from the server.  If its off,
	-- let the server know so we don't receive it
	if G.drawTeamOverlayModificationCount ~= G.cg_drawTeamOverlay.modificationCount then
		G.drawTeamOverlayModificationCount = G.cg_drawTeamOverlay.modificationCount

		if G.cg_drawTeamOverlay.integer > 0 then
			trap.Cvar_Set("teamoverlay", "1")
		else
			trap.Cvar_Set("teamoverlay", "0")
		end
	end

	-- if force model changed
	if G.forceModelModificationCount ~= G.cg_forceModel.modificationCount then
		G.forceModelModificationCount = G.cg_forceModel.modificationCount
		G.CG_ForceModelChange()
	end
end

function G.CG_CrosshairPlayer()
	if G.cg.time > (G.cg.crosshairClientTime + 1000) then
		return -1
	end
	return G.cg.crosshairClientNum
end

function G.CG_LastAttacker()
	if G.cg.attackerTime == 0 then
		return -1
	end
	return G.cg.snap.ps.persistant[C.PERS_ATTACKER]
end

function G.CG_Printf(msg, ...)
	trap.Print(Q.va(msg, ...))
end

function G.CG_Error(msg, ...)
	trap.Error(Q.va(msg, ...))
end

function G.Com_Error(level, err, ...)
	G.CG_Error("%s", Q.va(err, ...))
end

function G.Com_Printf(msg, ...)
	G.CG_Printf("%s", Q.va(msg, ...))
end

--[[
================
CG_Argv
================
]]
function G.CG_Argv(arg)
	return trap.Argv(arg)
end

--========================================================================

--[[
=================
CG_RegisterItemSounds

The server says this item is used on this level
=================
]]
function G.CG_RegisterItemSounds(itemNum)
	local item = BG.bg_itemlist[itemNum]

	if item.pickup_sound ~= nil and item.pickup_sound ~= "" then
		trap.S_RegisterSound(item.pickup_sound, false)
	end

	-- parse the space seperated precache string for other media
	local s = item.sounds
	if s == nil or s == "" then
		return
	end

	local pos = 1
	local total = #s
	while pos <= total do
		local start = pos
		while pos <= total and string.byte(s, pos) ~= 32 do
			pos += 1
		end

		local len = pos - start
		if len >= C.MAX_QPATH or len < 5 then
			G.CG_Error("PrecacheItem: %s has bad precache string", item.classname)
			return
		end
		local data = string.sub(s, start, start + len - 1)
		if pos <= total then
			pos += 1
		end

		if string.sub(data, len - 2) == "wav" then
			trap.S_RegisterSound(data, false)
		end
	end
end

--[[
=================
CG_RegisterSounds

called during a precache command
=================
]]
function G.CG_RegisterSounds()
	local cgs = G.cgs
	local m = cgs.media
	local reg = trap.S_RegisterSound
	local buildScript = G.cg_buildScript.integer ~= 0

	m.oneMinuteSound = reg("sound/feedback/1_minute.wav", true)
	m.fiveMinuteSound = reg("sound/feedback/5_minute.wav", true)
	m.suddenDeathSound = reg("sound/feedback/sudden_death.wav", true)
	m.oneFragSound = reg("sound/feedback/1_frag.wav", true)
	m.twoFragSound = reg("sound/feedback/2_frags.wav", true)
	m.threeFragSound = reg("sound/feedback/3_frags.wav", true)
	m.count3Sound = reg("sound/feedback/three.wav", true)
	m.count2Sound = reg("sound/feedback/two.wav", true)
	m.count1Sound = reg("sound/feedback/one.wav", true)
	m.countFightSound = reg("sound/feedback/fight.wav", true)
	m.countPrepareSound = reg("sound/feedback/prepare.wav", true)

	-- Load team game stuff if the gametype is a teamgame and not an exception (like GT_LMS)
	if (cgs.gametype >= C.GT_TEAM and cgs.ffa_gt ~= 1) or buildScript then
		m.captureAwardSound = reg("sound/teamplay/flagcapture_yourteam.wav", true)
		m.redLeadsSound = reg("sound/feedback/redleads.wav", true)
		m.blueLeadsSound = reg("sound/feedback/blueleads.wav", true)
		m.teamsTiedSound = reg("sound/feedback/teamstied.wav", true)
		m.hitTeamSound = reg("sound/feedback/hit_teammate.wav", true)

		m.redScoredSound = reg("sound/teamplay/voc_red_scores.wav", true)
		m.blueScoredSound = reg("sound/teamplay/voc_blue_scores.wav", true)

		m.captureYourTeamSound = reg("sound/teamplay/flagcapture_yourteam.wav", true)
		m.captureOpponentSound = reg("sound/teamplay/flagcapture_opponent.wav", true)

		m.returnYourTeamSound = reg("sound/teamplay/flagreturn_yourteam.wav", true)
		m.returnOpponentSound = reg("sound/teamplay/flagreturn_opponent.wav", true)

		m.takenYourTeamSound = reg("sound/teamplay/flagtaken_yourteam.wav", true)
		m.takenOpponentSound = reg("sound/teamplay/flagtaken_opponent.wav", true)

		if cgs.gametype == C.GT_CTF or cgs.gametype == C.GT_CTF_ELIMINATION or buildScript then
			m.redFlagReturnedSound = reg("sound/teamplay/voc_red_returned.wav", true)
			m.blueFlagReturnedSound = reg("sound/teamplay/voc_blue_returned.wav", true)
			m.enemyTookYourFlagSound = reg("sound/teamplay/voc_enemy_flag.wav", true)
			m.yourTeamTookEnemyFlagSound = reg("sound/teamplay/voc_team_flag.wav", true)
		end

		if cgs.gametype == C.GT_1FCTF or buildScript then
			-- FIXME: get a replacement for this sound ?
			m.neutralFlagReturnedSound = reg("sound/teamplay/flagreturn_opponent.wav", true)
			m.yourTeamTookTheFlagSound = reg("sound/teamplay/voc_team_1flag.wav", true)
			m.enemyTookTheFlagSound = reg("sound/teamplay/voc_enemy_1flag.wav", true)
		end

		if cgs.gametype == C.GT_1FCTF or cgs.gametype == C.GT_CTF or cgs.gametype == C.GT_CTF_ELIMINATION or buildScript then
			m.youHaveFlagSound = reg("sound/teamplay/voc_you_flag.wav", true)
			m.holyShitSound = reg("sound/feedback/voc_holyshit.wav", true)
		end

		if cgs.gametype == C.GT_OBELISK or buildScript then
			m.yourBaseIsUnderAttackSound = reg("sound/teamplay/voc_base_attack.wav", true)
		end
	end

	m.tracerSound = reg("sound/weapons/machinegun/buletby1.wav", false)
	m.selectSound = reg("sound/weapons/change.wav", false)
	m.wearOffSound = reg("sound/items/wearoff.wav", false)
	m.useNothingSound = reg("sound/items/use_nothing.wav", false)
	m.gibSound = reg("sound/player/gibsplt1.wav", false)
	m.gibBounce1Sound = reg("sound/player/gibimp1.wav", false)
	m.gibBounce2Sound = reg("sound/player/gibimp2.wav", false)
	m.gibBounce3Sound = reg("sound/player/gibimp3.wav", false)

	-- LEILEI
	m.lspl1Sound = reg("sound/le/splat1.wav", false)
	m.lspl2Sound = reg("sound/le/splat2.wav", false)
	m.lspl3Sound = reg("sound/le/splat3.wav", false)

	m.lbul1Sound = reg("sound/le/bullet1.wav", false)
	m.lbul2Sound = reg("sound/le/bullet2.wav", false)
	m.lbul3Sound = reg("sound/le/bullet3.wav", false)

	m.lshl1Sound = reg("sound/le/shell1.wav", false)
	m.lshl2Sound = reg("sound/le/shell2.wav", false)
	m.lshl3Sound = reg("sound/le/shell3.wav", false)

	m.useInvulnerabilitySound = reg("sound/items/invul_activate.wav", false)
	m.invulnerabilityImpactSound1 = reg("sound/items/invul_impact_01.wav", false)
	m.invulnerabilityImpactSound2 = reg("sound/items/invul_impact_02.wav", false)
	m.invulnerabilityImpactSound3 = reg("sound/items/invul_impact_03.wav", false)
	m.invulnerabilityJuicedSound = reg("sound/items/invul_juiced.wav", false)

	m.ammoregenSound = reg("sound/items/cl_ammoregen.wav", false)
	m.doublerSound = reg("sound/items/cl_doubler.wav", false)
	m.guardSound = reg("sound/items/cl_guard.wav", false)
	m.scoutSound = reg("sound/items/cl_scout.wav", false)
	m.obeliskHitSound1 = reg("sound/items/obelisk_hit_01.wav", false)
	m.obeliskHitSound2 = reg("sound/items/obelisk_hit_02.wav", false)
	m.obeliskHitSound3 = reg("sound/items/obelisk_hit_03.wav", false)
	m.obeliskRespawnSound = reg("sound/items/obelisk_respawn.wav", false)

	m.teleInSound = reg("sound/world/telein.wav", false)
	m.teleOutSound = reg("sound/world/teleout.wav", false)
	m.respawnSound = reg("sound/items/respawn1.wav", false)

	m.noAmmoSound = reg("sound/weapons/noammo.wav", false)

	m.talkSound = reg("sound/player/talk.wav", false)
	m.landSound = reg("sound/player/land1.wav", false)

	m.hitSound = reg("sound/feedback/hit.wav", false) -- cg_hitsound: every value uses hit.wav

	m.impressiveSound = reg("sound/feedback/impressive.wav", true)
	m.excellentSound = reg("sound/feedback/excellent.wav", true)
	m.deniedSound = reg("sound/feedback/denied.wav", true)
	m.humiliationSound = reg("sound/feedback/humiliation.wav", true)
	m.assistSound = reg("sound/feedback/assist.wav", true)
	m.defendSound = reg("sound/feedback/defense.wav", true)

	m.takenLeadSound = reg("sound/feedback/takenlead.wav", true)
	m.tiedLeadSound = reg("sound/feedback/tiedlead.wav", true)
	m.lostLeadSound = reg("sound/feedback/lostlead.wav", true)

	m.watrInSound = reg("sound/player/watr_in.wav", false)
	m.watrOutSound = reg("sound/player/watr_out.wav", false)
	m.watrUnSound = reg("sound/player/watr_un.wav", false)

	m.jumpPadSound = reg("sound/world/jumppad.wav", false)

	local steps = {
		{ C.FOOTSTEP_NORMAL, "step" },
		{ C.FOOTSTEP_BOOT, "boot" },
		{ C.FOOTSTEP_FLESH, "flesh" },
		{ C.FOOTSTEP_MECH, "mech" },
		{ C.FOOTSTEP_ENERGY, "energy" },
		{ C.FOOTSTEP_SPLASH, "splash" },
		{ C.FOOTSTEP_METAL, "clank" },
	}
	for i = 0, 3 do
		for _, st in steps do
			local name = Q.va("sound/player/footsteps/%s%i.wav", st[2], i + 1)
			m.footsteps[st[1]][i] = reg(name, false)
		end
	end

	-- only register the items that the server says we need
	for i = 1, BG.bg_numItems - 1 do
		G.CG_RegisterItemSounds(i)
	end

	for i = 1, C.MAX_SOUNDS - 1 do
		local soundName = G.CG_ConfigString(C.CS_SOUNDS + i)
		if soundName == "" then
			break
		end
		if string.byte(soundName, 1) ~= 42 then -- '*' is a custom sound
			cgs.gameSounds[i] = reg(soundName, false)
		end
	end

	-- FIXME: only needed with item
	m.flightSound = reg("sound/items/flight.wav", false)
	m.medkitSound = reg("sound/items/use_medkit.wav", false)
	m.quadSound = reg("sound/items/damage3.wav", false)
	m.sfx_ric1 = reg("sound/weapons/machinegun/ric1.wav", false)
	m.sfx_ric2 = reg("sound/weapons/machinegun/ric2.wav", false)
	m.sfx_ric3 = reg("sound/weapons/machinegun/ric3.wav", false)
	m.sfx_railg = reg("sound/weapons/railgun/railgf1a.wav", false)
	m.sfx_rockexp = reg("sound/weapons/rocket/rocklx1a.wav", false)
	m.sfx_plasmaexp = reg("sound/weapons/plasma/plasmx1a.wav", false)
	m.sfx_proxexp = reg("sound/weapons/proxmine/wstbexpl.wav", false)
	m.sfx_nghit = reg("sound/weapons/nailgun/wnalimpd.wav", false)
	m.sfx_nghitflesh = reg("sound/weapons/nailgun/wnalimpl.wav", false)
	m.sfx_nghitmetal = reg("sound/weapons/nailgun/wnalimpm.wav", false)
	m.sfx_chghit = reg("sound/weapons/vulcan/wvulimpd.wav", false)
	m.sfx_chghitflesh = reg("sound/weapons/vulcan/wvulimpl.wav", false)
	m.sfx_chghitmetal = reg("sound/weapons/vulcan/wvulimpm.wav", false)
	m.weaponHoverSound = reg("sound/weapons/weapon_hover.wav", false)
	m.kamikazeExplodeSound = reg("sound/items/kam_explode.wav", false)
	m.kamikazeImplodeSound = reg("sound/items/kam_implode.wav", false)
	m.kamikazeFarSound = reg("sound/items/kam_explode_far.wav", false)
	m.winnerSound = reg("sound/feedback/voc_youwin.wav", false)
	m.loserSound = reg("sound/feedback/voc_youlose.wav", false)
	m.youSuckSound = reg("sound/misc/yousuck.wav", false)

	m.wstbimplSound = reg("sound/weapons/proxmine/wstbimpl.wav", false)
	m.wstbimpmSound = reg("sound/weapons/proxmine/wstbimpm.wav", false)
	m.wstbimpdSound = reg("sound/weapons/proxmine/wstbimpd.wav", false)
	m.wstbactvSound = reg("sound/weapons/proxmine/wstbactv.wav", false)

	m.regenSound = reg("sound/items/regen.wav", false)
	m.protectSound = reg("sound/items/protect3.wav", false)
	m.n_healthSound = reg("sound/items/n_health.wav", false)
	m.hgrenb1aSound = reg("sound/weapons/grenade/hgrenb1a.wav", false)
	m.hgrenb2aSound = reg("sound/weapons/grenade/hgrenb2a.wav", false)
end

return G
