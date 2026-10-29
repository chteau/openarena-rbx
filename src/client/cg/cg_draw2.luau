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
along with Foobar; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
]]
-- Luau port of code/cgame/cg_draw.c (OpenArena gamecode).
-- This part covers cg_draw.c lines 1660-2768.

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local trap = require(script.Parent.Parent.sys.Trap)
local BG = require(script.Parent.Parent.adapters.BG)

local INT_MAX = 2147483647
local LAG_SAMPLES = 128
local MAX_LAGOMETER_PING = 900
local MAX_LAGOMETER_RANGE = 300
local CHATLOC_Y = 420
local CHATLOC_X = 0

local function c4(r, g, b, a)
	return { [0] = r, [1] = g, [2] = b, [3] = a }
end

function G.CG_DrawUpperRight(stereoFrame)
	local cgs = G.cgs
	local cg = G.cg
	local y = 0

	if cgs.gametype >= C.GT_TEAM and cgs.ffa_gt ~= 1 and G.cg_drawTeamOverlay.integer == 1 then
		y = G.CG_DrawTeamOverlay(y, true, true)
	end
	if cgs.gametype == C.GT_LMS and cg.showScores then
		y = G.CG_DrawLMSmode(y)
	elseif cgs.gametype == C.GT_CTF_ELIMINATION then
		y = G.CG_DrawCTFoneway(y)
	elseif cgs.gametype == C.GT_DOMINATION then
		y = G.CG_DrawDomStatus(y)
	elseif cgs.gametype == C.GT_POSSESSION then
		y = G.CG_DrawPossessionString(y)
	end

	if G.cg_drawSnapshot.integer ~= 0 then
		y = G.CG_DrawSnapshot(y)
	end
	if G.cg_drawFPS.integer ~= 0 and (stereoFrame == C.STEREO_CENTER or stereoFrame == C.STEREO_RIGHT) then
		y = G.CG_DrawFPS(y)
	end
	if cgs.gametype == C.GT_ELIMINATION or cgs.gametype == C.GT_CTF_ELIMINATION or cgs.gametype == C.GT_LMS then
		y = G.CG_DrawCountdownTimer(y)
	end

	y = G.CG_DrawFollowMessage(y)

	if G.cg_drawTimer.integer ~= 0 then
		y = G.CG_DrawTimer(y)
	end
	if G.cg_drawAttacker.integer ~= 0 then
		y = G.CG_DrawAttacker(y)
	end
	if G.cg_drawSpeed.integer ~= 0 then
		y = G.CG_DrawSpeedMeter(y)
	end
end

