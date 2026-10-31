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
-- Luau port of code/cgame/cg_draw.c (OpenArena 0.8.8, gamecode 9e0f0c0).
-- This part covers C lines 1-1377 of the 0.8.8 source.

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local trap = require(script.Parent.Parent.sys.Trap)
local BG = require(script.Parent.Parent.adapters.BG)
local Screen = require(script.Parent.Parent.Parent.ui.Screen)

local FPS_FRAMES = 4

G.drawTeamOverlayModificationCount = -1

G.sortedTeamPlayers = {}
for i = 0, C.TEAM_MAXOVERLAY - 1 do
	G.sortedTeamPlayers[i] = 0
end
G.numSortedTeamPlayers = 0

G.systemChat = ""
G.teamChat1 = ""
G.teamChat2 = ""

local function v4(a, b, c, d)
	return { [0] = a, [1] = b, [2] = c, [3] = d }
end

local function copyColor(src)
	return { [0] = src[0], [1] = src[1], [2] = src[2], [3] = src[3] }
end

local function itemIndex(item)
	for i = 0, BG.bg_numItems - 1 do
		if BG.bg_itemlist[i] == item then
			return i
		end
	end
	return 0
end

local statusColors = {
	[0] = v4(1.0, 0.69, 0.0, 1.0), -- normal
	[1] = v4(1.0, 0.2, 0.2, 1.0), -- low health
	[2] = v4(0.5, 0.5, 0.5, 1.0), -- weapon firing
	[3] = v4(1.0, 1.0, 1.0, 1.0), -- health > 100
}

local previousTimes = {}
for i = 0, FPS_FRAMES - 1 do
	previousTimes[i] = 0
end
local fpsIndex = 0
local fpsPrevious = 0

--[[
==============
CG_DrawField

Draws large numbers for status bar and powerups
==============
]]
function G.CG_DrawField(x, y, width, value)
	if width < 1 then
		return
	end

	-- draw number string
	if width > 5 then
		width = 5
	end

	if width == 1 then
		value = value > 9 and 9 or value
		value = value < 0 and 0 or value
	elseif width == 2 then
		value = value > 99 and 99 or value
		value = value < -9 and -9 or value
	elseif width == 3 then
		value = value > 999 and 999 or value
		value = value < -99 and -99 or value
	elseif width == 4 then
		value = value > 9999 and 9999 or value
		value = value < -999 and -999 or value
	end

	local num = Q.va("%i", value)
	local l = #num
	if l > width then
		l = width
	end
	x += 2 + C.CHAR_WIDTH * (width - l)

	local pos = 1
	while pos <= #num and l ~= 0 do
		local ch = string.byte(num, pos)
		local frame
		if ch == 45 then
			frame = C.STAT_MINUS
		else
			frame = ch - 48
		end

		G.CG_DrawPic(x, y, C.CHAR_WIDTH, C.CHAR_HEIGHT, G.cgs.media.numberShaders[frame])
		x += C.CHAR_WIDTH
		pos += 1
		l -= 1
	end
end

--[[
================
CG_Draw3DModel

================
]]
function G.CG_Draw3DModel(x, y, w, h, model, skin, origin, angles)
	if G.cg_draw3dIcons.integer == 0 or G.cg_drawIcons.integer == 0 then
		return
	end

	x, y, w, h = G.CG_AdjustFrom640(x, y, w, h)

	local refdef = T.refdef_t()
	local ent = T.refEntity_t()
	Q.AnglesToAxis(angles, ent.axis)
	Q.VectorCopy(origin, ent.origin)
	ent.hModel = model
	ent.customSkin = skin
	ent.renderfx = C.RF_NOSHADOW -- no stencil shadows

	refdef.rdflags = C.RDF_NOWORLDMODEL

	Q.AxisClear(refdef.viewaxis)

	refdef.fov_x = 30
	refdef.fov_y = 30

	refdef.x = x
	refdef.y = y
	refdef.width = w
	refdef.height = h

	refdef.time = G.cg.time

	trap.R_ClearScene()
	trap.R_AddRefEntityToScene(ent)
	trap.R_RenderScene(refdef)
end

