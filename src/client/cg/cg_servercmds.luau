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
-- Luau port of code/cgame/cg_servercmds.c (OpenArena gamecode).
-- cg_servercmds.c -- reliably sequenced text commands sent by the server
-- these are processed at snapshot transition time, so there will definately
-- be a valid snapshot this frame

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local trap = require(script.Parent.Parent.sys.Trap)

local MAX_VOICEFILESIZE = 16384
local MAX_VOICEFILES = 8
local MAX_VOICECHATS = 64
local MAX_VOICESOUNDS = 64
local MAX_CHATSIZE = 64
local MAX_HEADMODELS = 64
local MAX_VOICECHATBUFFER = 32

local function atoi(s: string): number
	local m = string.match(s, "^%s*([+-]?%d+)")
	if m == nil then
		return 0
	end
	return tonumber(m) :: number
end

local function charAt(s: string, i: number): number
	return string.byte(s, i + 1) or 0
end

local function isColorString(s: string, i: number): boolean
	return charAt(s, i) == 94 and charAt(s, i + 1) ~= 0 and charAt(s, i + 1) ~= 94
end

local function newVoiceChat()
	local sounds = {}
	local chats = {}
	for i = 0, MAX_VOICESOUNDS - 1 do
		sounds[i] = 0
		chats[i] = ""
	end
	return { id = "", numSounds = 0, sounds = sounds, chats = chats }
end

local function newVoiceChatList()
	local voiceChats = {}
	for i = 0, MAX_VOICECHATS - 1 do
		voiceChats[i] = newVoiceChat()
	end
	return { name = "", gender = 0, numVoiceChats = 0, voiceChats = voiceChats }
end

G.voiceChatLists = {}
for i = 0, MAX_VOICEFILES - 1 do
	G.voiceChatLists[i] = newVoiceChatList()
end

G.headModelVoiceChat = {}
for i = 0, MAX_HEADMODELS - 1 do
	G.headModelVoiceChat[i] = { headmodel = "", voiceChatNum = 0 }
end

G.voiceChatBuffer = {}
for i = 0, MAX_VOICECHATBUFFER - 1 do
	G.voiceChatBuffer[i] = { clientNum = 0, snd = 0, voiceOnly = 0, cmd = "", message = "" }
end

-- tokenizer standing in for COM_ParseExt(&ptr, qtrue); state is {s = text, i = 1-based position}
local function parseExt(state): string
	local s = state.s
	local n = #s
	local i = state.i
	while true do
		while i <= n and string.byte(s, i) <= 32 do
			i += 1
		end
		if i > n then
			state.i = i
			return ""
		end
		if string.sub(s, i, i + 1) == "//" then
			while i <= n and string.sub(s, i, i) ~= "\n" do
				i += 1
			end
		elseif string.sub(s, i, i + 1) == "/*" then
			local e = string.find(s, "*/", i + 2, true)
			if e == nil then
				i = n + 1
			else
				i = e + 2
			end
		else
			break
		end
	end
	if string.sub(s, i, i) == '"' then
		local e = string.find(s, '"', i + 1, true)
		local tok
		if e == nil then
			tok = string.sub(s, i + 1)
			i = n + 1
		else
			tok = string.sub(s, i + 1, e - 1)
			i = e + 1
		end
		state.i = i
		return tok
	end
	local st = i
	while i <= n and string.byte(s, i) > 32 do
		i += 1
	end
	state.i = i
	return string.sub(s, st, i - 1)
end

