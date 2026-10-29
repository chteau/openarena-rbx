--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_killspree.c).

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
-- Luau port of OpenArena 0.8.8's g_killspree.c (gamecode 9e0f0c0). Killing sprees, death sprees and multikills.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

G.killSprees = {}
G.deathSprees = {}
G.multiKills = {}

local function AP(x)
	G.trap_SendServerCommand(-1, x)
end

--[[
=================
G_ReadAltKillSettings
Since this is cvar dependent, it has to be placed in G_InitGame after cvars are registered.
=================
]]
function G.G_ReadAltKillSettings(ent, skiparg)
	local k = nil
	local d = nil
	local m = nil
	local ksc, dsc, mc = 0, 0, 0
	local spreeDivisor

	local i = 0

	local length
	local file
	local kspree_read
	local dspree_read
	local mkill_read
	local cnf
	local t

	i = 0
	while i < C.MAX_KSPREE and G.killSprees[i] ~= nil do
		G.killSprees[i] = nil
		i += 1
	end

	i = 0
	while i < C.MAX_KSPREE and G.deathSprees[i] ~= nil do
		G.deathSprees[i] = nil
		i += 1
	end

	i = 0
	while i < C.MAX_MULTIKILLS and G.multiKills[i] ~= nil do
		G.multiKills[i] = nil
		i += 1
	end

	if G.g_sprees.string == "" then
		if G.g_altExcellent.integer == 1 then
			G.trap_Cvar_Set("g_altExcellent", "0")
		end
		return false
	end
	if G.g_spreeDiv.integer >= 2 then
		G.level.spreeDivisor = G.g_spreeDiv.integer
		spreeDivisor = G.level.spreeDivisor
	else
		G.level.spreeDivisor = 5
		spreeDivisor = 5
		G.G_Printf("Error: cvar g_spreeDiv must not be set to 0 or 1, reverting to default settings!\n")
		G.G_Printf("Error: Set g_spreeDiv higher than 1 if 5 is not desired!\n")
	end

	length, file = G.trap_FS_FOpenFile(G.g_sprees.string, C.FS_READ)

	if length < 0 then
		G.G_Printf("Could not open configuration file for Sprees and Multikills %s\n", G.g_sprees.string)
		G.trap_Cvar_Set("g_altExcellent", "0")
		return false
	end
	local text = G.trap_FS_Read(length, file)
	G.trap_FS_FCloseFile(file)
	cnf = QS.cursor(text)

	kspree_read, dspree_read, mkill_read = false, false, false

	QS.COM_BeginParseSession(G.g_sprees.string)
	while true do
		t = QS.COM_Parse(cnf)
		if t == "" then
			break
		end
		if QS.Q_stricmp(t, "[kspree]") == 0 then
			if ksc >= C.MAX_KSPREE then
				return false
			end
			k = S.killspree_t()
			G.killSprees[ksc] = k
			ksc += 1
			kspree_read = true
			dspree_read = false
			mkill_read = false
		elseif QS.Q_stricmp(t, "[dspree]") == 0 then
			if dsc >= C.MAX_DSPREE then
				return false
			end
			d = S.deathspree_t()
			G.deathSprees[dsc] = d
			dsc += 1
			dspree_read = true
			kspree_read = false
			mkill_read = false
		elseif QS.Q_stricmp(t, "[mkill]") == 0 then
			if mc >= C.MAX_MULTIKILLS then
				return false
			end
			m = S.multikill_t()
			G.multiKills[mc] = m
			mc += 1
			mkill_read = true
			kspree_read = false
			dspree_read = false
		elseif kspree_read then
			if QS.Q_stricmp(t, "level") == 0 then
				k.spreeLevel = G.readFile_int(cnf)
				k.streakCount = k.spreeLevel * spreeDivisor
			elseif QS.Q_stricmp(t, "message") == 0 then
				k.spreeMsg = G.readFile_string(cnf, #k.spreeMsg)
			elseif QS.Q_stricmp(t, "printpos") == 0 then
				k.position = G.readFile_int(cnf)
			elseif QS.Q_stricmp(t, "sound") == 0 then
				k.sound2Play = G.readFile_string(cnf, #k.sound2Play)
			else
				QS.COM_ParseError('Killing Spree unrecognized token "%s"', t)
			end
		elseif dspree_read then
			if QS.Q_stricmp(t, "level") == 0 then
				d.spreeLevel = G.readFile_int(cnf)
				d.streakCount = d.spreeLevel * spreeDivisor
			elseif QS.Q_stricmp(t, "message") == 0 then
				d.spreeMsg = G.readFile_string(cnf, #d.spreeMsg)
			elseif QS.Q_stricmp(t, "printpos") == 0 then
				d.position = G.readFile_int(cnf)
			elseif QS.Q_stricmp(t, "sound") == 0 then
				d.sound2Play = G.readFile_string(cnf, #d.sound2Play)
			else
				QS.COM_ParseError('Death Spree unrecognized token "%s"', t)
			end
		elseif mkill_read then
			if QS.Q_stricmp(t, "kills") == 0 then
				m.kills = G.readFile_int(cnf)
			elseif QS.Q_stricmp(t, "message") == 0 then
				m.killMsg = G.readFile_string(cnf, #m.killMsg)
			elseif QS.Q_stricmp(t, "sound") == 0 then
				m.sound2Play = G.readFile_string(cnf, #m.sound2Play)
			else
				QS.COM_ParseError('Multikill unrecognized token "%s"', t)
			end
		else
			QS.COM_ParseError('unexpected token "%s"', t)
		end
	end
	G.G_Printf("Sprees/Kills: loaded %d killing sprees, %d death sprees, and %d multikills.\n", ksc, dsc, mc)
	G.level.kSpreeUBound = ksc - 1
	G.level.dSpreeUBound = dsc - 1
	if mc > 0 then
		G.level.mKillUBound = mc - 1
	else
		G.level.mKillUBound = -1
		if G.g_altExcellent.integer == 1 then
			G.trap_Cvar_Set("g_altExcellent", "0")
		end
	end
	return true
end

local fillOutput = ""

local function fillPlaceHolder(stringToSearch, placeHolder, replaceWith)
	local p = QS.strstr(stringToSearch, placeHolder)
	if p == nil then
		return stringToSearch
	end

	fillOutput = string.sub(
		string.sub(stringToSearch, 1, p - 1) .. replaceWith .. string.sub(stringToSearch, p + #placeHolder),
		1,
		C.MAX_SAY_TEXT - 1
	)

	return fillOutput
end

local createOutput = ""

-- This concatenate's the message to broadcast to the clients.
local function CreateMessage(ent, message, spreeNumber)
	if ent == nil then
		return createOutput
	elseif message == "" then
		return createOutput
	elseif spreeNumber == nil then
		return createOutput
	end
	local name = QS.Q_strncpyz(ent.client.pers.netname, C.MAX_NAME_LENGTH)
	createOutput = QS.Q_strncpyz(fillPlaceHolder(message, "[n]", name), C.MAX_SAY_TEXT)
	createOutput = QS.Q_strncpyz(fillPlaceHolder(createOutput, "[k]", spreeNumber), C.MAX_SAY_TEXT)
	return createOutput
end

--[[
================
G_RunStreakLogic
KK-OAX This is called from player_die.
It does all the adding resetting of kill/death streaks
to be compared against the kill/death spree levels.
================
]]
function G.G_RunStreakLogic(attacker, victim)
	if victim == nil or victim.client == nil then
		return
	end

	victim.client.pers.killstreak = 0
	victim.client.pers.deathstreak += 1

	G.G_CheckForSpree(victim, victim.client.pers.deathstreak, false)

	if attacker ~= nil and attacker.client ~= nil and attacker ~= victim then
		if G.g_gametype.integer >= C.GT_TEAM and G.g_ffa_gt ~= 1 then
			if G.OnSameTeam(victim, attacker) then
				return
			end
		end
		attacker.client.pers.deathstreak = 0
		attacker.client.pers.killstreak += 1

		G.G_CheckForSpree(attacker, attacker.client.pers.killstreak, true)
	end
end

-- If the streak / spree divisor is a whole number, we have a spree
local function TestSpreeWhole(streak2Test)
	local float2Test = streak2Test
	local spreeFDiv = G.level.spreeDivisor
	local spreeDiv = G.level.spreeDivisor
	local result = Q.idiv(streak2Test, spreeDiv)
	local resultf = Q.f(float2Test / spreeFDiv)

	if result == resultf then
		return true
	else
		return false
	end
end

--[[
==================
G_CheckForSpree
==================
]]
function G.G_CheckForSpree(ent, streak2Test, checkKillSpree)
	local returnedString
	local streakcount
	local sound
	local position
	local soundIndex

	local isSpree = false
	local divisionHolder

	if G.level.spreeDivisor < 1 then
		return
	end
	divisionHolder = Q.idiv(streak2Test, G.level.spreeDivisor)
	if not checkKillSpree then
		if divisionHolder > G.level.dSpreeUBound then
			isSpree = TestSpreeWhole(streak2Test)
			if not isSpree then
				return
			end
			streakcount = string.sub(QS.va("%i", streak2Test), 1, 2)
			local ds = G.deathSprees[G.level.dSpreeUBound]
			if ds == nil then
				return
			end
			returnedString = CreateMessage(ent, ds.spreeMsg, streakcount)
			position = ds.position
			sound = ds.sound2Play
			soundIndex = G.G_SoundIndex(sound)
			G.G_GlobalSound(soundIndex)
			if position == C.CENTER_PRINT then
				AP(QS.va('cp "%s"', returnedString))
			else
				AP(QS.va('chat "%s"', returnedString))
			end
		else
			local i = 0
			while G.deathSprees[i] ~= nil do
				local ds = G.deathSprees[i]
				if ds.streakCount == streak2Test then
					streakcount = string.sub(QS.va("%i", ds.streakCount), 1, 2)
					returnedString = CreateMessage(ent, ds.spreeMsg, streakcount)
					position = ds.position
					sound = ds.sound2Play
					soundIndex = G.G_SoundIndex(sound)
					G.G_GlobalSound(soundIndex)
					if position == C.CENTER_PRINT then
						AP(QS.va('cp "%s"', returnedString))
					else
						AP(QS.va('chat "%s"', returnedString))
					end
					break
				end
				i += 1
			end
		end
	else
		if divisionHolder > G.level.kSpreeUBound then
			isSpree = TestSpreeWhole(streak2Test)
			if not isSpree then
				return
			end
			streakcount = string.sub(QS.va("%i", streak2Test), 1, 2)
			local ks = G.killSprees[G.level.kSpreeUBound]
			if ks == nil then
				return
			end
			returnedString = CreateMessage(ent, ks.spreeMsg, streakcount)
			position = ks.position
			sound = ks.sound2Play
			soundIndex = G.G_SoundIndex(sound)
			soundIndex = G.G_SoundIndex(sound)
			G.G_Sound(ent, 0, soundIndex)
			AP(QS.va('chat "%s"', returnedString))
		else
			local i = 0
			while G.killSprees[i] ~= nil do
				local ks = G.killSprees[i]
				if ks.streakCount == streak2Test then
					streakcount = string.sub(QS.va("%i", ks.streakCount), 1, 2)
					returnedString = CreateMessage(ent, ks.spreeMsg, streakcount)
					position = ks.position
					sound = ks.sound2Play
					soundIndex = G.G_SoundIndex(sound)
					soundIndex = G.G_SoundIndex(sound)
					G.G_Sound(ent, 0, soundIndex)
					AP(QS.va('chat "%s"', returnedString))
					break
				end
				i += 1
			end
		end
	end
end

--[[
===============
G_checkForMultiKill
===============
]]
function G.G_checkForMultiKill(ent)
	local returnedString
	local sound
	local soundIndex
	local multiKillCount
	local multiKillString

	multiKillCount = ent.client.pers.multiKillCount

	local top = G.multiKills[G.level.mKillUBound]
	if top ~= nil and multiKillCount > top.kills then
		multiKillString = string.sub(QS.va("%i", multiKillCount), 1, 1)
		returnedString = CreateMessage(ent, top.killMsg, multiKillString)
		sound = top.sound2Play
		soundIndex = G.G_SoundIndex(sound)
		G.G_Sound(ent, 0, soundIndex)
		AP(QS.va('chat "%s"', returnedString))
		return
	end
	local i = 0
	while G.multiKills[i] ~= nil do
		local mk = G.multiKills[i]
		if mk.kills == multiKillCount then
			multiKillString = string.sub(QS.va("%i", mk.kills), 1, 1)
			returnedString = CreateMessage(ent, mk.killMsg, multiKillString)
			sound = mk.sound2Play
			soundIndex = G.G_SoundIndex(sound)
			G.G_Sound(ent, 0, soundIndex)
			AP(QS.va('chat "%s"', returnedString))
			break
		end
		i += 1
	end
end

return nil