--[[
================
CG_DrawHead

Used for both the status bar and the scoreboard
================
]]
function G.CG_DrawHead(x, y, w, h, clientNum, headAngles)
	local ci = G.cgs.clientinfo[clientNum]
	local origin = Q.vec3(0, 0, 0)
	local mins = Q.vec3(0, 0, 0)
	local maxs = Q.vec3(0, 0, 0)

	-- not in OA: a Roblox account's face is its headshot (cg_avatars.luau)
	local headshot = G.CG_AvatarHeadShader(clientNum)
	if headshot ~= 0 then
		G.CG_DrawPic(x, y, w, h, headshot)
		return
	end

	if G.cg_draw3dIcons.integer ~= 0 then
		local cm = ci.headModel
		if cm == 0 then
			return
		end

		-- offset the origin y and z to center the head
		trap.R_ModelBounds(cm, mins, maxs)

		origin[2] = -0.5 * (mins[2] + maxs[2])
		origin[1] = 0.5 * (mins[1] + maxs[1])

		-- calculate distance so the head nearly fills the box
		-- assume heads are taller than wide
		local len = 0.7 * (maxs[2] - mins[2])
		origin[0] = len / 0.268 -- len / tan( fov/2 )

		-- allow per-model tweaking
		Q.VectorAdd(origin, ci.headOffset, origin)

		G.CG_Draw3DModel(x, y, w, h, ci.headModel, ci.headSkin, origin, headAngles)
	elseif G.cg_drawIcons.integer ~= 0 then
		G.CG_DrawPic(x, y, w, h, ci.modelIcon)
	end

	-- if they are deferred, draw a cross out
	if ci.deferred then
		G.CG_DrawPic(x, y, w, h, G.cgs.media.deferShader)
	end
end

--[[
================
CG_DrawFlagModel

Used for both the status bar and the scoreboard
================
]]
function G.CG_DrawFlagModel(x, y, w, h, team, force2D)
	local cgs = G.cgs
	if not force2D and G.cg_draw3dIcons.integer ~= 0 then
		local angles = Q.vec3(0, 0, 0)
		local origin = Q.vec3(0, 0, 0)
		local mins = Q.vec3(0, 0, 0)
		local maxs = Q.vec3(0, 0, 0)
		local handle

		local cm = cgs.media.redFlagModel

		-- offset the origin y and z to center the flag
		trap.R_ModelBounds(cm, mins, maxs)

		origin[2] = -0.5 * (mins[2] + maxs[2])
		origin[1] = 0.5 * (mins[1] + maxs[1])

		-- calculate distance so the flag nearly fills the box
		-- assume heads are taller than wide
		local len = 0.5 * (maxs[2] - mins[2])
		origin[0] = len / 0.268 -- len / tan( fov/2 )

		angles[C.YAW] = 60 * math.sin(G.cg.time / 2000.0)

		if team == C.TEAM_RED then
			handle = cgs.media.redFlagModel
			if cgs.gametype == C.GT_DOUBLE_D then
				if cgs.redflag == C.TEAM_BLUE then
					handle = cgs.media.blueFlagModel
				end
				if cgs.redflag == C.TEAM_FREE then
					handle = cgs.media.neutralFlagModel
				end
				if cgs.redflag == C.TEAM_NONE then
					handle = cgs.media.neutralFlagModel
				end
			end
		elseif team == C.TEAM_BLUE then
			handle = cgs.media.blueFlagModel
			if cgs.gametype == C.GT_DOUBLE_D then
				if cgs.redflag == C.TEAM_BLUE then
					handle = cgs.media.blueFlagModel
				end
				if cgs.redflag == C.TEAM_FREE then
					handle = cgs.media.neutralFlagModel
				end
				if cgs.redflag == C.TEAM_NONE then
					handle = cgs.media.neutralFlagModel
				end
			end
		elseif team == C.TEAM_FREE then
			handle = cgs.media.neutralFlagModel
		else
			return
		end
		G.CG_Draw3DModel(x, y, w, h, handle, 0, origin, angles)
	elseif G.cg_drawIcons.integer ~= 0 then
		local item
		if team == C.TEAM_RED then
			item = BG.BG_FindItemForPowerup(C.PW_REDFLAG)
		elseif team == C.TEAM_BLUE then
			item = BG.BG_FindItemForPowerup(C.PW_BLUEFLAG)
		elseif team == C.TEAM_FREE then
			item = BG.BG_FindItemForPowerup(C.PW_NEUTRALFLAG)
		else
			return
		end
		if item ~= nil then
			G.CG_DrawPic(x, y, w, h, G.cg_items[itemIndex(item)].icon)
		end
	end
end

