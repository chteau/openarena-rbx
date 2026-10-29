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
-- Luau port of code/cgame/cg_marks.c (OpenArena 0.8.8, gamecode 9e0f0c0).
-- This part covers C lines 1563-2563 of the 0.8.8 source.
-- cg_marks.c -- wall marks

local G = require(script.Parent.G)
local C = require(script.Parent.Parent.q.Consts)
local Q = require(script.Parent.Parent.q.Q)
local T = require(script.Parent.Parent.q.Types)

local EXTRUDE_DIST = 0.5
local NORMALSIZE = 16
local LARGESIZE = 32

-- takes the head of the free list and links it into the active list; nil when none is free
local function allocParticle()
	local p = G.free_particles
	if p == nil then
		return nil
	end
	G.free_particles = p.next
	p.next = G.active_particles
	G.active_particles = p
	return p
end

function G.CG_NewParticleArea(num)
	local str = G.CG_ConfigString(num)
	if str == "" then
		return 0
	end

	local tokens = {}
	for tok in string.gmatch(str, "%S+") do
		table.insert(tokens, tok)
	end
	local idx = 0
	local function nextToken(): string
		idx += 1
		return tokens[idx] or ""
	end
	local function atof(s: string): number
		return tonumber(s) or 0
	end
	local function atoi(s: string): number
		return Q.int(tonumber(s) or 0)
	end

	-- returns type 128 64 or 32
	local ptype = atoi(nextToken())
	local range = 0
	if ptype == 1 then
		range = 128
	elseif ptype == 2 then
		range = 64
	elseif ptype == 3 then
		range = 32
	elseif ptype == 0 then
		range = 256
	elseif ptype == 4 then
		range = 8
	elseif ptype == 5 then
		range = 16
	elseif ptype == 6 then
		range = 32
	elseif ptype == 7 then
		range = 64
	end

	local origin = Q.vec3(0, 0, 0)
	local origin2 = Q.vec3(0, 0, 0)
	for i = 0, 2 do
		origin[i] = atof(nextToken())
	end
	for i = 0, 2 do
		origin2[i] = atof(nextToken())
	end

	local numparticles = atoi(nextToken())
	local turb = atoi(nextToken())
	local snum = atoi(nextToken())

	for _ = 0, numparticles - 1 do
		if ptype >= 4 then
			G.CG_ParticleBubble(G.cgs.media.waterBubbleShader, origin, origin2, turb, range, snum)
		else
			G.CG_ParticleSnow(G.cgs.media.waterBubbleShader, origin, origin2, turb, range, snum)
		end
	end

	return 1
end

function G.CG_SnowLink(cent, particleOn)
	local id = cent.currentState.frame

	local p = G.active_particles
	while p ~= nil do
		local nxt = p.next

		if p.type == C.P_WEATHER or p.type == C.P_WEATHER_TURBULENT then
			if p.snum == id then
				p.link = particleOn
			end
		end

		p = nxt
	end
end

function G.CG_ParticleImpactSmokePuff(pshader, origin)
	if pshader == 0 then
		G.CG_Printf("CG_ParticleImpactSmokePuff pshader == ZERO!\n")
	end

	local p = allocParticle()
	if p == nil then
		return
	end
	local time = G.cg.time
	p.time = time
	p.alpha = 0.25
	p.alphavel = 0
	p.roll = Q.crandom() * 179

	p.pshader = pshader

	p.endtime = time + 1000
	p.startfade = time + 100

	p.width = Q.rand() % 4 + 8
	p.height = Q.rand() % 4 + 8

	p.endheight = p.height * 2
	p.endwidth = p.width * 2

	p.endtime = time + 500

	p.type = C.P_SMOKE_IMPACT

	Q.VectorCopy(origin, p.org)
	Q.VectorSet(p.vel, 0, 0, 20)
	Q.VectorSet(p.accel, 0, 0, 20)

	p.rotate = true
end

function G.CG_Particle_Bleed(pshader, start, dir, fleshEntityNum, duration)
	if pshader == 0 then
		G.CG_Printf("CG_Particle_Bleed pshader == ZERO!\n")
	end

	local p = allocParticle()
	if p == nil then
		return
	end
	local time = G.cg.time
	p.time = time
	p.alpha = 1.0
	p.alphavel = 0
	p.roll = 0

	p.pshader = pshader

	p.endtime = time + duration

	if fleshEntityNum ~= 0 then
		p.startfade = time
	else
		p.startfade = time + 100
	end

	p.width = 4
	p.height = 4

	p.endheight = 4 + Q.rand() % 3
	p.endwidth = p.endheight

	p.type = C.P_SMOKE

	Q.VectorCopy(start, p.org)
	p.vel[0] = 0
	p.vel[1] = 0
	p.vel[2] = -20
	Q.VectorClear(p.accel)

	p.rotate = false

	p.roll = Q.rand() % 179

	p.color = C.BLOODRED
	p.alpha = 0.75
