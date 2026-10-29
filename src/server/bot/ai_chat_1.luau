--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/ai_chat.c, part 1 of 2).

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
-- Luau port of OpenArena 0.8.8's ai_chat.c (gamecode 9e0f0c0), part 1 of 2. Bot chat helpers and the chat triggers up to BotChat_Death.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local SF = G.FileStatics("ai_chat")

SF.TIME_BETWEENCHATTING = 25

-- true if the configstring of client i describes a non-spectating named player
local function ActivePlayerConfig(i)
	local buf = G.trap_GetConfigstring(C.CS_PLAYERS + i)
	if #buf == 0 or #QS.Info_ValueForKey(buf, "n") == 0 then return false end
	if QS.atoi(QS.Info_ValueForKey(buf, "t")) == C.TEAM_SPECTATOR then return false end
	return true
end

local maxclients_BotNumActivePlayers = 0
local maxclients_BotIsFirstInRankings = 0
local maxclients_BotIsLastInRankings = 0
local maxclients_BotFirstClientInRankings = 0
local maxclients_BotLastClientInRankings = 0
local maxclients_BotRandomOpponentName = 0

function G.BotNumActivePlayers()
	if maxclients_BotNumActivePlayers == 0 then
		maxclients_BotNumActivePlayers = G.trap_Cvar_VariableIntegerValue("sv_maxclients")
	end
	local num = 0
	for i = 0, math.min(maxclients_BotNumActivePlayers, C.MAX_CLIENTS) - 1 do
		if ActivePlayerConfig(i) then
			num += 1
		end
	end
	return num
end

function G.BotIsFirstInRankings(bs)
	local score = bs.cur_ps.persistant[C.PERS_SCORE]
	local ps = S.playerState_t()
	if maxclients_BotIsFirstInRankings == 0 then
		maxclients_BotIsFirstInRankings = G.trap_Cvar_VariableIntegerValue("sv_maxclients")
	end
	for i = 0, math.min(maxclients_BotIsFirstInRankings, C.MAX_CLIENTS) - 1 do
		if not ActivePlayerConfig(i) then continue end
		G.BotAI_GetClientState(i, ps)
		if score < ps.persistant[C.PERS_SCORE] then return 0 end
	end
	return 1
end

function G.BotIsLastInRankings(bs)
	local score = bs.cur_ps.persistant[C.PERS_SCORE]
	local ps = S.playerState_t()
	if maxclients_BotIsLastInRankings == 0 then
		maxclients_BotIsLastInRankings = G.trap_Cvar_VariableIntegerValue("sv_maxclients")
	end
	for i = 0, math.min(maxclients_BotIsLastInRankings, C.MAX_CLIENTS) - 1 do
		if not ActivePlayerConfig(i) then continue end
		G.BotAI_GetClientState(i, ps)
		if score > ps.persistant[C.PERS_SCORE] then return 0 end
	end
	return 1
end

function G.BotFirstClientInRankings()
	local bestscore = -999999
	local bestclient = 0
	local ps = S.playerState_t()
	if maxclients_BotFirstClientInRankings == 0 then
		maxclients_BotFirstClientInRankings = G.trap_Cvar_VariableIntegerValue("sv_maxclients")
	end
	for i = 0, math.min(maxclients_BotFirstClientInRankings, C.MAX_CLIENTS) - 1 do
		if not ActivePlayerConfig(i) then continue end
		G.BotAI_GetClientState(i, ps)
		if ps.persistant[C.PERS_SCORE] > bestscore then
			bestscore = ps.persistant[C.PERS_SCORE]
			bestclient = i
		end
	end
	return G.EasyClientName(bestclient, 32)
end

