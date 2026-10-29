--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_admin.c, part 1 of 4).

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
-- Luau port of g_admin.c (part 1): admin command table, permission checks,
-- config writing, default levels, admin log and admin listing.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SF = G.FileStatics("g_admin")

-- g_admin.h flag characters
local ADMF_IMMUTABLE = string.byte("!")
local ADMF_INCOGNITO = string.byte("@")

local function charAt(s: string, i: number): number
	return string.byte(s, i + 1) or 0
end

-- big ugly global buffer for use with buffered printing of long outputs
SF.g_bfb = ""

local function cmdHandler(name: string)
	return function(...)
		return G[name](...)
	end
end

-- note: list ordered alphabetically
G.g_admin_cmds = {
	[0] = {
		cmd = "adjustban", handler = cmdHandler("G_admin_adjustban"), flag = "b",
		["function"] = "change the duration or reason of a ban.  duration is specified as "
			.. "numbers followed by units 'w' (weeks), 'd' (days), 'h' (hours) or "
			.. "'m' (minutes), or seconds if no units are specified.  if the duration is"
			.. " preceded by a + or -, the ban duration will be extended or shortened by"
			.. " the specified amount",
		syntax = "[^3ban#^7] (^5duration^7) (^5reason^7)",
	},
	{
		cmd = "admintest", handler = cmdHandler("G_admin_admintest"), flag = "a",
		["function"] = "display your current admin level",
		syntax = "",
	},
	{
		cmd = "allready", handler = cmdHandler("G_admin_allready"), flag = "y",
		["function"] = "makes everyone ready in intermission",
		syntax = "",
	},
	{
		cmd = "ban", handler = cmdHandler("G_admin_ban"), flag = "b",
		["function"] = "ban a player by IP and GUID with an optional expiration time and reason."
			.. " duration is specified as numbers followed by units 'w' (weeks), 'd' "
			.. "(days), 'h' (hours) or 'm' (minutes), or seconds if no units are "
			.. "specified",
		syntax = "[^3name|slot#|IP^7] (^5duration^7) (^5reason^7)",
	},
	{
		cmd = "cancelvote", handler = cmdHandler("G_admin_cancelvote"), flag = "c",
		["function"] = "cancel a vote taking place",
		syntax = "",
	},
	--KK-OAX
	{
		cmd = "disorient", handler = cmdHandler("G_admin_disorient"), flag = "d",
		["function"] = "disorient a player by flipping player's view and controls",
		syntax = "[^3name|slot#^7] (^hreason^7)",
	},
	{
		cmd = "help", handler = cmdHandler("G_admin_help"), flag = "h",
		["function"] = "display commands available to you or help on a specific command",
		syntax = "(^5command^7)",
	},
	{
		cmd = "kick", handler = cmdHandler("G_admin_kick"), flag = "k",
		["function"] = "kick a player with an optional reason",
		syntax = "[^3name|slot#^7] (^5reason^7)",
	},
	{
		cmd = "listadmins", handler = cmdHandler("G_admin_listadmins"), flag = "D",
		["function"] = "display a list of all server admins and their levels",
		syntax = "(^5name|start admin#^7)",
	},
	{
		cmd = "listplayers", handler = cmdHandler("G_admin_listplayers"), flag = "i",
		["function"] = "display a list of players, their client numbers and their levels",
		syntax = "",
	},
	{
		cmd = "lock", handler = cmdHandler("G_admin_lock"), flag = "K",
		["function"] = "lock a team to prevent anyone from joining it",
		syntax = "[^3a|h^7]",
	},
	--KK-OAX
	{
		cmd = "map", handler = cmdHandler("G_admin_map"), flag = "M",
		["function"] = "load a map",
		syntax = "[^3mapname^7]",
	},
	{
		cmd = "mute", handler = cmdHandler("G_admin_mute"), flag = "m",
		["function"] = "mute a player",
		syntax = "[^3name|slot#^7]",
	},
	{
		cmd = "namelog", handler = cmdHandler("G_admin_namelog"), flag = "e",
		["function"] = "display a list of names used by recently connected players",
		syntax = "(^5name^7)",
	},
	{
		cmd = "nextmap", handler = cmdHandler("G_admin_nextmap"), flag = "n",
		["function"] = "go to the next map in the cycle",
		syntax = "",
	},
	--KK-OAX
	{
		cmd = "orient", handler = cmdHandler("G_admin_orient"), flag = "d",
		["function"] = "orient a player after a !disorient",
		syntax = "[^3name|slot#^7]",
	},
	{
		cmd = "passvote", handler = cmdHandler("G_admin_passvote"), flag = "V",
		["function"] = "pass a vote currently taking place",
		syntax = "",
	},
	{
		cmd = "putteam", handler = cmdHandler("G_admin_putteam"), flag = "p",
		["function"] = "move a player to a specified team",
		syntax = "[^3name|slot#^7] [^3h|a|s^7]",
	},
	{
		cmd = "readconfig", handler = cmdHandler("G_admin_readconfig"), flag = "G",
		["function"] = "reloads the admin config file and refreshes permission flags",
		syntax = "",
	},
	{
		cmd = "rename", handler = cmdHandler("G_admin_rename"), flag = "N",
		["function"] = "rename a player",
		syntax = "[^3name|slot#^7] [^3new name^7]",
	},
	{
		cmd = "restart", handler = cmdHandler("G_admin_restart"), flag = "r",
		["function"] = "restart the current map (optionally using named layout)",
		syntax = "",
	},
	{
		cmd = "setlevel", handler = cmdHandler("G_admin_setlevel"), flag = "s",
		["function"] = "sets the admin level of a player",
		syntax = "[^3name|slot#|admin#^7] [^3level^7]",
	},
	{
		cmd = "showbans", handler = cmdHandler("G_admin_showbans"), flag = "B",
		["function"] = "display a (partial) list of active bans",
		syntax = "(^5start at ban#^7) (^5name|IP^7)",
	},
	{
		cmd = "slap", handler = cmdHandler("G_admin_slap"), flag = "S",
		["function"] = "Reduces the health of the selected player by the damage specified",
		syntax = "[^3name|slot#] [damage] [reason]",
	},
	{
		cmd = "spec999", handler = cmdHandler("G_admin_spec999"), flag = "P",
		["function"] = "move 999 pingers to the spectator team",
		syntax = "",
	},
	{
		cmd = "time", handler = cmdHandler("G_admin_time"), flag = "C",
		["function"] = "show the current local server time",
		syntax = "",
	},
	{
		cmd = "unban", handler = cmdHandler("G_admin_unban"), flag = "b",
		["function"] = "unbans a player specified by the slot as seen in showbans",
		syntax = "[^3ban#^7]",
	},
	{
		cmd = "unlock", handler = cmdHandler("G_admin_unlock"), flag = "K",
		["function"] = "unlock a locked team",
		syntax = "[^3a|h^7]",
	},
	{
		cmd = "unmute", handler = cmdHandler("G_admin_mute"), flag = "m",
		["function"] = "unmute a muted player",
		syntax = "[^3name|slot#^7]",
	},
	--KK-OAX
	{
		cmd = "warn", handler = cmdHandler("G_admin_warn"), flag = "w",
		["function"] = "warn a player",
		syntax = "[^3name|slot#^7] [reason]",
	},
}