--[[
=================
CG_DrawScores

Draw the small two score display
=================
]]
function G.CG_DrawScores(y)
	local cgs = G.cgs
	local cg = G.cg
	local statusA = cgs.redflag
	local statusB = cgs.blueflag
	local s1 = cgs.scores1
	local s2 = cgs.scores2
	local s, w, x, v
	local color

	y -= C.BIGCHAR_HEIGHT + 8

	local y1 = y

	if cgs.gametype >= C.GT_TEAM and cgs.ffa_gt ~= 1 then
		x = 640
		color = c4(0.0, 0.0, 1.0, 0.33)
		s = Q.va("%2i", s2)
		w = G.CG_DrawStrlen(s) * C.BIGCHAR_WIDTH + 8
		x -= w
		G.CG_FillRect(x, y - 4, w, C.BIGCHAR_HEIGHT + 8, color)
		if cg.snap.ps.persistant[C.PERS_TEAM] == C.TEAM_BLUE then
			G.CG_DrawPic(x, y - 4, w, C.BIGCHAR_HEIGHT + 8, cgs.media.selectShader)
		end
		G.CG_DrawBigString(x + 4, y, s, 1.0)

		if cgs.gametype == C.GT_CTF or cgs.gametype == C.GT_CTF_ELIMINATION then
			local item = BG.BG_FindItemForPowerup(C.PW_BLUEFLAG)
			if item ~= nil then
				y1 = y - C.BIGCHAR_HEIGHT - 8
				if cgs.blueflag >= 0 and cgs.blueflag <= 2 then
					G.CG_DrawPic(x, y1 - 4, w, C.BIGCHAR_HEIGHT + 8, cgs.media.blueFlagShader[cgs.blueflag])
				end
			end
		end

		if cgs.gametype == C.GT_DOUBLE_D then
			y1 = y - 32
			if cgs.redflag >= 0 and cgs.redflag <= 3 then
				G.CG_DrawPic(x, y1 - 4, w, 32, cgs.media.ddPointSkinB[cgs.blueflag])
			end
		end

		color = c4(1.0, 0.0, 0.0, 0.33)
		s = Q.va("%2i", s1)
		w = G.CG_DrawStrlen(s) * C.BIGCHAR_WIDTH + 8
		x -= w
		G.CG_FillRect(x, y - 4, w, C.BIGCHAR_HEIGHT + 8, color)
		if cg.snap.ps.persistant[C.PERS_TEAM] == C.TEAM_RED then
			G.CG_DrawPic(x, y - 4, w, C.BIGCHAR_HEIGHT + 8, cgs.media.selectShader)
		end
		G.CG_DrawBigString(x + 4, y, s, 1.0)

		if cgs.gametype == C.GT_CTF or cgs.gametype == C.GT_CTF_ELIMINATION then
			local item = BG.BG_FindItemForPowerup(C.PW_REDFLAG)
			if item ~= nil then
				y1 = y - C.BIGCHAR_HEIGHT - 8
				if cgs.redflag >= 0 and cgs.redflag <= 2 then
					G.CG_DrawPic(x, y1 - 4, w, C.BIGCHAR_HEIGHT + 8, cgs.media.redFlagShader[cgs.redflag])
				end
			end
		end

		if cgs.gametype == C.GT_DOUBLE_D then
			y1 = y - 32
			if cgs.redflag >= 0 and cgs.redflag <= 3 then
				G.CG_DrawPic(x, y1 - 4, w, 32, cgs.media.ddPointSkinA[cgs.redflag])
			end

			--Time till capture:
			if (statusB == statusA and statusA == C.TEAM_RED) or (statusB == statusA and statusA == C.TEAM_BLUE) then
				s = Q.va("%i", Q.idiv(cgs.takeAt - cg.time, 1000) + 1)
				w = G.CG_DrawStrlen(s) * C.BIGCHAR_WIDTH
				G.CG_DrawBigString(x + 32 + 8 - Q.idiv(w, 2), y - 28, s, 1.0)
			end
		end

		if cgs.gametype == C.GT_OBELISK then
			s = Q.va("^1%3i%% ^4%3i%%", cg.redObeliskHealth, cg.blueObeliskHealth)
			G.CG_DrawSmallString(x, y - 28, s, 1.0)
		end

		if cgs.gametype >= C.GT_CTF and cgs.ffa_gt == 0 then
			v = cgs.capturelimit
		else
			v = cgs.fraglimit
		end
		if v ~= 0 then
			s = Q.va("%2i", v)
			w = G.CG_DrawStrlen(s) * C.BIGCHAR_WIDTH + 8
			x -= w
			G.CG_DrawBigString(x + 4, y, s, 1.0)
		end
	else
		x = 640
		local score = cg.snap.ps.persistant[C.PERS_SCORE]
		local spectator = cg.snap.ps.persistant[C.PERS_TEAM] == C.TEAM_SPECTATOR

		-- always show your score in the second box if not in first place
		if s1 ~= score then
			s2 = score
		end
		if s2 ~= C.SCORE_NOT_PRESENT then
			s = Q.va("%2i", s2)
			w = G.CG_DrawStrlen(s) * C.BIGCHAR_WIDTH + 8
			x -= w
			if not spectator and score == s2 and score ~= s1 then
				color = c4(1.0, 0.0, 0.0, 0.33)
				G.CG_FillRect(x, y - 4, w, C.BIGCHAR_HEIGHT + 8, color)
				G.CG_DrawPic(x, y - 4, w, C.BIGCHAR_HEIGHT + 8, cgs.media.selectShader)
			else
				color = c4(0.5, 0.5, 0.5, 0.33)
				G.CG_FillRect(x, y - 4, w, C.BIGCHAR_HEIGHT + 8, color)
			end
			G.CG_DrawBigString(x + 4, y, s, 1.0)
		end

		-- first place
		if s1 ~= C.SCORE_NOT_PRESENT then
			s = Q.va("%2i", s1)
			w = G.CG_DrawStrlen(s) * C.BIGCHAR_WIDTH + 8
			x -= w
			if not spectator and score == s1 then
				color = c4(0.0, 0.0, 1.0, 0.33)
				G.CG_FillRect(x, y - 4, w, C.BIGCHAR_HEIGHT + 8, color)
				G.CG_DrawPic(x, y - 4, w, C.BIGCHAR_HEIGHT + 8, cgs.media.selectShader)
			else
				color = c4(0.5, 0.5, 0.5, 0.33)
				G.CG_FillRect(x, y - 4, w, C.BIGCHAR_HEIGHT + 8, color)
			end
			G.CG_DrawBigString(x + 4, y, s, 1.0)
		end

		if cgs.fraglimit ~= 0 then
			s = Q.va("%2i", cgs.fraglimit)
			w = G.CG_DrawStrlen(s) * C.BIGCHAR_WIDTH + 8
			x -= w
			G.CG_DrawBigString(x + 4, y, s, 1.0)
		end
	end

	return y1 - 8
