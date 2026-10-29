--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/ai_main.c, part 2 of 3).

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
===========================================================================
]]
--!native
-- Luau port of ai_main.c, part 2 of 3. Interbreeding, view angles, usercmd conversion, BotAI frame, session write.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local SF = G.FileStatics("ai_main")

local function isFalse(v)
	return v == nil or v == false or v == 0
end

function G.BotInterbreedBots()
	local ranks = {}
	for i = 0, C.MAX_CLIENTS - 1 do
		local b = G.botstates[i]
		if b ~= nil and b.inuse ~= 0 then
			ranks[i] = b.num_kills * 2 - b.num_deaths
		else
			ranks[i] = -1
		end
	end

	local ok, parent1, parent2, child = G.trap_GeneticParentsAndChildSelection(C.MAX_CLIENTS, ranks)
	if not isFalse(ok) then
		G.trap_BotInterbreedGoalFuzzyLogic(G.botstates[parent1].gs, G.botstates[parent2].gs, G.botstates[child].gs)
		G.trap_BotMutateGoalFuzzyLogic(G.botstates[child].gs, 1)
	end
	for i = 0, C.MAX_CLIENTS - 1 do
		local b = G.botstates[i]
		if b ~= nil and b.inuse ~= 0 then
			b.num_kills = 0
			b.num_deaths = 0
		end
	end
end

function G.BotWriteInterbreeded(filename)
	local rank
	local bestrank = 0
	local bestbot = -1
	for i = 0, C.MAX_CLIENTS - 1 do
		local b = G.botstates[i]
		if b ~= nil and b.inuse ~= 0 then
			rank = b.num_kills * 2 - b.num_deaths
		else
			rank = -1
		end
		if rank > bestrank then
			bestrank = rank
			bestbot = i
		end
	end
	if bestbot >= 0 then
		G.trap_BotSaveGoalFuzzyLogic(G.botstates[bestbot].gs, filename)
	end
end

function G.BotInterbreedEndMatch()
	if isFalse(G.bot_interbreed) then return end
	G.bot_interbreedmatchcount = G.bot_interbreedmatchcount + 1
	if G.bot_interbreedmatchcount >= G.bot_interbreedcycle.integer then
		G.bot_interbreedmatchcount = 0
		G.trap_Cvar_Update(G.bot_interbreedwrite)
		if #G.bot_interbreedwrite.string ~= 0 then
			G.BotWriteInterbreeded(G.bot_interbreedwrite.string)
			G.trap_Cvar_Set("bot_interbreedwrite", "")
		end
		G.BotInterbreedBots()
	end
end

function G.BotInterbreeding()
	G.trap_Cvar_Update(G.bot_interbreedchar)
	if #G.bot_interbreedchar.string == 0 then return end
	if G.gametype ~= C.GT_TOURNAMENT then
		G.trap_Cvar_Set("g_gametype", QS.va("%d", C.GT_TOURNAMENT))
		G.ExitLevel()
		return
	end
	for i = 0, C.MAX_CLIENTS - 1 do
		local b = G.botstates[i]
		if b ~= nil and b.inuse ~= 0 then
			G.BotAIShutdownClient(b.client, false)
		end
	end
	G.trap_BotLibVarSet("bot_reloadcharacters", "1")
	for i = 0, G.bot_interbreedbots.integer - 1 do
		G.trap_SendConsoleCommand(C.EXEC_INSERT, QS.va("addbot %s 4 free %i %s%d\n",
			G.bot_interbreedchar.string, i * 50, G.bot_interbreedchar.string, i))
	end
	G.trap_Cvar_Set("bot_interbreedchar", "")
	G.bot_interbreed = true
end

function G.BotEntityInfo(entnum, info)
	G.trap_AAS_EntityInfo(entnum, info)
end

function G.NumBots()
	return G.numbots
end

function G.BotTeamLeader(bs)
	local leader = G.ClientFromName(bs.teamleader)
	if leader < 0 then return 0 end
	if G.botstates[leader] == nil or G.botstates[leader].inuse == 0 then return 0 end
	return 1
end

function G.AngleDifference(ang1, ang2)
	local diff = ang1 - ang2
	if ang1 > ang2 then
		if diff > 180.0 then diff -= 360.0 end
	else
		if diff < -180.0 then diff += 360.0 end
	end
	return diff
end