function G.BotLastClientInRankings()
	local worstscore = 999999
	local bestclient = 0
	local ps = S.playerState_t()
	if maxclients_BotLastClientInRankings == 0 then
		maxclients_BotLastClientInRankings = G.trap_Cvar_VariableIntegerValue("sv_maxclients")
	end
	for i = 0, math.min(maxclients_BotLastClientInRankings, C.MAX_CLIENTS) - 1 do
		if not ActivePlayerConfig(i) then continue end
		G.BotAI_GetClientState(i, ps)
		if ps.persistant[C.PERS_SCORE] < worstscore then
			worstscore = ps.persistant[C.PERS_SCORE]
			bestclient = i
		end
	end
	return G.EasyClientName(bestclient, 32)
end

function G.BotRandomOpponentName(bs)
	local opponents = {}
	local numopponents = 0
	opponents[0] = 0
	if maxclients_BotRandomOpponentName == 0 then
		maxclients_BotRandomOpponentName = G.trap_Cvar_VariableIntegerValue("sv_maxclients")
	end
	for i = 0, math.min(maxclients_BotRandomOpponentName, C.MAX_CLIENTS) - 1 do
		if i == bs.client then continue end
		if not ActivePlayerConfig(i) then continue end
		--skip team mates
		if G.BotSameTeam(bs, i) ~= 0 then continue end
		opponents[numopponents] = i
		numopponents += 1
	end
	local count = Q.trunc(Q.random() * numopponents)
	for i = 0, numopponents - 1 do
		count -= 1
		if count <= 0 then
			return G.EasyClientName(opponents[i], 32)
		end
	end
	return G.EasyClientName(opponents[0], 32)
end

function G.BotMapTitle()
	local info = G.trap_GetServerinfo()
	return QS.Q_strncpyz(QS.Info_ValueForKey(info, "mapname"), 128)
end

function G.BotWeaponNameForMeansOfDeath(mod)
	if mod == C.MOD_SHOTGUN then return "Shotgun"
	elseif mod == C.MOD_GAUNTLET then return "Gauntlet"
	elseif mod == C.MOD_MACHINEGUN then return "Machinegun"
	elseif mod == C.MOD_GRENADE or mod == C.MOD_GRENADE_SPLASH then return "Grenade Launcher"
	elseif mod == C.MOD_ROCKET or mod == C.MOD_ROCKET_SPLASH then return "Rocket Launcher"
	elseif mod == C.MOD_PLASMA or mod == C.MOD_PLASMA_SPLASH then return "Plasmagun"
	elseif mod == C.MOD_RAILGUN then return "Railgun"
	elseif mod == C.MOD_LIGHTNING then return "Lightning Gun"
	elseif mod == C.MOD_BFG or mod == C.MOD_BFG_SPLASH then return "BFG10K"
	elseif mod == C.MOD_NAIL then return "Nailgun"
	elseif mod == C.MOD_CHAINGUN then return "Chaingun"
	elseif mod == C.MOD_PROXIMITY_MINE then return "Proximity Launcher"
	elseif mod == C.MOD_KAMIKAZE then return "Kamikaze"
	elseif mod == C.MOD_JUICED then return "Prox mine"
	elseif mod == C.MOD_GRAPPLE then return "Grapple"
	end
	return "[unknown weapon]"
end

function G.BotRandomWeaponName()
	local rnd = Q.trunc(Q.random() * 11.9)
	if rnd == 0 then return "Gauntlet"
	elseif rnd == 1 then return "Shotgun"
	elseif rnd == 2 then return "Machinegun"
	elseif rnd == 3 then return "Grenade Launcher"
	elseif rnd == 4 then return "Rocket Launcher"
	elseif rnd == 5 then return "Plasmagun"
	elseif rnd == 6 then return "Railgun"
	elseif rnd == 7 then return "Lightning Gun"
	elseif rnd == 8 then return "Nailgun"
	elseif rnd == 9 then return "Chaingun"
	elseif rnd == 10 then return "Proximity Launcher"
	end
	return "BFG10K"
end