end

local powerupColors = {
	[0] = c4(0.2, 1.0, 0.2, 1.0),
	[1] = c4(1.0, 0.2, 0.2, 1.0),
}

function G.CG_DrawPowerups(y)
	local cg = G.cg
	local sorted = {}
	local sortedTime = {}
	local ps = cg.snap.ps

	if ps.stats[C.STAT_HEALTH] <= 0 then
		return y
	end

	-- sort the list by time remaining
	local active = 0
	for i = 0, C.MAX_POWERUPS - 1 do
		local pw = ps.powerups[i]
		if pw == 0 then
			continue
		end
		-- don't draw if the power up has unlimited time (CTF flags)
		if pw == INT_MAX then
			continue
		end

		local t = pw - cg.time
		if t <= 0 then
			continue
		end

		local item = BG.BG_FindItemForPowerup(i)
		if item ~= nil and item.giType == C.IT_PERSISTANT_POWERUP then
			continue
		end

		-- insert into the list
		local j = 0
		while j < active do
			if sortedTime[j] >= t then
				for k = active - 1, j, -1 do
					sorted[k + 1] = sorted[k]
					sortedTime[k + 1] = sortedTime[k]
				end
				break
			end
			j += 1
		end
		sorted[j] = i
		sortedTime[j] = t
		active += 1
	end

	-- draw the icons and timers
	local x = 640 - C.ICON_SIZE - C.CHAR_WIDTH * 2
	for i = 0, active - 1 do
		local item = BG.BG_FindItemForPowerup(sorted[i])

		if item ~= nil then
			y -= C.ICON_SIZE

			trap.R_SetColor(powerupColors[1])
			G.CG_DrawField(x, y, 2, Q.idiv(sortedTime[i], 1000))

			local t = ps.powerups[sorted[i]]
			if t - cg.time >= C.POWERUP_BLINKS * C.POWERUP_BLINK_TIME then
				trap.R_SetColor(nil)
			else
				local f = (t - cg.time) / C.POWERUP_BLINK_TIME
				f -= Q.int(f)
				trap.R_SetColor(c4(f, f, f, f))
			end

			local size
			if cg.powerupActive == sorted[i] and cg.time - cg.powerupTime < C.PULSE_TIME then
				local f = 1.0 - ((cg.time - cg.powerupTime) / C.PULSE_TIME)
				size = C.ICON_SIZE * (1.0 + (C.PULSE_SCALE - 1.0) * f)
			else
				size = C.ICON_SIZE
			end

			G.CG_DrawPic(640 - size, y + C.ICON_SIZE / 2 - size / 2, size, size, trap.R_RegisterShader(item.icon))
		end
	end
	trap.R_SetColor(nil)

	return y
