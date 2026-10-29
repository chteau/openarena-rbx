--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_admin.c, part 3 of 4).

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
-- Luau port of OpenArena 0.8.8's g_admin.c (gamecode 9e0f0c0) (part 3): ban, unban, adjustban, putteam, map, mute, listadmins, listplayers, showbans.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SF = G.FileStatics("g_admin")

-- g_admin.h flag characters and q_shared.h color strings
local ADMF_CAN_PERM_BAN = string.byte("1")
local ADMF_UNACCOUNTABLE = string.byte("2")
local ADMF_INCOGNITO = string.byte("@")
local S_COLOR_RED = "^1"
local S_COLOR_GREEN = "^2"
local S_COLOR_YELLOW = "^3"
local S_COLOR_BLUE = "^4"
local S_COLOR_CYAN = "^5"
local S_COLOR_WHITE = "^7"

local function isdigit(b)
	return b ~= nil and b >= 48 and b <= 57
end

function G.G_admin_ban(ent, skiparg)
	local seconds
	local search
	local secs
	local reason
	local minargc
	local duration
	local logmatch = -1
	local logmatches = 0
	local exactmatch = false
	local n2
	local s2
	local guid_stub

	if G.G_admin_permission(ent, ADMF_CAN_PERM_BAN) and G.G_admin_permission(ent, ADMF_UNACCOUNTABLE) then
		minargc = 2 + skiparg
	elseif
		G.G_admin_permission(ent, ADMF_CAN_PERM_BAN)
		or G.G_admin_permission(ent, ADMF_UNACCOUNTABLE)
		or G.g_adminMaxBan.integer ~= 0
	then
		minargc = 3 + skiparg
	else
		minargc = 4 + skiparg
	end
	if G.G_SayArgc() < minargc then
		G.G_admin_print(ent, "^3!ban: ^7usage: !ban [name|slot|ip] [duration] [reason]\n")
		return false
	end
	search = G.G_SayArgv(1 + skiparg)
	s2 = G.G_SanitiseString(search, C.MAX_NAME_LENGTH)
	secs = G.G_SayArgv(2 + skiparg)

	seconds = G.G_admin_parse_time(secs)
	if seconds <= 0 then
		if G.g_adminMaxBan.integer ~= 0 and not G.G_admin_permission(ent, ADMF_CAN_PERM_BAN) then
			G.G_admin_print(
				ent,
				QS.va("^3!ban: ^7using your admin level's maximum ban length of %s\n", G.g_adminMaxBan.string)
			)
			seconds = G.G_admin_parse_time(G.g_adminMaxBan.string)
		elseif G.G_admin_permission(ent, ADMF_CAN_PERM_BAN) then
			seconds = 0
		else
			G.G_admin_print(ent, "^3!ban: ^7you may not issue permanent bans\n")
			return false
		end
		reason = G.G_SayConcatArgs(2 + skiparg)
	else
		if
			G.g_adminMaxBan.integer ~= 0
			and not G.G_admin_permission(ent, ADMF_CAN_PERM_BAN)
			and seconds > G.G_admin_parse_time(G.g_adminMaxBan.string)
		then
			G.G_admin_print(
				ent,
				QS.va("^3!ban: ^7ban length limited to %s for your admin level\n", G.g_adminMaxBan.string)
			)
			seconds = G.G_admin_parse_time(G.g_adminMaxBan.string)
		end
		reason = G.G_SayConcatArgs(3 + skiparg)
	end

	local namelog = G.g_admin_namelog
	local i = 0
	while i < C.MAX_ADMIN_NAMELOGS and namelog[i] ~= nil do
		local skip = false
		if namelog[i].banned then
			skip = true
		elseif namelog[i].slot == -1 then
			skip = true
		end
		if not skip then
			if QS.Q_stricmp(QS.va("%d", namelog[i].slot), search) == 0 then
				logmatches = 1
				logmatch = i
				exactmatch = true
				break
			end
		end
		i += 1
	end

	i = 0
	while not exactmatch and i < C.MAX_ADMIN_NAMELOGS and namelog[i] ~= nil do
		if not namelog[i].banned then
			if QS.Q_stricmp(namelog[i].ip, search) == 0 then
				logmatches = 1
				logmatch = i
				exactmatch = true
				break
			end
			local j = 0
			while j < C.MAX_ADMIN_NAMELOG_NAMES and namelog[i].name[j] ~= nil and namelog[i].name[j] ~= "" do
				n2 = G.G_SanitiseString(namelog[i].name[j], C.MAX_NAME_LENGTH)
				if QS.strstr(n2, s2) ~= nil then
					if logmatch ~= i then
						logmatches += 1
					end
					logmatch = i
				end
				j += 1
			end
		end
		i += 1
	end

	if logmatches == 0 then
		G.G_admin_print(ent, "^3!ban: ^7no player found by that name, IP, or slot number\n")
		return false
	end
	if logmatches > 1 then
		G.G_admin_buffer_begin()
		G.G_admin_buffer_print(ent, "^3!ban: ^7multiple recent clients match name, use IP or slot#:\n")
		i = 0
		while i < C.MAX_ADMIN_NAMELOGS and namelog[i] ~= nil do
			guid_stub = string.sub(namelog[i].guid, 25, 32)
			local j = 0
			while j < C.MAX_ADMIN_NAMELOG_NAMES and namelog[i].name[j] ~= nil and namelog[i].name[j] ~= "" do
				n2 = G.G_SanitiseString(namelog[i].name[j], C.MAX_NAME_LENGTH)
				if QS.strstr(n2, s2) ~= nil then
					if namelog[i].slot > -1 then
						G.G_admin_buffer_print(ent, "^3")
					end
					G.G_admin_buffer_print(
						ent,
						QS.va(
							"%-2s (*%s) %15s ^7'%s^7'\n",
							if namelog[i].slot > -1 then QS.va("%d", namelog[i].slot) else "-",
							guid_stub,
							namelog[i].ip,
							namelog[i].name[j]
						)
					)
				end
				j += 1
			end
			i += 1
		end
		G.G_admin_buffer_end(ent)
		return false
	end

	if ent ~= nil and not SF.admin_higher_guid(ent.client.pers.guid, namelog[logmatch].guid) then
		G.G_admin_print(ent, "^3!ban: ^7sorry, but your intended victim has a higher admin level than you\n")
		return false
	end
	if namelog[logmatch].ip == "localhost" then
		G.G_admin_print(ent, "^3!ban: ^7disconnecting the host would end the game\n")
		return false
	end

	duration = G.G_admin_duration(if seconds ~= 0 then seconds else -1, 32)

	SF.admin_create_ban(ent, namelog[logmatch].name[0], namelog[logmatch].guid, namelog[logmatch].ip, seconds, reason)

	namelog[logmatch].banned = true

	if G.g_admin.string == "" then
		G.G_admin_print(ent, "^3!ban: ^7WARNING g_admin not set, not saving ban to a file\n")
	elseif #namelog[logmatch].guid == 0 or #namelog[logmatch].ip ~= 0 then
		G.G_admin_print(ent, "^3!ban: ^7WARNING bot or without GUID or IP cannot write to ban file\n")
	else
		SF.admin_writeconfig()
	end

	if namelog[logmatch].slot == -1 then
		G.trap_SendServerCommand(
			-1,
			QS.va(
				'print "^3!ban:^7 %s^7 has been banned by %s^7, duration: %s, reason: %s\n"',
				namelog[logmatch].name[0],
				if ent ~= nil then ent.client.pers.netname else "console",
				duration,
				if reason ~= "" then reason else "banned by admin"
			)
		)
		return true
	end

	G.trap_SendServerCommand(
		namelog[logmatch].slot,
		QS.va(
			'disconnect "You have been banned.\nadmin:\n%s^7\nduration:\n%s\nreason:\n%s"',
			if ent ~= nil then ent.client.pers.netname else "console",
			duration,
			if reason ~= "" then reason else "banned by admin"
		)
	)

	G.trap_DropClient(
		namelog[logmatch].slot,
		QS.va(
			"has been banned by %s^7, duration: %s, reason: %s",
			if ent ~= nil then ent.client.pers.netname else "console",
			duration,
			if reason ~= "" then reason else "banned by admin"
		)
	)
	return true
