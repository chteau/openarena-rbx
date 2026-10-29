--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/ai_main.c, part 3 of 3).

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
-- Luau port of ai_main.c, part 3 of 3. Session data, bot client setup/shutdown, map load, frame, library init.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local SF = G.FileStatics("ai_main")

local MAX_PATH = 144

-- static locals of BotAIStartFrame
local local_time = 0
local botlib_residual = 0
local lastbotthink_time = 0

--[[
==============
BotReadSessionData
==============
]]
function G.BotReadSessionData(bs)
	local var = QS.va("botsession%i", bs.client)
	local s = G.trap_Cvar_VariableStringBuffer(var)

	local tokens = {}
	for tok in string.gmatch(s, "%S+") do
		table.insert(tokens, tok)
	end
	local tg = bs.lastgoal_teamgoal
	local setters = {
		{ false, function(v) bs.lastgoal_decisionmaker = v end },
		{ false, function(v) bs.lastgoal_ltgtype = v end },
		{ false, function(v) bs.lastgoal_teammate = v end },
		{ false, function(v) tg.areanum = v end },
		{ false, function(v) tg.entitynum = v end },
		{ false, function(v) tg.flags = v end },
		{ false, function(v) tg.iteminfo = v end },
		{ false, function(v) tg.number = v end },
		{ true, function(v) tg.origin[0] = v end },
		{ true, function(v) tg.origin[1] = v end },
		{ true, function(v) tg.origin[2] = v end },
		{ true, function(v) tg.mins[0] = v end },
		{ true, function(v) tg.mins[1] = v end },
		{ true, function(v) tg.mins[2] = v end },
		{ true, function(v) tg.maxs[0] = v end },
		{ true, function(v) tg.maxs[1] = v end },
		{ true, function(v) tg.maxs[2] = v end },
		{ true, function(v) bs.formation_dist = v end },
	}
	for i, setter in ipairs(setters) do
		local tok = tokens[i]
		if tok == nil or tonumber(tok) == nil then
			break
		end
		if setter[1] then
			setter[2](QS.atof(tok))
		else
			setter[2](QS.atoi(tok))
		end
	end
end

--[[
==============
BotAISetupClient
==============
]]
function G.BotAISetupClient(client, settings, restart)
	if G.botstates[client] == nil then
		G.botstates[client] = S.bot_state_t()
	end
	local bs = G.botstates[client]

	if bs ~= nil and bs.inuse ~= 0 then
		G.BotAI_Print(C.PRT_FATAL, "BotAISetupClient: client %d already setup\n", client)
		return 0
	end

	if not G.trap_AAS_Initialized() then
		G.BotAI_Print(C.PRT_FATAL, "AAS not initialized\n")
		return 0
	end

	--load the bot character
	bs.character = G.trap_BotLoadCharacter(settings.characterfile, settings.skill)
	if bs.character == 0 then
		G.BotAI_Print(C.PRT_FATAL, "couldn't load skill %f from %s\n", settings.skill, settings.characterfile)
		return 0
	end
	--copy the settings
	S.copy_bot_settings_t(bs.settings, settings)
	--allocate a goal state
	bs.gs = G.trap_BotAllocGoalState(client)
	--load the item weights
	local filename = G.trap_Characteristic_String(bs.character, C.CHARACTERISTIC_ITEMWEIGHTS, MAX_PATH)
	local errnum = G.trap_BotLoadItemWeights(bs.gs, filename)
	if errnum ~= C.BLERR_NOERROR then
		G.trap_BotFreeGoalState(bs.gs)
		return 0
	end
	--allocate a weapon state
	bs.ws = G.trap_BotAllocWeaponState()
	--load the weapon weights
	filename = G.trap_Characteristic_String(bs.character, C.CHARACTERISTIC_WEAPONWEIGHTS, MAX_PATH)
	errnum = G.trap_BotLoadWeaponWeights(bs.ws, filename)
	if errnum ~= C.BLERR_NOERROR then
		G.trap_BotFreeGoalState(bs.gs)
		G.trap_BotFreeWeaponState(bs.ws)
		return 0
	end
	--allocate a chat state
	bs.cs = G.trap_BotAllocChatState()
	--load the chat file
	filename = G.trap_Characteristic_String(bs.character, C.CHARACTERISTIC_CHAT_FILE, MAX_PATH)
	local name = G.trap_Characteristic_String(bs.character, C.CHARACTERISTIC_CHAT_NAME, MAX_PATH)
	errnum = G.trap_BotLoadChatFile(bs.cs, filename, name)
	if errnum ~= C.BLERR_NOERROR then
		G.trap_BotFreeChatState(bs.cs)
		G.trap_BotFreeGoalState(bs.gs)
		G.trap_BotFreeWeaponState(bs.ws)
		return 0
	end
	--get the gender characteristic
	local gender = G.trap_Characteristic_String(bs.character, C.CHARACTERISTIC_GENDER, MAX_PATH)
	--set the chat gender
	local g0 = string.sub(gender, 1, 1)
	if g0 == "f" or g0 == "F" then
		G.trap_BotSetChatGender(bs.cs, C.CHAT_GENDERFEMALE)
	elseif g0 == "m" or g0 == "M" then
		G.trap_BotSetChatGender(bs.cs, C.CHAT_GENDERMALE)
	else
		G.trap_BotSetChatGender(bs.cs, C.CHAT_GENDERLESS)
	end

	bs.inuse = 1
	bs.client = client
	bs.entitynum = client
	bs.setupcount = 4
	bs.entergame_time = G.floattime
	bs.ms = G.trap_BotAllocMoveState()
	bs.walker = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_WALKER, 0, 1)
	G.numbots = G.numbots + 1

	if G.trap_Cvar_VariableIntegerValue("bot_testichat") ~= 0 then
		G.trap_BotLibVarSet("bot_testichat", "1")
		G.BotChatTest(bs)
	end
	--NOTE: reschedule the bot thinking
	G.BotScheduleBotThink()
	--if interbreeding start with a mutation
	if G.bot_interbreed ~= 0 then
		G.trap_BotMutateGoalFuzzyLogic(bs.gs, 1)
	end
	-- if we kept the bot client
	if restart then
		G.BotReadSessionData(bs)
	end
	--bot has been setup succesfully
	return 1
