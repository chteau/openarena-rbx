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
-- Luau port of code/q3_ui/ui_sppostgame.c (OpenArena 0.8.8, gamecode 9e0f0c0).

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local MAX_SCOREBOARD_CLIENTS = 8
local AWARD_PRESENTATION_TIME = 2000

local ART_MENU0 = "menu/art_blueish/menu_0"
local ART_MENU1 = "menu/art_blueish/menu_1"
local ART_REPLAY0 = "menu/art_blueish/replay_0"
local ART_REPLAY1 = "menu/art_blueish/replay_1"
local ART_NEXT0 = "menu/art_blueish/next_0"
local ART_NEXT1 = "menu/art_blueish/next_1"

local ID_AGAIN = 10
local ID_NEXT = 11
local ID_MENU = 12

local function atoi(s: string): number
	local n = tonumber(s)
	if n == nil then
		return 0
	end
	return Q.int(n)
end

local function zeroArray(n: number, v: any)
	local a = {}
	for i = 0, n - 1 do
		a[i] = v
	end
	return a
end

local function newInfo()
	return {
		menu = T.menuframework_s(),
		item_again = T.menubitmap_s(),
		item_next = T.menubitmap_s(),
		item_menu = T.menubitmap_s(),
		phase = 0,
		ignoreKeysTime = 0,
		starttime = 0,
		scoreboardtime = 0,
		serverId = 0,
		clientNums = zeroArray(MAX_SCOREBOARD_CLIENTS, 0),
		ranks = zeroArray(MAX_SCOREBOARD_CLIENTS, 0),
		scores = zeroArray(MAX_SCOREBOARD_CLIENTS, 0),
		placeNames = zeroArray(3, ""),
		level = 0,
		numClients = 0,
		won = 0,
		numAwards = 0,
		awardsEarned = zeroArray(6, 0),
		awardsLevels = zeroArray(6, 0),
		playedSound = zeroArray(6, false),
		lastTier = 0,
		winnerSound = 0,
	}
end

local postgameMenuInfo = newInfo()
local arenainfo = ""

local ui_medalNames = { [0] = "Accuracy", "Impressive", "Excellent", "Gauntlet", "Frags", "Perfect" }
local ui_medalPicNames = {
	[0] = "menu/medals/medal_accuracy",
	"menu/medals/medal_impressive",
	"menu/medals/medal_excellent",
	"menu/medals/medal_gauntlet",
	"menu/medals/medal_frags",
	"menu/medals/medal_victory",
}
local ui_medalSounds = {
	[0] = "sound/feedback/accuracy.wav",
	"sound/feedback/impressive_a.wav",
	"sound/feedback/excellent_a.wav",
	"sound/feedback/gauntlet.wav",
	"sound/feedback/frags.wav",
	"sound/feedback/perfect.wav",
}
U.ui_medalNames = ui_medalNames
U.ui_medalPicNames = ui_medalPicNames
U.ui_medalSounds = ui_medalSounds

local function UI_SPPostgameMenu_AgainEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end
	U.UI_PopMenu()
	trap.Cmd_ExecuteText(C.EXEC_APPEND, "map_restart 0\n")
end

local function UI_SPPostgameMenu_NextEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end
	U.UI_PopMenu()

	local level
	-- handle specially if we just won the training map
	if postgameMenuInfo.won == 0 then
		level = 0
	else
		level = postgameMenuInfo.level + 1
	end
	local levelSet = Q.idiv(level, C.ARENAS_PER_TIER)

	local currentLevel = U.UI_GetCurrentGame()
	if currentLevel == -1 then
		currentLevel = postgameMenuInfo.level
	end
	local currentSet = Q.idiv(currentLevel, C.ARENAS_PER_TIER)

	if levelSet > currentSet or levelSet == U.UI_GetNumSPTiers() then
		level = currentLevel
	end

	local arenaInfo = U.UI_GetArenaInfoByNumber(level)
	if arenaInfo == nil then
		return
	end

	U.UI_SPArena_Start(arenaInfo)
end

local function UI_SPPostgameMenu_MenuEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end
	U.UI_PopMenu()
	trap.Cvar_Set("nextmap", "")
	trap.Cmd_ExecuteText(C.EXEC_APPEND, "disconnect; levelselect\n")
end

