-- The chat line of the engine console (client/cl_console.c Con_MessageMode*_f
-- and the chat half of Con_DrawNotify, client/cl_keys.c Message_Key and
-- Field_*), on Roblox's text chat:
--
--   * Roblox's own chat window, input bar, bubbles and player list are
--     turned off (OAClient.client.luau, first thing); OA's notify lines and
--     say: prompt replace them, and Tab is OA's +scores;
--   * Enter sends the line on TextChatService.OAChat.Say / .Team instead
--     of as a `say` command, so Roblox filters it. The server
--     (server/sv/chat_roblox.luau) runs G_Say and sends each recipient a
--     `rchat <MessageId> <chat|tchat> "<name prefix>"` frame; Roblox
--     delivers each recipient the text filtered for them. Frame and text
--     are joined here by MessageId and go through the cgame's own chat
--     path (CG_ChatMessage: talk sound, team chat box, notify line);
--   * a player TextChatService doesn't let chat (the OACanChat attribute
--     the server sets from CanUserChatAsync) gets no prompt.
local C = require(script.Parent.Parent.q.Consts)
local Keys = require(script.Parent.Keys)
local Clock = require(script.Parent.Clock)
local Console = require(script.Parent.Console)
local R2D = require(script.Parent.R2D)
local Net = require(script.Parent.Net)
local Screen = require(script.Parent.Parent.Parent.ui.Screen)

local Chat = {}

local MAX_EDIT_LINE = 256
local BIGCHAR_WIDTH = 16
local PENDING_MS = 15000

-- chatField, chat_team, chat_playerNum, key_overstrikeMode
local field = { buffer = "", cursor = 0, scroll = 0, widthInChars = 30 }
local chatTeam = false
local chatPlayerNum = -1
local overstrike = false
Chat.field = field -- for tests

local function clear()
	field.buffer, field.cursor, field.scroll = "", 0, 0
end

local function closeLine()
	Keys.SetCatcher(bit32.band(Keys.GetCatcher(), bit32.bnot(C.KEYCATCH_MESSAGE)))
	clear()
end

function Chat.CanChat(): boolean
	local ok, can = pcall(function()
		return game:GetService("Players").LocalPlayer:GetAttribute("OACanChat")
	end)
	return ok and can == true
end

-- frames and filtered texts, joined by MessageId ----------------------------
local frames: { [string]: { cmd: string, prefix: string, t: number } } = {}
local texts: { [string]: { text: string, t: number } } = {}
local done: { [string]: number } = {}
local ready: { { cmd: string, line: string } } = {}

local function prune(now: number)
	for _, tab in { frames, texts, done } :: { any } do
		for id, e in tab do
			if now - (if type(e) == "number" then e else e.t) > PENDING_MS then
				tab[id] = nil
			end
		end
	end
end

local function join(id: string)
	local f, t = frames[id], texts[id]
	if f and t then
		frames[id], texts[id] = nil, nil
		done[id] = Clock.Milliseconds()
		table.insert(ready, { cmd = f.cmd, line = f.prefix .. t.text })
	end
end

function Chat.Frame(id: string, cmd: string, prefix: string)
	if done[id] or (cmd ~= "chat" and cmd ~= "tchat") then
		return
	end
	frames[id] = { cmd = cmd, prefix = prefix, t = Clock.Milliseconds() }
	join(id)
end

-- a delivered (filtered) TextChatMessage.Text
function Chat.Text(id: string, text: string)
	if done[id] then
		return
	end
	text = text:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&")
	-- what Cmd_Args_Sanitize leaves of a say line
	texts[id] = { text = (text:gsub("[%c;]", " ")), t = Clock.Milliseconds() }
	join(id)
end

-- the joined lines, for the cgame (Client.Frame)
function Chat.Drain(fn: (cmd: string, line: string) -> ())
	prune(Clock.Milliseconds())
	local list = ready
	ready = {}
	for _, r in list do
		fn(r.cmd, r.line)
	end
end

local function folder(): Instance?
	return game:GetService("TextChatService"):FindFirstChild("OAChat")
end

function Chat.Start()
	local tcs = game:GetService("TextChatService")
	tcs.MessageReceived:Connect(function(m: TextChatMessage)
		local f = folder()
		if f and m.TextChannel and m.TextChannel.Parent == f and m.Status == Enum.TextChatMessageStatus.Success then
			Chat.Text(m.MessageId, m.Text)
		end
	end)
end

-- Message_Key's send: the text goes to Roblox, never to the game directly
local function send(text: string)
	local f = folder()
	if f == nil then
		return
	end
	local ch: TextChannel, meta = f:FindFirstChild("Say") :: TextChannel, ""
	if chatPlayerNum ~= -1 then
		meta = "tell " .. chatPlayerNum
	elseif chatTeam then
		ch = f:FindFirstChild("Team") :: TextChannel
	end
	if ch == nil then
		return
	end
	task.spawn(function()
		local ok, m = pcall(function()
			return ch:SendAsync(text, meta)
		end)
		if ok and m and m.Status == Enum.TextChatMessageStatus.Success then
			Chat.Text(m.MessageId, m.Text)
		end
	end)
end

-- Con_MessageMode_f .. Con_MessageMode4_f ----------------------------------
local function messageMode(team: boolean, width: number, playerNum: number)
	if not Chat.CanChat() then
		return
	end
	chatPlayerNum = playerNum
	chatTeam = team
	clear()
	field.widthInChars = width
	Keys.SetCatcher(bit32.bxor(Keys.GetCatcher(), C.KEYCATCH_MESSAGE))
end

