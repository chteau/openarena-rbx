--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_admin.c, part 2 of 4).

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
-- Luau port of OpenArena 0.8.8's g_admin.c (gamecode 9e0f0c0) (part 2): ban checks, command dispatch, namelog, config reading, setlevel, kick.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QSBase = require("../shared/q_shared")
-- 0.8.8 compares with Q_stricmp (case-insensitive) everywhere master uses Q_strequal
local QS = setmetatable({
	Q_strequal = function(a, b)
		return QSBase.Q_stricmp(a, b) == 0
	end,
}, { __index = QSBase })
local BG = require("../shared/BG")

local SF = G.FileStatics("g_admin")

local ADMF_UNACCOUNTABLE = string.byte("2")
local ADMF_TEAMCHAT_CMD = string.byte("5")

local function isdigit(c)
	return c ~= nil and c >= 48 and c <= 57
end

function G.G_admin_duration(secs, dursize)
	dursize = dursize or 32
	if secs > (60 * 60 * 24 * 365 * 50) or secs < 0 then
		return QS.Q_strncpyz("PERMANENT", dursize)
	elseif secs >= (60 * 60 * 24 * 365) then
		return QS.Com_sprintf(dursize, "%1.1f years", (secs / (60 * 60 * 24 * 365.0)))
	elseif secs >= (60 * 60 * 24 * 90) then
		return QS.Com_sprintf(dursize, "%1.1f weeks", (secs / (60 * 60 * 24 * 7.0)))
	elseif secs >= (60 * 60 * 24) then
		return QS.Com_sprintf(dursize, "%1.1f days", (secs / (60 * 60 * 24.0)))
	elseif secs >= (60 * 60) then
		return QS.Com_sprintf(dursize, "%1.1f hours", (secs / (60 * 60.0)))
	elseif secs >= 60 then
		return QS.Com_sprintf(dursize, "%1.1f minutes", (secs / 60.0))
	else
		return QS.Com_sprintf(dursize, "%i seconds", secs)
	end
end

-- returns banned, reason
function G.G_admin_ban_check(userinfo, rlen)
	local reason = ""
	local t = G.trap_RealTime(nil)
	if userinfo == "" then
		return false, reason
	end
	local ip = QS.Info_ValueForKey(userinfo, "ip")
	if ip == "" then
		return false, reason
	end
	local guid = QS.Info_ValueForKey(userinfo, "cl_guid")
	local i = 0
	while i < C.MAX_ADMIN_BANS and G.g_admin_bans[i] do
		local ban = G.g_admin_bans[i]
		i += 1
		-- 0 is for perm ban
		if ban.expires ~= 0 and (ban.expires - t) < 1 then
			continue
		end
		if QS.strstr(ip, ban.ip) ~= nil then
			local duration = G.G_admin_duration(ban.expires - t, 32)
			reason = QS.Com_sprintf(rlen, "You have been banned by %s^7 reason: %s^7 expires: %s",
				ban.banner, ban.reason, duration)
			G.G_Printf("Banned player tried to connect from IP %s\n", ip)
			return true, reason
		end
		if guid ~= "" and QS.Q_strequal(ban.guid, guid) then
			local duration = G.G_admin_duration(ban.expires - t, 32)
			reason = QS.Com_sprintf(rlen, "You have been banned by %s^7 reason: %s^7 expires: %s",
				ban.banner, ban.reason, duration)
			G.G_Printf("Banned player tried to connect with GUID %s\n", guid)
			return true, reason
		end
	end
	return false, reason
end

