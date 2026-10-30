--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_main.c, part 1 of 3).

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
-- Luau port of OpenArena 0.8.8's g_main.c (gamecode 9e0f0c0), part 1 of 3. Cvar table, vmMain, game init, cvar registration/update.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SF = G.FileStatics("g_main")

local GAMEVERSION = "baseoa"
local PRODUCT_DATE = "Jan 28 2012" -- __DATE__ of the 0.8.8 QVM build
local MAX_VOTE_COUNT = "3"
local SP_PODIUM_MODEL = "models/mapobjects/podium/podium4.md3"

local vmCvarNames = {
	"g_gametype", "g_dmflags", "g_videoflags", "g_elimflags", "g_voteflags", "g_fraglimit",
	"g_timelimit", "g_capturelimit", "g_friendlyFire", "g_password", "g_needpass", "g_maxclients",
	"g_maxGameClients", "g_dedicated", "g_speed", "g_gravity", "g_gravityModifier", "g_damageModifier",
	"g_cheats", "g_knockback", "g_quadfactor", "g_forcerespawn", "g_respawntime", "g_inactivity",
	"g_debugMove", "g_debugDamage", "g_debugAlloc", "g_weaponRespawn", "g_weaponTeamRespawn",
	"g_motd", "g_motdfile", "g_votemaps", "g_votecustom", "g_synchronousClients", "g_warmup",
	"g_doWarmup", "g_restarted", "g_logfile", "g_logfileSync", "g_blood", "g_podiumDist",
	"g_podiumDrop", "g_friendBots", "g_allowVote", "g_teamAutoJoin", "g_teamForceBalance", "g_banIPs", "g_filterBan",
	"g_smoothClients", "pmove_fixed", "pmove_msec", "pmove_float", "g_rankings", "g_listEntity",
	"g_obeliskHealth", "g_obeliskRegenPeriod", "g_obeliskRegenAmount",
	"g_obeliskRespawnDelay", "g_cubeTimeout", "g_enableDust",
	"g_enableBreath", "g_proxMineTimeout", "g_music", "g_spawnprotect",
	"g_elimination_selfdamage", "g_elimination_startHealth", "g_elimination_startArmor",
	"g_elimination_bfg", "g_elimination_grapple", "g_elimination_roundtime", "g_elimination_warmup",
	"g_elimination_activewarmup", "g_elimination_allgametypes", "g_elimination_machinegun",
	"g_elimination_shotgun", "g_elimination_grenade", "g_elimination_rocket",
	"g_elimination_railgun", "g_elimination_lightning", "g_elimination_plasmagun",
	"g_elimination_chain", "g_elimination_mine", "g_elimination_nail",
	"g_elimination_lockspectator", "g_rockets", "g_instantgib", "g_vampire", "g_vampireMaxHealth",
	"g_regen", "g_lms_lives", "g_lms_mode", "g_elimination_ctf_oneway", "g_awardpushing", "g_persistantpowerups",
	"g_catchup", "g_autonextmap", "g_mappools", "g_voteNames", "g_voteBan", "g_voteGametypes",
	"g_voteMinTimelimit", "g_voteMaxTimelimit", "g_voteMinFraglimit", "g_voteMaxFraglimit",
	"g_maxvotes", "g_humanplayers", "g_redTeamClientNumbers", "g_blueTeamClientNumbers",
	"g_delagHitscan", "g_truePing", "sv_fps", "g_lagLightning", "g_sprees", "g_altExcellent",
	"g_spreeDiv", "g_floodMaxDemerits", "g_floodMinTime", "g_admin", "g_adminLog", "g_adminParseSay",
	"g_adminNameProtect", "g_adminTempBan", "g_adminMaxBan", "g_specChat", "g_publicAdminMessages",
	"g_maxWarnings", "g_warningExpire", "g_minNameChangePeriod", "g_maxNameChanges",
	"g_timestamp_startgame", "g_execute_gametype_script",
}
for _, name in vmCvarNames do
	G[name] = S.vmCvar_t()
end

G.g_ffa_gt = 0 -- Are this a FFA gametype even if gametype is high?

local function E(vmCvar, cvarName, defaultString, cvarFlags, modificationCount, trackChange, teamShader)
	return {
		vmCvar = vmCvar,
		cvarName = cvarName,
		defaultString = defaultString,
		cvarFlags = cvarFlags or 0,
		modificationCount = modificationCount or 0,
		trackChange = trackChange or false,
		teamShader = teamShader or false,
	}
