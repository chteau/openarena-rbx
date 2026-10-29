-- Keys and binds (client/cl_keys.c semantics): key names, the bind table,
-- key catchers, and dispatching a key event to the console, ui, cgame or a
-- bound command ("+cmd" binds get the key number and time, and their "-"
-- half on release). Roblox input is turned into Q3 key numbers by Client.
local C = require(script.Parent.Parent.q.Consts)
local Cmd = require(script.Parent.Cmd)

local Keys = {}

local names = {
	{ "TAB", "K_TAB" },
	{ "ENTER", "K_ENTER" },
	{ "ESCAPE", "K_ESCAPE" },
	{ "SPACE", "K_SPACE" },
	{ "BACKSPACE", "K_BACKSPACE" },
	{ "UPARROW", "K_UPARROW" },
	{ "DOWNARROW", "K_DOWNARROW" },
	{ "LEFTARROW", "K_LEFTARROW" },
	{ "RIGHTARROW", "K_RIGHTARROW" },
	{ "ALT", "K_ALT" },
	{ "CTRL", "K_CTRL" },
	{ "SHIFT", "K_SHIFT" },
	{ "COMMAND", "K_COMMAND" },
	{ "CAPSLOCK", "K_CAPSLOCK" },
	{ "F1", "K_F1" },
	{ "F2", "K_F2" },
	{ "F3", "K_F3" },
	{ "F4", "K_F4" },
	{ "F5", "K_F5" },
	{ "F6", "K_F6" },
	{ "F7", "K_F7" },
	{ "F8", "K_F8" },
	{ "F9", "K_F9" },
	{ "F10", "K_F10" },
	{ "F11", "K_F11" },
	{ "F12", "K_F12" },
	{ "F13", "K_F13" },
	{ "F14", "K_F14" },
	{ "F15", "K_F15" },
	{ "INS", "K_INS" },
	{ "DEL", "K_DEL" },
	{ "PGDN", "K_PGDN" },
	{ "PGUP", "K_PGUP" },
	{ "HOME", "K_HOME" },
	{ "END", "K_END" },
	{ "MOUSE1", "K_MOUSE1" },
	{ "MOUSE2", "K_MOUSE2" },
	{ "MOUSE3", "K_MOUSE3" },
	{ "MOUSE4", "K_MOUSE4" },
	{ "MOUSE5", "K_MOUSE5" },
	{ "MWHEELUP", "K_MWHEELUP" },
	{ "MWHEELDOWN", "K_MWHEELDOWN" },
	{ "JOY1", "K_JOY1" },
	{ "JOY2", "K_JOY2" },
	{ "JOY3", "K_JOY3" },
	{ "JOY4", "K_JOY4" },
	{ "JOY5", "K_JOY5" },
	{ "JOY6", "K_JOY6" },
	{ "JOY7", "K_JOY7" },
	{ "JOY8", "K_JOY8" },
	{ "JOY9", "K_JOY9" },
	{ "JOY10", "K_JOY10" },
	{ "JOY11", "K_JOY11" },
	{ "JOY12", "K_JOY12" },
	{ "JOY13", "K_JOY13" },
	{ "JOY14", "K_JOY14" },
	{ "JOY15", "K_JOY15" },
	{ "JOY16", "K_JOY16" },
	{ "JOY17", "K_JOY17" },
	{ "JOY18", "K_JOY18" },
	{ "JOY19", "K_JOY19" },
	{ "JOY20", "K_JOY20" },
	{ "JOY21", "K_JOY21" },
	{ "JOY22", "K_JOY22" },
	{ "JOY23", "K_JOY23" },
	{ "JOY24", "K_JOY24" },
	{ "JOY25", "K_JOY25" },
	{ "JOY26", "K_JOY26" },
	{ "JOY27", "K_JOY27" },
	{ "JOY28", "K_JOY28" },
	{ "JOY29", "K_JOY29" },
	{ "JOY30", "K_JOY30" },
	{ "JOY31", "K_JOY31" },
	{ "JOY32", "K_JOY32" },
	{ "AUX1", "K_AUX1" },
	{ "AUX2", "K_AUX2" },
	{ "AUX3", "K_AUX3" },
	{ "AUX4", "K_AUX4" },
	{ "AUX5", "K_AUX5" },
	{ "AUX6", "K_AUX6" },
	{ "AUX7", "K_AUX7" },
	{ "AUX8", "K_AUX8" },
	{ "AUX9", "K_AUX9" },
	{ "AUX10", "K_AUX10" },
	{ "AUX11", "K_AUX11" },
	{ "AUX12", "K_AUX12" },
	{ "AUX13", "K_AUX13" },
	{ "AUX14", "K_AUX14" },
	{ "AUX15", "K_AUX15" },
	{ "AUX16", "K_AUX16" },
	{ "KP_HOME", "K_KP_HOME" },
	{ "KP_UPARROW", "K_KP_UPARROW" },
	{ "KP_PGUP", "K_KP_PGUP" },
	{ "KP_LEFTARROW", "K_KP_LEFTARROW" },
	{ "KP_5", "K_KP_5" },
	{ "KP_RIGHTARROW", "K_KP_RIGHTARROW" },
	{ "KP_END", "K_KP_END" },
	{ "KP_DOWNARROW", "K_KP_DOWNARROW" },
	{ "KP_PGDN", "K_KP_PGDN" },
	{ "KP_ENTER", "K_KP_ENTER" },
	{ "KP_INS", "K_KP_INS" },
	{ "KP_DEL", "K_KP_DEL" },
	{ "KP_SLASH", "K_KP_SLASH" },
	{ "KP_MINUS", "K_KP_MINUS" },
	{ "KP_PLUS", "K_KP_PLUS" },
	{ "KP_NUMLOCK", "K_KP_NUMLOCK" },
	{ "KP_STAR", "K_KP_STAR" },
	{ "KP_EQUALS", "K_KP_EQUALS" },
	{ "PAUSE", "K_PAUSE" },
	{ "SEMICOLON", "59" },
	{ "WORLD_0", "K_WORLD_0" },
	{ "WORLD_1", "K_WORLD_1" },
	{ "WORLD_2", "K_WORLD_2" },
	{ "WORLD_3", "K_WORLD_3" },
	{ "WORLD_4", "K_WORLD_4" },
	{ "WORLD_5", "K_WORLD_5" },
	{ "WORLD_6", "K_WORLD_6" },
	{ "WORLD_7", "K_WORLD_7" },
	{ "WORLD_8", "K_WORLD_8" },
	{ "WORLD_9", "K_WORLD_9" },
	{ "WORLD_10", "K_WORLD_10" },
	{ "WORLD_11", "K_WORLD_11" },
	{ "WORLD_12", "K_WORLD_12" },
	{ "WORLD_13", "K_WORLD_13" },
	{ "WORLD_14", "K_WORLD_14" },
	{ "WORLD_15", "K_WORLD_15" },
	{ "WORLD_16", "K_WORLD_16" },
	{ "WORLD_17", "K_WORLD_17" },
	{ "WORLD_18", "K_WORLD_18" },
	{ "WORLD_19", "K_WORLD_19" },
	{ "WORLD_20", "K_WORLD_20" },
	{ "WORLD_21", "K_WORLD_21" },
	{ "WORLD_22", "K_WORLD_22" },
	{ "WORLD_23", "K_WORLD_23" },
	{ "WORLD_24", "K_WORLD_24" },
	{ "WORLD_25", "K_WORLD_25" },
	{ "WORLD_26", "K_WORLD_26" },
	{ "WORLD_27", "K_WORLD_27" },
	{ "WORLD_28", "K_WORLD_28" },
	{ "WORLD_29", "K_WORLD_29" },
	{ "WORLD_30", "K_WORLD_30" },
	{ "WORLD_31", "K_WORLD_31" },
	{ "WORLD_32", "K_WORLD_32" },
	{ "WORLD_33", "K_WORLD_33" },
	{ "WORLD_34", "K_WORLD_34" },
	{ "WORLD_35", "K_WORLD_35" },
	{ "WORLD_36", "K_WORLD_36" },
	{ "WORLD_37", "K_WORLD_37" },
	{ "WORLD_38", "K_WORLD_38" },
	{ "WORLD_39", "K_WORLD_39" },
	{ "WORLD_40", "K_WORLD_40" },
	{ "WORLD_41", "K_WORLD_41" },
	{ "WORLD_42", "K_WORLD_42" },
	{ "WORLD_43", "K_WORLD_43" },
	{ "WORLD_44", "K_WORLD_44" },
	{ "WORLD_45", "K_WORLD_45" },
	{ "WORLD_46", "K_WORLD_46" },
	{ "WORLD_47", "K_WORLD_47" },
	{ "WORLD_48", "K_WORLD_48" },
	{ "WORLD_49", "K_WORLD_49" },
	{ "WORLD_50", "K_WORLD_50" },
	{ "WORLD_51", "K_WORLD_51" },
	{ "WORLD_52", "K_WORLD_52" },
	{ "WORLD_53", "K_WORLD_53" },
	{ "WORLD_54", "K_WORLD_54" },
	{ "WORLD_55", "K_WORLD_55" },
	{ "WORLD_56", "K_WORLD_56" },
	{ "WORLD_57", "K_WORLD_57" },
	{ "WORLD_58", "K_WORLD_58" },
	{ "WORLD_59", "K_WORLD_59" },
	{ "WORLD_60", "K_WORLD_60" },
	{ "WORLD_61", "K_WORLD_61" },
	{ "WORLD_62", "K_WORLD_62" },
	{ "WORLD_63", "K_WORLD_63" },
	{ "WORLD_64", "K_WORLD_64" },
	{ "WORLD_65", "K_WORLD_65" },
	{ "WORLD_66", "K_WORLD_66" },
	{ "WORLD_67", "K_WORLD_67" },
	{ "WORLD_68", "K_WORLD_68" },
	{ "WORLD_69", "K_WORLD_69" },
	{ "WORLD_70", "K_WORLD_70" },
	{ "WORLD_71", "K_WORLD_71" },
	{ "WORLD_72", "K_WORLD_72" },
	{ "WORLD_73", "K_WORLD_73" },
	{ "WORLD_74", "K_WORLD_74" },
	{ "WORLD_75", "K_WORLD_75" },
	{ "WORLD_76", "K_WORLD_76" },
	{ "WORLD_77", "K_WORLD_77" },
	{ "WORLD_78", "K_WORLD_78" },
	{ "WORLD_79", "K_WORLD_79" },
	{ "WORLD_80", "K_WORLD_80" },
	{ "WORLD_81", "K_WORLD_81" },
	{ "WORLD_82", "K_WORLD_82" },
	{ "WORLD_83", "K_WORLD_83" },
	{ "WORLD_84", "K_WORLD_84" },
	{ "WORLD_85", "K_WORLD_85" },
	{ "WORLD_86", "K_WORLD_86" },
	{ "WORLD_87", "K_WORLD_87" },
	{ "WORLD_88", "K_WORLD_88" },
	{ "WORLD_89", "K_WORLD_89" },
	{ "WORLD_90", "K_WORLD_90" },
	{ "WORLD_91", "K_WORLD_91" },
	{ "WORLD_92", "K_WORLD_92" },
	{ "WORLD_93", "K_WORLD_93" },
	{ "WORLD_94", "K_WORLD_94" },
	{ "WORLD_95", "K_WORLD_95" },
	{ "WINDOWS", "K_SUPER" },
	{ "COMPOSE", "K_COMPOSE" },
	{ "MODE", "K_MODE" },
	{ "HELP", "K_HELP" },
	{ "PRINT", "K_PRINT" },
	{ "SYSREQ", "K_SYSREQ" },
	{ "SCROLLOCK", "K_SCROLLOCK" },
	{ "BREAK", "K_BREAK" },
	{ "MENU", "K_MENU" },
	{ "POWER", "K_POWER" },
	{ "EURO", "K_EURO" },
	{ "UNDO", "K_UNDO" },
	{ "PAD0_A", "K_PAD0_A" },
	{ "PAD0_B", "K_PAD0_B" },
	{ "PAD0_X", "K_PAD0_X" },
	{ "PAD0_Y", "K_PAD0_Y" },
	{ "PAD0_BACK", "K_PAD0_BACK" },
	{ "PAD0_GUIDE", "K_PAD0_GUIDE" },
	{ "PAD0_START", "K_PAD0_START" },
	{ "PAD0_LEFTSTICK_CLICK", "K_PAD0_LEFTSTICK_CLICK" },
	{ "PAD0_RIGHTSTICK_CLICK", "K_PAD0_RIGHTSTICK_CLICK" },
	{ "PAD0_LEFTSHOULDER", "K_PAD0_LEFTSHOULDER" },
	{ "PAD0_RIGHTSHOULDER", "K_PAD0_RIGHTSHOULDER" },
	{ "PAD0_DPAD_UP", "K_PAD0_DPAD_UP" },
	{ "PAD0_DPAD_DOWN", "K_PAD0_DPAD_DOWN" },
	{ "PAD0_DPAD_LEFT", "K_PAD0_DPAD_LEFT" },
	{ "PAD0_DPAD_RIGHT", "K_PAD0_DPAD_RIGHT" },
	{ "PAD0_LEFTSTICK_LEFT", "K_PAD0_LEFTSTICK_LEFT" },
	{ "PAD0_LEFTSTICK_RIGHT", "K_PAD0_LEFTSTICK_RIGHT" },
	{ "PAD0_LEFTSTICK_UP", "K_PAD0_LEFTSTICK_UP" },
	{ "PAD0_LEFTSTICK_DOWN", "K_PAD0_LEFTSTICK_DOWN" },
	{ "PAD0_RIGHTSTICK_LEFT", "K_PAD0_RIGHTSTICK_LEFT" },
	{ "PAD0_RIGHTSTICK_RIGHT", "K_PAD0_RIGHTSTICK_RIGHT" },
	{ "PAD0_RIGHTSTICK_UP", "K_PAD0_RIGHTSTICK_UP" },
	{ "PAD0_RIGHTSTICK_DOWN", "K_PAD0_RIGHTSTICK_DOWN" },
	{ "PAD0_LEFTTRIGGER", "K_PAD0_LEFTTRIGGER" },
	{ "PAD0_RIGHTTRIGGER", "K_PAD0_RIGHTTRIGGER" },
	{ "PAD0_MISC1", "K_PAD0_MISC1" },
	{ "PAD0_PADDLE1", "K_PAD0_PADDLE1" },
	{ "PAD0_PADDLE2", "K_PAD0_PADDLE2" },
	{ "PAD0_PADDLE3", "K_PAD0_PADDLE3" },
	{ "PAD0_PADDLE4", "K_PAD0_PADDLE4" },
	{ "PAD0_TOUCHPAD", "K_PAD0_TOUCHPAD" },}

