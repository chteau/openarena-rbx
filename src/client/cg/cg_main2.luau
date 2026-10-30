--[[
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of Quake III Arena source code.

Quake III Arena source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

Quake III Arena source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Foobar; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
]]
-- Luau port of code/cgame/cg_main.c (OpenArena 0.8.8, gamecode 9e0f0c0).
-- This part covers C lines 992-2348 of the 0.8.8 source.

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local trap = require(script.Parent.Parent.sys.Trap)
local BG = require(script.Parent.Parent.adapters.BG)

local sb_nums = {
	[0] = "gfx/2d/numbers/zero_32b",
	"gfx/2d/numbers/one_32b",
	"gfx/2d/numbers/two_32b",
	"gfx/2d/numbers/three_32b",
	"gfx/2d/numbers/four_32b",
	"gfx/2d/numbers/five_32b",
	"gfx/2d/numbers/six_32b",
	"gfx/2d/numbers/seven_32b",
	"gfx/2d/numbers/eight_32b",
	"gfx/2d/numbers/nine_32b",
	"gfx/2d/numbers/minus_32b",
}

local function atoi(s: string): number
	local n = tonumber(s)
	if n == nil then
		return 0
	end
	return Q.int(n)
end

function G.CG_RegisterGraphics()
	local cg = G.cg
	local cgs = G.cgs

	-- clear any references to old media
	T.reset(cg.refdef, T.refdef_t)
	trap.R_ClearScene()

	G.CG_LoadingString(cgs.mapname)

	trap.R_LoadWorldMap(cgs.mapname)

	-- precache status bar pics
	G.CG_LoadingString("game media")

	for i = 0, 10 do
		cgs.media.numberShaders[i] = trap.R_RegisterShader(sb_nums[i])
	end

	cgs.media.botSkillShaders[0] = trap.R_RegisterShader("menu/art/skill1.tga")
	cgs.media.botSkillShaders[1] = trap.R_RegisterShader("menu/art/skill2.tga")
	cgs.media.botSkillShaders[2] = trap.R_RegisterShader("menu/art/skill3.tga")
	cgs.media.botSkillShaders[3] = trap.R_RegisterShader("menu/art/skill4.tga")
	cgs.media.botSkillShaders[4] = trap.R_RegisterShader("menu/art/skill5.tga")

	cgs.media.viewBloodShader = trap.R_RegisterShader("viewBloodBlend")

	cgs.media.deferShader = trap.R_RegisterShaderNoMip("gfx/2d/defer.tga")

	cgs.media.scoreboardName = trap.R_RegisterShaderNoMip("menu/tab/name.tga")
	cgs.media.scoreboardPing = trap.R_RegisterShaderNoMip("menu/tab/ping.tga")
	cgs.media.scoreboardScore = trap.R_RegisterShaderNoMip("menu/tab/score.tga")
	cgs.media.scoreboardTime = trap.R_RegisterShaderNoMip("menu/tab/time.tga")

	cgs.media.smokePuffShader = trap.R_RegisterShader("smokePuff")
	cgs.media.smokePuffRageProShader = trap.R_RegisterShader("smokePuffRagePro")
	cgs.media.shotgunSmokePuffShader = trap.R_RegisterShader("shotgunSmokePuff")
	cgs.media.nailPuffShader = trap.R_RegisterShader("nailtrail")
	cgs.media.blueProxMine = trap.R_RegisterModel("models/weaphits/proxmineb.md3")
	cgs.media.plasmaBallShader = trap.R_RegisterShader("sprites/plasma1")
	cgs.media.bloodTrailShader = trap.R_RegisterShader("bloodTrail")
	cgs.media.lagometerShader = trap.R_RegisterShader("lagometer")
	cgs.media.connectionShader = trap.R_RegisterShader("disconnected")

	cgs.media.waterBubbleShader = trap.R_RegisterShader("waterBubble")

	cgs.media.tracerShader = trap.R_RegisterShader("gfx/misc/tracer")
	cgs.media.selectShader = trap.R_RegisterShader("gfx/2d/select")

	for i = 0, C.NUM_CROSSHAIRS - 1 do
		if i < 10 then
			cgs.media.crosshairShader[i] = trap.R_RegisterShader("gfx/2d/crosshair" .. string.char(97 + i))
		else
			cgs.media.crosshairShader[i] = trap.R_RegisterShader(string.format("gfx/2d/crosshair%02d", i - 10))
		end
	end

	cgs.media.backTileShader = trap.R_RegisterShader("gfx/2d/backtile")
	cgs.media.noammoShader = trap.R_RegisterShader("icons/noammo")

	-- powerup shaders
	cgs.media.quadShader = trap.R_RegisterShader("powerups/quad")
	cgs.media.quadWeaponShader = trap.R_RegisterShader("powerups/quadWeapon")
	cgs.media.battleSuitShader = trap.R_RegisterShader("powerups/battleSuit")
	cgs.media.battleWeaponShader = trap.R_RegisterShader("powerups/battleWeapon")
	cgs.media.invisShader = trap.R_RegisterShader("powerups/invisibility")
	cgs.media.regenShader = trap.R_RegisterShader("powerups/regen")
	cgs.media.hastePuffShader = trap.R_RegisterShader("hasteSmokePuff")

	local buildScript = G.cg_buildScript.integer ~= 0
	local gt = cgs.gametype

	if gt == C.GT_CTF or gt == C.GT_CTF_ELIMINATION or gt == C.GT_1FCTF or gt == C.GT_HARVESTER or buildScript then
		cgs.media.redCubeModel = trap.R_RegisterModel("models/powerups/orb/r_orb.md3")
		cgs.media.blueCubeModel = trap.R_RegisterModel("models/powerups/orb/b_orb.md3")
		cgs.media.redCubeIcon = trap.R_RegisterShader("icons/skull_red")
		cgs.media.blueCubeIcon = trap.R_RegisterShader("icons/skull_blue")
	end

	if gt >= C.GT_TEAM and cgs.ffa_gt ~= 1 then
		cgs.media.redOverlay = trap.R_RegisterShader("playeroverlays/playerSuit1_Red")
		cgs.media.blueOverlay = trap.R_RegisterShader("playeroverlays/playerSuit1_Blue")
	else
		cgs.media.neutralOverlay = trap.R_RegisterShader("playeroverlays/playerSuit1_Neutral")
	end

	--For Double Domination:
	if gt == C.GT_DOUBLE_D then
		cgs.media.ddPointSkinA[C.TEAM_RED] = trap.R_RegisterShaderNoMip("icons/icona_red")
		cgs.media.ddPointSkinA[C.TEAM_BLUE] = trap.R_RegisterShaderNoMip("icons/icona_blue")
		cgs.media.ddPointSkinA[C.TEAM_FREE] = trap.R_RegisterShaderNoMip("icons/icona_white")
		cgs.media.ddPointSkinA[C.TEAM_NONE] = trap.R_RegisterShaderNoMip("icons/noammo")

		cgs.media.ddPointSkinB[C.TEAM_RED] = trap.R_RegisterShaderNoMip("icons/iconb_red")
		cgs.media.ddPointSkinB[C.TEAM_BLUE] = trap.R_RegisterShaderNoMip("icons/iconb_blue")
		cgs.media.ddPointSkinB[C.TEAM_FREE] = trap.R_RegisterShaderNoMip("icons/iconb_white")
		cgs.media.ddPointSkinB[C.TEAM_NONE] = trap.R_RegisterShaderNoMip("icons/noammo")
	end

	if gt == C.GT_CTF or gt == C.GT_CTF_ELIMINATION or gt == C.GT_1FCTF or gt == C.GT_HARVESTER or buildScript then
		cgs.media.redFlagModel = trap.R_RegisterModel("models/flags/r_flag.md3")
		cgs.media.blueFlagModel = trap.R_RegisterModel("models/flags/b_flag.md3")
		cgs.media.neutralFlagModel = trap.R_RegisterModel("models/flags/n_flag.md3")
		cgs.media.redFlagShader[0] = trap.R_RegisterShaderNoMip("icons/iconf_red1")
		cgs.media.redFlagShader[1] = trap.R_RegisterShaderNoMip("icons/iconf_red2")
		cgs.media.redFlagShader[2] = trap.R_RegisterShaderNoMip("icons/iconf_red3")
		cgs.media.blueFlagShader[0] = trap.R_RegisterShaderNoMip("icons/iconf_blu1")
		cgs.media.blueFlagShader[1] = trap.R_RegisterShaderNoMip("icons/iconf_blu2")
		cgs.media.blueFlagShader[2] = trap.R_RegisterShaderNoMip("icons/iconf_blu3")
		cgs.media.flagPoleModel = trap.R_RegisterModel("models/flag2/flagpole.md3")
		cgs.media.flagFlapModel = trap.R_RegisterModel("models/flag2/flagflap3.md3")

		cgs.media.redFlagFlapSkin = trap.R_RegisterSkin("models/flag2/red.skin")
		cgs.media.blueFlagFlapSkin = trap.R_RegisterSkin("models/flag2/blue.skin")
		cgs.media.neutralFlagFlapSkin = trap.R_RegisterSkin("models/flag2/white.skin")

		cgs.media.redFlagBaseModel = trap.R_RegisterModel("models/mapobjects/flagbase/red_base.md3")
		cgs.media.blueFlagBaseModel = trap.R_RegisterModel("models/mapobjects/flagbase/blue_base.md3")
		cgs.media.neutralFlagBaseModel = trap.R_RegisterModel("models/mapobjects/flagbase/ntrl_base.md3")
	end

	if gt == C.GT_1FCTF or buildScript then
		cgs.media.neutralFlagModel = trap.R_RegisterModel("models/flags/n_flag.md3")
		cgs.media.flagShader[0] = trap.R_RegisterShaderNoMip("icons/iconf_neutral1")
		cgs.media.flagShader[1] = trap.R_RegisterShaderNoMip("icons/iconf_red2")
		cgs.media.flagShader[2] = trap.R_RegisterShaderNoMip("icons/iconf_blu2")
		cgs.media.flagShader[3] = trap.R_RegisterShaderNoMip("icons/iconf_neutral3")
	end

	if gt == C.GT_OBELISK or buildScript then
		cgs.media.rocketExplosionShader = trap.R_RegisterShader("rocketExplosion")
		cgs.media.overloadBaseModel = trap.R_RegisterModel("models/powerups/overload_base.md3")
		cgs.media.overloadTargetModel = trap.R_RegisterModel("models/powerups/overload_target.md3")
		cgs.media.overloadLightsModel = trap.R_RegisterModel("models/powerups/overload_lights.md3")
		cgs.media.overloadEnergyModel = trap.R_RegisterModel("models/powerups/overload_energy.md3")
	end

	if gt == C.GT_HARVESTER or buildScript then
		cgs.media.harvesterModel = trap.R_RegisterModel("models/powerups/harvester/harvester.md3")
		cgs.media.harvesterRedSkin = trap.R_RegisterSkin("models/powerups/harvester/red.skin")
		cgs.media.harvesterBlueSkin = trap.R_RegisterSkin("models/powerups/harvester/blue.skin")
		cgs.media.harvesterNeutralModel = trap.R_RegisterModel("models/powerups/obelisk/obelisk.md3")
	end

	cgs.media.redKamikazeShader = trap.R_RegisterShader("models/weaphits/kamikred")
	cgs.media.dustPuffShader = trap.R_RegisterShader("hasteSmokePuff")

	if (gt >= C.GT_TEAM and cgs.ffa_gt ~= 1) or buildScript then
		cgs.media.friendShader = trap.R_RegisterShader("sprites/foe")
		cgs.media.redQuadShader = trap.R_RegisterShader("powerups/blueflag")
		cgs.media.blueKamikazeShader = trap.R_RegisterShader("models/weaphits/kamikblu")
	end
	cgs.media.teamStatusBar = trap.R_RegisterShader("gfx/2d/colorbar.tga")

	cgs.media.armorModel = trap.R_RegisterModel("models/powerups/armor/armor_yel.md3")
	cgs.media.armorIcon = trap.R_RegisterShaderNoMip("icons/iconr_yellow")

	cgs.media.machinegunBrassModel = trap.R_RegisterModel("models/weapons2/shells/m_shell.md3")
	cgs.media.shotgunBrassModel = trap.R_RegisterModel("models/weapons2/shells/s_shell.md3")

	cgs.media.gibAbdomen = trap.R_RegisterModel("models/gibs/abdomen.md3")
	cgs.media.gibArm = trap.R_RegisterModel("models/gibs/arm.md3")
	cgs.media.gibChest = trap.R_RegisterModel("models/gibs/chest.md3")
	cgs.media.gibFist = trap.R_RegisterModel("models/gibs/fist.md3")
	cgs.media.gibFoot = trap.R_RegisterModel("models/gibs/foot.md3")
	cgs.media.gibForearm = trap.R_RegisterModel("models/gibs/forearm.md3")
	cgs.media.gibIntestine = trap.R_RegisterModel("models/gibs/intestine.md3")
	cgs.media.gibLeg = trap.R_RegisterModel("models/gibs/leg.md3")
	cgs.media.gibSkull = trap.R_RegisterModel("models/gibs/skull.md3")
	cgs.media.gibBrain = trap.R_RegisterModel("models/gibs/brain.md3")

	cgs.media.smoke2 = trap.R_RegisterModel("models/weapons2/shells/s_shell.md3")

	cgs.media.balloonShader = trap.R_RegisterShader("sprites/balloon3")

	cgs.media.bloodExplosionShader = trap.R_RegisterShader("bloodExplosion")

	cgs.media.bulletFlashModel = trap.R_RegisterModel("models/weaphits/bullet.md3")
	cgs.media.ringFlashModel = trap.R_RegisterModel("models/weaphits/ring02.md3")
	cgs.media.dishFlashModel = trap.R_RegisterModel("models/weaphits/boom01.md3")
	cgs.media.teleportEffectModel = trap.R_RegisterModel("models/misc/telep.md3")
	cgs.media.teleportEffectShader = trap.R_RegisterShader("teleportEffect")
	cgs.media.kamikazeEffectModel = trap.R_RegisterModel("models/weaphits/kamboom2.md3")
	cgs.media.kamikazeShockWave = trap.R_RegisterModel("models/weaphits/kamwave.md3")
	cgs.media.kamikazeHeadModel = trap.R_RegisterModel("models/powerups/kamikazi.md3")
	cgs.media.kamikazeHeadTrail = trap.R_RegisterModel("models/powerups/trailtest.md3")
	cgs.media.guardPowerupModel = trap.R_RegisterModel("models/powerups/guard_player.md3")
	cgs.media.scoutPowerupModel = trap.R_RegisterModel("models/powerups/scout_player.md3")
	cgs.media.doublerPowerupModel = trap.R_RegisterModel("models/powerups/doubler_player.md3")
	cgs.media.ammoRegenPowerupModel = trap.R_RegisterModel("models/powerups/ammo_player.md3")
	cgs.media.invulnerabilityImpactModel = trap.R_RegisterModel("models/powerups/shield/impact.md3")
	cgs.media.invulnerabilityJuicedModel = trap.R_RegisterModel("models/powerups/shield/juicer.md3")
	cgs.media.medkitUsageModel = trap.R_RegisterModel("models/powerups/regen.md3")
	cgs.media.heartShader = trap.R_RegisterShaderNoMip("ui/assets/statusbar/selectedhealth.tga")

	cgs.media.invulnerabilityPowerupModel = trap.R_RegisterModel("models/powerups/shield/shield.md3")
	cgs.media.medalImpressive = trap.R_RegisterShaderNoMip("medal_impressive")
	cgs.media.medalExcellent = trap.R_RegisterShaderNoMip("medal_excellent")
	cgs.media.medalGauntlet = trap.R_RegisterShaderNoMip("medal_gauntlet")
	cgs.media.medalDefend = trap.R_RegisterShaderNoMip("medal_defend")
	cgs.media.medalAssist = trap.R_RegisterShaderNoMip("medal_assist")
	cgs.media.medalCapture = trap.R_RegisterShaderNoMip("medal_capture")

	-- LEILEI SHADERS
	cgs.media.lsmkShader1 = trap.R_RegisterShader("leismoke1")
	cgs.media.lsmkShader2 = trap.R_RegisterShader("leismoke2")
	cgs.media.lsmkShader3 = trap.R_RegisterShader("leismoke3")
	cgs.media.lsmkShader4 = trap.R_RegisterShader("leismoke4")

	cgs.media.lsplShader = trap.R_RegisterShader("leisplash")
	cgs.media.lspkShader1 = trap.R_RegisterShader("leispark")
	cgs.media.lspkShader2 = trap.R_RegisterShader("leispark2")
	cgs.media.lbumShader1 = trap.R_RegisterShader("leiboom1")
	cgs.media.lfblShader1 = trap.R_RegisterShader("leifball")

	cgs.media.lbldShader1 = trap.R_RegisterShader("leiblood1")
	cgs.media.lbldShader2 = trap.R_RegisterShader("leiblood2") -- this is a mark, by the way

	-- New Bullet Marks
	cgs.media.lmarkmetal1 = trap.R_RegisterShader("leimetalmark1")
	cgs.media.lmarkmetal2 = trap.R_RegisterShader("leimetalmark2")
	cgs.media.lmarkmetal3 = trap.R_RegisterShader("leimetalmark3")
	cgs.media.lmarkmetal4 = trap.R_RegisterShader("leimetalmark4")
	cgs.media.lmarkbullet1 = trap.R_RegisterShader("leibulletmark1")
	cgs.media.lmarkbullet2 = trap.R_RegisterShader("leibulletmark2")
	cgs.media.lmarkbullet3 = trap.R_RegisterShader("leibulletmark3")
	cgs.media.lmarkbullet4 = trap.R_RegisterShader("leibulletmark4")

	for i = 0, C.MAX_ITEMS - 1 do
		T.reset(G.cg_items[i], T.itemInfo_t)
	end
	for i = 0, C.MAX_WEAPONS - 1 do
		T.reset(G.cg_weapons[i], T.weaponInfo_t)
	end

	-- only register the items that the server says we need
	local items = string.sub(G.CG_ConfigString(C.CS_ITEMS), 1, C.MAX_ITEMS)

	for i = 1, BG.bg_numItems - 1 do
		if string.sub(items, i + 1, i + 1) == "1" or buildScript then
			G.CG_LoadingItem(i)
			G.CG_RegisterItemVisuals(i)
		end
	end

	-- wall marks
	cgs.media.bulletMarkShader = trap.R_RegisterShader("gfx/damage/bullet_mrk")
	cgs.media.burnMarkShader = trap.R_RegisterShader("gfx/damage/burn_med_mrk")
	cgs.media.holeMarkShader = trap.R_RegisterShader("gfx/damage/hole_lg_mrk")
	cgs.media.energyMarkShader = trap.R_RegisterShader("gfx/damage/plasma_mrk")
	cgs.media.shadowMarkShader = trap.R_RegisterShader("markShadow")
	cgs.media.wakeMarkShader = trap.R_RegisterShader("wake")
	cgs.media.bloodMarkShader = trap.R_RegisterShader("bloodMark")

	-- register the inline models
	cgs.numInlineModels = trap.CM_NumInlineModels()
	for i = 1, cgs.numInlineModels - 1 do
		local mins = Q.vec3(0, 0, 0)
		local maxs = Q.vec3(0, 0, 0)

		local name = Q.va("*%i", i)
		cgs.inlineDrawModel[i] = trap.R_RegisterModel(name)
		trap.R_ModelBounds(cgs.inlineDrawModel[i], mins, maxs)
		for j = 0, 2 do
			cgs.inlineModelMidpoints[i][j] = mins[j] + 0.5 * (maxs[j] - mins[j])
		end
	end

	-- register all the server specified models
	for i = 1, C.MAX_MODELS - 1 do
		local modelName = G.CG_ConfigString(C.CS_MODELS + i)
		if modelName == "" then
			break
		end
		cgs.gameModels[i] = trap.R_RegisterModel(modelName)
	end

	G.CG_ClearParticles()