end

local gameCvarTableList = {
	-- don't override the cheat state set by the system
	E(G.g_cheats, "sv_cheats", "", 0, 0, false),

	-- noset vars
	E(nil, "gamename", GAMEVERSION, bit32.bor(C.CVAR_SERVERINFO, C.CVAR_ROM), 0, false),
	E(nil, "gamedate", PRODUCT_DATE, C.CVAR_ROM, 0, false),
	E(G.g_restarted, "g_restarted", "0", C.CVAR_ROM, 0, false),
	E(nil, "sv_mapname", "", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_ROM), 0, false),

	-- latched vars
	E(G.g_gametype, "g_gametype", "0", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_USERINFO, C.CVAR_LATCH), 0, false),

	E(G.g_maxclients, "sv_maxclients", "8", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_LATCH, C.CVAR_ARCHIVE), 0, false),
	E(G.g_maxGameClients, "g_maxGameClients", "0", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_LATCH, C.CVAR_ARCHIVE), 0, false),

	-- change anytime vars
	E(G.g_dmflags, "dmflags", "0", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_ARCHIVE), 0, true),
	E(G.g_videoflags, "videoflags", "7", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_ARCHIVE), 0, true),
	E(G.g_elimflags, "elimflags", "0", C.CVAR_SERVERINFO, 0, false),
	E(G.g_voteflags, "voteflags", "0", C.CVAR_SERVERINFO, 0, false),
	E(G.g_fraglimit, "fraglimit", "20", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),
	E(G.g_timelimit, "timelimit", "0", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),
	E(G.g_capturelimit, "capturelimit", "8", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),

	E(G.g_synchronousClients, "g_synchronousClients", "0", C.CVAR_SYSTEMINFO, 0, false),

	E(G.g_friendlyFire, "g_friendlyFire", "0", C.CVAR_ARCHIVE, 0, true),

	E(G.g_teamAutoJoin, "g_teamAutoJoin", "0", C.CVAR_ARCHIVE),
	E(G.g_teamForceBalance, "g_teamForceBalance", "0", C.CVAR_ARCHIVE),

	E(G.g_warmup, "g_warmup", "20", C.CVAR_ARCHIVE, 0, true),
	E(G.g_doWarmup, "g_doWarmup", "0", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_ARCHIVE), 0, true),
	E(G.g_logfile, "g_log", "games.log", C.CVAR_ARCHIVE, 0, false),
	E(G.g_logfileSync, "g_logsync", "0", C.CVAR_ARCHIVE, 0, false),

	E(G.g_password, "g_password", "", C.CVAR_USERINFO, 0, false),

	E(G.g_banIPs, "g_banIPs", "", C.CVAR_ARCHIVE, 0, false),
	E(G.g_filterBan, "g_filterBan", "1", C.CVAR_ARCHIVE, 0, false),

	E(G.g_needpass, "g_needpass", "0", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_ROM), 0, false),

	E(G.g_dedicated, "dedicated", "0", 0, 0, false),

	E(G.g_speed, "g_speed", "320", 0, 0, true),
	E(G.g_gravity, "g_gravity", "800", 0, 0, true),
	E(G.g_gravityModifier, "g_gravityModifier", "1", 0, 0, true),
	E(G.g_damageModifier, "g_damageModifier", "0", 0, 0, true),
	E(G.g_knockback, "g_knockback", "1000", 0, 0, true),
	E(G.g_quadfactor, "g_quadfactor", "3", 0, 0, true),
	E(G.g_weaponRespawn, "g_weaponrespawn", "5", 0, 0, true),
	E(G.g_weaponTeamRespawn, "g_weaponTeamRespawn", "30", 0, 0, true),
	E(G.g_forcerespawn, "g_forcerespawn", "20", 0, 0, true),
	E(G.g_respawntime, "g_respawntime", "0", C.CVAR_ARCHIVE, 0, true),
	E(G.g_inactivity, "g_inactivity", "0", 0, 0, true),
	E(G.g_debugMove, "g_debugMove", "0", 0, 0, false),
	E(G.g_debugDamage, "g_debugDamage", "0", 0, 0, false),
	E(G.g_debugAlloc, "g_debugAlloc", "0", 0, 0, false),
	E(G.g_motd, "g_motd", "", 0, 0, false),
	E(G.g_motdfile, "g_motdfile", "motd.cfg", 0, 0, false),
	E(G.g_blood, "com_blood", "1", 0, 0, false),

	E(G.g_podiumDist, "g_podiumDist", "80", 0, 0, false),
	E(G.g_podiumDrop, "g_podiumDrop", "70", 0, 0, false),
	-- not in OA: bots wear human players' Roblox friends (g_bot.luau)
	E(G.g_friendBots, "g_friendBots", "1", C.CVAR_ARCHIVE, 0, false),

	--Votes start:
	E(G.g_allowVote, "g_allowVote", "1", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_ARCHIVE), 0, false),
	E(G.g_maxvotes, "g_maxVotes", MAX_VOTE_COUNT, C.CVAR_ARCHIVE, 0, false),
	E(G.g_voteNames, "g_voteNames", "/map_restart/nextmap/map/g_gametype/kick/clientkick/g_doWarmup/timelimit/fraglimit/shuffle/", C.CVAR_ARCHIVE, 0, false),
	E(G.g_voteBan, "g_voteBan", "0", C.CVAR_ARCHIVE, 0, false),
	E(G.g_voteGametypes, "g_voteGametypes", "/0/1/3/4/5/6/7/8/9/10/11/12/", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_ARCHIVE), 0, false),
	E(G.g_voteMaxTimelimit, "g_voteMaxTimelimit", "1000", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_ARCHIVE), 0, false),
	E(G.g_voteMinTimelimit, "g_voteMinTimelimit", "0", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_ARCHIVE), 0, false),
	E(G.g_voteMaxFraglimit, "g_voteMaxFraglimit", "0", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_ARCHIVE), 0, false),
	E(G.g_voteMinFraglimit, "g_voteMinFraglimit", "0", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_ARCHIVE), 0, false),
	E(G.g_votemaps, "g_votemapsfile", "votemaps.cfg", 0, 0, false),
	E(G.g_votecustom, "g_votecustomfile", "votecustom.cfg", 0, 0, false),

	E(G.g_listEntity, "g_listEntity", "0", 0, 0, false),

	E(G.g_obeliskHealth, "g_obeliskHealth", "2500", 0, 0, false),
	E(G.g_obeliskRegenPeriod, "g_obeliskRegenPeriod", "1", 0, 0, false),
	E(G.g_obeliskRegenAmount, "g_obeliskRegenAmount", "15", 0, 0, false),
	E(G.g_obeliskRespawnDelay, "g_obeliskRespawnDelay", "10", C.CVAR_SERVERINFO, 0, false),

	E(G.g_cubeTimeout, "g_cubeTimeout", "30", 0, 0, false),

	E(G.g_enableDust, "g_enableDust", "0", C.CVAR_SERVERINFO, 0, true, false),
	E(G.g_enableBreath, "g_enableBreath", "0", C.CVAR_SERVERINFO, 0, true, false),
	E(G.g_proxMineTimeout, "g_proxMineTimeout", "20000", 0, 0, false),

	E(G.g_smoothClients, "g_smoothClients", "1", 0, 0, false),
	E(G.pmove_fixed, "pmove_fixed", "0", bit32.bor(C.CVAR_SYSTEMINFO, C.CVAR_ARCHIVE), 0, false),
	E(G.pmove_msec, "pmove_msec", "11", bit32.bor(C.CVAR_SYSTEMINFO, C.CVAR_ARCHIVE), 0, false),
	E(G.pmove_float, "pmove_float", "1", bit32.bor(C.CVAR_SYSTEMINFO, C.CVAR_ARCHIVE), 0, true),

	--unlagged - server options
	E(G.g_delagHitscan, "g_delagHitscan", "0", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_SERVERINFO), 0, true),
	E(G.g_truePing, "g_truePing", "0", C.CVAR_ARCHIVE, 0, true),
	-- it's CVAR_SYSTEMINFO so the client's sv_fps will be automagically set to its value
	E(G.sv_fps, "sv_fps", "20", bit32.bor(C.CVAR_SYSTEMINFO, C.CVAR_ARCHIVE), 0, false),
	E(G.g_lagLightning, "g_lagLightning", "1", C.CVAR_ARCHIVE, 0, true),
	--unlagged - server options

	E(G.g_rankings, "g_rankings", "0", 0, 0, false),
	E(G.g_music, "g_music", "", 0, 0, false),
	E(G.g_spawnprotect, "g_spawnprotect", "500", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),
	--Now for elimination stuff:
	E(G.g_elimination_selfdamage, "elimination_selfdamage", "0", 0, 0, true),
	E(G.g_elimination_startHealth, "elimination_startHealth", "200", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),
	E(G.g_elimination_startArmor, "elimination_startArmor", "150", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),
	E(G.g_elimination_bfg, "elimination_bfg", "0", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),
	E(G.g_elimination_grapple, "elimination_grapple", "0", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),
	E(G.g_elimination_roundtime, "elimination_roundtime", "120", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),
	E(G.g_elimination_warmup, "elimination_warmup", "7", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),
	E(G.g_elimination_activewarmup, "elimination_activewarmup", "5", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),
	E(G.g_elimination_allgametypes, "g_elimination", "0", bit32.bor(C.CVAR_LATCH, C.CVAR_NORESTART), 0, false),

	E(G.g_elimination_machinegun, "elimination_machinegun", "500", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),
	E(G.g_elimination_shotgun, "elimination_shotgun", "500", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),
	E(G.g_elimination_grenade, "elimination_grenade", "100", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),
	E(G.g_elimination_rocket, "elimination_rocket", "50", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),
	E(G.g_elimination_railgun, "elimination_railgun", "20", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),
	E(G.g_elimination_lightning, "elimination_lightning", "300", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),
	E(G.g_elimination_plasmagun, "elimination_plasmagun", "200", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),
	E(G.g_elimination_chain, "elimination_chain", "0", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),
	E(G.g_elimination_mine, "elimination_mine", "0", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),
	E(G.g_elimination_nail, "elimination_nail", "0", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),

	E(G.g_elimination_ctf_oneway, "elimination_ctf_oneway", "0", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),

	E(G.g_elimination_lockspectator, "elimination_lockspectator", "0", C.CVAR_NORESTART, 0, true),

	E(G.g_awardpushing, "g_awardpushing", "1", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),

	--g_persistantpowerups
	E(G.g_persistantpowerups, "g_runes", "0", bit32.bor(C.CVAR_LATCH, C.CVAR_ARCHIVE), 0, false),

	--nexuiz style rocket arena
	E(G.g_rockets, "g_rockets", "0", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_LATCH, C.CVAR_NORESTART), 0, false),

	--Instantgib and Vampire thingies
	E(G.g_instantgib, "g_instantgib", "0", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_LATCH), 0, false),
	E(G.g_vampire, "g_vampire", "0.0", C.CVAR_NORESTART, 0, true),
	E(G.g_regen, "g_regen", "0", C.CVAR_NORESTART, 0, true),
	E(G.g_vampireMaxHealth, "g_vampire_max_health", "500", C.CVAR_NORESTART, 0, true),
	E(G.g_lms_lives, "g_lms_lives", "1", C.CVAR_NORESTART, 0, true),
	E(G.g_lms_mode, "g_lms_mode", "0", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),

	E(G.g_catchup, "g_catchup", "0", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, true),

	E(G.g_autonextmap, "g_autonextmap", "0", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, false),
	E(G.g_mappools, "g_mappools", "0\\maps_dm.cfg\\1\\maps_tourney.cfg\\3\\maps_tdm.cfg\\4\\maps_ctf.cfg\\5\\maps_oneflag.cfg\\6\\maps_obelisk.cfg\\7\\maps_harvester.cfg\\8\\maps_elimination.cfg\\9\\maps_ctf.cfg\\10\\maps_lms.cfg\\11\\maps_dd.cfg\\12\\maps_dom.cfg\\", bit32.bor(C.CVAR_ARCHIVE, C.CVAR_NORESTART), 0, false),
	E(G.g_humanplayers, "g_humanplayers", "0", bit32.bor(C.CVAR_ROM, C.CVAR_NORESTART), 0, false),
	--used for voIP
	E(G.g_redTeamClientNumbers, "g_redTeamClientNumbers", "0", C.CVAR_ROM, 0, false),
	E(G.g_blueTeamClientNumbers, "g_blueTeamClientNumbers", "0", C.CVAR_ROM, 0, false),

	--KK-OAX
	E(G.g_sprees, "g_sprees", "sprees.dat", 0, 0, false),
	E(G.g_altExcellent, "g_altExcellent", "0", C.CVAR_SERVERINFO, 0, true),
	E(G.g_spreeDiv, "g_spreeDiv", "5", 0, 0, false),

	--Used for command/chat flooding
	E(G.g_floodMaxDemerits, "g_floodMaxDemerits", "5000", C.CVAR_ARCHIVE, 0, false),
	E(G.g_floodMinTime, "g_floodMinTime", "2000", C.CVAR_ARCHIVE, 0, false),

	--Admin
	E(G.g_admin, "g_admin", "admin.dat", C.CVAR_ARCHIVE, 0, false),
	E(G.g_adminLog, "g_adminLog", "admin.log", C.CVAR_ARCHIVE, 0, false),
	E(G.g_adminParseSay, "g_adminParseSay", "1", C.CVAR_ARCHIVE, 0, false),
	E(G.g_adminNameProtect, "g_adminNameProtect", "1", C.CVAR_ARCHIVE, 0, false),
	E(G.g_adminTempBan, "g_adminTempBan", "2m", C.CVAR_ARCHIVE, 0, false),
	E(G.g_adminMaxBan, "g_adminMaxBan", "2w", C.CVAR_ARCHIVE, 0, false),

	E(G.g_specChat, "g_specChat", "1", C.CVAR_ARCHIVE, 0, false),
	E(G.g_publicAdminMessages, "g_publicAdminMessages", "1", C.CVAR_ARCHIVE, 0, false),

	E(G.g_maxWarnings, "g_maxWarnings", "3", C.CVAR_ARCHIVE, 0, false),
	E(G.g_warningExpire, "g_warningExpire", "3600", C.CVAR_ARCHIVE, 0, false),

	E(G.g_minNameChangePeriod, "g_minNameChangePeriod", "10", 0, 0, false),
	E(G.g_maxNameChanges, "g_maxNameChanges", "50", 0, 0, false),

	E(G.g_timestamp_startgame, "g_timestamp", "0001-01-01 00:00:00", C.CVAR_SERVERINFO, 0, false),
	E(G.g_execute_gametype_script, "g_egs", "0", C.CVAR_ROM, 0, false),
}

