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
-- Luau port of code/cgame/cg_info.c (OpenArena 0.8.8, gamecode 9e0f0c0).
-- cg_info.c -- display information while data is being loading

local G = require(script.Parent.G)
local C = require(script.Parent.Parent.q.Consts)
local Q = require(script.Parent.Parent.q.Q)
local trap = require(script.Parent.Parent.sys.Trap)
local BG = require(script.Parent.Parent.adapters.BG)

local MAX_LOADING_PLAYER_ICONS = 16
local MAX_LOADING_ITEM_ICONS = 26

local loadingPlayerIconCount = 0
local loadingItemIconCount = 0
local loadingPlayerIcons = {}
local loadingItemIcons = {}

local function atoi(s: string): number
	local m = string.match(s, "^%s*([+-]?%d+)")
	return tonumber(m) or 0
end

local function CG_DrawLoadingIcons()
	for n = 0, loadingPlayerIconCount - 1 do
		local x = 16 + n * 78
		local y = 324 - 40
		G.CG_DrawPic(x, y, 64, 64, loadingPlayerIcons[n])
	end

	for n = 0, loadingItemIconCount - 1 do
		local y = 400 - 40
		if n >= 13 then
			y += 40
		end
		local x = 16 + (n % 13) * 48
		G.CG_DrawPic(x, y, 32, 32, loadingItemIcons[n])
	end
end

function G.CG_LoadingString(s)
	G.cg.infoScreenText = string.sub(s, 1, 1023)

	trap.UpdateScreen()
end

function G.CG_LoadingItem(itemNum)
	local item = BG.bg_itemlist[itemNum]

	if item.icon ~= nil and item.icon ~= "" and loadingItemIconCount < MAX_LOADING_ITEM_ICONS then
		loadingItemIcons[loadingItemIconCount] = trap.R_RegisterShaderNoMip(item.icon)
		loadingItemIconCount += 1
	end

	G.CG_LoadingString(item.pickup_name)
end

function G.CG_LoadingClient(clientNum)
	local info = G.CG_ConfigString(C.CS_PLAYERS + clientNum)

	if loadingPlayerIconCount < MAX_LOADING_PLAYER_ICONS then
		local model = string.sub(Q.Info_ValueForKey(info, "model"), 1, 63)
		local skin
		local slash = nil
		for i = #model, 1, -1 do
			if string.byte(model, i) == 47 then
				slash = i
				break
			end
		end
		if slash ~= nil then
			skin = string.sub(model, slash + 1)
			model = string.sub(model, 1, slash - 1)
		else
			skin = "default"
		end

		local iconName = Q.va("models/players/%s/icon_%s.tga", model, skin)

		local idx = loadingPlayerIconCount
		loadingPlayerIcons[idx] = trap.R_RegisterShaderNoMip(iconName)
		if loadingPlayerIcons[idx] == 0 then
			iconName = Q.va("models/players/characters/%s/icon_%s.tga", model, skin)
			loadingPlayerIcons[idx] = trap.R_RegisterShaderNoMip(iconName)
		end
		if loadingPlayerIcons[idx] == 0 then
			iconName = Q.va("models/players/%s/icon_%s.tga", C.DEFAULT_MODEL, "default")
			loadingPlayerIcons[idx] = trap.R_RegisterShaderNoMip(iconName)
		end
		if loadingPlayerIcons[idx] ~= 0 then
			loadingPlayerIconCount += 1
		end
	end

	local personality = string.sub(Q.Info_ValueForKey(info, "n"), 1, 63)
	personality = Q.CleanStr(personality)

	if G.cgs.gametype == C.GT_SINGLE_PLAYER then
		trap.S_RegisterSound(Q.va("sound/player/announce/%s.wav", personality), true)
	end

	G.CG_LoadingString(personality)
end