end

function G.G_admin_unban(ent, skiparg)
	local bnum
	local time = G.trap_RealTime(nil)
	local bs

	if G.G_SayArgc() < 2 + skiparg then
		G.G_admin_print(ent, "^3!unban: ^7usage: !unban [ban#]\n")
		return false
	end
	bs = G.G_SayArgv(1 + skiparg)
	bnum = QS.atoi(bs)
	if bnum < 1 or bnum > C.MAX_ADMIN_BANS or G.g_admin_bans[bnum - 1] == nil then
		G.G_admin_print(ent, "^3!unban: ^7invalid ban#\n")
		return false
	end
	if G.g_admin_bans[bnum - 1].expires == 0 and not G.G_admin_permission(ent, ADMF_CAN_PERM_BAN) then
		G.G_admin_print(ent, "^3!unban: ^7you cannot remove permanent bans\n")
		return false
	end
	if
		G.g_adminMaxBan.integer ~= 0
		and not G.G_admin_permission(ent, ADMF_CAN_PERM_BAN)
		and G.g_admin_bans[bnum - 1].expires - time > G.G_admin_parse_time(G.g_adminMaxBan.string)
	then
		G.G_admin_print(
			ent,
			QS.va("^3!unban: ^7your admin level cannot remove bans longer than %s\n", G.g_adminMaxBan.string)
		)
		return false
	end
	G.g_admin_bans[bnum - 1].expires = time
	G.trap_SendServerCommand(
		-1,
		QS.va(
			'print "^3!unban: ^7ban #%d for %s^7 has been removed by %s\n"',
			bnum,
			G.g_admin_bans[bnum - 1].name,
			if ent ~= nil then ent.client.pers.netname else "console"
		)
	)
	if G.g_admin.string ~= "" then
		SF.admin_writeconfig()
	end
	return true