--[[
================
CG_DrawStatusBarHead

================
]]
function G.CG_DrawStatusBarHead(x)
	local cg = G.cg
	local angles = Q.vec3(0, 0, 0)
	local size, stretch
	local frac

	if cg.damageTime ~= 0 and cg.time - cg.damageTime < C.DAMAGE_TIME then
		frac = (cg.time - cg.damageTime) / C.DAMAGE_TIME
		size = C.ICON_SIZE * 1.25 * (1.5 - frac * 0.5)

		stretch = size - C.ICON_SIZE * 1.25
		-- kick in the direction of damage
		x -= stretch * 0.5 + cg.damageX * stretch * 0.5

		cg.headStartYaw = 180 + cg.damageX * 45

		cg.headEndYaw = 180 + 20 * math.cos(Q.crandom() * math.pi)
		cg.headEndPitch = 5 * math.cos(Q.crandom() * math.pi)

		cg.headStartTime = cg.time
		cg.headEndTime = cg.time + 100 + Q.int(Q.random() * 2000)
	else
		if cg.time >= cg.headEndTime then
			-- select a new head angle
			cg.headStartYaw = cg.headEndYaw
			cg.headStartPitch = cg.headEndPitch
			cg.headStartTime = cg.headEndTime
			cg.headEndTime = cg.time + 100 + Q.int(Q.random() * 2000)

			cg.headEndYaw = 180 + 20 * math.cos(Q.crandom() * math.pi)
			cg.headEndPitch = 5 * math.cos(Q.crandom() * math.pi)
		end

		size = C.ICON_SIZE * 1.25
	end

	-- if the server was frozen for a while we may have a bad head start time
	if cg.headStartTime > cg.time then
		cg.headStartTime = cg.time
	end

	frac = (cg.time - cg.headStartTime) / (cg.headEndTime - cg.headStartTime)
	frac = frac * frac * (3 - 2 * frac)
	angles[C.YAW] = cg.headStartYaw + (cg.headEndYaw - cg.headStartYaw) * frac
	angles[C.PITCH] = cg.headStartPitch + (cg.headEndPitch - cg.headStartPitch) * frac

	G.CG_DrawHead(x, 480 - size, size, size, cg.snap.ps.clientNum, angles)
end

--[[
================
CG_DrawStatusBarFlag

================
]]
function G.CG_DrawStatusBarFlag(x, team)
	G.CG_DrawFlagModel(x, 480 - C.ICON_SIZE, C.ICON_SIZE, C.ICON_SIZE, team, false)
end

--[[
================
CG_DrawTeamBackground

================
]]
function G.CG_DrawTeamBackground(x, y, w, h, alpha, team)
	local hcolor = v4(0, 0, 0, alpha)
	if team == C.TEAM_RED then
		hcolor[0] = 1
		hcolor[1] = 0
		hcolor[2] = 0
	elseif team == C.TEAM_BLUE then
		hcolor[0] = 0
		hcolor[1] = 0
		hcolor[2] = 1
	else
		return
	end
	trap.R_SetColor(hcolor)
	G.CG_DrawPic(x, y, w, h, G.cgs.media.teamStatusBar)
	trap.R_SetColor(nil)
end