-- 0-based array like the C table
local gameCvarTable = {}
for i, cv in gameCvarTableList do
	gameCvarTable[i - 1] = cv
end
G.gameCvarTable = gameCvarTable

local gameCvarTableSize = #gameCvarTableList

--[[
================
vmMain

This is the only way control passes into the module.
This must be the very first function compiled into the .q3vm file
================
]]
function G.vmMain(command, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11)
	if command == C.GAME_INIT then
		G.G_InitGame(arg0, arg1, arg2)
		return 0
	elseif command == C.GAME_SHUTDOWN then
		G.G_ShutdownGame(arg0)
		return 0
	elseif command == C.GAME_CLIENT_CONNECT then
		return G.ClientConnect(arg0, arg1, arg2)
	elseif command == C.GAME_CLIENT_THINK then
		G.ClientThink(arg0)
		return 0
	elseif command == C.GAME_CLIENT_USERINFO_CHANGED then
		G.ClientUserinfoChanged(arg0)
		return 0
	elseif command == C.GAME_CLIENT_DISCONNECT then
		G.ClientDisconnect(arg0)
		return 0
	elseif command == C.GAME_CLIENT_BEGIN then
		G.ClientBegin(arg0)
		return 0
	elseif command == C.GAME_CLIENT_COMMAND then
		G.ClientCommand(arg0)
		return 0
	elseif command == C.GAME_RUN_FRAME then
		G.G_RunFrame(arg0)
		return 0
	elseif command == C.GAME_CONSOLE_COMMAND then
		return G.ConsoleCommand()
	elseif command == C.BOTAI_START_FRAME then
		return G.BotAIStartFrame(arg0)
	end

	return -1