end

function G.G_admin_adjustban(ent, skiparg)
	local bnum
	local length
	local expires = 0
	local time = G.trap_RealTime(nil)
	local duration = ""
	local reason
	local bs
	local secs
	local mode = ""
	local ban

	if G.G_SayArgc() < 3 + skiparg then
		G.G_admin_print(ent, "^3!adjustban: ^7usage: !adjustban [ban#] [duration] [reason]\n")
		return false
	end
	bs = G.G_SayArgv(1 + skiparg)
	bnum = QS.atoi(bs)
	if bnum < 1 or bnum > C.MAX_ADMIN_BANS or G.g_admin_bans[bnum - 1] == nil then
		G.G_admin_print(ent, "^3!adjustban: ^7invalid ban#\n")
		return false
	end
	ban = G.g_admin_bans[bnum - 1]
	if ban.expires == 0 and not G.G_admin_permission(ent, ADMF_CAN_PERM_BAN) then
		G.G_admin_print(ent, "^3!adjustban: ^7you cannot modify permanent bans\n")
		return false
	end
	if
		G.g_adminMaxBan.integer ~= 0
		and not G.G_admin_permission(ent, ADMF_CAN_PERM_BAN)
		and ban.expires - time > G.G_admin_parse_time(G.g_adminMaxBan.string)
	then
		G.G_admin_print(
			ent,
			QS.va("^3!adjustban: ^7your admin level cannot modify bans longer than %s\n", G.g_adminMaxBan.string)
		)
		return false
	end
	secs = G.G_SayArgv(2 + skiparg)
	local first = string.sub(secs, 1, 1)
	if first == "+" or first == "-" then
		mode = first
	end
	length = G.G_admin_parse_time(string.sub(secs, if mode ~= "" then 2 else 1))
	if length < 0 then
		skiparg -= 1
	else
		if length ~= 0 then
			if ban.expires == 0 and mode ~= "" then
				G.G_admin_print(ent, "^3!adjustban: ^7new duration must be explicit\n")
				return false
			end
			if mode == "+" then
				expires = ban.expires + length
			elseif mode == "-" then
				expires = ban.expires - length
			else
				expires = time + length
			end
			if expires <= time then
				G.G_admin_print(ent, "^3!adjustban: ^7ban duration must be positive\n")
				return false
			end
			if
				G.g_adminMaxBan.integer ~= 0
				and not G.G_admin_permission(ent, ADMF_CAN_PERM_BAN)
				and expires - time > G.G_admin_parse_time(G.g_adminMaxBan.string)
			then
				G.G_admin_print(
					ent,
					QS.va(
						"^3!adjustban: ^7ban length is limited to %s for your admin level\n",
						G.g_adminMaxBan.string
					)
				)
				length = G.G_admin_parse_time(G.g_adminMaxBan.string)
				expires = time + length
			end
		elseif G.G_admin_permission(ent, ADMF_CAN_PERM_BAN) then
			expires = 0
		else
			G.G_admin_print(ent, "^3!adjustban: ^7ban duration must be positive\n")
			return false
		end

		ban.expires = expires
		duration = G.G_admin_duration(if expires ~= 0 then expires - time else -1, 32)
	end
	reason = G.G_SayConcatArgs(3 + skiparg)
	if reason ~= "" then
		ban.reason = reason
	end
	G.trap_SendServerCommand(
		-1,
		QS.va(
			'print "^3!adjustban: ^7ban #%d for %s^7 has been updated by %s^7 %s%s%s%s%s\n"',
			bnum,
			ban.name,
			if ent ~= nil then ent.client.pers.netname else "console",
			if length >= 0 then "duration: " else "",
			duration,
			if length >= 0 and reason ~= "" then ", " else "",
			if reason ~= "" then "reason: " else "",
			reason
		)
	)
	if ent ~= nil then
		ban.banner = ent.client.pers.netname
	end
	if G.g_admin.string ~= "" then
		SF.admin_writeconfig()
	end
	return true