end

--[[
==============
BotAIShutdownClient
==============
]]
function G.BotAIShutdownClient(client, restart)
	local bs = G.botstates[client]
	if bs == nil or bs.inuse == 0 then
		return 0
	end

	if restart then
		G.BotWriteSessionData(bs)
	end

	if G.BotChat_ExitGame(bs) ~= 0 then
		G.trap_BotEnterChat(bs.cs, bs.client, C.CHAT_ALL)
	end

	G.trap_BotFreeMoveState(bs.ms)
	--free the goal state
	G.trap_BotFreeGoalState(bs.gs)
	--free the chat file
	G.trap_BotFreeChatState(bs.cs)
	--free the weapon weights
	G.trap_BotFreeWeaponState(bs.ws)
	--free the bot character
	G.trap_BotFreeCharacter(bs.character)
	--
	G.BotFreeWaypoints(bs.checkpoints)
	G.BotFreeWaypoints(bs.patrolpoints)
	--clear activate goal stack
	G.BotClearActivateGoalStack(bs)
	--clear the bot state
	S.copy_bot_state_t(bs, S.bot_state_t())
	--set the inuse flag to qfalse
	bs.inuse = 0

	--there's one bot less
	G.numbots = G.numbots - 1
	--everything went ok
	return 1
end

--[[
==============
BotResetState

called when a bot enters the intermission or observer mode and
when the level is changed
==============
]]
function G.BotResetState(bs)
	--save some things that should not be reset here
	local settings = S.bot_settings_t()
	S.copy_bot_settings_t(settings, bs.settings)
	local ps = S.playerState_t()
	S.copy_playerState_t(ps, bs.cur_ps)
	local inuse = bs.inuse
	local client = bs.client
	local entitynum = bs.entitynum
	local character = bs.character
	local movestate = bs.ms
	local goalstate = bs.gs
	local chatstate = bs.cs
	local weaponstate = bs.ws
	local entergame_time = bs.entergame_time
	--free checkpoints and patrol points
	G.BotFreeWaypoints(bs.checkpoints)
	G.BotFreeWaypoints(bs.patrolpoints)
	--reset the whole state
	S.copy_bot_state_t(bs, S.bot_state_t())
	--copy back some state stuff that should not be reset
	bs.ms = movestate
	bs.gs = goalstate
	bs.cs = chatstate
	bs.ws = weaponstate
	S.copy_playerState_t(bs.cur_ps, ps)
	S.copy_bot_settings_t(bs.settings, settings)
	bs.inuse = inuse
	bs.client = client
	bs.entitynum = entitynum
	bs.character = character
	bs.entergame_time = entergame_time
	--reset several states
	if bs.ms ~= 0 then G.trap_BotResetMoveState(bs.ms) end
	if bs.gs ~= 0 then G.trap_BotResetGoalState(bs.gs) end
	if bs.ws ~= 0 then G.trap_BotResetWeaponState(bs.ws) end
	if bs.gs ~= 0 then G.trap_BotResetAvoidGoals(bs.gs) end
	if bs.ms ~= 0 then G.trap_BotResetAvoidReach(bs.ms) end