local function UI_SPPostgameMenu_MenuKey(key)
	if U.uis.realtime < postgameMenuInfo.ignoreKeysTime then
		return 0
	end

	if postgameMenuInfo.phase == 1 then
		trap.Cmd_ExecuteText(C.EXEC_APPEND, "abort_podium\n")
		postgameMenuInfo.phase = 2
		postgameMenuInfo.starttime = U.uis.realtime
		postgameMenuInfo.ignoreKeysTime = U.uis.realtime + 250
		return 0
	end

	if postgameMenuInfo.phase == 2 then
		postgameMenuInfo.phase = 3
		postgameMenuInfo.starttime = U.uis.realtime
		postgameMenuInfo.ignoreKeysTime = U.uis.realtime + 250
		return 0
	end

	if key == C.K_ESCAPE or key == C.K_MOUSE2 then
		return 0
	end

	return U.Menu_DefaultKey(postgameMenuInfo.menu, key)
end

local medalLocations = { [0] = 144, 448, 88, 504, 32, 560 }

local function UI_SPPostgameMenu_DrawAwardsMedals(max)
	for n = 0, max - 1 do
		local x = medalLocations[n]
		local y = 64
		local medal = postgameMenuInfo.awardsEarned[n]
		local amount = postgameMenuInfo.awardsLevels[n]

		U.UI_DrawNamedPic(x, y, 48, 48, ui_medalPicNames[medal])

		local buf
		if medal == C.AWARD_ACCURACY then
			buf = Q.va("%i%%", amount)
		else
			if amount == 1 then
				continue
			end
			buf = Q.va("%i", amount)
		end

		U.UI_DrawString(x + 24, y + 52, buf, C.UI_CENTER, U.color_yellow)
	end
end

local function UI_SPPostgameMenu_DrawAwardsPresentation(timer)
	local awardNum = Q.idiv(timer, AWARD_PRESENTATION_TIME)
	local atimer = timer % AWARD_PRESENTATION_TIME

	local color = Q.vec4(1.0, 1.0, 1.0, (AWARD_PRESENTATION_TIME - atimer) / AWARD_PRESENTATION_TIME)
	U.UI_DrawProportionalString(320, 64, ui_medalNames[postgameMenuInfo.awardsEarned[awardNum]], C.UI_CENTER, color)

	UI_SPPostgameMenu_DrawAwardsMedals(awardNum + 1)

	if not postgameMenuInfo.playedSound[awardNum] then
		postgameMenuInfo.playedSound[awardNum] = true
		trap.S_StartLocalSound(
			trap.S_RegisterSound(ui_medalSounds[postgameMenuInfo.awardsEarned[awardNum]], false),
			C.CHAN_ANNOUNCER
		)
	end
end

local function UI_SPPostgameMenu_MenuDrawScoreLine(n, y)
	if n > (postgameMenuInfo.numClients + 1) then
		n -= (postgameMenuInfo.numClients + 2)
	end

	if n >= postgameMenuInfo.numClients then
		return
	end

	local rank = postgameMenuInfo.ranks[n]
	if bit32.band(rank, C.RANK_TIED_FLAG) ~= 0 then
		U.UI_DrawString(640 - 31 * C.SMALLCHAR_WIDTH, y, "(tie)", bit32.bor(C.UI_LEFT, C.UI_SMALLFONT), U.color_white)
		rank = bit32.band(rank, bit32.bnot(C.RANK_TIED_FLAG))
	end
	local info = trap.GetConfigString(C.CS_PLAYERS + postgameMenuInfo.clientNums[n])
	local name = Q.CleanStr(string.sub(Q.Info_ValueForKey(info, "n"), 1, 63))

	U.UI_DrawString(
		640 - 25 * C.SMALLCHAR_WIDTH,
		y,
		Q.va("#%i: %-16s %2i", rank + 1, name, postgameMenuInfo.scores[n]),
		bit32.bor(C.UI_LEFT, C.UI_SMALLFONT),
		U.color_white
	)
end