-- `target(which)` is VM_Call(cgvm, CG_CROSSHAIR_PLAYER / CG_LAST_ATTACKER)
function Chat.Register(Cmd: any, target: (which: string) -> number)
	Cmd.AddCommand("messagemode", function()
		messageMode(false, 30, -1)
	end)
	Cmd.AddCommand("messagemode2", function()
		messageMode(true, 25, -1)
	end)
	for name, which in { messagemode3 = "crosshair", messagemode4 = "attacker" } do
		Cmd.AddCommand(name, function()
			local n = target(which)
			if n >= 0 and n < C.MAX_CLIENTS then
				messageMode(false, 30, n)
			end
		end)
	end
end

-- Field_KeyDownEvent / Field_CharEvent --------------------------------------
local function fieldKeyDown(k: number)
	local len = #field.buffer
	if k == C.K_DEL then
		if field.cursor < len then
			field.buffer = field.buffer:sub(1, field.cursor) .. field.buffer:sub(field.cursor + 2)
		end
	elseif k == C.K_RIGHTARROW then
		if field.cursor < len then
			field.cursor += 1
		end
	elseif k == C.K_LEFTARROW then
		if field.cursor > 0 then
			field.cursor -= 1
		end
	elseif k == C.K_HOME then
		field.cursor = 0
	elseif k == C.K_END then
		field.cursor = len
	elseif k == C.K_INS then
		overstrike = not overstrike
	end
	-- Change scroll if cursor is no longer visible
	if field.cursor < field.scroll then
		field.scroll = field.cursor
	elseif field.cursor >= field.scroll + field.widthInChars and field.cursor <= len then
		field.scroll = field.cursor - field.widthInChars + 1
	end
end

local function fieldChar(ch: number)
	-- ctrl-v / shift-insert paste: Roblox gives scripts no clipboard
	if ch == 3 then -- ctrl-c clears the field
		clear()
		return
	end
	local len = #field.buffer
	if ch == 8 then -- ctrl-h is backspace
		if field.cursor > 0 then
			field.buffer = field.buffer:sub(1, field.cursor - 1) .. field.buffer:sub(field.cursor + 1)
			field.cursor -= 1
			if field.cursor < field.scroll then
				field.scroll -= 1
			end
		end
		return
	end
	if ch == 1 then -- ctrl-a is home
		field.cursor, field.scroll = 0, 0
		return
	end
	if ch == 5 then -- ctrl-e is end
		field.cursor = len
		field.scroll = field.cursor - field.widthInChars
		return
	end
	if ch < 32 then
		return
	end
	local c = string.char(ch)
	if overstrike then
		if field.cursor == MAX_EDIT_LINE - 2 then
			return
		end
		field.buffer = field.buffer:sub(1, field.cursor) .. c .. field.buffer:sub(field.cursor + 2)
	else
		if len == MAX_EDIT_LINE - 2 then
			return
		end
		field.buffer = field.buffer:sub(1, field.cursor) .. c .. field.buffer:sub(field.cursor + 1)
	end
	field.cursor += 1
	if field.cursor >= field.widthInChars then
		field.scroll += 1
	end
end

-- Message_Key, and the KEYCATCH_MESSAGE half of CL_CharEvent
function Chat.Key(k: number, char: string?)
	if char then
		local b = string.byte(char)
		-- SDL turns ctrl+letter into the control character
		if Keys.IsDown(C.K_CTRL) and char:match("%a") then
			b = string.byte(char:lower()) - 96
		end
		fieldChar(b)
		return
	end
	if k == C.K_ESCAPE then
		closeLine()
		return
	end
	if k == C.K_ENTER or k == C.K_KP_ENTER then
		if field.buffer ~= "" and Net.state == C.CA_ACTIVE then
			send(field.buffer)
		end
		closeLine()
		return
	end
	if k == C.K_BACKSPACE then -- SDL sends it as ctrl-h
		fieldChar(8)
		return
	end
	fieldKeyDown(k)
end

-- The chat line of Con_DrawNotify, `v` pixels below the top of the notify
-- lines: SCR_DrawBigString(8, v * 480 / vidHeight + 8, "say:") and
-- Field_BigDraw at skip * BIGCHAR_WIDTH, in 640x480 units pinned top-left.
function Chat.Draw(v: number)
	local catcher = Keys.GetCatcher()
	if bit32.band(catcher, bit32.bor(C.KEYCATCH_UI, C.KEYCATCH_CGAME)) ~= 0
		or bit32.band(catcher, C.KEYCATCH_MESSAGE) == 0 then
		return
	end
	local s = Screen.layout(R2D.width, R2D.height).scale
	local x0, y = Screen.insets.left, Screen.insets.top + v + 8 * s
	local big, shadow = BIGCHAR_WIDTH * s, 2 * s
	local skip = if chatTeam then 10 else 5
	Console.DrawString(x0 + 8 * s, y, big, big, if chatTeam then "say_team:" else "say:", 1, false, shadow)

	-- Field_VariableSizeDraw
	local x = x0 + skip * big
	local drawLen = field.widthInChars - 1 -- - 1 so there is always a space for the cursor
	local len = #field.buffer
	local prestep = 0
	if len > drawLen then
		if field.scroll + drawLen > len then
			field.scroll = math.max(len - drawLen, 0)
		end
		prestep = field.scroll
	end
	if prestep + drawLen > len then
		drawLen = len - prestep
	end
	local str = field.buffer:sub(prestep + 1, prestep + drawLen)
	Console.DrawString(x, y, big, big, str, 1, true, shadow)
	if bit32.band(bit32.rshift(Clock.Milliseconds(), 8), 1) == 0 then
		Console.DrawString(x + (field.cursor - prestep) * big, y, big, big,
			string.char(if overstrike then 11 else 10), 1, false, shadow)
	end
end

return Chat