local keynumByName: { [string]: number } = {}
local nameByKeynum: { [number]: string } = {}
for _, pair in names do
	local num = tonumber(pair[2]) or C[pair[2]]
	if num then
		keynumByName[string.upper(pair[1])] = num
		if nameByKeynum[num] == nil then
			nameByKeynum[num] = pair[1]
		end
	end
end

local bindings: { [number]: string } = {}
local down: { [number]: boolean } = {}
local repeats: { [number]: number } = {}
local catcher = 0
Keys.overstrike = false
Keys.anyKeyDown = 0

-- Set by the client: the ui / cgame / console handlers.
Keys.ui = nil :: any -- { KeyEvent(key, down), SetActiveMenu(menu), IsFullscreen() }
Keys.cgame = nil :: any -- { KeyEvent(key, down) }
Keys.console = nil :: any -- { Toggle(), Key(key, char) }
Keys.message = nil :: any -- { Key(key, char) }
Keys.connState = function(): number
	return C.CA_DISCONNECTED
end

-- Key_StringToKeynum: a name, a single character, or 0x hex.
function Keys.StringToKeynum(s: string): number
	if s == "" then
		return -1
	end
	if #s == 1 then
		return string.byte(string.lower(s))
	end
	local n = keynumByName[string.upper(s)]
	if n then
		return n
	end
	if s:sub(1, 2):lower() == "0x" and #s == 4 then
		return tonumber(s:sub(3), 16) or -1
	end
	return -1