local function CG_ParseScores()
	local cg = G.cg
	local cgs = G.cgs
	local NUM_DATA = 15
	local FIRST_DATA = 4

	cg.numScores = atoi(G.CG_Argv(1))
	if cg.numScores > C.MAX_CLIENTS then
		cg.numScores = C.MAX_CLIENTS
	end

	cg.teamScores[0] = atoi(G.CG_Argv(2))
	cg.teamScores[1] = atoi(G.CG_Argv(3))

	cgs.roundStartTime = atoi(G.CG_Argv(4))

	--Update thing in lower-right corner
	if cgs.gametype == C.GT_ELIMINATION or cgs.gametype == C.GT_CTF_ELIMINATION then
		cgs.scores1 = cg.teamScores[0]
		cgs.scores2 = cg.teamScores[1]
	end

	for i = 0, C.MAX_CLIENTS - 1 do
		local sc = cg.scores[i]
		sc.client = 0
		sc.score = 0
		sc.ping = 0
		sc.time = 0
		sc.scoreFlags = 0
		sc.accuracy = 0
		sc.impressiveCount = 0
		sc.excellentCount = 0
		sc.guantletCount = 0
		sc.defendCount = 0
		sc.assistCount = 0
		sc.perfect = 0
		sc.captures = 0
		sc.isDead = 0
		sc.team = 0
	end

	for i = 0, cg.numScores - 1 do
		local sc = cg.scores[i]
		local base = i * NUM_DATA + FIRST_DATA
		sc.client = atoi(G.CG_Argv(base + 1))
		sc.score = atoi(G.CG_Argv(base + 2))
		sc.ping = atoi(G.CG_Argv(base + 3))
		sc.time = atoi(G.CG_Argv(base + 4))
		sc.scoreFlags = atoi(G.CG_Argv(base + 5))
		local powerups = atoi(G.CG_Argv(base + 6))
		sc.accuracy = atoi(G.CG_Argv(base + 7))
		sc.impressiveCount = atoi(G.CG_Argv(base + 8))
		sc.excellentCount = atoi(G.CG_Argv(base + 9))
		sc.guantletCount = atoi(G.CG_Argv(base + 10))
		sc.defendCount = atoi(G.CG_Argv(base + 11))
		sc.assistCount = atoi(G.CG_Argv(base + 12))
		sc.perfect = atoi(G.CG_Argv(base + 13))
		sc.captures = atoi(G.CG_Argv(base + 14))
		sc.isDead = atoi(G.CG_Argv(base + 15))

		if sc.client < 0 or sc.client >= C.MAX_CLIENTS then
			sc.client = 0
		end
		cgs.clientinfo[sc.client].score = sc.score
		cgs.clientinfo[sc.client].powerups = powerups
		cgs.clientinfo[sc.client].isDead = sc.isDead

		sc.team = cgs.clientinfo[sc.client].team
	end
end

local function CG_ParseAccuracy()
	local cg = G.cg
	for i = C.WP_MACHINEGUN, C.WP_NUM_WEAPONS - 1 do
		cg.accuracys[i - C.WP_MACHINEGUN][0] = atoi(G.CG_Argv((i - C.WP_MACHINEGUN) * 2 + 1))
		cg.accuracys[i - C.WP_MACHINEGUN][1] = atoi(G.CG_Argv((i - C.WP_MACHINEGUN) * 2 + 2))
	end
end

local function CG_ParseElimination()
	local cgs = G.cgs
	if cgs.gametype == C.GT_ELIMINATION or cgs.gametype == C.GT_CTF_ELIMINATION then
		cgs.scores1 = atoi(G.CG_Argv(1))
		cgs.scores2 = atoi(G.CG_Argv(2))
	end
	cgs.roundStartTime = atoi(G.CG_Argv(3))
end

local function hasBadChar(s: string): boolean
	return string.find(s, "[\n\r;]") ~= nil
end

-- Sago: This parses values from the server rather directly. Some checks are performed, but beware if you change it or new
-- security holes are found
local function CG_ParseMappage()
	local temp = G.CG_Argv(1)
	if hasBadChar(temp) then
		return
	end
	local command = string.sub(Q.va("ui_mappage %s", temp), 1, 1023)
	for i = 2, 11 do
		temp = G.CG_Argv(i)
		if hasBadChar(temp) then
			return
		end
		if #temp < 1 then
			temp = "---"
		end
		command = string.sub(command .. Q.va(" %s ", temp), 1, 1023)
	end
	trap.SendConsoleCommand(command)
end

local function CG_ParseDDtimetakeAt()
	G.cgs.takeAt = atoi(G.CG_Argv(1))
end

local function CG_ParseDomPointNames()
	local cgs = G.cgs
	cgs.domination_points_count = atoi(G.CG_Argv(1))
	if cgs.domination_points_count >= C.MAX_DOMINATION_POINTS then
		cgs.domination_points_count = C.MAX_DOMINATION_POINTS
	end
	for i = 0, cgs.domination_points_count - 1 do
		local name = string.sub(
			G.CG_Argv(2),
			i * C.MAX_DOMINATION_POINTS_NAMES + 1,
			i * C.MAX_DOMINATION_POINTS_NAMES + C.MAX_DOMINATION_POINTS_NAMES - 1
		)
		local j = #name
		while j > 1 and string.byte(name, j) < 48 do
			j -= 1
		end
		cgs.domination_points_names[i] = string.sub(name, 1, j)
	end
end

local function CG_ParseDomStatus()
	local cgs = G.cgs
	if cgs.domination_points_count ~= atoi(G.CG_Argv(1)) then
		cgs.domination_points_count = 0
		return
	end
	for i = 0, cgs.domination_points_count - 1 do
		cgs.domination_points_status[i] = atoi(G.CG_Argv(2 + i))
	end
