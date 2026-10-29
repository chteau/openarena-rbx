-- Usercmd generation (client/cl_input.c semantics): the +/- button
-- commands, key-held fractions, keyboard turning, mouse look with
-- sensitivity/m_yaw/m_pitch/cl_mouseAccel, run/walk, and one usercmd_t per
-- client frame kept in a CMD_BACKUP ring for the cgame's prediction.
-- Gamepad and touch input are not mapped yet (docs/client-notes.md).
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local Cmd = require(script.Parent.Cmd)
local Cvar = require(script.Parent.Cvar)

local Input = {}

local CMD_BACKUP = C.CMD_BACKUP
local CMD_MASK = CMD_BACKUP - 1

local cl_yawspeed = Cvar.Get("cl_yawspeed", "140", C.CVAR_ARCHIVE)
local cl_pitchspeed = Cvar.Get("cl_pitchspeed", "140", C.CVAR_ARCHIVE)
local cl_anglespeedkey = Cvar.Get("cl_anglespeedkey", "1.5", 0)
local cl_run = Cvar.Get("cl_run", "1", C.CVAR_ARCHIVE)
local sensitivity = Cvar.Get("sensitivity", "5", C.CVAR_ARCHIVE)
local cl_mouseAccel = Cvar.Get("cl_mouseAccel", "0", C.CVAR_ARCHIVE)
local cl_freelook = Cvar.Get("cl_freelook", "1", C.CVAR_ARCHIVE)
local m_pitch = Cvar.Get("m_pitch", "0.022", C.CVAR_ARCHIVE)
local m_yaw = Cvar.Get("m_yaw", "0.022", C.CVAR_ARCHIVE)
local m_forward = Cvar.Get("m_forward", "0.25", C.CVAR_ARCHIVE)
local m_side = Cvar.Get("m_side", "0.25", C.CVAR_ARCHIVE)
local m_filter = Cvar.Get("m_filter", "0", C.CVAR_ARCHIVE)

-- kbutton_t
local function kbutton()
	return { down = { 0, 0 }, downtime = 0, msec = 0, active = false, wasPressed = false }
end

local in_left, in_right, in_forward, in_back = kbutton(), kbutton(), kbutton(), kbutton()
local in_lookup, in_lookdown, in_moveleft, in_moveright = kbutton(), kbutton(), kbutton(), kbutton()
local in_strafe, in_speed, in_up, in_down = kbutton(), kbutton(), kbutton(), kbutton()
local in_mlook = kbutton()
local in_buttons = {}
for i = 0, 15 do
	in_buttons[i] = kbutton()
end

-- client state the input code reads/writes (cl.viewangles etc.)
Input.viewangles = { [0] = 0, [1] = 0, [2] = 0 }
Input.cmdNumber = 0
Input.cmds = {}
for i = 0, CMD_BACKUP - 1 do
	Input.cmds[i] = T.usercmd_t()
end
Input.cgameUserCmdValue = 0
Input.cgameSensitivity = 1
Input.serverTime = 0 -- cl.serverTime, set by the client each frame
Input.frameMsec = 0
Input.frameTime = 0 -- com_frameTime
Input.mouseDx, Input.mouseDy = 0, 0
Input.oldMouseDx, Input.oldMouseDy = 0, 0
-- Set by the client: is a menu/console/message grabbing keys (no move)?
Input.keyCatcher = function(): number
	return 0
end
Input.anyKeyDown = function(): boolean
	return false
end

local function keyDown(b)
	local c = Cmd.Argv(1)
	local k = if c ~= "" then tonumber(c) or -1 else -1 -- typed manually at the console for continuous down
	if k == b.down[1] or k == b.down[2] then
		return -- repeating key
	end
	if b.down[1] == 0 then
		b.down[1] = k
	elseif b.down[2] == 0 then
		b.down[2] = k
	else
		print("Three keys down for a button!")
		return
	end
	if b.active then
		return -- still down
	end
	b.downtime = tonumber(Cmd.Argv(2)) or Input.frameTime
	b.active = true
	b.wasPressed = true
end

local function keyUp(b)
	local c = Cmd.Argv(1)
	if c == "" then
		-- typed manually at the console, assume for unsticking, so clear all
		b.down[1], b.down[2] = 0, 0
		b.active = false
		return
	end
	local k = tonumber(c) or 0
	if b.down[1] == k then
		b.down[1] = 0
	elseif b.down[2] == k then
		b.down[2] = 0
	else
		return -- key up without corresponding down (menu pass through)
	end
	if b.down[1] ~= 0 or b.down[2] ~= 0 then
		return -- some other key is still holding it down
	end
	b.active = false
	-- save timestamp for partial frame summing
	local uptime = tonumber(Cmd.Argv(2)) or 0
	if uptime ~= 0 then
		b.msec += uptime - b.downtime
	else
		b.msec += Input.frameMsec / 2
	end
	b.active = false
