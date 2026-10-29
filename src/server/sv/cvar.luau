--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (ioquake3 code/qcommon/cvar.c).

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
-- The engine's console variables (after ioquake3's qcommon/cvar.c): the
-- cvar table behind trap_Cvar_*, with the flag semantics the game relies
-- on (latched values applied on the next registration, ROM/INIT write
-- protection, serverinfo/systeminfo/userinfo info strings and the
-- modification counters vmCvar_t uses).

local QS = require("../../shared/q_shared")
local Q = require("../../shared/q_math")
local C = require("../g_defs")

local band, bor, bnot = bit32.band, bit32.bor, bit32.bnot

local Cvar = {}

local MAX_CVAR_VALUE_STRING = 256

-- name (lower case) -> cvar; cvarList keeps creation order (newest first,
-- like ioq3's linked list) for info strings and cvarlist
local vars = {}
local cvarList = {}
local cvar_indexes = {} -- handle -> cvar
Cvar.cvar_modifiedFlags = 0

Cvar.print = function(msg: string) end

local function key(name: string): string
	return string.lower(name)
end

local function setValues(var, s: string)
	var.string = s
	var.value = Q.f(QS.atof(s))
	var.integer = QS.atoi(s)
	var.modified = true
	var.modificationCount += 1
end

-- Some characters are illegal in info strings because they can mess up the
-- server's parsing
local function Cvar_ValidateString(s: string?): boolean
	if not s then
		return false
	end
	if string.find(s, "\\", 1, true) then
		return false
	end
	if string.find(s, '"', 1, true) then
		return false
	end
	if string.find(s, ";", 1, true) then
		return false
	end
	return true
end

function Cvar.FindVar(name: string)
	return vars[key(name)]
end

-- If the variable already exists, the value will not be set unless
-- CVAR_ROM. The flags will be or'ed in if the variable exists.
function Cvar.Get(var_name: string, var_value: string, flags: number)
	if not var_name or not var_value then
		error("Cvar_Get: NULL parameter")
	end
	if not Cvar_ValidateString(var_name) then
		Cvar.print("invalid cvar name string: " .. var_name .. "\n")
		var_name = "BADNAME"
	end

	local var = vars[key(var_name)]
	if var then
		-- if the C code is now specifying a variable that the user already
		-- set a value for, take the new value as the reset value
		if band(var.flags, C.CVAR_USER_CREATED) ~= 0 then
			var.flags = band(var.flags, bnot(C.CVAR_USER_CREATED))
			var.resetString = var_value
			if band(flags, C.CVAR_ROM) ~= 0 then
				-- this variable was set by the user, so force it to value given by the engine.
				var.latchedString = var_value
			end
		end

		var.flags = bor(var.flags, flags)

		-- only allow one non-empty reset string without a warning
		if var.resetString == "" then
			var.resetString = var_value
		end

		-- if we have a latched string, take that value now
		if var.latchedString then
			local s = var.latchedString
			var.latchedString = nil -- otherwise cvar_set2 would free it
			Cvar.Set2(var_name, s, true)
		end

		-- ZOID--needs to be set so that cvars the game sets as
		-- SERVERINFO get sent to clients
		Cvar.cvar_modifiedFlags = bor(Cvar.cvar_modifiedFlags, flags)

		return var
	end

	--
	-- allocate a new cvar
	--
	var = {
		name = var_name,
		string = "",
		resetString = var_value,
		latchedString = nil,
		flags = flags,
		modified = true,
		modificationCount = 0,
		value = 0,
		integer = 0,
		handle = #cvarList + 1,
	}
	var.string = var_value
	var.value = Q.f(QS.atof(var_value))
	var.integer = QS.atoi(var_value)
	var.modificationCount = 1

	vars[key(var_name)] = var
	table.insert(cvarList, 1, var)
	cvar_indexes[var.handle] = var

	Cvar.cvar_modifiedFlags = bor(Cvar.cvar_modifiedFlags, var.flags)

	return var
end

function Cvar.Set2(var_name: string, value: string?, force: boolean)
	if not Cvar_ValidateString(var_name) then
		Cvar.print("invalid cvar name string: " .. var_name .. "\n")
		var_name = "BADNAME"
	end

	local var = vars[key(var_name)]
	if not var then
		if not value then
			return nil
		end
		-- create it
		if not force then
			return Cvar.Get(var_name, value, C.CVAR_USER_CREATED)
		else
			return Cvar.Get(var_name, value, 0)
		end
	end

	if not value then
		value = var.resetString
	end
	value = string.sub(value :: string, 1, MAX_CVAR_VALUE_STRING - 1)

	if value == var.string and not var.latchedString then
		return var
	end
	-- note what types of cvars have been modified (userinfo, archive, serverinfo, systeminfo)
	Cvar.cvar_modifiedFlags = bor(Cvar.cvar_modifiedFlags, var.flags)

	if not force then
		if band(var.flags, C.CVAR_ROM) ~= 0 then
			Cvar.print(var_name .. " is read only.\n")
			return var
		end

		if band(var.flags, C.CVAR_INIT) ~= 0 then
			Cvar.print(var_name .. " is write protected.\n")
			return var
		end

		if band(var.flags, C.CVAR_LATCH) ~= 0 then
			if var.latchedString then
				if value == var.latchedString then
					return var
				end
			else
				if value == var.string then
					return var
				end
			end

			Cvar.print(var_name .. " will be changed upon restarting.\n")
			var.latchedString = value
			var.modified = true
			var.modificationCount += 1
			return var
		end

		if band(var.flags, C.CVAR_CHEAT) ~= 0 and Cvar.cheatsAllowed and not Cvar.cheatsAllowed() then
			Cvar.print(var_name .. " is cheat protected.\n")
			return var
		end
	else
		if var.latchedString then
			var.latchedString = nil
		end
	end

	if value == var.string then
		return var -- not changed
	end

	setValues(var, value :: string)
	return var
end

function Cvar.Set(var_name: string, value: string?)
	Cvar.Set2(var_name, value, true)
end

-- the user typed it / sent it: honours ROM, INIT, LATCH and CHEAT
function Cvar.SetSafe(var_name: string, value: string?)
	Cvar.Set2(var_name, value, false)
end

function Cvar.SetValue(var_name: string, value: number)
	if value == math.floor(value) then
		Cvar.Set(var_name, string.format("%d", value))
	else
		Cvar.Set(var_name, QS.cformat("%f", value))
	end
end

function Cvar.VariableValue(var_name: string): number
	local var = vars[key(var_name)]
	return if var then var.value else 0
end

function Cvar.VariableIntegerValue(var_name: string): number
	local var = vars[key(var_name)]
	return if var then var.integer else 0
end

function Cvar.VariableString(var_name: string): string
	local var = vars[key(var_name)]
	return if var then var.string else ""
end

function Cvar.Reset(var_name: string)
	Cvar.Set2(var_name, nil, false)
end

-- basically a slightly modified Cvar_Get for the interpreted modules
function Cvar.Register(vmCvar, varName: string, defaultValue: string, flags: number)
	local cv = Cvar.Get(varName, defaultValue, flags)
	if not vmCvar then
		return
	end
	vmCvar.handle = cv.handle
	vmCvar.modificationCount = -1
	Cvar.Update(vmCvar)
end

-- updates an interpreted modules' version of a cvar
function Cvar.Update(vmCvar)
	local cv = cvar_indexes[vmCvar.handle]
	if not cv then
		return
	end
	if cv.modificationCount == vmCvar.modificationCount then
		return
	end
	vmCvar.modificationCount = cv.modificationCount
	vmCvar.string = string.sub(cv.string, 1, MAX_CVAR_VALUE_STRING - 1)
	vmCvar.value = cv.value
	vmCvar.integer = cv.integer
end

function Cvar.InfoString(bit: number, maxSize: number?): string
	local info = ""
	-- ioq3 walks its list from the newest cvar; Info_SetValueForKey
	-- prepends, so the oldest ends up first
	for _, var in cvarList do
		if band(var.flags, bit) ~= 0 then
			info = QS.Info_SetValueForKey(info, var.name, var.string)
		end
	end
	return info
end

-- Handles variable inspection and changing from the console:
-- "name" prints, "name value" sets. Returns false if not a cvar.
function Cvar.Command(argc: number, argv: (number) -> string): boolean
	local v = Cvar.FindVar(argv(0))
	if not v then
		return false
	end
	if argc == 1 then
		Cvar.print(string.format('"%s" is:"%s^7" default:"%s^7"\n', v.name, v.string, v.resetString))
		return true
	end
	Cvar.Set2(v.name, argv(1), false)
	return true
end

function Cvar.List(): { any }
	return cvarList
end

-- forget everything (tests)
function Cvar.ResetAll()
	table.clear(vars)
	table.clear(cvarList)
	table.clear(cvar_indexes)
	Cvar.cvar_modifiedFlags = 0
end

return Cvar
