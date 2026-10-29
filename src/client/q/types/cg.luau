-- Zero-initialising constructors for the structs of cg_local.h and ui_local.h (non-MISSIONPACK).
local S = require(script.Parent.shared)
local consts = script.Parent.Parent.consts
local ConstsShared = require(consts.shared)
local ConstsCg = require(consts.cg)

local K = {}
for _, name in ipairs({
	"MAX_TOTALANIMATIONS",
	"MAX_CUSTOM_SOUNDS",
	"MAX_ITEM_MODELS",
	"MAX_CLIENTS",
	"WP_NUM_WEAPONS",
	"CMD_BACKUP",
	"MAX_DOMINATION_POINTS",
	"MAX_MODELS",
	"MAX_SOUNDS",
	"MAX_ANIMATIONS",
}) do
	local v = ConstsShared[name]
	if v == nil then
		v = ConstsCg[name]
	end
	assert(v ~= nil, "missing constant " .. name)
	K[name] = v
end

local MAX_MENUITEMS = 64
local MAX_MENUDEPTH = 8
local MAX_EDIT_LINE = 256
local MAX_SKULLTRAIL = 10
local MAX_REWARDSTACK = 10
local MAX_SOUNDBUFFER = 20
local MAX_PREDICTED_EVENTS = 16
local MAX_VERTS_ON_POLY = 10
local FOOTSTEP_TOTAL = 7
local NUM_CROSSHAIRS = 99
local TEAMCHAT_HEIGHT = 8

local function fill(n, f)
	local a = {}
	for i = 0, n - 1 do
		a[i] = f(i)
	end
	return a
end

local function zero()
	return 0
end

local function empty()
	return ""
end

local function nums(n)
	return fill(n, zero)
end

local function vec3()
	return { [0] = 0, [1] = 0, [2] = 0 }
end

local function vec4()
	return { [0] = 0, [1] = 0, [2] = 0, [3] = 0 }
end

local function animation_t()
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

local function trajectory_t()
	return { trType = 0, trTime = 0, trDuration = 0, trBase = vec3(), trDelta = vec3() }
end

local function polyVert_t()
	return { xyz = vec3(), st = { [0] = 0, [1] = 0 }, modulate = { [0] = 0, [1] = 0, [2] = 0, [3] = 0 } }
end

local T = {}

function T.lerpFrame_t()
	return {
		oldFrame = 0,
		oldFrameTime = 0,
		frame = 0,
		frameTime = 0,
		backlerp = 0,
		yawAngle = 0,
		yawing = false,
		pitchAngle = 0,
		pitching = false,
		animationNumber = 0,
		animation = nil,
		animationTime = 0,
	}
end

T.ui_lerpFrame_t = T.lerpFrame_t

function T.playerEntity_t()
	return {
		legs = T.lerpFrame_t(),
		torso = T.lerpFrame_t(),
		flag = T.lerpFrame_t(),
		painTime = 0,
		painDirection = 0,
		lightningFiring = false,
		railgunImpact = vec3(),
		railgunFlash = false,
		barrelAngle = 0,
		barrelTime = 0,
		barrelSpinning = false,
	}
end

function T.centity_t()
	return {
		currentState = S.entityState_t(),
		nextState = S.entityState_t(),
		interpolate = false,
		currentValid = false,
		muzzleFlashTime = 0,
		previousEvent = 0,
		teleportFlag = 0,
		trailTime = 0,
		dustTrailTime = 0,
		miscTime = 0,
		snapShotTime = 0,
		pe = T.playerEntity_t(),
		errorTime = 0,
		errorOrigin = vec3(),
		errorAngles = vec3(),
		extrapolated = false,
		rawOrigin = vec3(),
		rawAngles = vec3(),
		beamEnd = vec3(),
		lerpOrigin = vec3(),
		lerpAngles = vec3(),
	}
end

function T.markPoly_t()
	return {
		prevMark = nil,
		nextMark = nil,
		time = 0,
		markShader = 0,
		alphaFade = false,
		color = vec4(),
		poly = { hShader = 0, numVerts = 0, verts = nil },
		verts = fill(MAX_VERTS_ON_POLY, polyVert_t),
	}
end