function G.G_admin_cmd_check(ent, say)
	local skip = 0

	local command = G.G_SayArgv(0)
	if command == "" then
		return false
	end
	if QS.Q_strequal(command, "say") or
		(QS.Q_strequal(command, "say_team") and G.G_admin_permission(ent, ADMF_TEAMCHAT_CMD)) then
		skip = 1
		command = G.G_SayArgv(1)
	end

	local cmd
	if string.sub(command, 1, 1) == "!" then
		cmd = string.sub(command, 2)
	else
		return false
	end

	local i = 0
	while i < C.MAX_ADMIN_COMMANDS and G.g_admin_commands[i] do
		local ac = G.g_admin_commands[i]
		i += 1
		if not QS.Q_strequal(cmd, ac.command) then
			continue
		end

		if SF.admin_command_permission(ent, cmd) then
			-- flooding say will have already been accounted for in ClientCommand
			if not say and G.G_FloodLimited(ent) ~= 0 then
				return true
			end
			G.trap_SendConsoleCommand(C.EXEC_APPEND, ac.exec)
			SF.admin_log(ent, cmd, skip)
		else
			G.G_admin_print(ent, QS.va("^3!%s: ^7permission denied\n", ac.command))
			SF.admin_log(ent, "attempted", skip - 1)
		end
		return true
	end

	for j = 0, SF.adminNumCmds - 1 do
		local gc = G.g_admin_cmds[j]
		if not QS.Q_strequal(cmd, gc.keyword) then
			continue
		end

		if G.G_admin_permission(ent, string.byte(gc.flag, 1)) then
			-- flooding say will have already been accounted for in ClientCommand
			if not say and G.G_FloodLimited(ent) ~= 0 then
				return true
			end
			gc.handler(ent, skip)
			SF.admin_log(ent, cmd, skip)
		else
			G.G_admin_print(ent, QS.va("^3!%s: ^7permission denied\n", gc.keyword))
			SF.admin_log(ent, "attempted", skip - 1)
		end
		return true
	end
	return false
end

function G.G_admin_namelog_cleanup()
	local i = 0
	while i < C.MAX_ADMIN_NAMELOGS and G.g_admin_namelog[i] do
		G.g_admin_namelog[i] = nil
		i += 1
	end
end

function G.G_admin_namelog_update(client, disconnect)
	local clientNum = client.index

	local n1 = G.G_SanitiseString(client.pers.netname, 36)
	local i = 0
	while i < C.MAX_ADMIN_NAMELOGS and G.g_admin_namelog[i] do
		local nl = G.g_admin_namelog[i]
		local skip = false
		if disconnect and nl.slot ~= clientNum then
			skip = true
		end

		if not skip and not disconnect and not (nl.slot == clientNum or nl.slot == -1) then
			skip = true
		end

		if not skip and QS.Q_strequal(client.pers.ip, nl.ip) and QS.Q_strequal(client.pers.guid, nl.guid) then
			local j = 0
			while j < C.MAX_ADMIN_NAMELOG_NAMES and nl.name[j] ~= "" do
				local n2 = G.G_SanitiseString(nl.name[j], 36)
				if QS.Q_strequal(n1, n2) then
					break
				end
				j += 1
			end
			if j == C.MAX_ADMIN_NAMELOG_NAMES then
				j = C.MAX_ADMIN_NAMELOG_NAMES - 1
			end
			nl.name[j] = QS.Q_strncpyz(client.pers.netname, 36)
			nl.slot = if disconnect then -1 else clientNum

			-- if this player is connecting, they are no longer banned
			if not disconnect then
				nl.banned = false
			end

			return
		end
		i += 1
	end
	if i >= C.MAX_ADMIN_NAMELOGS then
		G.G_Printf("G_admin_namelog_update: warning, g_admin_namelogs overflow\n")
		return
	end
	local namelog = S.g_admin_namelog_t()
	for j = 0, C.MAX_ADMIN_NAMELOG_NAMES - 1 do
		namelog.name[j] = ""
	end
	namelog.ip = QS.Q_strncpyz(client.pers.ip, 40)
	namelog.guid = QS.Q_strncpyz(client.pers.guid, 33)
	namelog.name[0] = QS.Q_strncpyz(client.pers.netname, 36)
	namelog.slot = if disconnect then -1 else clientNum
	G.g_admin_namelog[i] = namelog
end

