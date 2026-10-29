--[[
===========================================================================
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
along with Quake III Arena source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
]]
-- Luau port of code/cgame/cg_players.c (OpenArena gamecode).
-- This part covers lines 1-1470 (through CG_PlayerAnimation).

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local trap = require(script.Parent.Parent.sys.Trap)

G.cg_customSoundNames = {
	[0] = "*death1.wav",
	"*death2.wav",
	"*death3.wav",
	"*jump1.wav",
	"*pain25_1.wav",
	"*pain50_1.wav",
	"*pain75_1.wav",
	"*pain100_1.wav",
	"*falling1.wav",
	"*gasp.wav",
	"*drown.wav",
	"*fall1.wav",
	"*taunt.wav",
}

-- leilei - eyes hack
G.headpos = Q.vec3(0, 0, 0)
G.headang = Q.vec3(0, 0, 0)
G.enableQ = 0

local function isTeamGame(): boolean
	return G.cgs.gametype >= C.GT_TEAM and G.cgs.ffa_gt ~= 1
end

function G.CG_CustomSound(clientNum, soundName)
	if string.sub(soundName, 1, 1) ~= "*" then
		return trap.S_RegisterSound(soundName, false)
	end

	if clientNum < 0 or clientNum >= C.MAX_CLIENTS then
		clientNum = 0
	end
	local ci = G.cgs.clientinfo[clientNum]

	local i = 0
	while i < C.MAX_CUSTOM_SOUNDS and G.cg_customSoundNames[i] ~= nil do
		if soundName == G.cg_customSoundNames[i] then
			return ci.sounds[i]
		end
		i += 1
	end

	G.CG_Error(Q.va("Unknown custom sound: %s", soundName))
	return 0
end

-- COM_Parse over a string: returns token and the new position (1-based)
local function comParse(text: string, pos: number): (string, number)
	local len = #text
	while true do
		while pos <= len and string.byte(text, pos) <= 32 do
			pos += 1
		end
		if pos > len then
			return "", pos
		end
		local c = string.sub(text, pos, pos)
		if c == "/" and string.sub(text, pos + 1, pos + 1) == "/" then
			while pos <= len and string.sub(text, pos, pos) ~= "\n" do
				pos += 1
			end
		elseif c == "/" and string.sub(text, pos + 1, pos + 1) == "*" then
			pos += 2
			while pos <= len and not (string.sub(text, pos, pos) == "*" and string.sub(text, pos + 1, pos + 1) == "/") do
				pos += 1
			end
			pos += 2
		else
			break
		end
	end

	if string.sub(text, pos, pos) == '"' then
		pos += 1
		local start = pos
		while pos <= len and string.sub(text, pos, pos) ~= '"' do
			pos += 1
		end
		return string.sub(text, start, pos - 1), pos + 1
	end

	local start = pos
	while pos <= len and string.byte(text, pos) > 32 do
		pos += 1
	end
	return string.sub(text, start, pos - 1), pos
end

local function readFile(filename: string): string?
	local len, f = trap.FS_FOpenFile(filename, C.FS_READ)
	if len == nil or len <= 0 then
		return nil
	end
	if len >= 20000 - 1 then
		G.CG_Printf(Q.va("File %s too long\n", filename))
		trap.FS_FCloseFile(f)
		return nil
	end
	local text = trap.FS_Read(len, f)
	trap.FS_FCloseFile(f)
	return text
end

local function atof(s: string): number
	return tonumber(string.match(s, "^%s*([%+%-]?%d*%.?%d*)")) or 0
end

local function atoi(s: string): number
	return Q.int(atof(string.match(s, "^%s*([%+%-]?%d*)") or ""))
end

local animFallbacks = {
	{ C.TORSO_RUN, C.TORSO_STAND },
	{ C.TORSO_RUN2, C.TORSO_STAND2 },
	{ C.TORSO_RUN3, C.TORSO_STAND },
	{ C.TORSO_STRAFE, C.TORSO_STAND },
	{ C.TORSO_STAND3, C.TORSO_STAND },
	{ C.TORSO_JUMP, C.TORSO_STAND },
	{ C.TORSO_JUMP2, C.TORSO_STAND },
	{ C.TORSO_JUMP3, C.TORSO_STAND },
	{ C.TORSO_FALL, C.TORSO_STAND },
	{ C.TORSO_FALL2, C.TORSO_STAND2 },
	{ C.TORSO_FALL3, C.TORSO_STAND },
	{ C.TORSO_TALK, C.TORSO_STAND },
	{ C.LEGS_STRAFE_LEFT, C.LEGS_RUN },
	{ C.LEGS_STRAFE_RIGHT, C.LEGS_RUN },
}