function G.BotChangeViewAngle(angle, ideal_angle, speed)
	angle = Q.AngleMod(angle)
	ideal_angle = Q.AngleMod(ideal_angle)
	if angle == ideal_angle then return angle end
	local move = ideal_angle - angle
	if ideal_angle > angle then
		if move > 180.0 then move -= 360.0 end
	else
		if move < -180.0 then move += 360.0 end
	end
	if move > 0 then
		if move > speed then move = speed end
	else
		if move < -speed then move = -speed end
	end
	return Q.AngleMod(angle + move)
end

function G.BotChangeViewAngles(bs, thinktime)
	local diff, factor, maxchange, anglespeed, disired_speed

	if bs.ideal_viewangles[C.PITCH] > 180 then bs.ideal_viewangles[C.PITCH] -= 360 end
	if bs.enemy >= 0 then
		factor = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_VIEW_FACTOR, 0.01, 1)
		maxchange = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_VIEW_MAXCHANGE, 1, 1800)
	else
		factor = 0.05
		maxchange = 360
	end
	if maxchange < 240 then maxchange = 240 end
	maxchange *= thinktime
	for i = 0, 1 do
		if G.bot_challenge.integer ~= 0 then
			diff = math.abs(G.AngleDifference(bs.viewangles[i], bs.ideal_viewangles[i]))
			anglespeed = diff * factor
			if anglespeed > maxchange then anglespeed = maxchange end
			bs.viewangles[i] = G.BotChangeViewAngle(bs.viewangles[i], bs.ideal_viewangles[i], anglespeed)
		else
			bs.viewangles[i] = Q.AngleMod(bs.viewangles[i])
			bs.ideal_viewangles[i] = Q.AngleMod(bs.ideal_viewangles[i])
			diff = G.AngleDifference(bs.viewangles[i], bs.ideal_viewangles[i])
			disired_speed = diff * factor
			bs.viewanglespeed[i] += (bs.viewanglespeed[i] - disired_speed)
			if bs.viewanglespeed[i] > 180 then bs.viewanglespeed[i] = maxchange end
			if bs.viewanglespeed[i] < -180 then bs.viewanglespeed[i] = -maxchange end
			anglespeed = bs.viewanglespeed[i]
			if anglespeed > maxchange then anglespeed = maxchange end
			if anglespeed < -maxchange then anglespeed = -maxchange end
			bs.viewangles[i] += anglespeed
			bs.viewangles[i] = Q.AngleMod(bs.viewangles[i])
			bs.viewanglespeed[i] *= 0.45 * (1 - factor)
		end
	end
	if bs.viewangles[C.PITCH] > 180 then bs.viewangles[C.PITCH] -= 360 end
	G.trap_EA_View(bs.client, bs.viewangles)
end

