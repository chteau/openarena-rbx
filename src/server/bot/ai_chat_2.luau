--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/ai_chat.c, part 2 of 2).

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
-- Luau port of OpenArena 0.8.8's ai_chat.c (gamecode 9e0f0c0), part 2 of 2. Bot chat selection: kill, suicide, hit, random chats and the chat test.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local TIME_BETWEENCHATTING = 25

function G.BotChat_Kill(bs)
	local name
	local rnd

	if G.BotNoChat(bs) then return 0 end
	if bs.lastchat_time > G.floattime - TIME_BETWEENCHATTING then return 0 end
	rnd = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_CHAT_KILL, 0, 1)
	-- don't chat in tournament mode
	if G.gametype == C.GT_TOURNAMENT then return 0 end
	--if fast chat is off
	if G.bot_fastchat.integer == 0 then
		if Q.random() > rnd then return 0 end
	end
	if bs.lastkilledplayer == bs.client then return 0 end
	if G.BotNumActivePlayers() <= 1 then return 0 end
	if G.BotValidChatPosition(bs) == 0 then return 0 end
	--
	if G.BotVisibleEnemies(bs) ~= 0 then return 0 end
	--
	name = G.EasyClientName(bs.lastkilledplayer, 32)
	--
	bs.chatto = C.CHAT_ALL
	if G.TeamPlayIsOn() ~= 0 and G.BotSameTeam(bs, bs.lastkilledplayer) ~= 0 then
		G.BotAI_BotInitialChat(bs, "kill_teammate", name)
		bs.chatto = C.CHAT_TEAM
	else
		--don't chat in teamplay
		if G.TeamPlayIsOn() ~= 0 then
			G.trap_EA_Command(bs.client, "vtaunt")
			return 0 -- don't wait
		end
		--
		if bs.enemydeathtype == C.MOD_GAUNTLET then
			G.BotAI_BotInitialChat(bs, "kill_gauntlet", name)
		elseif bs.enemydeathtype == C.MOD_RAILGUN then
			G.BotAI_BotInitialChat(bs, "kill_rail", name)
		elseif bs.enemydeathtype == C.MOD_TELEFRAG then
			G.BotAI_BotInitialChat(bs, "kill_telefrag", name)
		elseif bs.botdeathtype == C.MOD_KAMIKAZE and G.trap_BotNumInitialChats(bs.cs, "kill_kamikaze") ~= 0 then
			G.BotAI_BotInitialChat(bs, "kill_kamikaze", name)
		--choose between insult and praise
		elseif Q.random() < G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_CHAT_INSULT, 0, 1) then
			G.BotAI_BotInitialChat(bs, "kill_insult", name)
		else
			G.BotAI_BotInitialChat(bs, "kill_praise", name)
		end
	end
	bs.lastchat_time = G.floattime
	return 1
end

function G.BotChat_EnemySuicide(bs)
	local name
	local rnd

	if G.BotNoChat(bs) then return 0 end
	if bs.lastchat_time > G.floattime - TIME_BETWEENCHATTING then return 0 end
	if G.BotNumActivePlayers() <= 1 then return 0 end
	--
	rnd = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_CHAT_ENEMYSUICIDE, 0, 1)
	--don't chat in teamplay
	if G.TeamPlayIsOn() ~= 0 then return 0 end
	-- don't chat in tournament mode
	if G.gametype == C.GT_TOURNAMENT then return 0 end
	--if fast chat is off
	if G.bot_fastchat.integer == 0 then
		if Q.random() > rnd then return 0 end
	end
	if G.BotValidChatPosition(bs) == 0 then return 0 end
	--
	if G.BotVisibleEnemies(bs) ~= 0 then return 0 end
	--
	if bs.enemy >= 0 then
		name = G.EasyClientName(bs.enemy, 32)
	else
		name = ""
	end
	G.BotAI_BotInitialChat(bs, "enemy_suicide", name)
	bs.lastchat_time = G.floattime
	bs.chatto = C.CHAT_ALL
	return 1
end

