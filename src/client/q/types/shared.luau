-- Struct constructors for q_shared.h, tr_types.h, cg_public.h, bg_public.h.

local MAX_CONFIGSTRINGS = 1024
local MAX_MAP_AREA_BYTES = 32
local MAX_STATS = 16
local MAX_PERSISTANT = 16
local MAX_POWERUPS = 16
local MAX_WEAPONS = 16
local MAX_PS_EVENTS = 2
local MAXTOUCH = 32
local MAX_ENTITIES_IN_SNAPSHOT = 256
local MAX_RENDER_STRINGS = 8
local MAX_ITEM_MODELS = 4
local GLYPHS_PER_FONT = 256

local T = {}

local function vec(n: number): { [number]: number }
	local v = {}
	for i = 0, n - 1 do
		v[i] = 0
	end
	return v
end

local function zeros(n: number): { [number]: number }
	return vec(n)
end

local function strings(n: number): { [number]: string }
	local v = {}
	for i = 0, n - 1 do
		v[i] = ""
	end
	return v
end

local function array(n: number, ctor: () -> any): { [number]: any }
	local v = {}
	for i = 0, n - 1 do
		v[i] = ctor()
	end
	return v
end

local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = copy(x)
	end
	return out
end

function T.copy(v: any): any
	return copy(v)
end

function T.assign(dst: any, src: any): any
	for k, v in pairs(src) do
		dst[k] = copy(v)
	end
	return dst
end

function T.reset(obj: any, ctor: () -> any): any
	for k in pairs(obj) do
		obj[k] = nil
	end
	return T.assign(obj, ctor())
end

function T.vmCvar_t()
	return { handle = 0, modificationCount = 0, value = 0, integer = 0, string = "" }
end

function T.cplane_t()
	return { normal = vec(3), dist = 0, type = 0, signbits = 0, pad = zeros(2) }
end

function T.trace_t()
	return {
		allsolid = false,
		startsolid = false,
		fraction = 0,
		endpos = vec(3),
		plane = T.cplane_t(),
		surfaceFlags = 0,
		contents = 0,
		entityNum = 0,
	}
end

function T.markFragment_t()
	return { firstPoint = 0, numPoints = 0 }
end

function T.orientation_t()
	return { origin = vec(3), axis = array(3, function()
		return vec(3)
	end) }
end

function T.gameState_t()
	return { configstrings = strings(MAX_CONFIGSTRINGS) }
end

function T.playerState_t()
	return {
		commandTime = 0,
		pm_type = 0,
		bobCycle = 0,
		pm_flags = 0,
		pm_time = 0,
		origin = vec(3),
		velocity = vec(3),
		weaponTime = 0,
		gravity = 0,
		speed = 0,
		delta_angles = zeros(3),
		groundEntityNum = 0,
		legsTimer = 0,
		legsAnim = 0,
		torsoTimer = 0,
		torsoAnim = 0,
		movementDir = 0,
		grapplePoint = vec(3),
		eFlags = 0,
		eventSequence = 0,
		events = zeros(MAX_PS_EVENTS),
		eventParms = zeros(MAX_PS_EVENTS),
		externalEvent = 0,
		externalEventParm = 0,
		externalEventTime = 0,
		clientNum = 0,
		weapon = 0,
		weaponstate = 0,
		viewangles = vec(3),
		viewheight = 0,
		damageEvent = 0,
		damageYaw = 0,
		damagePitch = 0,
		damageCount = 0,
		stats = zeros(MAX_STATS),
		persistant = zeros(MAX_PERSISTANT),
		powerups = zeros(MAX_POWERUPS),
		ammo = zeros(MAX_WEAPONS),
		generic1 = 0,
		loopSound = 0,
		jumppad_ent = 0,
		ping = 0,
		pmove_framecount = 0,
		jumppad_frame = 0,
		entityEventSequence = 0,
	}
end

function T.usercmd_t()
	return {
		serverTime = 0,
		angles = zeros(3),
		buttons = 0,
		weapon = 0,
		forwardmove = 0,
		rightmove = 0,
		upmove = 0,
	}
end

function T.trajectory_t()
	return { trType = 0, trTime = 0, trDuration = 0, trBase = vec(3), trDelta = vec(3) }
end

function T.entityState_t()
	return {
		number = 0,
		eType = 0,
		eFlags = 0,
		pos = T.trajectory_t(),
		apos = T.trajectory_t(),
		time = 0,
		time2 = 0,
		origin = vec(3),
		origin2 = vec(3),
		angles = vec(3),
		angles2 = vec(3),
		otherEntityNum = 0,
		otherEntityNum2 = 0,
		groundEntityNum = 0,
		constantLight = 0,
		loopSound = 0,
		modelindex = 0,
		modelindex2 = 0,
		clientNum = 0,
		frame = 0,
		solid = 0,
		event = 0,
		eventParm = 0,
		powerups = 0,
		weapon = 0,
		legsAnim = 0,
		torsoAnim = 0,
		generic1 = 0,
	}