--[[
================
CG_DrawStatusBar

================
]]
function G.CG_DrawStatusBar()
	local cg = G.cg
	local cgs = G.cgs
	local cg_weapons = G.cg_weapons
	local color
	local value
	local hcolor = v4(0, 0, 0, 0)
	local angles = Q.vec3(0, 0, 0)
	local origin = Q.vec3(0, 0, 0)
	local handle

	if G.cg_drawStatus.integer == 0 then
		return
	end

	-- on the bottom edge: the background spans the screen, the ammo block
	-- keeps to the left corner, health and head to the centre, armor (and
	-- harvester skulls) to the right corner
	local L, M, R, BOTTOM = Screen.LEFT, Screen.CENTER, Screen.RIGHT, Screen.BOTTOM

	-- draw the team background
	G.CG_SetScreenPlacement(Screen.STRETCH, BOTTOM)
	if bit32.band(cg.snap.ps.pm_flags, C.PMF_FOLLOW) == 0 then -- If not following anybody:
		G.CG_DrawTeamBackground(0, 420, 640, 60, 0.33, cg.snap.ps.persistant[C.PERS_TEAM])
	else -- If we follow find the teamcolor of the guy we follow. It might not be our own team!
		G.CG_DrawTeamBackground(0, 420, 640, 60, 0.33, cgs.clientinfo[cg.snap.ps.clientNum].team)
	end

	local cent = G.cg_entities[cg.snap.ps.clientNum]
	local ps = cg.snap.ps

	-- draw any 3D icons first, so the changes back to 2D are minimized
	G.CG_SetScreenPlacement(L, BOTTOM)
	if cent.currentState.weapon ~= 0 and cg_weapons[cent.currentState.weapon].ammoModel ~= 0 then
		origin[0] = 70
		origin[1] = 0
		origin[2] = 0
		angles[C.YAW] = 90 + 20 * math.sin(cg.time / 1000.0)
		G.CG_Draw3DModel(
			C.CHAR_WIDTH * 3 + C.TEXT_ICON_SPACE,
			432,
			C.ICON_SIZE,
			C.ICON_SIZE,
			cg_weapons[cent.currentState.weapon].ammoModel,
			0,
			origin,
			angles
		)
	end

	G.CG_SetScreenPlacement(M, BOTTOM)
	G.CG_DrawStatusBarHead(185 + C.CHAR_WIDTH * 3 + C.TEXT_ICON_SPACE)

	if cg.predictedPlayerState.powerups[C.PW_REDFLAG] ~= 0 then
		G.CG_DrawStatusBarFlag(185 + C.CHAR_WIDTH * 3 + C.TEXT_ICON_SPACE + C.ICON_SIZE, C.TEAM_RED)
	elseif cg.predictedPlayerState.powerups[C.PW_BLUEFLAG] ~= 0 then
		G.CG_DrawStatusBarFlag(185 + C.CHAR_WIDTH * 3 + C.TEXT_ICON_SPACE + C.ICON_SIZE, C.TEAM_BLUE)
	elseif cg.predictedPlayerState.powerups[C.PW_NEUTRALFLAG] ~= 0 then
		G.CG_DrawStatusBarFlag(185 + C.CHAR_WIDTH * 3 + C.TEXT_ICON_SPACE + C.ICON_SIZE, C.TEAM_FREE)
	end

	G.CG_SetScreenPlacement(R, BOTTOM)
	if ps.stats[C.STAT_ARMOR] ~= 0 then
		origin[0] = 90
		origin[1] = 0
		origin[2] = -10
		angles[C.YAW] = bit32.band(cg.time, 2047) * 360 / 2048.0
		G.CG_Draw3DModel(
			370 + C.CHAR_WIDTH * 3 + C.TEXT_ICON_SPACE,
			432,
			C.ICON_SIZE,
			C.ICON_SIZE,
			cgs.media.armorModel,
			0,
			origin,
			angles
		)
	end

	if cgs.gametype == C.GT_HARVESTER then
		origin[0] = 90
		origin[1] = 0
		origin[2] = -10
		angles[C.YAW] = bit32.band(cg.time, 2047) * 360 / 2048.0
		if cg.snap.ps.persistant[C.PERS_TEAM] == C.TEAM_BLUE then
			handle = cgs.media.redCubeModel
		else
			handle = cgs.media.blueCubeModel
		end
		G.CG_Draw3DModel(
			470 + C.CHAR_WIDTH * 3 + C.TEXT_ICON_SPACE,
			432,
			C.ICON_SIZE,
			C.ICON_SIZE,
			handle,
			0,
			origin,
			angles
		)
	end

	--
	-- ammo
	--
	G.CG_SetScreenPlacement(L, BOTTOM)
	if cent.currentState.weapon ~= 0 then
		value = ps.ammo[cent.currentState.weapon]
		if value > -1 then
			if cg.predictedPlayerState.weaponstate == C.WEAPON_FIRING and cg.predictedPlayerState.weaponTime > 100 then
				-- draw as dark grey when reloading
				color = 2 -- dark grey
			else
				if value >= 0 then
					color = 0 -- green
				else
					color = 1 -- red
				end
			end
			trap.R_SetColor(statusColors[color])

			G.CG_DrawField(0, 432, 3, value)
			trap.R_SetColor(nil)

			-- if we didn't draw a 3D icon, draw a 2D icon for ammo
			if G.cg_draw3dIcons.integer == 0 and G.cg_drawIcons.integer ~= 0 then
				local icon = cg_weapons[cg.predictedPlayerState.weapon].ammoIcon
				if icon ~= 0 then
					G.CG_DrawPic(C.CHAR_WIDTH * 3 + C.TEXT_ICON_SPACE, 432, C.ICON_SIZE, C.ICON_SIZE, icon)
				end
			end
		end
	end

	--
	-- health
	--
	value = ps.stats[C.STAT_HEALTH]
	if value > 100 then
		trap.R_SetColor(statusColors[3]) -- white
	elseif value > 25 then
		trap.R_SetColor(statusColors[0]) -- green
	elseif value > 0 then
		color = bit32.band(bit32.rshift(cg.time, 8), 1) -- flash
		trap.R_SetColor(statusColors[color])
	else
		trap.R_SetColor(statusColors[1]) -- red
	end

	-- stretch the health up when taking damage
	G.CG_SetScreenPlacement(M, BOTTOM)
	G.CG_DrawField(185, 432, 3, value)
	G.CG_ColorForHealth(hcolor)
	trap.R_SetColor(hcolor)

	--
	-- armor
	--
	G.CG_SetScreenPlacement(R, BOTTOM)
	value = ps.stats[C.STAT_ARMOR]
	if value > 0 then
		trap.R_SetColor(statusColors[0])
		G.CG_DrawField(370, 432, 3, value)
		trap.R_SetColor(nil)
		-- if we didn't draw a 3D icon, draw a 2D icon for armor
		if G.cg_draw3dIcons.integer == 0 and G.cg_drawIcons.integer ~= 0 then
			G.CG_DrawPic(370 + C.CHAR_WIDTH * 3 + C.TEXT_ICON_SPACE, 432, C.ICON_SIZE, C.ICON_SIZE, cgs.media.armorIcon)
		end
	end

	-- Skulls!
	if cgs.gametype == C.GT_HARVESTER then
		value = ps.generic1
		if value > 0 then
			trap.R_SetColor(statusColors[0])
			G.CG_DrawField(470, 432, 3, value)
			trap.R_SetColor(nil)
			-- if we didn't draw a 3D icon, draw a 2D icon for skull
			if G.cg_draw3dIcons.integer == 0 and G.cg_drawIcons.integer ~= 0 then
				if cg.snap.ps.persistant[C.PERS_TEAM] == C.TEAM_BLUE then
					handle = cgs.media.redCubeIcon
				else
					handle = cgs.media.blueCubeIcon
				end
				G.CG_DrawPic(470 + C.CHAR_WIDTH * 3 + C.TEXT_ICON_SPACE, 432, C.ICON_SIZE, C.ICON_SIZE, handle)
			end
		end
	end