end

local function CG_ParseChallenge()
	G.addChallenge(atoi(G.CG_Argv(1)))
end

local function CG_ParseObeliskHealth()
	G.cg.redObeliskHealth = atoi(G.CG_Argv(1))
	G.cg.blueObeliskHealth = atoi(G.CG_Argv(2))
end

-- Sets the respawn counter for the client.
local function CG_ParseRespawnTime()
	G.cg.respawnTime = atoi(G.CG_Argv(1))
end

local function CG_ParseTeam()
	if G.cg_voip_teamonly.integer ~= 0 then
		trap.Cvar_Set("cl_voipSendTarget", G.CG_Argv(1))
	end
end

local function CG_ParseAttackingTeam()
	local temp = atoi(G.CG_Argv(1))
	if temp == C.TEAM_RED then
		G.cgs.attackingTeam = C.TEAM_RED
	elseif temp == C.TEAM_BLUE then
		G.cgs.attackingTeam = C.TEAM_BLUE
	else
		G.cgs.attackingTeam = C.TEAM_NONE --Should never happen.
	end
end

local function CG_ParseTeamInfo()
	local cgs = G.cgs

	G.numSortedTeamPlayers = atoi(G.CG_Argv(1))
	if G.numSortedTeamPlayers < 0 or G.numSortedTeamPlayers > C.TEAM_MAXOVERLAY then
		G.CG_Error(Q.va("CG_ParseTeamInfo: numSortedTeamPlayers out of range (%d)", G.numSortedTeamPlayers))
		return
	end

	for i = 0, G.numSortedTeamPlayers - 1 do
		local client = atoi(G.CG_Argv(i * 6 + 2))
		if client < 0 or client >= C.MAX_CLIENTS then
			G.CG_Error(Q.va("CG_ParseTeamInfo: bad client number: %d", client))
			return
		end

		G.sortedTeamPlayers[i] = client

		cgs.clientinfo[client].location = atoi(G.CG_Argv(i * 6 + 3))
		cgs.clientinfo[client].health = atoi(G.CG_Argv(i * 6 + 4))
		cgs.clientinfo[client].armor = atoi(G.CG_Argv(i * 6 + 5))
		cgs.clientinfo[client].curWeapon = atoi(G.CG_Argv(i * 6 + 6))
		cgs.clientinfo[client].powerups = atoi(G.CG_Argv(i * 6 + 7))
	end
end

--[[
This is called explicitly when the gamestate is first received,
and whenever the server updates any serverinfo flagged cvars
]]
function G.CG_ParseServerinfo()
	local cgs = G.cgs
	local info = G.CG_ConfigString(C.CS_SERVERINFO)
	local function val(key: string): number
		return atoi(Q.Info_ValueForKey(info, key))
	end
	cgs.gametype = val("g_gametype")
	--By default do as normal:
	cgs.ffa_gt = 0
	--See if ffa gametype
	if cgs.gametype == C.GT_LMS or cgs.gametype == C.GT_POSSESSION then
		cgs.ffa_gt = 1
	end
	trap.Cvar_Set("g_gametype", Q.va("%i", cgs.gametype))
	cgs.dmflags = val("dmflags")
	cgs.videoflags = val("videoflags")
	cgs.elimflags = val("elimflags")
	cgs.teamflags = val("teamflags")
	cgs.fraglimit = val("fraglimit")
	cgs.capturelimit = val("capturelimit")
	cgs.timelimit = val("timelimit")
	cgs.maxclients = val("sv_maxclients")
	cgs.roundtime = val("elimination_roundtime")
	cgs.nopickup = val("g_rockets") + val("g_instantgib") + val("g_elimination")
	cgs.lms_mode = val("g_lms_mode")
	cgs.altExcellent = val("g_altExcellent")
	local mapname = Q.Info_ValueForKey(info, "mapname")
	cgs.mapname = Q.va("maps/%s.bsp", mapname)
	cgs.redTeam = Q.Info_ValueForKey(info, "g_redTeam")
	trap.Cvar_Set("g_redTeam", cgs.redTeam)
	cgs.blueTeam = Q.Info_ValueForKey(info, "g_blueTeam")
	trap.Cvar_Set("g_blueTeam", cgs.blueTeam)

	-- we'll need this for deciding whether or not to predict weapon effects
	cgs.delagHitscan = val("g_delagHitscan")
	trap.Cvar_Set("g_delagHitscan", Q.va("%i", cgs.delagHitscan))

	--Copy allowed votes directly to the client:
	trap.Cvar_Set("cg_voteflags", Q.Info_ValueForKey(info, "voteflags"))