local function UI_SPPostgameMenu_MenuDraw()
	local info = trap.GetConfigString(C.CS_SYSTEMINFO)
	local serverId = atoi(Q.Info_ValueForKey(info, "sv_serverid"))
	if serverId ~= postgameMenuInfo.serverId then
		U.UI_PopMenu()
		return
	end

	-- phase 1
	if postgameMenuInfo.numClients > 2 then
		U.UI_DrawProportionalString(510, 480 - 64 - C.PROP_HEIGHT, postgameMenuInfo.placeNames[2], C.UI_CENTER, U.color_white)
	end
	U.UI_DrawProportionalString(130, 480 - 64 - C.PROP_HEIGHT, postgameMenuInfo.placeNames[1], C.UI_CENTER, U.color_white)
	U.UI_DrawProportionalString(320, 480 - 64 - 2 * C.PROP_HEIGHT, postgameMenuInfo.placeNames[0], C.UI_CENTER, U.color_white)

	local timer
	if postgameMenuInfo.phase == 1 then
		timer = U.uis.realtime - postgameMenuInfo.starttime

		if timer >= 1000 and postgameMenuInfo.winnerSound ~= 0 then
			trap.S_StartLocalSound(postgameMenuInfo.winnerSound, C.CHAN_ANNOUNCER)
			postgameMenuInfo.winnerSound = 0
		end

		if timer < 5000 then
			return
		end
		postgameMenuInfo.phase = 2
		postgameMenuInfo.starttime = U.uis.realtime
	end

	-- phase 2
	if postgameMenuInfo.phase == 2 then
		timer = U.uis.realtime - postgameMenuInfo.starttime
		if timer >= (postgameMenuInfo.numAwards * AWARD_PRESENTATION_TIME) then
			if timer < 5000 then
				return
			end

			postgameMenuInfo.phase = 3
			postgameMenuInfo.starttime = U.uis.realtime
		else
			UI_SPPostgameMenu_DrawAwardsPresentation(timer)
		end
	end

	-- phase 3
	if postgameMenuInfo.phase == 3 then
		if U.uis.demoversion then
			if postgameMenuInfo.won == 1 and U.UI_ShowTierVideo(8) then
				trap.Cvar_Set("nextmap", "")
				trap.Cmd_ExecuteText(C.EXEC_APPEND, "disconnect; cinematic demoEnd.RoQ\n")
				return
			end
		elseif postgameMenuInfo.won > -1 and U.UI_ShowTierVideo(postgameMenuInfo.won + 1) then
			if postgameMenuInfo.won == postgameMenuInfo.lastTier then
				trap.Cvar_Set("nextmap", "")
				trap.Cmd_ExecuteText(C.EXEC_APPEND, "disconnect; cinematic end.RoQ\n")
				return
			end

			trap.Cvar_SetValue("ui_spSelection", postgameMenuInfo.won * C.ARENAS_PER_TIER)
			trap.Cvar_Set("nextmap", "levelselect")
			trap.Cmd_ExecuteText(C.EXEC_APPEND, Q.va("disconnect; cinematic tier%i.RoQ\n", postgameMenuInfo.won + 1))
			return
		end

		local nq = bit32.bnot(C.QMF_INACTIVE)
		postgameMenuInfo.item_again.generic.flags = bit32.band(postgameMenuInfo.item_again.generic.flags, nq)
		postgameMenuInfo.item_next.generic.flags = bit32.band(postgameMenuInfo.item_next.generic.flags, nq)
		postgameMenuInfo.item_menu.generic.flags = bit32.band(postgameMenuInfo.item_menu.generic.flags, nq)

		UI_SPPostgameMenu_DrawAwardsMedals(postgameMenuInfo.numAwards)

		U.Menu_Draw(postgameMenuInfo.menu)
	end

	-- draw the scoreboard
	if trap.Cvar_VariableValue("ui_spScoreboard") == 0 then
		return
	end

	timer = U.uis.realtime - postgameMenuInfo.scoreboardtime
	local n
	if postgameMenuInfo.numClients <= 3 then
		n = 0
	else
		n = Q.idiv(timer, 1500) % (postgameMenuInfo.numClients + 2)
	end
	UI_SPPostgameMenu_MenuDrawScoreLine(n, 0)
	UI_SPPostgameMenu_MenuDrawScoreLine(n + 1, 0 + C.SMALLCHAR_HEIGHT)
	UI_SPPostgameMenu_MenuDrawScoreLine(n + 2, 0 + 2 * C.SMALLCHAR_HEIGHT)
end

function U.UI_SPPostgameMenu_Cache()
	local buildscript = trap.Cvar_VariableValue("com_buildscript") ~= 0

	trap.R_RegisterShaderNoMip(ART_MENU0)
	trap.R_RegisterShaderNoMip(ART_MENU1)
	trap.R_RegisterShaderNoMip(ART_REPLAY0)
	trap.R_RegisterShaderNoMip(ART_REPLAY1)
	trap.R_RegisterShaderNoMip(ART_NEXT0)
	trap.R_RegisterShaderNoMip(ART_NEXT1)
	for n = 0, 5 do
		trap.R_RegisterShaderNoMip(ui_medalPicNames[n])
		trap.S_RegisterSound(ui_medalSounds[n], false)
	end

	if buildscript then
		trap.S_RegisterSound("music/loss.wav", false)
		trap.S_RegisterSound("music/win.wav", false)
		trap.S_RegisterSound("sound/player/announce/youwin.wav", false)
	end
