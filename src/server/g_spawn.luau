--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_spawn.c).

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
-- Luau port of OpenArena 0.8.8's g_spawn.c (gamecode 9e0f0c0). Parses the entity string and spawns gentities.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local GAME_VERSION = "baseoa-1"

-- sscanf(s, "%f %f %f", ...): assigns as many leading values as parse
local function scanVec3(s, out)
	local n = 0
	for tok in string.gmatch(s, "%S+") do
		if n >= 3 then
			break
		end
		if string.match(tok, "^[+-]?%.?%d") == nil then
			break
		end
		out[n] = QS.atof(tok)
		n += 1
	end
end

function G.G_SpawnString(key, defaultString, out)
	if not G.level.spawning then
		out = defaultString
	end

	for i = 0, G.level.numSpawnVars - 1 do
		if QS.Q_stricmp(key, G.level.spawnVars[i][0]) == 0 then
			return true, G.level.spawnVars[i][1]
		end
	end

	return false, defaultString
end

function G.G_SpawnFloat(key, defaultString, out)
	local present, s = G.G_SpawnString(key, defaultString)
	return present, QS.atof(s)
end

function G.G_SpawnInt(key, defaultString, out)
	local present, s = G.G_SpawnString(key, defaultString)
	return present, QS.atoi(s)
end

function G.G_SpawnVector(key, defaultString, out)
	local present, s = G.G_SpawnString(key, defaultString)
	local v = { [0] = 0, 0, 0 }
	scanVec3(s, v)
	return present, v
end

-- fields are needed for spawning from the entity string
local F_INT = 0
local F_FLOAT = 1
local F_LSTRING = 2
local F_GSTRING = 3
local F_VECTOR = 4
local F_ANGLEHACK = 5
local F_ENTITY = 6
local F_ITEM = 7
local F_CLIENT = 8
local F_IGNORE = 9

local fields = {
	{ name = "classname", field = "classname", type = F_LSTRING },
	{ name = "origin", field = "s.origin", type = F_VECTOR },
	{ name = "model", field = "model", type = F_LSTRING },
	{ name = "model2", field = "model2", type = F_LSTRING },
	{ name = "spawnflags", field = "spawnflags", type = F_INT },
	{ name = "speed", field = "speed", type = F_FLOAT },
	{ name = "target", field = "target", type = F_LSTRING },
	{ name = "targetname", field = "targetname", type = F_LSTRING },
	{ name = "message", field = "message", type = F_LSTRING },
	{ name = "team", field = "team", type = F_LSTRING },
	{ name = "wait", field = "wait", type = F_FLOAT },
	{ name = "random", field = "random", type = F_FLOAT },
	{ name = "count", field = "count", type = F_INT },
	{ name = "health", field = "health", type = F_INT },
	{ name = "light", field = "", type = F_IGNORE },
	{ name = "dmg", field = "damage", type = F_INT },
	{ name = "angles", field = "s.angles", type = F_VECTOR },
	{ name = "angle", field = "s.angles", type = F_ANGLEHACK },
	{ name = "targetShaderName", field = "targetShaderName", type = F_LSTRING },
	{ name = "targetShaderNewName", field = "targetShaderNewName", type = F_LSTRING },
}

local function SP(name)
	return function(ent)
		G.sp_dispatch(name, ent)
	end
end

function G.sp_dispatch(name, ent)
	G[name](ent)
end

function G.SP_item_botroam(ent) end

local function spawnEntry(classname, fn)
	return { name = classname, spawn = fn }
end