end

function G.CG_DrawLowerRight()
	local y = 472 - C.ICON_SIZE

	if G.cgs.gametype >= C.GT_TEAM and G.cgs.ffa_gt ~= 1 and G.cg_drawTeamOverlay.integer == 2 then
		y = G.CG_DrawTeamOverlay(y, true, false)
	end

	y = G.CG_DrawScores(y)
	y = G.CG_DrawPowerups(y)
end

function G.CG_DrawPickupItem(y)
	local cg = G.cg

	if cg.snap.ps.stats[C.STAT_HEALTH] <= 0 then
		return y
	end

	y -= C.ICON_SIZE

	local value = cg.itemPickup
	if value ~= 0 then
		local fadeColor = G.CG_FadeColor(cg.itemPickupTime, 3000)
		if fadeColor ~= nil then
			G.CG_RegisterItemVisuals(value)
			trap.R_SetColor(fadeColor)
			G.CG_DrawPic(8, y, C.ICON_SIZE, C.ICON_SIZE, G.cg_items[value].icon)
			G.CG_DrawBigString(
				C.ICON_SIZE + 16,
				y + (Q.idiv(C.ICON_SIZE, 2) - Q.idiv(C.BIGCHAR_HEIGHT, 2)),
				BG.bg_itemlist[value].pickup_name,
				fadeColor[0]
			)
			trap.R_SetColor(nil)
		end
	end

	return y
end

function G.CG_DrawLowerLeft()
	local y = 480 - C.ICON_SIZE

	if G.cgs.gametype >= C.GT_TEAM and G.cgs.ffa_gt ~= 1 and G.cg_drawTeamOverlay.integer == 3 then
		y = G.CG_DrawTeamOverlay(y, false, false)
	end

	y = G.CG_DrawPickupItem(y)
end

function G.CG_DrawTeamInfo()
	local cgs = G.cgs
	local cg = G.cg
	local chatHeight

	if G.cg_teamChatHeight.integer < C.TEAMCHAT_HEIGHT then
		chatHeight = G.cg_teamChatHeight.integer
	else
		chatHeight = C.TEAMCHAT_HEIGHT
	end
	if chatHeight <= 0 then
		return -- disabled
	end

	if cgs.teamLastChatPos ~= cgs.teamChatPos then
		if cg.time - cgs.teamChatMsgTimes[cgs.teamLastChatPos % chatHeight] > G.cg_teamChatTime.integer then
			cgs.teamLastChatPos += 1
		end

		local h = (cgs.teamChatPos - cgs.teamLastChatPos) * C.TINYCHAR_HEIGHT

		local w = 0
		for i = cgs.teamLastChatPos, cgs.teamChatPos - 1 do
			local len = G.CG_DrawStrlen(cgs.teamChatMsgs[i % chatHeight])
			if len > w then
				w = len
			end
		end
		w *= C.TINYCHAR_WIDTH
		w += C.TINYCHAR_WIDTH * 2

		local hcolor
		local team = cgs.clientinfo[cg.clientNum].team
		if team == C.TEAM_RED then
			hcolor = c4(1.0, 0.0, 0.0, 0.33)
		elseif team == C.TEAM_BLUE then
			hcolor = c4(0.0, 0.0, 1.0, 0.33)
		else
			hcolor = c4(0.0, 1.0, 0.0, 0.33)
		end

		trap.R_SetColor(hcolor)
		G.CG_DrawPic(CHATLOC_X, CHATLOC_Y - h, 640, h, cgs.media.teamStatusBar)
		trap.R_SetColor(nil)

		hcolor[0] = 1.0
		hcolor[1] = 1.0
		hcolor[2] = 1.0
		hcolor[3] = 1.0

		for i = cgs.teamChatPos - 1, cgs.teamLastChatPos, -1 do
			G.CG_DrawStringExt(
				CHATLOC_X + C.TINYCHAR_WIDTH,
				CHATLOC_Y - (cgs.teamChatPos - i) * C.TINYCHAR_HEIGHT,
				cgs.teamChatMsgs[i % chatHeight],
				hcolor,
				false,
				false,
				C.TINYCHAR_WIDTH,
				C.TINYCHAR_HEIGHT,
				0
			)
		end
	end
