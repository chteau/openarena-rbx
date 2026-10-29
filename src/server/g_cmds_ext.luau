--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_cmds_ext.c).

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
-- Luau port of g_cmds_ext.c. Say-text argument parsing, player name matching, flood limiting, admin messages.

local G = require("./g_local")      -- game globals + every non-static function
local C = require("./g_defs")       -- EVERY #define / enum
local S = require("./g_structs")    -- struct constructors
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SPACE = 32
local ADMF_NOCENSORFLOOD = string.byte("?")
local ADMF_ADMINCHAT = string.byte("&")
local S_COLOR_MAGENTA = "^6"
local S_COLOR_WHITE = "^7"

local function chr(s, i)
	return string.byte(s, i) or 0
end

--[[
G_SayArgc / G_SayArgv / G_SayConcatArgs: trap_Argc, trap_Argv, and ConcatArgs
consider say text as a single argument; these re-parse it on word boundaries.
]]
function G.G_SayArgc()
	local c = 0
	local s = G.ConcatArgs(0)
	local i = 1
	while true do
		while chr(s, i) == SPACE do
			i += 1
		end
		if chr(s, i) == 0 then
			break
		end
		c += 1
		while chr(s, i) ~= 0 and chr(s, i) ~= SPACE do
			i += 1
		end
	end
	return c
end

-- C fills buffer and returns qboolean; here: returns (string, ok), the
-- string "" when ok is false. bufferLength defaults to MAX_STRING_CHARS.
function G.G_SayArgv(n, bufferLength)
	bufferLength = bufferLength or C.MAX_STRING_CHARS
	if bufferLength < 1 then
		return "", false
	end
	if n < 0 then
		return "", false
	end
	local s = G.ConcatArgs(0)
	local i = 1
	while true do
		while chr(s, i) == SPACE do
			i += 1
		end
		if chr(s, i) == 0 or n == 0 then
			break
		end
		n -= 1
		while chr(s, i) ~= 0 and chr(s, i) ~= SPACE do
			i += 1
		end
	end
	if n > 0 then
		return "", false
	end
	local out = ""
	while chr(s, i) ~= 0 and chr(s, i) ~= SPACE and bufferLength > 1 do
		out ..= string.sub(s, i, i)
		i += 1
		bufferLength -= 1
	end
	return out, true
end

function G.G_SayConcatArgs(start)
	local s = G.ConcatArgs(0)
	local i = 1
	while true do
		while chr(s, i) == SPACE do
			i += 1
		end
		if chr(s, i) == 0 or start == 0 then
			break
		end
		start -= 1
		while chr(s, i) ~= 0 and chr(s, i) ~= SPACE do
			i += 1
		end
	end
	return string.sub(s, i)
end

function G.G_DecolorString(inp, len)
	len -= 1
	local out = ""
	local i = 1
	while chr(inp, i) ~= 0 and len > 0 do
		if QS.Q_IsColorString(inp, i) then
			i += 1
			if chr(inp, i) ~= 0 then
				i += 1
			end
			continue
		end
		out ..= string.sub(inp, i, i)
		i += 1
		len -= 1
	end
	return out
end

--[[
G_MatchOnePlayer

This is a companion function to G_ClientNumbersFromString()
Returns err, which will be populated with an error message.
]]
function G.G_MatchOnePlayer(plist, num, len)
	local err = ""
	if num == 0 then
		err = QS.Q_strcat(err, len, "no connected player by that name or slot #")
	elseif num > 1 then
		err = QS.Q_strcat(err, len, "more than one player name matches. Be more specific or use the slot #:\n")
		for i = 0, num - 1 do
			local cl = G.level.clients[plist[i]]
			if cl.pers.connected == C.CON_DISCONNECTED then
				continue
			end
			local line = QS.Com_sprintf(C.MAX_NAME_LENGTH + 10, "%2i - %s^7\n", plist[i], cl.pers.netname)
			if #err + #line > len then
				break
			end
			err = QS.Q_strcat(err, len, line)
		end
	end
	return err
end