end

--[[
===========================================================================================

 UPPER RIGHT CORNER

===========================================================================================
]]

--[[
================
CG_DrawAttacker

================
]]
function G.CG_DrawAttacker(y)
	local cg = G.cg
	local cgs = G.cgs

	if cg.predictedPlayerState.stats[C.STAT_HEALTH] <= 0 then
		return y
	end

	if cg.attackerTime == 0 then
		return y
	end

	local clientNum = cg.predictedPlayerState.persistant[C.PERS_ATTACKER]
	if clientNum < 0 or clientNum >= C.MAX_CLIENTS or clientNum == cg.snap.ps.clientNum then
		return y
	end

	local t =cg.time - cg.attackerTime
	if t > C.ATTACKER_HEAD_TIME then
		cg.attackerTime = 0
		return y
	end

	local size = C.ICON_SIZE * 1.25

	local angles = Q.vec3(0, 180, 0)
	G.CG_DrawHead(640 - size, y, size, size, clientNum, angles)

	local info = G.CG_ConfigString(C.CS_PLAYERS + clientNum)
	local name = Q.Info_ValueForKey(info, "n")
	y += size
	G.CG_DrawBigString(640 - (Q.PrintStrlen(name) * C.BIGCHAR_WIDTH), y, name, 0.5)

	return y + C.BIGCHAR_HEIGHT + 2
end

--[[
================
CG_DrawSpeedMeter

================
]]
function G.CG_DrawSpeedMeter(y)
	local cg = G.cg

	-- speed meter can get in the way of the scoreboard
	if cg.scoreBoardShowing then
		return y
	end

	local vel = cg.snap.ps.velocity
	-- ignore vertical component of velocity
	local speed = Q.int(math.sqrt(vel[0] * vel[0] + vel[1] * vel[1]))

	local s = Q.va("%iu/s", speed)

	local w = G.CG_DrawStrlen(s) * C.BIGCHAR_WIDTH

	if G.cg_drawSpeed.integer == 1 then
		-- top left-hand corner of screen
		G.CG_DrawBigString(635 - w, y + 2, s, 1.0)
		return y + C.BIGCHAR_HEIGHT + 4
	else
		-- center of screen
		G.CG_DrawBigString(320 - Q.idiv(w, 2), 300, s, 1.0)
		return y
	end
end

--[[
==================
CG_DrawSnapshot
==================
]]
function G.CG_DrawSnapshot(y)
	local s = Q.va("time:%i snap:%i cmd:%i", G.cg.snap.serverTime, G.cg.latestSnapshotNum, G.cgs.serverCommandSequence)
	local w = G.CG_DrawStrlen(s) * C.BIGCHAR_WIDTH

	G.CG_DrawBigString(635 - w, y + 2, s, 1.0)

	return y + C.BIGCHAR_HEIGHT + 4
end

