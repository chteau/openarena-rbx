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
-- Luau port of code/cgame/cg_draw.c (OpenArena 0.8.8, gamecode 9e0f0c0).
-- This part covers C lines 2462-3408 of the 0.8.8 source.

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local trap = require(script.Parent.Parent.sys.Trap)

local ACCBOARD_XPOS = 500
local ACCBOARD_YPOS = 150
local ACCBOARD_HEIGHT = 20
local ACCITEM_SIZE = 16

local proxTime = 0
local proxCounter = 0
local proxTick = 0

local function isSet(v)
	return v ~= nil and v ~= false and v ~= 0
end

local function crosshairShaderFor(ca)
	local hShader = G.cgs.media.crosshairShader[math.fmod(ca, C.NUM_CROSSHAIRS)]
	if hShader == nil or hShader == 0 then
		hShader = G.cgs.media.crosshairShader[math.fmod(ca, 10)]
	end
	return hShader
end

function G.CG_DrawCrosshair()
	local cg = G.cg
	local w, h
	local ca = 0
	local currentWeapon = cg.predictedPlayerState.weapon

	if G.cg_drawCrosshair.integer == 0 then
		return
	end

	if cg.snap.ps.persistant[C.PERS_TEAM] == C.TEAM_SPECTATOR then
		return
	end

	if isSet(cg.renderingThirdPerson) then
		return
	end

	-- set color based on health
	if G.cg_crosshairHealth.integer ~= 0 then
		local hcolor = Q.vec4(0, 0, 0, 0)
		G.CG_ColorForHealth(hcolor)
		trap.R_SetColor(hcolor)
	else
		local color = Q.vec4(
			G.cg_crosshairColorRed.value,
			G.cg_crosshairColorGreen.value,
			G.cg_crosshairColorBlue.value,
			1.0
		)
		trap.R_SetColor(color)
	end

	if G.cg_differentCrosshairs.integer == 1 and currentWeapon >= 1 and currentWeapon <= 13 then
		w = G["cg_ch" .. currentWeapon .. "size"].value
		h = w
		ca = G["cg_ch" .. currentWeapon].integer
	else
		w = G.cg_crosshairSize.value
		h = w
		ca = G.cg_drawCrosshair.integer
	end

	if G.cg_crosshairPulse.integer ~= 0 then
		-- pulse the size of the crosshair when picking up items
		local f = cg.time - cg.itemPickupBlendTime
		if f > 0 and f < C.ITEM_BLOB_TIME then
			f /= C.ITEM_BLOB_TIME
			w *= (1 + f)
			h *= (1 + f)
		end
	end

	local x = G.cg_crosshairX.integer
	local y = G.cg_crosshairY.integer
	x, y, w, h = G.CG_AdjustFrom640(x, y, w, h)

	if ca < 0 then
		ca = 0
	end
	local hShader = crosshairShaderFor(ca)

	trap.R_DrawStretchPic(
		x + cg.refdef.x + 0.5 * (cg.refdef.width - w),
		y + cg.refdef.y + 0.5 * (cg.refdef.height - h),
		w, h, 0, 0, 1, 1, hShader
	)
end

function G.CG_DrawCrosshair3D()
	local cg = G.cg
	local cgs = G.cgs

	if G.cg_drawCrosshair.integer == 0 then
		return
	end

	if cg.snap.ps.persistant[C.PERS_TEAM] == C.TEAM_SPECTATOR then
		return
	end

	if isSet(cg.renderingThirdPerson) then
		return
	end

	local w = G.cg_crosshairSize.value
	local h = w

	-- pulse the size of the crosshair when picking up items
	local f = cg.time - cg.itemPickupBlendTime
	if f > 0 and f < C.ITEM_BLOB_TIME then
		f /= C.ITEM_BLOB_TIME
		w *= (1 + f)
		h *= (1 + f)
	end

	local ca = G.cg_drawCrosshair.integer
	if ca < 0 then
		ca = 0
	end
	local hShader = crosshairShaderFor(ca)

	-- trace to the next shootable object and place the crosshair in front of it
	local zProj = tonumber(trap.Cvar_VariableStringBuffer("r_zProj")) or 0
	local stereoSep = zProj / (tonumber(trap.Cvar_VariableStringBuffer("r_stereoSeparation")) or 0)

	local xmax = zProj * math.tan(cg.refdef.fov_x * math.pi / 360.0)

	-- let the trace run through until a change in stereo separation of the crosshair becomes less than one pixel.
	local maxdist = cgs.glconfig.vidWidth * stereoSep * zProj / (2 * xmax)
	local endpos = Q.vec3(0, 0, 0)
	Q.VectorMA(cg.refdef.vieworg, maxdist, cg.refdef.viewaxis[0], endpos)
	local trace = T.trace_t()
	G.CG_Trace(trace, cg.refdef.vieworg, nil, nil, endpos, 0, C.MASK_SHOT)

	local ent = T.refEntity_t()
	ent.reType = C.RT_SPRITE
	ent.renderfx = bit32.bor(C.RF_DEPTHHACK, C.RF_CROSSHAIR)

	Q.VectorCopy(trace.endpos, ent.origin)

	-- scale the crosshair so it appears the same size for all distances
	ent.radius = w / 640 * xmax * trace.fraction * maxdist / zProj
	ent.customShader = hShader

	trap.R_AddRefEntityToScene(ent)
