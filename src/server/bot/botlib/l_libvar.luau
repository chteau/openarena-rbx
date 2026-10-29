--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/l_libvar.c).

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
-- Luau port of l_libvar.c. Bot library variables: a linked list of name/string/value entries.

local B = require("./b_local")                 -- botlib namespace: every non-static function + global
local SB = require("./structs")                -- SB.<type>() zeroed struct, SB.copy_<type>(dst, src)
local QS = require("../../../shared/q_shared") -- strings: va, Com_sprintf, Q_stricmp, atoi, atof, Q_strncpyz ...

-- list with library variables
B.libvarlist = nil

--[[
Parameter:				-
Returns:					-
Changes Globals:		-
]]
function B.LibVarStringValue(str: string): number
	local dotfound = 0
	local value = 0
	local p = 0
	while B.ch(str, p) ~= 0 do
		local c = B.ch(str, p)
		if c < 48 or c > 57 then
			if dotfound ~= 0 or c ~= 46 then
				return 0
			else
				dotfound = 10
				p = p + 1
				c = B.ch(str, p)
			end
		end
		if dotfound ~= 0 then
			value = value + (c - 48) / dotfound
			dotfound = dotfound * 10
		else
			value = value * 10.0 + (c - 48)
		end
		p = p + 1
	end
	return value
end

--[[
Parameter:				-
Returns:					-
Changes Globals:		-
]]
function B.LibVarAlloc(var_name: string)
	local v = SB.libvar_t()
	v.name = var_name
	-- add the variable in the list
	v.next = B.libvarlist
	B.libvarlist = v
	return v
end

--[[
Parameter:				-
Returns:					-
Changes Globals:		-
]]
function B.LibVarDeAlloc(v)
	v.string = nil
	v.name = nil
end

--[[
Parameter:				-
Returns:					-
Changes Globals:		-
]]
function B.LibVarDeAllocAll()
	local v = B.libvarlist
	while v ~= nil do
		B.libvarlist = B.libvarlist.next
		B.LibVarDeAlloc(v)
		v = B.libvarlist
	end
	B.libvarlist = nil
end

--[[
Parameter:				-
Returns:					-
Changes Globals:		-
]]
function B.LibVarGet(var_name: string)
	local v = B.libvarlist
	while v ~= nil do
		if QS.Q_stricmp(v.name, var_name) == 0 then
			return v
		end
		v = v.next
	end
	return nil
end

--[[
Parameter:				-
Returns:					-
Changes Globals:		-
]]
function B.LibVarGetString(var_name: string)
	local v = B.LibVarGet(var_name)
	if v ~= nil then
		return v.string
	else
		return ""
	end
end

--[[
Parameter:				-
Returns:					-
Changes Globals:		-
]]
function B.LibVarGetValue(var_name: string): number
	local v = B.LibVarGet(var_name)
	if v ~= nil then
		return v.value
	else
		return 0
	end
end

--[[
Parameter:				-
Returns:					-
Changes Globals:		-
]]
function B.LibVar(var_name: string, value: string)
	local v = B.LibVarGet(var_name)
	if v ~= nil then return v end
	-- create new variable
	v = B.LibVarAlloc(var_name)
	-- variable string
	v.string = value
	-- the value
	v.value = B.LibVarStringValue(v.string)
	-- variable is modified
	v.modified = true
	return v
end

--[[
Parameter:				-
Returns:					-
Changes Globals:		-
]]
function B.LibVarString(var_name: string, value: string): string
	local v = B.LibVar(var_name, value)
	return v.string
end

--[[
Parameter:				-
Returns:					-
Changes Globals:		-
]]
function B.LibVarValue(var_name: string, value: string): number
	local v = B.LibVar(var_name, value)
	return v.value
end

--[[
Parameter:				-
Returns:					-
Changes Globals:		-
]]
function B.LibVarSet(var_name: string, value: string)
	local v = B.LibVarGet(var_name)
	if v ~= nil then
		v.string = nil
	else
		v = B.LibVarAlloc(var_name)
	end
	-- variable string
	v.string = value
	-- the value
	v.value = B.LibVarStringValue(v.string)
	-- variable is modified
	v.modified = true
end

--[[
Parameter:				-
Returns:					-
Changes Globals:		-
]]
function B.LibVarChanged(var_name: string): boolean
	local v = B.LibVarGet(var_name)
	if v ~= nil then
		return v.modified
	else
		return false
	end
end

--[[
Parameter:				-
Returns:					-
Changes Globals:		-
]]
function B.LibVarSetNotModified(var_name: string)
	local v = B.LibVarGet(var_name)
	if v ~= nil then
		v.modified = false
	end
end

return nil