end

local function CG_ParseWarmup()
	local cg = G.cg
	local info = G.CG_ConfigString(C.CS_WARMUP)

	local warmup = atoi(info)
	cg.warmupCount = -1

	if warmup == 0 and cg.warmup ~= 0 then
		-- nothing
	elseif warmup > 0 and cg.warmup <= 0 then
		trap.S_StartLocalSound(G.cgs.media.countPrepareSound, C.CHAN_ANNOUNCER)
	end

	cg.warmup = warmup
end

-- Called on load to set the initial values from configure strings
function G.CG_SetConfigValues()
	local cgs = G.cgs

	cgs.scores1 = atoi(G.CG_ConfigString(C.CS_SCORES1))
	cgs.scores2 = atoi(G.CG_ConfigString(C.CS_SCORES2))
	cgs.levelStartTime = atoi(G.CG_ConfigString(C.CS_LEVEL_START_TIME))
	if cgs.gametype == C.GT_CTF or cgs.gametype == C.GT_CTF_ELIMINATION or cgs.gametype == C.GT_DOUBLE_D then
		local s = G.CG_ConfigString(C.CS_FLAGSTATUS)
		cgs.redflag = charAt(s, 0) - 48
		cgs.blueflag = charAt(s, 1) - 48
	elseif cgs.gametype == C.GT_1FCTF or cgs.gametype == C.GT_POSSESSION then
		local s = G.CG_ConfigString(C.CS_FLAGSTATUS)
		cgs.flagStatus = charAt(s, 0) - 48
	end
	G.cg.warmup = atoi(G.CG_ConfigString(C.CS_WARMUP))
end

function G.CG_ShaderStateChanged()
	local o = G.CG_ConfigString(C.CS_SHADERSTATE)
	local pos = 1
	while pos <= #o do
		local n = string.find(o, "=", pos, true)
		if n ~= nil then
			local originalShader = string.sub(o, pos, n - 1)
			n += 1
			local t = string.find(o, ":", n, true)
			local newShader
			if t ~= nil then
				newShader = string.sub(o, n, t - 1)
			else
				break
			end
			t += 1
			local at = string.find(o, "@", t, true)
			if at ~= nil then
				local timeOffset = string.sub(o, t, at - 1)
				pos = at + 1
				trap.R_RemapShader(originalShader, newShader, timeOffset)
			else
				break
			end
		else
			break
		end
	end
end

local function CG_AddToTeamChat(str: string)
	local cg = G.cg
	local cgs = G.cgs
	local chatHeight
	if G.cg_teamChatHeight.integer < C.TEAMCHAT_HEIGHT then
		chatHeight = G.cg_teamChatHeight.integer
	else
		chatHeight = C.TEAMCHAT_HEIGHT
	end

	if chatHeight <= 0 or G.cg_teamChatTime.integer <= 0 then
		-- team chat disabled, dump into normal chat
		cgs.teamChatPos = 0
		cgs.teamLastChatPos = 0
		return
	end

	local len = 0
	local cur: { string } = {}
	local n = 0
	local lastcolor = "7"
	local ls: number? = nil
	local si = 0
	local slen = #str

	while si < slen do
		if len > C.TEAMCHAT_WIDTH - 1 then
			if ls ~= nil then
				si = si - (n - ls)
				si += 1
				n = ls
			end
			cgs.teamChatMsgs[cgs.teamChatPos % chatHeight] = table.concat(cur, "", 1, n)
			cgs.teamChatMsgTimes[cgs.teamChatPos % chatHeight] = cg.time

			cgs.teamChatPos += 1
			cur = { "^", lastcolor }
			n = 2
			len = 0
			ls = nil
		end

		if isColorString(str, si) then
			n += 1
			cur[n] = string.sub(str, si + 1, si + 1)
			si += 1
			lastcolor = string.sub(str, si + 1, si + 1)
			n += 1
			cur[n] = lastcolor
			si += 1
			continue
		end
		if string.sub(str, si + 1, si + 1) == " " then
			ls = n
		end
		n += 1
		cur[n] = string.sub(str, si + 1, si + 1)
		si += 1
		len += 1
	end
	cgs.teamChatMsgs[cgs.teamChatPos % chatHeight] = table.concat(cur, "", 1, n)

	cgs.teamChatMsgTimes[cgs.teamChatPos % chatHeight] = cg.time
	cgs.teamChatPos += 1

	if cgs.teamChatPos - cgs.teamLastChatPos > chatHeight then
		cgs.teamLastChatPos = cgs.teamChatPos - chatHeight
	end