function T.localEntity_t()
	return {
		prev = nil,
		next = nil,
		leType = 0,
		leFlags = 0,
		startTime = 0,
		endTime = 0,
		fadeInTime = 0,
		lifeRate = 0,
		pos = trajectory_t(),
		angles = trajectory_t(),
		bounceFactor = 0,
		color = vec4(),
		radius = 0,
		light = 0,
		lightColor = vec3(),
		leMarkType = 0,
		leBounceSoundType = 0,
		refEntity = S.refEntity_t(),
	}
end

function T.score_t()
	return {
		client = 0,
		score = 0,
		ping = 0,
		time = 0,
		scoreFlags = 0,
		powerUps = 0,
		accuracy = 0,
		impressiveCount = 0,
		excellentCount = 0,
		guantletCount = 0,
		defendCount = 0,
		assistCount = 0,
		captures = 0,
		perfect = false,
		team = 0,
		isDead = 0,
	}
end

function T.clientInfo_t()
	return {
		infoValid = false,
		name = "",
		team = 0,
		botSkill = 0,
		color1 = vec3(),
		color2 = vec3(),
		score = 0,
		location = 0,
		health = 0,
		armor = 0,
		curWeapon = 0,
		handicap = 0,
		wins = 0,
		losses = 0,
		teamTask = 0,
		teamLeader = false,
		powerups = 0,
		medkitUsageTime = 0,
		invulnerabilityStartTime = 0,
		invulnerabilityStopTime = 0,
		breathPuffTime = 0,
		modelName = "",
		skinName = "",
		headModelName = "",
		headSkinName = "",
		redTeam = "",
		blueTeam = "",
		deferred = false,
		newAnims = false,
		fixedlegs = false,
		fixedtorso = false,
		headOffset = vec3(),
		footsteps = 0,
		gender = 0,
		legsModel = 0,
		legsSkin = 0,
		torsoModel = 0,
		torsoSkin = 0,
		headModel = 0,
		headSkin = 0,
		modelIcon = 0,
		animations = fill(K.MAX_TOTALANIMATIONS, animation_t),
		sounds = nums(K.MAX_CUSTOM_SOUNDS),
		isDead = 0,
	}
end

function T.weaponInfo_t()
	return {
		registered = false,
		item = nil,
		handsModel = 0,
		weaponModel = 0,
		barrelModel = 0,
		flashModel = 0,
		weaponMidpoint = vec3(),
		flashDlight = 0,
		flashDlightColor = vec3(),
		flashSound = nums(4),
		weaponIcon = 0,
		ammoIcon = 0,
		ammoModel = 0,
		missileModel = 0,
		missileSound = 0,
		missileTrailFunc = nil,
		missileDlight = 0,
		missileDlightColor = vec3(),
		missileRenderfx = 0,
		ejectBrassFunc = nil,
		trailRadius = 0,
		wiTrailTime = 0,
		readySound = 0,
		firingSound = 0,
		loopFireSound = false,
	}
end

function T.itemInfo_t()
	return { registered = false, models = nums(K.MAX_ITEM_MODELS), icon = 0 }
end

function T.powerupInfo_t()
	return { itemNum = 0 }
end

function T.skulltrail_t()
	return { positions = fill(MAX_SKULLTRAIL, vec3), numpositions = 0 }
end