end

function T.glyphInfo_t()
	return {
		height = 0,
		top = 0,
		bottom = 0,
		pitch = 0,
		xSkip = 0,
		imageWidth = 0,
		imageHeight = 0,
		s = 0,
		t = 0,
		s2 = 0,
		t2 = 0,
		glyph = 0,
		shaderName = "",
	}
end

function T.fontInfo_t()
	return { glyphs = array(GLYPHS_PER_FONT, T.glyphInfo_t), glyphScale = 0, name = "" }
end

function T.qtime_t()
	return {
		tm_sec = 0,
		tm_min = 0,
		tm_hour = 0,
		tm_mday = 0,
		tm_mon = 0,
		tm_year = 0,
		tm_wday = 0,
		tm_yday = 0,
		tm_isdst = 0,
	}
end

function T.pc_token_t()
	return { type = 0, subtype = 0, intvalue = 0, floatvalue = 0, string = "" }
end

function T.polyVert_t()
	return { xyz = vec(3), st = zeros(2), modulate = zeros(4) }
end

function T.poly_t()
	return { hShader = 0, numVerts = 0, verts = nil }
end

function T.refEntity_t()
	return {
		reType = 0,
		renderfx = 0,
		hModel = 0,
		lightingOrigin = vec(3),
		shadowPlane = 0,
		axis = array(3, function()
			return vec(3)
		end),
		nonNormalizedAxes = false,
		origin = vec(3),
		frame = 0,
		oldorigin = vec(3),
		oldframe = 0,
		backlerp = 0,
		skinNum = 0,
		customSkin = 0,
		customShader = 0,
		shaderRGBA = zeros(4),
		shaderTexCoord = zeros(2),
		shaderTime = 0,
		radius = 0,
		rotation = 0,
	}
end

function T.refdef_t()
	return {
		x = 0,
		y = 0,
		width = 0,
		height = 0,
		fov_x = 0,
		fov_y = 0,
		vieworg = vec(3),
		viewaxis = array(3, function()
			return vec(3)
		end),
		time = 0,
		rdflags = 0,
		areamask = zeros(MAX_MAP_AREA_BYTES),
		text = strings(MAX_RENDER_STRINGS),
	}
end

function T.glconfig_t()
	return {
		renderer_string = "",
		vendor_string = "",
		version_string = "",
		extensions_string = "",
		maxTextureSize = 0,
		numTextureUnits = 0,
		colorBits = 0,
		depthBits = 0,
		stencilBits = 0,
		driverType = 0,
		hardwareType = 0,
		deviceSupportsGamma = false,
		textureCompression = 0,
		textureEnvAddAvailable = false,
		vidWidth = 0,
		vidHeight = 0,
		windowAspect = 0,
		displayFrequency = 0,
		isFullscreen = false,
		stereoEnabled = false,
		smpActive = false,
	}
end

function T.snapshot_t()
	return {
		snapFlags = 0,
		ping = 0,
		serverTime = 0,
		areamask = zeros(MAX_MAP_AREA_BYTES),
		ps = T.playerState_t(),
		numEntities = 0,
		entities = array(MAX_ENTITIES_IN_SNAPSHOT, T.entityState_t),
		numServerCommands = 0,
		serverCommandSequence = 0,
	}
end

function T.pmove_t()
	return {
		ps = nil,
		cmd = T.usercmd_t(),
		tracemask = 0,
		debugLevel = 0,
		noFootsteps = false,
		gauntletHit = false,
		framecount = 0,
		numtouch = 0,
		touchents = zeros(MAXTOUCH),
		mins = vec(3),
		maxs = vec(3),
		watertype = 0,
		waterlevel = 0,
		xyspeed = 0,
		pmove_fixed = 0,
		pmove_msec = 0,
		pmove_float = 0,
		pmove_flags = 0,
		trace = nil,
		pointcontents = nil,
	}
end

function T.animation_t()
	return {
		firstFrame = 0,
		numFrames = 0,
		loopFrames = 0,
		frameLerp = 0,
		initialLerp = 0,
		reversed = false,
		flipflop = false,
	}
end

function T.gitem_t()
	return {
		classname = nil,
		pickup_sound = nil,
		world_model = {},
		icon = nil,
		pickup_name = nil,
		quantity = 0,
		giType = 0,
		giTag = 0,
		precaches = nil,
		sounds = nil,
	}
end

return T
