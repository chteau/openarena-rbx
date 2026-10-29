--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_fileops.c).

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
-- Luau port of OpenArena 0.8.8's g_fileops.c (gamecode 9e0f0c0). Config file parse/write helpers shared by admin and sprees.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

-- Parses an integer for the "tag"; cnf is a QS.cursor. Returns the value (C: *v).
function G.readFile_int(cnf)
	local t = QS.COM_ParseExt(cnf, false)
	if t == "=" then
		t = QS.COM_ParseExt(cnf, false)
	else
		QS.COM_ParseWarning("expected '=' before \"%s\"", t)
	end
	return QS.atoi(t)
end

-- Parses a literal string for the "tag". Returns the string (C: s).
function G.readFile_string(cnf, size)
	local s = ""
	local t = QS.COM_ParseExt(cnf, false)
	if t ~= "=" then
		QS.COM_ParseWarning("expected '=' before \"%s\"", t)
		s = QS.Q_strncpyz(t, size)
	end
	while true do
		t = QS.COM_ParseExt(cnf, false)
		if t == "" then
			break
		end
		if #t + #s >= size then
			break
		end
		if s ~= "" then
			s = QS.Q_strcat(s, size, " ")
		end
		s = QS.Q_strcat(s, size, t)
	end
	return s
end

function G.writeFile_int(v, f)
	local buf = QS.Com_sprintf(32, "%d", v)
	G.trap_FS_Write(buf, #buf, f)
	G.trap_FS_Write("\n", 1, f)
end

function G.writeFile_string(s, f)
	local buf = ""
	if s ~= "" then
		buf = QS.Q_strncpyz(s, C.MAX_STRING_CHARS)
		G.trap_FS_Write(buf, #buf, f)
	end
	G.trap_FS_Write("\n", 1, f)
end

return nil