local spawns = {
	-- info entities don't do anything at all, but provide positional
	-- information for things controlled by other processes
	spawnEntry("info_player_start", SP("SP_info_player_start")),
	spawnEntry("info_player_deathmatch", SP("SP_info_player_deathmatch")),
	spawnEntry("info_player_intermission", SP("SP_info_player_intermission")),
	--Double Domination player spawn:
	spawnEntry("info_player_dd", SP("SP_info_player_dd")),
	spawnEntry("info_player_dd_red", SP("SP_info_player_dd_red")),
	spawnEntry("info_player_dd_blue", SP("SP_info_player_dd_blue")),
	--Standard Domination point spawn:
	spawnEntry("domination_point", SP("SP_domination_point")),

	spawnEntry("info_null", SP("SP_info_null")),
	spawnEntry("info_notnull", SP("SP_info_notnull")), -- use target_position instead
	spawnEntry("info_camp", SP("SP_info_camp")),

	spawnEntry("func_plat", SP("SP_func_plat")),
	spawnEntry("func_button", SP("SP_func_button")),
	spawnEntry("func_door", SP("SP_func_door")),
	spawnEntry("func_static", SP("SP_func_static")),
	spawnEntry("func_rotating", SP("SP_func_rotating")),
	spawnEntry("func_bobbing", SP("SP_func_bobbing")),
	spawnEntry("func_pendulum", SP("SP_func_pendulum")),
	spawnEntry("func_train", SP("SP_func_train")),
	spawnEntry("func_group", SP("SP_info_null")),
	spawnEntry("func_timer", SP("SP_func_timer")), -- rename trigger_timer?

	-- Triggers are brush objects that cause an effect when contacted
	-- by a living player, usually involving firing targets.
	-- While almost everything could be done with
	-- a single trigger class and different targets, triggered effects
	-- could not be client side predicted (push and teleport).
	spawnEntry("trigger_always", SP("SP_trigger_always")),
	spawnEntry("trigger_multiple", SP("SP_trigger_multiple")),
	spawnEntry("trigger_push", SP("SP_trigger_push")),
	spawnEntry("trigger_teleport", SP("SP_trigger_teleport")),
	spawnEntry("trigger_hurt", SP("SP_trigger_hurt")),

	-- targets perform no action by themselves, but must be triggered
	-- by another entity
	spawnEntry("target_give", SP("SP_target_give")),
	spawnEntry("target_remove_powerups", SP("SP_target_remove_powerups")),
	spawnEntry("target_delay", SP("SP_target_delay")),
	spawnEntry("target_speaker", SP("SP_target_speaker")),
	spawnEntry("target_print", SP("SP_target_print")),
	spawnEntry("target_laser", SP("SP_target_laser")),
	spawnEntry("target_score", SP("SP_target_score")),
	spawnEntry("target_teleporter", SP("SP_target_teleporter")),
	spawnEntry("target_relay", SP("SP_target_relay")),
	spawnEntry("target_kill", SP("SP_target_kill")),
	spawnEntry("target_position", SP("SP_target_position")),
	spawnEntry("target_location", SP("SP_target_location")),
	spawnEntry("target_push", SP("SP_target_push")),

	spawnEntry("light", SP("SP_light")),
	spawnEntry("path_corner", SP("SP_path_corner")),

	spawnEntry("misc_teleporter_dest", SP("SP_misc_teleporter_dest")),
	spawnEntry("misc_model", SP("SP_misc_model")),
	spawnEntry("misc_portal_surface", SP("SP_misc_portal_surface")),
	spawnEntry("misc_portal_camera", SP("SP_misc_portal_camera")),

	spawnEntry("shooter_rocket", SP("SP_shooter_rocket")),
	spawnEntry("shooter_grenade", SP("SP_shooter_grenade")),
	spawnEntry("shooter_plasma", SP("SP_shooter_plasma")),

	spawnEntry("team_CTF_redplayer", SP("SP_team_CTF_redplayer")),
	spawnEntry("team_CTF_blueplayer", SP("SP_team_CTF_blueplayer")),

	spawnEntry("team_CTF_redspawn", SP("SP_team_CTF_redspawn")),
	spawnEntry("team_CTF_bluespawn", SP("SP_team_CTF_bluespawn")),

	spawnEntry("team_redobelisk", SP("SP_team_redobelisk")),
	spawnEntry("team_blueobelisk", SP("SP_team_blueobelisk")),
	spawnEntry("team_neutralobelisk", SP("SP_team_neutralobelisk")),

	spawnEntry("item_botroam", SP("SP_item_botroam")),
}