end

local function UI_SPPostgameMenu_Init()
	postgameMenuInfo.menu.wrapAround = true
	postgameMenuInfo.menu.key = UI_SPPostgameMenu_MenuKey
	postgameMenuInfo.menu.draw = UI_SPPostgameMenu_MenuDraw
	postgameMenuInfo.ignoreKeysTime = U.uis.realtime + 1500

	U.UI_SPPostgameMenu_Cache()

	local m = postgameMenuInfo.item_menu
	m.generic.type = C.MTYPE_BITMAP
	m.generic.name = ART_MENU0
	m.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS, C.QMF_INACTIVE)
	m.generic.x = 0
	m.generic.y = 480 - 64
	m.generic.callback = UI_SPPostgameMenu_MenuEvent
	m.generic.id = ID_MENU
	m.width = 128
	m.height = 64
	m.focuspic = ART_MENU1

	local a = postgameMenuInfo.item_again
	a.generic.type = C.MTYPE_BITMAP
	a.generic.name = ART_REPLAY0
	a.generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_PULSEIFFOCUS, C.QMF_INACTIVE)
	a.generic.x = 320
	a.generic.y = 480 - 64
	a.generic.callback = UI_SPPostgameMenu_AgainEvent
	a.generic.id = ID_AGAIN
	a.width = 128
	a.height = 64
	a.focuspic = ART_REPLAY1

	local nx = postgameMenuInfo.item_next
	nx.generic.type = C.MTYPE_BITMAP
	nx.generic.name = ART_NEXT0
	nx.generic.flags = bit32.bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS, C.QMF_INACTIVE)
	nx.generic.x = 640
	nx.generic.y = 480 - 64
	nx.generic.callback = UI_SPPostgameMenu_NextEvent
	nx.generic.id = ID_NEXT
	nx.width = 128
	nx.height = 64
	nx.focuspic = ART_NEXT1

	U.Menu_AddItem(postgameMenuInfo.menu, postgameMenuInfo.item_menu)
	U.Menu_AddItem(postgameMenuInfo.menu, postgameMenuInfo.item_again)
	U.Menu_AddItem(postgameMenuInfo.menu, postgameMenuInfo.item_next)
end

local function Prepname(index)
	local info = trap.GetConfigString(C.CS_PLAYERS + postgameMenuInfo.clientNums[index])
	local name = Q.CleanStr(string.sub(Q.Info_ValueForKey(info, "n"), 1, 63))
	local len = #name

	while len ~= 0 and U.UI_ProportionalStringWidth(name) > 256 do
		len -= 1
		name = string.sub(name, 1, len)
	end

	postgameMenuInfo.placeNames[index] = string.sub(name, 1, 63)
end