end

function G.CG_Particle_OilParticle(pshader, cent)
	local duration = 1500

	local time = G.cg.time
	local time2 = G.cg.time + cent.currentState.time

	local ratio = 1 - (time / time2)

	if pshader == 0 then
		G.CG_Printf("CG_Particle_OilParticle == ZERO!\n")
	end

	local p = allocParticle()
	if p == nil then
		return
	end
	p.time = time
	p.alpha = 1.0
	p.alphavel = 0
	p.roll = 0

	p.pshader = pshader

	p.endtime = time + duration

	p.startfade = p.endtime

	p.width = 1
	p.height = 3

	p.endheight = 3
	p.endwidth = 1

	p.type = C.P_SMOKE

	Q.VectorCopy(cent.currentState.origin, p.org)

	p.vel[0] = cent.currentState.origin2[0] * (16 * ratio)
	p.vel[1] = cent.currentState.origin2[1] * (16 * ratio)
	p.vel[2] = cent.currentState.origin2[2]

	p.snum = 1.0

	Q.VectorClear(p.accel)

	p.accel[2] = -20

	p.rotate = false

	p.roll = Q.rand() % 179

	p.alpha = 0.75
end

function G.CG_Particle_OilSlick(pshader, cent)
	if pshader == 0 then
		G.CG_Printf("CG_Particle_OilSlick == ZERO!\n")
	end

	local p = allocParticle()
	if p == nil then
		return
	end
	local time = G.cg.time
	local a2 = cent.currentState.angles2
	p.time = time

	if a2[2] ~= 0 then
		p.endtime = time + a2[2]
	else
		p.endtime = time + 60000
	end

	p.startfade = p.endtime

	p.alpha = 1.0
	p.alphavel = 0
	p.roll = 0

	p.pshader = pshader

	if a2[0] ~= 0 or a2[1] ~= 0 then
		p.width = a2[0]
		p.height = a2[0]

		p.endheight = a2[1]
		p.endwidth = a2[1]
	else
		p.width = 8
		p.height = 8

		p.endheight = 16
		p.endwidth = 16
	end

	p.type = C.P_FLAT_SCALEUP

	p.snum = 1.0

	Q.VectorCopy(cent.currentState.origin, p.org)

	p.org[2] += 0.55 + (Q.crandom() * 0.5)

	p.vel[0] = 0
	p.vel[1] = 0
	p.vel[2] = 0
	Q.VectorClear(p.accel)

	p.rotate = false

	p.roll = Q.rand() % 179

	p.alpha = 0.75
end

function G.CG_OilSlickRemove(cent)
	local id = 1.0

	local p = G.active_particles
	while p ~= nil do
		local nxt = p.next

		if p.type == C.P_FLAT_SCALEUP then
			if p.snum == id then
				p.endtime = G.cg.time + 100
				p.startfade = p.endtime
				p.type = C.P_FLAT_SCALEUP_FADE
			end
		end

		p = nxt
	end
end

function G.ValidBloodPool(start)
	local angles = Q.vec3(0, 0, 0)
	local right = Q.vec3(0, 0, 0)
	local up = Q.vec3(0, 0, 0)
	local this_pos = Q.vec3(0, 0, 0)
	local x_pos = Q.vec3(0, 0, 0)
	local center_pos = Q.vec3(0, 0, 0)
	local end_pos = Q.vec3(0, 0, 0)
	local trace = T.trace_t()
	local normal = Q.vec3(0, 0, 1)

	local fwidth = 16
	local fheight = 16

	Q.vectoangles(normal, angles)
	Q.AngleVectors(angles, nil, right, up)

	Q.VectorMA(start, EXTRUDE_DIST, normal, center_pos)

	local x = -fwidth / 2
	while x < fwidth do
		Q.VectorMA(center_pos, x, right, x_pos)

		local y = -fheight / 2
		while y < fheight do
			Q.VectorMA(x_pos, y, up, this_pos)
			Q.VectorMA(this_pos, -EXTRUDE_DIST * 2, normal, end_pos)

			G.CG_Trace(trace, this_pos, nil, nil, end_pos, -1, C.CONTENTS_SOLID)

			if trace.entityNum < (C.MAX_ENTITIES - 1) then -- may only land on world
				return false
			end

			if not (not trace.startsolid and trace.fraction < 1) then
				return false
			end

			y += fheight
		end
		x += fwidth
	end

	return true
