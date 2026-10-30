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
-- Luau port of code/cgame/cg_scoreboard.c (OpenArena 0.8.8, gamecode 9e0f0c0).
-- cg_scoreboard -- draw the scoreboard on top of the game screen

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local trap = require(script.Parent.Parent.sys.Trap)
local Screen = require(script.Parent.Parent.Parent.ui.Screen)

local SCOREBOARD_X = 0

local SB_HEADER = 86
local SB_TOP = SB_HEADER + 32

-- Where the status bar starts, so we don't overwrite it
local SB_STATUSBAR = 420

local SB_NORMAL_HEIGHT = 40
local SB_INTER_HEIGHT = 16 -- interleaved height

local SB_MAXCLIENTS_NORMAL = Q.idiv(SB_STATUSBAR - SB_TOP, SB_NORMAL_HEIGHT)
local SB_MAXCLIENTS_INTER = Q.idiv(SB_STATUSBAR - SB_TOP, SB_INTER_HEIGHT) - 1

-- Normal
local SB_BOTICON_X = SCOREBOARD_X + 32
local SB_HEAD_X = SCOREBOARD_X + 64

local SB_SCORELINE_X = 112

local SB_RATING_WIDTH = 6 * C.BIGCHAR_WIDTH
local SB_SCORE_X = SB_SCORELINE_X + C.BIGCHAR_WIDTH
local SB_PING_X = SB_SCORELINE_X + 12 * C.BIGCHAR_WIDTH + 8
local SB_TIME_X = SB_SCORELINE_X + 17 * C.BIGCHAR_WIDTH + 8
local SB_NAME_X = SB_SCORELINE_X + 22 * C.BIGCHAR_WIDTH

local localClient = false -- true if local client has been displayed

local function CG_DrawClientScore(y, score, color, fade, largeFormat)
	local cg = G.cg
	local cgs = G.cgs
	local string

	if score.client < 0 or score.client >= cgs.maxclients then
		trap.Print(Q.va("Bad score->client: %i\n", score.client))
		return
	end

	local ci = cgs.clientinfo[score.client]

	local iconx = SB_BOTICON_X + Q.idiv(SB_RATING_WIDTH, 2)
	local headx = SB_HEAD_X + Q.idiv(SB_RATING_WIDTH, 2)
	local bigOff = Q.idiv(32 - C.BIGCHAR_HEIGHT, 2)

	-- draw the handicap or bot skill marker (unless player has flag)
	local flagTeam = nil
	if bit32.band(ci.powerups, bit32.lshift(1, C.PW_NEUTRALFLAG)) ~= 0 then
		flagTeam = C.TEAM_FREE
	elseif bit32.band(ci.powerups, bit32.lshift(1, C.PW_REDFLAG)) ~= 0 then
		flagTeam = C.TEAM_RED
	elseif bit32.band(ci.powerups, bit32.lshift(1, C.PW_BLUEFLAG)) ~= 0 then
		flagTeam = C.TEAM_BLUE
	end

	if flagTeam ~= nil then
		if largeFormat then
			G.CG_DrawFlagModel(iconx, y - bigOff, 32, 32, flagTeam, false)
		else
			G.CG_DrawFlagModel(iconx, y, 16, 16, flagTeam, false)
		end
	else
		if ci.botSkill > 0 and ci.botSkill <= 5 then
			if G.cg_drawIcons.integer ~= 0 then
				if largeFormat then
					G.CG_DrawPic(iconx, y - bigOff, 32, 32, cgs.media.botSkillShaders[ci.botSkill - 1])
				else
					G.CG_DrawPic(iconx, y, 16, 16, cgs.media.botSkillShaders[ci.botSkill - 1])
				end
			end
		elseif ci.handicap < 100 then
			string = Q.va("%i", ci.handicap)
			if cgs.gametype == C.GT_TOURNAMENT then
				G.CG_DrawSmallStringColor(iconx, y - Q.idiv(C.SMALLCHAR_HEIGHT, 2), string, color)
			else
				G.CG_DrawSmallStringColor(iconx, y, string, color)
			end
		end

		-- draw the wins / losses
		if cgs.gametype == C.GT_TOURNAMENT then
			string = Q.va("%i/%i", ci.wins, ci.losses)
			if ci.handicap < 100 and ci.botSkill == 0 then
				G.CG_DrawSmallStringColor(iconx, y + Q.idiv(C.SMALLCHAR_HEIGHT, 2), string, color)
			else
				G.CG_DrawSmallStringColor(iconx, y, string, color)
			end
		end
	end

	-- draw the face
	local headAngles = Q.vec3(0, 0, 0)
	headAngles[C.YAW] = 180
	if largeFormat then
		G.CG_DrawHead(headx, y - Q.idiv(C.ICON_SIZE - C.BIGCHAR_HEIGHT, 2), C.ICON_SIZE, C.ICON_SIZE, score.client, headAngles)
	else
		G.CG_DrawHead(headx, y, 16, 16, score.client, headAngles)
	end

	-- draw the score line
	if score.ping == -1 then
		string = Q.va(" connecting    %s", ci.name)
	elseif ci.team == C.TEAM_SPECTATOR then
		string = Q.va(" SPECT %3i %4i %s", score.ping, score.time, ci.name)
	else
		string = Q.va("%5i %4i %4i %s", score.score, score.ping, score.time, ci.name)
	end

	-- highlight your position
	if score.client == cg.snap.ps.clientNum then
		local hcolor = Q.vec4(0, 0, 0, 0)
		local rank

		localClient = true

		if cg.snap.ps.persistant[C.PERS_TEAM] == C.TEAM_SPECTATOR
			or (cgs.gametype >= C.GT_TEAM and cgs.ffa_gt ~= 1) then
			-- it doesn't matter if two players are tied in team game - only team score counts
			rank = -1
		else
			rank = bit32.band(cg.snap.ps.persistant[C.PERS_RANK], bit32.bnot(C.RANK_TIED_FLAG))
		end
		if rank == 0 then
			hcolor[0] = 0
			hcolor[1] = 0
			hcolor[2] = 0.7
		elseif rank == 1 then
			hcolor[0] = 0.7
			hcolor[1] = 0
			hcolor[2] = 0
		elseif rank == 2 then
			hcolor[0] = 0.7
			hcolor[1] = 0.7
			hcolor[2] = 0
		else
			hcolor[0] = 0.7
			hcolor[1] = 0.7
			hcolor[2] = 0.7
		end

		hcolor[3] = fade * 0.7
		G.CG_FillRect(SB_SCORELINE_X + C.BIGCHAR_WIDTH + Q.idiv(SB_RATING_WIDTH, 2), y,
			640 - SB_SCORELINE_X - C.BIGCHAR_WIDTH, C.BIGCHAR_HEIGHT + 1, hcolor)
	end

	G.CG_DrawBigString(SB_SCORELINE_X + Q.idiv(SB_RATING_WIDTH, 2), y, string, fade)

	-- add the "ready" marker for intermission exiting
	if bit32.band(cg.snap.ps.stats[C.STAT_CLIENTS_READY], bit32.lshift(1, score.client)) ~= 0 then
		G.CG_DrawBigStringColor(iconx, y, "READY", color)
	elseif cgs.gametype == C.GT_LMS then
		G.CG_DrawBigStringColor(iconx - 50, y, Q.va("*%i*", ci.isDead), color)
	elseif ci.isDead ~= 0 then
		G.CG_DrawBigStringColor(iconx - 60, y, "DEAD", color)
	end
