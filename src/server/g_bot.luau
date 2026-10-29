--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_bot.c).

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
-- Luau port of OpenArena 0.8.8's g_bot.c (gamecode 9e0f0c0). Bot and arena info loading, bot spawn queue, addbot/botlist commands.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local S_COLOR_RED = "^1"
local S_COLOR_YELLOW = "^3"

local g_numBots = 0
local g_botInfos = {}

G.g_numArenas = 0
local g_arenaInfos = {}

local BOT_BEGIN_DELAY_BASE = 2000
local BOT_BEGIN_DELAY_INCREMENT = 1500

local BOT_SPAWN_QUEUE_DEPTH = 16

local botSpawnQueue = {}
for i = 0, BOT_SPAWN_QUEUE_DEPTH - 1 do
	botSpawnQueue[i] = { clientNum = 0, spawnTime = 0 }
end

G.bot_minplayers = S.vmCvar_t()
G.bot_autominplayers = S.vmCvar_t()

-- static in G_CheckMinimumPlayers
local checkminimumplayers_time = 0

--[[
===============
G_ParseInfos
===============
]]
function G.G_ParseInfos(buf, max, infos)
	local token
	local count
	local key
	local info

	local p = QS.cursor(buf)
	count = 0

	while true do
		token = QS.COM_Parse(p)
		if token == "" then
			break
		end
		if token ~= "{" then
			G.Com_Printf("Missing { in info file\n")
			break
		end

		if count == max then
			G.Com_Printf("Max infos exceeded\n")
			break
		end

		info = ""
		while true do
			token = QS.COM_ParseExt(p, true)
			if token == "" then
				G.Com_Printf("Unexpected end of info file\n")
				break
			end
			if token == "}" then
				break
			end
			key = QS.Q_strncpyz(token, C.MAX_TOKEN_CHARS)

			token = QS.COM_ParseExt(p, false)
			if token == "" then
				token = "<NULL>"
			end
			info = QS.Info_SetValueForKey(info, key, token)
		end
		infos[count] = info
		count += 1
	end
	return count
end

--[[
===============
G_LoadArenasFromFile
===============
]]
local function G_LoadArenasFromFile(filename)
	local len, f = G.trap_FS_FOpenFile(filename, C.FS_READ)
	if f == 0 then
		G.trap_Printf(QS.va(S_COLOR_RED .. "file not found: %s\n", filename))
		return
	end
	if len >= C.MAX_ARENAS_TEXT then
		G.trap_Printf(QS.va(S_COLOR_RED .. "file too large: %s is %i, max allowed is %i\n", filename, len, C.MAX_ARENAS_TEXT))
		G.trap_FS_FCloseFile(f)
		return
	end

	local buf = G.trap_FS_Read(len, f)
	G.trap_FS_FCloseFile(f)

	local tmp = {}
	local n = G.G_ParseInfos(buf, C.MAX_ARENAS - G.g_numArenas, tmp)
	for i = 0, n - 1 do
		g_arenaInfos[G.g_numArenas + i] = tmp[i]
	end
	G.g_numArenas += n
end

--[[
===============
G_LoadArenas
===============
]]
local function G_LoadArenas()
	local arenasFile = S.vmCvar_t()

	G.g_numArenas = 0

	G.trap_Cvar_Register(arenasFile, "g_arenasFile", "", bit32.bor(C.CVAR_INIT, C.CVAR_ROM))
	if arenasFile.string ~= "" then
		G_LoadArenasFromFile(arenasFile.string)
	else
		G_LoadArenasFromFile("scripts/arenas.txt")
	end

	-- get all arenas from .arena files
	local numdirs, dirlist = G.trap_FS_GetFileList("scripts", ".arena")
	for i = 0, numdirs - 1 do
		local filename = "scripts/" .. dirlist[i]
		G_LoadArenasFromFile(filename)
	end
	G.trap_Printf(QS.va("%i arenas parsed\n", G.g_numArenas))

	for n = 0, G.g_numArenas - 1 do
		g_arenaInfos[n] = QS.Info_SetValueForKey(g_arenaInfos[n], "num", QS.va("%i", n))
	end
end