--[[
==================
CG_DrawFPS
==================
]]
function G.CG_DrawFPS(y)
	-- don't use serverTime, because that will be drifting to
	-- correct for internet lag changes, timescales, timedemos, etc
	local t = trap.Milliseconds()
	local frameTime = t - fpsPrevious
	fpsPrevious = t

	previousTimes[fpsIndex % FPS_FRAMES] = frameTime
	fpsIndex += 1
	if fpsIndex > FPS_FRAMES then
		-- average multiple frames together to smooth changes out a bit
		local total = 0
		for i = 0, FPS_FRAMES - 1 do
			total += previousTimes[i]
		end
		if total == 0 then
			total = 1
		end
		local fps = Q.idiv(1000 * FPS_FRAMES, total)

		local s = Q.va("%ifps", fps)
		local w = G.CG_DrawStrlen(s) * C.BIGCHAR_WIDTH

		G.CG_DrawBigString(635 - w, y + 2, s, 1.0)
	end

	return y + C.BIGCHAR_HEIGHT + 4
end

--[[
=================
CG_DrawTimer
=================
]]
function G.CG_DrawTimer(y)
	local msec = G.cg.time - G.cgs.levelStartTime

	local seconds = Q.idiv(msec, 1000)
	local mins = Q.idiv(seconds, 60)
	seconds -= mins * 60
	local tens = Q.idiv(seconds, 10)
	seconds -= tens * 10

	local s = Q.va("%i:%i%i", mins, tens, seconds)
	local w = G.CG_DrawStrlen(s) * C.BIGCHAR_WIDTH

	G.CG_DrawBigString(635 - w, y + 2, s, 1.0)

	return y + C.BIGCHAR_HEIGHT + 4
end

--[[
=================
CG_DrawLMSmode
=================
]]
function G.CG_DrawLMSmode(y)
	local s
	local mode = G.cgs.lms_mode

	if mode == 0 then
		s = Q.va("LMS: Point/round + OT")
	elseif mode == 1 then
		s = Q.va("LMS: Point/round - OT")
	elseif mode == 2 then
		s = Q.va("LMS: Point/kill + OT")
	elseif mode == 3 then
		s = Q.va("LMS: Point/kill - OT")
	else
		s = Q.va("LMS: Unknown mode")
	end

	local w = G.CG_DrawStrlen(s) * C.SMALLCHAR_WIDTH
	G.CG_DrawSmallString(635 - w, y + 2, s, 1.0)

	return y + C.SMALLCHAR_HEIGHT + 4
end

--[[
=================
CG_DrawCTFoneway
=================
]]
function G.CG_DrawCTFoneway(y)
	local cgs = G.cgs
	local s

	if cgs.gametype ~= C.GT_CTF_ELIMINATION then
		return y
	end

	local color = copyColor(Q.g_color_table[Q.ColorIndex(C.COLOR_WHITE)])

	if bit32.band(cgs.elimflags, C.EF_ONEWAY) == 0 then
		return y -- nothing to draw
	elseif cgs.attackingTeam == C.TEAM_BLUE then
		color = copyColor(Q.g_color_table[Q.ColorIndex(C.COLOR_BLUE)])
		s = Q.va("Blue team on offence")
	elseif cgs.attackingTeam == C.TEAM_RED then
		color = copyColor(Q.g_color_table[Q.ColorIndex(C.COLOR_RED)])
		s = Q.va("Red team on offence")
	else
		s = Q.va("Unknown team on offence")
	end

	local w = G.CG_DrawStrlen(s) * C.SMALLCHAR_WIDTH
	G.CG_DrawSmallStringColor(635 - w, y + 2, s, color)

	return y + C.SMALLCHAR_HEIGHT + 4
end

--[[
=================
CG_DrawDomStatus
=================
]]
function G.CG_DrawDomStatus(y)
	local cgs = G.cgs

	for i = 0, cgs.domination_points_count - 1 do
		local color
		local status = cgs.domination_points_status[i]
		if status == C.TEAM_RED then
			color = copyColor(Q.g_color_table[Q.ColorIndex(C.COLOR_RED)])
		elseif status == C.TEAM_BLUE then
			color = copyColor(Q.g_color_table[Q.ColorIndex(C.COLOR_BLUE)])
		else
			color = copyColor(Q.g_color_table[Q.ColorIndex(C.COLOR_WHITE)])
		end

		local s = Q.va("%s", cgs.domination_points_names[i])
		local w = G.CG_DrawStrlen(s) * C.SMALLCHAR_WIDTH
		G.CG_DrawSmallStringColor(635 - w, y + 2, s, color)
		y += C.SMALLCHAR_HEIGHT + 4
	end

	return y
end

