-- The client frame (cl_main.c / cl_cgame.c / cl_ui.c / cl_scrn.c semantics):
-- owns the ScreenGui, feeds Roblox input to Keys/Input, runs the command
-- buffer, builds and sends usercmds, keeps the cgame clock, and draws the
-- cgame view, the ui and the console each frame.
local C = require(script.Parent.Parent.q.Consts)
local Cmd = require(script.Parent.Cmd)
local Cvar = require(script.Parent.Cvar)
local Keys = require(script.Parent.Keys)
local Input = require(script.Parent.Input)
local Net = require(script.Parent.Net)
local Clock = require(script.Parent.Clock)
local Console = require(script.Parent.Console)
local R2D = require(script.Parent.R2D)
local R3D = require(script.Parent.R3D)
local Snd = require(script.Parent.Snd)
local FS = require(script.Parent.FS)

local Client = {}

local G, U -- cgame / ui namespaces, loaded by Start()
Client.cgameActive = false
Client.uiActive = false
Client.realtime = 0
local lastFrame = 0
local chat: { team: boolean, text: string }? = nil

local cl_timeNudge = Cvar.Get("cl_timeNudge", "0", C.CVAR_TEMP)
Cvar.Get("protocol", "71", C.CVAR_ROM)
Cvar.Get("version", "OA 0.8.8 Roblox", C.CVAR_ROM)
Cvar.Get("name", "UnnamedPlayer", bit32.bor(C.CVAR_USERINFO, C.CVAR_ARCHIVE))

local function loadModules(folder: Instance)
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			require(child)
		end
	end
end

-- engine commands ----------------------------------------------------------------
Cmd.AddCommand("toggleconsole", function()
	Client.ToggleConsole()
end)
Cmd.AddCommand("togglemenu", function()
	local t = Clock.Milliseconds()
	Keys.Event(C.K_ESCAPE, true, t)
	Keys.Event(C.K_ESCAPE, false, t)
end)
Cmd.AddCommand("messagemode", function()
	chat = { team = false, text = "" }
	Keys.SetCatcher(bit32.bxor(Keys.GetCatcher(), C.KEYCATCH_MESSAGE))
end)
Cmd.AddCommand("messagemode2", function()
	chat = { team = true, text = "" }
	Keys.SetCatcher(bit32.bxor(Keys.GetCatcher(), C.KEYCATCH_MESSAGE))
end)
Cmd.AddCommand("exec", function()
	local name = Cmd.Argv(1)
	local text = FS.ReadFile(name) or FS.ReadFile(name .. ".cfg")
	if text then
		Cmd.InsertText(text)
	else
		Cmd.print("couldn't exec " .. name)
	end
end)
Cmd.AddCommand("cmd", function()
	Net.SendClientCommand(Cmd.Args())
end)
-- Map/mode changes the menus issue become server votes on Roblox: one place
-- hosts the match, players don't start their own servers.
local function mapVote()
	local map = Cmd.Argv(1)
	if map ~= "" then
		local gt = Cvar.VariableIntegerValue("g_gametype")
		Net.SendClientCommand(("callvote g_gametype %d"):format(gt))
		Net.SendClientCommand("callvote map " .. map)
	end
	Client.Connect()
end
Cmd.AddCommand("map", mapVote)
Cmd.AddCommand("devmap", mapVote)
Cmd.AddCommand("spmap", mapVote)
Cmd.AddCommand("connect", function()
	Client.Connect()
end)
Cmd.AddCommand("reconnect", function()
	Client.Connect()
end)
Cmd.AddCommand("disconnect", function()
	Client.Disconnect()
end)
for _, name in { "vid_restart", "snd_restart", "screenshot", "screenshotJPEG", "quit", "writeconfig", "cinematic", "s_stop" } do
	-- no Roblox equivalent: the window, renderer and process belong to Roblox
	Cmd.AddCommand(name, function() end)
end

-- Unowned commands: cgame, then ui, then the server (CL_ForwardCommandToServer).
Cmd.fallback = function(name: string): boolean
	if Client.cgameActive and G.CG_ConsoleCommand() then
		return true
	end
	if U and U.UI_ConsoleCommand(Client.realtime) then
		return true
	end
	if Net.state == C.CA_ACTIVE or Net.state == C.CA_PRIMED then
		local args = Cmd.Args()
		Net.SendClientCommand(if args ~= "" then name .. " " .. args else name)
		return true
	end
	return false
end