end

function G.CG_BloodPool(le, pshader, tr)
	if pshader == 0 then
		G.CG_Printf("CG_BloodPool pshader == ZERO!\n")
	end

	if G.free_particles == nil then
		return
	end

	local start = Q.vec3(0, 0, 0)
	Q.VectorCopy(tr.endpos, start)
	local legit = G.ValidBloodPool(start)

	if not legit then
		return
	end

	local p = allocParticle()
	local time = G.cg.time
	p.time = time

	p.endtime = time + 3000
	p.startfade = p.endtime

	p.alpha = 1.0
	p.alphavel = 0
	p.roll = 0

	p.pshader = pshader

	local rndSize = 0.4 + Q.random() * 0.6

	p.width = 8 * rndSize
	p.height = 8 * rndSize

	p.endheight = 16 * rndSize
	p.endwidth = 16 * rndSize

	p.type = C.P_FLAT_SCALEUP

	Q.VectorCopy(start, p.org)

	p.vel[0] = 0
	p.vel[1] = 0
	p.vel[2] = 0
	Q.VectorClear(p.accel)

	p.rotate = false

	p.roll = Q.rand() % 179

	p.alpha = 0.75

	p.color = C.BLOODRED
end

function G.CG_ParticleBloodCloud(cent, origin, dir)
	local angles = Q.vec3(0, 0, 0)
	local forward = Q.vec3(0, 0, 0)
	local point = Q.vec3(0, 0, 0)
	local dist = 0

	local length = Q.VectorLength(dir)
	Q.vectoangles(dir, angles)
	Q.AngleVectors(angles, forward, nil, nil)

	local crittersize = LARGESIZE

	if length ~= 0 then
		dist = length / crittersize
	end

	if dist < 1 then
		dist = 1
	end

	Q.VectorCopy(origin, point)

	local i = 0
	while i < dist do
		Q.VectorMA(point, crittersize, forward, point)

		local p = allocParticle()
		if p == nil then
			return
		end
		local time = G.cg.time

		p.time = time
		p.alpha = 1.0
		p.alphavel = 0
		p.roll = 0

		p.pshader = G.cgs.media.smokePuffShader

		p.endtime = time + 350 + (Q.crandom() * 100)

		p.startfade = time

		p.width = LARGESIZE
		p.height = LARGESIZE
		p.endheight = LARGESIZE
		p.endwidth = LARGESIZE

		p.type = C.P_SMOKE

		Q.VectorCopy(origin, p.org)

		p.vel[0] = 0
		p.vel[1] = 0
		p.vel[2] = -1

		Q.VectorClear(p.accel)

		p.rotate = false

		p.roll = Q.rand() % 179

		p.color = C.BLOODRED

		p.alpha = 0.75

		i += 1
	end
end

function G.CG_ParticleSparks(org, vel, duration, x, y, speed)
	local p = allocParticle()
	if p == nil then
		return
	end
	local time = G.cg.time
	p.time = time

	p.endtime = time + duration
	p.startfade = time + Q.idiv(duration, 2)

	p.color = C.EMISIVEFADE
	p.alpha = 0.4
	p.alphavel = 0

	p.height = 0.5
	p.width = 0.5
	p.endheight = 0.5
	p.endwidth = 0.5

	p.pshader = G.cgs.media.tracerShader

	p.type = C.P_SMOKE

	Q.VectorCopy(org, p.org)

	p.org[0] += Q.crandom() * x
	p.org[1] += Q.crandom() * y

	p.vel[0] = vel[0]
	p.vel[1] = vel[1]
	p.vel[2] = vel[2]

	p.accel[0] = 0
	p.accel[1] = 0
	p.accel[2] = 0

	p.vel[0] += Q.crandom() * 4
	p.vel[1] += Q.crandom() * 4
	p.vel[2] += (20 + (Q.crandom() * 10)) * speed

	p.accel[0] = Q.crandom() * 4
	p.accel[1] = Q.crandom() * 4
end

