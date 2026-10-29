--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib).

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
-- The botlib's global namespace: every non-static botlib function and
-- global variable (aasworld, botimport, botlibglobals, ...) lives on B, so
-- the ported be_*.c / l_*.c files can call each other in any load order.

local B = {}

-- static functions/variables of a C file split across several Luau parts
local fileStatics: { [string]: { [string]: any } } = {}
function B.FileStatics(cfile: string): { [string]: any }
	local t = fileStatics[cfile]
	if not t then
		t = {}
		fileStatics[cfile] = t
	end
	return t
end

-- C `s[i]` on a char buffer held as a Luau string: the byte at 0-based
-- offset i, 0 at or past the end (the terminating NUL)
function B.ch(s: string, i: number): number
	return string.byte(s, i + 1) or 0
end

-- a 0-based array of n zeros (GetClearedMemory for int/float/short arrays)
function B.zeros(n: number): { [number]: number }
	local t = table.create(n, 0)
	if n > 0 then
		t[0] = 0
		t[n] = nil
	end
	return t
end

return B