--[[
Draw all the status / pacifier stuff during level loading
]]
function G.CG_DrawInformation()
	local cgs = G.cgs
	local flags = bit32.bor(C.UI_CENTER, C.UI_SMALLFONT, C.UI_DROPSHADOW)

	local info = G.CG_ConfigString(C.CS_SERVERINFO)
	local sysInfo = G.CG_ConfigString(C.CS_SYSTEMINFO)

	local s = Q.Info_ValueForKey(info, "mapname")
	local levelshot = trap.R_RegisterShaderNoMip(Q.va("levelshots/%s.tga", s))
	if levelshot == 0 then
		levelshot = trap.R_RegisterShaderNoMip("menu/art/unknownmap")
	end
	trap.R_SetColor(nil)
	G.CG_DrawPic(0, 0, C.SCREEN_WIDTH, C.SCREEN_HEIGHT, levelshot)

	-- blend a detail texture over it
	local detail = trap.R_RegisterShader("levelShotDetail")
	trap.R_DrawStretchPic(0, 0, cgs.glconfig.vidWidth, cgs.glconfig.vidHeight, 0, 0, 2.5, 2, detail)

	-- draw the icons of things as they are loaded
	CG_DrawLoadingIcons()

	-- the first 150 rows are reserved for the client connection
	-- screen to write into
	if G.cg.infoScreenText ~= "" then
		G.UI_DrawProportionalString(320, 128 - 32, Q.va("Loading... %s", G.cg.infoScreenText), flags, Q.colorWhite)
	else
		G.UI_DrawProportionalString(320, 128 - 32, "Awaiting snapshot...", flags, Q.colorWhite)
	end

	-- draw info string information

	local y = 180 - 32

	-- don't print server lines if playing a local game
	local buf = trap.Cvar_VariableStringBuffer("sv_running")
	if atoi(buf) == 0 then
		-- server hostname
		buf = string.sub(Q.Info_ValueForKey(info, "sv_hostname"), 1, 1023)
		buf = Q.CleanStr(buf)
		G.UI_DrawProportionalString(320, y, buf, flags, Q.colorWhite)
		y += C.PROP_HEIGHT

		-- pure server
		s = Q.Info_ValueForKey(sysInfo, "sv_pure")
		if string.sub(s, 1, 1) == "1" then
			G.UI_DrawProportionalString(320, y, "Pure Server", flags, Q.colorWhite)
			y += C.PROP_HEIGHT
		end

		-- server-specific message of the day
		s = G.CG_ConfigString(C.CS_MOTD)
		if s ~= "" then
			G.UI_DrawProportionalString(320, y, s, flags, Q.colorWhite)
			y += C.PROP_HEIGHT
		end

		-- some extra space after hostname and motd
		y += 10
	end

	-- map-specific message (long map name)
	s = G.CG_ConfigString(C.CS_MESSAGE)
	if s ~= "" then
		G.UI_DrawProportionalString(320, y, s, flags, Q.colorWhite)
		y += C.PROP_HEIGHT
	end

	-- cheats warning
	s = Q.Info_ValueForKey(sysInfo, "sv_cheats")
	if string.sub(s, 1, 1) == "1" then
		G.UI_DrawProportionalString(320, y, "CHEATS ARE ENABLED", flags, Q.colorWhite)
		y += C.PROP_HEIGHT
	end

	-- game type
	local gt = cgs.gametype
	if gt == C.GT_FFA then
		s = "Free For All"
	elseif gt == C.GT_SINGLE_PLAYER then
		s = "Single Player"
	elseif gt == C.GT_TOURNAMENT then
		s = "Tournament"
	elseif gt == C.GT_TEAM then
		s = "Team Deathmatch"
	elseif gt == C.GT_CTF then
		s = "Capture The Flag"
	elseif gt == C.GT_1FCTF then
		s = "One Flag CTF"
	elseif gt == C.GT_OBELISK then
		s = "Overload"
	elseif gt == C.GT_HARVESTER then
		s = "Harvester"
	elseif gt == C.GT_ELIMINATION then
		s = "Elimination"
	elseif gt == C.GT_CTF_ELIMINATION then
		s = " CTF Elimination"
	elseif gt == C.GT_LMS then
		s = "Last Man Standing"
	elseif gt == C.GT_DOUBLE_D then
		s = "Double Domination"
	elseif gt == C.GT_DOMINATION then
		s = "Domination"
	else
		s = "Unknown Gametype"
	end
	G.UI_DrawProportionalString(320, y, s, flags, Q.colorWhite)
	y += C.PROP_HEIGHT

	local value = atoi(Q.Info_ValueForKey(info, "timelimit"))
	if value ~= 0 then
		G.UI_DrawProportionalString(320, y, Q.va("timelimit %i", value), flags, Q.colorWhite)
		y += C.PROP_HEIGHT
	end

	if cgs.gametype < C.GT_CTF or cgs.ffa_gt > 0 then
		value = atoi(Q.Info_ValueForKey(info, "fraglimit"))
		if value ~= 0 then
			G.UI_DrawProportionalString(320, y, Q.va("fraglimit %i", value), flags, Q.colorWhite)
			y += C.PROP_HEIGHT
		end
	end

	if cgs.gametype >= C.GT_CTF and cgs.ffa_gt == 0 then
		value = atoi(Q.Info_ValueForKey(info, "capturelimit"))
		if value ~= 0 then
			G.UI_DrawProportionalString(320, y, Q.va("capturelimit %i", value), flags, Q.colorWhite)
			y += C.PROP_HEIGHT
		end
	end
end

return G