function G.CG_ParseAnimationFile(filename, ci)
	local animations = ci.animations

	local text = readFile(filename)
	if text == nil then
		return false
	end

	local pos = 1
	local prev
	local token
	local skip = 0

	ci.footsteps = C.FOOTSTEP_NORMAL
	ci.headOffset[0] = 0
	ci.headOffset[1] = 0
	ci.headOffset[2] = 0
	ci.gender = C.GENDER_MALE
	ci.fixedlegs = false
	ci.fixedtorso = false

	-- read optional parameters
	while true do
		prev = pos
		token, pos = comParse(text, pos)
		if token == "" then
			break
		end
		if token == "footsteps" then
			token, pos = comParse(text, pos)
			if token == "" then
				break
			end
			if token == "default" or token == "normal" then
				ci.footsteps = C.FOOTSTEP_NORMAL
			elseif token == "boot" then
				ci.footsteps = C.FOOTSTEP_BOOT
			elseif token == "flesh" then
				ci.footsteps = C.FOOTSTEP_FLESH
			elseif token == "mech" then
				ci.footsteps = C.FOOTSTEP_MECH
			elseif token == "energy" then
				ci.footsteps = C.FOOTSTEP_ENERGY
			else
				G.CG_Printf(Q.va("Bad footsteps parm in %s: %s\n", filename, token))
			end
			continue
		elseif token == "headoffset" then
			for i = 0, 2 do
				token, pos = comParse(text, pos)
				if token == "" then
					break
				end
				ci.headOffset[i] = atof(token)
			end
			continue
		elseif token == "eyes" then
			for i = 0, 2 do
				token, pos = comParse(text, pos)
				if token == "" then
					break
				end
				ci.eyepos[i] = atof(token)
			end
			continue
		elseif token == "sex" then
			token, pos = comParse(text, pos)
			if token == "" then
				break
			end
			local c = string.sub(token, 1, 1)
			if c == "f" or c == "F" then
				ci.gender = C.GENDER_FEMALE
			elseif c == "n" or c == "N" then
				ci.gender = C.GENDER_NEUTER
			else
				ci.gender = C.GENDER_MALE
			end
			continue
		elseif token == "fixedlegs" then
			ci.fixedlegs = true
			continue
		elseif token == "fixedtorso" then
			ci.fixedtorso = true
			continue
		end

		-- if it is a number, start parsing animations
		local c = string.sub(token, 1, 1)
		if c >= "0" and c <= "9" then
			pos = prev -- unget the token
			break
		end
		trap.Print(Q.va("unknown token '%s' in %s\n", token, filename))
	end

	-- read information for each frame
	local i = 0
	while i < C.MAX_ANIMATIONS do
		token, pos = comParse(text, pos)
		if token == "" then
			if i >= C.TORSO_GETFLAG and i <= C.TORSO_NEGATIVE then
				animations[i] = T.copy(animations[C.TORSO_GESTURE])
				animations[i].reversed = false
				animations[i].flipflop = false
				i += 1
				continue
			end
			local handled = false
			for _, fb in animFallbacks do
				if i == fb[1] then
					animations[i] = T.copy(animations[fb[2]])
					animations[i].reversed = false
					animations[i].flipflop = false
					handled = true
					break
				end
			end
			if handled then
				i += 1
				continue
			end
			break
		end
		animations[i].firstFrame = atoi(token)
		-- leg only frames are adjusted to not count the upper body only frames
		if i == C.LEGS_WALKCR then
			skip = animations[C.LEGS_WALKCR].firstFrame - animations[C.TORSO_GESTURE].firstFrame
		end
		if i >= C.LEGS_WALKCR and i < C.TORSO_GETFLAG then
			animations[i].firstFrame -= skip
		end

		token, pos = comParse(text, pos)
		if token == "" then
			break
		end
		animations[i].numFrames = atoi(token)

		animations[i].reversed = false
		animations[i].flipflop = false
		-- if numFrames is negative the animation is reversed
		if animations[i].numFrames < 0 then
			animations[i].numFrames = -animations[i].numFrames
			animations[i].reversed = true
		end

		token, pos = comParse(text, pos)
		if token == "" then
			break
		end
		animations[i].loopFrames = atoi(token)

		token, pos = comParse(text, pos)
		if token == "" then
			break
		end
		local fps = atof(token)
		if fps == 0 then
			fps = 1
		end
		animations[i].frameLerp = Q.int(1000 / fps)
		animations[i].initialLerp = Q.int(1000 / fps)
		i += 1
	end

	if i ~= C.MAX_ANIMATIONS then
		G.CG_Printf(Q.va("Error parsing animation file: %s\n", filename))
		return false
	end

	-- crouch backward animation
	animations[C.LEGS_BACKCR] = T.copy(animations[C.LEGS_WALKCR])
	animations[C.LEGS_BACKCR].reversed = true
	-- walk backward animation
	animations[C.LEGS_BACKWALK] = T.copy(animations[C.LEGS_WALK])
	animations[C.LEGS_BACKWALK].reversed = true
	-- flag moving fast
	animations[C.FLAG_RUN].firstFrame = 0
	animations[C.FLAG_RUN].numFrames = 16
	animations[C.FLAG_RUN].loopFrames = 16
	animations[C.FLAG_RUN].frameLerp = Q.idiv(1000, 15)
	animations[C.FLAG_RUN].initialLerp = Q.idiv(1000, 15)
	animations[C.FLAG_RUN].reversed = false
	-- flag not moving or moving slowly
	animations[C.FLAG_STAND].firstFrame = 16
	animations[C.FLAG_STAND].numFrames = 5
	animations[C.FLAG_STAND].loopFrames = 0
	animations[C.FLAG_STAND].frameLerp = Q.idiv(1000, 20)
	animations[C.FLAG_STAND].initialLerp = Q.idiv(1000, 20)
	animations[C.FLAG_STAND].reversed = false
	-- flag speeding up
	animations[C.FLAG_STAND2RUN].firstFrame = 16
	animations[C.FLAG_STAND2RUN].numFrames = 5
	animations[C.FLAG_STAND2RUN].loopFrames = 1
	animations[C.FLAG_STAND2RUN].frameLerp = Q.idiv(1000, 15)
	animations[C.FLAG_STAND2RUN].initialLerp = Q.idiv(1000, 15)
	animations[C.FLAG_STAND2RUN].reversed = true
	--
	-- new anims changes
	--
	animations[C.TORSO_GETFLAG].flipflop = true
	animations[C.TORSO_GUARDBASE].flipflop = true
	animations[C.TORSO_PATROL].flipflop = true
	animations[C.TORSO_AFFIRMATIVE].flipflop = true
	animations[C.TORSO_NEGATIVE].flipflop = true
	--
	return true