--KK-OAX Added Parsing Warnings
function G.G_admin_readconfig(ent, skiparg)
	local l = nil
	local a = nil
	local b = nil
	local c = nil
	local w = nil
	local lc, ac, bc, cc, wc = 0, 0, 0, 0, 0

	G.G_admin_cleanup()

	if G.g_admin.string == "" then
		G.G_admin_print(ent, "^3!readconfig: g_admin is not set, not loading configuration " ..
			"from a file\n")
		SF.admin_default_levels()
		return false
	end

	local len, f = G.trap_FS_FOpenFile(G.g_admin.string, C.FS_READ)
	if len < 0 then
		G.G_Printf("^3!readconfig: ^7could not open admin config file %s\n", G.g_admin.string)
		SF.admin_default_levels()
		return false
	end
	local text = G.trap_FS_Read(len, f)
	G.trap_FS_FCloseFile(f)
	local cnf = QS.cursor(text)

	SF.admin_level_maxname = 0

	local level_open, admin_open, ban_open, command_open, warning_open = false, false, false, false, false
	QS.COM_BeginParseSession(G.g_admin.string)
	while true do
		local t = QS.COM_Parse(cnf)
		if t == "" then
			break
		end

		if QS.Q_strequal(t, "[level]") then
			if lc >= C.MAX_ADMIN_LEVELS then
				return false
			end
			l = S.g_admin_level_t()
			G.g_admin_levels[lc] = l
			lc += 1
			level_open = true
			admin_open, ban_open, command_open, warning_open = false, false, false, false
		elseif QS.Q_strequal(t, "[admin]") then
			if ac >= C.MAX_ADMIN_ADMINS then
				return false
			end
			a = S.g_admin_admin_t()
			G.g_admin_admins[ac] = a
			ac += 1
			admin_open = true
			level_open, ban_open, command_open, warning_open = false, false, false, false
		elseif QS.Q_strequal(t, "[ban]") then
			if bc >= C.MAX_ADMIN_BANS then
				return false
			end
			b = S.g_admin_ban_t()
			G.g_admin_bans[bc] = b
			bc += 1
			ban_open = true
			level_open, admin_open, command_open, warning_open = false, false, false, false
		elseif QS.Q_strequal(t, "[command]") then
			if cc >= C.MAX_ADMIN_COMMANDS then
				return false
			end
			c = S.g_admin_command_t()
			G.g_admin_commands[cc] = c
			cc += 1
			c.levels[0] = -1
			command_open = true
			level_open, admin_open, ban_open, warning_open = false, false, false, false
		elseif QS.Q_strequal(t, "[warning]") then
			if wc >= C.MAX_ADMIN_WARNINGS then
				return false
			end
			w = S.g_admin_warning_t()
			G.g_admin_warnings[wc] = w
			wc += 1
			warning_open = true
			level_open, admin_open, ban_open, command_open = false, false, false, false
		elseif level_open then
			if QS.Q_strequal(t, "level") then
				l.level = G.readFile_int(cnf)
			elseif QS.Q_strequal(t, "name") then
				l.name = G.readFile_string(cnf, 64)
			elseif QS.Q_strequal(t, "flags") then
				l.flags = G.readFile_string(cnf, C.MAX_ADMIN_FLAGS)
			else
				QS.COM_ParseError("[level] unrecognized token \"%s\"", t)
			end
		elseif admin_open then
			if QS.Q_strequal(t, "name") then
				a.name = G.readFile_string(cnf, 36)
			elseif QS.Q_strequal(t, "guid") then
				a.guid = G.readFile_string(cnf, 33)
			elseif QS.Q_strequal(t, "level") then
				a.level = G.readFile_int(cnf)
			elseif QS.Q_strequal(t, "flags") then
				a.flags = G.readFile_string(cnf, C.MAX_ADMIN_FLAGS)
			else
				QS.COM_ParseError("[admin] unrecognized token \"%s\"", t)
			end
		elseif ban_open then
			if QS.Q_strequal(t, "name") then
				b.name = G.readFile_string(cnf, 36)
			elseif QS.Q_strequal(t, "guid") then
				b.guid = G.readFile_string(cnf, 33)
			elseif QS.Q_strequal(t, "ip") then
				b.ip = G.readFile_string(cnf, 40)
			elseif QS.Q_strequal(t, "reason") then
				b.reason = G.readFile_string(cnf, C.MAX_ADMIN_BAN_REASON)
			elseif QS.Q_strequal(t, "made") then
				b.made = G.readFile_string(cnf, 20)
			elseif QS.Q_strequal(t, "expires") then
				b.expires = G.readFile_int(cnf)
			elseif QS.Q_strequal(t, "banner") then
				b.banner = G.readFile_string(cnf, 36)
			else
				QS.COM_ParseError("[ban] unrecognized token \"%s\"", t)
			end
		elseif command_open then
			if QS.Q_strequal(t, "command") then
				c.command = G.readFile_string(cnf, C.MAX_ADMIN_CMD_LEN)
			elseif QS.Q_strequal(t, "exec") then
				c.exec = G.readFile_string(cnf, 256)
			elseif QS.Q_strequal(t, "desc") then
				c.desc = G.readFile_string(cnf, 256)
			elseif QS.Q_strequal(t, "levels") then
				local levels = G.readFile_string(cnf, C.MAX_STRING_CHARS)
				local level = QS.cursor(levels)
				local cmdlevel = 0

				while cmdlevel < C.MAX_ADMIN_LEVELS do
					local lp = QS.COM_Parse(level)
					if lp == "" then
						break
					end
					c.levels[cmdlevel] = QS.atoi(lp)
					cmdlevel += 1
				end
				-- ensure the list is -1 terminated
				c.levels[cmdlevel] = -1
			else
				QS.COM_ParseError("[command] unrecognized token \"%s\"", t)
			end
		elseif warning_open then
			if QS.Q_strequal(t, "name") then
				w.name = G.readFile_string(cnf, 36)
			elseif QS.Q_strequal(t, "guid") then
				w.guid = G.readFile_string(cnf, 33)
			elseif QS.Q_strequal(t, "ip") then
				w.ip = G.readFile_string(cnf, 40)
			elseif QS.Q_strequal(t, "warning") then
				w.warning = G.readFile_string(cnf, C.MAX_ADMIN_BAN_REASON)
			elseif QS.Q_strequal(t, "made") then
				w.made = G.readFile_string(cnf, 20)
			elseif QS.Q_strequal(t, "expires") then
				w.expires = G.readFile_int(cnf)
			elseif QS.Q_strequal(t, "warner") then
				w.warner = G.readFile_string(cnf, 36)
			else
				QS.COM_ParseError("[warning] unrecognized token \"%s\"", t)
			end
		else
			QS.COM_ParseError("unexpected token \"%s\"", t)
		end
	end
	G.G_admin_print(ent, QS.va("^3!readconfig: ^7loaded %d levels, %d admins, %d bans, %d commands, %d warnings\n",
		lc, ac, bc, cc, wc))
	if lc == 0 then
		SF.admin_default_levels()
	else
		-- max printable name length for formatting
		local i = 0
		while i < C.MAX_ADMIN_LEVELS and G.g_admin_levels[i] do
			len = QS.Q_PrintStrlen(G.g_admin_levels[i].name)
			if len > SF.admin_level_maxname then
				SF.admin_level_maxname = len
			end
			i += 1
		end
	end
	-- reset adminLevel
	local level = G.level
	for i = 0, level.maxclients - 1 do
		if level.clients[i].pers.connected ~= C.CON_DISCONNECTED then
			level.clients[i].pers.adminLevel = G.G_admin_level(G.g_entities[i])
		end
	end
	return true