-- Remove case and control characters from a string; returns out
function G.G_SanitiseString(inp, len)
	local skip = true
	local spaces = 0
	local i = 1
	local out = ""

	len -= 1

	while chr(inp, i) ~= 0 and len > 0 do
		-- strip leading white space
		if chr(inp, i) == SPACE then
			if skip then
				i += 1
				continue
			end
			spaces += 1
		else
			spaces = 0
			skip = false
		end

		if QS.Q_IsColorString(inp, i) then
			i += 2 -- skip color code
			continue
		end

		if chr(inp, i) < 32 then
			i += 1
			continue
		end

		out ..= string.lower(string.sub(inp, i, i))
		i += 1
		len -= 1
	end
	return string.sub(out, 1, #out - spaces)
end

--[[
G_ClientNumbersFromString

Sets plist (0-based) to client numbers that have names that are a partial
match for s. Returns number of matching clientids up to max.
]]
function G.G_ClientNumbersFromString(s, plist, max)
	local found = 0

	if max == 0 then
		return 0
	end

	-- if a number is provided, it is a clientnum
	if string.find(s, "%D") == nil then
		local i = QS.atoi(s)
		if i >= 0 and i < G.level.maxclients then
			local p = G.level.clients[i]
			if p.pers.connected ~= C.CON_DISCONNECTED then
				plist[0] = i
				return 1
			end
		end
		-- we must assume that if only a number is provided, it is a clientNum
		return 0
	end

	-- now look for name matches
	local s2 = G.G_SanitiseString(s, C.MAX_NAME_LENGTH)
	if #s2 < 1 then
		return 0
	end
	local i = 0
	while i < G.level.maxclients and found < max do
		local p = G.level.clients[i]
		if p.pers.connected ~= C.CON_DISCONNECTED then
			local n2 = G.G_SanitiseString(p.pers.netname, C.MAX_NAME_LENGTH)
			if QS.strstr(n2, s2) ~= nil then
				plist[found] = i
				found += 1
			end
		end
		i += 1
	end
	return found
end

--[[
G_FloodLimited

Determine whether a user is flood limited, and adjust their flood demerits
Print them a warning message if they are over the limit
Return is time in msec until the user can speak again
]]
function G.G_FloodLimited(ent)
	if G.g_floodMinTime.integer <= 0 then
		return 0
	end

	-- handles !ent
	if G.G_admin_permission(ent, ADMF_NOCENSORFLOOD) then
		return 0
	end

	local deltatime = G.level.time - ent.client.pers.floodTime

	ent.client.pers.floodDemerits += G.g_floodMinTime.integer - deltatime
	if ent.client.pers.floodDemerits < 0 then
		ent.client.pers.floodDemerits = 0
	end
	ent.client.pers.floodTime = G.level.time

	local ms = ent.client.pers.floodDemerits - G.g_floodMaxDemerits.integer
	if ms <= 0 then
		return 0
	end
	G.trap_SendServerCommand(ent.index, QS.va("print \"You are flooding: please wait %d second%s before trying again\n",
		(ms + 999) // 1000, if ms > 1000 then "s" else ""))
	return ms
end

--[[
G_AdminMessage

Print to all active server admins, and to the logfile, and to the server console
Prepend *prefix, or '[SERVER]' if no *prefix is given
]]
local function G_AdminMessage(prefix, fmt, ...)
	local str = string.sub(QS.va(fmt, ...), 1, 1023)

	-- If there is no prefix, assume that this function was called directly
	-- and we should add one
	if prefix == nil or prefix == "" then
		prefix = "[SERVER]:"
	end

	local outstring = QS.Com_sprintf(1024, "%s " .. S_COLOR_MAGENTA .. "%s", prefix, str)

	-- Send to all appropriate clients
	for i = 0, G.level.maxclients - 1 do
		if G.G_admin_permission(G.g_entities[i], ADMF_ADMINCHAT) then
			G.trap_SendServerCommand(i, QS.va("chat \"%s\"", outstring))
		end
	end

	-- Send to the logfile and server console
	G.G_LogPrintf("adminmsg: %s\n", outstring)
end

-- Send a message to all active admins
function G.Cmd_AdminMessage_f(ent)
	local prefix
	local skiparg = 0

	local function ADMP(x)
		G.trap_SendServerCommand(ent.index, QS.va("print \"%s\"", x))
	end

	-- Check permissions and add the appropriate user [prefix]
	if ent == nil then
		prefix = QS.Com_sprintf(50, "[CONSOLE]:")
	elseif not G.G_admin_permission(ent, ADMF_ADMINCHAT) then
		if G.g_publicAdminMessages.integer == 0 then
			ADMP("Sorry, but use of /a by non-admins has been disabled.\n")
			return
		else
			prefix = QS.Com_sprintf(50, "[PLAYER] %s" .. S_COLOR_WHITE .. ":", ent.client.pers.netname)
			ADMP("Your message has been sent to any available admins and to the server logs.\n")
		end
	else
		prefix = QS.Com_sprintf(50, "[ADMIN] %s" .. S_COLOR_WHITE .. ":", ent.client.pers.netname)
	end

	-- Skip say/say_team if this was used from one of those
	local cmd = G.G_SayArgv(0, #"say_team" + 1)
	if QS.Q_strequal(cmd, "say") or QS.Q_strequal(cmd, "say_team") then
		skiparg = 1
		local a1, ok = G.G_SayArgv(1, #"say_team" + 1)
		if ok then
			cmd = a1
		end
	end
	if G.G_SayArgc() < 2 + skiparg then
		ADMP(QS.va("usage: %s [message]\n", cmd))
		return
	end

	local msg = G.G_SayConcatArgs(1 + skiparg)

	-- Send it
	G_AdminMessage(prefix, "%s", msg)
end

--[[
G_ClientNumberFromString

Returns a player number for either a number or name string
Returns -1 if invalid
]]
function G.G_ClientNumberFromString(s)
	-- numeric values are just slot numbers
	if string.find(s, "%D") == nil then
		local i = QS.atoi(s)

		if i < 0 or i >= G.level.maxclients then
			return -1
		end

		local cl = G.level.clients[i]

		if cl.pers.connected == C.CON_DISCONNECTED then
			return -1
		end

		return i
	end

	-- check for a name match
	local s2 = G.G_SanitiseString(s, C.MAX_NAME_LENGTH)

	for i = 0, G.level.maxclients - 1 do
		local cl = G.level.clients[i]
		if cl.pers.connected == C.CON_DISCONNECTED then
			continue
		end

		local n2 = G.G_SanitiseString(cl.pers.netname, C.MAX_NAME_LENGTH)

		if n2 == s2 then
			return i
		end
	end

	return -1
end

--KK-OAX Used to !spec999'ers
function G.G_ClientIsLagging(client)
	if client ~= nil then
		if client.ps.ping >= 999 then
			return true
		else
			return false
		end
	end

	return false -- is a non-existant client lagging? woooo zen
end

-- Remove case and control characters; returns out
function G.SanitizeString(inp, out)
	out = ""
	local i = 1
	while chr(inp, i) ~= 0 do
		if chr(inp, i) == 27 then
			i += 2 -- skip color code
			continue
		end
		if chr(inp, i) < 32 then
			i += 1
			continue
		end
		out ..= string.lower(string.sub(inp, i, i))
		i += 1
	end

	return out
end

return nil