--[[
===============
G_CallSpawn

Finds the spawn function for the entity and calls it,
returning qfalse if not found
===============
]]
function G.G_CallSpawn(ent)
	--Construct a replace cvar:
	local cvarname = QS.Com_sprintf(128, "replace_%s", ent.classname)
	local itemname

	--Look an alternative item up:
	itemname = G.trap_Cvar_VariableStringBuffer(cvarname)
	if itemname == "" then --If nothing found use original
		itemname = QS.Com_sprintf(128, "%s", ent.classname)
	else
		G.G_Printf("%s replaced by %s\n", ent.classname, itemname)
	end

	if itemname == "" then
		G.G_Printf("G_CallSpawn: NULL classname\n")
		return false
	end

	-- check item spawn functions
	local idx = 1
	while true do
		local item = BG.bg_itemlist[idx]
		if item == nil or item.classname == nil or item.classname == "" then
			break
		end
		if item.classname == itemname then
			G.G_SpawnItem(ent, item)
			return true
		end
		idx += 1
	end

	-- check normal spawn functions
	for _, s in spawns do
		if s.name == itemname then
			-- found it
			s.spawn(ent)
			return true
		end
	end
	G.G_Printf("%s doesn't have a spawn function\n", itemname)
	return false
end

--[[
=============
G_NewString

Builds a copy of the string, translating \n to real linefeeds
so message texts can be multi-line
=============
]]
function G.G_NewString(str)
	local out = {}
	local l = #str + 1

	-- turn \n into a real linefeed
	local i = 0
	while i < l do
		if i < l - 1 and string.byte(str, i + 1) == 92 then
			i += 1
			if string.byte(str, i + 1) == 110 then
				table.insert(out, "\n")
			else
				table.insert(out, "\\")
			end
		elseif i < l - 1 then
			table.insert(out, string.sub(str, i + 1, i + 1))
		end
		i += 1
	end

	return table.concat(out)
end

