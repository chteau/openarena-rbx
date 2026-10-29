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
-- Luau port of code/q3_ui/ui_gameinfo.c (OpenArena 0.8.8, gamecode 9e0f0c0).

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

--
-- arena and bot info
--

local POOLSIZE = 128 * 1024

local ui_numBots = 0
local ui_botInfos = {}

local ui_numArenas = 0
local ui_arenaInfos = {}

local ui_numSinglePlayerArenas = 0
local ui_numSpecialSinglePlayerArenas = 0

local allocPoint = 0
local outOfMemory = false

local function atoi(s)
	return tonumber(string.match(s, "^%s*([+-]?%d+)")) or 0
end

-- Pool accounting only: returns the offset of the block, or nil when the pool is full.
function U.UI_Alloc(size)
	if allocPoint + size > POOLSIZE then
		outOfMemory = true
		return nil
	end

	local p = allocPoint

	allocPoint += bit32.band(size + 31, bit32.bnot(31))

	return p
end

function U.UI_InitMemory()
	allocPoint = 0
	outOfMemory = false
end

-- infos is a 0-based array; base is the index of the first slot to fill.
function U.UI_ParseInfos(buf, max, infos, base)
	base = base or 0
	local count = 0
	local parser = Q.COM_Parser(buf)

	while true do
		local token = parser:Parse()
		if token == "" then
			break
		end
		if token ~= "{" then
			trap.Print("Missing { in info file\n")
			break
		end

		if count == max then
			trap.Print("Max infos exceeded\n")
			break
		end

		local info = ""
		while true do
			token = parser:ParseExt(true)
			if token == "" then
				trap.Print("Unexpected end of info file\n")
				break
			end
			if token == "}" then
				break
			end
			local key = string.sub(token, 1, C.MAX_TOKEN_CHARS - 1)

			token = parser:ParseExt(false)
			if token == "" then
				token = "<NULL>"
			end
			info = Q.Info_SetValueForKey(info, key, token)
		end
		--NOTE: extra space for arena number
		local p = U.UI_Alloc(#info + #"\\num\\" + #Q.va("%d", C.MAX_ARENAS) + 1)
		if p ~= nil then
			infos[base + count] = info
			count += 1
		end
	end
	return count
end

local function UI_LoadArenasFromFile(filename)
	local len, f = trap.FS_FOpenFile(filename, C.FS_READ)
	if f == nil or f == 0 or len < 0 then
		trap.Print(Q.va("^1file not found: %s\n", filename))
		return
	end
	if len >= C.MAX_ARENAS_TEXT then
		trap.Print(Q.va("^1file too large: %s is %i, max allowed is %i\n", filename, len, C.MAX_ARENAS_TEXT))
		trap.FS_FCloseFile(f)
		return
	end

	local buf = trap.FS_Read(len, f)
	trap.FS_FCloseFile(f)

	ui_numArenas += U.UI_ParseInfos(buf, C.MAX_ARENAS - ui_numArenas, ui_arenaInfos, ui_numArenas)
end

local function UI_LoadArenas()
	ui_numArenas = 0

	local arenasFile = T.vmCvar_t()
	trap.Cvar_Register(arenasFile, "g_arenasFile", "", bit32.bor(C.CVAR_INIT, C.CVAR_ROM))
	if arenasFile.string ~= "" then
		UI_LoadArenasFromFile(arenasFile.string)
	else
		UI_LoadArenasFromFile("scripts/arenas.txt")
	end

	-- get all arenas from .arena files
	local numdirs, dirlist = trap.FS_GetFileList("scripts", ".arena")
	for i = 0, numdirs - 1 do
		local filename = Q.va("scripts/%s", dirlist[i])
		UI_LoadArenasFromFile(filename)
	end
	trap.Print(Q.va("%i arenas parsed\n", ui_numArenas))
	if outOfMemory then
		trap.Print("^3WARNING: not anough memory in pool to load all arenas\n")
	end

	-- set initial numbers
	for n = 0, ui_numArenas - 1 do
		ui_arenaInfos[n] = Q.Info_SetValueForKey(ui_arenaInfos[n], "num", Q.va("%i", n))
	end

	-- go through and count single players levels
	ui_numSinglePlayerArenas = 0
	ui_numSpecialSinglePlayerArenas = 0
	for n = 0, ui_numArenas - 1 do
		-- determine type
		local type = Q.Info_ValueForKey(ui_arenaInfos[n], "type")

		-- if no type specified, it will be treated as "ffa"
		if type ~= "" then
			if string.find(type, "single", 1, true) ~= nil then
				-- check for special single player arenas (training, final)
				local tag = Q.Info_ValueForKey(ui_arenaInfos[n], "special")
				if tag ~= "" then
					ui_numSpecialSinglePlayerArenas += 1
				else
					ui_numSinglePlayerArenas += 1
				end
			end
		end
	end

	local rem = math.fmod(ui_numSinglePlayerArenas, C.ARENAS_PER_TIER)
	if rem ~= 0 then
		ui_numSinglePlayerArenas -= rem
		trap.Print(Q.va("%i arenas ignored to make count divisible by %i\n", rem, C.ARENAS_PER_TIER))
	end

	-- go through once more and assign number to the levels
	local singlePlayerNum = 0
	local specialNum = singlePlayerNum + ui_numSinglePlayerArenas
	local otherNum = specialNum + ui_numSpecialSinglePlayerArenas + rem
	for n = 0, ui_numArenas - 1 do
		local type = Q.Info_ValueForKey(ui_arenaInfos[n], "type")
		local assigned = false

		-- if no type specified, it will be treated as "ffa"
		if type ~= "" then
			if string.find(type, "single", 1, true) ~= nil then
				local tag = Q.Info_ValueForKey(ui_arenaInfos[n], "special")
				if tag ~= "" then
					ui_arenaInfos[n] = Q.Info_SetValueForKey(ui_arenaInfos[n], "num", Q.va("%i", specialNum))
					specialNum += 1
				else
					ui_arenaInfos[n] = Q.Info_SetValueForKey(ui_arenaInfos[n], "num", Q.va("%i", singlePlayerNum))
					singlePlayerNum += 1
				end
				assigned = true
			end
		end

		if not assigned then
			ui_arenaInfos[n] = Q.Info_SetValueForKey(ui_arenaInfos[n], "num", Q.va("%i", otherNum))
			otherNum += 1
		end
	end
end

function U.UI_GetArenaInfoByNumber(num)
	if num < 0 or num >= ui_numArenas then
		trap.Print(Q.va("^1Invalid arena number: %i\n", num))
		return nil
	end

	for n = 0, ui_numArenas - 1 do
		local value = Q.Info_ValueForKey(ui_arenaInfos[n], "num")
		if value ~= "" and atoi(value) == num then
			return ui_arenaInfos[n]
		end
	end

	return nil
end

function U.UI_GetArenaInfoByMap(map)
	for n = 0, ui_numArenas - 1 do
		if Q.stricmp(Q.Info_ValueForKey(ui_arenaInfos[n], "map"), map) == 0 then
			return ui_arenaInfos[n]
		end
	end

	return nil
end

function U.UI_GetSpecialArenaInfo(tag)
	for n = 0, ui_numArenas - 1 do
		if Q.stricmp(Q.Info_ValueForKey(ui_arenaInfos[n], "special"), tag) == 0 then
			return ui_arenaInfos[n]
		end
	end

	return nil
end

local function UI_LoadBotsFromFile(filename)
	local len, f = trap.FS_FOpenFile(filename, C.FS_READ)
	if f == nil or f == 0 or len < 0 then
		trap.Print(Q.va("^1file not found: %s\n", filename))
		return
	end
	if len >= C.MAX_BOTS_TEXT then
		trap.Print(Q.va("^1file too large: %s is %i, max allowed is %i\n", filename, len, C.MAX_BOTS_TEXT))
		trap.FS_FCloseFile(f)
		return
	end

	local buf = trap.FS_Read(len, f)
	trap.FS_FCloseFile(f)

	ui_numBots += U.UI_ParseInfos(buf, C.MAX_BOTS - ui_numBots, ui_botInfos, ui_numBots)
	if outOfMemory then
		trap.Print("^3WARNING: not anough memory in pool to load all bots\n")
	end
end

local function UI_LoadBots()
	ui_numBots = 0

	local botsFile = T.vmCvar_t()
	trap.Cvar_Register(botsFile, "g_botsFile", "", bit32.bor(C.CVAR_INIT, C.CVAR_ROM))
	if botsFile.string ~= "" then
		UI_LoadBotsFromFile(botsFile.string)
	else
		UI_LoadBotsFromFile("scripts/bots.txt")
	end

	-- get all bots from .bot files
	local numdirs, dirlist = trap.FS_GetFileList("scripts", ".bot")
	for i = 0, numdirs - 1 do
		UI_LoadBotsFromFile(Q.va("scripts/%s", dirlist[i]))
	end
	trap.Print(Q.va("%i bots parsed\n", ui_numBots))
end

function U.UI_GetBotInfoByNumber(num)
	if num < 0 or num >= ui_numBots then
		trap.Print(Q.va("^1Invalid bot number: %i\n", num))
		return nil
	end
	return ui_botInfos[num]
end

function U.UI_GetBotInfoByName(name)
	for n = 0, ui_numBots - 1 do
		local value = Q.Info_ValueForKey(ui_botInfos[n], "name")
		if Q.stricmp(value, name) == 0 then
			return ui_botInfos[n]
		end
	end

	return nil
end

--
-- single player game info
--

-- Returns the player's best finish on a given level, 0 if the have not played the level.
-- Returns score, skill.
function U.UI_GetBestScore(level, score, skill)
	if level < 0 or level > ui_numArenas then
		return 0, 0
	end

	local bestScore = 0
	local bestScoreSkill = 0

	for n = 1, 5 do
		local scores = trap.Cvar_VariableStringBuffer(Q.va("g_spScores%i", n))

		local arenaKey = Q.va("l%i", level)
		local skillScore = atoi(Q.Info_ValueForKey(scores, arenaKey))

		if skillScore >= 1 and skillScore <= 8 then
			if bestScore == 0 or skillScore <= bestScore then
				bestScore = skillScore
				bestScoreSkill = n
			end
		end
	end

	return bestScore, bestScoreSkill
end

-- Set the player's best finish for a level
function U.UI_SetBestScore(level, score)
	-- validate score
	if score < 1 or score > 8 then
		return
	end

	-- validate skill
	local skill = Q.int(trap.Cvar_VariableValue("g_spSkill"))
	if skill < 1 or skill > 5 then
		return
	end

	-- get scores
	local scores = trap.Cvar_VariableStringBuffer(Q.va("g_spScores%i", skill))

	-- see if this is better
	local arenaKey = Q.va("l%i", level)
	local oldScore = atoi(Q.Info_ValueForKey(scores, arenaKey))
	if oldScore ~= 0 and oldScore <= score then
		return
	end

	-- update scores
	scores = Q.Info_SetValueForKey(scores, arenaKey, Q.va("%i", score))
	trap.Cvar_Set(Q.va("g_spScores%i", skill), scores)
end

function U.UI_LogAwardData(award, data)
	if data == 0 then
		return
	end

	if award > C.AWARD_PERFECT then
		trap.Print(Q.va("^1Bad award %i in UI_LogAwardData\n", award))
		return
	end

	local awardData = trap.Cvar_VariableStringBuffer("g_spAwards")

	local key = Q.va("a%i", award)
	local oldValue = atoi(Q.Info_ValueForKey(awardData, key))

	awardData = Q.Info_SetValueForKey(awardData, key, Q.va("%i", oldValue + data))
	trap.Cvar_Set("g_spAwards", awardData)
end

function U.UI_GetAwardLevel(award)
	local awardData = trap.Cvar_VariableStringBuffer("g_spAwards")

	local key = Q.va("a%i", award)
	return atoi(Q.Info_ValueForKey(awardData, key))
end

function U.UI_TierCompleted(levelWon)
	local tier = Q.idiv(levelWon, C.ARENAS_PER_TIER)
	local level = tier * C.ARENAS_PER_TIER

	if tier == U.UI_GetNumSPTiers() then
		local info = U.UI_GetSpecialArenaInfo("training")
		if levelWon == atoi(Q.Info_ValueForKey(info, "num")) then
			return 0
		end
		info = U.UI_GetSpecialArenaInfo("final")
		if info == nil or levelWon == atoi(Q.Info_ValueForKey(info, "num")) then
			return tier + 1
		end
		return -1
	end

	for _ = 0, C.ARENAS_PER_TIER - 1 do
		local score = U.UI_GetBestScore(level)
		if score ~= 1 then
			return -1
		end
		level += 1
	end
	return tier + 1
end

function U.UI_ShowTierVideo(tier)
	if tier <= 0 then
		return false
	end

	local videos = trap.Cvar_VariableStringBuffer("g_spVideos")

	local key = Q.va("tier%i", tier)
	if atoi(Q.Info_ValueForKey(videos, key)) ~= 0 then
		return false
	end

	videos = Q.Info_SetValueForKey(videos, key, Q.va("%i", 1))
	trap.Cvar_Set("g_spVideos", videos)

	return true
end

function U.UI_CanShowTierVideo(tier)
	if tier == 0 then
		return false
	end

	if U.uis.demoversion and tier ~= 8 then
		return false
	end

	local videos = trap.Cvar_VariableStringBuffer("g_spVideos")

	local key = Q.va("tier%i", tier)
	if atoi(Q.Info_ValueForKey(videos, key)) ~= 0 then
		return true
	end

	return false
end

-- Returns the next level the player has not won
function U.UI_GetCurrentGame()
	local info = U.UI_GetSpecialArenaInfo("training")
	if info ~= nil then
		local level = atoi(Q.Info_ValueForKey(info, "num"))
		local rank = U.UI_GetBestScore(level)
		if rank == 0 or rank > 1 then
			return level
		end
	end

	for level = 0, ui_numSinglePlayerArenas - 1 do
		local rank = U.UI_GetBestScore(level)
		if rank == 0 or rank > 1 then
			return level
		end
	end

	info = U.UI_GetSpecialArenaInfo("final")
	if info == nil then
		return -1
	end
	return atoi(Q.Info_ValueForKey(info, "num"))
end

-- Clears the scores and sets the difficutly level
function U.UI_NewGame()
	trap.Cvar_Set("g_spScores1", "")
	trap.Cvar_Set("g_spScores2", "")
	trap.Cvar_Set("g_spScores3", "")
	trap.Cvar_Set("g_spScores4", "")
	trap.Cvar_Set("g_spScores5", "")
	trap.Cvar_Set("g_spAwards", "")
	trap.Cvar_Set("g_spVideos", "")
end

function U.UI_GetNumArenas()
	return ui_numArenas
end

function U.UI_GetNumSPArenas()
	return ui_numSinglePlayerArenas
end

function U.UI_GetNumSPTiers()
	return Q.idiv(ui_numSinglePlayerArenas, C.ARENAS_PER_TIER)
end

function U.UI_GetNumBots()
	return ui_numBots
end

function U.UI_SPUnlock_f()
	-- get scores for skill 1
	local scores = trap.Cvar_VariableStringBuffer("g_spScores1")

	-- update scores
	for level = 0, ui_numSinglePlayerArenas + ui_numSpecialSinglePlayerArenas - 1 do
		scores = Q.Info_SetValueForKey(scores, Q.va("l%i", level), "1")
	end
	trap.Cvar_Set("g_spScores1", scores)

	-- unlock cinematics
	for tier = 1, 8 do
		U.UI_ShowTierVideo(tier)
	end

	trap.Print("All levels unlocked at skill level 1\n")

	U.UI_SPLevelMenu_ReInit()
end

function U.UI_SPUnlockMedals_f()
	local awardData = trap.Cvar_VariableStringBuffer("g_spAwards")

	for n = 0, 5 do
		awardData = Q.Info_SetValueForKey(awardData, Q.va("a%i", n), "100")
	end

	trap.Cvar_Set("g_spAwards", awardData)

	trap.Print("All levels unlocked at 100\n")
end

function U.UI_InitGameinfo()
	U.UI_InitMemory()
	UI_LoadArenas()
	UI_LoadBots()

	U.uis.demoversion = false
end

return U