end

function G.CG_ParseEyesFile(filename, ci)
	local text = readFile(filename)
	if text == nil then
		return false
	end

	local pos = 1
	local token

	while true do
		token, pos = comParse(text, pos)
		if token == "" then
			break
		end

		if Q.stricmp(token, "eyes") == 0 then
			for i = 0, 2 do
				token, pos = comParse(text, pos)
				if token == "" then
					break
				end
				ci.eyepos[i] = atof(token)
			end
			continue
		end
		break
	end

	return true
end

function G.CG_FileExists(filename)
	local len, f = trap.FS_FOpenFile(filename, C.FS_READ)
	if len ~= nil and len > 0 then
		if f ~= nil and f ~= 0 then
			trap.FS_FCloseFile(f)
		end
		return true
	end
	return false
end

-- Returns found, filename.
function G.CG_FindClientModelFile(ci, teamName, modelName, skinName, base, ext)
	local team
	local filename = ""

	if isTeamGame() then
		if ci.team == C.TEAM_BLUE then
			team = "blue"
		else
			team = "red"
		end
	else
		team = "default"
	end
	local hasTeam = teamName ~= nil and teamName ~= ""
	local charactersFolder = ""
	while true do
		for i = 0, 1 do
			if i == 0 and hasTeam then
				filename = Q.va("models/players/%s%s/%s%s_%s_%s.%s", charactersFolder, modelName, teamName, base, skinName, team, ext)
			else
				filename = Q.va("models/players/%s%s/%s_%s_%s.%s", charactersFolder, modelName, base, skinName, team, ext)
			end
			if G.CG_FileExists(filename) then
				return true, filename
			end
			if isTeamGame() then
				if i == 0 and hasTeam then
					filename = Q.va("models/players/%s%s/%s%s_%s.%s", charactersFolder, modelName, teamName, base, team, ext)
				else
					filename = Q.va("models/players/%s%s/%s_%s.%s", charactersFolder, modelName, base, team, ext)
				end
			else
				if i == 0 and hasTeam then
					filename = Q.va("models/players/%s%s/%s%s_%s.%s", charactersFolder, modelName, teamName, base, skinName, ext)
				else
					filename = Q.va("models/players/%s%s/%s_%s.%s", charactersFolder, modelName, base, skinName, ext)
				end
			end
			if G.CG_FileExists(filename) then
				return true, filename
			end
			if not hasTeam then
				break
			end
		end
		-- if tried the heads folder first
		if charactersFolder ~= "" then
			break
		end
		charactersFolder = "characters/"
	end

	return false, filename
end

-- Returns found, filename.
function G.CG_FindClientHeadFile(ci, teamName, headModelName, headSkinName, base, ext)
	local team
	local filename = ""

	if isTeamGame() then
		if ci.team == C.TEAM_BLUE then
			team = "blue"
		else
			team = "red"
		end
	else
		team = "default"
	end

	local headsFolder
	if string.sub(headModelName, 1, 1) == "*" then
		headsFolder = "heads/"
		headModelName = string.sub(headModelName, 2)
	else
		headsFolder = ""
	end
	local hasTeam = teamName ~= nil and teamName ~= ""
	while true do
		for i = 0, 1 do
			if i == 0 and hasTeam then
				filename = Q.va("models/players/%s%s/%s/%s%s_%s.%s", headsFolder, headModelName, headSkinName, teamName, base, team, ext)
			else
				filename = Q.va("models/players/%s%s/%s/%s_%s.%s", headsFolder, headModelName, headSkinName, base, team, ext)
			end
			if G.CG_FileExists(filename) then
				return true, filename
			end
			if isTeamGame() then
				if i == 0 and hasTeam then
					filename = Q.va("models/players/%s%s/%s%s_%s.%s", headsFolder, headModelName, teamName, base, team, ext)
				else
					filename = Q.va("models/players/%s%s/%s_%s.%s", headsFolder, headModelName, base, team, ext)
				end
			else
				if i == 0 and hasTeam then
					filename = Q.va("models/players/%s%s/%s%s_%s.%s", headsFolder, headModelName, teamName, base, headSkinName, ext)
				else
					filename = Q.va("models/players/%s%s/%s_%s.%s", headsFolder, headModelName, base, headSkinName, ext)
				end
			end
			if G.CG_FileExists(filename) then
				return true, filename
			end
			if not hasTeam then
				break
			end
		end
		-- if tried the heads folder first
		if headsFolder ~= "" then
			break
		end
		headsFolder = "heads/"
	end

	return false, filename