end

-- Key_KeynumToString
function Keys.KeynumToString(k: number): string
	if k < 0 or k >= C.MAX_KEYS then
		return "<OUT OF RANGE>"
	end
	if k > 32 and k < 127 and k ~= 34 and k ~= 59 then -- printable, not " or ;
		return string.char(k)
	end
	return nameByKeynum[k] or string.format("0x%02x", k)
end

function Keys.SetBinding(k: number, cmd: string)
	if k < 0 then
		return
	end
	bindings[k] = if cmd ~= "" then cmd else nil
end

function Keys.GetBinding(k: number): string
	return bindings[k] or ""
end

-- Key_GetKey: the first key bound to exactly `binding`.
function Keys.GetKey(binding: string): number
	for k = 0, C.MAX_KEYS - 1 do
		if bindings[k] and string.lower(bindings[k]) == string.lower(binding) then
			return k
		end
	end
	return -1
end

function Keys.IsDown(k: number): boolean
	return down[k] == true
end

function Keys.GetCatcher(): number
	return catcher
end

function Keys.SetCatcher(c: number)
	-- changing catchers releases held keys, as Key_SetCatcher does
	if c ~= catcher then
		Keys.ClearStates()
	end
	catcher = c
end

function Keys.ClearStates()
	Keys.anyKeyDown = 0
	for k in down do
		if down[k] then
			Keys.Event(k, false, 0)
		end
	end
	table.clear(down)
	table.clear(repeats)
