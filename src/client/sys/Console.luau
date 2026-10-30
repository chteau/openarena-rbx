-- The engine console (client/cl_console.c, trimmed): Com_Printf lines, the
-- notify lines drawn top-left during play (con_notifytime), and the
-- drop-down console with an input line (toggleconsole). Text uses the same
-- charset as Q3 (gfx/2d/bigchars) at SMALLCHAR size in real pixels.
local C = require(script.Parent.Parent.q.Consts)
local Clock = require(script.Parent.Clock)
local Cvar = require(script.Parent.Cvar)
local Screen = require(script.Parent.Parent.Parent.ui.Screen)

local Console = {}

local NUM_CON_TIMES = 4
local MAX_LINES = 256
local SMALLCHAR_WIDTH, SMALLCHAR_HEIGHT = 8, 16

local lines: { string } = {}
local times: { number } = {} -- per line, Milliseconds when printed (0 = cleared)
local partial = ""
Console.lines = lines -- for tests
Console.open = false
Console.input = ""
Console.cursor = 0
Console.history = {} :: { string }
Console.historyLine = 0
-- Mirrors to the Roblox output (dev/parity) when set.
Console.echo = print :: ((string) -> ())?

local con_notifytime = Cvar.Get("con_notifytime", "3", 0)
Cvar.Get("con_conspeed", "3", 0)

local function cleanForEcho(s: string): string
	return (s:gsub("%^[^%^]", ""))
end

-- CL_ConsolePrint: lines wrap at the console width, at word boundaries
local lineX, lineColor, partialTime = 0, 7, 0

local function linefeed()
	table.insert(lines, partial)
	table.insert(times, Clock.Milliseconds())
	if #lines > MAX_LINES then
		table.remove(lines, 1)
		table.remove(times, 1)
	end
	partial = if lineColor ~= 7 then "^" .. lineColor else ""
	lineX = 0
end

function Console.Print(msg: string)
	if Console.echo then
		Console.echo(cleanForEcho((msg:gsub("\n$", ""))))
	end
	local R2D = require(script.Parent.R2D)
	-- Con_CheckResize: (vidWidth / SMALLCHAR_WIDTH) - 2
	local linewidth = if R2D.width > 0 then R2D.width // SMALLCHAR_WIDTH - 2 else 78
	local Q = require(script.Parent.Parent.q.Q)
	if lineColor ~= 7 then
		partial ..= "^7"
	end
	lineColor = 7
	local i, n = 1, #msg
	while i <= n do
		local c = string.byte(msg, i)
		if c == 94 and i < n and string.byte(msg, i + 1) ~= 94 then -- Q_IsColorString
			lineColor = Q.ColorIndex(string.byte(msg, i + 1))
			partial ..= "^" .. lineColor
			i += 2
			continue
		end
		-- count word length
		local l = 0
		while l < linewidth and i + l <= n and string.byte(msg, i + l) > 32 do
			l += 1
		end
		-- word wrap
		if l ~= linewidth and lineX + l >= linewidth then
			linefeed()
		end
		if c == 10 then
			linefeed()
		elseif c == 13 then
			lineX = 0
		else
			partial ..= string.char(c)
			lineX += 1
			if lineX >= linewidth then
				linefeed()
			end
		end
		i += 1
	end
	partialTime = Clock.Milliseconds()
end

function Console.ClearNotify()
	partialTime = 0
	for i = 1, #times do
		times[i] = 0
	end
end

-- SCR_DrawStringExt in real pixels: w x h characters with Q3 colour codes
-- (shown as text too when noColorEscape), and the 2-unit drop shadow of
-- SCR_DrawBigString when `shadow` is its size in pixels.
function Console.DrawString(x: number, y: number, w: number, h: number, s: string, alpha: number?,
	noColorEscape: boolean?, shadow: number?)
	local R2D = require(script.Parent.R2D)
	local Assets = require(script.Parent.Assets)
	local Q = require(script.Parent.Parent.q.Q)
	local charset = Assets.RegisterShader("gfx/2d/bigchars", false)
	local a = alpha or 1
	local function chars(x0: number, y0: number, colored: boolean)
		local i = 1
		while i <= #s do
			local c = string.byte(s, i)
			if c == 94 and i < #s and string.byte(s, i + 1) ~= 94 then -- '^'
				if colored then
					local col = Q.g_color_table[Q.ColorIndex(string.byte(s, i + 1))]
					R2D.SetColor({ [0] = col[0], [1] = col[1], [2] = col[2], [3] = a })
				end
				if not noColorEscape then
					i += 2
					continue
				end
			end
			if c ~= 32 then
				local row, colm = bit32.rshift(c, 4), bit32.band(c, 15)
				local size = 0.0625
				R2D.DrawStretchPic(x0, y0, w, h, colm * size, row * size, colm * size + size, row * size + size, charset)
			end
			x0 += w
			i += 1
		end
	end
	if shadow then
		R2D.SetColor({ [0] = 0, [1] = 0, [2] = 0, [3] = a })
		chars(x + shadow, y + shadow, false)
	end
	R2D.SetColor({ [0] = 1, [1] = 1, [2] = 1, [3] = a })
	chars(x, y, true)
	R2D.SetColor(nil)
end

-- One string of SMALLCHAR characters at real pixel (x, y).
function Console.DrawSmallString(x: number, y: number, s: string, alpha: number?)
	Console.DrawString(x, y, SMALLCHAR_WIDTH, SMALLCHAR_HEIGHT, s, alpha)