end

function G.G_admin_putteam(ent, skiparg)
	local pids = {}
	local found
	local name
	local team
	local err
	local vic
	local teamnum = C.TEAM_NONE

	name = G.G_SayArgv(1 + skiparg)
	team = G.G_SayArgv(2 + skiparg)
	if G.G_SayArgc() < 3 + skiparg then
		G.G_admin_print(ent, "^3!putteam: ^7usage: !putteam [name] [h|a|s]\n")
		return false
	end

	found = G.G_ClientNumbersFromString(name, pids, C.MAX_CLIENTS)
	if found ~= 1 then
		err = G.G_MatchOnePlayer(pids, found, C.MAX_STRING_CHARS)
		G.G_admin_print(ent, QS.va("^3!putteam: ^7%s\n", err))
		return false
	end
	if not SF.admin_higher(ent, G.g_entities[pids[0]]) then
		G.G_admin_print(ent, "^3!putteam: ^7sorry, but your intended victim has a higher  admin level than you\n")
		return false
	end
	vic = G.g_entities[pids[0]]
	teamnum = G.G_TeamFromString(team)
	if teamnum == C.TEAM_NUM_TEAMS then
		G.G_admin_print(ent, QS.va("^3!putteam: ^7unknown team %s\n", team))
		return false
	end
	if vic.client.sess.sessionTeam == teamnum then
		return false
	end

	G.SetTeam(vic, team)

	G.trap_SendServerCommand(
		-1,
		QS.va(
			'print "^3!putteam: ^7%s^7 put %s^7 on to the %s team\n"',
			if ent ~= nil then ent.client.pers.netname else "console",
			vic.client.pers.netname,
			BG.BG_TeamName(teamnum)
		)
	)
	return true
end

function G.G_admin_map(ent, skiparg)
	local map

	if G.G_SayArgc() < 2 + skiparg then
		G.G_admin_print(ent, "^3!map: ^7usage: !map [map] (layout)\n")
		return false
	end

	map = G.G_SayArgv(skiparg + 1)

	local len = G.trap_FS_FOpenFile(QS.va("maps/%s.bsp", map), C.FS_READ)
	if len == 0 then
		G.G_admin_print(ent, QS.va("^3!map: ^7invalid map name '%s'\n", map))
		return false
	end

	G.trap_SendConsoleCommand(C.EXEC_APPEND, QS.va("map %s", map))
	G.level.restarted = true
	G.trap_SendServerCommand(
		-1,
		QS.va(
			'print "^3!map: ^7map \'%s\' started by %s\n"',
			map,
			if ent ~= nil then ent.client.pers.netname else "console"
		)
	)
	return true
end