function G.BotInputToUserCommand(bi, ucmd, delta_angles, time)
	local angles = Q.vec3()
	local forward = Q.vec3()
	local right = Q.vec3()

	S.copy_usercmd_t(ucmd, S.usercmd_t())
	ucmd.serverTime = time
	if bit32.band(bi.actionflags, C.ACTION_DELAYEDJUMP) ~= 0 then
		bi.actionflags = bit32.bor(bi.actionflags, C.ACTION_JUMP)
		bi.actionflags = bit32.band(bi.actionflags, bit32.bnot(C.ACTION_DELAYEDJUMP))
	end
	local af = bi.actionflags
	if bit32.band(af, C.ACTION_RESPAWN) ~= 0 then ucmd.buttons = C.BUTTON_ATTACK end
	if bit32.band(af, C.ACTION_ATTACK) ~= 0 then ucmd.buttons = bit32.bor(ucmd.buttons, C.BUTTON_ATTACK) end
	if bit32.band(af, C.ACTION_TALK) ~= 0 then ucmd.buttons = bit32.bor(ucmd.buttons, C.BUTTON_TALK) end
	if bit32.band(af, C.ACTION_GESTURE) ~= 0 then ucmd.buttons = bit32.bor(ucmd.buttons, C.BUTTON_GESTURE) end
	if bit32.band(af, C.ACTION_USE) ~= 0 then ucmd.buttons = bit32.bor(ucmd.buttons, C.BUTTON_USE_HOLDABLE) end
	if bit32.band(af, C.ACTION_WALK) ~= 0 then ucmd.buttons = bit32.bor(ucmd.buttons, C.BUTTON_WALKING) end
	if bit32.band(af, C.ACTION_AFFIRMATIVE) ~= 0 then ucmd.buttons = bit32.bor(ucmd.buttons, C.BUTTON_AFFIRMATIVE) end
	if bit32.band(af, C.ACTION_NEGATIVE) ~= 0 then ucmd.buttons = bit32.bor(ucmd.buttons, C.BUTTON_NEGATIVE) end
	if bit32.band(af, C.ACTION_GETFLAG) ~= 0 then ucmd.buttons = bit32.bor(ucmd.buttons, C.BUTTON_GETFLAG) end
	if bit32.band(af, C.ACTION_GUARDBASE) ~= 0 then ucmd.buttons = bit32.bor(ucmd.buttons, C.BUTTON_GUARDBASE) end
	if bit32.band(af, C.ACTION_PATROL) ~= 0 then ucmd.buttons = bit32.bor(ucmd.buttons, C.BUTTON_PATROL) end
	if bit32.band(af, C.ACTION_FOLLOWME) ~= 0 then ucmd.buttons = bit32.bor(ucmd.buttons, C.BUTTON_FOLLOWME) end

	ucmd.weapon = bi.weapon
	-- NOTE: the ucmd.angles are the angles WITHOUT the delta angles
	ucmd.angles[C.PITCH] = Q.ANGLE2SHORT(bi.viewangles[C.PITCH])
	ucmd.angles[C.YAW] = Q.ANGLE2SHORT(bi.viewangles[C.YAW])
	ucmd.angles[C.ROLL] = Q.ANGLE2SHORT(bi.viewangles[C.ROLL])
	for j = 0, 2 do
		local temp = ucmd.angles[j] - delta_angles[j]
		temp = ((temp + 32768) % 65536) - 32768
		ucmd.angles[j] = temp
	end
	if bi.dir[2] ~= 0 then
		angles[C.PITCH] = bi.viewangles[C.PITCH]
	else
		angles[C.PITCH] = 0
	end
	angles[C.YAW] = bi.viewangles[C.YAW]
	angles[C.ROLL] = 0
	Q.AngleVectors(angles, forward, right, nil)
	bi.speed = bi.speed * 127 / 400
	local f = Q.DotProduct(forward, bi.dir)
	local r = Q.DotProduct(right, bi.dir)
	local u = math.abs(forward[2]) * bi.dir[2]
	local m = math.abs(f)

	if math.abs(r) > m then
		m = math.abs(r)
	end

	if math.abs(u) > m then
		m = math.abs(u)
	end

	if m > 0 then
		f *= bi.speed / m
		r *= bi.speed / m
		u *= bi.speed / m
	end

	ucmd.forwardmove = Q.schar(f)
	ucmd.rightmove = Q.schar(r)
	ucmd.upmove = Q.schar(u)

	if bit32.band(af, C.ACTION_MOVEFORWARD) ~= 0 then ucmd.forwardmove = 127 end
	if bit32.band(af, C.ACTION_MOVEBACK) ~= 0 then ucmd.forwardmove = -127 end
	if bit32.band(af, C.ACTION_MOVELEFT) ~= 0 then ucmd.rightmove = -127 end
	if bit32.band(af, C.ACTION_MOVERIGHT) ~= 0 then ucmd.rightmove = 127 end
	if bit32.band(af, C.ACTION_JUMP) ~= 0 then ucmd.upmove = 127 end
	if bit32.band(af, C.ACTION_CROUCH) ~= 0 then ucmd.upmove = -127 end
end

function G.BotUpdateInput(bs, time, elapsed_time)
	local bi = S.bot_input_t()

	for j = 0, 2 do
		bs.viewangles[j] = Q.AngleMod(bs.viewangles[j] + Q.SHORT2ANGLE(bs.cur_ps.delta_angles[j]))
	end
	G.BotChangeViewAngles(bs, elapsed_time / 1000)
	G.trap_EA_GetInput(bs.client, time / 1000, bi)
	if bit32.band(bi.actionflags, C.ACTION_RESPAWN) ~= 0 then
		if bit32.band(bs.lastucmd.buttons, C.BUTTON_ATTACK) ~= 0 then
			bi.actionflags = bit32.band(bi.actionflags, bit32.bnot(bit32.bor(C.ACTION_RESPAWN, C.ACTION_ATTACK)))
		end
	end
	G.BotInputToUserCommand(bi, bs.lastucmd, bs.cur_ps.delta_angles, time)
	for j = 0, 2 do
		bs.viewangles[j] = Q.AngleMod(bs.viewangles[j] - Q.SHORT2ANGLE(bs.cur_ps.delta_angles[j]))
	end
