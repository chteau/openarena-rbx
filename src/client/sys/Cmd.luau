-- Command buffer, tokenizer and command table (qcommon/cmd.c semantics):
-- `;`/newline separated text, `//` comments, quoted args, `wait`, `vstr`,
-- the cvar commands, and a fallback chain for names the engine doesn't own
-- (cgame, then ui, then the server).
local Cvar = require(script.Parent.Cvar)
local C = require(script.Parent.Parent.q.Consts)

local Cmd = {}

local commands: { [string]: { name: string, fn: (() -> ())? } } = {}
local argv: { string } = {}
local args = ""
local cbuf = ""
local waitFrames = 0

-- Set by the client: called for a command nothing registered, returns true
-- if handled. Default: print like Q3 does.
Cmd.fallback = nil :: ((name: string) -> boolean)?
Cmd.print = print

-- Cmd_TokenizeString.
function Cmd.TokenizeString(text: string)
	table.clear(argv)
	args = ""
	local i, n = 1, #text
	while true do
		-- skip whitespace and // comments
		while i <= n do
			local c = text:sub(i, i)
			if c <= " " then
				i += 1
			elseif text:sub(i, i + 1) == "//" or text:sub(i, i + 1) == "/*" then
				if text:sub(i, i + 1) == "//" then
					return
				end
				local e = text:find("*/", i + 2, true)
				if e == nil then
					return
				end
				i = e + 2
			else
				break
			end
		end
		if i > n then
			return
		end
		if #argv == 1 then
			args = text:sub(i):gsub("%s+$", "")
		end
		local tok
		if text:sub(i, i) == '"' then
			local e = text:find('"', i + 1, true) or (n + 1)
			tok = text:sub(i + 1, e - 1)
			i = e + 1
		else
			local s = i
			while i <= n and text:sub(i, i) > " " do
				if text:sub(i, i + 1) == "//" or text:sub(i, i + 1) == "/*" then
					break
				end
				i += 1
			end
			tok = text:sub(s, i - 1)
		end
		table.insert(argv, tok)
	end
end

function Cmd.Argc(): number
	return #argv
end

function Cmd.Argv(n: number): string
	return argv[n + 1] or ""
end

function Cmd.Args(): string
	return args
end

-- Cmd_ArgsFrom(n): the args from n on, re-joined.
function Cmd.ArgsFrom(n: number): string
	local out = {}
	for i = n + 1, #argv do
		table.insert(out, argv[i])
	end
	return table.concat(out, " ")
end