--[[
===============
G_GetArenaInfoByNumber
===============
]]
function G.G_GetArenaInfoByMap(map)
	for n = 0, G.g_numArenas - 1 do
		if QS.Q_stricmp(QS.Info_ValueForKey(g_arenaInfos[n], "map"), map) == 0 then
			return g_arenaInfos[n]
		end
	end

	return nil
end

--[[
=================
PlayerIntroSound
=================
]]
local function PlayerIntroSound(modelAndSkin)
	local model = QS.Q_strncpyz(modelAndSkin, C.MAX_QPATH)
	local skin
	local head, tail = string.match(model, "^(.*)/(.*)$")
	if head ~= nil then
		model = head
		skin = tail
	else
		skin = model
	end

	if QS.Q_stricmp(skin, "default") == 0 then
		skin = model
	end

	G.trap_SendConsoleCommand(C.EXEC_APPEND, QS.va("play sound/player/announce/%s.wav\n", skin))
end

--[[
===============
G_AddRandomBot
===============
]]
function G.G_AddRandomBot(team)
	local i, num
	local skill
	local value, netname, teamstr
	local cl

	if not G.trap_AAS_Initialized() then
		return -- If no AAS then don't even try
	end

	num = 0
	for n = 0, g_numBots - 1 do
		value = QS.Info_ValueForKey(g_botInfos[n], "name")
		--
		i = 0
		while i < G.g_maxclients.integer do
			cl = G.level.clients[i]
			if
				cl.pers.connected == C.CON_CONNECTED
				and bit32.band(G.g_entities[cl.ps.clientNum].r.svFlags, C.SVF_BOT) ~= 0
				and not (team >= 0 and cl.sess.sessionTeam ~= team)
				and QS.Q_stricmp(value, cl.pers.netname) == 0
			then
				break
			end
			i += 1
		end
		if i >= G.g_maxclients.integer then
			num += 1
		end
	end
	num = Q.trunc(Q.random() * num)
	for n = 0, g_numBots - 1 do
		value = QS.Info_ValueForKey(g_botInfos[n], "name")
		--
		i = 0
		while i < G.g_maxclients.integer do
			cl = G.level.clients[i]
			if
				cl.pers.connected == C.CON_CONNECTED
				and bit32.band(G.g_entities[cl.ps.clientNum].r.svFlags, C.SVF_BOT) ~= 0
				and not (team >= 0 and cl.sess.sessionTeam ~= team)
				and QS.Q_stricmp(value, cl.pers.netname) == 0
			then
				break
			end
			i += 1
		end
		if i >= G.g_maxclients.integer then
			num -= 1
			if num <= 0 then
				skill = G.trap_Cvar_VariableValue("g_spSkill")
				if team == C.TEAM_RED then
					teamstr = "red"
				elseif team == C.TEAM_BLUE then
					teamstr = "blue"
				else
					teamstr = ""
				end
				netname = string.sub(value, 1, 35)
				netname = QS.Q_CleanStr(netname)
				G.trap_SendConsoleCommand(C.EXEC_INSERT, QS.va("addbot %s %f %s %i\n", netname, skill, teamstr, 0))
				return
			end
		end
	end
end

--[[
===============
G_RemoveRandomBot
===============
]]
function G.G_RemoveRandomBot(team)
	for i = 0, G.g_maxclients.integer - 1 do
		local cl = G.level.clients[i]
		if cl.pers.connected ~= C.CON_CONNECTED then
			continue
		end
		if bit32.band(G.g_entities[cl.ps.clientNum].r.svFlags, C.SVF_BOT) == 0 then
			continue
		end
		if team >= 0 and cl.sess.sessionTeam ~= team then
			continue
		end
		G.trap_SendConsoleCommand(C.EXEC_INSERT, QS.va("clientkick %d\n", cl.ps.clientNum))
		return true
	end
	return false
end

--[[
===============
G_CountHumanPlayers
===============
]]
function G.G_CountHumanPlayers(team)
	local num = 0
	for i = 0, G.g_maxclients.integer - 1 do
		local cl = G.level.clients[i]
		if cl.pers.connected ~= C.CON_CONNECTED then
			continue
		end
		if bit32.band(G.g_entities[cl.ps.clientNum].r.svFlags, C.SVF_BOT) ~= 0 then
			continue
		end
		if team >= 0 and cl.sess.sessionTeam ~= team then
			continue
		end
		num += 1
	end
	return num