end

-- CL_KeyState: fraction of the frame the key was down
local function keyState(key): number
	local msec = key.msec
	key.msec = 0
	if key.active then
		-- still down
		if key.downtime == 0 then
			msec = Input.frameTime
		else
			msec += Input.frameTime - key.downtime
		end
		key.downtime = Input.frameTime
	end
	if Input.frameMsec == 0 then
		return 0
	end
	local val = msec / Input.frameMsec
	return math.clamp(val, 0, 1)
end

local function bind(name: string, b)
	Cmd.AddCommand("+" .. name, function()
		keyDown(b)
	end)
	Cmd.AddCommand("-" .. name, function()
		keyUp(b)
	end)
end
bind("moveup", in_up)
bind("movedown", in_down)
bind("left", in_left)
bind("right", in_right)
bind("forward", in_forward)
bind("back", in_back)
bind("lookup", in_lookup)
bind("lookdown", in_lookdown)
bind("strafe", in_strafe)
bind("moveleft", in_moveleft)
bind("moveright", in_moveright)
bind("speed", in_speed)
bind("attack", in_buttons[0])
for i = 0, 14 do
	bind("button" .. i, in_buttons[i])
end
bind("mlook", in_mlook)
Cmd.AddCommand("-mlook", function()
	keyUp(in_mlook)
	if cl_freelook.integer == 0 then
		-- IN_CenterView
		Input.viewangles[C.PITCH] = 0
	end
end)
Cmd.AddCommand("centerview", function()
	Input.viewangles[C.PITCH] = 0
end)

local function angleMod(a: number): number
	return (360.0 / 65536) * bit32.band(math.floor(a * (65536 / 360.0)), 65535)
end

-- CL_AdjustAngles
local function adjustAngles()
	local speed
	if bit32.bxor(if in_speed.active then 1 else 0, cl_run.integer ~= 0 and 1 or 0) ~= 0 then
		speed = 0.001 * Input.frameMsec * cl_anglespeedkey.value
	else
		speed = 0.001 * Input.frameMsec
	end
	if not in_strafe.active then
		Input.viewangles[C.YAW] -= speed * cl_yawspeed.value * keyState(in_right)
		Input.viewangles[C.YAW] += speed * cl_yawspeed.value * keyState(in_left)
	end
	Input.viewangles[C.PITCH] -= speed * cl_pitchspeed.value * keyState(in_lookup)
	Input.viewangles[C.PITCH] += speed * cl_pitchspeed.value * keyState(in_lookdown)
end

local function clampChar(v: number): number
	v = math.floor(v + 0.5)
	return math.clamp(v, -128, 127)
end

-- CL_KeyMove
local function keyMove(cmd)
	local movespeed
	-- adjust for speed key / running; the walking flag is to keep animations
	-- consistent even during acceleration and develeration
	if bit32.bxor(if in_speed.active then 1 else 0, cl_run.integer ~= 0 and 1 or 0) ~= 0 then
		movespeed = 127
		cmd.buttons = bit32.band(cmd.buttons, bit32.bnot(C.BUTTON_WALKING))
	else
		cmd.buttons = bit32.bor(cmd.buttons, C.BUTTON_WALKING)
		movespeed = 64
	end
	local forward, side, up = 0, 0, 0
	if in_strafe.active then
		side += movespeed * keyState(in_right)
		side -= movespeed * keyState(in_left)
	end
	side += movespeed * keyState(in_moveright)
	side -= movespeed * keyState(in_moveleft)
	up += movespeed * keyState(in_up)
	up -= movespeed * keyState(in_down)
	forward += movespeed * keyState(in_forward)
	forward -= movespeed * keyState(in_back)
	cmd.forwardmove = clampChar(forward)
	cmd.rightmove = clampChar(side)
	cmd.upmove = clampChar(up)
end