end

function G.BotAIRegularUpdate()
	if G.regularupdate_time < G.floattime then
		G.trap_BotUpdateEntityItems()
		G.regularupdate_time = G.floattime + 0.3
	end
end

function G.RemoveColorEscapeSequences(text)
	local out = ""
	local i = 0
	while i < #text do
		if QS.Q_IsColorString(text, i + 1) then
			i += 2
			continue
		end
		local c = string.byte(text, i + 1)
		if c > 0x7E then
			i += 1
			continue
		end
		out = out .. string.sub(text, i + 1, i + 1)
		i += 1
	end
	return out
end

function G.BotAI(client, thinktime)
	G.trap_EA_ResetInput(client)

	local bs = G.botstates[client]
	if bs == nil or bs.inuse == 0 then
		G.BotAI_Print(C.PRT_FATAL, "BotAI: client %d is not setup\n", client)
		return 0
	end

	if isFalse(G.BotAI_GetClientState(client, bs.cur_ps)) then
		G.BotAI_Print(C.PRT_FATAL, "BotAI: failed to get player state for player %d\n", client)
		return 0
	end

	while true do
		local ok, buf = G.trap_BotGetServerCommand(client, 1024)
		if isFalse(ok) then break end
		local idx = QS.strchr(buf, " ")
		if idx == nil then continue end
		local args = string.sub(buf, idx + 1)
		buf = string.sub(buf, 1, idx - 1)

		args = G.RemoveColorEscapeSequences(args)

		if QS.Q_strequal(buf, "print") then
			args = string.sub(args, 2)
			args = string.sub(args, 1, #args - 1)
			G.trap_BotQueueConsoleMessage(bs.cs, C.CMS_NORMAL, args)
		elseif QS.Q_strequal(buf, "chat") then
			args = string.sub(args, 2)
			args = string.sub(args, 1, #args - 1)
			G.trap_BotQueueConsoleMessage(bs.cs, C.CMS_CHAT, args)
		elseif QS.Q_strequal(buf, "tchat") then
			args = string.sub(args, 2)
			args = string.sub(args, 1, #args - 1)
			G.trap_BotQueueConsoleMessage(bs.cs, C.CMS_CHAT, args)
		end
	end
	for j = 0, 2 do
		bs.viewangles[j] = Q.AngleMod(bs.viewangles[j] + Q.SHORT2ANGLE(bs.cur_ps.delta_angles[j]))
	end
	bs.ltime += thinktime
	bs.thinktime = thinktime
	Q.VectorCopy(bs.cur_ps.origin, bs.origin)
	Q.VectorCopy(bs.cur_ps.origin, bs.eye)
	bs.eye[2] += bs.cur_ps.viewheight
	bs.areanum = G.BotPointAreaNum(bs.origin)
	G.BotDeathmatchAI(bs, thinktime)
	G.trap_EA_SelectWeapon(bs.client, bs.weaponnum)
	for j = 0, 2 do
		bs.viewangles[j] = Q.AngleMod(bs.viewangles[j] - Q.SHORT2ANGLE(bs.cur_ps.delta_angles[j]))
	end
	return 1
end

function G.BotScheduleBotThink()
	local botnum = 0

	for i = 0, C.MAX_CLIENTS - 1 do
		local b = G.botstates[i]
		if b == nil or b.inuse == 0 then
			continue
		end
		b.botthink_residual = Q.idiv(G.bot_thinktime.integer * botnum, G.numbots)
		botnum += 1
	end
end

function G.BotWriteSessionData(bs)
	local g = bs.lastgoal_teamgoal
	local s = QS.va(
		"%i %i %i %i %i %i %i %i"
		.. " %f %f %f"
		.. " %f %f %f"
		.. " %f %f %f"
		.. " %f",
		bs.lastgoal_decisionmaker,
		bs.lastgoal_ltgtype,
		bs.lastgoal_teammate,
		g.areanum,
		g.entitynum,
		g.flags,
		g.iteminfo,
		g.number,
		g.origin[0],
		g.origin[1],
		g.origin[2],
		g.mins[0],
		g.mins[1],
		g.mins[2],
		g.maxs[0],
		g.maxs[1],
		g.maxs[2],
		bs.formation_dist
	)

	local var = QS.va("botsession%i", bs.client)

	G.trap_Cvar_Set(var, s)
end

return nil