end

function G.CG_DrawHoldableItem()
	local value = G.cg.snap.ps.stats[C.STAT_HOLDABLE_ITEM]
	if value ~= 0 then
		G.CG_RegisterItemVisuals(value)
		G.CG_DrawPic(640 - C.ICON_SIZE, Q.idiv(C.SCREEN_HEIGHT - C.ICON_SIZE, 2), C.ICON_SIZE, C.ICON_SIZE, G.cg_items[value].icon)
	end
end

function G.CG_DrawPersistantPowerup()
	local value = G.cg.snap.ps.stats[C.STAT_PERSISTANT_POWERUP]
	if value ~= 0 then
		G.CG_RegisterItemVisuals(value)
		G.CG_DrawPic(
			640 - C.ICON_SIZE,
			Q.idiv(C.SCREEN_HEIGHT - C.ICON_SIZE, 2) - C.ICON_SIZE,
			C.ICON_SIZE,
			C.ICON_SIZE,
			G.cg_items[value].icon
		)
	end
end

function G.CG_DrawReward()
	local cg = G.cg

	if G.cg_drawRewards.integer == 0 then
		return
	end

	local color = G.CG_FadeColor(cg.rewardTime, C.REWARD_TIME)
	if color == nil then
		if cg.rewardStack > 0 then
			for i = 0, cg.rewardStack - 1 do
				cg.rewardSound[i] = cg.rewardSound[i + 1] or 0
				cg.rewardShader[i] = cg.rewardShader[i + 1] or 0
				cg.rewardCount[i] = cg.rewardCount[i + 1] or 0
			end
			cg.rewardTime = cg.time
			cg.rewardStack -= 1
			color = G.CG_FadeColor(cg.rewardTime, C.REWARD_TIME)

			trap.S_StartLocalSound(cg.rewardSound[0], C.CHAN_ANNOUNCER)
		else
			return
		end
	end

	trap.R_SetColor(color)

	if cg.rewardCount[0] >= 10 then
		local y = 56
		local x = 320 - Q.idiv(C.ICON_SIZE, 2)
		G.CG_DrawPic(x, y, C.ICON_SIZE - 4, C.ICON_SIZE - 4, cg.rewardShader[0])
		local buf = Q.va("%d", cg.rewardCount[0])
		x = Q.idiv(C.SCREEN_WIDTH - C.SMALLCHAR_WIDTH * G.CG_DrawStrlen(buf), 2)
		G.CG_DrawStringExt(x, y + C.ICON_SIZE, buf, color, false, true, C.SMALLCHAR_WIDTH, C.SMALLCHAR_HEIGHT, 0)
	else
		local count = cg.rewardCount[0]

		local y = 56
		local x = 320 - Q.idiv(count * C.ICON_SIZE, 2)
		for _ = 0, count - 1 do
			G.CG_DrawPic(x, y, C.ICON_SIZE - 4, C.ICON_SIZE - 4, cg.rewardShader[0])
			x += C.ICON_SIZE
		end
	end
	trap.R_SetColor(nil)