end

local function CG_ConfigStringModified()
	local cg = G.cg
	local cgs = G.cgs

	local num = atoi(G.CG_Argv(1))

	-- get the gamestate from the client system, which will have the
	-- new configstring already integrated
	trap.GetGameState(cgs.gameState)

	-- look up the individual string that was modified
	local str = G.CG_ConfigString(num)

	-- do something with it if necessary
	if num == C.CS_MUSIC then
		G.CG_StartMusic()
	elseif num == C.CS_SERVERINFO then
		G.CG_ParseServerinfo()
	elseif num == C.CS_WARMUP then
		CG_ParseWarmup()
	elseif num == C.CS_SCORES1 then
		cgs.scores1 = atoi(str)
	elseif num == C.CS_SCORES2 then
		cgs.scores2 = atoi(str)
	elseif num == C.CS_LEVEL_START_TIME then
		cgs.levelStartTime = atoi(str)
	elseif num == C.CS_VOTE_TIME then
		cgs.voteTime = atoi(str)
		cgs.voteModified = true
	elseif num == C.CS_VOTE_YES then
		cgs.voteYes = atoi(str)
		cgs.voteModified = true
	elseif num == C.CS_VOTE_NO then
		cgs.voteNo = atoi(str)
		cgs.voteModified = true
	elseif num == C.CS_VOTE_STRING then
		cgs.voteString = string.sub(str, 1, C.MAX_STRING_TOKENS - 1)
	elseif num >= C.CS_TEAMVOTE_TIME and num <= C.CS_TEAMVOTE_TIME + 1 then
		cgs.teamVoteTime[num - C.CS_TEAMVOTE_TIME] = atoi(str)
		cgs.teamVoteModified[num - C.CS_TEAMVOTE_TIME] = true
	elseif num >= C.CS_TEAMVOTE_YES and num <= C.CS_TEAMVOTE_YES + 1 then
		cgs.teamVoteYes[num - C.CS_TEAMVOTE_YES] = atoi(str)
		cgs.teamVoteModified[num - C.CS_TEAMVOTE_YES] = true
	elseif num >= C.CS_TEAMVOTE_NO and num <= C.CS_TEAMVOTE_NO + 1 then
		cgs.teamVoteNo[num - C.CS_TEAMVOTE_NO] = atoi(str)
		cgs.teamVoteModified[num - C.CS_TEAMVOTE_NO] = true
	elseif num >= C.CS_TEAMVOTE_STRING and num <= C.CS_TEAMVOTE_STRING + 1 then
		cgs.teamVoteString[num - C.CS_TEAMVOTE_STRING] = string.sub(str, 1, C.MAX_STRING_TOKENS - 1)
	elseif num == C.CS_INTERMISSION then
		cg.intermissionStarted = atoi(str) ~= 0
	elseif num >= C.CS_MODELS and num < C.CS_MODELS + C.MAX_MODELS then
		cgs.gameModels[num - C.CS_MODELS] = trap.R_RegisterModel(str)
	elseif num >= C.CS_SOUNDS and num < C.CS_SOUNDS + C.MAX_SOUNDS then
		if string.sub(str, 1, 1) ~= "*" then -- player specific sounds don't register here
			cgs.gameSounds[num - C.CS_SOUNDS] = trap.S_RegisterSound(str, false)
		end
	elseif num >= C.CS_PLAYERS and num < C.CS_PLAYERS + C.MAX_CLIENTS then
		G.CG_NewClientInfo(num - C.CS_PLAYERS)
		G.CG_BuildSpectatorString()
	elseif num == C.CS_FLAGSTATUS then
		if cgs.gametype == C.GT_CTF or cgs.gametype == C.GT_CTF_ELIMINATION or cgs.gametype == C.GT_DOUBLE_D then
			-- format is rb where its red/blue, 0 is at base, 1 is taken, 2 is dropped
			cgs.redflag = charAt(str, 0) - 48
			cgs.blueflag = charAt(str, 1) - 48
		elseif cgs.gametype == C.GT_1FCTF or cgs.gametype == C.GT_POSSESSION then
			cgs.flagStatus = charAt(str, 0) - 48
		end
	elseif num == C.CS_SHADERSTATE then
		G.CG_ShaderStateChanged()
	end
end

