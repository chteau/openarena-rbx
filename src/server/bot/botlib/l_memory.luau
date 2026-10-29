--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/l_memory.c).

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
-- Luau port of l_memory.c. Luau is garbage collected, so the allocators
-- themselves become table constructors at each call site (SB.<type>(),
-- B.zeros(n)) and FreeMemory is dropping the reference; what is left are
-- the functions other files call for memory bookkeeping and reports.

local B = require("./b_local")
local BC = require("./consts")

function B.AvailableMemory(): number
	return B.botimport.AvailableMemory()
end

-- C: memory size of a block; the port has no block headers
function B.MemoryByteSize(ptr): number
	return 0
end

function B.PrintUsedMemorySize()
	B.botimport.Print(BC.PRT_MESSAGE, "total botlib memory: managed by the Luau garbage collector\n")
end

function B.PrintMemoryLabels() end

function B.DumpMemory() end

return nil