function G.BotVisibleEnemies(bs)
	local entinfo = S.aas_entityinfo_t()

	for i = 0, C.MAX_CLIENTS - 1 do
		if i == bs.client then continue end
		G.BotEntityInfo(i, entinfo)
		if entinfo.valid == 0 then continue end
		--if the enemy isn't dead and the enemy isn't the bot self
		if G.EntityIsDead(entinfo) or entinfo.number == bs.entitynum then continue end
		--if the enemy is invisible and not shooting
		if G.EntityIsInvisible(entinfo) and not G.EntityIsShooting(entinfo) then
			continue
		end
		--if on the same team
		if G.BotSameTeam(bs, i) ~= 0 then continue end
		--check if the enemy is visible
		local vis = G.BotEntityVisible(bs.entitynum, bs.eye, bs.viewangles, 360, i)
		if vis > 0 then return 1 end
	end
	return 0
end

function G.BotValidChatPosition(bs)
	local point = Q.vec3()
	local start = Q.vec3()
	local end_ = Q.vec3()
	local mins = Q.vec3()
	local maxs = Q.vec3()
	local trace = S.bsp_trace_t()

	--if the bot is dead all positions are valid
	if G.BotIsDead(bs) then return 1 end
	if G.BotIsObserver(bs) then return 1 end
	--never start chatting with a powerup
	if bs.inventory[C.INVENTORY_QUAD] ~= 0 or
		bs.inventory[C.INVENTORY_ENVIRONMENTSUIT] ~= 0 or
		bs.inventory[C.INVENTORY_HASTE] ~= 0 or
		bs.inventory[C.INVENTORY_INVISIBILITY] ~= 0 or
		bs.inventory[C.INVENTORY_REGEN] ~= 0 or
		bs.inventory[C.INVENTORY_FLIGHT] ~= 0 then return 0 end
	--do not chat if in lava or slime
	Q.VectorCopy(bs.origin, point)
	point[2] -= 24
	if bit32.band(G.trap_PointContents(point, bs.entitynum), bit32.bor(C.CONTENTS_LAVA, C.CONTENTS_SLIME)) ~= 0 then return 0 end
	--do not chat if under water
	Q.VectorCopy(bs.origin, point)
	point[2] += 32
	if bit32.band(G.trap_PointContents(point, bs.entitynum), C.MASK_WATER) ~= 0 then return 0 end
	--must be standing on the world entity
	Q.VectorCopy(bs.origin, start)
	Q.VectorCopy(bs.origin, end_)
	start[2] += 1
	end_[2] -= 10
	G.trap_AAS_PresenceTypeBoundingBox(C.PRESENCE_CROUCH, mins, maxs)
	G.BotAI_Trace(trace, start, mins, maxs, end_, bs.client, C.MASK_SOLID)
	if trace.ent ~= C.ENTITYNUM_WORLD then return 0 end
	--the bot is in a position where it can chat
	return 1
end

function G.BotChat_EnterGame(bs)
	if G.bot_nochat.integer ~= 0 then return 0 end
	if bs.lastchat_time > G.floattime - SF.TIME_BETWEENCHATTING then return 0 end
	--don't chat in teamplay
	if G.TeamPlayIsOn() ~= 0 then return 0 end
	-- don't chat in tournament mode
	if G.gametype == C.GT_TOURNAMENT then return 0 end
	local rnd = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_CHAT_ENTEREXITGAME, 0, 1)
	if G.bot_fastchat.integer == 0 then
		if Q.random() > rnd then return 0 end
	end
	if G.BotNumActivePlayers() <= 1 then return 0 end
	if G.BotValidChatPosition(bs) == 0 then return 0 end
	G.BotAI_BotInitialChat(bs, "game_enter",
		G.EasyClientName(bs.client, 32),	-- 0
		G.BotRandomOpponentName(bs),		-- 1
		"[invalid var]",					-- 2
		"[invalid var]",					-- 3
		G.BotMapTitle())					-- 4
	bs.lastchat_time = G.floattime
	bs.chatto = C.CHAT_ALL
	return 1
end