--[[
The server has issued a map_restart, so the next snapshot
is completely new and should not be interpolated to.

A tournement restart will clear everything, but doesn't
require a reload of all the media
]]
local function CG_MapRestart()
	local cg = G.cg
	if G.cg_showmiss.integer ~= 0 then
		G.CG_Printf("CG_MapRestart\n")
	end

	G.CG_InitLocalEntities()
	G.CG_InitMarkPolys()

	-- make sure the "3 frags left" warnings play again
	cg.fraglimitWarnings = 0

	cg.timelimitWarnings = 0

	cg.intermissionStarted = false

	G.cgs.voteTime = 0

	cg.mapRestart = true

	G.CG_StartMusic()

	trap.S_ClearLoopingSounds(true)

	-- we really should clear more parts of cg here and stop sounds

	-- play the "fight" sound if this is a restart without warmup
	if cg.warmup == 0 then
		trap.S_StartLocalSound(G.cgs.media.countFightSound, C.CHAN_ANNOUNCER)
		G.CG_CenterPrint("FIGHT!", 120, C.GIANTCHAR_WIDTH * 2)
	end
	trap.Cvar_Set("cg_thirdPerson", "0")
end

function G.CG_ParseVoiceChats(filename: string, voiceChatList, maxVoiceChats: number): boolean
	local compress = true
	if G.cg_buildScript.integer ~= 0 then
		compress = false
	end

	local len, f = trap.FS_FOpenFile(filename, C.FS_READ)
	if f == 0 or len < 0 then
		trap.Print(Q.va("^1voice chat file not found: %s\n", filename))
		return false
	end
	if len >= MAX_VOICEFILESIZE then
		trap.Print(
			Q.va("^1voice chat file too large: %s is %i, max allowed is %i\n", filename, len, MAX_VOICEFILESIZE)
		)
		trap.FS_FCloseFile(f)
		return false
	end

	local buf = trap.FS_Read(len, f)
	trap.FS_FCloseFile(f)

	local state = { s = buf, i = 1 }

	voiceChatList.name = filename
	local voiceChats = voiceChatList.voiceChats
	for i = 0, maxVoiceChats - 1 do
		voiceChats[i].id = ""
	end
	local token = parseExt(state)
	if token == "" then
		return true
	end
	if token == "female" then
		voiceChatList.gender = C.GENDER_FEMALE
	elseif token == "male" then
		voiceChatList.gender = C.GENDER_MALE
	elseif token == "neuter" then
		voiceChatList.gender = C.GENDER_NEUTER
	else
		trap.Print(Q.va("^1expected gender not found in voice chat file: %s\n", filename))
		return false
	end

	voiceChatList.numVoiceChats = 0
	while true do
		token = parseExt(state)
		if token == "" then
			return true
		end
		local vc = voiceChats[voiceChatList.numVoiceChats]
		vc.id = token
		token = parseExt(state)
		if token ~= "{" then
			trap.Print(Q.va("^1expected { found %s in voice chat file: %s\n", token, filename))
			return false
		end
		vc.numSounds = 0
		while true do
			token = parseExt(state)
			if token == "" then
				return true
			end
			if token == "}" then
				break
			end
			local sound = trap.S_RegisterSound(token, compress)
			vc.sounds[vc.numSounds] = sound
			token = parseExt(state)
			if token == "" then
				return true
			end
			vc.chats[vc.numSounds] = string.sub(token, 1, MAX_CHATSIZE - 1)
			if sound ~= 0 then
				vc.numSounds += 1
			end
			if vc.numSounds >= MAX_VOICESOUNDS then
				break
			end
		end
		voiceChatList.numVoiceChats += 1
		if voiceChatList.numVoiceChats >= maxVoiceChats then
			return true
		end
	end
end

function G.CG_LoadVoiceChats()
	local size = trap.MemoryRemaining()
	local files = {
		[0] = "scripts/female1.voice",
		"scripts/female2.voice",
		"scripts/female3.voice",
		"scripts/male1.voice",
		"scripts/male2.voice",
		"scripts/male3.voice",
		"scripts/male4.voice",
		"scripts/male5.voice",
	}
	for i = 0, MAX_VOICEFILES - 1 do
		G.CG_ParseVoiceChats(files[i], G.voiceChatLists[i], MAX_VOICECHATS)
	end
	G.CG_Printf(Q.va("voice chat memory size = %d\n", size - trap.MemoryRemaining()))
end