--[[
===============
G_ParseField

Takes a key/value pair and sets the binary values
in a gentity
===============
]]
function G.G_ParseField(key, value, ent)
	for _, f in fields do
		if QS.Q_stricmp(f.name, key) == 0 then
			-- found it
			local holder = ent
			local fname = f.field
			local sub = string.match(fname, "^(%w+)%.")
			if sub ~= nil then
				holder = ent[sub]
				fname = string.sub(fname, #sub + 2)
			end

			if f.type == F_LSTRING then
				holder[fname] = G.G_NewString(value)
			elseif f.type == F_VECTOR then
				local vec = { [0] = 0, 0, 0 }
				scanVec3(value, vec)
				holder[fname][0] = Q.f(vec[0])
				holder[fname][1] = Q.f(vec[1])
				holder[fname][2] = Q.f(vec[2])
			elseif f.type == F_INT then
				holder[fname] = QS.atoi(value)
			elseif f.type == F_FLOAT then
				holder[fname] = Q.f(QS.atof(value))
			elseif f.type == F_ANGLEHACK then
				local v = QS.atof(value)
				holder[fname][0] = 0
				holder[fname][1] = Q.f(v)
				holder[fname][2] = 0
			end
			return
		end
	end
end

local gametypeNames = {
	[0] = "ffa", "tournament", "single", "team", "ctf", "oneflag", "obelisk", "harvester",
	"elimination", "ctf", "lms", "dd", "dom",
}

--[[
===================
G_SpawnGEntityFromSpawnVars

Spawn an entity and fill in all of the level fields from
level.spawnVars[], then call the class specfic spawn function
===================
]]
function G.G_SpawnGEntityFromSpawnVars()
	local level = G.level
	local i

	-- get the next free entity
	local ent = G.G_Spawn()

	for n = 0, level.numSpawnVars - 1 do
		G.G_ParseField(level.spawnVars[n][0], level.spawnVars[n][1], ent)
	end

	-- check for "notsingle" flag
	if G.g_gametype.integer == C.GT_SINGLE_PLAYER then
		local _
		_, i = G.G_SpawnInt("notsingle", "0")
		if i ~= 0 then
			G.G_FreeEntity(ent)
			return
		end
	end
	-- check for "notteam" flag (GT_FFA, GT_TOURNAMENT, GT_SINGLE_PLAYER)
	if G.g_gametype.integer >= C.GT_TEAM and G.g_ffa_gt == 0 then
		local _
		_, i = G.G_SpawnInt("notteam", "0")
		if i ~= 0 then
			G.G_FreeEntity(ent)
			return
		end
	else
		local _
		_, i = G.G_SpawnInt("notfree", "0")
		if i ~= 0 then
			G.G_FreeEntity(ent)
			return
		end
	end

	do
		local _
		_, i = G.G_SpawnInt("notq3a", "0")
		if i ~= 0 then
			G.G_FreeEntity(ent)
			return
		end
	end

	local found, value = G.G_SpawnString("!gametype", nil)
	if found then
		if G.g_gametype.integer >= C.GT_FFA and G.g_gametype.integer < C.GT_MAX_GAME_TYPE then
			local gametypeName = gametypeNames[G.g_gametype.integer]

			local s = QS.strstr(value, gametypeName)
			if s ~= nil then
				G.G_FreeEntity(ent)
				return
			end
		end
	end

	found, value = G.G_SpawnString("gametype", nil)
	if found then
		if G.g_gametype.integer >= C.GT_FFA and G.g_gametype.integer < C.GT_MAX_GAME_TYPE then
			local gametypeName = gametypeNames[G.g_gametype.integer]

			local s = QS.strstr(value, gametypeName)
			if s == nil then
				G.G_FreeEntity(ent)
				return
			end
		end
	end

	-- move editor origin to pos
	Q.VectorCopy(ent.s.origin, ent.s.pos.trBase)
	Q.VectorCopy(ent.s.origin, ent.r.currentOrigin)

	-- if we didn't get a classname, don't bother spawning anything
	if not G.G_CallSpawn(ent) then
		G.G_FreeEntity(ent)
	end
end

--[[
====================
G_AddSpawnVarToken
====================
]]
function G.G_AddSpawnVarToken(str)
	local l = #str
	if G.level.numSpawnVarChars + l + 1 > C.MAX_SPAWN_VARS_CHARS then
		G.G_Error("G_AddSpawnVarToken: MAX_SPAWN_VARS")
	end

	G.level.numSpawnVarChars += l + 1

	return str
end

--[[
====================
G_ParseSpawnVars

Parses a brace bounded set of key / value pairs out of the
level's entity strings into level.spawnVars[]

This does not actually spawn an entity.
====================
]]
function G.G_ParseSpawnVars()
	local level = G.level

	level.numSpawnVars = 0
	level.numSpawnVarChars = 0

	-- parse the opening brace
	local com_token = G.trap_GetEntityToken()
	if com_token == nil then
		-- end of spawn string
		return false
	end
	if string.sub(com_token, 1, 1) ~= "{" then
		G.G_Error("G_ParseSpawnVars: found %s when expecting {", com_token)
	end

	-- go through all the key / value pairs
	while true do
		-- parse key
		local keyname = G.trap_GetEntityToken()
		if keyname == nil then
			G.G_Error("G_ParseSpawnVars: EOF without closing brace")
		end

		if string.sub(keyname, 1, 1) == "}" then
			break
		end

		-- parse value
		com_token = G.trap_GetEntityToken()
		if com_token == nil then
			G.G_Error("G_ParseSpawnVars: EOF without closing brace")
		end

		if string.sub(com_token, 1, 1) == "}" then
			G.G_Error("G_ParseSpawnVars: closing brace without data")
		end
		if level.numSpawnVars == C.MAX_SPAWN_VARS then
			G.G_Error("G_ParseSpawnVars: MAX_SPAWN_VARS")
		end
		level.spawnVars[level.numSpawnVars] = { [0] = G.G_AddSpawnVarToken(keyname), [1] = G.G_AddSpawnVarToken(com_token) }
		level.numSpawnVars += 1
	end

	return true
end

--[[QUAKED worldspawn (0 0 0) ?

Every map should have exactly one worldspawn.
"music"		music wav file
"gravity"	800 is default gravity
"message"	Text to print during connection process
]]
function G.SP_worldspawn()
	local _, s = G.G_SpawnString("classname", "")
	if QS.Q_stricmp(s, "worldspawn") ~= 0 then
		G.G_Error("SP_worldspawn: The first entity isn't 'worldspawn'")
	end

	-- make some data visible to connecting client
	G.trap_SetConfigstring(C.CS_GAME_VERSION, GAME_VERSION)

	G.trap_SetConfigstring(C.CS_LEVEL_START_TIME, QS.va("%i", G.level.startTime))

	if G.g_music.string ~= "" and QS.Q_stricmp(G.g_music.string, "none") ~= 0 then
		G.trap_SetConfigstring(C.CS_MUSIC, G.g_music.string)
	else
		_, s = G.G_SpawnString("music", "")
		G.trap_SetConfigstring(C.CS_MUSIC, s)
	end

	_, s = G.G_SpawnString("message", "")
	G.trap_SetConfigstring(C.CS_MESSAGE, s) -- map specific message

	G.trap_SetConfigstring(C.CS_MOTD, G.g_motd.string) -- message of the day

	_, s = G.G_SpawnString("gravity", "800")
	G.trap_Cvar_Set("g_gravity", s)

	_, s = G.G_SpawnString("enableDust", "0")
	G.trap_Cvar_Set("g_enableDust", s)

	_, s = G.G_SpawnString("enableBreath", "0")
	G.trap_Cvar_Set("g_enableBreath", s)

	G.g_entities[C.ENTITYNUM_WORLD].s.number = C.ENTITYNUM_WORLD
	G.g_entities[C.ENTITYNUM_WORLD].r.ownerNum = C.ENTITYNUM_NONE
	G.g_entities[C.ENTITYNUM_WORLD].classname = "worldspawn"

	G.g_entities[C.ENTITYNUM_NONE].s.number = C.ENTITYNUM_NONE
	G.g_entities[C.ENTITYNUM_NONE].r.ownerNum = C.ENTITYNUM_NONE
	G.g_entities[C.ENTITYNUM_NONE].classname = "nothing"

	-- see if we want a warmup time
	G.trap_SetConfigstring(C.CS_WARMUP, "")
	if G.g_restarted.integer ~= 0 then
		G.trap_Cvar_Set("g_restarted", "0")
		G.level.warmupTime = 0
	elseif G.g_doWarmup.integer ~= 0 then -- Turn it on
		G.level.warmupTime = -1
		G.trap_SetConfigstring(C.CS_WARMUP, QS.va("%i", G.level.warmupTime))
		G.G_LogPrintf("Warmup:\n")
	end
end

--[[
==============
G_SpawnEntitiesFromString

Parses textual entity definitions out of an entstring and spawns gentities.
==============
]]
function G.G_SpawnEntitiesFromString()
	-- allow calls to G_Spawn*()
	G.level.spawning = true
	G.level.numSpawnVars = 0

	-- the worldspawn is not an actual entity, but it still
	-- has a "spawn" function to perform any global setup
	-- needed by a level (setting configstrings or cvars, etc)
	if not G.G_ParseSpawnVars() then
		G.G_Error("SpawnEntities: no entities")
	end
	G.SP_worldspawn()

	-- parse ents
	while G.G_ParseSpawnVars() do
		G.G_SpawnGEntityFromSpawnVars()
	end

	G.level.spawning = false -- any future calls to G_Spawn*() will be errors
end

return nil