end

function G.CG_ScanForCrosshairEntity()
	local cg = G.cg
	local start = Q.vec3(0, 0, 0)
	local finish = Q.vec3(0, 0, 0)
	local trace = T.trace_t()

	Q.VectorCopy(cg.refdef.vieworg, start)
	Q.VectorMA(start, 131072, cg.refdef.viewaxis[0], finish)

	G.CG_Trace(trace, start, Q.vec3_origin, Q.vec3_origin, finish,
		cg.snap.ps.clientNum, bit32.bor(C.CONTENTS_SOLID, C.CONTENTS_BODY))
	if trace.entityNum >= C.MAX_CLIENTS then
		return
	end

	-- if the player is in fog, don't show it
	local content = G.CG_PointContents(trace.endpos, 0)
	if bit32.band(content, C.CONTENTS_FOG) ~= 0 then
		return
	end

	-- if the player is invisible, don't show it
	if bit32.band(G.cg_entities[trace.entityNum].currentState.powerups, bit32.lshift(1, C.PW_INVIS)) ~= 0 then
		return
	end

	-- update the fade timer
	cg.crosshairClientNum = trace.entityNum
	cg.crosshairClientTime = cg.time
end

function G.CG_DrawCrosshairNames()
	local cg = G.cg

	if G.cg_drawCrosshair.integer == 0 then
		return
	end
	if G.cg_drawCrosshairNames.integer == 0 then
		return
	end
	if isSet(cg.renderingThirdPerson) then
		return
	end

	-- scan the known entities to see if the crosshair is sighted on one
	G.CG_ScanForCrosshairEntity()

	-- draw the name of the player being looked at
	local color = G.CG_FadeColor(cg.crosshairClientTime, 1000)
	if color == nil then
		trap.R_SetColor(nil)
		return
	end

	local name = G.cgs.clientinfo[cg.crosshairClientNum].name
	local w = G.CG_DrawStrlen(name) * C.BIGCHAR_WIDTH
	G.CG_DrawBigString(320 - w / 2, 170, name, color[3] * 0.5)
	trap.R_SetColor(nil)
end

function G.CG_DrawSpectator()
	local cgs = G.cgs
	G.CG_DrawBigString(320 - 9 * 8, 440, "SPECTATOR", 1.0)
	if cgs.gametype == C.GT_TOURNAMENT then
		G.CG_DrawBigString(320 - 15 * 8, 460, "waiting to play", 1.0)
	elseif cgs.gametype >= C.GT_TEAM and cgs.ffa_gt ~= 1 then
		G.CG_DrawBigString(320 - 39 * 8, 460, "press ESC and use the JOIN menu to play", 1.0)
	end
end

function G.CG_DrawVote()
	local cg = G.cg
	local cgs = G.cgs

	if cgs.voteTime == 0 then
		return
	end

	-- play a talk beep whenever it is modified
	if isSet(cgs.voteModified) then
		cgs.voteModified = false
		trap.S_StartLocalSound(cgs.media.talkSound, C.CHAN_LOCAL_SOUND)
	end

	local sec = Q.idiv(C.VOTE_TIME - (cg.time - cgs.voteTime), 1000)
	if sec < 0 then
		sec = 0
	end
	local s = Q.va("VOTE(%i):%s yes:%i no:%i", sec, cgs.voteString, cgs.voteYes, cgs.voteNo)
	G.CG_DrawSmallString(0, 58, s, 1.0)
end