end

--[[
===============================================================================

LAGOMETER

===============================================================================
]]

local function newLagometer()
	local lm = { frameSamples = {}, frameCount = 0, snapshotFlags = {}, snapshotSamples = {}, snapshotCount = 0 }
	for i = 0, LAG_SAMPLES - 1 do
		lm.frameSamples[i] = 0
		lm.snapshotFlags[i] = 0
		lm.snapshotSamples[i] = 0
	end
	return lm
end

G.lagometer = newLagometer()

-- Adds the current interpolate / extrapolate bar for this frame
function G.CG_AddLagometerFrameInfo()
	local lagometer = G.lagometer
	local offset = G.cg.time - G.cg.latestSnapshotTime
	lagometer.frameSamples[bit32.band(lagometer.frameCount, LAG_SAMPLES - 1)] = offset
	lagometer.frameCount += 1
end

--[[
Each time a snapshot is received, log its ping time and
the number of snapshots that were dropped before it.

Pass nil for a dropped packet.
]]
function G.CG_AddLagometerSnapshotInfo(snap)
	local lagometer = G.lagometer
	-- dropped packet
	if snap == nil then
		lagometer.snapshotSamples[bit32.band(lagometer.snapshotCount, LAG_SAMPLES - 1)] = -1
		lagometer.snapshotCount += 1
		return
	end

	-- add this snapshot's info
	local idx = bit32.band(lagometer.snapshotCount, LAG_SAMPLES - 1)
	lagometer.snapshotSamples[idx] = snap.ping
	lagometer.snapshotFlags[idx] = snap.snapFlags
	lagometer.snapshotCount += 1
end

function G.CG_DrawDisconnect()
	local cg = G.cg

	-- draw the phone jack if we are completely past our buffers
	local cmdNum = trap.GetCurrentCmdNumber() - C.CMD_BACKUP + 1
	local cmd = T.usercmd_t()
	trap.GetUserCmd(cmdNum, cmd)
	if cmd.serverTime <= cg.snap.ps.commandTime or cmd.serverTime > cg.time then -- special check for map_restart
		return
	end

	-- also add text in center of screen
	local s = "Connection Interrupted"
	local w = G.CG_DrawStrlen(s) * C.BIGCHAR_WIDTH
	G.CG_DrawBigString(320 - Q.idiv(w, 2), 100, s, 1.0)

	-- blink the icon
	if bit32.band(bit32.rshift(cg.time, 9), 1) ~= 0 then
		return
	end

	local x = 640 - 48
	local y = 480 - 48

	G.CG_DrawPic(x, y, 48, 48, trap.R_RegisterShader("gfx/2d/net.tga"))
end