function G.G_admin_mute(ent, skiparg)
	local pids = {}
	local found
	local name
	local err
	local command
	local cmd
	local vic

	command = G.G_SayArgv(skiparg)
	cmd = command
	if string.sub(cmd, 1, 1) == "!" then
		cmd = string.sub(cmd, 2)
	end
	if G.G_SayArgc() < 2 + skiparg then
		G.G_admin_print(ent, QS.va("^3!%s: ^7usage: !%s [name|slot#]\n", cmd, cmd))
		return false
	end
	name = G.G_SayArgv(1 + skiparg)
	found = G.G_ClientNumbersFromString(name, pids, C.MAX_CLIENTS)
	if found ~= 1 then
		err = G.G_MatchOnePlayer(pids, found, C.MAX_STRING_CHARS)
		G.G_admin_print(ent, QS.va("^3!%s: ^7%s\n", cmd, err))
		return false
	end
	if not SF.admin_higher(ent, G.g_entities[pids[0]]) then
		G.G_admin_print(
			ent,
			QS.va("^3!%s: ^7sorry, but your intended victim has a higher admin level than you\n", cmd)
		)
		return false
	end
	vic = G.g_entities[pids[0]]
	if vic.client.pers.muted == true then
		if QS.Q_stricmp(cmd, "mute") == 0 then
			G.G_admin_print(ent, "^3!mute: ^7player is already muted\n")
			return true
		end
		vic.client.pers.muted = false
		G.trap_SendServerCommand(pids[0], 'cp "^1You have been unmuted"')
		G.trap_SendServerCommand(
			-1,
			QS.va(
				'print "^3!unmute: ^7%s^7 has been unmuted by %s\n"',
				vic.client.pers.netname,
				if ent ~= nil then ent.client.pers.netname else "console"
			)
		)
	else
		if QS.Q_stricmp(cmd, "unmute") == 0 then
			G.G_admin_print(ent, "^3!unmute: ^7player is not currently muted\n")
			return true
		end
		vic.client.pers.muted = true
		G.trap_SendServerCommand(pids[0], 'cp "^1You\'ve been muted"')
		G.trap_SendServerCommand(
			-1,
			QS.va(
				'print "^3!mute: ^7%s^7 has been muted by ^7%s\n"',
				vic.client.pers.netname,
				if ent ~= nil then ent.client.pers.netname else "console"
			)
		)
	end
	return true
end

function G.G_admin_listadmins(ent, skiparg)
	local found = 0
	local search = ""
	local s = ""
	local start = 0
	local numeric = true
	local drawn = 0

	local i = 0
	while i < C.MAX_ADMIN_ADMINS and G.g_admin_admins[i] ~= nil do
		if G.g_admin_admins[i].level ~= 0 then
			found += 1
		end
		i += 1
	end
	if found == 0 then
		G.G_admin_print(ent, "^3!listadmins: ^7no admins defined\n")
		return false
	end

	if G.G_SayArgc() == 2 + skiparg then
		s = G.G_SayArgv(1 + skiparg)
		i = 0
		while i < C.MAX_NAME_LENGTH and i < #s do
			if not isdigit(string.byte(s, i + 1)) then
				numeric = false
			end
			i += 1
		end
		if numeric then
			start = QS.atoi(s)
			if start > 0 then
				start -= 1
			elseif start < 0 then
				start = found + start
			end
		else
			search = G.G_SanitiseString(s, C.MAX_NAME_LENGTH)
		end
	end

	if start >= found or start < 0 then
		start = 0
	end

	if start >= found then
		G.G_admin_print(ent, QS.va("^3!listadmins: ^7listing %d admins\n", found))
		return false
	end

	drawn = SF.admin_listadmins(ent, start, search)

	if search ~= "" then
		G.G_admin_print(ent, QS.va("^3!listadmins:^7 found %d admins matching '%s^7'\n", drawn, search))
	else
		G.G_admin_buffer_begin()
		G.G_admin_buffer_print(
			ent,
			QS.va(
				"^3!listadmins:^7 showing admin %d - %d of %d.  ",
				if found ~= 0 then start + 1 else 0,
				if (start + C.MAX_ADMIN_LISTITEMS) > found then found else (start + C.MAX_ADMIN_LISTITEMS),
				found
			)
		)
		if (start + C.MAX_ADMIN_LISTITEMS) < found then
			G.G_admin_buffer_print(
				ent,
				QS.va("run '!listadmins %d' to see more", start + C.MAX_ADMIN_LISTITEMS + 1)
			)
		end
		G.G_admin_buffer_print(ent, "\n")
		G.G_admin_buffer_end(ent)
	end
	return true
end