function Cmd.AddCommand(name: string, fn: (() -> ())?)
	-- as ioq3: a completion-only add (cgame's forward-to-server list) never
	-- replaces a command the engine handles (LAN's addbot, team)
	local old = commands[string.lower(name)]
	if fn == nil and old and old.fn then
		return
	end
	commands[string.lower(name)] = { name = name, fn = fn }
end

function Cmd.RemoveCommand(name: string)
	commands[string.lower(name)] = nil
end

function Cmd.Exists(name: string): boolean
	return commands[string.lower(name)] ~= nil
end

function Cmd.CompleteNames(): { string }
	local out = {}
	for _, c in commands do
		table.insert(out, c.name)
	end
	table.sort(out)
	return out
end

-- Cvar_Command: `name` prints, `name value` sets.
local function cvarCommand(): boolean
	local v = Cvar.Find(Cmd.Argv(0))
	if v == nil then
		return false
	end
	if Cmd.Argc() == 1 then
		Cmd.print(('"%s" is:"%s^7" default:"%s^7"'):format(v.name, v.string, v.resetString))
		return true
	end
	Cvar.Set(v.name, Cmd.Args(), false)
	return true
end

-- Cmd_ExecuteString: runs one already-separated command line.
function Cmd.ExecuteString(text: string)
	Cmd.TokenizeString(text)
	if Cmd.Argc() == 0 then
		return
	end
	local c = commands[string.lower(Cmd.Argv(0))]
	if c then
		if c.fn then
			c.fn()
			return
		end
	elseif cvarCommand() then
		return
	end
	-- registered without a function (cgame/ui/server commands), or unknown
	if Cmd.fallback and Cmd.fallback(Cmd.Argv(0)) then
		return
	end
	if c == nil then
		Cmd.print("Unknown command \"" .. Cmd.Argv(0) .. "^7\"")
	end
end

function Cmd.AddText(text: string)
	cbuf ..= text
end

function Cmd.InsertText(text: string)
	cbuf = text .. "\n" .. cbuf
end

-- Cbuf_ExecuteText(EXEC_NOW / EXEC_INSERT / EXEC_APPEND, text).
function Cmd.ExecuteText(when: number, text: string)
	if when == C.EXEC_NOW then
		if text ~= "" then
			Cmd.ExecuteString(text)
		else
			Cmd.Execute()
		end
	elseif when == C.EXEC_INSERT then
		Cmd.InsertText(text)
	else
		Cmd.AddText(text)
	end
end

-- Cbuf_Execute: one line at a time, stopping at `wait`.
function Cmd.Execute()
	while cbuf ~= "" do
		if waitFrames > 0 then
			waitFrames -= 1
			return
		end
		local quotes = false
		local cut = #cbuf + 1
		for i = 1, #cbuf do
			local c = cbuf:sub(i, i)
			if c == '"' then
				quotes = not quotes
			end
			if (c == ";" and not quotes) or c == "\n" or c == "\r" then
				cut = i
				break
			end
		end
		local line = cbuf:sub(1, cut - 1)
		cbuf = cbuf:sub(cut + 1)
		Cmd.ExecuteString(line)
	end
end

-- Built-in commands.
Cmd.AddCommand("wait", function()
	waitFrames = math.max(tonumber(Cmd.Argv(1)) or 1, 1)
end)
Cmd.AddCommand("echo", function()
	Cmd.print(Cmd.Args())
end)
Cmd.AddCommand("vstr", function()
	Cmd.InsertText(Cvar.VariableString(Cmd.Argv(1)))
end)
local function set(flags: number)
	return function()
		if Cmd.Argc() < 3 then
			Cmd.print("usage: set <variable> <value>")
			return
		end
		local name = Cmd.Argv(1)
		Cvar.Set(name, Cmd.ArgsFrom(2), false)
		local v = Cvar.Find(name)
		if v and flags ~= 0 then
			v.flags = bit32.bor(v.flags, flags)
		end
	end
end
Cmd.AddCommand("set", set(0))
Cmd.AddCommand("seta", set(C.CVAR_ARCHIVE))
Cmd.AddCommand("setu", set(C.CVAR_USERINFO))
Cmd.AddCommand("sets", set(C.CVAR_SERVERINFO))
Cmd.AddCommand("reset", function()
	Cvar.Reset(Cmd.Argv(1))
end)
Cmd.AddCommand("toggle", function()
	local name = Cmd.Argv(1)
	if Cmd.Argc() <= 2 then
		Cvar.SetValue(name, if Cvar.VariableValue(name) ~= 0 then 0 else 1)
		return
	end
	-- toggle through the listed values
	local cur = Cvar.VariableString(name)
	for i = 2, Cmd.Argc() - 1 do
		if Cmd.Argv(i) == cur then
			Cvar.Set(name, Cmd.Argv(if i + 1 < Cmd.Argc() then i + 1 else 2), false)
			return
		end
	end
	Cvar.Set(name, Cmd.Argv(2), false)
end)
Cmd.AddCommand("cvar_restart", function()
	for _, v in Cvar.vars do
		if bit32.band(v.flags, bit32.bor(C.CVAR_ROM, C.CVAR_INIT)) == 0 then
			Cvar.Set(v.name, nil, true)
		end
	end
end)

return Cmd