function G.BotChat_ExitGame(bs)
	if G.bot_nochat.integer ~= 0 then return 0 end
	if bs.lastchat_time > G.floattime - SF.TIME_BETWEENCHATTING then return 0 end
	--don't chat in teamplay
	if G.TeamPlayIsOn() ~= 0 then return 0 end
	-- don't chat in tournament mode
	if G.gametype == C.GT_TOURNAMENT then return 0 end
	local rnd = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_CHAT_ENTEREXITGAME, 0, 1)
	if G.bot_fastchat.integer == 0 then
		if Q.random() > rnd then return 0 end
	end
	if G.BotNumActivePlayers() <= 1 then return 0 end
	G.BotAI_BotInitialChat(bs, "game_exit",
		G.EasyClientName(bs.client, 32),	-- 0
		G.BotRandomOpponentName(bs),		-- 1
		"[invalid var]",					-- 2
		"[invalid var]",					-- 3
		G.BotMapTitle())					-- 4
	bs.lastchat_time = G.floattime
	bs.chatto = C.CHAT_ALL
	return 1
end

function G.BotChat_StartLevel(bs)
	if G.bot_nochat.integer ~= 0 then return 0 end
	if G.BotIsObserver(bs) then return 0 end
	if bs.lastchat_time > G.floattime - SF.TIME_BETWEENCHATTING then return 0 end
	--don't chat in teamplay
	if G.TeamPlayIsOn() ~= 0 then
		G.trap_EA_Command(bs.client, "vtaunt")
		return 0
	end
	-- don't chat in tournament mode
	if G.gametype == C.GT_TOURNAMENT then return 0 end
	local rnd = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_CHAT_STARTENDLEVEL, 0, 1)
	if G.bot_fastchat.integer == 0 then
		if Q.random() > rnd then return 0 end
	end
	if G.BotNumActivePlayers() <= 1 then return 0 end
	G.BotAI_BotInitialChat(bs, "level_start",
		G.EasyClientName(bs.client, 32))	-- 0
	bs.lastchat_time = G.floattime
	bs.chatto = C.CHAT_ALL
	return 1
end

function G.BotChat_EndLevel(bs)
	if G.bot_nochat.integer ~= 0 then return 0 end
	if G.BotIsObserver(bs) then return 0 end
	if bs.lastchat_time > G.floattime - SF.TIME_BETWEENCHATTING then return 0 end
	-- teamplay
	if G.TeamPlayIsOn() ~= 0 then
		if G.BotIsFirstInRankings(bs) ~= 0 then
			G.trap_EA_Command(bs.client, "vtaunt")
		end
		return 1
	end
	-- don't chat in tournament mode
	if G.gametype == C.GT_TOURNAMENT then return 0 end
	local rnd = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_CHAT_STARTENDLEVEL, 0, 1)
	if G.bot_fastchat.integer == 0 then
		if Q.random() > rnd then return 0 end
	end
	if G.BotNumActivePlayers() <= 1 then return 0 end
	if G.BotIsFirstInRankings(bs) ~= 0 then
		G.BotAI_BotInitialChat(bs, "level_end_victory",
			G.EasyClientName(bs.client, 32),	-- 0
			G.BotRandomOpponentName(bs),		-- 1
			"[invalid var]",					-- 2
			G.BotLastClientInRankings(),		-- 3
			G.BotMapTitle())					-- 4
	elseif G.BotIsLastInRankings(bs) ~= 0 then
		G.BotAI_BotInitialChat(bs, "level_end_lose",
			G.EasyClientName(bs.client, 32),	-- 0
			G.BotRandomOpponentName(bs),		-- 1
			G.BotFirstClientInRankings(),		-- 2
			"[invalid var]",					-- 3
			G.BotMapTitle())					-- 4
	else
		G.BotAI_BotInitialChat(bs, "level_end",
			G.EasyClientName(bs.client, 32),	-- 0
			G.BotRandomOpponentName(bs),		-- 1
			G.BotFirstClientInRankings(),		-- 2
			G.BotLastClientInRankings(),		-- 3
			G.BotMapTitle())					-- 4
	end
	bs.lastchat_time = G.floattime
	bs.chatto = C.CHAT_ALL
	return 1
end