end
G.sb_nums = sb_nums

function G.CG_BuildSpectatorString()
	local cg = G.cg
	local cgs = G.cgs
	cg.spectatorList = ""
	for i = 0, C.MAX_CLIENTS - 1 do
		if cgs.clientinfo[i].infoValid and cgs.clientinfo[i].team == C.TEAM_SPECTATOR then
			cg.spectatorList = cg.spectatorList .. Q.va("%s     ", cgs.clientinfo[i].name)
		end
	end
	local n = #cg.spectatorList
	if n ~= cg.spectatorLen then
		cg.spectatorLen = n
		cg.spectatorWidth = -1
	end
end

function G.CG_RegisterClients()
	local cg = G.cg

	G.CG_LoadingClient(cg.clientNum)
	G.CG_NewClientInfo(cg.clientNum)

	for i = 0, C.MAX_CLIENTS - 1 do
		if cg.clientNum ~= i then
			local clientInfo = G.CG_ConfigString(C.CS_PLAYERS + i)
			if clientInfo ~= "" then
				G.CG_LoadingClient(i)
				G.CG_NewClientInfo(i)
			end
		end
	end
	G.CG_BuildSpectatorString()
end

function G.CG_ConfigString(index: number): string
	if index < 0 or index >= C.MAX_CONFIGSTRINGS then
		G.CG_Error(Q.va("CG_ConfigString: bad index: %i", index))
	end
	return G.cgs.gameState.configstrings[index] or ""