SF.adminNumCmds = 0
while G.g_admin_cmds[SF.adminNumCmds] ~= nil do
	SF.adminNumCmds += 1
end

SF.admin_level_maxname = 0
G.g_admin_levels = {}
G.g_admin_admins = {}
G.g_admin_bans = {}
G.g_admin_commands = {}
G.g_admin_namelog = {}
--KK-OAX Load us up some warnings here....
G.g_admin_warnings = {}

function G.G_admin_permission(ent, flag)
	local i
	local l = 0
	local flags: string
	local p: number

	if type(flag) == "string" then
		flag = string.byte(flag)
	end

	-- console always wins
	if ent == nil then
		return true
	end

	i = 0
	while i < C.MAX_ADMIN_ADMINS and G.g_admin_admins[i] ~= nil do
		if QS.Q_strequal(ent.client.pers.guid, G.g_admin_admins[i].guid) then
			flags = G.g_admin_admins[i].flags
			p = 0
			while charAt(flags, p) ~= 0 do
				local c = charAt(flags, p)
				if c == flag then
					return true
				elseif c == string.byte("-") then
					while true do
						local cur = charAt(flags, p)
						p += 1
						if cur == 0 then
							break
						end
						if charAt(flags, p) == flag then
							return false
						end
						if charAt(flags, p) == string.byte("+") then
							break
						end
					end
				elseif c == string.byte("*") then
					while true do
						local cur = charAt(flags, p)
						p += 1
						if cur == 0 then
							break
						end
						if charAt(flags, p) == flag then
							return false
						end
					end
					-- flags with significance only for individuals (
					-- like ADMF_INCOGNITO and ADMF_IMMUTABLE are NOT covered
					-- by the '*' wildcard.  They must be specified manually.
					return (flag ~= ADMF_INCOGNITO and flag ~= ADMF_IMMUTABLE)
				end
				p += 1
			end
			l = G.g_admin_admins[i].level
		end
		i += 1
	end
	i = 0
	while i < C.MAX_ADMIN_LEVELS and G.g_admin_levels[i] ~= nil do
		if G.g_admin_levels[i].level == l then
			flags = G.g_admin_levels[i].flags
			p = 0
			while charAt(flags, p) ~= 0 do
				local c = charAt(flags, p)
				if c == flag then
					return true
				end
				if c == string.byte("*") then
					while true do
						local cur = charAt(flags, p)
						p += 1
						if cur == 0 then
							break
						end
						if charAt(flags, p) == flag then
							return false
						end
					end
					-- flags with significance only for individuals (
					-- like ADMF_INCOGNITO and ADMF_IMMUTABLE are NOT covered
					-- by the '*' wildcard.  They must be specified manually.
					return (flag ~= ADMF_INCOGNITO and flag ~= ADMF_IMMUTABLE)
				end
				p += 1
			end
		end
		i += 1
	end
	return false
end

-- Returns qboolean, err (the C err buffer).
function G.G_admin_name_check(ent, name, len)
	local err = ""
	local client
	local testName = ""
	local name2 = ""

	name2 = G.G_SanitiseString(name, C.MAX_NAME_LENGTH)

	if QS.Q_strequal(name2, "UnnamedPlayer") then
		return true, err
	end

	for i = 0, G.level.maxclients - 1 do
		client = G.level.clients[i]
		if client.pers.connected == C.CON_DISCONNECTED then
			continue
		end

		-- can rename ones self to the same name using different colors
		if i == ent.index then
			continue
		end

		testName = G.G_SanitiseString(client.pers.netname, C.MAX_NAME_LENGTH)
		if QS.Q_strequal(name2, testName) then
			err = QS.Com_sprintf(len, "The name '%s^7' is already in use", name)
			return false, err
		end
	end

	if G.g_adminNameProtect.integer == 0 then
		return true, err
	end

	local i = 0
	while i < C.MAX_ADMIN_ADMINS and G.g_admin_admins[i] ~= nil do
		if G.g_admin_admins[i].level < 1 then
			i += 1
			continue
		end
		testName = G.G_SanitiseString(G.g_admin_admins[i].name, C.MAX_NAME_LENGTH)
		if QS.Q_strequal(name2, testName) and not QS.Q_strequal(ent.client.pers.guid, G.g_admin_admins[i].guid) then
			err = QS.Com_sprintf(len, "The name '%s^7' belongs to an admin, "
				.. "please use another name", name)
			return false, err
		end
		i += 1
	end
	return true, err
end

function SF.admin_higher_guid(admin_guid, victim_guid)
	local alevel = 0

	local i = 0
	while i < C.MAX_ADMIN_ADMINS and G.g_admin_admins[i] ~= nil do
		if QS.Q_strequal(admin_guid, G.g_admin_admins[i].guid) then
			alevel = G.g_admin_admins[i].level
			break
		end
		i += 1
	end
	i = 0
	while i < C.MAX_ADMIN_ADMINS and G.g_admin_admins[i] ~= nil do
		if QS.Q_strequal(victim_guid, G.g_admin_admins[i].guid) then
			if alevel < G.g_admin_admins[i].level then
				return false
			end
			return QS.strstr(G.g_admin_admins[i].flags, QS.va("%c", ADMF_IMMUTABLE)) == nil
		end
		i += 1
	end
	return true
end

function SF.admin_higher(admin, victim)
	-- console always wins
	if admin == nil then
		return true
	end
	-- just in case
	if victim == nil then
		return true
	end

	return SF.admin_higher_guid(admin.client.pers.guid, victim.client.pers.guid)
end

--KK-OAX Moved the Read/Write int/String functions to g_fileops.c for portability
--across GAME

--KK-OAX Added Warnings
function SF.admin_writeconfig()
	local f
	local len, t
	local levels = ""

	if G.g_admin.string == "" then
		G.G_Printf("^3" .. "WARNING: g_admin is not set. "
			.. " configuration will not be saved to a file.\n")
		return
	end
	t = G.trap_RealTime(nil)
	len, f = G.trap_FS_FOpenFile(G.g_admin.string, C.FS_WRITE)
	if len < 0 then
		G.G_Printf("admin_writeconfig: could not open g_admin file \"%s\"\n",
			G.g_admin.string)
		return
	end
	local i = 0
	while i < C.MAX_ADMIN_LEVELS and G.g_admin_levels[i] ~= nil do
		G.trap_FS_Write("[level]\n", 8, f)
		G.trap_FS_Write("level   = ", 10, f)
		G.writeFile_int(G.g_admin_levels[i].level, f)
		G.trap_FS_Write("name    = ", 10, f)
		G.writeFile_string(G.g_admin_levels[i].name, f)
		G.trap_FS_Write("flags   = ", 10, f)
		G.writeFile_string(G.g_admin_levels[i].flags, f)
		G.trap_FS_Write("\n", 1, f)
		i += 1
	end
	i = 0
	while i < C.MAX_ADMIN_ADMINS and G.g_admin_admins[i] ~= nil do
		-- don't write level 0 users
		if G.g_admin_admins[i].level == 0 then
			i += 1
			continue
		end

		G.trap_FS_Write("[admin]\n", 8, f)
		G.trap_FS_Write("name    = ", 10, f)
		G.writeFile_string(G.g_admin_admins[i].name, f)
		G.trap_FS_Write("guid    = ", 10, f)
		G.writeFile_string(G.g_admin_admins[i].guid, f)
		G.trap_FS_Write("level   = ", 10, f)
		G.writeFile_int(G.g_admin_admins[i].level, f)
		G.trap_FS_Write("flags   = ", 10, f)
		G.writeFile_string(G.g_admin_admins[i].flags, f)
		G.trap_FS_Write("\n", 1, f)
		i += 1
	end
	i = 0
	while i < C.MAX_ADMIN_BANS and G.g_admin_bans[i] ~= nil do
		-- don't write expired bans
		-- if expires is 0, then it's a perm ban
		if G.g_admin_bans[i].expires ~= 0 and (G.g_admin_bans[i].expires - t) < 1 then
			i += 1
			continue
		end

		G.trap_FS_Write("[ban]\n", 6, f)
		G.trap_FS_Write("name    = ", 10, f)
		G.writeFile_string(G.g_admin_bans[i].name, f)
		G.trap_FS_Write("guid    = ", 10, f)
		G.writeFile_string(G.g_admin_bans[i].guid, f)
		G.trap_FS_Write("ip      = ", 10, f)
		G.writeFile_string(G.g_admin_bans[i].ip, f)
		G.trap_FS_Write("reason  = ", 10, f)
		G.writeFile_string(G.g_admin_bans[i].reason, f)
		G.trap_FS_Write("made    = ", 10, f)
		G.writeFile_string(G.g_admin_bans[i].made, f)
		G.trap_FS_Write("expires = ", 10, f)
		G.writeFile_int(G.g_admin_bans[i].expires, f)
		G.trap_FS_Write("banner  = ", 10, f)
		G.writeFile_string(G.g_admin_bans[i].banner, f)
		G.trap_FS_Write("\n", 1, f)
		i += 1
	end
	i = 0
	while i < C.MAX_ADMIN_COMMANDS and G.g_admin_commands[i] ~= nil do
		levels = ""
		G.trap_FS_Write("[command]\n", 10, f)
		G.trap_FS_Write("command = ", 10, f)
		G.writeFile_string(G.g_admin_commands[i].command, f)
		G.trap_FS_Write("exec    = ", 10, f)
		G.writeFile_string(G.g_admin_commands[i].exec, f)
		G.trap_FS_Write("desc    = ", 10, f)
		G.writeFile_string(G.g_admin_commands[i].desc, f)
		G.trap_FS_Write("levels  = ", 10, f)
		local j = 0
		while G.g_admin_commands[i].levels[j] ~= -1 do
			levels = QS.Q_strcat(levels, C.MAX_STRING_CHARS,
				QS.va("%i ", G.g_admin_commands[i].levels[j]))
			j += 1
		end
		G.writeFile_string(levels, f)
		G.trap_FS_Write("\n", 1, f)
		i += 1
	end
	i = 0
	while i < C.MAX_ADMIN_WARNINGS and G.g_admin_warnings[i] ~= nil do
		-- don't write expired warnings
		-- if expires is 0, then it's a perm warning
		-- it will get loaded everytime they connect!!!!
		if G.g_admin_warnings[i].expires ~= 0 and (G.g_admin_warnings[i].expires - t) < 1 then
			i += 1
			continue
		end

		G.trap_FS_Write("[warning]\n", 10, f)
		G.trap_FS_Write("name    = ", 10, f)
		G.writeFile_string(G.g_admin_warnings[i].name, f)
		G.trap_FS_Write("guid    = ", 10, f)
		G.writeFile_string(G.g_admin_warnings[i].guid, f)
		G.trap_FS_Write("ip      = ", 10, f)
		G.writeFile_string(G.g_admin_warnings[i].ip, f)
		G.trap_FS_Write("warning = ", 10, f)
		G.writeFile_string(G.g_admin_warnings[i].warning, f)
		G.trap_FS_Write("made    = ", 10, f)
		G.writeFile_string(G.g_admin_warnings[i].made, f)
		G.trap_FS_Write("expires = ", 10, f)
		G.writeFile_int(G.g_admin_warnings[i].expires, f)
		G.trap_FS_Write("warner  = ", 10, f)
		G.writeFile_string(G.g_admin_warnings[i].warner, f)
		G.trap_FS_Write("\n", 1, f)
		i += 1
	end
	G.trap_FS_FCloseFile(f)
end

-- if we can't parse any levels from readconfig, set up default
-- ones to make new installs easier for admins
--KK-OAX TODO: Add all features to default levels...
function SF.admin_default_levels()
	local l

	local i = 0
	while i < C.MAX_ADMIN_LEVELS and G.g_admin_levels[i] ~= nil do
		G.g_admin_levels[i] = nil
		i += 1
	end
	for k = 0, 5 do
		l = S.g_admin_level_t()
		l.level = k
		l.name = ""
		l.flags = ""
		G.g_admin_levels[k] = l
	end
	G.g_admin_levels[0].name = QS.Q_strncpyz("^4Unknown Player", C.MAX_NAME_LENGTH)
	G.g_admin_levels[0].flags = QS.Q_strncpyz("ahC", C.MAX_ADMIN_FLAGS)

	G.g_admin_levels[1].name = QS.Q_strncpyz("^5Server Regular", C.MAX_NAME_LENGTH)
	G.g_admin_levels[1].flags = QS.Q_strncpyz("iahC", C.MAX_ADMIN_FLAGS)

	G.g_admin_levels[2].name = QS.Q_strncpyz("^6Team Manager", C.MAX_NAME_LENGTH)
	G.g_admin_levels[2].flags = QS.Q_strncpyz("iahCpPwr", C.MAX_ADMIN_FLAGS)

	G.g_admin_levels[3].name = QS.Q_strncpyz("^2Junior Admin", C.MAX_NAME_LENGTH)
	G.g_admin_levels[3].flags = QS.Q_strncpyz("iahCpPwrkmfKncN?", C.MAX_ADMIN_FLAGS)

	G.g_admin_levels[4].name = QS.Q_strncpyz("^3Senior Admin", C.MAX_NAME_LENGTH)
	G.g_admin_levels[4].flags = QS.Q_strncpyz("iahCpPwrkmfKncN?MVdBbeDS51", C.MAX_ADMIN_FLAGS)

	G.g_admin_levels[5].name = QS.Q_strncpyz("^1Server Operator", C.MAX_NAME_LENGTH)
	G.g_admin_levels[5].flags = QS.Q_strncpyz("*", C.MAX_ADMIN_FLAGS)
	SF.admin_level_maxname = 15
end

--  return a level for a player entity.
function G.G_admin_level(ent)
	if ent == nil then
		return C.MAX_ADMIN_LEVELS
	end

	local i = 0
	while i < C.MAX_ADMIN_ADMINS and G.g_admin_admins[i] ~= nil do
		if QS.Q_strequal(G.g_admin_admins[i].guid, ent.client.pers.guid) then
			return G.g_admin_admins[i].level
		end
		i += 1
	end

	return 0
end

function SF.admin_command_permission(ent, command)
	local level

	if ent == nil then
		return true
	end
	level = ent.client.pers.adminLevel
	local i = 0
	while i < C.MAX_ADMIN_COMMANDS and G.g_admin_commands[i] ~= nil do
		if QS.Q_strequal(command, G.g_admin_commands[i].command) then
			local j = 0
			while G.g_admin_commands[i].levels[j] ~= -1 do
				if G.g_admin_commands[i].levels[j] == level then
					return true
				end
				j += 1
			end
		end
		i += 1
	end
	return false
end

function SF.admin_log(admin, cmd, skiparg)
	local f
	local len
	local str
	local min, tens, sec
	local a
	local l
	local flags
	local victim = nil
	local pids = {}
	local name

	if G.g_adminLog.string == "" then
		return
	end

	len, f = G.trap_FS_FOpenFile(G.g_adminLog.string, C.FS_APPEND)
	if len < 0 then
		G.G_Printf("admin_log: error could not open %s\n", G.g_adminLog.string)
		return
	end

	sec = Q.idiv(G.level.time, 1000)
	min = Q.idiv(sec, 60)
	sec -= min * 60
	tens = Q.idiv(sec, 10)
	sec -= tens * 10

	flags = ""
	if admin ~= nil then
		local i = 0
		while i < C.MAX_ADMIN_ADMINS and G.g_admin_admins[i] ~= nil do
			if QS.Q_strequal(G.g_admin_admins[i].guid, admin.client.pers.guid) then
				a = G.g_admin_admins[i]
				flags = QS.Q_strncpyz(a.flags, C.MAX_ADMIN_FLAGS * 2)
				local j = 0
				while j < C.MAX_ADMIN_LEVELS and G.g_admin_levels[j] ~= nil do
					if G.g_admin_levels[j].level == a.level then
						l = G.g_admin_levels[j]
						flags = QS.Q_strcat(flags, C.MAX_ADMIN_FLAGS * 2, l.flags)
						break
					end
					j += 1
				end
				break
			end
			i += 1
		end
	end

	if G.G_SayArgc() > 1 + skiparg then
		name = G.G_SayArgv(1 + skiparg, C.MAX_NAME_LENGTH)
		if G.G_ClientNumbersFromString(name, pids, C.MAX_CLIENTS) == 1 then
			victim = G.g_entities[pids[0]]
		end
	end

	if victim ~= nil and not QS.Q_strequal(cmd, "attempted") then
		str = QS.Com_sprintf(C.MAX_STRING_CHARS,
			"%3i:%i%i: %i: %s: %s: %s: %s: %s: %s: \"%s\"\n",
			min,
			tens,
			sec,
			if admin ~= nil then admin.s.clientNum else -1,
			if admin ~= nil then admin.client.pers.guid else "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
			if admin ~= nil then admin.client.pers.netname else "console",
			flags,
			cmd,
			victim.client.pers.guid,
			victim.client.pers.netname,
			G.G_SayConcatArgs(2 + skiparg))
	else
		str = QS.Com_sprintf(C.MAX_STRING_CHARS,
			"%3i:%i%i: %i: %s: %s: %s: %s: \"%s\"\n",
			min,
			tens,
			sec,
			if admin ~= nil then admin.s.clientNum else -1,
			if admin ~= nil then admin.client.pers.guid else "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
			if admin ~= nil then admin.client.pers.netname else "console",
			flags,
			cmd,
			G.G_SayConcatArgs(1 + skiparg))
	end
	G.trap_FS_Write(str, #str, f)
	G.trap_FS_FCloseFile(f)
end

local function levelNameFor(level: number): string
	local lname = ""
	local j = 0
	while j < C.MAX_ADMIN_LEVELS and G.g_admin_levels[j] ~= nil do
		if G.g_admin_levels[j].level == level then
			local colorlen = 0
			local nm = G.g_admin_levels[j].name
			for k = 0, #nm - 1 do
				if QS.Q_IsColorString(nm, k + 1) then
					colorlen += 2
				end
			end
			lname = QS.Com_sprintf(C.MAX_NAME_LENGTH, "%*s",
				SF.admin_level_maxname + colorlen,
				nm)
			break
		end
		j += 1
	end
	return lname
end

function SF.admin_listadmins(ent, start, search)
	local drawn = 0
	local guid_stub
	local name = ""
	local name2 = ""
	local lname
	local vic
	local l = 0
	local dup = false

	G.G_admin_buffer_begin()

	-- print out all connected players regardless of level if name searching
	local i = 0
	while i < G.level.maxclients and search ~= "" do
		vic = G.g_entities[i]

		if vic.client == nil or vic.client.pers.connected ~= C.CON_CONNECTED then
			i += 1
			continue
		end

		l = vic.client.pers.adminLevel

		name = G.G_SanitiseString(vic.client.pers.netname, C.MAX_NAME_LENGTH)
		if QS.strstr(name, search) == nil then
			i += 1
			continue
		end

		guid_stub = string.sub(vic.client.pers.guid, 25, 32)

		lname = levelNameFor(l)
		G.G_admin_buffer_print(ent, QS.va("%4i %4i %s^7 (*%s) %s^7\n",
			i,
			l,
			lname,
			guid_stub,
			vic.client.pers.netname))
		drawn += 1
		i += 1
	end

	i = start
	while i < C.MAX_ADMIN_ADMINS and G.g_admin_admins[i] ~= nil and drawn < C.MAX_ADMIN_LISTITEMS do
		if search ~= "" then
			name = G.G_SanitiseString(G.g_admin_admins[i].name, C.MAX_NAME_LENGTH)
			if QS.strstr(name, search) == nil then
				i += 1
				continue
			end

			-- verify we don't have the same guid/name pair in connected players
			-- since we don't want to draw the same player twice
			dup = false
			for j = 0, G.level.maxclients - 1 do
				vic = G.g_entities[j]
				if vic.client == nil or vic.client.pers.connected ~= C.CON_CONNECTED then
					continue
				end
				name2 = G.G_SanitiseString(vic.client.pers.netname, C.MAX_NAME_LENGTH)
				if QS.Q_strequal(vic.client.pers.guid, G.g_admin_admins[i].guid) and
					QS.strstr(name2, search) ~= nil then
					dup = true
					break
				end
			end
			if dup then
				i += 1
				continue
			end
		end
		guid_stub = string.sub(G.g_admin_admins[i].guid, 25, 32)

		lname = levelNameFor(G.g_admin_admins[i].level)
		G.G_admin_buffer_print(ent, QS.va("%4i %4i %s^7 (*%s) %s^7\n",
			(i + C.MAX_CLIENTS),
			G.g_admin_admins[i].level,
			lname,
			guid_stub,
			G.g_admin_admins[i].name))
		drawn += 1
		i += 1
	end
	G.G_admin_buffer_end(ent)
	return drawn
end

return nil