--[[
=================
CG_DrawEliminationTimer
=================
]]
function G.CG_DrawEliminationTimer(y)
	local cg = G.cg
	local cgs = G.cgs
	local msec
	local rst = cgs.roundStartTime

	if cg.time > rst and cgs.roundtime == 0 then
		return y
	end

	-- default color is white
	local color = copyColor(Q.g_color_table[Q.ColorIndex(C.COLOR_WHITE)])

	if cg.time > rst then -- We are started
		msec = cgs.roundtime * 1000 - (cg.time - rst)
		if msec <= 30 * 1000 - 1 then -- <= 30 seconds
			color = copyColor(Q.g_color_table[Q.ColorIndex(C.COLOR_YELLOW)])
		end
		if msec <= 10 * 1000 - 1 then -- <= 10 seconds
			color = copyColor(Q.g_color_table[Q.ColorIndex(C.COLOR_RED)])
		end
		msec += 1000 -- 120-1 instead of 119-0
	else
		-- Warmup
		msec = -cg.time + rst
		color = copyColor(Q.g_color_table[Q.ColorIndex(C.COLOR_GREEN)])
		local sec = Q.idiv(msec, 1000)
		msec += 1000 -- 5-1 instead of 4-0
		if cg.warmup == 0 then
			local st = Q.va("Round in: %i", sec + 1)
			if sec ~= cg.warmupCount then
				cg.warmupCount = sec
				if sec == 0 then
					trap.S_StartLocalSound(cgs.media.count1Sound, C.CHAN_ANNOUNCER)
				elseif sec == 1 then
					trap.S_StartLocalSound(cgs.media.count2Sound, C.CHAN_ANNOUNCER)
				elseif sec == 2 then
					trap.S_StartLocalSound(cgs.media.count3Sound, C.CHAN_ANNOUNCER)
				end
			end
			local cw
			if cg.warmupCount == 0 then
				cw = 28
			elseif cg.warmupCount == 1 then
				cw = 24
			elseif cg.warmupCount == 2 then
				cw = 20
			else
				cw = 16
			end

			local w = G.CG_DrawStrlen(st)
			G.CG_DrawStringExt(320 - Q.idiv(w * cw, 2), 70, st, Q.colorWhite, false, true, cw, Q.int(cw * 1.5), 0)
		end
	end

	local seconds = Q.idiv(msec, 1000)
	local mins = Q.idiv(seconds, 60)
	seconds -= mins * 60
	local tens = Q.idiv(seconds, 10)
	seconds -= tens * 10

	local s
	if msec >= 0 then
		s = Q.va(" %i:%i%i", mins, tens, seconds)
	else
		s = Q.va(" Overtime")
	end
	local w = G.CG_DrawStrlen(s) * C.BIGCHAR_WIDTH

	G.CG_DrawBigStringColor(635 - w, y + 2, s, color)

	return y + C.BIGCHAR_HEIGHT + 4
end