end

function G.CG_StartMusic()
	-- start the background music
	if G.cg_music.string ~= "" and Q.stricmp(G.cg_music.string, "none") ~= 0 then
		return
	end
	local parser = Q.COM_Parser(G.CG_ConfigString(C.CS_MUSIC))
	local parm1 = parser:Parse()
	local parm2 = parser:Parse()

	trap.S_StartBackgroundTrack(parm1, parm2)
end

function G.CG_Init(serverMessageNum, serverCommandSequence, clientNum)
	-- clear everything
	T.reset(G.cgs, T.cgs_t)
	T.reset(G.cg, T.cg_t)
	for i = 0, C.MAX_GENTITIES - 1 do
		T.reset(G.cg_entities[i], T.centity_t)
	end
	for i = 0, C.MAX_WEAPONS - 1 do
		T.reset(G.cg_weapons[i], T.weaponInfo_t)
	end
	for i = 0, C.MAX_ITEMS - 1 do
		T.reset(G.cg_items[i], T.itemInfo_t)
	end

	local cg = G.cg
	local cgs = G.cgs

	cg.clientNum = clientNum

	cgs.processedSnapshotNum = serverMessageNum
	cgs.serverCommandSequence = serverCommandSequence

	-- load a few needed things before we do any screen updates
	cgs.media.charsetShader = trap.R_RegisterShader("gfx/2d/bigchars")
	cgs.media.whiteShader = trap.R_RegisterShader("white")
	cgs.media.charsetProp = trap.R_RegisterShaderNoMip("menu/art/font1_prop.tga")
	cgs.media.charsetPropGlow = trap.R_RegisterShaderNoMip("menu/art/font1_prop_glo.tga")
	cgs.media.charsetPropB = trap.R_RegisterShaderNoMip("menu/art/font2_prop.tga")

	G.CG_RegisterCvars()

	G.CG_InitConsoleCommands()

	cg.weaponSelect = C.WP_MACHINEGUN

	cgs.redflag = -1
	cgs.blueflag = -1 -- For compatibily, default to unset for
	cgs.flagStatus = -1
	-- old servers

	-- get the rendering configuration from the client system
	trap.GetGlconfig(cgs.glconfig)

	local Screen = require(script.Parent.Parent.Parent.ui.Screen)
	Screen.cgSetup(G.cgs)

	-- get the gamestate from the client system
	trap.GetGameState(cgs.gameState)

	-- check version
	local s = G.CG_ConfigString(C.CS_GAME_VERSION)
	if s ~= C.GAME_VERSION then
		G.CG_Error(Q.va("Client/Server game mismatch: %s/%s", C.GAME_VERSION, s))
	end

	s = G.CG_ConfigString(C.CS_LEVEL_START_TIME)
	cgs.levelStartTime = atoi(s)

	G.CG_ParseServerinfo()

	-- load the new map
	G.CG_LoadingString("collision map")
	trap.CM_LoadMap(cgs.mapname)

	cg.loading = true -- force players to load instead of defer

	G.CG_LoadingString("sounds")

	G.CG_RegisterSounds()

	G.CG_LoadingString("graphics")

	G.CG_RegisterGraphics()

	G.CG_LoadingString("clients")

	G.CG_RegisterClients() -- if low on memory, some clients will be deferred

	cg.loading = false -- future players will be deferred

	G.CG_InitLocalEntities()

	G.CG_InitMarkPolys()

	-- remove the last loading update
	cg.infoScreenText = ""

	-- Make sure we have update values (scores)
	G.CG_SetConfigValues()

	G.CG_StartMusic()

	G.CG_LoadingString("")

	G.CG_ShaderStateChanged()

	--Init challenge system
	G.challenges_init()

	G.addChallenge(C.GENERAL_TEST)

	trap.S_ClearLoopingSounds(true)