end

function G.G_Printf(fmt, ...)
	local text = string.sub(QS.va(fmt, ...), 1, 1023)

	G.trap_Printf(text)
end

function G.G_Error(fmt, ...)
	local text = string.sub(QS.va(fmt, ...), 1, 1023)

	G.trap_Error(text)
end

--[[
================
G_FindTeams

Chain together all entities with a matching team field.
Entity teams are used for item groups and multi-entity mover groups.

All but the first will have the FL_TEAMSLAVE flag set and teammaster field set
All but the last will have the teamchain field set to the next one
================
]]
function G.G_FindTeams()
	local c = 0
	local c2 = 0
	for i = 1, G.level.num_entities - 1 do
		local e = G.g_entities[i]
		if not e.inuse then
			continue
		end
		if e.team == nil then
			continue
		end
		if bit32.band(e.flags, C.FL_TEAMSLAVE) ~= 0 then
			continue
		end
		e.teammaster = e
		c += 1
		c2 += 1
		for j = i + 1, G.level.num_entities - 1 do
			local e2 = G.g_entities[j]
			if not e2.inuse then
				continue
			end
			if e2.team == nil then
				continue
			end
			if bit32.band(e2.flags, C.FL_TEAMSLAVE) ~= 0 then
				continue
			end
			if e.team == e2.team then
				c2 += 1
				e2.teamchain = e.teamchain
				e.teamchain = e2
				e2.teammaster = e
				e2.flags = bit32.bor(e2.flags, C.FL_TEAMSLAVE)

				-- make sure that targets only point at the master
				if e2.targetname ~= nil then
					e.targetname = e2.targetname
					e2.targetname = nil
				end
			end
		end
	end
	G.G_Printf("%i teams with %i entities\n", c, c2)