function T.cg_t()
	return {
		clientFrame = 0,
		clientNum = 0,
		demoPlayback = false,
		levelShot = false,
		deferredPlayerLoading = 0,
		loading = false,
		intermissionStarted = false,
		latestSnapshotNum = 0,
		latestSnapshotTime = 0,
		snap = nil,
		nextSnap = nil,
		activeSnapshots = fill(2, S.snapshot_t),
		frameInterpolation = 0,
		thisFrameTeleport = false,
		nextFrameTeleport = false,
		frametime = 0,
		time = 0,
		oldTime = 0,
		physicsTime = 0,
		timelimitWarnings = 0,
		fraglimitWarnings = 0,
		mapRestart = false,
		renderingThirdPerson = false,
		hyperspace = false,
		predictedPlayerState = S.playerState_t(),
		predictedPlayerEntity = T.centity_t(),
		validPPS = false,
		predictedErrorTime = 0,
		predictedError = vec3(),
		eventSequence = 0,
		predictableEvents = nums(MAX_PREDICTED_EVENTS),
		stepChange = 0,
		stepTime = 0,
		duckChange = 0,
		duckTime = 0,
		landChange = 0,
		landTime = 0,
		weaponSelect = 0,
		autoAngles = vec3(),
		autoAxis = fill(3, vec3),
		autoAnglesFast = vec3(),
		autoAxisFast = fill(3, vec3),
		refdef = S.refdef_t(),
		refdefViewAngles = vec3(),
		zoomed = false,
		zoomTime = 0,
		zoomSensitivity = 0,
		infoScreenText = "",
		scoresRequestTime = 0,
		numScores = 0,
		selectedScore = 0,
		teamScores = nums(2),
		scores = fill(K.MAX_CLIENTS, T.score_t),
		showScores = false,
		scoreBoardShowing = false,
		scoreFadeTime = 0,
		accuracys = fill(K.WP_NUM_WEAPONS, function()
			return nums(2)
		end),
		accRequestTime = 0,
		showAcc = false,
		accBoardShowing = false,
		accFadeTime = 0,
		killerName = "",
		spectatorList = "",
		spectatorLen = 0,
		spectatorWidth = 0,
		spectatorTime = 0,
		spectatorPaintX = 0,
		spectatorPaintX2 = 0,
		spectatorOffset = 0,
		spectatorPaintLen = 0,
		skulltrails = fill(K.MAX_CLIENTS, T.skulltrail_t),
		centerPrintTime = 0,
		centerPrintCharWidth = 0,
		centerPrintY = 0,
		centerPrint = "",
		centerPrintLines = 0,
		lowAmmoWarning = 0,
		lastKillTime = 0,
		crosshairClientNum = 0,
		crosshairClientTime = 0,
		powerupActive = 0,
		powerupTime = 0,
		attackerTime = 0,
		voiceTime = 0,
		rewardStack = 0,
		rewardTime = 0,
		rewardCount = nums(MAX_REWARDSTACK),
		rewardShader = nums(MAX_REWARDSTACK),
		rewardSound = nums(MAX_REWARDSTACK),
		soundBufferIn = 0,
		soundBufferOut = 0,
		soundTime = 0,
		soundBuffer = nums(MAX_SOUNDBUFFER),
		voiceChatTime = 0,
		voiceChatBufferIn = 0,
		voiceChatBufferOut = 0,
		warmup = 0,
		warmupCount = 0,
		itemPickup = 0,
		itemPickupTime = 0,
		itemPickupBlendTime = 0,
		weaponSelectTime = 0,
		weaponAnimation = 0,
		weaponAnimationTime = 0,
		damageTime = 0,
		damageX = 0,
		damageY = 0,
		damageValue = 0,
		headYaw = 0,
		headEndPitch = 0,
		headEndYaw = 0,
		headEndTime = 0,
		headStartPitch = 0,
		headStartYaw = 0,
		headStartTime = 0,
		v_dmg_time = 0,
		v_dmg_pitch = 0,
		v_dmg_roll = 0,
		kick_angles = vec3(),
		kick_origin = vec3(),
		bobfracsin = 0,
		bobcycle = 0,
		xyspeed = 0,
		nextOrbitTime = 0,
		testModelEntity = S.refEntity_t(),
		testModelName = "",
		testGun = false,
		lastPredictedCommand = 0,
		lastServerTime = 0,
		savedPmoveStates = fill(K.CMD_BACKUP + 2, S.playerState_t),
		stateHead = 0,
		stateTail = 0,
		respawnTime = 0,
		redObeliskHealth = 0,
		blueObeliskHealth = 0,
	}
end