end

--[[
===============
G_CountBotPlayers

===============
]]
function G.G_CountBotPlayers(team)
	local num = 0
	for i = 0, G.g_maxclients.integer - 1 do
		local cl = G.level.clients[i]
		if cl.pers.connected ~= C.CON_CONNECTED then
			continue
		end
		if bit32.band(G.g_entities[cl.ps.clientNum].r.svFlags, C.SVF_BOT) == 0 then
			continue
		end
		if team >= 0 and cl.sess.sessionTeam ~= team then
			continue
		end
		num += 1
	end
	for n = 0, BOT_SPAWN_QUEUE_DEPTH - 1 do
		if botSpawnQueue[n].spawnTime == 0 then
			continue
		end
		if botSpawnQueue[n].spawnTime > G.level.time then
			continue
		end
		num += 1
	end
	return num
end

--[[
===============
G_CheckMinimumPlayers
===============
]]
function G.G_CheckMinimumPlayers()
	local minplayers
	local humanplayers, botplayers

	if G.level.intermissiontime ~= 0 then
		return
	end
	--only check once each 10 seconds
	if checkminimumplayers_time > G.level.time - 10000 then
		return
	end
	checkminimumplayers_time = G.level.time
	G.trap_Cvar_Update(G.bot_minplayers)
	minplayers = G.bot_minplayers.integer
	if minplayers <= 0 then
		return
	end

	if not G.trap_AAS_Initialized() then
		minplayers = 0
		checkminimumplayers_time = G.level.time + 600 * 1000
		return -- If no AAS then don't even try
	end

	if G.g_gametype.integer >= C.GT_TEAM and G.g_ffa_gt ~= 1 then
		if minplayers >= Q.idiv(G.g_maxclients.integer, 2) then
			minplayers = Q.idiv(G.g_maxclients.integer, 2) - 1
		end

		humanplayers = G.G_CountHumanPlayers(C.TEAM_RED)
		botplayers = G.G_CountBotPlayers(C.TEAM_RED)
		--
		if humanplayers + botplayers < minplayers then
			G.G_AddRandomBot(C.TEAM_RED)
		elseif humanplayers + botplayers > minplayers and botplayers ~= 0 then
			G.G_RemoveRandomBot(C.TEAM_RED)
		end
		--
		humanplayers = G.G_CountHumanPlayers(C.TEAM_BLUE)
		botplayers = G.G_CountBotPlayers(C.TEAM_BLUE)
		--
		if humanplayers + botplayers < minplayers then
			G.G_AddRandomBot(C.TEAM_BLUE)
		elseif humanplayers + botplayers > minplayers and botplayers ~= 0 then
			G.G_RemoveRandomBot(C.TEAM_BLUE)
		end
	elseif G.g_gametype.integer == C.GT_TOURNAMENT then
		if minplayers >= G.g_maxclients.integer then
			minplayers = G.g_maxclients.integer - 1
		end
		humanplayers = G.G_CountHumanPlayers(-1)
		botplayers = G.G_CountBotPlayers(-1)
		--
		if humanplayers + botplayers < minplayers then
			G.G_AddRandomBot(C.TEAM_FREE)
		elseif humanplayers + botplayers > minplayers and botplayers ~= 0 then
			-- try to remove spectators first
			if not G.G_RemoveRandomBot(C.TEAM_SPECTATOR) then
				-- just remove the bot that is playing
				G.G_RemoveRandomBot(-1)
			end
		end
	elseif G.g_gametype.integer == C.GT_FFA or G.g_gametype.integer == C.GT_LMS then
		if minplayers >= G.g_maxclients.integer then
			minplayers = G.g_maxclients.integer - 1
		end
		humanplayers = G.G_CountHumanPlayers(C.TEAM_FREE)
		botplayers = G.G_CountBotPlayers(C.TEAM_FREE)
		--
		if humanplayers + botplayers < minplayers then
			G.G_AddRandomBot(C.TEAM_FREE)
		elseif humanplayers + botplayers > minplayers and botplayers ~= 0 then
			G.G_RemoveRandomBot(C.TEAM_FREE)
		end
	end