function G.BotChat_Death(bs)
	local name

	if G.bot_nochat.integer ~= 0 then return 0 end
	if bs.lastchat_time > G.floattime - SF.TIME_BETWEENCHATTING then return 0 end
	local rnd = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_CHAT_DEATH, 0, 1)
	-- don't chat in tournament mode
	if G.gametype == C.GT_TOURNAMENT then return 0 end
	--if fast chatting is off
	if G.bot_fastchat.integer == 0 then
		if Q.random() > rnd then return 0 end
	end
	if G.BotNumActivePlayers() <= 1 then return 0 end
	if bs.lastkilledby >= 0 and bs.lastkilledby < C.MAX_CLIENTS then
		name = G.EasyClientName(bs.lastkilledby, 32)
	else
		name = "[world]"
	end
	if G.TeamPlayIsOn() ~= 0 and G.BotSameTeam(bs, bs.lastkilledby) ~= 0 then
		if bs.lastkilledby == bs.client then return 0 end
		G.BotAI_BotInitialChat(bs, "death_teammate", name)
		bs.chatto = C.CHAT_TEAM
	else
		--teamplay
		if G.TeamPlayIsOn() ~= 0 then
			G.trap_EA_Command(bs.client, "vtaunt")
			return 1
		end
		local dt = bs.botdeathtype
		if dt == C.MOD_WATER then
			G.BotAI_BotInitialChat(bs, "death_drown", G.BotRandomOpponentName(bs))
		elseif dt == C.MOD_SLIME then
			G.BotAI_BotInitialChat(bs, "death_slime", G.BotRandomOpponentName(bs))
		elseif dt == C.MOD_LAVA then
			G.BotAI_BotInitialChat(bs, "death_lava", G.BotRandomOpponentName(bs))
		elseif dt == C.MOD_FALLING then
			G.BotAI_BotInitialChat(bs, "death_cratered", G.BotRandomOpponentName(bs))
		elseif bs.botsuicide ~= 0 or --all other suicides by own weapon
				dt == C.MOD_CRUSH or
				dt == C.MOD_SUICIDE or
				dt == C.MOD_TARGET_LASER or
				dt == C.MOD_TRIGGER_HURT or
				dt == C.MOD_UNKNOWN then
			G.BotAI_BotInitialChat(bs, "death_suicide", G.BotRandomOpponentName(bs))
		elseif dt == C.MOD_TELEFRAG then
			G.BotAI_BotInitialChat(bs, "death_telefrag", name)
		elseif dt == C.MOD_KAMIKAZE and G.trap_BotNumInitialChats(bs.cs, "death_kamikaze") ~= 0 then
			G.BotAI_BotInitialChat(bs, "death_kamikaze", name)
		else
			if (dt == C.MOD_GAUNTLET or
				dt == C.MOD_RAILGUN or
				dt == C.MOD_BFG or
				dt == C.MOD_BFG_SPLASH) and Q.random() < 0.5 then

				if dt == C.MOD_GAUNTLET then
					G.BotAI_BotInitialChat(bs, "death_gauntlet",
						name,										-- 0
						G.BotWeaponNameForMeansOfDeath(dt))			-- 1
				elseif dt == C.MOD_RAILGUN then
					G.BotAI_BotInitialChat(bs, "death_rail",
						name,										-- 0
						G.BotWeaponNameForMeansOfDeath(dt))			-- 1
				else
					G.BotAI_BotInitialChat(bs, "death_bfg",
						name,										-- 0
						G.BotWeaponNameForMeansOfDeath(dt))			-- 1
				end
			--choose between insult and praise
			elseif Q.random() < G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_CHAT_INSULT, 0, 1) then
				G.BotAI_BotInitialChat(bs, "death_insult",
					name,											-- 0
					G.BotWeaponNameForMeansOfDeath(dt))				-- 1
			else
				G.BotAI_BotInitialChat(bs, "death_praise",
					name,											-- 0
					G.BotWeaponNameForMeansOfDeath(dt))				-- 1
			end
		end
		bs.chatto = C.CHAT_ALL
	end
	bs.lastchat_time = G.floattime
	return 1
end

return nil