function G.BotChat_HitTalking(bs)
	local name, weap
	local lasthurt_client
	local rnd

	if G.BotNoChat(bs) then return 0 end
	if bs.lastchat_time > G.floattime - TIME_BETWEENCHATTING then return 0 end
	if G.BotNumActivePlayers() <= 1 then return 0 end
	lasthurt_client = G.g_entities[bs.client].client.lasthurt_client
	if lasthurt_client == 0 then return 0 end
	if lasthurt_client == bs.client then return 0 end
	--
	if lasthurt_client < 0 or lasthurt_client >= C.MAX_CLIENTS then return 0 end
	--
	rnd = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_CHAT_HITTALKING, 0, 1)
	--don't chat in teamplay
	if G.TeamPlayIsOn() ~= 0 then return 0 end
	-- don't chat in tournament mode
	if G.gametype == C.GT_TOURNAMENT then return 0 end
	--if fast chat is off
	if G.bot_fastchat.integer == 0 then
		if Q.random() > rnd * 0.5 then return 0 end
	end
	if G.BotValidChatPosition(bs) == 0 then return 0 end
	--
	name = G.ClientName(G.g_entities[bs.client].client.lasthurt_client, 32)
	weap = G.BotWeaponNameForMeansOfDeath(G.g_entities[bs.client].client.lasthurt_mod)
	--
	G.BotAI_BotInitialChat(bs, "hit_talking", name, weap)
	bs.lastchat_time = G.floattime
	bs.chatto = C.CHAT_ALL
	return 1
end

function G.BotChat_HitNoDeath(bs)
	local name, weap
	local rnd
	local lasthurt_client
	local entinfo = S.aas_entityinfo_t()

	lasthurt_client = G.g_entities[bs.client].client.lasthurt_client
	if lasthurt_client == 0 then return 0 end
	if lasthurt_client == bs.client then return 0 end
	--
	if lasthurt_client < 0 or lasthurt_client >= C.MAX_CLIENTS then return 0 end
	--
	if G.BotNoChat(bs) then return 0 end
	if bs.lastchat_time > G.floattime - TIME_BETWEENCHATTING then return 0 end
	if G.BotNumActivePlayers() <= 1 then return 0 end
	rnd = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_CHAT_HITNODEATH, 0, 1)
	--don't chat in teamplay
	if G.TeamPlayIsOn() ~= 0 then return 0 end
	-- don't chat in tournament mode
	if G.gametype == C.GT_TOURNAMENT then return 0 end
	--if fast chat is off
	if G.bot_fastchat.integer == 0 then
		if Q.random() > rnd * 0.5 then return 0 end
	end
	if G.BotValidChatPosition(bs) == 0 then return 0 end
	--
	if G.BotVisibleEnemies(bs) ~= 0 then return 0 end
	--
	G.BotEntityInfo(bs.enemy, entinfo)
	if G.EntityIsShooting(entinfo) then return 0 end
	--
	name = G.ClientName(lasthurt_client, 32)
	weap = G.BotWeaponNameForMeansOfDeath(G.g_entities[bs.client].client.lasthurt_mod)
	--
	G.BotAI_BotInitialChat(bs, "hit_nodeath", name, weap)
	bs.lastchat_time = G.floattime
	bs.chatto = C.CHAT_ALL
	return 1
end

function G.BotChat_HitNoKill(bs)
	local name, weap
	local rnd
	local entinfo = S.aas_entityinfo_t()

	if G.BotNoChat(bs) then return 0 end
	if bs.lastchat_time > G.floattime - TIME_BETWEENCHATTING then return 0 end
	if G.BotNumActivePlayers() <= 1 then return 0 end
	rnd = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_CHAT_HITNOKILL, 0, 1)
	--don't chat in teamplay
	if G.TeamPlayIsOn() ~= 0 then return 0 end
	-- don't chat in tournament mode
	if G.gametype == C.GT_TOURNAMENT then return 0 end
	--if fast chat is off
	if G.bot_fastchat.integer == 0 then
		if Q.random() > rnd * 0.5 then return 0 end
	end
	if G.BotValidChatPosition(bs) == 0 then return 0 end
	--
	if G.BotVisibleEnemies(bs) ~= 0 then return 0 end
	--
	G.BotEntityInfo(bs.enemy, entinfo)
	if G.EntityIsShooting(entinfo) then return 0 end
	--
	name = G.ClientName(bs.enemy, 32)
	weap = G.BotWeaponNameForMeansOfDeath(G.g_entities[bs.enemy].client.lasthurt_mod)
	--
	G.BotAI_BotInitialChat(bs, "hit_nokill", name, weap)
	bs.lastchat_time = G.floattime
	bs.chatto = C.CHAT_ALL
	return 1