end

--[[
===============
G_CheckBotSpawn
===============
]]
function G.G_CheckBotSpawn()
	G.G_CheckMinimumPlayers()

	for n = 0, BOT_SPAWN_QUEUE_DEPTH - 1 do
		if botSpawnQueue[n].spawnTime == 0 then
			continue
		end
		if botSpawnQueue[n].spawnTime > G.level.time then
			continue
		end
		G.ClientBegin(botSpawnQueue[n].clientNum)
		botSpawnQueue[n].spawnTime = 0

		if G.g_gametype.integer == C.GT_SINGLE_PLAYER then
			local userinfo = G.trap_GetUserinfo(botSpawnQueue[n].clientNum)
			PlayerIntroSound(QS.Info_ValueForKey(userinfo, "model"))
		end
	end
end

--[[
===============
AddBotToSpawnQueue
===============
]]
local function AddBotToSpawnQueue(clientNum, delay)
	for n = 0, BOT_SPAWN_QUEUE_DEPTH - 1 do
		if botSpawnQueue[n].spawnTime == 0 then
			botSpawnQueue[n].spawnTime = G.level.time + delay
			botSpawnQueue[n].clientNum = clientNum
			return
		end
	end
	G.G_Printf(S_COLOR_YELLOW .. "Unable to delay spawn\n")
	G.ClientBegin(clientNum)
end

--[[
===============
G_RemoveQueuedBotBegin

Called on client disconnect to make sure the delayed spawn
doesn't happen on a freed index
===============
]]
function G.G_RemoveQueuedBotBegin(clientNum)
	for n = 0, BOT_SPAWN_QUEUE_DEPTH - 1 do
		if botSpawnQueue[n].clientNum == clientNum then
			botSpawnQueue[n].spawnTime = 0
			return
		end
	end
end

--[[
===============
G_BotConnect
===============
]]
function G.G_BotConnect(clientNum, restart)
	local userinfo = G.trap_GetUserinfo(clientNum)

	local settings = {
		characterfile = QS.Q_strncpyz(QS.Info_ValueForKey(userinfo, "characterfile"), C.MAX_FILEPATH),
		skill = QS.atof(QS.Info_ValueForKey(userinfo, "skill")),
		team = QS.Q_strncpyz(QS.Info_ValueForKey(userinfo, "team"), C.MAX_FILEPATH),
	}

	if not G.trap_AAS_Initialized() or G.BotAISetupClient(clientNum, settings, restart) == 0 then
		G.trap_DropClient(clientNum, "BotAISetupClient failed")
		return false
	end

	return true
end

