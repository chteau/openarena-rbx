--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (ioquake3 code/qcommon/cmd.c).

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
-- The engine's command buffer and command tokenizer (after ioquake3's
-- qcommon/cmd.c): Cbuf_AddText/InsertText/Execute with the same line
-- splitting (';', newlines, // and /* */ comments, quotes),
-- Cmd_TokenizeString with the same argv rules, the command registry and
-- the built-in script commands (wait, vstr, echo, set*, reset, toggle,
-- exec). Commands nobody registered fall through to cvar inspection and
-- then to Cmd.fallback (the server wires this to the game's
-- ConsoleCommand).

local Cvar = require("./cvar")
local C = require("../g_defs")

local Cmd = {}

local MAX_STRING_TOKENS = 1024
local MAX_CMD_LINE = 1024
local MAX_CMD_BUFFER = 128 * 1024

local cmd_text = ""
local cmd_wait = 0

local cmd_argc = 0
local cmd_argv: { [number]: string } = {}
local cmd_cmd = "" -- the original command we received (no token processing)

local functions: { [string]: { name: string, fn: () -> () } } = {}

Cmd.print = function(msg: string) end
-- (text) -> boolean: game ConsoleCommand, called with the line tokenized
Cmd.fallback = nil :: (() -> boolean)?
-- reads a script for "exec": (path) -> string?
Cmd.readFile = nil :: ((string) -> string?)?

--
-- command buffer
--

function Cmd.Cbuf_AddText(text: string)
	if #cmd_text + #text >= MAX_CMD_BUFFER then
		Cmd.print("Cbuf_AddText: overflow\n")
		return
	end
	cmd_text ..= text
end

-- Adds command text immediately after the current command; adds a \n to
-- the text
function Cmd.Cbuf_InsertText(text: string)
	if #cmd_text + #text + 1 > MAX_CMD_BUFFER then
		Cmd.print("Cbuf_InsertText overflowed\n")
		return
	end
	cmd_text = text .. "\n" .. cmd_text
end

function Cmd.Cbuf_ExecuteText(exec_when: number, text: string?)
	if exec_when == C.EXEC_NOW then
		if text and #text > 0 then
			Cmd.Cmd_ExecuteString(text)
		else
			Cmd.Cbuf_Execute()
		end
	elseif exec_when == C.EXEC_INSERT then
		Cmd.Cbuf_InsertText(text or "")
	elseif exec_when == C.EXEC_APPEND then
		Cmd.Cbuf_AddText(text or "")
	else
		error("Cbuf_ExecuteText: bad exec_when")
	end
end

function Cmd.Cbuf_Execute()
	-- This will keep // style comments all on one line by not breaking on
	-- a semicolon. It will keep /* ... */ style comments all on one line by
	-- not breaking it for semicolon or newline.
	local in_star_comment = false
	local in_slash_comment = false
	while #cmd_text > 0 do
		if cmd_wait > 0 then
			-- skip out while text still remains in buffer, leaving it for next frame
			cmd_wait -= 1
			break
		end

		-- find a \n or ; line break or comment: // or /* */
		local text = cmd_text
		local size = #text
		local quotes = 0
		local i = 0
		while i < size do
			local c = string.byte(text, i + 1)
			if c == 34 then -- '"'
				quotes += 1
			end
			local brk = false
			if quotes % 2 == 0 then
				if i < size - 1 then
					local n = string.byte(text, i + 2)
					if not in_star_comment and c == 47 and n == 47 then
						in_slash_comment = true
					elseif not in_slash_comment and c == 47 and n == 42 then
						in_star_comment = true
					elseif in_star_comment and c == 42 and n == 47 then
						in_star_comment = false
						-- If we are in a star comment, then the part after it is valid
						i += 1
						break
					end
				end
				if not in_slash_comment and not in_star_comment and c == 59 then -- ';'
					brk = true
				end
			end
			if brk then
				break
			end
			if not in_star_comment and (c == 10 or c == 13) then
				in_slash_comment = false
				break
			end
			i += 1
		end

		local n = i
		if n >= MAX_CMD_LINE - 1 then
			n = MAX_CMD_LINE - 1
		end
		local line = string.sub(text, 1, n)

		-- delete the text from the command buffer (commands like exec can
		-- insert data at the beginning of the buffer)
		if i == size then
			cmd_text = ""
		else
			cmd_text = string.sub(text, i + 2)
		end

		-- execute the command line
		Cmd.Cmd_ExecuteString(line)
	end
end

--
-- tokenizer
--

function Cmd.Cmd_Argc(): number
	return cmd_argc
end

function Cmd.Cmd_Argv(arg: number): string
	if arg < 0 or arg >= cmd_argc then
		return ""
	end
	return cmd_argv[arg]
end

-- Returns a single string containing argv(arg) to argv(argc()-1)
function Cmd.Cmd_ArgsFrom(arg: number): string
	if arg < 0 then
		arg = 0
	end
	local parts = {}
	for i = arg, cmd_argc - 1 do
		table.insert(parts, cmd_argv[i])
	end
	return table.concat(parts, " ")
end

function Cmd.Cmd_Args(): string
	return Cmd.Cmd_ArgsFrom(1)
end

-- Cmd_Args_Sanitize rewrites arguments in place
function Cmd.SetArgv(arg: number, s: string)
	if arg >= 0 and arg < cmd_argc then
		cmd_argv[arg] = s
	end
end

function Cmd.Cmd_Cmd(): string
	return cmd_cmd
end

-- Parses the given string into command line tokens. The text is copied to
-- a separate buffer and 0 characters are inserted in the appropriate place.
local function Cmd_TokenizeString2(text_in: string?, ignoreQuotes: boolean)
	-- clear previous args
	cmd_argc = 0
	table.clear(cmd_argv)

	if not text_in then
		return
	end

	cmd_cmd = string.sub(text_in, 1, C.BIG_INFO_STRING - 1)

	local text = text_in
	local len = #text
	local p = 1 -- 1-based cursor; byte(p) == nil means the NUL terminator
	local function at(k: number): number
		return string.byte(text, k) or 0
	end

	while true do
		if cmd_argc == MAX_STRING_TOKENS then
			return -- this is usually something malicious
		end

		while true do
			-- skip whitespace
			while p <= len and at(p) <= 32 do
				p += 1
			end
			if p > len then
				return -- all tokens parsed
			end

			-- skip // comments
			if at(p) == 47 and at(p + 1) == 47 then
				return -- all tokens parsed
			end

			-- skip /* */ comments
			if at(p) == 47 and at(p + 1) == 42 then
				while p <= len and (at(p) ~= 42 or at(p + 1) ~= 47) do
					p += 1
				end
				if p > len then
					return -- all tokens parsed
				end
				p += 2
			else
				break -- we are ready to parse a token
			end
		end

		-- handle quoted strings (this doesn't handle \" escaping)
		if not ignoreQuotes and at(p) == 34 then
			p += 1
			local s = p
			while p <= len and at(p) ~= 34 do
				p += 1
			end
			cmd_argv[cmd_argc] = string.sub(text, s, p - 1)
			cmd_argc += 1
			if p > len then
				return -- all tokens parsed
			end
			p += 1
			continue
		end

		-- regular token: skip until whitespace, quote, or command
		local s = p
		while p <= len and at(p) > 32 do
			if not ignoreQuotes and at(p) == 34 then
				break
			end
			if at(p) == 47 and at(p + 1) == 47 then
				break
			end
			-- skip /* */ comments
			if at(p) == 47 and at(p + 1) == 42 then
				break
			end
			p += 1
		end
		cmd_argv[cmd_argc] = string.sub(text, s, p - 1)
		cmd_argc += 1

		if p > len then
			return -- all tokens parsed
		end
	end
end

function Cmd.Cmd_TokenizeString(text_in: string?)
	Cmd_TokenizeString2(text_in, false)
end

function Cmd.Cmd_TokenizeStringIgnoreQuotes(text_in: string?)
	Cmd_TokenizeString2(text_in, true)
end

--
-- registry
--

function Cmd.Cmd_AddCommand(cmd_name: string, fn: () -> ())
	local k = string.lower(cmd_name)
	if functions[k] then
		-- allow re-registration of the same name with a new function
		Cmd.print("Cmd_AddCommand: " .. cmd_name .. " already defined\n")
		return
	end
	functions[k] = { name = cmd_name, fn = fn }
end

function Cmd.Cmd_RemoveCommand(cmd_name: string)
	functions[string.lower(cmd_name)] = nil
end

function Cmd.Cmd_Exists(cmd_name: string): boolean
	return functions[string.lower(cmd_name)] ~= nil
end

-- A complete command line has been parsed, so try to execute it
function Cmd.Cmd_ExecuteString(text: string)
	-- execute the command line
	Cmd.Cmd_TokenizeString(text)
	if cmd_argc == 0 then
		return -- no tokens
	end

	-- check registered command functions
	local f = functions[string.lower(cmd_argv[0])]
	if f then
		f.fn()
		return
	end

	-- check cvars
	if Cvar.Command(cmd_argc, Cmd.Cmd_Argv) then
		return
	end

	-- check server game commands
	if Cmd.fallback and Cmd.fallback() then
		return
	end

	Cmd.print("Unknown command \"" .. cmd_argv[0] .. "\"\n")
end

--
-- script commands
--

-- Causes execution of the remainder of the command buffer to be delayed
-- until next frame. This allows commands like: bind g "cmd use rocket ; +attack ; wait ; -attack ; cmd use blaster"
local function Cmd_Wait_f()
	if cmd_argc == 2 then
		cmd_wait = tonumber(cmd_argv[1]) or 0
		if cmd_wait < 0 then
			cmd_wait = 1 -- ignore the argument
		end
	else
		cmd_wait = 1
	end
end

-- Inserts the current value of a variable as command text
local function Cmd_Vstr_f()
	if cmd_argc ~= 2 then
		Cmd.print("vstr <variablename> : execute a variable command\n")
		return
	end
	local v = Cvar.VariableString(cmd_argv[1])
	Cmd.Cbuf_InsertText(v)
end

-- Just prints the rest of the line to the console
local function Cmd_Echo_f()
	Cmd.print(Cmd.Cmd_Args() .. "\n")
end

local function Cmd_Exec_f()
	if cmd_argc ~= 2 then
		Cmd.print("exec <filename> : execute a script file\n")
		return
	end
	local filename = cmd_argv[1]
	if not string.find(filename, "%.[^/]*$") then
		filename ..= ".cfg"
	end
	local text = Cmd.readFile and Cmd.readFile(filename)
	if not text then
		Cmd.print("couldn't exec " .. filename .. "\n")
		return
	end
	Cmd.print("execing " .. filename .. "\n")
	Cmd.Cbuf_InsertText(text)
end

-- set/seta/sets/setu: Allows setting and defining of arbitrary cvars from console
local function setWithFlags(flag: number)
	return function()
		local c = cmd_argc
		local cmdname = cmd_argv[0]
		if c < 2 then
			Cmd.print("usage: " .. cmdname .. " <variable> <value>\n")
			return
		end
		if c == 2 then
			Cvar.Command(1, function(i: number): string
				return cmd_argv[i + 1] or ""
			end)
			return
		end
		Cvar.Set2(cmd_argv[1], Cmd.Cmd_ArgsFrom(2), false)
		if flag ~= 0 then
			local v = Cvar.FindVar(cmd_argv[1])
			if v then
				v.flags = bit32.bor(v.flags, flag)
				Cvar.cvar_modifiedFlags = bit32.bor(Cvar.cvar_modifiedFlags, flag)
			end
		end
	end
end

local function Cvar_Reset_f()
	if cmd_argc ~= 2 then
		Cmd.print("usage: reset <variable>\n")
		return
	end
	Cvar.Reset(cmd_argv[1])
end

-- Toggles a cvar for easy single key binding, optionally through a list of values
local function Cvar_Toggle_f()
	local c = cmd_argc
	if c < 2 then
		Cmd.print("usage: toggle <variable> [value1, value2, ...]\n")
		return
	end
	if c == 2 then
		Cvar.Set2(cmd_argv[1], if Cvar.VariableValue(cmd_argv[1]) ~= 0 then "0" else "1", false)
		return
	end
	if c == 3 then
		Cmd.print("toggle: nothing to toggle to\n")
		return
	end
	local curval = Cvar.VariableString(cmd_argv[1])
	-- don't bother checking the last arg for a match since the desired
	-- behaviour is the same as no match (set to the first argument)
	for i = 2, c - 2 do
		if curval == cmd_argv[i] then
			Cvar.Set2(cmd_argv[1], cmd_argv[i + 1], false)
			return
		end
	end
	-- fallback
	Cvar.Set2(cmd_argv[1], cmd_argv[2], false)
end

function Cmd.Init()
	table.clear(functions)
	cmd_text = ""
	cmd_wait = 0
	Cmd.Cmd_AddCommand("wait", Cmd_Wait_f)
	Cmd.Cmd_AddCommand("vstr", Cmd_Vstr_f)
	Cmd.Cmd_AddCommand("echo", Cmd_Echo_f)
	Cmd.Cmd_AddCommand("exec", Cmd_Exec_f)
	Cmd.Cmd_AddCommand("set", setWithFlags(0))
	Cmd.Cmd_AddCommand("sets", setWithFlags(C.CVAR_SERVERINFO))
	Cmd.Cmd_AddCommand("setu", setWithFlags(C.CVAR_USERINFO))
	Cmd.Cmd_AddCommand("seta", setWithFlags(C.CVAR_ARCHIVE))
	Cmd.Cmd_AddCommand("reset", Cvar_Reset_f)
	Cmd.Cmd_AddCommand("toggle", Cvar_Toggle_f)
end

return Cmd
