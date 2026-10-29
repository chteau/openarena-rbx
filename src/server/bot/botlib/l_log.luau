--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/l_log.c).

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
-- Luau port of l_log.c. Log file kept in memory: each write appends a chunk to a table.

local B = require("./b_local")                 -- botlib namespace: every non-static function + global
local BC = require("./consts")                 -- every #define/enum of q_shared.h, surfaceflags.h, botlib/*.h
local Q = require("../../../shared/q_math")    -- float32-exact vector math, Q.f, trunc, idiv, imod, random
local QS = require("../../../shared/q_shared") -- strings: va, Com_sprintf, Q_stricmp, atoi, atof, Q_strncpyz ...

local MAX_LOGFILENAMESIZE = 1024

local logfile = {
	filename = "",
	fp = nil :: { string }?,
	numwrites = 0,
}

function B.Log_Open(filename)
	if B.LibVarValue("log", "0") == 0 then return end
	if filename == nil or #filename == 0 then
		B.botimport.Print(BC.PRT_MESSAGE, "openlog <filename>\n")
		return
	end
	if logfile.fp ~= nil then
		B.botimport.Print(BC.PRT_ERROR, "log file %s is already opened\n", logfile.filename)
		return
	end
	logfile.fp = {}
	logfile.filename = QS.Q_strncpyz(filename, MAX_LOGFILENAMESIZE)
	B.botimport.Print(BC.PRT_MESSAGE, "Opened log %s\n", logfile.filename)
end

function B.Log_Close()
	if logfile.fp == nil then return end
	logfile.fp = nil
	B.botimport.Print(BC.PRT_MESSAGE, "Closed log %s\n", logfile.filename)
end

function B.Log_Shutdown()
	if logfile.fp ~= nil then B.Log_Close() end
end

function B.Log_Write(fmt, ...)
	local fp = logfile.fp
	if fp == nil then return end
	fp[#fp + 1] = QS.va(fmt, ...)
end

function B.Log_WriteTimeStamped(fmt, ...)
	local fp = logfile.fp
	if fp == nil then return end
	local time = B.botlibglobals.time
	local prefix = string.format("%d   %02d:%02d:%02d:%02d   ",
		logfile.numwrites,
		Q.trunc(time / 60 / 60),
		Q.trunc(time / 60),
		Q.trunc(time),
		Q.trunc(time * 100) - Q.trunc(time) * 100)
	fp[#fp + 1] = prefix .. QS.va(fmt, ...) .. "\r\n"
	logfile.numwrites = logfile.numwrites + 1
end

function B.Log_FilePointer()
	return logfile.fp
end

function B.Log_Flush()
	if logfile.fp == nil then return end
end

return nil