--[[
===============
G_AddBot
===============
]]
local function G_AddBot(name, skill, team, delay, altname)
	local clientNum
	local botinfo
	local bot
	local key
	local s
	local botname
	local model
	local headmodel
	local userinfo

	-- get the botinfo from bots.txt
	botinfo = G.G_GetBotInfoByName(name)
	if botinfo == nil then
		G.G_Printf(S_COLOR_RED .. "Error: Bot '%s' not defined\n", name)
		return
	end

	-- create the bot's userinfo
	userinfo = ""

	botname = QS.Info_ValueForKey(botinfo, "funname")
	if botname == "" then
		botname = QS.Info_ValueForKey(botinfo, "name")
	end
	-- check for an alternative name
	if altname ~= nil and altname ~= "" then
		botname = altname
	end
	userinfo = QS.Info_SetValueForKey(userinfo, "name", botname)
	userinfo = QS.Info_SetValueForKey(userinfo, "rate", "25000")
	userinfo = QS.Info_SetValueForKey(userinfo, "snaps", "20")
	userinfo = QS.Info_SetValueForKey(userinfo, "skill", QS.va("%1.2f", skill))

	if skill >= 1 and skill < 2 then
		userinfo = QS.Info_SetValueForKey(userinfo, "handicap", "50")
	elseif skill >= 2 and skill < 3 then
		userinfo = QS.Info_SetValueForKey(userinfo, "handicap", "70")
	elseif skill >= 3 and skill < 4 then
		userinfo = QS.Info_SetValueForKey(userinfo, "handicap", "90")
	end

	key = "model"
	model = QS.Info_ValueForKey(botinfo, key)
	if model == "" then
		model = "sarge/default"
	end
	userinfo = QS.Info_SetValueForKey(userinfo, key, model)
	key = "team_model"
	userinfo = QS.Info_SetValueForKey(userinfo, key, model)

	key = "headmodel"
	headmodel = QS.Info_ValueForKey(botinfo, key)
	if headmodel == "" then
		headmodel = model
	end
	userinfo = QS.Info_SetValueForKey(userinfo, key, headmodel)
	key = "team_headmodel"
	userinfo = QS.Info_SetValueForKey(userinfo, key, headmodel)

	key = "gender"
	s = QS.Info_ValueForKey(botinfo, key)
	if s == "" then
		s = "male"
	end
	userinfo = QS.Info_SetValueForKey(userinfo, "sex", s)

	key = "color1"
	s = QS.Info_ValueForKey(botinfo, key)
	if s == "" then
		s = "4"
	end
	userinfo = QS.Info_SetValueForKey(userinfo, key, s)

	key = "color2"
	s = QS.Info_ValueForKey(botinfo, key)
	if s == "" then
		s = "5"
	end
	userinfo = QS.Info_SetValueForKey(userinfo, key, s)

	s = QS.Info_ValueForKey(botinfo, "aifile")
	if s == "" then
		G.trap_Printf(S_COLOR_RED .. "Error: bot has no aifile specified\n")
		return
	end

	-- have the server allocate a client slot
	clientNum = G.trap_BotAllocateClient()
	if clientNum == -1 then
		G.G_Printf(S_COLOR_RED .. "Unable to add bot.  All player slots are in use.\n")
		G.G_Printf(S_COLOR_RED .. "Start server with more 'open' slots (or check setting of sv_maxclients cvar).\n")
		return
	end

	-- initialize the bot settings
	if team == nil or team == "" then
		if G.g_gametype.integer >= C.GT_TEAM and G.g_ffa_gt ~= 1 then
			if G.PickTeam(clientNum) == C.TEAM_RED then
				team = "red"
			else
				team = "blue"
			end
		else
			team = "red"
		end
	end
	userinfo = QS.Info_SetValueForKey(userinfo, "characterfile", QS.Info_ValueForKey(botinfo, "aifile"))
	userinfo = QS.Info_SetValueForKey(userinfo, "skill", QS.va("%5.2f", skill))
	userinfo = QS.Info_SetValueForKey(userinfo, "team", team)

	bot = G.g_entities[clientNum]
	bot.r.svFlags = bit32.bor(bot.r.svFlags, C.SVF_BOT)
	bot.inuse = true

	-- register the userinfo
	G.trap_SetUserinfo(clientNum, userinfo)

	-- have it connect to the game as a normal client
	if G.ClientConnect(clientNum, true, true) ~= nil then
		return
	end

	if delay == 0 then
		G.ClientBegin(clientNum)
		return
	end

	AddBotToSpawnQueue(clientNum, delay)
end

--[[
===============
Svcmd_AddBot_f
===============
]]
function G.Svcmd_AddBot_f()
	local skill
	local delay
	local name
	local altname
	local str
	local team

	-- are bots enabled?
	if G.trap_Cvar_VariableIntegerValue("bot_enable") == 0 or not G.trap_AAS_Initialized() then
		return
	end

	-- name
	name = G.trap_Argv(1)
	if name == "" then
		G.trap_Printf("Usage: Addbot <botname> [skill 1-5] [team] [msec delay] [altname]\n")
		return
	end

	-- skill
	str = G.trap_Argv(2)
	if str == "" then
		skill = 4
	else
		skill = QS.atof(str)
	end

	-- team
	team = G.trap_Argv(3)

	-- delay
	str = G.trap_Argv(4)
	if str == "" then
		delay = 0
	else
		delay = QS.atoi(str)
	end

	-- alternative name
	altname = G.trap_Argv(5)

	G_AddBot(name, skill, team, delay, altname)

	-- if this was issued during gameplay and we are playing locally,
	-- go ahead and load the bot's media immediately
	if G.level.time - G.level.startTime > 1000 and G.trap_Cvar_VariableIntegerValue("cl_running") ~= 0 then
		G.trap_SendServerCommand(-1, "loaddefered\n") -- FIXME: spelled wrong, but not changing for demo
	end