function U.UI_SPPostgameMenu_f()
	local awardValues = {}

	postgameMenuInfo = newInfo()

	local info = trap.GetConfigString(C.CS_SYSTEMINFO)
	postgameMenuInfo.serverId = atoi(Q.Info_ValueForKey(info, "sv_serverid"))

	info = trap.GetConfigString(C.CS_SERVERINFO)
	local map = string.sub(Q.Info_ValueForKey(info, "mapname"), 1, C.MAX_QPATH - 1)
	local arena = U.UI_GetArenaInfoByMap(map)
	if arena == nil then
		return
	end
	arenainfo = arena

	postgameMenuInfo.level = atoi(Q.Info_ValueForKey(arenainfo, "num"))

	postgameMenuInfo.numClients = atoi(U.UI_Argv(1))
	local playerClientNum = atoi(U.UI_Argv(2))
	local playerGameRank = 8 -- in case they ended game as a spectator

	if postgameMenuInfo.numClients > MAX_SCOREBOARD_CLIENTS then
		postgameMenuInfo.numClients = MAX_SCOREBOARD_CLIENTS
	end

	for n = 0, postgameMenuInfo.numClients - 1 do
		postgameMenuInfo.clientNums[n] = atoi(U.UI_Argv(8 + n * 3 + 1))
		postgameMenuInfo.ranks[n] = atoi(U.UI_Argv(8 + n * 3 + 2))
		postgameMenuInfo.scores[n] = atoi(U.UI_Argv(8 + n * 3 + 3))

		if postgameMenuInfo.clientNums[n] == playerClientNum then
			playerGameRank = bit32.band(postgameMenuInfo.ranks[n], bit32.bnot(C.RANK_TIED_FLAG)) + 1
		end
	end

	U.UI_SetBestScore(postgameMenuInfo.level, playerGameRank)

	-- process award stats and prepare presentation data
	awardValues[C.AWARD_ACCURACY] = atoi(U.UI_Argv(3))
	awardValues[C.AWARD_IMPRESSIVE] = atoi(U.UI_Argv(4))
	awardValues[C.AWARD_EXCELLENT] = atoi(U.UI_Argv(5))
	awardValues[C.AWARD_GAUNTLET] = atoi(U.UI_Argv(6))
	awardValues[C.AWARD_FRAGS] = atoi(U.UI_Argv(7))
	awardValues[C.AWARD_PERFECT] = atoi(U.UI_Argv(8))

	postgameMenuInfo.numAwards = 0

	local function addAward(award, level)
		postgameMenuInfo.awardsEarned[postgameMenuInfo.numAwards] = award
		postgameMenuInfo.awardsLevels[postgameMenuInfo.numAwards] = level
		postgameMenuInfo.numAwards += 1
	end

	if awardValues[C.AWARD_ACCURACY] >= 50 then
		U.UI_LogAwardData(C.AWARD_ACCURACY, 1)
		addAward(C.AWARD_ACCURACY, awardValues[C.AWARD_ACCURACY])
	end

	if awardValues[C.AWARD_IMPRESSIVE] ~= 0 then
		U.UI_LogAwardData(C.AWARD_IMPRESSIVE, awardValues[C.AWARD_IMPRESSIVE])
		addAward(C.AWARD_IMPRESSIVE, awardValues[C.AWARD_IMPRESSIVE])
	end

	if awardValues[C.AWARD_EXCELLENT] ~= 0 then
		U.UI_LogAwardData(C.AWARD_EXCELLENT, awardValues[C.AWARD_EXCELLENT])
		addAward(C.AWARD_EXCELLENT, awardValues[C.AWARD_EXCELLENT])
	end

	if awardValues[C.AWARD_GAUNTLET] ~= 0 then
		U.UI_LogAwardData(C.AWARD_GAUNTLET, awardValues[C.AWARD_GAUNTLET])
		addAward(C.AWARD_GAUNTLET, awardValues[C.AWARD_GAUNTLET])
	end

	local oldFrags = Q.idiv(U.UI_GetAwardLevel(C.AWARD_FRAGS), 100)
	U.UI_LogAwardData(C.AWARD_FRAGS, awardValues[C.AWARD_FRAGS])
	local newFrags = Q.idiv(U.UI_GetAwardLevel(C.AWARD_FRAGS), 100)
	if newFrags > oldFrags then
		addAward(C.AWARD_FRAGS, newFrags * 100)
	end

	if awardValues[C.AWARD_PERFECT] ~= 0 then
		U.UI_LogAwardData(C.AWARD_PERFECT, 1)
		addAward(C.AWARD_PERFECT, 1)
	end

	if playerGameRank == 1 then
		postgameMenuInfo.won = U.UI_TierCompleted(postgameMenuInfo.level)
	else
		postgameMenuInfo.won = -1
	end

	postgameMenuInfo.starttime = U.uis.realtime
	postgameMenuInfo.scoreboardtime = U.uis.realtime

	trap.Key_SetCatcher(C.KEYCATCH_UI)
	U.uis.menusp = 0

	UI_SPPostgameMenu_Init()
	U.UI_PushMenu(postgameMenuInfo.menu)

	if playerGameRank == 1 then
		U.Menu_SetCursorToItem(postgameMenuInfo.menu, postgameMenuInfo.item_next)
	else
		U.Menu_SetCursorToItem(postgameMenuInfo.menu, postgameMenuInfo.item_again)
	end

	Prepname(0)
	Prepname(1)
	Prepname(2)

	if playerGameRank ~= 1 then
		postgameMenuInfo.winnerSound =
			trap.S_RegisterSound(Q.va("sound/player/announce/%s_wins.wav", postgameMenuInfo.placeNames[0]), false)
		trap.Cmd_ExecuteText(C.EXEC_APPEND, "music music/loss\n")
	else
		postgameMenuInfo.winnerSound = trap.S_RegisterSound("sound/player/announce/youwin.wav", false)
		trap.Cmd_ExecuteText(C.EXEC_APPEND, "music music/win\n")
	end

	postgameMenuInfo.phase = 1

	postgameMenuInfo.lastTier = U.UI_GetNumSPTiers()
	if U.UI_GetSpecialArenaInfo("final") ~= nil then
		postgameMenuInfo.lastTier += 1
	end
end

return U