end

function G.CG_RegisterClientSkin(ci, teamName, modelName, skinName, headModelName, headSkinName)
	local filename = ""
	local found

	if ci.onepiece ~= 0 then
		filename = Q.va("models/playerfs/%s/%stris_%s.skin", modelName, teamName, skinName)
		ci.legsSkin = trap.R_RegisterSkin(filename)
		if ci.legsSkin == 0 then
			trap.Print(Q.va("Onepieced model skin load failure: %s\n", filename))
		end
	else
		found, filename = G.CG_FindClientModelFile(ci, teamName, modelName, skinName, "lower", "skin")
		if found then
			ci.legsSkin = trap.R_RegisterSkin(filename)
		end
		if ci.legsSkin == 0 then
			trap.Print(Q.va("Leg skin load failure: %s\n", filename))
		end
	end

	found, filename = G.CG_FindClientModelFile(ci, teamName, modelName, skinName, "upper", "skin")
	if found then
		ci.torsoSkin = trap.R_RegisterSkin(filename)
	end
	if ci.torsoSkin == 0 then
		trap.Print(Q.va("Torso skin load failure: %s\n", filename))
	end

	found, filename = G.CG_FindClientHeadFile(ci, teamName, headModelName, headSkinName, "head", "skin")
	if found then
		ci.headSkin = trap.R_RegisterSkin(filename)
	end
	if ci.headSkin == 0 then
		trap.Print(Q.va("Head skin load failure: %s\n", filename))
	end

	-- if any skins failed to load
	if ci.legsSkin == 0 or ci.torsoSkin == 0 or ci.headSkin == 0 then
		return false
	end
	return true
end

function G.CG_RegisterClientModelname(ci, modelName, skinName, headModelName, headSkinName, teamName)
	local filename
	local headName
	local FSloaded = 0

	if headModelName == "" then
		headName = modelName
	else
		headName = headModelName
	end

	-- leilei - onepiece model loading for certain maps or WIP animation debug
	ci.onepiece = 0
	if G.cg_enableFS.integer ~= 0 then
		filename = Q.va("models/playerfs/%s/tris.mdr", modelName)
		ci.legsModel = trap.R_RegisterModel(filename)
		if ci.legsModel ~= 0 then
			FSloaded = 1
			ci.onepiece = 1
		end
		if ci.legsModel == 0 then
			FSloaded = 0
		end

		if FSloaded ~= 0 then
			trap.Print(Q.va("%s is fanservice\n", filename))
		else
			trap.Print(Q.va("%s can't provide fanservice\n", filename))
		end
	end

	-- load the usual model
	if FSloaded == 0 then
		filename = Q.va("models/players/%s/lower.mdr", modelName)
		ci.legsModel = trap.R_RegisterModel(filename)
		if ci.legsModel == 0 then
			filename = Q.va("models/players/characters/%s/lower.mdr", modelName)
			ci.legsModel = trap.R_RegisterModel(filename)
			if ci.legsModel == 0 then
				filename = Q.va("models/players/%s/lower.md3", modelName)
				ci.legsModel = trap.R_RegisterModel(filename)
				if ci.legsModel == 0 then
					filename = Q.va("models/players/characters/%s/lower.md3", modelName)
					ci.legsModel = trap.R_RegisterModel(filename)
					if ci.legsModel == 0 then
						trap.Print(Q.va("Failed to load model file %s\n", filename))
						return false
					end
				end
			end
		end

		filename = Q.va("models/players/%s/upper.mdr", modelName)
		ci.torsoModel = trap.R_RegisterModel(filename)
		if ci.torsoModel == 0 then
			filename = Q.va("models/players/characters/%s/upper.mdr", modelName)
			ci.torsoModel = trap.R_RegisterModel(filename)
			if ci.torsoModel == 0 then
				filename = Q.va("models/players/%s/upper.md3", modelName)
				ci.torsoModel = trap.R_RegisterModel(filename)
				if ci.torsoModel == 0 then
					filename = Q.va("models/players/characters/%s/upper.md3", modelName)
					ci.torsoModel = trap.R_RegisterModel(filename)
					if ci.torsoModel == 0 then
						trap.Print(Q.va("Failed to load model file %s\n", filename))
						return false
					end
				end
			end
		end
	end

	local headStar = string.sub(headName, 1, 1) == "*"
	local headRest = string.sub(headModelName, 2)
	if headStar then
		filename = Q.va("models/players/heads/%s/%s.mdr", headRest, headRest)
	else
		filename = Q.va("models/players/%s/head.mdr", headName)
	end
	ci.headModel = trap.R_RegisterModel(filename)
	-- if the head model could not be found and we didn't load from the heads folder try to load from there
	if ci.headModel == 0 and not headStar then
		filename = Q.va("models/players/heads/%s/%s.mdr", headModelName, headModelName)
		ci.headModel = trap.R_RegisterModel(filename)
	end
	if ci.headModel == 0 then
		if headStar then
			filename = Q.va("models/players/heads/%s/%s.md3", headRest, headRest)
		else
			filename = Q.va("models/players/%s/head.md3", headName)
		end
		ci.headModel = trap.R_RegisterModel(filename)
		if ci.headModel == 0 and not headStar then
			filename = Q.va("models/players/heads/%s/%s.md3", headModelName, headModelName)
			ci.headModel = trap.R_RegisterModel(filename)
		end
		if ci.headModel == 0 then
			trap.Print(Q.va("Failed to load model file %s\n", filename))
			return false
		end
	end

	-- if any skins failed to load, return failure
	if not G.CG_RegisterClientSkin(ci, teamName, modelName, skinName, headName, headSkinName) then
		if teamName ~= nil and teamName ~= "" then
			trap.Print(Q.va("Failed to load skin file: %s : %s : %s, %s : %s\n", teamName, modelName, skinName, headName, headSkinName))
			local newTeamName
			if ci.team == C.TEAM_BLUE then
				newTeamName = Q.va("%s/", C.DEFAULT_BLUETEAM_NAME)
			else
				newTeamName = Q.va("%s/", C.DEFAULT_REDTEAM_NAME)
			end
			if not G.CG_RegisterClientSkin(ci, newTeamName, modelName, skinName, headName, headSkinName) then
				trap.Print(Q.va("Failed to load skin file: %s : %s : %s, %s : %s\n", newTeamName, modelName, skinName, headName, headSkinName))
				return false
			end
		else
			trap.Print(Q.va("Failed to load skin file: %s : %s, %s : %s\n", modelName, skinName, headName, headSkinName))
			return false
		end
	end

	-- load the animations
	-- leilei - load one piece animation
	if ci.onepiece ~= 0 then
		filename = Q.va("models/playerfs/%s/animation.cfg", modelName)
		if not G.CG_ParseAnimationFile(filename, ci) then
			trap.Print(Q.va("Failed to load animation file %s\n", filename))
		end
	else
		filename = Q.va("models/players/%s/animation.cfg", modelName)
		if not G.CG_ParseAnimationFile(filename, ci) then
			filename = Q.va("models/players/characters/%s/animation.cfg", modelName)
			if not G.CG_ParseAnimationFile(filename, ci) then
				trap.Print(Q.va("Failed to load animation file %s\n", filename))
				return false
			end
		end
	end

	-- leilei - load eyes
	filename = Q.va("models/players/%s/eyes.cfg", modelName)
	G.CG_ParseEyesFile(filename, ci)

	local found
	found, filename = G.CG_FindClientHeadFile(ci, teamName, headName, headSkinName, "icon", "skin")
	if found then
		ci.modelIcon = trap.R_RegisterShaderNoMip(filename)
	else
		found, filename = G.CG_FindClientHeadFile(ci, teamName, headName, headSkinName, "icon", "tga")
		if found then
			ci.modelIcon = trap.R_RegisterShaderNoMip(filename)
		end
	end

	if ci.modelIcon == 0 then
		return false
	end

	return true