--[[
=================
CG_DrawTeamOverlay
=================
]]
function G.CG_DrawTeamOverlay(y, right, upper)
	local cg = G.cg
	local cgs = G.cgs
	local cg_weapons = G.cg_weapons
	local sorted = G.sortedTeamPlayers
	local x, w, h, xx
	local len
	local p
	local hcolor = v4(0, 0, 0, 0)
	local pwidth, lwidth
	local plyrs
	local ci
	local ret_y, count
	local myTeam = cg.snap.ps.persistant[C.PERS_TEAM]

	if G.cg_drawTeamOverlay.integer == 0 then
		return y
	end

	if myTeam ~= C.TEAM_RED and myTeam ~= C.TEAM_BLUE then
		return y -- Not on any team
	end

	plyrs = 0

	-- max player name width
	pwidth = 0
	count = (G.numSortedTeamPlayers > 8) and 8 or G.numSortedTeamPlayers
	for i = 0, count - 1 do
		ci = cgs.clientinfo[sorted[i]]
		if ci.infoValid and ci.team == myTeam then
			plyrs += 1
			len = G.CG_DrawStrlen(ci.name)
			if len > pwidth then
				pwidth = len
			end
		end
	end

	if plyrs == 0 then
		return y
	end

	if pwidth > C.TEAM_OVERLAY_MAXNAME_WIDTH then
		pwidth = C.TEAM_OVERLAY_MAXNAME_WIDTH
	end

	-- max location name width
	lwidth = 0
	for i = 1, C.MAX_LOCATIONS - 1 do
		p = G.CG_ConfigString(C.CS_LOCATIONS + i)
		if p ~= "" then
			len = G.CG_DrawStrlen(p)
			if len > lwidth then
				lwidth = len
			end
		end
	end

	if lwidth > C.TEAM_OVERLAY_MAXLOCATION_WIDTH then
		lwidth = C.TEAM_OVERLAY_MAXLOCATION_WIDTH
	end

	w = (pwidth + lwidth + 4 + 7) * C.TINYCHAR_WIDTH

	if right then
		x = 640 - w
	else
		x = 0
	end

	h = plyrs * C.TINYCHAR_HEIGHT

	if upper then
		ret_y = Q.int(y + h)
	else
		y -= h
		ret_y = Q.int(y)
	end

	if myTeam == C.TEAM_RED then
		hcolor[0] = 1.0
		hcolor[1] = 0.0
		hcolor[2] = 0.0
		hcolor[3] = 0.33
	else
		hcolor[0] = 0.0
		hcolor[1] = 0.0
		hcolor[2] = 1.0
		hcolor[3] = 0.33
	end
	trap.R_SetColor(hcolor)
	G.CG_DrawPic(x, y, w, h, cgs.media.teamStatusBar)
	trap.R_SetColor(nil)

	for i = 0, count - 1 do
		ci = cgs.clientinfo[sorted[i]]
		if ci.infoValid and ci.team == myTeam then
			hcolor[0] = 1.0
			hcolor[1] = 1.0
			hcolor[2] = 1.0
			hcolor[3] = 1.0

			xx = x + C.TINYCHAR_WIDTH

			G.CG_DrawStringExt(
				xx,
				y,
				ci.name,
				hcolor,
				false,
				false,
				C.TINYCHAR_WIDTH,
				C.TINYCHAR_HEIGHT,
				C.TEAM_OVERLAY_MAXNAME_WIDTH
			)

			if lwidth ~= 0 then
				p = G.CG_ConfigString(C.CS_LOCATIONS + ci.location)
				if p == "" then
					p = "unknown"
				end
				len = G.CG_DrawStrlen(p)
				if len > lwidth then
					len = lwidth
				end

				xx = x + C.TINYCHAR_WIDTH * 2 + C.TINYCHAR_WIDTH * pwidth
				G.CG_DrawStringExt(
					xx,
					y,
					p,
					hcolor,
					false,
					false,
					C.TINYCHAR_WIDTH,
					C.TINYCHAR_HEIGHT,
					C.TEAM_OVERLAY_MAXLOCATION_WIDTH
				)
			end

			G.CG_GetColorForHealth(ci.health, ci.armor, hcolor)

			local st = Q.va("%3i %3i", ci.health, ci.armor)

			xx = x + C.TINYCHAR_WIDTH * 3 + C.TINYCHAR_WIDTH * pwidth + C.TINYCHAR_WIDTH * lwidth

			G.CG_DrawStringExt(xx, y, st, hcolor, false, false, C.TINYCHAR_WIDTH, C.TINYCHAR_HEIGHT, 0)

			-- draw weapon icon
			xx += C.TINYCHAR_WIDTH * 3

			if cg_weapons[ci.curWeapon].weaponIcon ~= 0 then
				G.CG_DrawPic(xx, y, C.TINYCHAR_WIDTH, C.TINYCHAR_HEIGHT, cg_weapons[ci.curWeapon].weaponIcon)
			else
				G.CG_DrawPic(xx, y, C.TINYCHAR_WIDTH, C.TINYCHAR_HEIGHT, cgs.media.deferShader)
			end

			-- Draw powerup icons
			if right then
				xx = x
			else
				xx = x + w - C.TINYCHAR_WIDTH
			end
			for j = 0, C.PW_NUM_POWERUPS do
				if bit32.band(ci.powerups, bit32.lshift(1, j)) ~= 0 then
					local item = BG.BG_FindItemForPowerup(j)

					if item ~= nil then
						G.CG_DrawPic(xx, y, C.TINYCHAR_WIDTH, C.TINYCHAR_HEIGHT, trap.R_RegisterShader(item.icon))
						if right then
							xx -= C.TINYCHAR_WIDTH
						else
							xx += C.TINYCHAR_WIDTH
						end
					end
				end
			end

			y += C.TINYCHAR_HEIGHT
		end
	end

	return ret_y
end

function G.CG_DrawFollowMessage(y)
	local cgs = G.cgs

	if
		bit32.band(G.cg.snap.ps.pm_flags, C.PMF_FOLLOW) == 0
		or (
			bit32.band(cgs.elimflags, C.EF_NO_FREESPEC) ~= 0
			and (cgs.gametype == C.GT_ELIMINATION or cgs.gametype == C.GT_CTF_ELIMINATION)
		)
	then
		return y
	end

	local s = Q.va("USE_ITEM to stop following")
	local w = G.CG_DrawStrlen(s) * C.SMALLCHAR_WIDTH
	G.CG_DrawSmallString(635 - w, y + 2, s, 1.0)

	return y + C.SMALLCHAR_HEIGHT + 4
end

return G