end

function G.G_RemapTeamShaders()
end

--[[
=================
G_RegisterCvars
=================
]]
function G.G_RegisterCvars()
	local remapped = false

	for i = 0, gameCvarTableSize - 1 do
		local cv = gameCvarTable[i]
		G.trap_Cvar_Register(cv.vmCvar, cv.cvarName, cv.defaultString, cv.cvarFlags)
		if cv.vmCvar ~= nil then
			cv.modificationCount = cv.vmCvar.modificationCount
		end

		if cv.teamShader then
			remapped = true
		end
	end

	if remapped then
		G.G_RemapTeamShaders()
	end

	-- check some things
	if G.g_gametype.integer < 0 or G.g_gametype.integer >= C.GT_MAX_GAME_TYPE then
		G.G_Printf("g_gametype %i is out of range, defaulting to 0\n", G.g_gametype.integer)
		G.trap_Cvar_Set("g_gametype", "0")
	end

	--set FFA status for high gametypes:
	if G.g_gametype.integer == C.GT_LMS then
		G.g_ffa_gt = 1 --Last Man standig is a FFA gametype
	else
		G.g_ffa_gt = 0 --If >GT_CTF use bases
	end

	G.level.warmupModificationCount = G.g_warmup.modificationCount
end

--[[
=================
G_UpdateCvars
=================
]]
function G.G_UpdateCvars()
	local remapped = false

	for i = 0, gameCvarTableSize - 1 do
		local cv = gameCvarTable[i]
		if cv.vmCvar ~= nil then
			G.trap_Cvar_Update(cv.vmCvar)

			if cv.modificationCount ~= cv.vmCvar.modificationCount then
				cv.modificationCount = cv.vmCvar.modificationCount

				if cv.vmCvar == G.g_gametype then
					--gametype modified
					G.trap_Cvar_Set("g_egs", "1")
				end

				if cv.trackChange then
					G.trap_SendServerCommand(-1, QS.va("print \"Server: %s changed to %s\n\"", cv.cvarName, cv.vmCvar.string))
				end

				if cv.vmCvar == G.g_votecustom then
					G.VoteParseCustomVotes()
				end

				--Here comes the cvars that must trigger a map_restart
				if cv.vmCvar == G.g_instantgib or cv.vmCvar == G.g_rockets or cv.vmCvar == G.g_elimination_allgametypes then
					G.trap_Cvar_Set("sv_dorestart", "1")
				end

				if cv.vmCvar == G.g_voteNames then
					--Set vote flags
					local voteflags = 0
					if G.allowedVote("map_restart") ~= 0 then
						voteflags = bit32.bor(voteflags, C.VF_map_restart)
					end

					if G.allowedVote("map") ~= 0 then
						voteflags = bit32.bor(voteflags, C.VF_map)
					end

					if G.allowedVote("clientkick") ~= 0 then
						voteflags = bit32.bor(voteflags, C.VF_clientkick)
					end

					if G.allowedVote("shuffle") ~= 0 then
						voteflags = bit32.bor(voteflags, C.VF_shuffle)
					end

					if G.allowedVote("nextmap") ~= 0 then
						voteflags = bit32.bor(voteflags, C.VF_nextmap)
					end

					if G.allowedVote("g_gametype") ~= 0 then
						voteflags = bit32.bor(voteflags, C.VF_g_gametype)
					end

					if G.allowedVote("g_doWarmup") ~= 0 then
						voteflags = bit32.bor(voteflags, C.VF_g_doWarmup)
					end

					if G.allowedVote("timelimit") ~= 0 then
						voteflags = bit32.bor(voteflags, C.VF_timelimit)
					end

					if G.allowedVote("fraglimit") ~= 0 then
						voteflags = bit32.bor(voteflags, C.VF_fraglimit)
					end

					if G.allowedVote("custom") ~= 0 then
						voteflags = bit32.bor(voteflags, C.VF_custom)
					end

					G.trap_Cvar_Set("voteflags", QS.va("%i", voteflags))
				end

				if cv.teamShader then
					remapped = true
				end
			end
		end
	end

	if remapped then
		G.G_RemapTeamShaders()
	end