-- console / chat ---------------------------------------------------------------------
function Client.ToggleConsole()
	Console.open = not Console.open
	if Console.open then
		Keys.SetCatcher(bit32.bor(Keys.GetCatcher(), C.KEYCATCH_CONSOLE))
	else
		Keys.SetCatcher(bit32.band(Keys.GetCatcher(), bit32.bnot(C.KEYCATCH_CONSOLE)))
	end
end

Keys.console = { Toggle = Client.ToggleConsole, Key = Console.Key }
Keys.message = {
	Key = function(k: number, char: string?)
		if chat == nil then
			return
		end
		if k == C.K_ESCAPE then
			chat = nil
			Keys.SetCatcher(bit32.band(Keys.GetCatcher(), bit32.bnot(C.KEYCATCH_MESSAGE)))
		elseif k == C.K_ENTER or k == C.K_KP_ENTER then
			if chat.text ~= "" then
				Net.SendClientCommand(('%s "%s"'):format(if chat.team then "say_team" else "say", chat.text:gsub('"', "'")))
			end
			chat = nil
			Keys.SetCatcher(bit32.band(Keys.GetCatcher(), bit32.bnot(C.KEYCATCH_MESSAGE)))
		elseif k == C.K_BACKSPACE then
			chat.text = chat.text:sub(1, -2)
		elseif char and #char == 1 and #chat.text < 150 then
			chat.text ..= char
		end
	end,
}
Keys.connState = function()
	return Net.state
end
Input.keyCatcher = Keys.GetCatcher
Input.anyKeyDown = function()
	return Keys.anyKeyDown > 0
end

