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
-- Luau port of code/q3_ui/ui_connect.c (OpenArena 0.8.8, gamecode 9e0f0c0).

local U = require(script.Parent.U)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local bor = bit32.bor

--[[
===============================================================================

CONNECTION SCREEN

===============================================================================
]]

U.passwordNeeded = true
U.passwordField = nil

local lastConnState = 0
local lastLoadingText = ""

local function UI_ReadableSize(value: number): string
	local G = 1024 * 1024 * 1024
	local M = 1024 * 1024
	if value > G then -- gigs
		return Q.va("%d", Q.idiv(value, G)) .. Q.va(".%02d GB", Q.idiv(math.fmod(value, G) * 100, G))
	elseif value > M then -- megs
		return Q.va("%d", Q.idiv(value, M)) .. Q.va(".%02d MB", Q.idiv(math.fmod(value, M) * 100, M))
	elseif value > 1024 then -- kilos
		return Q.va("%d KB", Q.idiv(value, 1024))
	end
	return Q.va("%d bytes", value)
end

-- Assumes time is in msec
local function UI_PrintTime(time: number): string
	time = Q.idiv(time, 1000) -- change to seconds

	if time > 3600 then -- in the hours range
		return Q.va("%d hr %d min", Q.idiv(time, 3600), Q.idiv(math.fmod(time, 3600), 60))
	elseif time > 60 then -- mins
		return Q.va("%d min %d sec", Q.idiv(time, 60), math.fmod(time, 60))
	end
	return Q.va("%d sec", time)
end

local function UI_DisplayDownloadInfo(downloadName: string)
	local dlText = "Downloading:"
	local etaText = "Estimated time left:"
	local xferText = "Transfer rate:"

	local xferRate
	local style = bor(C.UI_LEFT, C.UI_SMALLFONT, C.UI_DROPSHADOW)
	local white = Q.colorWhite

	local downloadSize = Q.int(trap.Cvar_VariableValue("cl_downloadSize"))
	local downloadCount = Q.int(trap.Cvar_VariableValue("cl_downloadCount"))
	local downloadTime = Q.int(trap.Cvar_VariableValue("cl_downloadTime"))

	local scale = U.UI_ProportionalSizeScale(style)
	local leftWidth = U.UI_ProportionalStringWidth(dlText) * scale
	local width = U.UI_ProportionalStringWidth(etaText) * scale
	if width > leftWidth then
		leftWidth = width
	end
	width = U.UI_ProportionalStringWidth(xferText) * scale
	if width > leftWidth then
		leftWidth = width
	end
	leftWidth += 16

	U.UI_DrawProportionalString(8, 128, dlText, style, white)
	U.UI_DrawProportionalString(8, 160, etaText, style, white)
	U.UI_DrawProportionalString(8, 224, xferText, style, white)

	local s
	if downloadSize > 0 then
		s = Q.va("%s (%d%%)", downloadName, Q.int(downloadCount * 100.0 / downloadSize))
	else
		s = downloadName
	end

	U.UI_DrawProportionalString(leftWidth, 128, s, style, white)

	local dlSizeBuf = UI_ReadableSize(downloadCount)
	local totalSizeBuf = UI_ReadableSize(downloadSize)

	if downloadCount < 4096 or downloadTime == 0 then
		U.UI_DrawProportionalString(leftWidth, 160, "estimating", style, white)
		U.UI_DrawProportionalString(leftWidth, 192, Q.va("(%s of %s copied)", dlSizeBuf, totalSizeBuf), style, white)
	else
		if Q.idiv(U.uis.realtime - downloadTime, 1000) ~= 0 then
			xferRate = Q.idiv(downloadCount, Q.idiv(U.uis.realtime - downloadTime, 1000))
		else
			xferRate = 0
		end

		local xferRateBuf = UI_ReadableSize(xferRate)

		-- Extrapolate estimated completion time
		if downloadSize ~= 0 and xferRate ~= 0 then
			local n = Q.idiv(downloadSize, xferRate) -- estimated time for entire d/l in secs

			-- We do it in K (/1024) because we'd overflow around 4MB
			n = (n - Q.idiv(Q.idiv(downloadCount, 1024) * n, Q.idiv(downloadSize, 1024))) * 1000

			local dlTimeBuf = UI_PrintTime(n)

			U.UI_DrawProportionalString(leftWidth, 160, dlTimeBuf, style, white)
			U.UI_DrawProportionalString(leftWidth, 192, Q.va("(%s of %s copied)", dlSizeBuf, totalSizeBuf), style, white)
		else
			U.UI_DrawProportionalString(leftWidth, 160, "estimating", style, white)
			if downloadSize ~= 0 then
				U.UI_DrawProportionalString(leftWidth, 192, Q.va("(%s of %s copied)", dlSizeBuf, totalSizeBuf), style, white)
			else
				U.UI_DrawProportionalString(leftWidth, 192, Q.va("(%s copied)", dlSizeBuf), style, white)
			end
		end

		if xferRate ~= 0 then
			U.UI_DrawProportionalString(leftWidth, 224, Q.va("%s/Sec", xferRateBuf), style, white)
		end
	end