end

function G.G_admin_time(ent, skiparg)
	local qt = {}

	G.trap_RealTime(qt)
	G.G_admin_print(ent, QS.va("^3!time: ^7local time is %02i:%02i:%02i\n",
		qt.tm_hour, qt.tm_min, qt.tm_sec))
	return true
end

function G.G_admin_setlevel(ent, skiparg)
	local name = ""
	local adminname = ""
	local testname = ""
	local guid = ""
	local vic = nil
	local updated = false
	local found = false
	local numeric = true
	local matches = 0
	local id = -1
	local level = G.level

	if G.G_SayArgc() < 3 + skiparg then
		G.G_admin_print(ent, "^3!setlevel: ^7usage: !setlevel [name|slot#] [level]\n")
		return false
	end
	testname = G.G_SayArgv(1 + skiparg)
	local lstr = G.G_SayArgv(2 + skiparg)
	local l = QS.atoi(lstr)
	name = G.G_SanitiseString(testname, 36)
	for i = 0, 35 do
		local ch = string.byte(name, i + 1)
		if ch == nil then
			break
		end
		if not isdigit(ch) then
			numeric = false
			break
		end
	end
	if numeric then
		id = QS.atoi(name)
	end

	if ent ~= nil and l > ent.client.pers.adminLevel then
		G.G_admin_print(ent, "^3!setlevel: ^7you may not use !setlevel to set a level higher " ..
			"than your current level\n")
		return false
	end

	-- if admin is activated for the first time on a running server, we need
	-- to ensure at least the default levels get created
	if ent == nil and not G.g_admin_levels[0] then
		G.G_admin_readconfig(nil, 0)
	end

	local i = 0
	while i < C.MAX_ADMIN_LEVELS and G.g_admin_levels[i] do
		if G.g_admin_levels[i].level == l then
			found = true
			break
		end
		i += 1
	end
	if not found then
		G.G_admin_print(ent, "^3!setlevel: ^7level is not defined\n")
		return false
	end

	if numeric and id >= 0 and id < level.maxclients then
		vic = G.g_entities[id]
	end

	if vic ~= nil and vic.client ~= nil and vic.client.pers.connected ~= C.CON_DISCONNECTED then
		adminname = QS.Q_strncpyz(vic.client.pers.netname, 36)
		guid = QS.Q_strncpyz(vic.client.pers.guid, 33)
		matches = 1
	elseif numeric and id >= C.MAX_CLIENTS and id < C.MAX_CLIENTS + C.MAX_ADMIN_ADMINS
		and G.g_admin_admins[id - C.MAX_CLIENTS] then
		adminname = QS.Q_strncpyz(G.g_admin_admins[id - C.MAX_CLIENTS].name, 36)
		guid = QS.Q_strncpyz(G.g_admin_admins[id - C.MAX_CLIENTS].guid, 33)
		matches = 1
	else
		i = 0
		while i < C.MAX_ADMIN_ADMINS and G.g_admin_admins[i] and matches < 2 do
			testname = G.G_SanitiseString(G.g_admin_admins[i].name, 36)
			if QS.strstr(testname, name) ~= nil then
				adminname = QS.Q_strncpyz(G.g_admin_admins[i].name, 36)
				guid = QS.Q_strncpyz(G.g_admin_admins[i].guid, 33)
				matches += 1
			end
			i += 1
		end
		i = 0
		while i < level.maxclients and matches < 2 do
			if level.clients[i].pers.connected == C.CON_DISCONNECTED then
				i += 1
				continue
			end
			if matches ~= 0 and QS.Q_strequal(level.clients[i].pers.guid, guid) then
				vic = G.g_entities[i]
				i += 1
				continue
			end
			testname = G.G_SanitiseString(level.clients[i].pers.netname, 36)
			if QS.strstr(testname, name) ~= nil then
				vic = G.g_entities[i]
				matches += 1
				guid = QS.Q_strncpyz(vic.client.pers.guid, 33)
			end
			i += 1
		end
		if vic ~= nil and vic.client ~= nil then
			adminname = QS.Q_strncpyz(vic.client.pers.netname, 36)
		end
	end

	if matches == 0 then
		G.G_admin_print(ent, "^3!setlevel:^7 no match.  use !listplayers or !listadmins to " ..
			"find an appropriate number to use instead of name.\n")
		return false
	end
	if matches > 1 then
		G.G_admin_print(ent, "^3!setlevel:^7 more than one match.  Use the admin number " ..
			"instead:\n")
		SF.admin_listadmins(ent, 0, name)
		return false
	end

	if ent ~= nil and not SF.admin_higher_guid(ent.client.pers.guid, guid) then
		G.G_admin_print(ent, "^3!setlevel: ^7sorry, but your intended victim has a higher" ..
			" admin level than you\n")
		return false
	end

	i = 0
	while i < C.MAX_ADMIN_ADMINS and G.g_admin_admins[i] do
		if QS.Q_strequal(G.g_admin_admins[i].guid, guid) then
			G.g_admin_admins[i].level = l
			G.g_admin_admins[i].name = QS.Q_strncpyz(adminname, 36)
			updated = true
		end
		i += 1
	end
	if not updated then
		if i == C.MAX_ADMIN_ADMINS then
			G.G_admin_print(ent, "^3!setlevel: ^7too many admins\n")
			return false
		end
		local a = S.g_admin_admin_t()
		a.level = l
		a.name = QS.Q_strncpyz(adminname, 36)
		a.guid = QS.Q_strncpyz(guid, 33)
		a.flags = ""
		G.g_admin_admins[i] = a
	end

	G.trap_SendServerCommand(-1, QS.va(
		"print \"^3!setlevel: ^7%s^7 was given level %d admin rights by %s\n\"",
		adminname, l, if ent ~= nil then ent.client.pers.netname else "console"))
	if vic ~= nil and vic.client ~= nil then
		vic.client.pers.adminLevel = l
	end

	if G.g_admin.string == "" then
		G.G_admin_print(ent, "^3!setlevel: ^7WARNING g_admin not set, not saving admin record " ..
			"to a file\n")
	else
		SF.admin_writeconfig()
	end
	return true