end

function G.CG_Shutdown()
	-- some mods may need to do cleanup work here,
	-- like closing files or archiving session data
	G.challenges_save()
end

--[[
type 0 - no event handling
     1 - team menu
     2 - hud editor
]]
function G.CG_EventHandling(type: number) end

function G.CG_KeyEvent(key: number, down: boolean) end

function G.CG_MouseEvent(x: number, y: number) end

--unlagged - attack prediction #3
-- moved from g_weapon.c

--[[
Round a vector to integers for more efficient network
transmission, but make sure that it rounds towards a given point
rather than blindly truncating.  This prevents it from truncating
into a wall.
]]
function G.SnapVectorTowards(v, to)
	for i = 0, 2 do
		if to[i] <= v[i] then
			v[i] = Q.int(v[i])
		else
			v[i] = Q.int(v[i]) + 1
		end
	end
end

G.do_vid_restart = false

function G.CG_FairCvars()
	local cgs = G.cgs
	local vid_restart_required = false

	if cgs.gametype == C.GT_SINGLE_PLAYER then
		local info = trap.Cvar_VariableStringBuffer("r_vertexlight")
		if G.cg_autovertex.integer ~= 0 and atoi(info) == 0 then
			trap.Cvar_Set("r_vertexlight", "1")
			vid_restart_required = true
		end
		return -- Don't do anything in single player
	end

	if bit32.band(cgs.videoflags, C.VF_LOCK_CVARS_BASIC) ~= 0 then
		-- Lock basic cvars.
		local info = trap.Cvar_VariableStringBuffer("r_subdivisions")
		if atoi(info) > 80 then
			trap.Cvar_Set("r_subdivisions", "80")
			vid_restart_required = true
		end

		info = trap.Cvar_VariableStringBuffer("cg_shadows")
		if atoi(info) ~= 0 and atoi(info) ~= 1 then
			trap.Cvar_Set("cg_shadows", "1")
		end
	end

	if bit32.band(cgs.videoflags, C.VF_LOCK_CVARS_EXTENDED) ~= 0 then
		-- Lock extended cvars.
		local info = trap.Cvar_VariableStringBuffer("r_subdivisions")
		if atoi(info) > 20 then
			trap.Cvar_Set("r_subdivisions", "20")
			vid_restart_required = true
		end

		info = trap.Cvar_VariableStringBuffer("r_picmip")
		if atoi(info) > 3 then
			trap.Cvar_Set("r_picmip", "3")
			vid_restart_required = true
		elseif atoi(info) < 0 then
			trap.Cvar_Set("r_picmip", "0")
			vid_restart_required = true
		end

		info = trap.Cvar_VariableStringBuffer("r_intensity")
		if atoi(info) > 2 then
			trap.Cvar_Set("r_intensity", "2")
			vid_restart_required = true
		elseif atoi(info) < 0 then
			trap.Cvar_Set("r_intensity", "0")
			vid_restart_required = true
		end

		info = trap.Cvar_VariableStringBuffer("r_mapoverbrightbits")
		if atoi(info) > 2 then
			trap.Cvar_Set("r_mapoverbrightbits", "2")
			vid_restart_required = true
		elseif atoi(info) < 0 then
			trap.Cvar_Set("r_mapoverbrightbits", "0")
			vid_restart_required = true
		end

		info = trap.Cvar_VariableStringBuffer("r_overbrightbits")
		if atoi(info) > 2 then
			trap.Cvar_Set("r_overbrightbits", "2")
			vid_restart_required = true
		elseif atoi(info) < 0 then
			trap.Cvar_Set("r_overbrightbits", "0")
			vid_restart_required = true
		end
	end

	if bit32.band(cgs.videoflags, C.VF_LOCK_VERTEX) ~= 0 then
		local info = trap.Cvar_VariableStringBuffer("r_vertexlight")
		if atoi(info) ~= 0 then
			trap.Cvar_Set("r_vertexlight", "0")
			vid_restart_required = true
		end
	elseif G.cg_autovertex.integer ~= 0 then
		local info = trap.Cvar_VariableStringBuffer("r_vertexlight")
		if atoi(info) == 0 then
			trap.Cvar_Set("r_vertexlight", "1")
			vid_restart_required = true
		end
	end

	if vid_restart_required and G.do_vid_restart then
		trap.SendConsoleCommand("vid_restart")
	end

	G.do_vid_restart = true
end

return G