function G.CG_DrawLagometer()
	local lagometer = G.lagometer
	local media = G.cgs.media

	if G.cg_lagometer.integer == 0 or G.cgs.localServer then
		G.CG_DrawDisconnect()
		return
	end

	--
	-- draw the graph
	--
	local x = 640 - 48
	local y = 480 - 48

	trap.R_SetColor(nil)
	G.CG_DrawPic(x, y, 48, 48, media.lagometerShader)

	local ax, ay, aw, ah = G.CG_AdjustFrom640(x, y, 48, 48)

	local color = -1
	local range = ah / 3
	local mid = ay + range

	local vscale = range / MAX_LAGOMETER_RANGE

	-- draw the frame interpoalte / extrapolate graph
	for a = 0, math.ceil(aw) - 1 do
		local i = bit32.band(lagometer.frameCount - 1 - a, LAG_SAMPLES - 1)
		local v = lagometer.frameSamples[i]
		v *= vscale
		if v > 0 then
			if color ~= 1 then
				color = 1
				trap.R_SetColor(Q.g_color_table[Q.ColorIndex(C.COLOR_YELLOW)])
			end
			if v > range then
				v = range
			end
			trap.R_DrawStretchPic(ax + aw - a, mid - v, 1, v, 0, 0, 0, 0, media.whiteShader)
		elseif v < 0 then
			if color ~= 2 then
				color = 2
				trap.R_SetColor(Q.g_color_table[Q.ColorIndex(C.COLOR_BLUE)])
			end
			v = -v
			if v > range then
				v = range
			end
			trap.R_DrawStretchPic(ax + aw - a, mid, 1, v, 0, 0, 0, 0, media.whiteShader)
		end
	end

	-- draw the snapshot latency / drop graph
	range = ah / 2
	vscale = range / MAX_LAGOMETER_PING

	for a = 0, math.ceil(aw) - 1 do
		local i = bit32.band(lagometer.snapshotCount - 1 - a, LAG_SAMPLES - 1)
		local v = lagometer.snapshotSamples[i]
		if v > 0 then
			if bit32.band(lagometer.snapshotFlags[i], C.SNAPFLAG_RATE_DELAYED) ~= 0 then
				if color ~= 5 then
					color = 5 -- YELLOW for rate delay
					trap.R_SetColor(Q.g_color_table[Q.ColorIndex(C.COLOR_YELLOW)])
				end
			else
				if color ~= 3 then
					color = 3
					trap.R_SetColor(Q.g_color_table[Q.ColorIndex(C.COLOR_GREEN)])
				end
			end
			v = v * vscale
			if v > range then
				v = range
			end
			trap.R_DrawStretchPic(ax + aw - a, ay + ah - v, 1, v, 0, 0, 0, 0, media.whiteShader)
		elseif v < 0 then
			if color ~= 4 then
				color = 4 -- RED for dropped snapshots
				trap.R_SetColor(Q.g_color_table[Q.ColorIndex(C.COLOR_RED)])
			end
			trap.R_DrawStretchPic(ax + aw - a, ay + ah - range, 1, range, 0, 0, 0, 0, media.whiteShader)
		end
	end

	trap.R_SetColor(nil)

	if G.cg_nopredict.integer ~= 0 or G.cg_synchronousClients.integer ~= 0 then
		G.CG_DrawBigString(ax, ay, "snc", 1.0)
	end

	G.CG_DrawDisconnect()
end

--[[
===============================================================================

CENTER PRINTING

===============================================================================
]]

-- Called for important messages that should stay in the center of the screen
-- for a few moments
function G.CG_CenterPrint(str, y, charWidth)
	local cg = G.cg

	cg.centerPrint = string.sub(str, 1, C.MAX_STRING_CHARS - 1)

	cg.centerPrintTime = cg.time
	cg.centerPrintY = y
	cg.centerPrintCharWidth = charWidth

	-- count the number of lines for centering
	local lines = 1
	for i = 1, #cg.centerPrint do
		if string.byte(cg.centerPrint, i) == 10 then
			lines += 1
		end
	end
	cg.centerPrintLines = lines
end

function G.CG_DrawCenterString()
	local cg = G.cg

	if cg.centerPrintTime == 0 then
		return
	end

	local color = G.CG_FadeColor(cg.centerPrintTime, 1000 * G.cg_centertime.value)
	if color == nil then
		return
	end

	trap.R_SetColor(color)

	local text = cg.centerPrint
	local start = 1

	local y = cg.centerPrintY - Q.idiv(cg.centerPrintLines * C.BIGCHAR_HEIGHT, 2)

	while true do
		local l = 0
		while l < 50 do
			local ch = string.byte(text, start + l)
			if ch == nil or ch == 10 then
				break
			end
			l += 1
		end
		local linebuffer = string.sub(text, start, start + l - 1)

		local w = cg.centerPrintCharWidth * G.CG_DrawStrlen(linebuffer)

		local x = Q.idiv(C.SCREEN_WIDTH - w, 2)

		G.CG_DrawStringExt(x, y, linebuffer, color, false, true, cg.centerPrintCharWidth, Q.int(cg.centerPrintCharWidth * 1.5), 0)

		y += cg.centerPrintCharWidth * 1.5

		while true do
			local ch = string.byte(text, start)
			if ch == nil or ch == 10 then
				break
			end
			start += 1
		end
		if string.byte(text, start) == nil then
			break
		end
		start += 1
	end

	trap.R_SetColor(nil)
