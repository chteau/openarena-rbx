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
local Chat = require(script.Parent.Chat)
local R2D = require(script.Parent.R2D)
local Assets = require(script.Parent.Assets)
local R3D = require(script.Parent.R3D)
local Snd = require(script.Parent.Snd)
local FS = require(script.Parent.FS)
local LAN = require(script.Parent.LAN)
local Players = game:GetService("Players")
local Screen = require(script.Parent.Parent.Parent.ui.Screen)
local Servers = require(script.Parent.Parent.Parent.shared.net.servers)

local Client = {}

local G, U -- cgame / ui namespaces, loaded by Start()
Client.cgameActive = false
Client.uiActive = false
Client.realtime = 0
local lastFrame = 0

local cl_timeNudge = Cvar.Get("cl_timeNudge", "0", C.CVAR_TEMP)
Cvar.Get("protocol", "71", C.CVAR_ROM)
Cvar.Get("version", "OA 0.8.8 Roblox", C.CVAR_ROM)
Cvar.Get("name", "UnnamedPlayer", bit32.bor(C.CVAR_USERINFO, C.CVAR_ARCHIVE))
-- the rest of CL_Init's userinfo cvars (ioq3 cl_main.c), with OA's models
for _, v in {
	{ "rate", "25000" }, { "snaps", "20" }, { "model", "sarge" }, { "headmodel", "sarge" },
	{ "team_model", "sarge" }, { "team_headmodel", "sarge" }, { "color1", "4" }, { "color2", "5" },
	{ "handicap", "100" }, { "sex", "male" },
} do
	Cvar.Get(v[1], v[2], bit32.bor(C.CVAR_USERINFO, C.CVAR_ARCHIVE))