end

--[[
==============
BotAILoadMap
==============
]]
function G.BotAILoadMap(restart)
	if restart == 0 or restart == false then
		local mapname = S.vmCvar_t()
		G.trap_Cvar_Register(mapname, "mapname", "", bit32.bor(C.CVAR_SERVERINFO, C.CVAR_ROM))
		G.trap_BotLibLoadMap(mapname.string)
	end

	for i = 0, C.MAX_CLIENTS - 1 do
		local b = G.botstates[i]
		if b ~= nil and b.inuse ~= 0 then
			G.BotResetState(b)
			b.setupcount = 4
		end
	end

	G.BotSetupDeathmatchAI()

	return 1
end

--[[
==================
BotAIStartFrame
==================
]]
function G.BotAIStartFrame(time)
	G.G_CheckBotSpawn()

	G.trap_Cvar_Update(G.bot_rocketjump)
	G.trap_Cvar_Update(G.bot_grapple)
	G.trap_Cvar_Update(G.bot_fastchat)
	G.trap_Cvar_Update(G.bot_nochat)
	G.trap_Cvar_Update(G.bot_testrchat)
	G.trap_Cvar_Update(G.bot_thinktime)
	G.trap_Cvar_Update(G.bot_memorydump)
	G.trap_Cvar_Update(G.bot_saveroutingcache)
	G.trap_Cvar_Update(G.bot_pause)
	G.trap_Cvar_Update(G.bot_report)

	if G.bot_report.integer ~= 0 then
		G.BotUpdateInfoConfigStrings()
	end

	if G.bot_pause.integer ~= 0 then
		-- execute bot user commands every frame
		for i = 0, C.MAX_CLIENTS - 1 do
			local b = G.botstates[i]
			if b == nil or b.inuse == 0 then
				continue
			end
			if G.g_entities[i].client.pers.connected ~= C.CON_CONNECTED then
				continue
			end
			b.lastucmd.forwardmove = 0
			b.lastucmd.rightmove = 0
			b.lastucmd.upmove = 0
			b.lastucmd.buttons = 0
			b.lastucmd.serverTime = time
			G.trap_BotUserCommand(b.client, b.lastucmd)
		end
		return 1
	end

	if G.bot_memorydump.integer ~= 0 then
		G.trap_BotLibVarSet("memorydump", "1")
		G.trap_Cvar_Set("bot_memorydump", "0")
	end
	if G.bot_saveroutingcache.integer ~= 0 then
		G.trap_BotLibVarSet("saveroutingcache", "1")
		G.trap_Cvar_Set("bot_saveroutingcache", "0")
	end
	--check if bot interbreeding is activated
	G.BotInterbreeding()
	--cap the bot think time
	if G.bot_thinktime.integer > 200 then
		G.trap_Cvar_Set("bot_thinktime", "200")
	end
	--if the bot think time changed we should reschedule the bots
	if G.bot_thinktime.integer ~= lastbotthink_time then
		lastbotthink_time = G.bot_thinktime.integer
		G.BotScheduleBotThink()
	end

	local elapsed_time = time - local_time
	local_time = time

	botlib_residual = botlib_residual + elapsed_time

	local thinktime
	if elapsed_time > G.bot_thinktime.integer then
		thinktime = elapsed_time
	else
		thinktime = G.bot_thinktime.integer
	end

	-- update the bot library
	if botlib_residual >= thinktime then
		botlib_residual = botlib_residual - thinktime

		G.trap_BotLibStartFrame(time / 1000)

		if not G.trap_AAS_Initialized() then return 0 end

		--update entities in the botlib
		for i = 0, C.MAX_GENTITIES - 1 do
			local ent = G.g_entities[i]
			if not ent.inuse then
				G.trap_BotLibUpdateEntity(i, nil)
				continue
			end
			if not ent.r.linked then
				G.trap_BotLibUpdateEntity(i, nil)
				continue
			end
			if not (G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_LMS
					or G.g_instantgib.integer ~= 0 or G.g_rockets.integer ~= 0
					or G.g_elimination_allgametypes.integer ~= 0 or G.g_gametype.integer == C.GT_CTF_ELIMINATION)
				and bit32.band(ent.r.svFlags, C.SVF_NOCLIENT) ~= 0 then
				G.trap_BotLibUpdateEntity(i, nil)
				continue
			end
			-- do not update missiles
			if ent.s.eType == C.ET_MISSILE and ent.s.weapon ~= C.WP_GRAPPLING_HOOK then
				G.trap_BotLibUpdateEntity(i, nil)
				continue
			end
			-- do not update event only entities
			if ent.s.eType > C.ET_EVENTS then
				G.trap_BotLibUpdateEntity(i, nil)
				continue
			end

			-- never link prox mine triggers
			if ent.r.contents == C.CONTENTS_TRIGGER then
				if ent.touch == G.ProximityMine_Trigger then
					G.trap_BotLibUpdateEntity(i, nil)
					continue
				end
			end

			--
			local state = S.bot_entitystate_t()
			--
			Q.VectorCopy(ent.r.currentOrigin, state.origin)
			if i < C.MAX_CLIENTS then
				Q.VectorCopy(ent.s.apos.trBase, state.angles)
			else
				Q.VectorCopy(ent.r.currentAngles, state.angles)
			end
			Q.VectorCopy(ent.s.origin2, state.old_origin)
			Q.VectorCopy(ent.r.mins, state.mins)
			Q.VectorCopy(ent.r.maxs, state.maxs)
			state.type = ent.s.eType
			state.flags = ent.s.eFlags
			if ent.r.bmodel then
				state.solid = C.SOLID_BSP
			else
				state.solid = C.SOLID_BBOX
			end
			state.groundent = ent.s.groundEntityNum
			state.modelindex = ent.s.modelindex
			state.modelindex2 = ent.s.modelindex2
			state.frame = ent.s.frame
			state.event = ent.s.event
			state.eventParm = ent.s.eventParm
			state.powerups = ent.s.powerups
			state.legsAnim = ent.s.legsAnim
			state.torsoAnim = ent.s.torsoAnim
			state.weapon = ent.s.weapon
			--
			G.trap_BotLibUpdateEntity(i, state)
		end

		G.BotAIRegularUpdate()
	end

	G.floattime = G.trap_AAS_Time()

	-- execute scheduled bot AI
	for i = 0, C.MAX_CLIENTS - 1 do
		local b = G.botstates[i]
		if b == nil or b.inuse == 0 then
			continue
		end
		--
		b.botthink_residual = b.botthink_residual + elapsed_time
		--
		if b.botthink_residual >= thinktime then
			b.botthink_residual = b.botthink_residual - thinktime

			if not G.trap_AAS_Initialized() then return 0 end

			if G.g_entities[i].client.pers.connected == C.CON_CONNECTED then
				G.BotAI(i, thinktime / 1000)
			end
		end
	end

	-- execute bot user commands every frame
	for i = 0, C.MAX_CLIENTS - 1 do
		local b = G.botstates[i]
		if b == nil or b.inuse == 0 then
			continue
		end
		if G.g_entities[i].client.pers.connected ~= C.CON_CONNECTED then
			continue
		end

		G.BotUpdateInput(b, time, elapsed_time)
		G.trap_BotUserCommand(b.client, b.lastucmd)
	end

	return 1