end

-- "+cmd" binds carry the key and time so two keys on one button work.
local function parseBinding(k: number, isDown: boolean, time: number)
	local b = bindings[k]
	if b == nil then
		return
	end
	for part in (b .. ";"):gmatch("([^;]*);") do
		local p = part:match("^%s*(.-)%s*$")
		if p:sub(1, 1) == "+" then
			local cmd = ("%s%s %d %d\n"):format(if isDown then "+" else "-", p:sub(2), k, time)
			Cmd.AddText(cmd)
		elseif isDown and p ~= "" then
			Cmd.AddText(p .. "\n")
		end
	end
end

-- CL_KeyDownEvent / CL_KeyUpEvent
function Keys.Event(k: number, isDown: boolean, time: number)
	if isDown then
		repeats[k] = (repeats[k] or 0) + 1
		if repeats[k] == 1 then
			Keys.anyKeyDown += 1
		end
	else
		repeats[k] = 0
		Keys.anyKeyDown = math.max(Keys.anyKeyDown - 1, 0)
	end
	down[k] = isDown

	if isDown then
		-- console key, or shift-escape
		if k == C.K_CONSOLE or (k == C.K_ESCAPE and down[C.K_SHIFT]) then
			if Keys.console then
				Keys.console.Toggle()
			end
			return
		end
		if k == C.K_ESCAPE then
			if bit32.band(catcher, C.KEYCATCH_MESSAGE) ~= 0 then
				if Keys.message then
					Keys.message.Key(k, nil)
				end
				return
			end
			if bit32.band(catcher, C.KEYCATCH_CGAME) ~= 0 then
				Keys.SetCatcher(bit32.band(catcher, bit32.bnot(C.KEYCATCH_CGAME)))
				if Keys.cgame then
					Keys.cgame.EventHandling(C.CGAME_EVENT_NONE)
				end
				return
			end
			if bit32.band(catcher, C.KEYCATCH_CONSOLE) ~= 0 then
				if Keys.console then
					Keys.console.Toggle()
				end
				return
			end
			if bit32.band(catcher, C.KEYCATCH_UI) == 0 then
				local state = Keys.connState()
				if state == C.CA_ACTIVE and Keys.ui then
					Keys.ui.SetActiveMenu(C.UIMENU_INGAME)
				elseif Keys.ui then
					Keys.ui.SetActiveMenu(C.UIMENU_MAIN)
				end
				return
			end
			if Keys.ui then
				Keys.ui.KeyEvent(k, true)
			end
			return
		end
		if bit32.band(catcher, C.KEYCATCH_CONSOLE) ~= 0 then
			if Keys.console then
				Keys.console.Key(k, nil)
			end
		elseif bit32.band(catcher, C.KEYCATCH_UI) ~= 0 then
			if Keys.ui then
				Keys.ui.KeyEvent(k, true)
			end
		elseif bit32.band(catcher, C.KEYCATCH_CGAME) ~= 0 then
			if Keys.cgame then
				Keys.cgame.KeyEvent(k, true)
			end
		elseif bit32.band(catcher, C.KEYCATCH_MESSAGE) ~= 0 then
			if Keys.message then
				Keys.message.Key(k, nil)
			end
		else
			parseBinding(k, true, time)
		end
	else
		if bit32.band(catcher, C.KEYCATCH_UI) ~= 0 and Keys.ui then
			Keys.ui.KeyEvent(k, false)
		elseif bit32.band(catcher, C.KEYCATCH_CGAME) ~= 0 and Keys.cgame then
			Keys.cgame.KeyEvent(k, false)
		end
		-- the "-" half always runs so a button never sticks
		parseBinding(k, false, time)
	end