end

function G.BotChat_Random(bs)
	local rnd
	local name

	if G.BotNoChat(bs) then return 0 end
	if G.BotIsObserver(bs) then return 0 end
	if bs.lastchat_time > G.floattime - TIME_BETWEENCHATTING then return 0 end
	-- don't chat in tournament mode
	if G.gametype == C.GT_TOURNAMENT then return 0 end
	--don't chat when doing something important :)
	if bs.ltgtype == C.LTG_TEAMHELP or
		bs.ltgtype == C.LTG_TEAMACCOMPANY or
		bs.ltgtype == C.LTG_RUSHBASE then return 0 end
	--
	rnd = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_CHAT_RANDOM, 0, 1)
	if Q.random() > bs.thinktime * 0.1 then return 0 end
	if G.bot_fastchat.integer == 0 then
		if Q.random() > rnd then return 0 end
		if Q.random() > 0.25 then return 0 end
	end
	if G.BotNumActivePlayers() <= 1 then return 0 end
	--
	if G.BotValidChatPosition(bs) == 0 then return 0 end
	--
	if G.BotVisibleEnemies(bs) ~= 0 then return 0 end
	--
	if bs.lastkilledplayer == bs.client then
		name = QS.Q_strncpyz(G.BotRandomOpponentName(bs), 32)
	else
		name = G.EasyClientName(bs.lastkilledplayer, 32)
	end
	if G.TeamPlayIsOn() ~= 0 then
		G.trap_EA_Command(bs.client, "vtaunt")
		return 0 -- don't wait
	end
	--
	if Q.random() < G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_CHAT_MISC, 0, 1) then
		G.BotAI_BotInitialChat(bs, "random_misc",
					G.BotRandomOpponentName(bs), -- 0
					name, -- 1
					"[invalid var]", -- 2
					"[invalid var]", -- 3
					G.BotMapTitle(), -- 4
					G.BotRandomWeaponName()) -- 5
	else
		G.BotAI_BotInitialChat(bs, "random_insult",
					G.BotRandomOpponentName(bs), -- 0
					name, -- 1
					"[invalid var]", -- 2
					"[invalid var]", -- 3
					G.BotMapTitle(), -- 4
					G.BotRandomWeaponName()) -- 5
	end
	bs.lastchat_time = G.floattime
	bs.chatto = C.CHAT_ALL
	return 1
end

function G.BotChatTime(bs)
	return 2.0 --(float) trap_BotChatLength(bs->cs) * 30 / cpm;
end