end

--[[
===============
Svcmd_BotList_f
===============
]]
function G.Svcmd_BotList_f()
	local name
	local funname
	local model
	local aifile

	G.trap_Printf("^1name             model            aifile              funname\n")
	for i = 0, g_numBots - 1 do
		name = QS.Q_strncpyz(QS.Info_ValueForKey(g_botInfos[i], "name"), C.MAX_TOKEN_CHARS)
		if name == "" then
			name = "UnnamedPlayer"
		end
		funname = QS.Q_strncpyz(QS.Info_ValueForKey(g_botInfos[i], "funname"), C.MAX_TOKEN_CHARS)
		if funname == "" then
			funname = ""
		end
		model = QS.Q_strncpyz(QS.Info_ValueForKey(g_botInfos[i], "model"), C.MAX_TOKEN_CHARS)
		if model == "" then
			model = "sarge/default"
		end
		aifile = QS.Q_strncpyz(QS.Info_ValueForKey(g_botInfos[i], "aifile"), C.MAX_TOKEN_CHARS)
		if aifile == "" then
			aifile = "bots/default_c.c"
		end
		G.trap_Printf(QS.va("%-16s %-16s %-20s %-20s\n", name, model, aifile, funname))
	end
end

--[[
===============
G_SpawnBots
===============
]]
local function G_SpawnBots(botList, baseDelay)
	local bot
	local skill
	local delay
	local bots

	G.podium1 = nil
	G.podium2 = nil
	G.podium3 = nil

	skill = G.trap_Cvar_VariableValue("g_spSkill")
	if skill < 1 then
		G.trap_Cvar_Set("g_spSkill", "1")
		skill = 1
	elseif skill > 5 then
		G.trap_Cvar_Set("g_spSkill", "5")
		skill = 5
	end

	bots = QS.Q_strncpyz(botList, C.MAX_INFO_VALUE)
	local space = string.byte(" ")
	local len = #bots
	local p = 1
	delay = baseDelay
	while p <= len do
		--skip spaces
		while p <= len and string.byte(bots, p) == space do
			p += 1
		end

		-- mark start of bot name
		local start = p

		-- skip until space of null
		while p <= len and string.byte(bots, p) ~= space do
			p += 1
		end
		bot = string.sub(bots, start, p - 1)
		p += 1

		-- we must add the bot this way, calling G_AddBot directly at this stage
		-- does "Bad Things"
		G.trap_SendConsoleCommand(C.EXEC_INSERT, QS.va("addbot %s %f free %i\n", bot, skill, delay))

		delay += BOT_BEGIN_DELAY_INCREMENT
	end
end

--[[
===============
G_LoadBotsFromFile
===============
]]
local function G_LoadBotsFromFile(filename)
	local len, f = G.trap_FS_FOpenFile(filename, C.FS_READ)
	if f == 0 then
		G.trap_Printf(QS.va(S_COLOR_RED .. "file not found: %s\n", filename))
		return
	end
	if len >= C.MAX_BOTS_TEXT then
		G.trap_Printf(QS.va(S_COLOR_RED .. "file too large: %s is %i, max allowed is %i\n", filename, len, C.MAX_BOTS_TEXT))
		G.trap_FS_FCloseFile(f)
		return
	end

	local buf = G.trap_FS_Read(len, f)
	G.trap_FS_FCloseFile(f)

	local tmp = {}
	local n = G.G_ParseInfos(buf, C.MAX_BOTS - g_numBots, tmp)
	for i = 0, n - 1 do
		g_botInfos[g_numBots + i] = tmp[i]
	end
	g_numBots += n
end