function G.CG_DrawTeamVote()
	local cg = G.cg
	local cgs = G.cgs
	local cs_offset

	local team = cgs.clientinfo[cg.clientNum].team
	if team == C.TEAM_RED then
		cs_offset = 0
	elseif team == C.TEAM_BLUE then
		cs_offset = 1
	else
		return
	end

	if cgs.teamVoteTime[cs_offset] == 0 then
		return
	end

	-- play a talk beep whenever it is modified
	if isSet(cgs.teamVoteModified[cs_offset]) then
		cgs.teamVoteModified[cs_offset] = false
		trap.S_StartLocalSound(cgs.media.talkSound, C.CHAN_LOCAL_SOUND)
	end

	local sec = Q.idiv(C.VOTE_TIME - (cg.time - cgs.teamVoteTime[cs_offset]), 1000)
	if sec < 0 then
		sec = 0
	end
	local s = Q.va("TEAMVOTE(%i):%s yes:%i no:%i", sec, cgs.teamVoteString[cs_offset],
		cgs.teamVoteYes[cs_offset], cgs.teamVoteNo[cs_offset])
	G.CG_DrawSmallString(0, 90, s, 1.0)
end

function G.CG_DrawScoreboard()
	local cg = G.cg
	local cgs = G.cgs
	if cg.respawnTime ~= 0 and cg.snap.ps.persistant[C.PERS_TEAM] ~= C.TEAM_SPECTATOR
		and (cgs.gametype < C.GT_ELIMINATION or cgs.gametype > C.GT_LMS) then
		if cg.respawnTime > cg.time then
			local s = Q.va("Respawn in: %2.2f", (cg.respawnTime - cg.time) / 1000.0)
			local w = G.CG_DrawStrlen(s) * C.SMALLCHAR_WIDTH
			G.CG_DrawSmallStringColor(320 - Q.idiv(w, 2), 400, s, Q.colorYellow)
		else
			local s = "Click FIRE to respawn"
			local w = G.CG_DrawStrlen(s) * C.SMALLCHAR_WIDTH
			G.CG_DrawSmallStringColor(320 - Q.idiv(w, 2), 400, "Click FIRE to respawn", Q.colorGreen)
		end
	end
	return G.CG_DrawOldScoreboard()
end

function G.CG_DrawAccboard()
	local cg = G.cg
	local cg_weapons = G.cg_weapons

	if not isSet(cg.showAcc) then
		return false
	end
	trap.R_SetColor(Q.colorWhite)

	local i = 0
	for counter = 0, C.WP_NUM_WEAPONS - 1 do
		if cg_weapons[counter + 2].weaponIcon ~= 0 and counter ~= C.WP_PROX_LAUNCHER and counter ~= C.WP_GRAPPLING_HOOK then
			i += 1
		end
	end

	G.CG_DrawTeamBackground(ACCBOARD_XPOS, ACCBOARD_YPOS, 75, ACCBOARD_HEIGHT * (i + 1), 0.33, C.TEAM_BLUE)

	i = 0

	for counter = 0, C.WP_NUM_WEAPONS - 1 do
		if cg_weapons[counter + 2].weaponIcon ~= 0 and counter ~= C.WP_PROX_LAUNCHER and counter ~= C.WP_GRAPPLING_HOOK then
			G.CG_DrawPic(ACCBOARD_XPOS + 10, ACCBOARD_YPOS + 10 + i * ACCBOARD_HEIGHT, ACCITEM_SIZE, ACCITEM_SIZE, cg_weapons[counter + 2].weaponIcon)
			local ty = ACCBOARD_YPOS + 10 + i * ACCBOARD_HEIGHT + Q.idiv(ACCITEM_SIZE, 2) - Q.idiv(C.SMALLCHAR_HEIGHT, 2)
			if cg.accuracys[counter][0] > 0 then
				G.CG_DrawSmallStringColor(ACCBOARD_XPOS + 10 + ACCITEM_SIZE + 10, ty,
					Q.va("%i%s", Q.int((cg.accuracys[counter][1] * 100) / cg.accuracys[counter][0]), "%"), Q.colorWhite)
			else
				G.CG_DrawSmallStringColor(ACCBOARD_XPOS + 10 + ACCITEM_SIZE + 10, ty, "-%", Q.colorWhite)
			end
			i += 1
		end
	end

	trap.R_SetColor(nil)
	return true
end

function G.CG_DrawIntermission()
	local cg = G.cg
	if G.cgs.gametype == C.GT_SINGLE_PLAYER then
		G.CG_DrawCenterString()
		return
	end
	cg.scoreFadeTime = cg.time
	cg.scoreBoardShowing = G.CG_DrawScoreboard()