end

function G.drawCenterString(line, color)
	local y = 100

	if line == nil or color == nil then
		return
	end

	local w = G.cg.centerPrintCharWidth * G.CG_DrawStrlen(line)

	local x = Q.idiv(C.SCREEN_WIDTH - w, 2)

	G.CG_DrawStringExt(x, y, line, color, false, true, G.cg.centerPrintCharWidth, Q.int(G.cg.centerPrintCharWidth * 1.5), 0)
end

function G.CG_DrawCenter1FctfString()
	if G.cgs.gametype ~= C.GT_1FCTF then
		return
	end

	local status = G.cgs.flagStatus
	local line, color

	--Sago: TODO: Find the proper defines instead of hardcoded values.
	if status == 2 then
		line = Q.va("Red has the flag!")
		color = Q.colorRed
	elseif status == 3 then
		line = Q.va("Blue has the flag!")
		color = Q.colorBlue
	elseif status == 4 then
		line = Q.va("Flag dropped!")
		color = Q.colorWhite
	else
		return
	end

	G.drawCenterString(line, color)
end

G.lastDDSec = -100

function G.CG_DrawCenterDDString()
	local cgs = G.cgs
	local cg = G.cg

	if cgs.gametype ~= C.GT_DOUBLE_D then
		return
	end

	local statusA = cgs.redflag
	local statusB = cgs.blueflag

	if not ((statusB == statusA and statusA == C.TEAM_RED) or (statusB == statusA and statusA == C.TEAM_BLUE)) then
		G.lastDDSec = -100
		return -- No team is dominating
	end

	local line, color
	if statusA == C.TEAM_BLUE then
		line = Q.va("Blue scores in %i", Q.idiv(cgs.takeAt - cg.time, 1000) + 1)
		color = Q.colorBlue
	elseif statusA == C.TEAM_RED then
		line = Q.va("Red scores in %i", Q.idiv(cgs.takeAt - cg.time, 1000) + 1)
		color = Q.colorRed
	else
		G.lastDDSec = -100
		return
	end

	if cgs.takeAt == 0 then
		return
	end

	local sec = Q.idiv(cgs.takeAt - cg.time, 1000) + 1

	if sec < 0 then
		return
	end

	if sec ~= G.lastDDSec then
		-- A new number is being displayed... play the sound!
		if sec == 1 then
			trap.S_StartLocalSound(cgs.media.count1Sound, C.CHAN_ANNOUNCER)
		elseif sec == 2 then
			trap.S_StartLocalSound(cgs.media.count2Sound, C.CHAN_ANNOUNCER)
		elseif sec == 3 then
			trap.S_StartLocalSound(cgs.media.count3Sound, C.CHAN_ANNOUNCER)
		elseif G.lastDDSec == -100 then
			trap.S_StartLocalSound(cgs.media.doublerSound, C.CHAN_ANNOUNCER)
		end
	end
	G.lastDDSec = sec

	local y = 100

	local w = cg.centerPrintCharWidth * G.CG_DrawStrlen(line)

	local x = Q.idiv(C.SCREEN_WIDTH - w, 2)

	G.CG_DrawStringExt(x, y, line, color, false, true, cg.centerPrintCharWidth, Q.int(cg.centerPrintCharWidth * 1.5), 0)
end

return G