end

local function CG_TeamScoreboard(y, team, fade, maxClients, lineHeight)
	local cg = G.cg
	local color = Q.vec4(1.0, 1.0, 1.0, fade)

	local count = 0
	local i = 0
	while i < cg.numScores and count < maxClients do
		local score = cg.scores[i]
		local ci = G.cgs.clientinfo[score.client]

		if team == ci.team then
			CG_DrawClientScore(y + lineHeight * count, score, color, fade, lineHeight == SB_NORMAL_HEIGHT)
			count += 1
		end
		i += 1
	end

	return count
end

-- Draw the normal in-game scoreboard
function G.CG_DrawOldScoreboard()
	local cg = G.cg
	local cgs = G.cgs
	local x, y, w, n1, n2
	local fade
	local fadeColor
	local s
	local maxClients
	local lineHeight
	local topBorderSize, bottomBorderSize

	-- don't draw amuthing if the menu or console is up
	if G.cg_paused.integer ~= 0 then
		cg.deferredPlayerLoading = 0
		return false
	end

	if cgs.gametype == C.GT_SINGLE_PLAYER and cg.predictedPlayerState.pm_type == C.PM_INTERMISSION then
		cg.deferredPlayerLoading = 0
		return false
	end

	-- don't draw scoreboard during death while warmup up
	if cg.warmup ~= 0 and not cg.showScores then
		return false
	end

	if cg.showScores or cg.predictedPlayerState.pm_type == C.PM_DEAD
		or cg.predictedPlayerState.pm_type == C.PM_INTERMISSION then
		fade = 1.0
		fadeColor = Q.colorWhite
	else
		fadeColor = G.CG_FadeColor(cg.scoreFadeTime, C.FADE_TIME)

		if fadeColor == nil then
			-- next time scoreboard comes up, don't print killer
			cg.deferredPlayerLoading = 0
			cg.killerName = ""
			return false
		end
		fade = fadeColor[0]
	end

	-- fragged by ... line
	if cg.killerName ~= "" then
		s = Q.va("Fragged by %s", cg.killerName)
		w = G.CG_DrawStrlen(s) * C.BIGCHAR_WIDTH
		x = Q.idiv(C.SCREEN_WIDTH - w, 2)
		y = 40
		G.CG_DrawBigString(x, y, s, fade)
	end

	-- current rank
	if cgs.gametype < C.GT_TEAM or cgs.ffa_gt == 1 then
		if cg.snap.ps.persistant[C.PERS_TEAM] ~= C.TEAM_SPECTATOR then
			s = Q.va("%s place with %i",
				G.CG_PlaceString(cg.snap.ps.persistant[C.PERS_RANK] + 1),
				cg.snap.ps.persistant[C.PERS_SCORE])
			w = G.CG_DrawStrlen(s) * C.BIGCHAR_WIDTH
			x = Q.idiv(C.SCREEN_WIDTH - w, 2)
			y = 60
			G.CG_DrawBigString(x, y, s, fade)
		end
	else
		if cg.teamScores[0] == cg.teamScores[1] then
			s = Q.va("Teams are tied at %i", cg.teamScores[0])
		elseif cg.teamScores[0] >= cg.teamScores[1] then
			s = Q.va("Red leads %i to %i", cg.teamScores[0], cg.teamScores[1])
		else
			s = Q.va("Blue leads %i to %i", cg.teamScores[1], cg.teamScores[0])
		end

		w = G.CG_DrawStrlen(s) * C.BIGCHAR_WIDTH
		x = Q.idiv(C.SCREEN_WIDTH - w, 2)
		y = 60
		G.CG_DrawBigString(x, y, s, fade)
	end

	-- scoreboard
	y = SB_HEADER

	G.CG_DrawPic(SB_SCORE_X + Q.idiv(SB_RATING_WIDTH, 2), y, 64, 32, cgs.media.scoreboardScore)
	G.CG_DrawPic(SB_PING_X - Q.idiv(SB_RATING_WIDTH, 2), y, 64, 32, cgs.media.scoreboardPing)
	G.CG_DrawPic(SB_TIME_X - Q.idiv(SB_RATING_WIDTH, 2), y, 64, 32, cgs.media.scoreboardTime)
	G.CG_DrawPic(SB_NAME_X - Q.idiv(SB_RATING_WIDTH, 2), y, 64, 32, cgs.media.scoreboardName)

	y = SB_TOP

	-- If there are more than SB_MAXCLIENTS_NORMAL, use the interleaved scores
	if cg.numScores > SB_MAXCLIENTS_NORMAL then
		maxClients = SB_MAXCLIENTS_INTER
		lineHeight = SB_INTER_HEIGHT
		topBorderSize = 8
		bottomBorderSize = 16
	else
		maxClients = SB_MAXCLIENTS_NORMAL
		lineHeight = SB_NORMAL_HEIGHT
		topBorderSize = 16
		bottomBorderSize = 16
	end

	localClient = false

	if cgs.gametype >= C.GT_TEAM and cgs.ffa_gt ~= 1 then
		-- teamplay scoreboard
		y += Q.idiv(lineHeight, 2)

		if cg.teamScores[0] >= cg.teamScores[1] then
			n1 = CG_TeamScoreboard(y, C.TEAM_RED, fade, maxClients, lineHeight)
			G.CG_DrawTeamBackground(0, y - topBorderSize, 640, n1 * lineHeight + bottomBorderSize, 0.33, C.TEAM_RED)
			y += (n1 * lineHeight) + C.BIGCHAR_HEIGHT
			maxClients -= n1
			n2 = CG_TeamScoreboard(y, C.TEAM_BLUE, fade, maxClients, lineHeight)
			G.CG_DrawTeamBackground(0, y - topBorderSize, 640, n2 * lineHeight + bottomBorderSize, 0.33, C.TEAM_BLUE)
			y += (n2 * lineHeight) + C.BIGCHAR_HEIGHT
			maxClients -= n2
		else
			n1 = CG_TeamScoreboard(y, C.TEAM_BLUE, fade, maxClients, lineHeight)
			G.CG_DrawTeamBackground(0, y - topBorderSize, 640, n1 * lineHeight + bottomBorderSize, 0.33, C.TEAM_BLUE)
			y += (n1 * lineHeight) + C.BIGCHAR_HEIGHT
			maxClients -= n1
			n2 = CG_TeamScoreboard(y, C.TEAM_RED, fade, maxClients, lineHeight)
			G.CG_DrawTeamBackground(0, y - topBorderSize, 640, n2 * lineHeight + bottomBorderSize, 0.33, C.TEAM_RED)
			y += (n2 * lineHeight) + C.BIGCHAR_HEIGHT
			maxClients -= n2
		end
		n1 = CG_TeamScoreboard(y, C.TEAM_SPECTATOR, fade, maxClients, lineHeight)
		y += (n1 * lineHeight) + C.BIGCHAR_HEIGHT
	else
		-- free for all scoreboard
		n1 = CG_TeamScoreboard(y, C.TEAM_FREE, fade, maxClients, lineHeight)
		y += (n1 * lineHeight) + C.BIGCHAR_HEIGHT
		n2 = CG_TeamScoreboard(y, C.TEAM_SPECTATOR, fade, maxClients - n1, lineHeight)
		y += (n2 * lineHeight) + C.BIGCHAR_HEIGHT
	end

	if not localClient then
		-- draw local client at the bottom
		for i = 0, cg.numScores - 1 do
			if cg.scores[i].client == cg.snap.ps.clientNum then
				CG_DrawClientScore(y, cg.scores[i], fadeColor, fade, lineHeight == SB_NORMAL_HEIGHT)
				break
			end
		end
	end

	-- load any models that have been deferred
	cg.deferredPlayerLoading += 1
	if cg.deferredPlayerLoading > 10 then
		G.CG_LoadDeferredPlayers()
	end

	return true