end

function G.CG_DrawFollow()
	local cg = G.cg
	if bit32.band(cg.snap.ps.pm_flags, C.PMF_FOLLOW) == 0 then
		return false
	end
	local color = Q.vec4(1, 1, 1, 1)

	G.CG_DrawBigString(320 - 9 * 8, 24, "following", 1.0)

	local name = G.cgs.clientinfo[cg.snap.ps.clientNum].name

	local x = 0.5 * (640 - C.GIANT_WIDTH * G.CG_DrawStrlen(name))

	G.CG_DrawStringExt(x, 40, name, color, true, true, C.GIANT_WIDTH, C.GIANT_HEIGHT, 0)

	return true
end

function G.CG_DrawAmmoWarning()
	local cg = G.cg

	-- Don't report in instant gib same with RA
	if isSet(G.cgs.nopickup) then
		return
	end

	if G.cg_drawAmmoWarning.integer == 0 then
		return
	end

	if cg.lowAmmoWarning == 0 then
		return
	end

	local s
	if cg.lowAmmoWarning == 2 then
		s = "OUT OF AMMO"
	else
		s = "LOW AMMO WARNING"
	end
	local w = G.CG_DrawStrlen(s) * C.BIGCHAR_WIDTH
	G.CG_DrawBigString(320 - Q.idiv(w, 2), 64, s, 1.0)
end

function G.CG_DrawProxWarning()
	local cg = G.cg

	if bit32.band(cg.snap.ps.eFlags, C.EF_TICKING) == 0 then
		proxTime = 0
		return
	end

	if proxTime == 0 then
		proxTime = cg.time + 5000
		proxCounter = 5
		proxTick = 0
	end

	if cg.time > proxTime then
		proxTick = proxCounter
		proxCounter -= 1
		proxTime = cg.time + 1000
	end

	local s
	if proxTick ~= 0 then
		s = Q.va("INTERNAL COMBUSTION IN: %i", proxTick)
	else
		s = "YOU HAVE BEEN MINED"
	end

	local w = G.CG_DrawStrlen(s) * C.BIGCHAR_WIDTH
	G.CG_DrawBigStringColor(320 - Q.idiv(w, 2), 64 + C.BIGCHAR_HEIGHT, s, Q.g_color_table[Q.ColorIndex(C.COLOR_RED)])
end

function G.CG_DrawWarmup()
	local cg = G.cg
	local cgs = G.cgs
	local w, cw, s

	local sec = cg.warmup
	if sec == 0 then
		return
	end

	if sec < 0 then
		s = "Waiting for players"
		w = G.CG_DrawStrlen(s) * C.BIGCHAR_WIDTH
		G.CG_DrawBigString(320 - Q.idiv(w, 2), 24, s, 1.0)
		cg.warmupCount = 0
		return
	end

	if cgs.gametype == C.GT_TOURNAMENT then
		-- find the two active players
		local ci1 = nil
		local ci2 = nil
		for i = 0, cgs.maxclients - 1 do
			if isSet(cgs.clientinfo[i].infoValid) and cgs.clientinfo[i].team == C.TEAM_FREE then
				if ci1 == nil then
					ci1 = cgs.clientinfo[i]
				else
					ci2 = cgs.clientinfo[i]
				end
			end
		end

		if ci1 ~= nil and ci2 ~= nil then
			s = Q.va("%s vs %s", ci1.name, ci2.name)
			w = G.CG_DrawStrlen(s)
			if w > Q.idiv(640, C.GIANT_WIDTH) then
				cw = Q.idiv(640, w)
			else
				cw = C.GIANT_WIDTH
			end
			G.CG_DrawStringExt(320 - Q.idiv(w * cw, 2), 20, s, Q.colorWhite,
				false, true, cw, Q.int(cw * 1.5), 0)
		end
	else
		local gt = cgs.gametype
		if gt == C.GT_FFA then
			s = "Free For All"
		elseif gt == C.GT_TEAM then
			s = "Team Deathmatch"
		elseif gt == C.GT_CTF then
			s = "Capture the Flag"
		elseif gt == C.GT_ELIMINATION then
			s = "Elimination"
		elseif gt == C.GT_CTF_ELIMINATION then
			s = "CTF Elimination"
		elseif gt == C.GT_LMS then
			s = "Last Man Standing"
		elseif gt == C.GT_DOUBLE_D then
			s = "Double Domination"
		elseif gt == C.GT_1FCTF then
			s = "One Flag CTF"
		elseif gt == C.GT_OBELISK then
			s = "Overload"
		elseif gt == C.GT_HARVESTER then
			s = "Harvester"
		elseif gt == C.GT_DOMINATION then
			s = "Domination"
		else
			s = ""
		end
		w = G.CG_DrawStrlen(s)
		if w > Q.idiv(640, C.GIANT_WIDTH) then
			cw = Q.idiv(640, w)
		else
			cw = C.GIANT_WIDTH
		end
		G.CG_DrawStringExt(320 - Q.idiv(w * cw, 2), 25, s, Q.colorWhite,
			false, true, cw, Q.int(cw * 1.1), 0)
	end

	sec = Q.idiv(sec - cg.time, 1000)
	if sec < 0 then
		cg.warmup = 0
		sec = 0
	end
	s = Q.va("Starts in: %i", sec + 1)
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
	if cg.warmupCount == 0 then
		cw = 28
	elseif cg.warmupCount == 1 then
		cw = 24
	elseif cg.warmupCount == 2 then
		cw = 20
	else
		cw = 16
	end

	w = G.CG_DrawStrlen(s)
	G.CG_DrawStringExt(320 - Q.idiv(w * cw, 2), 70, s, Q.colorWhite,
		false, true, cw, Q.int(cw * 1.5), 0)