function G.CG_ParticleDust(cent, origin, dir)
	local angles = Q.vec3(0, 0, 0)
	local forward = Q.vec3(0, 0, 0)
	local point = Q.vec3(0, 0, 0)
	local dist = 0

	dir[0] = -dir[0]
	dir[1] = -dir[1]
	dir[2] = -dir[2]
	local length = Q.VectorLength(dir)
	Q.vectoangles(dir, angles)
	Q.AngleVectors(angles, forward, nil, nil)

	local crittersize = LARGESIZE

	if length ~= 0 then
		dist = length / crittersize
	end

	if dist < 1 then
		dist = 1
	end

	Q.VectorCopy(origin, point)

	local i = 0
	while i < dist do
		Q.VectorMA(point, crittersize, forward, point)

		local p = allocParticle()
		if p == nil then
			return
		end
		local time = G.cg.time

		p.time = time
		p.alpha = 5.0
		p.alphavel = 0
		p.roll = 0

		p.pshader = G.cgs.media.smokePuffShader

		-- RF, stay around for long enough to expand and dissipate naturally
		if length ~= 0 then
			p.endtime = time + 4500 + (Q.crandom() * 3500)
		else
			p.endtime = time + 750 + (Q.crandom() * 500)
		end

		p.startfade = time

		p.width = LARGESIZE
		p.height = LARGESIZE

		-- RF, expand while falling
		p.endheight = LARGESIZE * 3.0
		p.endwidth = LARGESIZE * 3.0

		if length == 0 then
			p.width *= 0.2
			p.height *= 0.2

			p.endheight = NORMALSIZE
			p.endwidth = NORMALSIZE
		end

		p.type = C.P_SMOKE

		Q.VectorCopy(point, p.org)

		p.vel[0] = Q.crandom() * 6
		p.vel[1] = Q.crandom() * 6
		p.vel[2] = Q.random() * 20

		-- RF, add some gravity/randomness
		p.accel[0] = Q.crandom() * 3
		p.accel[1] = Q.crandom() * 3
		p.accel[2] = -C.PARTICLE_GRAVITY * 0.4

		Q.VectorClear(p.accel)

		p.rotate = false

		p.roll = Q.rand() % 179

		p.alpha = 0.75

		i += 1
	end
end

function G.CG_ParticleMisc(pshader, origin, size, duration, alpha)
	if pshader == 0 then
		G.CG_Printf("CG_ParticleImpactSmokePuff pshader == ZERO!\n")
	end

	local p = allocParticle()
	if p == nil then
		return
	end
	local time = G.cg.time
	p.time = time
	p.alpha = 1.0
	p.alphavel = 0
	p.roll = Q.rand() % 179

	p.pshader = pshader

	if duration > 0 then
		p.endtime = time + duration
	else
		p.endtime = duration
	end

	p.startfade = time

	p.width = size
	p.height = size

	p.endheight = size
	p.endwidth = size

	p.type = C.P_SPRITE

	Q.VectorCopy(origin, p.org)

	p.rotate = false
end

-- LEILEI ENHANCEMENT PARTICLE EFFECTS

-- sparks!
-- for small arms
function G.CG_LeiSparks(org, vel, duration, x, y, speed)
	local p = allocParticle()
	if p == nil then
		return
	end
	local time = G.cg.time
	p.time = time

	p.endtime = time + duration
	p.startfade = time + Q.idiv(duration, 2)

	p.color = C.EMISIVEFADE
	p.alpha = 0.8
	p.alphavel = 0.8

	p.height = 4
	p.width = 4
	p.endheight = 4
	p.endwidth = 4

	p.pshader = G.cgs.media.lspkShader1

	p.type = C.P_SMOKE

	Q.VectorCopy(org, p.org)

	p.org[0] += Q.crandom() * x
	p.org[1] += Q.crandom() * y

	p.vel[0] = vel[0] * 75
	p.vel[1] = vel[1] * 75
	p.vel[2] = vel[2] * 75

	p.accel[0] = 0
	p.accel[1] = 0
	p.accel[2] = 0

	p.vel[0] += Q.crandom() * speed
	p.vel[1] += Q.crandom() * speed
	p.vel[2] += speed + (Q.crandom() * speed)

	p.vel[0] += Q.crandom() * 24
	p.vel[1] += Q.crandom() * 24
	p.vel[2] += 20 + (Q.crandom() * 180)

	p.accel[0] = Q.crandom() * 6
	p.accel[1] = Q.crandom() * 6
	p.accel[2] = -C.PARTICLE_GRAVITY * 7.2
end