-- connection -------------------------------------------------------------------------
-- The Roblox server is always there; "connecting" means asking it to put us
-- in the game. The transport (feat/game's net) answers with a gamestate.
Client.connectRequested = false
function Client.Connect()
	Client.connectRequested = true
	if Net.transport and Net.transport.connect then
		Net.transport.connect(Cvar.InfoString(C.CVAR_USERINFO))
	end
	if Net.state == C.CA_DISCONNECTED then
		Net.state = C.CA_CONNECTING
	end
end

function Client.Disconnect()
	if Client.cgameActive then
		G.CG_Shutdown()
		Client.cgameActive = false
	end
	if Net.transport and Net.transport.disconnect then
		Net.transport.disconnect()
	end
	Net.state = C.CA_DISCONNECTED
	Client.connectRequested = false
	if U then
		U.UI_SetActiveMenu(C.UIMENU_MAIN)
	end
end

-- userinfo changes go to the server like CL_CheckUserinfo
Cvar.onChange = function(v)
	if bit32.band(v.flags, C.CVAR_USERINFO) ~= 0 and Net.state == C.CA_ACTIVE then
		Net.SendClientCommand('userinfo "' .. Cvar.InfoString(C.CVAR_USERINFO) .. '"')
	end
end

-- CL_InitCGame
local function initCGame()
	local n = Net.GetCurrentSnapshotNumber()
	G.CG_Init(n, 0, Net.clientNum)
	Client.cgameActive = true
	-- clear anything that got printed
	Console.ClearNotify()
	-- the ui stops drawing the menu once the game is up
	if U then
		U.UI_SetActiveMenu(C.UIMENU_NONE)
	end
end

-- frame -------------------------------------------------------------------------------
function Client.Frame(dtSec: number)
	local now = Clock.Milliseconds()
	local msec = now - lastFrame
	lastFrame = now
	Client.realtime = now

	Cmd.Execute()

	-- CL_SendCmd
	if Net.state == C.CA_ACTIVE then
		Input.serverTime = Net.serverTime
		local cmd = Input.CreateNewCommand(now, msec)
		Net.SendUserCmds({ cmd })
	end

	if Net.state == C.CA_PRIMED and not Client.cgameActive and Client.connectRequested then
		initCGame()
	end
	Net.SetCGameTime(now, cl_timeNudge.integer)
	Client.UpdateScreen()
	Snd.Update()
end

-- SCR_UpdateScreen. The cgame also calls it while loading (trap_UpdateScreen):
-- Roblox only presents when the script yields, so those calls build the
-- loading screen but the player sees it only if loading spans frames.
local drawing = false
function Client.UpdateScreen()
	if drawing then
		return
	end
	drawing = true
	local now = Client.realtime
	R2D.BeginFrame()
	R3D.BeginFrame()
	local uiFullscreen = U ~= nil and Client.uiActive and U.UI_IsFullscreen()
	local loading = G ~= nil and G.cg ~= nil and G.cg.infoScreenText ~= nil and G.cg.infoScreenText ~= ""
		and Net.state == C.CA_PRIMED
	if loading then
		-- CA_LOADING/CA_PRIMED: the cgame's info screen, then the ui's overlay
		G.CG_DrawActiveFrame(Net.serverTime, C.STEREO_CENTER, false)
	elseif Client.cgameActive and Net.state == C.CA_ACTIVE and not uiFullscreen then
		G.CG_DrawActiveFrame(Net.serverTime, C.STEREO_CENTER, false)
		if bit32.band(Keys.GetCatcher(), bit32.bor(C.KEYCATCH_UI, C.KEYCATCH_CGAME)) == 0 then
			Console.DrawNotify()
		end
	elseif U and (Net.state == C.CA_CONNECTING or Net.state == C.CA_PRIMED) and Client.connectRequested then
		U.UI_DrawConnectScreen(false)
	end
	if U and bit32.band(Keys.GetCatcher(), C.KEYCATCH_UI) ~= 0 then
		U.UI_Refresh(now)
	end
	if chat then
		Console.DrawSmallString(8, 64, (if chat.team then "say_team: " else "say: ") .. chat.text .. "_")
	end
	if Console.open then
		Console.DrawConsole(R2D.width, R2D.height)
	end
	R2D.EndFrame()
	R3D.EndFrame()
	drawing = false
end

-- Roblox input -> Q3 keys --------------------------------------------------------------
local KEYMAP: { [any]: number } = {}
local SHIFTED: { [number]: string } = {}
do
	local K = Enum.KeyCode
	for i = 0, 25 do
		local ch = string.char(97 + i)
		KEYMAP[K[string.upper(ch)]] = 97 + i
	end
	local digits = { "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
	for i, name in digits do
		KEYMAP[K[name]] = 47 + i
	end
	local simple = {
		Space = 32, Minus = 45, Equals = 61, LeftBracket = 91, RightBracket = 93, BackSlash = 92,
		Semicolon = 59, Quote = 39, Comma = 44, Period = 46, Slash = 47, Backquote = 96,
	}
	for name, v in simple do
		KEYMAP[K[name]] = v
	end
	local named = {
		Return = "K_ENTER", Escape = "K_ESCAPE", Tab = "K_TAB", Backspace = "K_BACKSPACE",
		Up = "K_UPARROW", Down = "K_DOWNARROW", Left = "K_LEFTARROW", Right = "K_RIGHTARROW",
		LeftShift = "K_SHIFT", RightShift = "K_SHIFT", LeftControl = "K_CTRL", RightControl = "K_CTRL",
		LeftAlt = "K_ALT", RightAlt = "K_ALT", Insert = "K_INS", Delete = "K_DEL", Home = "K_HOME",
		End = "K_END", PageUp = "K_PGUP", PageDown = "K_PGDN", Pause = "K_PAUSE", CapsLock = "K_CAPSLOCK",
		KeypadZero = "K_KP_INS", KeypadOne = "K_KP_END", KeypadTwo = "K_KP_DOWNARROW", KeypadThree = "K_KP_PGDN",
		KeypadFour = "K_KP_LEFTARROW", KeypadFive = "K_KP_5", KeypadSix = "K_KP_RIGHTARROW", KeypadSeven = "K_KP_HOME",
		KeypadEight = "K_KP_UPARROW", KeypadNine = "K_KP_PGUP", KeypadPeriod = "K_KP_DEL", KeypadDivide = "K_KP_SLASH",
		KeypadMultiply = "K_KP_STAR", KeypadMinus = "K_KP_MINUS", KeypadPlus = "K_KP_PLUS", KeypadEnter = "K_KP_ENTER",
		KeypadEquals = "K_KP_EQUALS",
	}
	for name, k in named do
		if K[name] and C[k] then
			KEYMAP[K[name]] = C[k]
		end
	end
	for i = 1, 12 do
		KEYMAP[K["F" .. i]] = C["K_F" .. i]
	end
	local shifted = { [49] = "!", [50] = "@", [51] = "#", [52] = "$", [53] = "%", [54] = "^", [55] = "&", [56] = "*",
		[57] = "(", [48] = ")", [45] = "_", [61] = "+", [91] = "{", [93] = "}", [92] = "|", [59] = ":", [39] = '"',
		[44] = "<", [46] = ">", [47] = "?", [96] = "~" }
	SHIFTED = shifted
end

local function charFor(k: number): string?
	if k >= 32 and k < 127 then
		local shift = Keys.IsDown(C.K_SHIFT)
		if k >= 97 and k <= 122 then
			return if shift then string.upper(string.char(k)) else string.char(k)
		end
		return if shift and SHIFTED[k] then SHIFTED[k] else string.char(k)
	end
	return nil
end

local function onInput(io: InputObject, isDown: boolean)
	local t = io.UserInputType
	local k
	if t == Enum.UserInputType.Keyboard then
		k = KEYMAP[io.KeyCode]
	elseif t == Enum.UserInputType.MouseButton1 then
		k = C.K_MOUSE1
	elseif t == Enum.UserInputType.MouseButton2 then
		k = C.K_MOUSE2
	elseif t == Enum.UserInputType.MouseButton3 then
		k = C.K_MOUSE3
	end
	if k == nil then
		return
	end
	Keys.Event(k, isDown, Clock.Milliseconds())
	if isDown then
		local ch = charFor(k)
		if ch then
			Keys.CharEvent(ch)
		end
	end
end

-- Boot: everything but the input/frame hookups (the parity driver and the
-- headless smoke test call this and step Client.Frame themselves).
-- Start: the LocalScript entry point.
local resize: () -> () = function() end
function Client.Boot(opts: { root: Instance?, width: number?, height: number? }?)
	opts = opts or {}
	local Players = game:GetService("Players")
	local root = opts.root
	if root == nil then
		local gui = Instance.new("ScreenGui")
		gui.Name = "OpenArena"
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.DisplayOrder = 10
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		root = gui
	end
	R2D.root = root
	resize = function()
		local cam = workspace.CurrentCamera
		local size = if opts.width then Vector2.new(opts.width, opts.height) else (cam and cam.ViewportSize or Vector2.new(640, 480))
		R2D.width, R2D.height = math.floor(size.X), math.floor(size.Y)
	end
	resize()
	local scene = Instance.new("Folder")
	scene.Name = "OAScene"
	scene.Parent = workspace
	R3D.worldRoot = scene
	R3D.camera = workspace.CurrentCamera
	Snd.worldRoot = scene
	Snd.localRoot = game:GetService("SoundService")

	local src = script.Parent.Parent
	G = require(src.cg.G)
	U = require(src.Parent.ui.q3.U)
	loadModules(src.cg)
	loadModules(src.Parent.ui.q3)
	Keys.ui = {
		KeyEvent = function(k, down)
			U.UI_KeyEvent(k, down)
		end,
		SetActiveMenu = function(m)
			U.UI_SetActiveMenu(m)
		end,
	}
	Keys.cgame = {
		KeyEvent = function(k, down)
			G.CG_KeyEvent(k, down)
		end,
		EventHandling = function(e)
			G.CG_EventHandling(e)
		end,
	}

	Cmd.ExecuteText(C.EXEC_NOW, "exec default.cfg")
	Cmd.Execute()
	-- Roblox keeps Escape for its own menu: F10 also toggles OA's
	if Keys.GetBinding(C.K_F10) == "" then
		Keys.SetBinding(C.K_F10, "togglemenu")
	end
	U.UI_Init()
	Client.uiActive = true
	U.UI_SetActiveMenu(C.UIMENU_MAIN)
end

function Client.Start(opts: { root: Instance?, width: number?, height: number? }?)
	Client.Boot(opts)
	local UIS = game:GetService("UserInputService")
	UIS.MouseIconEnabled = false
	UIS.InputBegan:Connect(function(io)
		onInput(io, true)
	end)
	UIS.InputEnded:Connect(function(io)
		onInput(io, false)
	end)
	UIS.InputChanged:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseMovement then
			local d = io.Delta
			Input.MouseDelta(d.X, d.Y)
			if bit32.band(Keys.GetCatcher(), C.KEYCATCH_UI) ~= 0 then
				U.UI_MouseEvent(d.X, d.Y)
			elseif bit32.band(Keys.GetCatcher(), C.KEYCATCH_CGAME) ~= 0 and Client.cgameActive then
				G.CG_MouseEvent(d.X, d.Y)
			end
		elseif io.UserInputType == Enum.UserInputType.MouseWheel then
			local k = if io.Position.Z > 0 then C.K_MWHEELUP else C.K_MWHEELDOWN
			local t = Clock.Milliseconds()
			Keys.Event(k, true, t)
			Keys.Event(k, false, t)
		end
	end)
	local RunService = game:GetService("RunService")
	RunService:BindToRenderStep("OpenArena", Enum.RenderPriority.Camera.Value + 1, function(dt)
		UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
		resize()
		Client.Frame(dt)
	end)
end

return Client