end

--[[
==============
BotInitLibrary
==============
]]
function G.BotInitLibrary()
	--set the maxclients and maxentities library variables before calling BotSetupLibrary
	local buf = QS.Com_sprintf(144, "%d", G.level.maxclients)
	G.trap_BotLibVarSet("maxclients", buf)
	buf = QS.Com_sprintf(144, "%d", C.MAX_GENTITIES)
	G.trap_BotLibVarSet("maxentities", buf)
	--bsp checksum
	buf = G.trap_Cvar_VariableStringBuffer("sv_mapChecksum")
	if #buf ~= 0 then G.trap_BotLibVarSet("sv_mapChecksum", buf) end
	--maximum number of aas links
	buf = G.trap_Cvar_VariableStringBuffer("max_aaslinks")
	if #buf ~= 0 then G.trap_BotLibVarSet("max_aaslinks", buf) end
	--maximum number of items in a level
	buf = G.trap_Cvar_VariableStringBuffer("max_levelitems")
	if #buf ~= 0 then G.trap_BotLibVarSet("max_levelitems", buf) end
	--game type
	buf = G.trap_Cvar_VariableStringBuffer("g_gametype")
	if #buf == 0 then buf = "0" end
	G.trap_BotLibVarSet("g_gametype", buf)
	--bot developer mode and log file
	G.trap_BotLibVarSet("bot_developer", G.bot_developer.string)
	buf = G.trap_Cvar_VariableStringBuffer("logfile")
	G.trap_BotLibVarSet("log", buf)
	--no chatting
	buf = G.trap_Cvar_VariableStringBuffer("bot_nochat")
	if #buf ~= 0 then G.trap_BotLibVarSet("nochat", buf) end
	--visualize jump pads
	buf = G.trap_Cvar_VariableStringBuffer("bot_visualizejumppads")
	if #buf ~= 0 then G.trap_BotLibVarSet("bot_visualizejumppads", buf) end
	--forced clustering calculations
	buf = G.trap_Cvar_VariableStringBuffer("bot_forceclustering")
	if #buf ~= 0 then G.trap_BotLibVarSet("forceclustering", buf) end
	--forced reachability calculations
	buf = G.trap_Cvar_VariableStringBuffer("bot_forcereachability")
	if #buf ~= 0 then G.trap_BotLibVarSet("forcereachability", buf) end
	--force writing of AAS to file
	buf = G.trap_Cvar_VariableStringBuffer("bot_forcewrite")
	if #buf ~= 0 then G.trap_BotLibVarSet("forcewrite", buf) end
	--no AAS optimization
	buf = G.trap_Cvar_VariableStringBuffer("bot_aasoptimize")
	if #buf ~= 0 then G.trap_BotLibVarSet("aasoptimize", buf) end
	--
	buf = G.trap_Cvar_VariableStringBuffer("bot_saveroutingcache")
	if #buf ~= 0 then G.trap_BotLibVarSet("saveroutingcache", buf) end
	--reload instead of cache bot character files
	buf = G.trap_Cvar_VariableStringBuffer("bot_reloadcharacters")
	if #buf == 0 then buf = "0" end
	G.trap_BotLibVarSet("bot_reloadcharacters", buf)
	--base directory
	buf = G.trap_Cvar_VariableStringBuffer("fs_basepath")
	if #buf ~= 0 then G.trap_BotLibVarSet("basedir", buf) end
	--game directory
	buf = G.trap_Cvar_VariableStringBuffer("fs_game")
	if #buf ~= 0 then G.trap_BotLibVarSet("gamedir", buf) end
	--home directory
	buf = G.trap_Cvar_VariableStringBuffer("fs_homepath")
	if #buf ~= 0 then G.trap_BotLibVarSet("homedir", buf) end
	--setup the bot library
	return G.trap_BotLibSetup()