-- a different sort of puff
function G.CG_LeiPuff(org, vel, duration, x, y, speed, size)
	local p = allocParticle()
	if p == nil then
		return
	end
	local time = G.cg.time
	p.time = time

	p.endtime = time + duration
	p.startfade = time + Q.idiv(duration, 2)

	p.color = C.EMISIVEFADE
	p.alpha = 0.8
	p.alphavel = 0.8

	p.height = size
	p.width = size
	p.endheight = size * 1.8
	p.endwidth = size * 1.8

	p.pshader = G.cgs.media.lspkShader1

	p.type = C.P_SMOKE

	Q.VectorCopy(org, p.org)

	p.org[0] += Q.crandom() * x
	p.org[1] += Q.crandom() * y

	p.vel[0] = vel[0] * speed
	p.vel[1] = vel[1] * speed
	p.vel[2] = vel[2] * speed

	p.accel[0] = 0
	p.accel[1] = 0
	p.accel[2] = 0

	p.vel[0] += Q.crandom() * 44
	p.vel[1] += Q.crandom() * 44
	p.vel[2] += Q.crandom() * 44
	p.roll = Q.crandom() * 256 - 128

	p.accel[0] = -2
	p.accel[1] = -2
	p.accel[2] = -2
end

-- a violent blast puff
function G.CG_LeiBlast(org, vel, duration, x, y, speed, size)
	local p = allocParticle()
	if p == nil then
		return
	end
	local time = G.cg.time
	p.time = time

	p.endtime = time + duration
	p.startfade = time + Q.idiv(duration, 2)

	p.color = C.EMISIVEFADE
	p.alpha = 1.0
	p.alphavel = 0.72

	p.height = size
	p.width = size
	p.endheight = size * 6
	p.endwidth = size * 6

	p.pshader = G.cgs.media.lbumShader1

	p.type = C.P_SMOKE

	Q.VectorCopy(org, p.org)

	p.org[0] += Q.crandom() * x
	p.org[1] += Q.crandom() * y

	p.vel[0] = vel[0] * speed
	p.vel[1] = vel[1] * speed
	p.vel[2] = vel[2] * speed

	p.accel[0] = 0
	p.accel[1] = 0
	p.accel[2] = 0

	p.vel[0] += Q.crandom() * 84
	p.vel[1] += Q.crandom() * 84
	p.vel[2] += Q.crandom() * 84
	p.roll = Q.crandom() * 256 - 128

	p.accel[0] = -2
	p.accel[1] = -2
	p.accel[2] = -2
end

-- for explosions
function G.CG_LeiSparks2(org, vel, duration, x, y, speed)
	local p = allocParticle()
	if p == nil then
		return
	end
	local time = G.cg.time
	p.time = time

	p.endtime = time + duration
	p.startfade = time + Q.idiv(duration, 2)

	p.color = C.EMISIVEFADE
	p.alpha = 0.8
	p.alphavel = 0

	p.height = 9
	p.width = 9
	p.endheight = 32
	p.endwidth = 32

	p.pshader = G.cgs.media.lspkShader1

	p.type = C.P_SMOKE

	Q.VectorCopy(org, p.org)

	p.org[0] += Q.crandom() * x
	p.org[1] += Q.crandom() * y

	p.vel[0] = vel[0] * 15
	p.vel[1] = vel[1] * 15
	p.vel[2] = vel[2] * 15

	p.accel[0] = 0
	p.accel[1] = 0
	p.accel[2] = 0

	p.vel[0] += Q.crandom() * 524
	p.vel[1] += Q.crandom() * 524
	p.vel[2] += (120 + (Q.crandom() * 780)) * speed
end

-- not so friendly water splash
function G.CG_LeiSplash2(org, vel, duration, x, y, speed)
	local p = allocParticle()
	if p == nil then
		return
	end
	local time = G.cg.time
	p.time = time

	p.endtime = time + duration
	p.startfade = time + Q.idiv(duration, 2)

	p.color = C.EMISIVEFADE
	p.alpha = 0.9
	p.alphavel = 0

	p.height = 4
	p.width = 4
	p.endheight = 2
	p.endwidth = 2

	p.pshader = G.cgs.media.lsplShader

	p.type = C.P_SMOKE

	Q.VectorCopy(org, p.org)

	p.org[0] += Q.crandom() * x
	p.org[1] += Q.crandom() * y

	p.vel[0] = vel[0] * 44
	p.vel[1] = vel[1] * 44
	p.vel[2] = vel[2] * 872

	p.accel[0] = 0
	p.accel[1] = 0
	p.accel[2] = 0

	p.vel[0] += Q.crandom() * 4
	p.vel[1] += Q.crandom() * 4
	p.vel[2] += (20 + (Q.crandom() * 10)) * speed

	p.accel[0] = Q.crandom() * 3
	p.accel[1] = Q.crandom() * 3
	p.accel[2] = -C.PARTICLE_GRAVITY * 4.2
end

return G