end

-- Sets the cvar g_timestamp. Return 0 if success or !0 for errors.
function SF.G_UpdateTimestamp()
	local timestamp = {
		tm_sec = 0, tm_min = 0, tm_hour = 0, tm_mday = 0, tm_mon = 0,
		tm_year = 0, tm_wday = 0, tm_yday = 0, tm_isdst = 0,
	}
	local ret = G.trap_RealTime(timestamp)
	G.trap_Cvar_Set("g_timestamp", QS.va("%04i-%02i-%02i %02i:%02i:%02i",
		1900 + timestamp.tm_year, 1 + timestamp.tm_mon, timestamp.tm_mday,
		timestamp.tm_hour, timestamp.tm_min, timestamp.tm_sec))
	return ret
end

-- Runs a script if it exists.
-- Returns 0 if the script ran, 1 if it did not exist.
function SF.G_RunScript(script)
	local _len, file = G.trap_FS_FOpenFile(script, C.FS_READ)
	if file == 0 then
		return 1 --script does not exist
	end
	G.trap_FS_FCloseFile(file)
	local command = string.sub(QS.va("exec %s;\n", script), 1, 99)
	G.trap_SendConsoleCommand(C.EXEC_APPEND, command)
	return 0
end

function SF.G_CheckGametypeScripts()
	if G.g_execute_gametype_script.integer ~= 0 then
		SF.G_RunScript(QS.va("gametype_%i.cfg", G.g_gametype.integer))
		G.trap_Cvar_Set("g_egs", "0") --Don't run again on next restart
	end
	return 0