end

--[[
========================
UI_DrawConnectScreen

This will also be overlaid on the cgame info screen during loading
to prevent it from blinking away too rapidly on local or lan games.
========================
]]
function U.UI_DrawConnectScreen(overlay)
	local s

	U.Menu_Cache()

	if not overlay then
		-- draw the dialog background
		U.UI_SetColor(Q.colorWhite)
		U.UI_DrawBackground(U.uis.menuBackShader)
	end

	-- see what information we should display
	local cstate = T.uiClientState_t()
	trap.GetClientState(cstate)

	local info = trap.GetConfigString(C.CS_SERVERINFO)
	if info ~= "" then
		U.UI_DrawProportionalString(320, 16, Q.va("Loading %s", Q.Info_ValueForKey(info, "mapname")), bor(C.UI_BIGFONT, C.UI_CENTER, C.UI_DROPSHADOW), Q.colorWhite)
	end

	U.UI_DrawProportionalString(320, 64, Q.va("Connecting to %s", cstate.servername), bor(C.UI_CENTER, C.UI_SMALLFONT, C.UI_DROPSHADOW), U.menu_text_color)

	-- display global MOTD at bottom
	U.UI_DrawProportionalString(C.SCREEN_WIDTH // 2, C.SCREEN_HEIGHT - 32, Q.Info_ValueForKey(cstate.updateInfoString, "motd"), bor(C.UI_CENTER, C.UI_SMALLFONT, C.UI_DROPSHADOW), U.menu_text_color)

	-- print any server info (server full, bad version, etc)
	if cstate.connState < C.CA_CONNECTED then
		U.UI_DrawProportionalString_AutoWrapped(320, 192, 630, 20, cstate.messageString, bor(C.UI_CENTER, C.UI_SMALLFONT, C.UI_DROPSHADOW), U.menu_text_color)
	end

	if lastConnState > cstate.connState then
		lastLoadingText = ""
	end
	lastConnState = cstate.connState

	if cstate.connState == C.CA_CONNECTING then
		s = Q.va("Awaiting challenge...%i", cstate.connectPacketCount)
	elseif cstate.connState == C.CA_CHALLENGING then
		s = Q.va("Awaiting connection...%i", cstate.connectPacketCount)
	elseif cstate.connState == C.CA_CONNECTED then
		local downloadName = trap.Cvar_VariableStringBuffer("cl_downloadName")
		if downloadName ~= "" then
			UI_DisplayDownloadInfo(downloadName)
			return
		end
		s = "Awaiting gamestate..."
	else
		return
	end

	U.UI_DrawProportionalString(320, 128, s, bor(C.UI_CENTER, C.UI_SMALLFONT, C.UI_DROPSHADOW), Q.colorWhite)

	-- password required / connection rejected information goes here
end

function U.UI_KeyConnect(key)
	if key == C.K_ESCAPE then
		trap.Cmd_ExecuteText(C.EXEC_APPEND, "disconnect\n")
		return
	end
end

return U