end

function G.CG_ColorFromString(v, color)
	color[0] = 0
	color[1] = 0
	color[2] = 0

	local val = atoi(v)

	if val < 1 or val > 7 then
		color[0] = 1
		color[1] = 1
		color[2] = 1
		return
	end

	if bit32.band(val, 1) ~= 0 then
		color[2] = 1.0
	end
	if bit32.band(val, 2) ~= 0 then
		color[1] = 1.0
	end
	if bit32.band(val, 4) ~= 0 then
		color[0] = 1.0
	end
end

--[[
Load it now, taking the disk hits.
This will usually be deferred to a safe time
]]
function G.CG_LoadClientInfo(clientNum, ci)
	local teamname = ""

	local modelloaded = true
	if not G.CG_RegisterClientModelname(ci, ci.modelName, ci.skinName, ci.headModelName, ci.headSkinName, teamname) then
		if G.cg_buildScript.integer ~= 0 then
			G.CG_Error(Q.va("CG_RegisterClientModelname( %s, %s, %s, %s %s ) failed", ci.modelName, ci.skinName, ci.headModelName, ci.headSkinName, teamname))
		end

		-- fall back to default team name
		if isTeamGame() then
			-- keep skin name
			if ci.team == C.TEAM_BLUE then
				teamname = C.DEFAULT_BLUETEAM_NAME
			else
				teamname = C.DEFAULT_REDTEAM_NAME
			end
			if not G.CG_RegisterClientModelname(ci, C.DEFAULT_TEAM_MODEL, ci.skinName, C.DEFAULT_TEAM_HEAD, ci.skinName, teamname) then
				G.CG_Error(Q.va("DEFAULT_TEAM_MODEL / skin (%s/%s) failed to register", C.DEFAULT_TEAM_MODEL, ci.skinName))
			end
		else
			if not G.CG_RegisterClientModelname(ci, C.DEFAULT_MODEL, "default", C.DEFAULT_MODEL, "default", teamname) then
				G.CG_Error(Q.va("DEFAULT_MODEL (%s) failed to register", C.DEFAULT_MODEL))
			end
		end
		modelloaded = false
	end

	ci.newAnims = false
	if ci.torsoModel ~= 0 then
		local tag = T.orientation_t()
		-- if the torso model has the "tag_flag"
		if trap.R_LerpTag(tag, ci.torsoModel, 0, 0, 1, "tag_flag") then
			ci.newAnims = true
		end
	end

	-- sounds
	local dir = ci.modelName
	local fallback = isTeamGame() and C.DEFAULT_TEAM_MODEL or C.DEFAULT_MODEL

	for i = 0, C.MAX_CUSTOM_SOUNDS - 1 do
		local s = G.cg_customSoundNames[i]
		if s == nil then
			break
		end
		ci.sounds[i] = 0
		-- if the model didn't load use the sounds of the default model
		if modelloaded then
			ci.sounds[i] = trap.S_RegisterSound(Q.va("sound/player/%s/%s", dir, string.sub(s, 2)), false)
		end
		if ci.sounds[i] == 0 then
			ci.sounds[i] = trap.S_RegisterSound(Q.va("sound/player/%s/%s", fallback, string.sub(s, 2)), false)
		end
	end

	ci.deferred = false

	-- reset any existing players and bodies, because they might be in bad
	-- frames for this new model
	for i = 0, C.MAX_GENTITIES - 1 do
		if G.cg_entities[i].currentState.clientNum == clientNum
			and G.cg_entities[i].currentState.eType == C.ET_PLAYER then
			G.CG_ResetPlayerEntity(G.cg_entities[i])
		end
	end