end

function SF.admin_create_ban(ent, netname, guid, ip, seconds, reason)
	local qt = {}

	local t = G.trap_RealTime(qt)
	local b = S.g_admin_ban_t()

	b.name = QS.Q_strncpyz(netname, 36)
	b.guid = QS.Q_strncpyz(guid, 33)
	b.ip = QS.Q_strncpyz(ip, 40)

	b.made = QS.Com_sprintf(20, "%02i/%02i/%02i %02i:%02i:%02i",
		qt.tm_mon + 1, qt.tm_mday, Q.imod(qt.tm_year, 100),
		qt.tm_hour, qt.tm_min, qt.tm_sec)

	if ent ~= nil then
		b.banner = QS.Q_strncpyz(ent.client.pers.netname, 36)
	else
		b.banner = QS.Q_strncpyz("console", 36)
	end
	if seconds == 0 then
		b.expires = 0
	else
		b.expires = t + seconds
	end
	if reason == "" then
		b.reason = QS.Q_strncpyz("banned by admin", C.MAX_ADMIN_BAN_REASON)
	else
		b.reason = QS.Q_strncpyz(reason, C.MAX_ADMIN_BAN_REASON)
	end
	local i = 0
	while i < C.MAX_ADMIN_BANS and G.g_admin_bans[i] do
		i += 1
	end
	if i == C.MAX_ADMIN_BANS then
		G.G_admin_print(ent, "^3!ban: ^7too many bans\n")
		return false
	end
	G.g_admin_bans[i] = b
	return true