end

--[[
==============
BotAISetup
==============
]]
function G.BotAISetup(restart)
	G.trap_Cvar_Register(G.bot_thinktime, "bot_thinktime", "100", C.CVAR_CHEAT)
	G.trap_Cvar_Register(G.bot_memorydump, "bot_memorydump", "0", C.CVAR_CHEAT)
	G.trap_Cvar_Register(G.bot_saveroutingcache, "bot_saveroutingcache", "0", C.CVAR_CHEAT)
	G.trap_Cvar_Register(G.bot_pause, "bot_pause", "0", C.CVAR_CHEAT)
	G.trap_Cvar_Register(G.bot_report, "bot_report", "0", C.CVAR_CHEAT)
	G.trap_Cvar_Register(G.bot_testsolid, "bot_testsolid", "0", C.CVAR_CHEAT)
	G.trap_Cvar_Register(G.bot_testclusters, "bot_testclusters", "0", C.CVAR_CHEAT)
	G.trap_Cvar_Register(G.bot_developer, "bot_developer", "0", C.CVAR_CHEAT)
	G.trap_Cvar_Register(G.bot_interbreedchar, "bot_interbreedchar", "", 0)
	G.trap_Cvar_Register(G.bot_interbreedbots, "bot_interbreedbots", "10", 0)
	G.trap_Cvar_Register(G.bot_interbreedcycle, "bot_interbreedcycle", "20", 0)
	G.trap_Cvar_Register(G.bot_interbreedwrite, "bot_interbreedwrite", "", 0)

	--if the game is restarted for a tournament
	if restart ~= 0 and restart ~= false then
		return 1
	end

	--initialize the bot states
	for i = 0, C.MAX_CLIENTS - 1 do
		G.botstates[i] = nil
	end

	local errnum = G.BotInitLibrary()
	if errnum ~= C.BLERR_NOERROR then return 0 end
	return 1
end

--[[
==============
BotAIShutdown
==============
]]
function G.BotAIShutdown(restart)
	--if the game is restarted for a tournament
	if restart ~= 0 and restart ~= false then
		--shutdown all the bots in the botlib
		for i = 0, C.MAX_CLIENTS - 1 do
			local b = G.botstates[i]
			if b ~= nil and b.inuse ~= 0 then
				G.BotAIShutdownClient(b.client, restart)
			end
		end
		--don't shutdown the bot library
	else
		G.trap_BotLibShutdown()
	end
	return 1
end

return nil