end
Cvar.Get("teamtask", "0", C.CVAR_USERINFO)
-- the server browser's ping timeout (a Roblox lookup takes a round trip or two)
Cvar.Get("cl_maxPing", "800", C.CVAR_ARCHIVE)
Cvar.Get("cg_predictItems", "1", bit32.bor(C.CVAR_USERINFO, C.CVAR_ARCHIVE))

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
Chat.Register(Cmd, function(which: string): number
	if not Client.cgameActive then
		return -1
	end
	return if which == "crosshair" then G.CG_CrosshairPlayer() else G.CG_LastAttacker()
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
-- Map/mode changes the menus issue: on a live Roblox server they start a
-- reserved server (sys/LAN.luau); where teleports don't exist (Studio,
-- rbx-native's runtime) they become votes on the one server there is.
-- One vote carries both: a gametype that differs from the server's rides
-- along as `callvote map <map> <gametype>` (g_cmds_3's map vote).
local function sendMapVote(map: string)
	local gt = Cvar.VariableIntegerValue("g_gametype")
	local current = tonumber(string.match(Net.ConfigString(C.CS_SERVERINFO), "\\g_gametype\\(%d+)"))
	if current ~= nil and current ~= gt then
		Net.SendClientCommand(("callvote map %s %d"):format(map, gt))
	else
		Net.SendClientCommand("callvote map " .. map)
	end
end
-- a `map` given before the game is up (from the main menu) waits for it: a
-- client command sent earlier is lost, and sv_floodProtect drops one that
-- follows the client's own within a second
local pendingMap: string? = nil
local pendingSince: number? = nil
local function mapVote()
	local map = Cmd.Argv(1)
	if LAN.Map(Cmd.Argv(0), map) then
		return
	end
	if map ~= "" then
		if Net.state == C.CA_ACTIVE then
			sendMapVote(map)
		else
			pendingMap, pendingSince = map, nil
		end
	end
	-- in the game the vote is all: when it passes, the server changes map
	-- and sends the new gamestate, which the client takes as Q3's does
	-- (CL_ParseGamestate), with no new connection. From the main menu the
	-- player still has to join.
	if Net.state == C.CA_DISCONNECTED then
		Client.Connect()
	end
end
Cmd.AddCommand("map", mapVote)
Cmd.AddCommand("devmap", mapVote)
Cmd.AddCommand("spmap", mapVote)
Cmd.AddCommand("connect", function()
	if Cmd.Argv(1) ~= "" then
		LAN.Join(Cmd.Argv(1))
	else
		Client.Connect()
	end
end)
Cmd.AddCommand("reconnect", function()
	Client.Connect()
end)
Cmd.AddCommand("disconnect", function()
	Client.Disconnect()
end)
Cmd.AddCommand("quit", function()
	-- a game can't close Roblox, so leave the server: the client is left on
	-- Roblox's disconnect screen, whose Leave button closes the experience
	local player = game:GetService("Players").LocalPlayer
	if player then
		player:Kick("Thanks for playing OpenArena!")
	end
end)
for _, name in { "vid_restart", "snd_restart", "screenshot", "screenshotJPEG", "writeconfig", "cinematic", "s_stop" } do
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

LAN.connect = function()
	Client.Connect()
end
LAN.forward = function(text: string)
	if Net.state == C.CA_ACTIVE or Net.state == C.CA_PRIMED then
		Net.SendClientCommand(text)
	end
end
-- The teleport loading screen (ReplicatedFirst.OALoadingScreen, absent
-- outside the place): up from the request until the teleport takes the
-- player away, or the request fails.
local loadingGui: ScreenGui? = nil
local function loadingModule(): any
	local m = game:GetService("ReplicatedFirst"):FindFirstChild("OALoadingScreen")
	return m and require(m)
end
LAN.showLoading = function(map: string?): string?
	local img = if map then Assets.Image("levelshots/" .. map) else nil
	local shot = img and img.id
	local ok, gui = pcall(function()
		local screen = loadingModule().build(map, shot)
		-- Roblox shows this one during the teleport and hands it over on arrival
		game:GetService("TeleportService"):SetTeleportGui(screen)
		screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		return screen
	end)
	if ok then
		LAN.hideLoading()
		loadingGui = gui
		-- never stick if the teleport doesn't happen
		task.delay(90, function()
			if loadingGui == gui then
				LAN.hideLoading()
			end
		end)
	end
	return shot
end
LAN.hideLoading = function()
	local gui = loadingGui
	loadingGui = nil
	if gui then
		pcall(function()
			loadingModule().dismiss(gui)
		end)
	end
end
-- the arriving loading screen (ReplicatedFirst script) waits for this
local mapReady = false
function Client.markReady()
	if not mapReady then
		mapReady = true
		pcall(function()
			Players.LocalPlayer:SetAttribute("OAReady", true)
		end)
	end
end

-- a join or start that didn't happen: the main menu's error box, as a
-- failed connect shows it
LAN.fail = function(msg: string)
	LAN.hideLoading()
	Client.markReady()
	Cvar.Set("com_errorMessage", msg)
	print(msg .. "\n")
	if U and not Client.cgameActive then
		U.UI_SetActiveMenu(C.UIMENU_MAIN)
	end
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
Keys.message = { Key = Chat.Key }
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
	Net.lastExecutedServerCommand = 0
	if Net.transport and Net.transport.connect then
		Net.transport.connect(Cvar.InfoString(C.CVAR_USERINFO))
	end
	if Net.state == C.CA_DISCONNECTED then
		Net.state = C.CA_CONNECTING
	end
end

-- set while a frame draws (Client.UpdateScreen)
local drawing = false
local restartPending = false

-- A new gamestate (map change, map_restart from the server side): cgame
-- starts again on the next frame, as CL_ParseGamestate -> CL_InitCGame.
-- The frame can yield (a mesh loading), which lets the gamestate in while
-- the cgame draws: it then finishes that frame on the old level first.
function Client.RestartCGame()
	if drawing then
		restartPending = true
		return
	end
	if Client.cgameActive then
		G.CG_Shutdown()
		Client.cgameActive = false
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
	pendingMap = nil
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
local cgameLoading = false
local function initCGame()
	local n = Net.GetCurrentSnapshotNumber()
	-- the commands the old cgame already ran are not run again; from 0 the
	-- new cgame would ask for ones long cycled out of the ring
	G.CG_Init(n, Net.lastExecutedServerCommand, Net.clientNum)
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
	if Client.cgameActive then
		Chat.Drain(G.CG_ChatMessage)
	end

	-- CL_SendCmd
	-- CL_CreateNewCommands runs from CA_PRIMED on: the server moves a client
	-- into the world (SV_ClientEnterWorld) on its first usercmd, and only
	-- then do snapshots lose SNAPFLAG_NOT_ACTIVE
	if Net.state == C.CA_ACTIVE or Net.state == C.CA_PRIMED then
		Input.serverTime = Net.serverTime
		local cmd = Input.CreateNewCommand(now, msec)
		Net.SendUserCmds({ cmd })
	end

	if Net.state == C.CA_PRIMED and not Client.cgameActive and not cgameLoading and Client.connectRequested then
		-- CG_Init yields while it loads media, and the render step keeps
		-- calling this function meanwhile: only the first frame starts it
		cgameLoading = true
		local ok, err = pcall(initCGame)
		cgameLoading = false
		if not ok then
			error(err, 0)
		end
	end
	if pendingMap and Net.state == C.CA_ACTIVE then
		pendingSince = pendingSince or now
		if now - pendingSince >= 1500 then
			sendMapVote(pendingMap)
			pendingMap = nil
		end
	end
	-- CL_SetCGameTime, once the cgame is up (it stays CA_PRIMED while
	-- loading), with the clock as it is now rather than at the top of the
	-- frame: snapshots that came in while the frame yielded in CG_Init
	-- would otherwise put the client's server time ahead by the length of
	-- the yield, and the server, which keeps the newest usercmd time it
	-- ran, would drop every usercmd until its own clock caught up
	if not cgameLoading then
		Net.SetCGameTime(Clock.Milliseconds(), cl_timeNudge.integer)
	end
	Client.UpdateScreen()
	Snd.Update()
end

-- SCR_UpdateScreen. The cgame also calls it while loading (trap_UpdateScreen):
-- Roblox only presents when the script yields, so those calls build the
-- loading screen but the player sees it only if loading spans frames.
local drawScreen
function Client.UpdateScreen()
	if drawing then
		return
	end
	-- an error in one frame must not leave `drawing` set, which would
	-- freeze the screen for good
	drawing = true
	local ok, err = xpcall(drawScreen, debug.traceback)
	drawing = false
	if restartPending then
		restartPending = false
		Client.RestartCGame()
	end
	if not ok then
		warn("SCR_UpdateScreen: " .. tostring(err))
	end
end
function drawScreen()
	local now = Client.realtime
	R2D.BeginFrame()
	R3D.BeginFrame()
	local uiFullscreen = U ~= nil and Client.uiActive and U.UI_IsFullscreen()
	-- SCR_DrawScreenField: wide screens get their sides cleared to black
	-- unless they are displaying game renderings
	if (uiFullscreen or Net.state < C.CA_LOADING) and R2D.width * 480 > R2D.height * 640 then
		R2D.SetColor({ [0] = 0, [1] = 0, [2] = 0, [3] = 1 })
		R2D.DrawStretchPic(0, 0, R2D.width, R2D.height, 0, 0, 0, 0, Assets.RegisterShader("white", false))
		R2D.SetColor(nil)
	end
	local loading = G ~= nil and G.cg ~= nil and G.cg.infoScreenText ~= nil and G.cg.infoScreenText ~= ""
		and Net.state == C.CA_PRIMED
	if loading then
		-- CA_LOADING/CA_PRIMED: the cgame's info screen, then the ui's overlay
		G.CG_DrawActiveFrame(Net.serverTime, C.STEREO_CENTER, false)
	elseif Client.cgameActive and Net.state == C.CA_ACTIVE and not uiFullscreen then
		G.CG_DrawActiveFrame(Net.serverTime, C.STEREO_CENTER, false)
		Client.markReady()
		if bit32.band(Keys.GetCatcher(), bit32.bor(C.KEYCATCH_UI, C.KEYCATCH_CGAME)) == 0 then
			Chat.Draw(Console.DrawNotify())
		end
	elseif U and (Net.state == C.CA_CONNECTING or Net.state == C.CA_PRIMED) and Client.connectRequested then
		U.UI_DrawConnectScreen(false)
	end
	if U and bit32.band(Keys.GetCatcher(), C.KEYCATCH_UI) ~= 0 then
		U.UI_Refresh(now)
	end
	if Console.open then
		Console.DrawConsole(R2D.width, R2D.height)
	end
	R2D.EndFrame()
	R3D.EndFrame()
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

-- Roblox keeps Escape for its own menu, so P stands in for OA's Escape
-- (open/close the menu, back out of a submenu) unless the player is typing.
local function typing(): boolean
	local catcher = Keys.GetCatcher()
	if bit32.band(catcher, bit32.bor(C.KEYCATCH_MESSAGE, C.KEYCATCH_CONSOLE)) ~= 0 then
		return true
	end
	if bit32.band(catcher, C.KEYCATCH_UI) ~= 0 and U and U.uis.activemenu then
		local item = U.Menu_ItemAtCursor(U.uis.activemenu)
		return item ~= nil and item.generic.type == C.MTYPE_FIELD
	end
	return false
end

local menuKeyDown, escapeDown = false, false
local function onInput(io: InputObject, isDown: boolean)
	local t = io.UserInputType
	local k
	if t == Enum.UserInputType.Keyboard then
		k = KEYMAP[io.KeyCode]
		if io.KeyCode == Enum.KeyCode.Escape then
			-- only to cancel the chat prompt or close the console
			if isDown then
				escapeDown = typing()
			end
			if not escapeDown then
				return
			end
		elseif io.KeyCode == Enum.KeyCode.P then
			if isDown then
				menuKeyDown = not typing()
			end
			if menuKeyDown then
				Keys.Event(C.K_ESCAPE, isDown, Clock.Milliseconds())
				return
			end
		end
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
	local catcher = Keys.GetCatcher()
	Keys.Event(k, isDown, Clock.Milliseconds())
	-- ioq3 buffers a bind's command, so the key's own character reaches the
	-- catcher it was pressed under: the t of messagemode isn't typed
	if isDown and Keys.GetCatcher() == catcher then
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

-- The safe area (notches, the Roblox topbar) as insets from the screen
-- edges: a probe ScreenGui with CoreUISafeInsets against the full-screen
-- root. Engines without ScreenInsets fall back to the topbar inset alone.
local safeProbe: ScreenGui? = nil
local function safeInsets(root: Instance): Screen.Insets
	local ok, insets = pcall(function()
		if safeProbe == nil then
			local probe = Instance.new("ScreenGui")
			probe.Name = "OASafeArea"
			probe.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
			probe.Parent = root.Parent
			safeProbe = probe
		end
		local r, p = root :: ScreenGui, safeProbe :: ScreenGui
		local r0, p0 = r.AbsolutePosition, p.AbsolutePosition
		local r1, p1 = r0 + r.AbsoluteSize, p0 + p.AbsoluteSize
		return {
			left = math.max(0, p0.X - r0.X),
			top = math.max(0, p0.Y - r0.Y),
			right = math.max(0, r1.X - p1.X),
			bottom = math.max(0, r1.Y - p1.Y),
		}
	end)
	if ok then
		return insets
	end
	local topLeft = game:GetService("GuiService"):GetGuiInset()
	return { left = 0, top = topLeft.Y, right = 0, bottom = 0 }
end

-- A new viewport size or safe area: the cgame and q3_ui re-read glconfig
-- and redo their screen layout (live, like a vid_restart without one).
local function screenChanged()
	if U ~= nil and U.uis ~= nil and U.uis.glconfig ~= nil then
		R2D.GetGlconfig(U.uis.glconfig)
		Screen.uiSetup(U.uis)
	end
	if G ~= nil and G.cgs ~= nil and G.cgs.screenLayout ~= nil then
		R2D.GetGlconfig(G.cgs.glconfig)
		Screen.cgSetup(G.cgs)
	end
end
function Client.Boot(opts: { root: Instance?, width: number?, height: number?, teleportData: any? }?)
	opts = opts or {}
	local root = opts.root
	if root == nil then
		local gui = Instance.new("ScreenGui")
		gui.Name = "OpenArena"
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		-- full screen, notch area included: Screen.insets keeps the HUD clear of it
		pcall(function()
			gui.ScreenInsets = Enum.ScreenInsets.None
			gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
		end)
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.DisplayOrder = 10
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		root = gui
	end
	R2D.root = root
	FS.maps = Assets.index.maps
	local key = ""
	resize = function()
		local cam = workspace.CurrentCamera
		local size = if opts.width then Vector2.new(opts.width, opts.height) else (cam and cam.ViewportSize or Vector2.new(640, 480))
		R2D.width, R2D.height = math.floor(size.X), math.floor(size.Y)
		if opts.root == nil then
			Screen.insets = safeInsets(root)
		end
		local ins = Screen.insets
		local k = table.concat({ R2D.width, R2D.height, ins.left, ins.top, ins.right, ins.bottom }, " ")
		if k ~= key then
			key = k
			screenChanged()
		end
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
	-- Roblox keeps Escape for its own menu: P (onInput) and F10 toggle OA's
	if Keys.GetBinding(C.K_F10) == "" then
		Keys.SetBinding(C.K_F10, "togglemenu")
	end
	U.UI_Init()
	Client.uiActive = true
	U.UI_SetActiveMenu(C.UIMENU_MAIN)
	-- the server names a player by their Roblox name: the menus show the same
	local me = Players.LocalPlayer
	if me then
		Cvar.Set("name", Servers.playerName(me.DisplayName, me.Name))
	end
	-- after Cvar.onChange is set above: LAN chains its favorites hook to it
	LAN.Register()
	LAN.Start(opts.teleportData)
end

function Client.Start(opts: { root: Instance?, width: number?, height: number? }?)
	local o: any = table.clone(opts or {})
	pcall(function()
		o.teleportData = game:GetService("TeleportService"):GetLocalPlayerTeleportData()
	end)
	Client.Boot(o)
	local note = LAN.note()
	if note then
		note.OnClientEvent:Connect(function(kind, msg)
			if kind == "teleportfailed" then
				LAN.fail("Teleport failed: " .. tostring(msg))
			end
		end)
	end
	Chat.Start()
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