-- CL_MouseMove
local function mouseMove(cmd)
	local mx, my
	if m_filter.integer ~= 0 then
		mx = (Input.mouseDx + Input.oldMouseDx) * 0.5
		my = (Input.mouseDy + Input.oldMouseDy) * 0.5
	else
		mx, my = Input.mouseDx, Input.mouseDy
	end
	Input.oldMouseDx, Input.oldMouseDy = Input.mouseDx, Input.mouseDy
	Input.mouseDx, Input.mouseDy = 0, 0
	if mx == 0 and my == 0 then
		return
	end
	if cl_mouseAccel.value ~= 0 and Input.frameMsec > 0 then
		local rate = math.sqrt(mx * mx + my * my) / Input.frameMsec
		local accel = sensitivity.value + rate * cl_mouseAccel.value
		mx *= accel
		my *= accel
	else
		mx *= sensitivity.value
		my *= sensitivity.value
	end
	-- ingame FOV
	mx *= Input.cgameSensitivity
	my *= Input.cgameSensitivity
	-- add mouse X/Y movement to cmd
	if in_strafe.active then
		cmd.rightmove = clampChar(cmd.rightmove + m_side.value * mx)
	else
		Input.viewangles[C.YAW] -= m_yaw.value * mx
	end
	if (in_mlook.active or cl_freelook.integer ~= 0) and not in_strafe.active then
		Input.viewangles[C.PITCH] += m_pitch.value * my
	else
		cmd.forwardmove = clampChar(cmd.forwardmove - m_forward.value * my)
	end
end

-- CL_CmdButtons
local function cmdButtons(cmd)
	-- figure button bits; send a button bit even if the key was pressed and
	-- released in less than a frame
	for i = 0, 14 do
		if in_buttons[i].active or in_buttons[i].wasPressed then
			cmd.buttons = bit32.bor(cmd.buttons, bit32.lshift(1, i))
		end
		in_buttons[i].wasPressed = false
	end
	if bit32.band(Input.keyCatcher(), C.KEYCATCH_UI) ~= 0 then
		cmd.buttons = bit32.bor(cmd.buttons, C.BUTTON_TALK)
	end
	-- allow the game to know if any key at all is currently pressed, even if
	-- it isn't bound to anything
	if Input.anyKeyDown() and Input.keyCatcher() == 0 then
		cmd.buttons = bit32.bor(cmd.buttons, C.BUTTON_ANY)
	end
end

local function angle2short(x: number): number
	return bit32.band(math.floor(x * 65536 / 360), 65535)
end

-- CL_CreateCmd
local function createCmd()
	local oldPitch = Input.viewangles[C.PITCH]
	adjustAngles()
	local cmd = T.usercmd_t()
	cmdButtons(cmd)
	keyMove(cmd)
	mouseMove(cmd)
	-- check to make sure the angles haven't wrapped
	if Input.viewangles[C.PITCH] - oldPitch > 90 then
		Input.viewangles[C.PITCH] = oldPitch + 90
	elseif oldPitch - Input.viewangles[C.PITCH] > 90 then
		Input.viewangles[C.PITCH] = oldPitch - 90
	end
	-- CL_FinishMove
	cmd.weapon = Input.cgameUserCmdValue
	cmd.serverTime = Input.serverTime
	for i = 0, 2 do
		cmd.angles[i] = angle2short(Input.viewangles[i])
	end
	return cmd
end

-- CL_CreateNewCommands: one usercmd per client frame. `frameTime` is the
-- client's millisecond clock, `msec` the time since the last frame.
function Input.CreateNewCommand(frameTime: number, msec: number)
	Input.frameTime = frameTime
	Input.frameMsec = math.clamp(msec, 1, 200)
	-- the catchers own the keys while a menu or the console is up
	Input.cmdNumber += 1
	local cmd = createCmd()
	if Input.keyCatcher() ~= 0 then
		cmd.forwardmove, cmd.rightmove, cmd.upmove = 0, 0, 0
	end
	Input.cmds[bit32.band(Input.cmdNumber, CMD_MASK)] = cmd
	return cmd
end

function Input.GetCurrentCmdNumber(): number
	return Input.cmdNumber
end

function Input.GetUserCmd(n: number, out): boolean
	-- cmds[cmdNumber] is the one just created; it's valid
	if n > Input.cmdNumber then
		error("GetUserCmd: " .. n .. " >= " .. Input.cmdNumber)
	end
	if n <= Input.cmdNumber - CMD_BACKUP then
		return false
	end
	T.assign(out, Input.cmds[bit32.band(n, CMD_MASK)])
	return true
end

function Input.SetUserCmdValue(weapon: number, sensitivityScale: number)
	Input.cgameUserCmdValue = weapon
	Input.cgameSensitivity = sensitivityScale
end

-- Mouse motion in pixels since the last frame (accumulated by the client).
function Input.MouseDelta(dx: number, dy: number)
	Input.mouseDx += dx
	Input.mouseDy += dy
end

Input._angleMod = angleMod
return Input