end

function G.CG_CopyClientInfoModel(from, to)
	to.headOffset[0], to.headOffset[1], to.headOffset[2] = from.headOffset[0], from.headOffset[1], from.headOffset[2]
	to.eyepos[0], to.eyepos[1], to.eyepos[2] = from.eyepos[0], from.eyepos[1], from.eyepos[2]
	to.footsteps = from.footsteps
	to.gender = from.gender

	to.legsModel = from.legsModel
	to.legsSkin = from.legsSkin
	to.torsoModel = from.torsoModel
	to.torsoSkin = from.torsoSkin
	to.headModel = from.headModel
	to.headSkin = from.headSkin
	to.modelIcon = from.modelIcon

	to.newAnims = from.newAnims

	for i = 0, C.MAX_TOTALANIMATIONS - 1 do
		to.animations[i] = T.copy(from.animations[i])
	end
	for i = 0, C.MAX_CUSTOM_SOUNDS - 1 do
		to.sounds[i] = from.sounds[i]
	end
end

function G.CG_ScanForExistingClientInfo(ci)
	for i = 0, G.cgs.maxclients - 1 do
		local match = G.cgs.clientinfo[i]
		if not match.infoValid then
			continue
		end
		if match.deferred then
			continue
		end
		if ci.modelName == match.modelName
			and ci.skinName == match.skinName
			and ci.headModelName == match.headModelName
			and ci.headSkinName == match.headSkinName
			and ci.blueTeam == match.blueTeam
			and ci.redTeam == match.redTeam
			and (G.cgs.gametype < C.GT_TEAM or G.cgs.ffa_gt == 1 or ci.team == match.team) then
			-- this clientinfo is identical, so use it's handles
			ci.deferred = false

			G.CG_CopyClientInfoModel(match, ci)

			return true
		end
	end

	-- nothing matches, so defer the load
	return false
end

--[[
We aren't going to load it now, so grab some other
client's info to use until we have some spare time.
]]
function G.CG_SetDeferredClientInfo(clientNum, ci)
	-- if someone else is already the same models and skins we
	-- can just load the client info
	for i = 0, G.cgs.maxclients - 1 do
		local match = G.cgs.clientinfo[i]
		if not match.infoValid or match.deferred then
			continue
		end
		if ci.skinName ~= match.skinName
			or ci.modelName ~= match.modelName
			or (isTeamGame() and ci.team ~= match.team) then
			continue
		end
		-- just load the real info cause it uses the same models and skins
		G.CG_LoadClientInfo(clientNum, ci)
		return
	end

	-- if we are in teamplay, only grab a model if the skin is correct
	if isTeamGame() then
		for i = 0, G.cgs.maxclients - 1 do
			local match = G.cgs.clientinfo[i]
			if not match.infoValid or match.deferred then
				continue
			end
			if ci.skinName ~= match.skinName or (isTeamGame() and ci.team ~= match.team) then
				continue
			end
			ci.deferred = true
			G.CG_CopyClientInfoModel(match, ci)
			return
		end
		-- load the full model, because we don't ever want to show
		-- an improper team skin.  This will cause a hitch for the first
		-- player, when the second enters.  Combat shouldn't be going on
		-- yet, so it shouldn't matter
		G.CG_LoadClientInfo(clientNum, ci)
		return
	end

	-- find the first valid clientinfo and grab its stuff
	for i = 0, G.cgs.maxclients - 1 do
		local match = G.cgs.clientinfo[i]
		if not match.infoValid then
			continue
		end

		ci.deferred = true
		G.CG_CopyClientInfoModel(match, ci)
		return
	end

	-- we should never get here...
	G.CG_Printf("CG_SetDeferredClientInfo: no valid clients!\n")

	G.CG_LoadClientInfo(clientNum, ci)
end

local function splitSkin(str: string): (string, string)
	local slash = string.find(str, "/", 1, true)
	if slash == nil then
		return str, "default"
	end
	return string.sub(str, 1, slash - 1), string.sub(str, slash + 1)