end

--KK-OAX Copied create_ban to get Time Stuff Right (Didn't feel like writing code to parse it)
function SF.admin_create_warning(ent, netname, guid, ip, seconds, warning)
	local qt = {}

	local t = G.trap_RealTime(qt)
	local w = S.g_admin_warning_t()

	w.name = QS.Q_strncpyz(netname, 36)
	w.guid = QS.Q_strncpyz(guid, 33)
	w.ip = QS.Q_strncpyz(ip, 40)

	w.made = QS.Com_sprintf(20, "%02i/%02i/%02i %02i:%02i:%02i",
		qt.tm_mon + 1, qt.tm_mday, Q.imod(qt.tm_year, 100),
		qt.tm_hour, qt.tm_min, qt.tm_sec)

	if ent ~= nil then
		w.warner = QS.Q_strncpyz(ent.client.pers.netname, 36)
	else
		w.warner = QS.Q_strncpyz("console", 36)
	end
	if seconds == 0 then
		w.expires = 0
	else
		w.expires = t + seconds
	end
	if warning == "" then
		w.warning = QS.Q_strncpyz("warned by admin", C.MAX_ADMIN_BAN_REASON)
	else
		w.warning = QS.Q_strncpyz(warning, C.MAX_ADMIN_BAN_REASON)
	end
	local i = 0
	while i < C.MAX_ADMIN_WARNINGS and G.g_admin_warnings[i] do
		i += 1
	end
	if i == C.MAX_ADMIN_WARNINGS then
		G.G_admin_print(ent, "^3!warn: ^7too many warnings\n")
		return false
	end
	G.g_admin_warnings[i] = w
	return true
end

function G.G_admin_parse_time(time)
	local seconds, num = 0, 0
	local p = 1
	while p <= #time do
		if not isdigit(string.byte(time, p)) then
			return -1
		end
		while isdigit(string.byte(time, p)) do
			num = num * 10 + string.byte(time, p) - 48
			p += 1
		end

		if p > #time then
			break
		end
		local ch = string.sub(time, p, p)
		p += 1
		if ch == "w" then
			num *= 7
		end
		if ch == "w" or ch == "d" then
			num *= 24
		end
		if ch == "w" or ch == "d" or ch == "h" then
			num *= 60
		end
		if ch == "w" or ch == "d" or ch == "h" or ch == "m" then
			num *= 60
		end
		if not (ch == "w" or ch == "d" or ch == "h" or ch == "m" or ch == "s") then
			return -1
		end
		seconds += num
		num = 0
	end
	if num ~= 0 then
		seconds += num
	end
	return seconds
end

function G.G_admin_kick(ent, skiparg)
	local pids = {}

	local minargc = 3 + skiparg
	if G.G_admin_permission(ent, ADMF_UNACCOUNTABLE) then
		minargc = 2 + skiparg
	end

	if G.G_SayArgc() < minargc then
		G.G_admin_print(ent, "^3!kick: ^7usage: !kick [name] [reason]\n")
		return false
	end
	local name = G.G_SayArgv(1 + skiparg)
	local reason = G.G_SayConcatArgs(2 + skiparg)
	local found = G.G_ClientNumbersFromString(name, pids, C.MAX_CLIENTS)
	if found ~= 1 then
		local err = G.G_MatchOnePlayer(pids, found, C.MAX_STRING_CHARS)
		G.G_admin_print(ent, QS.va("^3!kick: ^7%s\n", err))
		return false
	end
	local vic = G.g_entities[pids[0]]
	if not SF.admin_higher(ent, vic) then
		G.G_admin_print(ent, "^3!kick: ^7sorry, but your intended victim has a higher admin" ..
			" level than you\n")
		return false
	end
	if vic.client.pers.localClient then
		G.G_admin_print(ent, "^3!kick: ^7disconnecting the host would end the game\n")
		return false
	end
	SF.admin_create_ban(ent,
		vic.client.pers.netname,
		vic.client.pers.guid,
		vic.client.pers.ip,
		G.G_admin_parse_time(QS.va("1s%s", G.g_adminTempBan.string)),
		if reason ~= "" then reason else "kicked by admin")
	if G.g_admin.string ~= "" then
		SF.admin_writeconfig()
	end

	G.trap_SendServerCommand(pids[0],
		QS.va("disconnect \"You have been kicked.\n%s^7\nreason:\n%s\"",
			if ent ~= nil then QS.va("admin:\n%s", ent.client.pers.netname) else "",
			if reason ~= "" then reason else "kicked by admin"))

	G.trap_DropClient(pids[0], QS.va("has been kicked%s^7. reason: %s",
		if ent ~= nil then QS.va(" by %s", ent.client.pers.netname) else "",
		if reason ~= "" then reason else "kicked by admin"))

	return true
end

return nil