function G.G_admin_listplayers(ent, skiparg)
	local p
	local c
	local t
	local n
	local n2
	local n3
	local lname
	local guid_stub
	local muted
	local l

	G.G_admin_buffer_begin()
	G.G_admin_buffer_print(ent, QS.va("^3!listplayers: ^7%d players connected:\n", G.level.numConnectedClients))
	for i = 0, G.level.maxclients - 1 do
		p = G.level.clients[i]
		t = "S"
		c = S_COLOR_YELLOW
		if p.sess.sessionTeam == C.TEAM_BLUE then
			t = "B"
			c = S_COLOR_BLUE
		elseif p.sess.sessionTeam == C.TEAM_RED then
			t = "R"
			c = S_COLOR_RED
		elseif p.sess.sessionTeam == C.TEAM_FREE then
			t = "F"
			c = S_COLOR_GREEN
		elseif p.sess.sessionTeam == C.TEAM_NONE then
			t = "S"
			c = S_COLOR_WHITE
		end
		local skip = false
		if p.pers.connected == C.CON_CONNECTING then
			t = "C"
			c = S_COLOR_CYAN
		elseif p.pers.connected ~= C.CON_CONNECTED then
			skip = true
		end

		if not skip then
			guid_stub = string.sub(p.pers.guid, 25, 32)

			muted = ""
			if p.pers.muted then
				muted = "M"
			end

			l = 0
			n2 = G.G_SanitiseString(p.pers.netname, C.MAX_NAME_LENGTH)
			n = ""
			n3 = ""
			local j = 0
			while j < C.MAX_ADMIN_ADMINS and G.g_admin_admins[j] ~= nil do
				if QS.Q_stricmp(G.g_admin_admins[j].guid, p.pers.guid) == 0 then
					if ent ~= nil and G.G_admin_permission(G.g_entities[i], ADMF_INCOGNITO) then
						break
					end
					l = G.g_admin_admins[j].level
					n3 = G.G_SanitiseString(G.g_admin_admins[j].name, C.MAX_NAME_LENGTH)
					if QS.Q_stricmp(n2, n3) ~= 0 then
						n = G.g_admin_admins[j].name
					end
					break
				end
				j += 1
			end
			lname = ""
			j = 0
			while j < C.MAX_ADMIN_LEVELS and G.g_admin_levels[j] ~= nil do
				if G.g_admin_levels[j].level == l then
					local colorlen = 0
					local lvname = G.g_admin_levels[j].name
					for k = 0, #lvname - 1 do
						if QS.Q_IsColorString(lvname, k + 1) then
							colorlen += 2
						end
					end
					lname = QS.Com_sprintf(C.MAX_NAME_LENGTH, "%*s", SF.admin_level_maxname + colorlen, lvname)
					break
				end
				j += 1
			end

			G.G_admin_buffer_print(
				ent,
				QS.va(
					"%2i %s%s^7 %-2i %s^7 (*%s) ^1%1s^7 %s^7 %s%s^7%s\n",
					i,
					c,
					t,
					l,
					lname,
					guid_stub,
					muted,
					p.pers.netname,
					if n ~= "" then "(a.k.a. " else "",
					n,
					if n ~= "" then ")" else ""
				)
			)
		end
	end
	G.G_admin_buffer_end(ent)
	return true
end