end

function G.CG_NewClientInfo(clientNum)
	local ci = G.cgs.clientinfo[clientNum]

	local configstring = G.CG_ConfigString(clientNum + C.CS_PLAYERS)
	if configstring == "" then
		T.reset(ci, T.clientInfo_t)
		return -- player just left
	end

	-- build into a temp buffer so the defer checks can use
	-- the old value
	local newInfo = T.clientInfo_t()

	-- isolate the player's name
	local v = Q.Info_ValueForKey(configstring, "n")
	newInfo.name = string.sub(v, 1, C.MAX_QPATH - 1)

	-- colors
	v = Q.Info_ValueForKey(configstring, "c1")
	G.CG_ColorFromString(v, newInfo.color1)

	v = Q.Info_ValueForKey(configstring, "c2")
	G.CG_ColorFromString(v, newInfo.color2)

	v = Q.Info_ValueForKey(configstring, "skill")
	newInfo.botSkill = atoi(v)

	v = Q.Info_ValueForKey(configstring, "hc")
	newInfo.handicap = atoi(v)

	v = Q.Info_ValueForKey(configstring, "w")
	newInfo.wins = atoi(v)

	v = Q.Info_ValueForKey(configstring, "l")
	newInfo.losses = atoi(v)

	v = Q.Info_ValueForKey(configstring, "t")
	newInfo.team = atoi(v)

	v = Q.Info_ValueForKey(configstring, "tt")
	newInfo.teamTask = atoi(v)

	v = Q.Info_ValueForKey(configstring, "tl")
	newInfo.teamLeader = atoi(v)

	v = Q.Info_ValueForKey(configstring, "g_redteam")
	newInfo.redTeam = string.sub(v, 1, C.MAX_TEAMNAME - 1)

	v = Q.Info_ValueForKey(configstring, "g_blueteam")
	newInfo.blueTeam = string.sub(v, 1, C.MAX_TEAMNAME - 1)

	-- model
	v = Q.Info_ValueForKey(configstring, "model")
	if G.cg_forceModel.integer ~= 0 then
		-- forcemodel makes everyone use a single model
		-- to prevent load hitches
		if isTeamGame() then
			newInfo.modelName = C.DEFAULT_TEAM_MODEL
			newInfo.skinName = "default"
		else
			local modelStr = trap.Cvar_VariableStringBuffer("model")
			newInfo.modelName, newInfo.skinName = splitSkin(modelStr)
		end

		if isTeamGame() then
			-- keep skin name
			local slash = string.find(v, "/", 1, true)
			if slash ~= nil then
				newInfo.skinName = string.sub(v, slash + 1)
			end
		end
	else
		newInfo.modelName = v
		newInfo.modelName, newInfo.skinName = splitSkin(v)
	end

	-- head model
	v = Q.Info_ValueForKey(configstring, "hmodel")
	if G.cg_forceModel.integer ~= 0 then
		if isTeamGame() then
			newInfo.headModelName = C.DEFAULT_TEAM_MODEL
			newInfo.headSkinName = "default"
		else
			local modelStr = trap.Cvar_VariableStringBuffer("headmodel")
			newInfo.headModelName, newInfo.headSkinName = splitSkin(modelStr)
		end

		if isTeamGame() then
			-- keep skin name
			local slash = string.find(v, "/", 1, true)
			if slash ~= nil then
				newInfo.headSkinName = string.sub(v, slash + 1)
			end
		end
	else
		newInfo.headModelName, newInfo.headSkinName = splitSkin(v)
	end

	-- scan for an existing clientinfo that matches this modelname
	-- so we can avoid loading checks if possible
	if not G.CG_ScanForExistingClientInfo(newInfo) then
		local forceDefer = trap.MemoryRemaining() < 4000000

		-- if we are defering loads, just have it pick the first valid
		if forceDefer or (G.cg_deferPlayers.integer ~= 0 and G.cg_buildScript.integer == 0 and not G.cg.loading) then
			-- keep whatever they had if it won't violate team skins
			G.CG_SetDeferredClientInfo(clientNum, newInfo)
			-- if we are low on memory, leave them with this model
			if forceDefer then
				G.CG_Printf("Memory is low. Using deferred model.\n")
				newInfo.deferred = false
			end
		else
			G.CG_LoadClientInfo(clientNum, newInfo)
		end
	end

	-- replace whatever was there with the new one
	newInfo.infoValid = true
	T.assign(ci, newInfo)
end

--[[
Called each frame when a player is dead
and the scoreboard is up
so deferred players can be loaded
]]
function G.CG_LoadDeferredPlayers()
	for i = 0, G.cgs.maxclients - 1 do
		local ci = G.cgs.clientinfo[i]
		if ci.infoValid and ci.deferred then
			-- if we are low on memory, leave it deferred
			if trap.MemoryRemaining() < 4000000 then
				G.CG_Printf("Memory is low. Using deferred model.\n")
				ci.deferred = false
				continue
			end
			G.CG_LoadClientInfo(i, ci)
		end
	end
end