end

--================================================================================

local function CG_CenterGiantLine(y, string)
	local color = Q.vec4(1, 1, 1, 1)

	local x = 0.5 * (640 - C.GIANT_WIDTH * G.CG_DrawStrlen(string))

	G.CG_DrawStringExt(x, y, string, color, true, true, C.GIANT_WIDTH, C.GIANT_HEIGHT, 0)
end

-- Draw the oversize scoreboard for tournements
function G.CG_DrawOldTourneyScoreboard()
	local cg = G.cg
	local cgs = G.cgs
	local s
	local min, tens, ones
	local y

	-- request more scores regularly
	if cg.scoresRequestTime + 2000 < cg.time then
		cg.scoresRequestTime = cg.time
		trap.SendClientCommand("score")
	end

	-- draw the dialog background
	local color = Q.vec4(0, 0, 0, 1)
	G.CG_SetScreenPlacement(Screen.STRETCH, Screen.STRETCH)
	G.CG_FillRect(0, 0, C.SCREEN_WIDTH, C.SCREEN_HEIGHT, color)
	G.CG_SetScreenPlacement(Screen.CENTER, Screen.CENTER)

	color[0] = 1
	color[1] = 1
	color[2] = 1
	color[3] = 1

	-- print the mesage of the day
	s = G.CG_ConfigString(C.CS_MOTD)
	if s == "" then
		s = "Scoreboard"
	end

	-- print optional title
	CG_CenterGiantLine(8, s)

	-- print server time
	ones = Q.idiv(cg.time, 1000)
	min = Q.idiv(ones, 60)
	ones = ones % 60
	tens = Q.idiv(ones, 10)
	ones = ones % 10
	s = Q.va("%i:%i%i", min, tens, ones)

	CG_CenterGiantLine(64, s)

	-- print the two scores

	y = 160
	if cgs.gametype >= C.GT_TEAM and cgs.ffa_gt ~= 1 then
		-- teamplay scoreboard
		G.CG_DrawStringExt(8, y, "Red Team", color, true, true, C.GIANT_WIDTH, C.GIANT_HEIGHT, 0)
		s = Q.va("%i", cg.teamScores[0])
		G.CG_DrawStringExt(632 - C.GIANT_WIDTH * #s, y, s, color, true, true, C.GIANT_WIDTH, C.GIANT_HEIGHT, 0)

		y += 64

		G.CG_DrawStringExt(8, y, "Blue Team", color, true, true, C.GIANT_WIDTH, C.GIANT_HEIGHT, 0)
		s = Q.va("%i", cg.teamScores[1])
		G.CG_DrawStringExt(632 - C.GIANT_WIDTH * #s, y, s, color, true, true, C.GIANT_WIDTH, C.GIANT_HEIGHT, 0)
	else
		-- free for all scoreboard
		for i = 0, C.MAX_CLIENTS - 1 do
			local ci = cgs.clientinfo[i]
			if ci.infoValid and ci.team == C.TEAM_FREE then
				G.CG_DrawStringExt(8, y, ci.name, color, true, true, C.GIANT_WIDTH, C.GIANT_HEIGHT, 0)
				s = Q.va("%i", ci.score)
				G.CG_DrawStringExt(632 - C.GIANT_WIDTH * #s, y, s, color, true, true, C.GIANT_WIDTH, C.GIANT_HEIGHT, 0)
				y += 64
			end
		end
	end
end

return G