function G.BotChatTest(bs)
	local name
	local weap
	local num

	if G.BotNoChat(bs) then return end

	num = G.trap_BotNumInitialChats(bs.cs, "game_enter")
	for _ = 0, num - 1 do
		G.BotAI_BotInitialChat(bs, "game_enter",
					G.EasyClientName(bs.client, 32), -- 0
					G.BotRandomOpponentName(bs), -- 1
					"[invalid var]", -- 2
					"[invalid var]", -- 3
					G.BotMapTitle()) -- 4
		G.trap_BotEnterChat(bs.cs, 0, C.CHAT_ALL)
	end
	num = G.trap_BotNumInitialChats(bs.cs, "game_exit")
	for _ = 0, num - 1 do
		G.BotAI_BotInitialChat(bs, "game_exit",
					G.EasyClientName(bs.client, 32), -- 0
					G.BotRandomOpponentName(bs), -- 1
					"[invalid var]", -- 2
					"[invalid var]", -- 3
					G.BotMapTitle()) -- 4
		G.trap_BotEnterChat(bs.cs, 0, C.CHAT_ALL)
	end
	num = G.trap_BotNumInitialChats(bs.cs, "level_start")
	for _ = 0, num - 1 do
		G.BotAI_BotInitialChat(bs, "level_start",
					G.EasyClientName(bs.client, 32)) -- 0
		G.trap_BotEnterChat(bs.cs, 0, C.CHAT_ALL)
	end
	for _, t in ipairs({ "level_end_victory", "level_end_lose", "level_end" }) do
		num = G.trap_BotNumInitialChats(bs.cs, t)
		for _ = 0, num - 1 do
			G.BotAI_BotInitialChat(bs, t,
					G.EasyClientName(bs.client, 32), -- 0
					G.BotRandomOpponentName(bs), -- 1
					G.BotFirstClientInRankings(), -- 2
					G.BotLastClientInRankings(), -- 3
					G.BotMapTitle()) -- 4
			G.trap_BotEnterChat(bs.cs, 0, C.CHAT_ALL)
		end
	end
	name = G.EasyClientName(bs.lastkilledby, 32)
	for _, t in ipairs({ "death_drown", "death_slime", "death_lava", "death_cratered", "death_suicide", "death_telefrag" }) do
		num = G.trap_BotNumInitialChats(bs.cs, t)
		for _ = 0, num - 1 do
			G.BotAI_BotInitialChat(bs, t, name)
			G.trap_BotEnterChat(bs.cs, 0, C.CHAT_ALL)
		end
	end
	for _, t in ipairs({ "death_gauntlet", "death_rail", "death_bfg", "death_insult", "death_praise" }) do
		num = G.trap_BotNumInitialChats(bs.cs, t)
		for _ = 0, num - 1 do
			G.BotAI_BotInitialChat(bs, t,
					name, -- 0
					G.BotWeaponNameForMeansOfDeath(bs.botdeathtype)) -- 1
			G.trap_BotEnterChat(bs.cs, 0, C.CHAT_ALL)
		end
	end
	--
	name = G.EasyClientName(bs.lastkilledplayer, 32)
	--
	for _, t in ipairs({ "kill_gauntlet", "kill_rail", "kill_telefrag", "kill_insult", "kill_praise", "enemy_suicide" }) do
		num = G.trap_BotNumInitialChats(bs.cs, t)
		for _ = 0, num - 1 do
			G.BotAI_BotInitialChat(bs, t, name)
			G.trap_BotEnterChat(bs.cs, 0, C.CHAT_ALL)
		end
	end
	name = G.ClientName(G.g_entities[bs.client].client.lasthurt_client, 32)
	weap = G.BotWeaponNameForMeansOfDeath(G.g_entities[bs.client].client.lasthurt_client)
	for _, t in ipairs({ "hit_talking", "hit_nodeath", "hit_nokill" }) do
		num = G.trap_BotNumInitialChats(bs.cs, t)
		for _ = 0, num - 1 do
			G.BotAI_BotInitialChat(bs, t, name, weap)
			G.trap_BotEnterChat(bs.cs, 0, C.CHAT_ALL)
		end
	end
	--
	if bs.lastkilledplayer == bs.client then
		name = QS.Q_strncpyz(G.BotRandomOpponentName(bs), 32)
	else
		name = G.EasyClientName(bs.lastkilledplayer, 32)
	end
	--
	for _, t in ipairs({ "random_misc", "random_insult" }) do
		num = G.trap_BotNumInitialChats(bs.cs, t)
		for _ = 0, num - 1 do
			G.BotAI_BotInitialChat(bs, t,
					G.BotRandomOpponentName(bs), -- 0
					name, -- 1
					"[invalid var]", -- 2
					"[invalid var]", -- 3
					G.BotMapTitle(), -- 4
					G.BotRandomWeaponName()) -- 5
			G.trap_BotEnterChat(bs.cs, 0, C.CHAT_ALL)
		end
	end
end

return nil