-- may include ANIM_TOGGLEBIT
function G.CG_SetLerpFrameAnimation(ci, lf, newAnimation)
	lf.animationNumber = newAnimation
	newAnimation = bit32.band(newAnimation, bit32.bnot(C.ANIM_TOGGLEBIT))

	if newAnimation < 0 or newAnimation >= C.MAX_TOTALANIMATIONS then
		G.CG_Error(Q.va("Bad animation number: %i", newAnimation))
	end

	local anim = ci.animations[newAnimation]

	lf.animation = anim
	lf.animationTime = lf.frameTime + anim.initialLerp

	if G.cg_debugAnim.integer ~= 0 then
		G.CG_Printf(Q.va("Anim: %i\n", newAnimation))
	end
end

--[[
Sets cg.snap, cg.oldFrame, and cg.backlerp
cg.time should be between oldFrameTime and frameTime after exit
]]
function G.CG_RunLerpFrame(ci, lf, newAnimation, speedScale)
	local cg = G.cg

	-- debugging tool to get no animations
	if G.cg_animSpeed.integer == 0 then
		lf.oldFrame = 0
		lf.frame = 0
		lf.backlerp = 0
		return
	end

	-- see if the animation sequence is switching
	if newAnimation ~= lf.animationNumber or lf.animation == nil then
		G.CG_SetLerpFrameAnimation(ci, lf, newAnimation)
	end

	-- if we have passed the current frame, move it to
	-- oldFrame and calculate a new frame
	if cg.time >= lf.frameTime then
		lf.oldFrame = lf.frame
		lf.oldFrameTime = lf.frameTime

		-- get the next frame based on the animation
		local anim = lf.animation
		if anim.frameLerp == 0 then
			return -- shouldn't happen
		end
		if cg.time < lf.animationTime then
			lf.frameTime = lf.animationTime -- initial lerp
		else
			lf.frameTime = lf.oldFrameTime + anim.frameLerp
		end
		local f = Q.idiv(lf.frameTime - lf.animationTime, anim.frameLerp)
		f = Q.int(f * speedScale) -- adjust for haste, etc

		local numFrames = anim.numFrames
		if anim.flipflop then
			numFrames *= 2
		end
		if f >= numFrames then
			f -= numFrames
			if anim.loopFrames ~= 0 then
				f = math.fmod(f, anim.loopFrames)
				f += anim.numFrames - anim.loopFrames
			else
				f = numFrames - 1
				-- the animation is stuck at the end, so it
				-- can immediately transition to another sequence
				lf.frameTime = cg.time
			end
		end
		if anim.reversed then
			lf.frame = anim.firstFrame + anim.numFrames - 1 - f
		elseif anim.flipflop and f >= anim.numFrames then
			lf.frame = anim.firstFrame + anim.numFrames - 1 - math.fmod(f, anim.numFrames)
		else
			lf.frame = anim.firstFrame + f
		end
		if cg.time > lf.frameTime then
			lf.frameTime = cg.time
			if G.cg_debugAnim.integer ~= 0 then
				G.CG_Printf("Clamp lf->frameTime\n")
			end
		end
	end

	if lf.frameTime > cg.time + 200 then
		lf.frameTime = cg.time
	end

	if lf.oldFrameTime > cg.time then
		lf.oldFrameTime = cg.time
	end
	-- calculate current lerp value
	if lf.frameTime == lf.oldFrameTime then
		lf.backlerp = 0
	else
		lf.backlerp = 1.0 - (cg.time - lf.oldFrameTime) / (lf.frameTime - lf.oldFrameTime)
	end
end

function G.CG_ClearLerpFrame(ci, lf, animationNumber)
	lf.frameTime = G.cg.time
	lf.oldFrameTime = G.cg.time
	G.CG_SetLerpFrameAnimation(ci, lf, animationNumber)
	lf.frame = lf.animation.firstFrame
	lf.oldFrame = lf.frame
end

-- Returns legsOld, legs, legsBackLerp, torsoOld, torso, torsoBackLerp.
function G.CG_PlayerAnimation(cent)
	local clientNum = cent.currentState.clientNum

	if G.cg_noPlayerAnims.integer ~= 0 then
		return 0, 0, 0, 0, 0, 0
	end

	local speedScale
	if bit32.band(cent.currentState.powerups, bit32.lshift(1, C.PW_HASTE)) ~= 0 then
		speedScale = 1.5
	else
		speedScale = 1
	end

	local ci = G.cgs.clientinfo[clientNum]

	-- do the shuffle turn frames locally
	if cent.pe.legs.yawing and bit32.band(cent.currentState.legsAnim, bit32.bnot(C.ANIM_TOGGLEBIT)) == C.LEGS_IDLE then
		G.CG_RunLerpFrame(ci, cent.pe.legs, C.LEGS_TURN, speedScale)
	else
		G.CG_RunLerpFrame(ci, cent.pe.legs, cent.currentState.legsAnim, speedScale)
	end

	local legsOld = cent.pe.legs.oldFrame
	local legs = cent.pe.legs.frame
	local legsBackLerp = cent.pe.legs.backlerp

	G.CG_RunLerpFrame(ci, cent.pe.torso, cent.currentState.torsoAnim, speedScale)

	local torsoOld = cent.pe.torso.oldFrame
	local torso = cent.pe.torso.frame
	local torsoBackLerp = cent.pe.torso.backlerp

	return legsOld, legs, legsBackLerp, torsoOld, torso, torsoBackLerp
end

return G