end

-- Con_DrawNotify: the lines from con.current - NUM_CON_TIMES + 1 to the
-- one being written (con.current), so the last three finished lines and
-- the unfinished one, each while younger than con_notifytime. Returns the
-- height drawn, in pixels.
function Console.DrawNotify(): number
	local now = Clock.Milliseconds()
	-- top-left, clear of the safe-area insets
	local x, y0 = Screen.insets.left + SMALLCHAR_WIDTH, Screen.insets.top
	local y = y0
	local limit = con_notifytime.value * 1000
	for i = math.max(1, #lines - NUM_CON_TIMES + 2), #lines do
		local t = times[i]
		if t ~= 0 and now - t <= limit and cleanForEcho(lines[i]):find("[^ ]") then
			Console.DrawSmallString(x, y, lines[i])
			y += SMALLCHAR_HEIGHT
		end
	end
	if partialTime ~= 0 and now - partialTime <= limit and cleanForEcho(partial):find("[^ ]") then
		Console.DrawSmallString(x, y, partial)
		y += SMALLCHAR_HEIGHT
	end
	return y - y0
end

-- Con_DrawSolidConsole at half the screen height.
function Console.DrawConsole(width: number, height: number)
	local R2D = require(script.Parent.R2D)
	local Assets = require(script.Parent.Assets)
	local lines_h = math.floor(height * 0.5)
	local bg = Assets.RegisterShader("console", false)
	if bg == 0 then
		bg = Assets.RegisterShader("white", false)
	end
	R2D.SetColor({ [0] = 0.1, [1] = 0.1, [2] = 0.1, [3] = 0.85 })
	R2D.DrawStretchPic(0, 0, width, lines_h, 0, 0, 1, 1, bg)
	R2D.SetColor({ [0] = 1, [1] = 0, [2] = 0, [3] = 1 })
	R2D.DrawStretchPic(0, lines_h, width, 2, 0, 0, 0, 0, Assets.RegisterShader("white", false))
	R2D.SetColor(nil)
	local rows = math.floor((lines_h - SMALLCHAR_HEIGHT * 2) / SMALLCHAR_HEIGHT)
	local y = lines_h - SMALLCHAR_HEIGHT * 2 - SMALLCHAR_HEIGHT
	for i = #lines, math.max(1, #lines - rows + 1), -1 do
		Console.DrawSmallString(SMALLCHAR_WIDTH, y, lines[i])
		y -= SMALLCHAR_HEIGHT
	end
	local blink = (math.floor(Clock.Milliseconds() / 250) % 2) == 0
	local text = "]" .. Console.input
	Console.DrawSmallString(SMALLCHAR_WIDTH, lines_h - SMALLCHAR_HEIGHT * 1.5, text)
	if blink then
		Console.DrawSmallString(SMALLCHAR_WIDTH * (2 + Console.cursor), lines_h - SMALLCHAR_HEIGHT * 1.5, "_")
	end
end

-- Console key handling while open (Console_Key).
function Console.Key(key: number, char: string?)
	local Cmd = require(script.Parent.Cmd)
	if key == C.K_ENTER or key == C.K_KP_ENTER then
		local text = Console.input
		Console.Print("]" .. text .. "\n")
		if text ~= "" then
			table.insert(Console.history, text)
			Console.historyLine = #Console.history + 1
			-- a console line without a slash is still a command, as with con_autochat 0
			local cmd = text:gsub("^[/\\]", "")
			Cmd.AddText(cmd .. "\n")
		end
		Console.input, Console.cursor = "", 0
	elseif key == C.K_BACKSPACE then
		if Console.cursor > 0 then
			Console.input = Console.input:sub(1, Console.cursor - 1) .. Console.input:sub(Console.cursor + 1)
			Console.cursor -= 1
		end
	elseif key == C.K_DEL then
		Console.input = Console.input:sub(1, Console.cursor) .. Console.input:sub(Console.cursor + 2)
	elseif key == C.K_LEFTARROW then
		Console.cursor = math.max(0, Console.cursor - 1)
	elseif key == C.K_RIGHTARROW then
		Console.cursor = math.min(#Console.input, Console.cursor + 1)
	elseif key == C.K_HOME then
		Console.cursor = 0
	elseif key == C.K_END then
		Console.cursor = #Console.input
	elseif key == C.K_UPARROW then
		if Console.historyLine > 1 then
			Console.historyLine -= 1
			Console.input = Console.history[Console.historyLine]
			Console.cursor = #Console.input
		end
	elseif key == C.K_DOWNARROW then
		if Console.historyLine <= #Console.history then
			Console.historyLine += 1
			Console.input = Console.history[Console.historyLine] or ""
			Console.cursor = #Console.input
		end
	elseif key == C.K_TAB then
		-- complete a command or cvar name
		local prefix = string.lower(Console.input:gsub("^[/\\]", ""))
		if prefix ~= "" and not prefix:find(" ") then
			for _, name in Cmd.CompleteNames() do
				if string.lower(name):sub(1, #prefix) == prefix then
					Console.input = name .. " "
					Console.cursor = #Console.input
					break
				end
			end
		end
	elseif char and #char == 1 and char >= " " then
		Console.input = Console.input:sub(1, Console.cursor) .. char .. Console.input:sub(Console.cursor + 1)
		Console.cursor += 1
	end
end

return Console