function G.CG_HeadModelVoiceChats(filename: string): number
	local len, f = trap.FS_FOpenFile(filename, C.FS_READ)
	if f == 0 or len < 0 then
		return -1
	end
	if len >= MAX_VOICEFILESIZE then
		trap.Print(
			Q.va("^1voice chat file too large: %s is %i, max allowed is %i\n", filename, len, MAX_VOICEFILESIZE)
		)
		trap.FS_FCloseFile(f)
		return -1
	end

	local buf = trap.FS_Read(len, f)
	trap.FS_FCloseFile(f)

	local token = parseExt({ s = buf, i = 1 })
	if token == "" then
		return -1
	end

	for i = 0, MAX_VOICEFILES - 1 do
		if token == G.voiceChatLists[i].name then
			return i
		end
	end

	--FIXME: maybe try to load the .voice file which name is stored in token?

	return -1
end

-- returns found, snd, chat
function G.CG_GetVoiceChat(voiceChatList, id: string, snd: number?, chat: string?): (boolean, number?, string?)
	for i = 0, voiceChatList.numVoiceChats - 1 do
		if id == voiceChatList.voiceChats[i].id then
			local rnd = Q.int(Q.random() * voiceChatList.voiceChats[i].numSounds)
			return true, voiceChatList.voiceChats[i].sounds[rnd], voiceChatList.voiceChats[i].chats[rnd]
		end
	end
	return false, snd, chat
end

function G.CG_VoiceChatListForClient(clientNum: number)
	local headModelVoiceChat = G.headModelVoiceChat
	local voiceChatLists = G.voiceChatLists
	local headModelName = ""

	if clientNum < 0 or clientNum >= C.MAX_CLIENTS then
		clientNum = 0
	end
	local ci = G.cgs.clientinfo[clientNum]

	for k = 0, 1 do
		local base = ci.headModelName
		if string.sub(base, 1, 1) == "*" then
			base = string.sub(base, 2)
		end
		if k == 0 then
			headModelName = Q.va("%s/%s", base, ci.headSkinName)
		else
			headModelName = base
		end
		-- find the voice file for the head model the client uses
		local i = 0
		while i < MAX_HEADMODELS do
			if headModelVoiceChat[i].headmodel == headModelName then
				break
			end
			i += 1
		end
		if i < MAX_HEADMODELS then
			return voiceChatLists[headModelVoiceChat[i].voiceChatNum]
		end
		-- find a <headmodelname>.vc file
		for j = 0, MAX_HEADMODELS - 1 do
			if headModelVoiceChat[j].headmodel == "" then
				local filename = Q.va("scripts/%s.vc", headModelName)
				local voiceChatNum = G.CG_HeadModelVoiceChats(filename)
				if voiceChatNum == -1 then
					break
				end
				headModelVoiceChat[j].headmodel = headModelName
				headModelVoiceChat[j].voiceChatNum = voiceChatNum
				return voiceChatLists[headModelVoiceChat[j].voiceChatNum]
			end
		end
	end
	local gender = ci.gender
	for _ = 0, 1 do
		-- just pick the first with the right gender
		for i = 0, MAX_VOICEFILES - 1 do
			if voiceChatLists[i].name ~= "" then
				if voiceChatLists[i].gender == gender then
					-- store this head model with voice chat for future reference
					for j = 0, MAX_HEADMODELS - 1 do
						if headModelVoiceChat[j].headmodel == "" then
							headModelVoiceChat[j].headmodel = headModelName
							headModelVoiceChat[j].voiceChatNum = i
							break
						end
					end
					return voiceChatLists[i]
				end
			end
		end
		-- fall back to male gender because we don't have neuter in the mission pack
		if gender == C.GENDER_MALE then
			break
		end
		gender = C.GENDER_MALE
	end
	-- store this head model with voice chat for future reference
	for j = 0, MAX_HEADMODELS - 1 do
		if headModelVoiceChat[j].headmodel == "" then
			headModelVoiceChat[j].headmodel = headModelName
			headModelVoiceChat[j].voiceChatNum = 0
			break
		end
	end
	-- just return the first voice chat list
	return voiceChatLists[0]
end

-- voice chat playback is MISSIONPACK-only; the base game keeps these as no-ops
function G.CG_PlayVoiceChat(vchat) end

function G.CG_PlayBufferedVoiceChats() end

function G.CG_AddBufferedVoiceChat(vchat) end

function G.CG_VoiceChatLocal(mode: number, voiceOnly: boolean, clientNum: number, color: number, cmd: string) end

function G.CG_VoiceChat(mode: number) end

local function CG_RemoveChatEscapeChar(text: string): string
	local out = string.gsub(text, "\25", "")
	return out
end