function G.G_admin_showbans(ent, skiparg)
	local found = 0
	local max = -1
	local count
	local t
	local duration
	local max_name = 1
	local max_banner = 1
	local colorlen
	local len
	local secs
	local start = 0
	local filter = ""
	local date
	local made
	local n1 = ""
	local n2 = ""
	local numeric = true
	local ip_match = nil
	local ip_match_len = 0
	local name_match = ""
	local bans = G.g_admin_bans

	t = G.trap_RealTime(nil)

	local i = 0
	while i < C.MAX_ADMIN_BANS and bans[i] ~= nil do
		if not (bans[i].expires ~= 0 and (bans[i].expires - t) < 1) then
			found += 1
			max = i
		end
		i += 1
	end

	if max < 0 then
		G.G_admin_print(ent, "^3!showbans: ^7no bans to display\n")
		return false
	end

	if G.G_SayArgc() >= 2 + skiparg then
		filter = G.G_SayArgv(1 + skiparg)
		if G.G_SayArgc() >= 3 + skiparg then
			start = QS.atoi(filter)
			filter = G.G_SayArgv(2 + skiparg)
		end
		i = 0
		while i < C.MAX_NAME_LENGTH and i < #filter do
			local b = string.byte(filter, i + 1)
			if not isdigit(b) and b ~= 46 and b ~= 45 then
				numeric = false
				break
			end
			i += 1
		end
		if not numeric then
			name_match = G.G_SanitiseString(filter, C.MAX_NAME_LENGTH)
		elseif QS.strchr(filter, ".") ~= nil then
			ip_match = filter
			ip_match_len = #ip_match
		else
			start = QS.atoi(filter)
			filter = ""
		end
		if start > 0 then
			start -= 1
		elseif start < 0 then
			i = max
			count = 0
			while i >= 0 and count < -start do
				if bans[i].expires == 0 or (bans[i].expires - t) > 0 then
					count += 1
				end
				i -= 1
			end
			start = i + 1
		end
	end

	if start < 0 then
		start = 0
	end

	if start > max then
		G.G_admin_print(ent, QS.va("^3!showbans: ^7%d is the last valid ban\n", max + 1))
		return false
	end

	i = start
	count = 0
	while i <= max and count < C.MAX_ADMIN_SHOWBANS do
		local skip = false
		if bans[i].expires ~= 0 and (bans[i].expires - t) < 1 then
			skip = true
		end
		if not skip and name_match ~= "" then
			n1 = G.G_SanitiseString(bans[i].name, C.MAX_NAME_LENGTH * 2)
			if QS.strstr(n1, name_match) == nil then
				skip = true
			end
		end
		if not skip and ip_match ~= nil and QS.Q_strncmp(ip_match, bans[i].ip, ip_match_len) ~= 0 then
			skip = true
		end

		if not skip then
			count += 1

			len = QS.Q_PrintStrlen(bans[i].name)
			if len > max_name then
				max_name = len
			end
			len = QS.Q_PrintStrlen(bans[i].banner)
			if len > max_banner then
				max_banner = len
			end
		end
		i += 1
	end

	G.G_admin_buffer_begin()
	i = start
	count = 0
	while i <= max and count < C.MAX_ADMIN_SHOWBANS do
		local skip = false
		if bans[i].expires ~= 0 and (bans[i].expires - t) < 1 then
			skip = true
		end
		if not skip and name_match ~= "" then
			n1 = G.G_SanitiseString(bans[i].name, C.MAX_NAME_LENGTH * 2)
			if QS.strstr(n1, name_match) == nil then
				skip = true
			end
		end
		if not skip and ip_match ~= nil and QS.Q_strncmp(ip_match, bans[i].ip, ip_match_len) ~= 0 then
			skip = true
		end

		if not skip then
			count += 1

			date = ""
			made = bans[i].made
			local j = 0
			local mi = 1
			while made ~= nil and mi <= #made do
				if (j + 1) >= 11 then
					break
				end
				local ch = string.sub(made, mi, mi)
				if ch == " " then
					break
				end
				date = date .. ch
				mi += 1
				j += 1
			end

			secs = bans[i].expires - t
			duration = G.G_admin_duration(secs, 32)

			colorlen = 0
			for k = 0, #bans[i].name - 1 do
				if QS.Q_IsColorString(bans[i].name, k + 1) then
					colorlen += 2
				end
			end
			n1 = QS.Com_sprintf(C.MAX_NAME_LENGTH * 2, "%*s", max_name + colorlen, bans[i].name)

			colorlen = 0
			for k = 0, #bans[i].banner - 1 do
				if QS.Q_IsColorString(bans[i].banner, k + 1) then
					colorlen += 2
				end
			end
			n2 = QS.Com_sprintf(C.MAX_NAME_LENGTH * 2, "%*s", max_banner + colorlen, bans[i].banner)

			G.G_admin_buffer_print(
				ent,
				QS.va(
					"%4i %s^7 %-15s %-8s %s^7 %-10s\n     \\__ %s\n",
					i + 1,
					n1,
					bans[i].ip,
					date,
					n2,
					duration,
					bans[i].reason
				)
			)
		end
		i += 1
	end

	if name_match ~= "" or ip_match ~= nil then
		G.G_admin_buffer_print(
			ent,
			QS.va(
				"^3!showbans:^7 found %d matching bans by %s.  ",
				count,
				if ip_match ~= nil then "IP" else "name"
			)
		)
	else
		G.G_admin_buffer_print(
			ent,
			QS.va(
				"^3!showbans:^7 showing bans %d - %d of %d (%d total).",
				if found ~= 0 then start + 1 else 0,
				i,
				max + 1,
				found
			)
		)
	end

	if i <= max then
		G.G_admin_buffer_print(
			ent,
			QS.va(
				"  run !showbans %d%s%s to see more",
				i + 1,
				if filter ~= "" then " " else "",
				if filter ~= "" then filter else ""
			)
		)
	end
	G.G_admin_buffer_print(ent, "\n")
	G.G_admin_buffer_end(ent)
	return true
end

return nil