local mediaHandles = {
	"charsetShader", "charsetProp", "charsetPropGlow", "charsetPropB", "whiteShader",
	"redCubeModel", "blueCubeModel", "redCubeIcon", "blueCubeIcon", "redFlagModel",
	"blueFlagModel", "neutralFlagModel", "flagPoleModel", "flagFlapModel",
	"redFlagFlapSkin", "blueFlagFlapSkin", "neutralFlagFlapSkin",
	"redFlagBaseModel", "blueFlagBaseModel", "neutralFlagBaseModel",
	"overloadBaseModel", "overloadTargetModel", "overloadLightsModel", "overloadEnergyModel",
	"harvesterModel", "harvesterRedSkin", "harvesterBlueSkin", "harvesterNeutralModel",
	"armorModel", "armorIcon", "teamStatusBar", "deferShader",
	"gibAbdomen", "gibArm", "gibChest", "gibFist", "gibFoot", "gibForearm", "gibIntestine",
	"gibLeg", "gibSkull", "gibBrain", "smoke2", "machinegunBrassModel", "shotgunBrassModel",
	"railRingsShader", "railCoreShader", "lightningShader", "friendShader", "balloonShader",
	"connectionShader", "selectShader", "viewBloodShader", "tracerShader", "lagometerShader",
	"backTileShader", "noammoShader", "smokePuffShader", "smokePuffRageProShader",
	"shotgunSmokePuffShader", "plasmaBallShader", "waterBubbleShader", "bloodTrailShader",
	"lsmkShader1", "lsmkShader2", "lsmkShader3", "lsmkShader4", "lbumShader1", "lfblShader1",
	"lsplShader", "lspkShader1", "lspkShader2", "lbldShader1", "lbldShader2", "grappleShader",
	"lmarkmetal1", "lmarkmetal2", "lmarkmetal3", "lmarkmetal4",
	"lmarkbullet1", "lmarkbullet2", "lmarkbullet3", "lmarkbullet4",
	"nailPuffShader", "blueProxMine", "shadowMarkShader",
	"wakeMarkShader", "bloodMarkShader", "bulletMarkShader", "burnMarkShader", "holeMarkShader",
	"energyMarkShader",
	"quadShader", "redQuadShader", "quadWeaponShader", "invisShader", "regenShader",
	"battleSuitShader", "battleWeaponShader", "hastePuffShader", "redKamikazeShader",
	"blueKamikazeShader", "neutralOverlay", "redOverlay", "blueOverlay",
	"bulletFlashModel", "ringFlashModel", "dishFlashModel", "lightningExplosionModel",
	"railExplosionShader", "plasmaExplosionShader", "bulletExplosionShader",
	"rocketExplosionShader", "grenadeExplosionShader", "bfgExplosionShader",
	"bloodExplosionShader",
	"teleportEffectModel", "teleportEffectShader", "kamikazeEffectModel", "kamikazeShockWave",
	"kamikazeHeadModel", "kamikazeHeadTrail", "guardPowerupModel", "scoutPowerupModel",
	"doublerPowerupModel", "ammoRegenPowerupModel", "invulnerabilityImpactModel",
	"invulnerabilityJuicedModel", "medkitUsageModel", "dustPuffShader", "heartShader",
	"invulnerabilityPowerupModel",
	"scoreboardName", "scoreboardPing", "scoreboardScore", "scoreboardTime",
	"medalImpressive", "medalExcellent", "medalGauntlet", "medalDefend", "medalAssist",
	"medalCapture",
	"quadSound", "tracerSound", "selectSound", "useNothingSound", "wearOffSound",
	"sfx_lghit1", "sfx_lghit2", "sfx_lghit3", "sfx_ric1", "sfx_ric2", "sfx_ric3", "sfx_railg",
	"sfx_rockexp", "sfx_plasmaexp", "sfx_proxexp", "sfx_nghit", "sfx_nghitflesh",
	"sfx_nghitmetal", "sfx_chghit", "sfx_chghitflesh", "sfx_chghitmetal",
	"kamikazeExplodeSound", "kamikazeImplodeSound", "kamikazeFarSound", "useInvulnerabilitySound",
	"invulnerabilityImpactSound1", "invulnerabilityImpactSound2", "invulnerabilityImpactSound3",
	"invulnerabilityJuicedSound", "obeliskHitSound1", "obeliskHitSound2", "obeliskHitSound3",
	"obeliskRespawnSound", "winnerSound", "loserSound", "youSuckSound", "gibSound",
	"gibBounce1Sound", "gibBounce2Sound", "gibBounce3Sound", "teleInSound", "teleOutSound",
	"noAmmoSound", "respawnSound", "talkSound", "landSound", "fallSound", "jumpPadSound",
	"lspl1Sound", "lspl2Sound", "lspl3Sound", "lbul1Sound", "lbul2Sound", "lbul3Sound",
	"lshl1Sound", "lshl2Sound", "lshl3Sound",
	"oneMinuteSound", "fiveMinuteSound", "suddenDeathSound",
	"threeFragSound", "twoFragSound", "oneFragSound",
	"hitSound", "hitSoundHighArmor", "hitSoundLowArmor", "hitTeamSound", "impressiveSound",
	"excellentSound", "deniedSound", "humiliationSound", "assistSound", "defendSound",
	"firstImpressiveSound", "firstExcellentSound", "firstHumiliationSound",
	"takenLeadSound", "tiedLeadSound", "lostLeadSound",
	"voteNow", "votePassed", "voteFailed",
	"watrInSound", "watrOutSound", "watrUnSound", "flightSound", "medkitSound",
	"weaponHoverSound",
	"captureAwardSound", "redScoredSound", "blueScoredSound", "redLeadsSound",
	"blueLeadsSound", "teamsTiedSound",
	"captureYourTeamSound", "captureOpponentSound", "returnYourTeamSound",
	"returnOpponentSound", "takenYourTeamSound", "takenOpponentSound",
	"redFlagReturnedSound", "blueFlagReturnedSound", "neutralFlagReturnedSound",
	"enemyTookYourFlagSound", "enemyTookTheFlagSound", "yourTeamTookEnemyFlagSound",
	"yourTeamTookTheFlagSound", "youHaveFlagSound", "yourBaseIsUnderAttackSound",
	"holyShitSound",
	"count3Sound", "count2Sound", "count1Sound", "countFightSound", "countPrepareSound",
	"ammoregenSound", "doublerSound", "guardSound", "scoutSound",
	"cursor", "selectCursor", "sizeCursor",
	"regenSound", "protectSound", "n_healthSound", "hgrenb1aSound", "hgrenb2aSound",
	"wstbimplSound", "wstbimpmSound", "wstbimpdSound", "wstbactvSound",
}