end

--[[
============
G_InitGame

============
]]
function G.G_InitGame(levelTime, randomSeed, restart)
	G.G_Printf("------- Game Initialization -------\n")
	G.G_Printf("gamename: %s\n", GAMEVERSION)
	G.G_Printf("gamedate: %s\n", PRODUCT_DATE)

	Q.srand(randomSeed)

	G.G_RegisterCvars()

	SF.G_UpdateTimestamp()

	--disable unwanted cvars
	if G.g_gametype.integer == C.GT_SINGLE_PLAYER then
		G.g_instantgib.integer = 0
		G.g_rockets.integer = 0
		G.g_vampire.value = 0.0
	end

	G.G_ProcessIPBans()

	--KK-OAX Changed to Tremulous's BG_InitMemory
	G.BG_InitMemory()

	-- set some level globals
	S.copy_level_locals_t(G.level, S.level_locals_t())
	local level = G.level

	level.time = levelTime
	level.startTime = levelTime

	level.snd_fry = G.G_SoundIndex("sound/player/fry.wav") -- FIXME standing in lava / slime

	if G.g_gametype.integer ~= C.GT_SINGLE_PLAYER and G.g_logfile.string ~= "" then
		local _len, handle
		if G.g_logfileSync.integer ~= 0 then
			_len, handle = G.trap_FS_FOpenFile(G.g_logfile.string, C.FS_APPEND_SYNC)
		else
			_len, handle = G.trap_FS_FOpenFile(G.g_logfile.string, C.FS_APPEND)
		end
		level.logFile = handle
		if level.logFile == 0 then
			G.G_Printf("WARNING: Couldn't open logfile: %s\n", G.g_logfile.string)
		else
			local serverinfo = G.trap_GetServerinfo()
			G.G_LogPrintf("------------------------------------------------------------\n")
			G.G_LogPrintf("InitGame: %s\n", serverinfo)
			G.G_LogPrintf("Info: ServerInfo length: %d of %d\n", #serverinfo, C.MAX_INFO_STRING)
		end
	else
		G.G_Printf("Not logging to disk.\n")
	end

	--Parse the custom vote names:
	G.VoteParseCustomVotes()

	G.G_InitWorldSession()

	--KK-OAX Get Admin Configuration
	G.G_admin_readconfig(nil, 0)
	--Let's Load up any killing sprees/multikills
	G.G_ReadAltKillSettings(nil, 0)

	-- initialize all entities for this game
	for i = 0, C.MAX_GENTITIES - 1 do
		G.G_ClearEntity(G.g_entities[i])
	end
	level.gentities = G.g_entities

	-- initialize all clients for this game
	level.maxclients = G.g_maxclients.integer
	for i = 0, C.MAX_CLIENTS - 1 do
		G.G_ClearClient(G.g_clients[i])
	end
	level.clients = G.g_clients

	-- set client fields on player ents
	for i = 0, level.maxclients - 1 do
		G.g_entities[i].client = level.clients[i]
	end

	-- always leave room for the max number of clients,
	-- even if they aren't all used, so numbers inside that
	-- range are NEVER anything but clients
	level.num_entities = C.MAX_CLIENTS

	for i = 0, C.MAX_CLIENTS - 1 do
		G.g_entities[i].classname = "clientslot"
	end

	-- let the server system know where the entites are
	G.trap_LocateGameData(G.g_entities, level.num_entities, level.clients)

	-- reserve some spots for dead player bodies
	G.InitBodyQue()

	G.ClearRegisteredItems()

	-- parse the key/value pairs and spawn gentities
	G.G_SpawnEntitiesFromString()

	-- general initialization
	G.G_FindTeams()

	-- make sure we have flags for CTF, etc
	if G.g_gametype.integer >= C.GT_TEAM and G.g_ffa_gt ~= 1 then
		G.G_CheckTeamItems()
	end

	G.SaveRegisteredItems()

	G.G_Printf("-----------------------------------\n")

	if G.g_gametype.integer == C.GT_SINGLE_PLAYER or G.trap_Cvar_VariableIntegerValue("com_buildScript") ~= 0 then
		G.G_ModelIndex(SP_PODIUM_MODEL)
	end

	if G.trap_Cvar_VariableIntegerValue("bot_enable") ~= 0 then
		G.BotAISetup(restart)
		G.BotAILoadMap(restart)
		G.G_InitBots(restart)
	end

	G.G_RemapTeamShaders()

	--elimination:
	level.roundNumber = 1
	level.roundNumberStarted = 0
	level.roundStartTime = level.time + G.g_elimination_warmup.integer * 1000
	level.roundRespawned = false
	level.eliminationSides = Q.imod(Q.rand(), 2) --0 or 1

	--Challenges:
	level.teamSize = 0
	level.hadBots = false

	if G.g_gametype.integer == C.GT_DOUBLE_D then
		G.Team_SpawnDoubleDominationPoints()
	end

	if G.g_gametype.integer == C.GT_DOMINATION then
		level.dom_scoreGiven = 0
		for i = 0, C.MAX_DOMINATION_POINTS - 1 do
			level.pointStatusDom[i] = C.TEAM_NONE
		end
		level.domination_points_count = 0 --make sure its not too big
	end

	G.PlayerStoreInit()

	--Set vote flags
	do
		local voteflags = 0
		if G.allowedVote("map_restart") ~= 0 then
			voteflags = bit32.bor(voteflags, C.VF_map_restart)
		end

		if G.allowedVote("map") ~= 0 then
			voteflags = bit32.bor(voteflags, C.VF_map)
		end

		if G.allowedVote("clientkick") ~= 0 then
			voteflags = bit32.bor(voteflags, C.VF_clientkick)
		end

		if G.allowedVote("shuffle") ~= 0 then
			voteflags = bit32.bor(voteflags, C.VF_shuffle)
		end

		if G.allowedVote("nextmap") ~= 0 then
			voteflags = bit32.bor(voteflags, C.VF_nextmap)
		end

		if G.allowedVote("g_gametype") ~= 0 then
			voteflags = bit32.bor(voteflags, C.VF_g_gametype)
		end

		if G.allowedVote("g_doWarmup") ~= 0 then
			voteflags = bit32.bor(voteflags, C.VF_g_doWarmup)
		end

		if G.allowedVote("timelimit") ~= 0 then
			voteflags = bit32.bor(voteflags, C.VF_timelimit)
		end

		if G.allowedVote("fraglimit") ~= 0 then
			voteflags = bit32.bor(voteflags, C.VF_fraglimit)
		end

		if G.allowedVote("custom") ~= 0 then
			voteflags = bit32.bor(voteflags, C.VF_custom)
		end

		G.trap_Cvar_Set("voteflags", QS.va("%i", voteflags))
	end
	SF.G_CheckGametypeScripts()
end

return nil