end

-- CL_CharEvent: typed characters for text fields.
function Keys.CharEvent(char: string)
	if bit32.band(catcher, C.KEYCATCH_CONSOLE) ~= 0 then
		if Keys.console then
			Keys.console.Key(0, char)
		end
	elseif bit32.band(catcher, C.KEYCATCH_UI) ~= 0 then
		if Keys.ui then
			Keys.ui.KeyEvent(bit32.bor(string.byte(char), C.K_CHAR_FLAG), true)
		end
	elseif bit32.band(catcher, C.KEYCATCH_MESSAGE) ~= 0 then
		if Keys.message then
			Keys.message.Key(0, char)
		end
	end
end

-- bind commands --------------------------------------------------------------
Cmd.AddCommand("bind", function()
	local c = Cmd.Argc()
	if c < 2 then
		Cmd.print("bind <key> [command] : attach a command to a key")
		return
	end
	local k = Keys.StringToKeynum(Cmd.Argv(1))
	if k == -1 then
		Cmd.print('"' .. Cmd.Argv(1) .. '" isn\'t a valid key')
		return
	end
	if c == 2 then
		Cmd.print(if bindings[k] then ('"%s" = "%s"'):format(Cmd.Argv(1), bindings[k]) else ('"%s" is not bound'):format(Cmd.Argv(1)))
		return
	end
	Keys.SetBinding(k, Cmd.ArgsFrom(2))
end)
Cmd.AddCommand("unbind", function()
	local k = Keys.StringToKeynum(Cmd.Argv(1))
	if k ~= -1 then
		Keys.SetBinding(k, "")
	end
end)
Cmd.AddCommand("unbindall", function()
	table.clear(bindings)
end)
Cmd.AddCommand("bindlist", function()
	for k = 0, C.MAX_KEYS - 1 do
		if bindings[k] then
			Cmd.print(('%s "%s"'):format(Keys.KeynumToString(k), bindings[k]))
		end
	end
end)

-- All binds as "bind k cmd" lines (saved with the archived cvars).
function Keys.WriteBindings(): string
	local out = {}
	for k = 0, C.MAX_KEYS - 1 do
		if bindings[k] then
			table.insert(out, ('bind %s "%s"'):format(Keys.KeynumToString(k), bindings[k]))
		end
	end
	return table.concat(out, "\n")
end

return Keys