function T.cgMedia_t()
	local m = {
		redFlagShader = nums(3),
		blueFlagShader = nums(3),
		flagShader = nums(4),
		ddPointSkinA = nums(4),
		ddPointSkinB = nums(4),
		crosshairShader = nums(NUM_CROSSHAIRS),
		numberShaders = nums(11),
		botSkillShaders = nums(5),
		footsteps = fill(FOOTSTEP_TOTAL, function()
			return nums(4)
		end),
	}
	for _, name in ipairs(mediaHandles) do
		m[name] = 0
	end
	return m
end

function T.cgs_t()
	local domCount = K.MAX_DOMINATION_POINTS
	return {
		gameState = S.gameState_t(),
		glconfig = S.glconfig_t(),
		screenXScale = 0,
		screenYScale = 0,
		screenXBias = 0,
		serverCommandSequence = 0,
		processedSnapshotNum = 0,
		localServer = false,
		gametype = 0,
		dmflags = 0,
		videoflags = 0,
		elimflags = 0,
		teamflags = 0,
		fraglimit = 0,
		capturelimit = 0,
		timelimit = 0,
		maxclients = 0,
		mapname = "",
		redTeam = "",
		blueTeam = "",
		voteTime = 0,
		voteYes = 0,
		voteNo = 0,
		voteModified = false,
		voteString = "",
		teamVoteTime = nums(2),
		teamVoteYes = nums(2),
		teamVoteNo = nums(2),
		teamVoteModified = fill(2, function()
			return false
		end),
		teamVoteString = fill(2, empty),
		levelStartTime = 0,
		ffa_gt = 0,
		roundStartTime = 0,
		roundtime = 0,
		attackingTeam = 0,
		lms_mode = 0,
		nopickup = 0,
		timetaken = 0,
		domination_points_count = 0,
		domination_points_names = fill(domCount, empty),
		domination_points_status = nums(domCount),
		scores1 = 0,
		scores2 = 0,
		redflag = 0,
		blueflag = 0,
		flagStatus = 0,
		newHud = false,
		gameModels = nums(K.MAX_MODELS),
		gameSounds = nums(K.MAX_SOUNDS),
		numInlineModels = 0,
		inlineDrawModel = nums(K.MAX_MODELS),
		inlineModelMidpoints = fill(K.MAX_MODELS, vec3),
		clientinfo = fill(K.MAX_CLIENTS, T.clientInfo_t),
		teamChatMsgs = fill(TEAMCHAT_HEIGHT, empty),
		teamChatMsgTimes = nums(TEAMCHAT_HEIGHT),
		teamChatPos = 0,
		teamLastChatPos = 0,
		cursorX = 0,
		cursorY = 0,
		eventHandling = false,
		mouseCaptured = false,
		sizingHud = false,
		capturedItem = nil,
		activeCursor = 0,
		currentOrder = 0,
		orderPending = false,
		orderTime = 0,
		currentVoiceClient = 0,
		acceptOrderTime = 0,
		acceptTask = 0,
		acceptLeader = 0,
		acceptVoice = "",
		media = T.cgMedia_t(),
		delagHitscan = 0,
		altExcellent = 0,
	}