--[[
===============
G_LoadBots
===============
]]
local function G_LoadBots()
	local botsFile = S.vmCvar_t()

	if G.trap_Cvar_VariableIntegerValue("bot_enable") == 0 then
		return
	end

	g_numBots = 0

	G.trap_Cvar_Register(botsFile, "g_botsFile", "", bit32.bor(C.CVAR_INIT, C.CVAR_ROM))
	if botsFile.string ~= "" then
		G_LoadBotsFromFile(botsFile.string)
	else
		G_LoadBotsFromFile("scripts/bots.txt")
	end

	-- get all bots from .bot files
	local numdirs, dirlist = G.trap_FS_GetFileList("scripts", ".bot")
	for i = 0, numdirs - 1 do
		local filename = "scripts/" .. dirlist[i]
		G_LoadBotsFromFile(filename)
	end
	G.trap_Printf(QS.va("%i bots parsed\n", g_numBots))
end

--[[
===============
G_GetBotInfoByNumber
===============
]]
function G.G_GetBotInfoByNumber(num)
	if num < 0 or num >= g_numBots then
		G.trap_Printf(QS.va(S_COLOR_RED .. "Invalid bot number: %i\n", num))
		return nil
	end
	return g_botInfos[num]
end

--[[
===============
G_GetBotInfoByName
===============
]]
function G.G_GetBotInfoByName(name)
	local value

	for n = 0, g_numBots - 1 do
		value = QS.Info_ValueForKey(g_botInfos[n], "name")
		if QS.Q_stricmp(value, name) == 0 then
			return g_botInfos[n]
		end
	end

	return nil
end

--[[
===============
G_InitBots
===============
]]
function G.G_InitBots(restart)
	local fragLimit
	local timeLimit
	local arenainfo
	local strValue
	local basedelay
	local map
	local serverinfo

	G_LoadBots()
	G_LoadArenas()

	G.trap_Cvar_Register(G.bot_minplayers, "bot_minplayers", "0", C.CVAR_SERVERINFO)
	G.trap_Cvar_Register(G.bot_autominplayers, "bot_autominplayers", "0", C.CVAR_SERVERINFO)

	if G.g_gametype.integer == C.GT_SINGLE_PLAYER then
		serverinfo = G.trap_GetServerinfo()
		map = QS.Q_strncpyz(QS.Info_ValueForKey(serverinfo, "mapname"), C.MAX_QPATH)
		arenainfo = G.G_GetArenaInfoByMap(map)
		if arenainfo == nil then
			return
		end

		strValue = QS.Info_ValueForKey(arenainfo, "fraglimit")
		fragLimit = QS.atoi(strValue)
		if fragLimit ~= 0 then
			G.trap_Cvar_Set("fraglimit", strValue)
		else
			G.trap_Cvar_Set("fraglimit", "0")
		end

		strValue = QS.Info_ValueForKey(arenainfo, "timelimit")
		timeLimit = QS.atoi(strValue)
		if timeLimit ~= 0 then
			G.trap_Cvar_Set("timelimit", strValue)
		else
			G.trap_Cvar_Set("timelimit", "0")
		end

		if fragLimit == 0 and timeLimit == 0 then
			G.trap_Cvar_Set("fraglimit", "10")
			G.trap_Cvar_Set("timelimit", "0")
		end

		basedelay = BOT_BEGIN_DELAY_BASE
		strValue = QS.Info_ValueForKey(arenainfo, "special")
		if QS.Q_stricmp(strValue, "training") == 0 then
			basedelay += 10000
		end

		if not restart then
			G_SpawnBots(QS.Info_ValueForKey(arenainfo, "bots"), basedelay)
		end
	else
		if G.bot_autominplayers.integer ~= 0 then
			--Set bot_minplayers
			if G.g_gametype.integer == C.GT_TOURNAMENT then
				G.trap_Cvar_Set("bot_minplayers", "2") --Always 2 for Tourney
			else
				basedelay = Q.idiv(G.MinSpawnpointCount(), 2)
				if basedelay < 3 and (G.g_gametype.integer < C.GT_TEAM or G.g_ffa_gt ~= 0) then
					basedelay = 3 --Minimum 3 for FFA
				end
				if basedelay < 2 and not (G.g_gametype.integer < C.GT_TEAM or G.g_ffa_gt ~= 0) then
					basedelay = 2 --Minimum 2 for TEAM
				end
				G.trap_Cvar_Set("bot_minplayers", QS.va("%i", basedelay))
			end
		end
	end
end

return nil