local function CG_ServerCommand()
	local cmd = G.CG_Argv(0)

	if cmd == "" then
		-- server claimed the command
		return
	end

	if cmd == "cp" then
		G.CG_CenterPrint(G.CG_Argv(1), Q.int(C.SCREEN_HEIGHT * 0.30), C.BIGCHAR_WIDTH)
		return
	end

	if cmd == "cs" then
		CG_ConfigStringModified()
		return
	end

	if cmd == "print" then
		G.CG_Printf(Q.va("%s", G.CG_Argv(1)))
		return
	end

	if cmd == "chat" then
		if G.cg_teamChatsOnly.integer == 0 then
			if G.cg_chatBeep.integer ~= 0 then
				trap.S_StartLocalSound(G.cgs.media.talkSound, C.CHAN_LOCAL_SOUND)
			end
			local text = CG_RemoveChatEscapeChar(string.sub(G.CG_Argv(1), 1, C.MAX_SAY_TEXT - 1))
			G.CG_Printf(Q.va("%s\n", text))
		end
		return
	end

	if cmd == "tchat" then
		if G.cg_teamChatBeep.integer ~= 0 then
			trap.S_StartLocalSound(G.cgs.media.talkSound, C.CHAN_LOCAL_SOUND)
		end
		local text = CG_RemoveChatEscapeChar(string.sub(G.CG_Argv(1), 1, C.MAX_SAY_TEXT - 1))
		CG_AddToTeamChat(text)
		G.CG_Printf(Q.va("%s\n", text))
		return
	end
	if cmd == "vchat" then
		G.CG_VoiceChat(C.SAY_ALL)
		return
	end

	if cmd == "vtchat" then
		G.CG_VoiceChat(C.SAY_TEAM)
		return
	end

	if cmd == "vtell" then
		G.CG_VoiceChat(C.SAY_TELL)
		return
	end

	if cmd == "scores" then
		CG_ParseScores()
		return
	end

	if cmd == "accs" then
		CG_ParseAccuracy()
		return
	end

	if cmd == "ddTakeAt" then
		CG_ParseDDtimetakeAt()
		return
	end

	if cmd == "dompointnames" then
		CG_ParseDomPointNames()
		return
	end

	if cmd == "domStatus" then
		CG_ParseDomStatus()
		return
	end

	if cmd == "elimination" then
		CG_ParseElimination()
		return
	end

	if cmd == "mappage" then
		CG_ParseMappage()
		return
	end

	if cmd == "attackingteam" then
		CG_ParseAttackingTeam()
		return
	end

	if cmd == "tinfo" then
		CG_ParseTeamInfo()
		return
	end

	if cmd == "map_restart" then
		CG_MapRestart()
		return
	end

	if Q.stricmp(cmd, "remapShader") == 0 then
		if trap.Argc() == 4 then
			trap.R_RemapShader(
				string.sub(G.CG_Argv(1), 1, C.MAX_QPATH - 1),
				string.sub(G.CG_Argv(2), 1, C.MAX_QPATH - 1),
				string.sub(G.CG_Argv(3), 1, C.MAX_QPATH - 1)
			)
		end

		return
	end

	-- loaddeferred can be both a servercmd and a consolecmd
	if cmd == "loaddefered" then -- FIXME: spelled wrong, but not changing for demo
		G.CG_LoadDeferredPlayers()
		return
	end

	-- clientLevelShot is sent before taking a special screenshot for
	-- the menu system during development
	if cmd == "clientLevelShot" then
		G.cg.levelShot = true
		return
	end

	-- challenge completed is determened by the server. A client should consider this message valid:
	if cmd == "ch" then
		CG_ParseChallenge()
		return
	end

	if cmd == "oh" then
		CG_ParseObeliskHealth()
		return
	end

	if cmd == "respawn" then
		CG_ParseRespawnTime()
		return
	end

	if cmd == "team" then
		CG_ParseTeam()
		return
	end

	if cmd == "customvotes" then
		local infoString = ""
		for i = 1, 12 do
			infoString ..= G.CG_Argv(i)
			infoString ..= " "
		end
		trap.Cvar_Set("cg_vote_custom_commands", string.sub(infoString, 1, 1023))
		return
	end

	G.CG_Printf(Q.va("Unknown client game command: %s\n", cmd))
end

--[[
Execute all of the server commands that were received along
with this this snapshot.
]]
function G.CG_ExecuteNewServerCommands(latestSequence: number)
	local cgs = G.cgs
	while cgs.serverCommandSequence < latestSequence do
		cgs.serverCommandSequence += 1
		if trap.GetServerCommand(cgs.serverCommandSequence) then
			CG_ServerCommand()
		end
	end
end

return G