end

function T.menuframework_s()
	return {
		cursor = 0,
		cursor_prev = 0,
		nitems = 0,
		items = fill(MAX_MENUITEMS, function()
			return nil
		end),
		draw = nil,
		key = nil,
		wrapAround = false,
		fullscreen = false,
		showlogo = false,
	}
end

function T.menucommon_s()
	return {
		type = 0,
		name = nil,
		id = 0,
		x = 0,
		y = 0,
		left = 0,
		top = 0,
		right = 0,
		bottom = 0,
		parent = nil,
		menuPosition = 0,
		flags = 0,
		callback = nil,
		statusbar = nil,
		ownerdraw = nil,
	}
end

function T.mfield_t()
	return { cursor = 0, scroll = 0, widthInChars = 0, buffer = "", maxchars = 0 }
end

function T.menufield_s()
	return { generic = T.menucommon_s(), field = T.mfield_t() }
end

function T.menuslider_s()
	return { generic = T.menucommon_s(), minvalue = 0, maxvalue = 0, curvalue = 0, range = 0 }
end

function T.menulist_s()
	return {
		generic = T.menucommon_s(),
		oldvalue = 0,
		curvalue = 0,
		numitems = 0,
		top = 0,
		itemnames = nil,
		width = 0,
		height = 0,
		columns = 0,
		seperation = 0,
	}
end

function T.menuaction_s()
	return { generic = T.menucommon_s() }
end

function T.menuradiobutton_s()
	return { generic = T.menucommon_s(), curvalue = 0 }
end

function T.menubitmap_s()
	return {
		generic = T.menucommon_s(),
		focuspic = nil,
		errorpic = nil,
		shader = 0,
		focusshader = 0,
		width = 0,
		height = 0,
		focuscolor = nil,
	}
end

function T.menutext_s()
	return { generic = T.menucommon_s(), string = nil, style = 0, color = nil }
end

function T.playerInfo_t()
	return {
		legsModel = 0,
		legsSkin = 0,
		legs = T.lerpFrame_t(),
		torsoModel = 0,
		torsoSkin = 0,
		torso = T.lerpFrame_t(),
		headModel = 0,
		headSkin = 0,
		animations = fill(K.MAX_ANIMATIONS, animation_t),
		weaponModel = 0,
		barrelModel = 0,
		flashModel = 0,
		flashDlightColor = vec3(),
		muzzleFlashTime = 0,
		viewAngles = vec3(),
		moveAngles = vec3(),
		currentWeapon = 0,
		legsAnim = 0,
		torsoAnim = 0,
		weapon = 0,
		lastWeapon = 0,
		pendingWeapon = 0,
		weaponTimer = 0,
		pendingLegsAnim = 0,
		torsoAnimationTimer = 0,
		pendingTorsoAnim = 0,
		legsAnimationTimer = 0,
		chat = false,
		newModel = false,
		barrelSpinning = false,
		barrelAngle = 0,
		barrelTime = 0,
		realWeapon = 0,
	}
end

function T.uiStatic_t()
	return {
		frametime = 0,
		realtime = 0,
		cursorx = 0,
		cursory = 0,
		menusp = 0,
		activemenu = nil,
		stack = fill(MAX_MENUDEPTH, function()
			return nil
		end),
		glconfig = S.glconfig_t(),
		debug = false,
		whiteShader = 0,
		menuBackShader = 0,
		menuBackNoLogoShader = 0,
		charset = 0,
		charsetProp = 0,
		charsetPropGlow = 0,
		charsetPropB = 0,
		cursor = 0,
		rb_on = 0,
		rb_off = 0,
		xscale = 0,
		yscale = 0,
		bias = 0,
		demoversion = false,
		firstdraw = false,
	}
end

T.MAX_EDIT_LINE = MAX_EDIT_LINE

return T