end

function G.CG_Draw2D(stereoFrame)
	local cg = G.cg
	local cgs = G.cgs

	-- if we are taking a levelshot for the menu, don't draw anything
	if isSet(cg.levelShot) then
		return
	end

	if G.cg_draw2D.integer == 0 then
		return
	end

	if cg.snap.ps.pm_type == C.PM_INTERMISSION then
		G.CG_DrawIntermission()
		return
	end

	if cg.snap.ps.persistant[C.PERS_TEAM] == C.TEAM_SPECTATOR then
		G.CG_DrawSpectator()

		if stereoFrame == C.STEREO_CENTER then
			G.CG_DrawCrosshair()
		end

		G.CG_DrawCrosshairNames()
	else
		-- don't draw any status if dead or the scoreboard is being explicitly shown
		if not isSet(cg.showScores) and cg.snap.ps.stats[C.STAT_HEALTH] > 0 then
			G.CG_DrawStatusBar()

			G.CG_DrawAmmoWarning()

			G.CG_DrawProxWarning()
			if stereoFrame == C.STEREO_CENTER then
				G.CG_DrawCrosshair()
			end
			G.CG_DrawCrosshairNames()
			G.CG_DrawWeaponSelect()

			G.CG_DrawHoldableItem()
			G.CG_DrawPersistantPowerup()

			G.CG_DrawReward()
		end

		if cgs.gametype >= C.GT_TEAM and cgs.ffa_gt ~= 1 then
			G.CG_DrawTeamInfo()
		end
	end

	G.CG_DrawVote()
	G.CG_DrawTeamVote()

	G.CG_DrawLagometer()

	G.CG_DrawUpperRight(stereoFrame)

	G.CG_DrawLowerRight()
	G.CG_DrawLowerLeft()

	if not G.CG_DrawFollow() then
		G.CG_DrawWarmup()
	end

	-- don't draw center string if scoreboard is up
	cg.scoreBoardShowing = G.CG_DrawScoreboard()
	if not isSet(cg.scoreBoardShowing) then
		G.CG_DrawCenterDDString()
		G.CG_DrawCenter1FctfString()
		G.CG_DrawCenterString()
	end

	cg.accBoardShowing = G.CG_DrawAccboard()
end

function G.CG_DrawTourneyScoreboard()
	G.CG_DrawOldTourneyScoreboard()
end

function G.CG_DrawActive(stereoView)
	local cg = G.cg

	-- optionally draw the info screen instead
	if cg.snap == nil then
		G.CG_DrawInformation()
		return
	end

	-- optionally draw the tournement scoreboard instead
	if cg.snap.ps.persistant[C.PERS_TEAM] == C.TEAM_SPECTATOR
		and bit32.band(cg.snap.ps.pm_flags, C.PMF_SCOREBOARD) ~= 0 then
		G.CG_DrawTourneyScoreboard()
		return
	end

	-- clear around the rendered view if sized down
	G.CG_TileClear()

	if stereoView ~= C.STEREO_CENTER then
		G.CG_DrawCrosshair3D()
	end

	-- draw 3D view
	trap.R_RenderScene(cg.refdef)

	-- draw status bar and other floating elements
	G.CG_Draw2D(stereoView)
end

return G
