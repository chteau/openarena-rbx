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
-- This part covers C lines 399-1562 of the 0.8.8 source.

local G = require(script.Parent.G)
local C = require(script.Parent.Parent.q.Consts)
local Q = require(script.Parent.Parent.q.Q)
local T = require(script.Parent.Parent.q.Types)
local trap = require(script.Parent.Parent.sys.Trap)

local P_WEATHER = C.P_WEATHER or 1
local P_FLAT = C.P_FLAT or 2
local P_SMOKE = C.P_SMOKE or 3
local P_WEATHER_TURBULENT = C.P_WEATHER_TURBULENT or 5
local P_ANIM = C.P_ANIM or 6
local P_BAT = C.P_BAT or 7
local P_BLEED = C.P_BLEED or 8
local P_FLAT_SCALEUP = C.P_FLAT_SCALEUP or 9
local P_FLAT_SCALEUP_FADE = C.P_FLAT_SCALEUP_FADE or 10
local P_WEATHER_FLURRY = C.P_WEATHER_FLURRY or 11
local P_SMOKE_IMPACT = C.P_SMOKE_IMPACT or 12
local P_BUBBLE = C.P_BUBBLE or 13
local P_BUBBLE_TURBULENT = C.P_BUBBLE_TURBULENT or 14
local P_SPRITE = C.P_SPRITE or 15
local BLOODRED = C.BLOODRED or 2
local EMISIVEFADE = C.EMISIVEFADE or 3
local GREY75 = C.GREY75 or 4

local MAX_SHADER_ANIMS = 32
local MAX_SHADER_ANIM_FRAMES = 64

local function newParticle()
	return {
		next = nil,
		time = 0,
		endtime = 0,
		startfade = 0,
		org = Q.vec3(0, 0, 0),
		vel = Q.vec3(0, 0, 0),
		accel = Q.vec3(0, 0, 0),
		color = 0,
		colorvel = 0,
		alpha = 0,
		alphavel = 0,
		type = 0,
		pshader = 0,
		height = 0,
		width = 0,
		endheight = 0,
		endwidth = 0,
		start = 0,
		end_ = 0,
		startfade_ = 0,
		rotate = false,
		snum = 0,
		link = false,
		shaderAnim = 0,
		roll = 0,
		accumroll = 0,
	}
end
G.cparticle_t = newParticle

G.cl_numparticles = 1024
G.particles = {}
for i = 0, G.cl_numparticles - 1 do
	G.particles[i] = newParticle()
end
G.active_particles = nil
G.free_particles = nil
G.numparticles = 0
G.initparticles = false
G.vforward = Q.vec3(0, 0, 0)
G.vright = Q.vec3(0, 0, 0)
G.vup = Q.vec3(0, 0, 0)
G.rforward = Q.vec3(0, 0, 0)
G.rright = Q.vec3(0, 0, 0)
G.rup = Q.vec3(0, 0, 0)
G.pvforward = Q.vec3(0, 0, 0)
G.pvright = Q.vec3(0, 0, 0)
G.pvup = Q.vec3(0, 0, 0)
G.oldtime = 0
G.roll = 0.0

G.shaderAnimNames = { [0] = "explode1", "blacksmokeanim", "twiltb2", "expblue", "blacksmokeanimb", "blood" }
G.shaderAnimCounts = { [0] = 23, 25, 45, 25, 23, 5 }
G.shaderAnimSTRatio = { [0] = 1, 1, 1, 1, 1, 1 }
G.numShaderAnims = 0
G.shaderAnims = {}
for i = 0, MAX_SHADER_ANIMS - 1 do
	local row = {}
	for j = 0, MAX_SHADER_ANIM_FRAMES - 1 do
		row[j] = 0
	end
	G.shaderAnims[i] = row
end

local function byte(x: number): number
	return bit32.band(Q.int(x), 255)
end

local function setVert(v, point, s, t, r, g, b, a)
	Q.VectorCopy(point, v.xyz)
	v.st[0] = s
	v.st[1] = t
	v.modulate[0] = byte(r)
	v.modulate[1] = byte(g)
	v.modulate[2] = byte(b)
	v.modulate[3] = byte(a)
end

local function takeParticle()
	local p = G.free_particles
	G.free_particles = p.next
	p.next = G.active_particles
	G.active_particles = p
	p.time = G.cg.time
	return p
end

local function freeParticle(p)
	p.next = G.free_particles
	G.free_particles = p
	p.type = 0
	p.color = 0
	p.alpha = 0
end

function G.CG_ClearParticles()
	local n = G.cl_numparticles
	for i = 0, n - 1 do
		G.particles[i] = newParticle()
	end

	G.free_particles = G.particles[0]
	G.active_particles = nil

	for i = 0, n - 1 do
		G.particles[i].next = G.particles[i + 1]
		G.particles[i].type = 0
	end
	G.particles[n - 1].next = nil

	G.oldtime = G.cg.time

	-- Ridah, init the shaderAnims
	local i = 0
	while G.shaderAnimNames[i] ~= nil do
		for j = 0, G.shaderAnimCounts[i] - 1 do
			G.shaderAnims[i][j] = trap.R_RegisterShader(Q.va("%s%i", G.shaderAnimNames[i], j + 1))
		end
		i += 1
	end
	G.numShaderAnims = i

	G.initparticles = true
end

function G.CG_AddParticleToScene(p, org, alpha)
	local cg = G.cg
	local pvup, pvright = G.pvup, G.pvright
	local point = Q.vec3(0, 0, 0)
	local verts = { [0] = T.polyVert_t(), T.polyVert_t(), T.polyVert_t(), T.polyVert_t() }
	local TRIverts = { [0] = T.polyVert_t(), T.polyVert_t(), T.polyVert_t() }
	local color = Q.vec3(0, 0, 0)
	local rright2 = Q.vec3(0, 0, 0)
	local rup2 = Q.vec3(0, 0, 0)
	local ptype = p.type

	if
		ptype == P_WEATHER
		or ptype == P_WEATHER_TURBULENT
		or ptype == P_WEATHER_FLURRY
		or ptype == P_BUBBLE
		or ptype == P_BUBBLE_TURBULENT
	then
		-- create a front facing polygon
		if ptype ~= P_WEATHER_FLURRY then
			if ptype == P_BUBBLE or ptype == P_BUBBLE_TURBULENT then
				if org[2] > p.end_ then
					p.time = cg.time
					Q.VectorCopy(org, p.org) -- Ridah, fixes rare snow flakes that flicker on the ground

					p.org[2] = (p.start + Q.crandom() * 4)

					if ptype == P_BUBBLE_TURBULENT then
						p.vel[0] = Q.crandom() * 4
						p.vel[1] = Q.crandom() * 4
					end
				end
			else
				if org[2] < p.end_ then
					p.time = cg.time
					Q.VectorCopy(org, p.org) -- Ridah, fixes rare snow flakes that flicker on the ground

					while p.org[2] < p.end_ do
						p.org[2] += (p.start - p.end_)
					end

					if ptype == P_WEATHER_TURBULENT then
						p.vel[0] = Q.crandom() * 16
						p.vel[1] = Q.crandom() * 16
					end
				end
			end

			-- Rafael snow pvs check
			if not p.link then
				return
			end

			p.alpha = 1
		end

		-- Ridah, had to do this or MAX_POLYS is being exceeded in village1.bsp
		if Q.Distance(cg.snap.ps.origin, org) > 1024 then
			return
		end

		if ptype == P_BUBBLE or ptype == P_BUBBLE_TURBULENT then
			local a = 255 * p.alpha
			Q.VectorMA(org, -p.height, pvup, point)
			Q.VectorMA(point, -p.width, pvright, point)
			setVert(verts[0], point, 0, 0, 255, 255, 255, a)

			Q.VectorMA(org, -p.height, pvup, point)
			Q.VectorMA(point, p.width, pvright, point)
			setVert(verts[1], point, 0, 1, 255, 255, 255, a)

			Q.VectorMA(org, p.height, pvup, point)
			Q.VectorMA(point, p.width, pvright, point)
			setVert(verts[2], point, 1, 1, 255, 255, 255, a)

			Q.VectorMA(org, p.height, pvup, point)
			Q.VectorMA(point, -p.width, pvright, point)
			setVert(verts[3], point, 1, 0, 255, 255, 255, a)
		else
			local a = 255 * p.alpha
			Q.VectorMA(org, -p.height, pvup, point)
			Q.VectorMA(point, -p.width, pvright, point)
			setVert(TRIverts[0], point, 1, 0, 255, 255, 255, a)

			Q.VectorMA(org, p.height, pvup, point)
			Q.VectorMA(point, -p.width, pvright, point)
			setVert(TRIverts[1], point, 0, 0, 255, 255, 255, a)

			Q.VectorMA(org, p.height, pvup, point)
			Q.VectorMA(point, p.width, pvright, point)
			setVert(TRIverts[2], point, 0, 1, 255, 255, 255, a)
		end
	elseif ptype == P_SPRITE then
		local rr = Q.vec3(0, 0, 0)
		local ru = Q.vec3(0, 0, 0)
		local rotate_ang = Q.vec3(0, 0, 0)

		Q.VectorSet(color, 1.0, 1.0, 0.5)
		local time = cg.time - p.time
		local time2 = p.endtime - p.time
		local ratio = time / time2

		local width = p.width + (ratio * (p.endwidth - p.width))
		local height = p.height + (ratio * (p.endheight - p.height))

		if p.roll ~= 0 then
			Q.vectoangles(cg.refdef.viewaxis[0], rotate_ang)
			rotate_ang[C.ROLL] += p.roll
			Q.AngleVectors(rotate_ang, nil, rr, ru)
		end

		if p.roll ~= 0 then
			Q.VectorMA(org, -height, ru, point)
			Q.VectorMA(point, -width, rr, point)
		else
			Q.VectorMA(org, -height, pvup, point)
			Q.VectorMA(point, -width, pvright, point)
		end
		setVert(verts[0], point, 0, 0, 255, 255, 255, 255)

		if p.roll ~= 0 then
			Q.VectorMA(point, 2 * height, ru, point)
		else
			Q.VectorMA(point, 2 * height, pvup, point)
		end
		setVert(verts[1], point, 0, 1, 255, 255, 255, 255)

		if p.roll ~= 0 then
			Q.VectorMA(point, 2 * width, rr, point)
		else
			Q.VectorMA(point, 2 * width, pvright, point)
		end
		setVert(verts[2], point, 1, 1, 255, 255, 255, 255)

		if p.roll ~= 0 then
			Q.VectorMA(point, -2 * height, ru, point)
		else
			Q.VectorMA(point, -2 * height, pvup, point)
		end
		setVert(verts[3], point, 1, 0, 255, 255, 255, 255)
	elseif ptype == P_SMOKE or ptype == P_SMOKE_IMPACT then
		-- create a front rotating facing polygon
		if ptype == P_SMOKE_IMPACT and Q.Distance(cg.snap.ps.origin, org) > 1024 then
			return
		end

		if p.color == BLOODRED then
			Q.VectorSet(color, 0.22, 0.0, 0.0)
		elseif p.color == GREY75 then
			local len = Q.Distance(cg.snap.ps.origin, org)
			if len == 0 then
				len = 1
			end

			local val = 4096 / len
			local greyit = 0.25 * val
			if greyit > 0.5 then
				greyit = 0.5
			end

			Q.VectorSet(color, greyit, greyit, greyit)
		else
			Q.VectorSet(color, 1.0, 1.0, 1.0)
		end

		local time = cg.time - p.time
		local time2 = p.endtime - p.time
		local ratio = time / time2
		local invratio

		if cg.time > p.startfade then
			invratio = 1 - ((cg.time - p.startfade) / (p.endtime - p.startfade))

			if p.color == EMISIVEFADE then
				local fval = (invratio * invratio)
				if fval < 0 then
					fval = 0
				end
				Q.VectorSet(color, fval, fval, fval)
			end
			invratio *= p.alpha
		else
			invratio = 1 * p.alpha
		end

		if G.cgs.glconfig.hardwareType == C.GLHW_RAGEPRO then
			invratio = 1
		end

		if invratio > 1 then
			invratio = 1
		end

		local width = p.width + (ratio * (p.endwidth - p.width))
		local height = p.height + (ratio * (p.endheight - p.height))

		if ptype ~= P_SMOKE_IMPACT then
			local temp = Q.vec3(0, 0, 0)

			Q.vectoangles(G.rforward, temp)
			p.accumroll += p.roll
			temp[C.ROLL] += p.accumroll * 0.1
			Q.AngleVectors(temp, nil, rright2, rup2)
		else
			Q.VectorCopy(G.rright, rright2)
			Q.VectorCopy(G.rup, rup2)
		end

		local ia = 255 * invratio
		local cr, cgc, cb = 255 * color[0], 255 * color[1], 255 * color[2]

		if p.rotate then
			Q.VectorMA(org, -height, rup2, point)
			Q.VectorMA(point, -width, rright2, point)
		else
			Q.VectorMA(org, -p.height, pvup, point)
			Q.VectorMA(point, -p.width, pvright, point)
		end
		setVert(verts[0], point, 0, 0, cr, cgc, cb, ia)

		if p.rotate then
			Q.VectorMA(org, -height, rup2, point)
			Q.VectorMA(point, width, rright2, point)
		else
			Q.VectorMA(org, -p.height, pvup, point)
			Q.VectorMA(point, p.width, pvright, point)
		end
		setVert(verts[1], point, 0, 1, cr, cgc, cb, ia)

		if p.rotate then
			Q.VectorMA(org, height, rup2, point)
			Q.VectorMA(point, width, rright2, point)
		else
			Q.VectorMA(org, p.height, pvup, point)
			Q.VectorMA(point, p.width, pvright, point)
		end
		setVert(verts[2], point, 1, 1, cr, cgc, cb, ia)

		if p.rotate then
			Q.VectorMA(org, height, rup2, point)
			Q.VectorMA(point, -width, rright2, point)
		else
			Q.VectorMA(org, p.height, pvup, point)
			Q.VectorMA(point, -p.width, pvright, point)
		end
		setVert(verts[3], point, 1, 0, cr, cgc, cb, ia)
	elseif ptype == P_BLEED then
		local rr = Q.vec3(0, 0, 0)
		local ru = Q.vec3(0, 0, 0)
		local rotate_ang = Q.vec3(0, 0, 0)

		local a = p.alpha

		if G.cgs.glconfig.hardwareType == C.GLHW_RAGEPRO then
			a = 1
		end

		if p.roll ~= 0 then
			Q.vectoangles(cg.refdef.viewaxis[0], rotate_ang)
			rotate_ang[C.ROLL] += p.roll
			Q.AngleVectors(rotate_ang, nil, rr, ru)
		else
			Q.VectorCopy(pvup, ru)
			Q.VectorCopy(pvright, rr)
		end

		Q.VectorMA(org, -p.height, ru, point)
		Q.VectorMA(point, -p.width, rr, point)
		setVert(verts[0], point, 0, 0, 111, 19, 9, 255 * a)

		Q.VectorMA(org, -p.height, ru, point)
		Q.VectorMA(point, p.width, rr, point)
		setVert(verts[1], point, 0, 1, 111, 19, 9, 255 * a)

		Q.VectorMA(org, p.height, ru, point)
		Q.VectorMA(point, p.width, rr, point)
		setVert(verts[2], point, 1, 1, 111, 19, 9, 255 * a)

		Q.VectorMA(org, p.height, ru, point)
		Q.VectorMA(point, -p.width, rr, point)
		setVert(verts[3], point, 1, 0, 111, 19, 9, 255 * a)
	elseif ptype == P_FLAT_SCALEUP then
		if p.color == BLOODRED then
			Q.VectorSet(color, 1, 1, 1)
		else
			Q.VectorSet(color, 0.5, 0.5, 0.5)
		end

		local time = cg.time - p.time
		local time2 = p.endtime - p.time
		local ratio = time / time2

		local width = p.width + (ratio * (p.endwidth - p.width))
		local height = p.height + (ratio * (p.endheight - p.height))

		if width > p.endwidth then
			width = p.endwidth
		end

		if height > p.endheight then
			height = p.endheight
		end

		local sinR = height * math.sin(math.rad(p.roll)) * math.sqrt(2)
		local cosR = width * math.cos(math.rad(p.roll)) * math.sqrt(2)
		local cr, cgc, cb = 255 * color[0], 255 * color[1], 255 * color[2]

		Q.VectorCopy(org, verts[0].xyz)
		verts[0].xyz[0] -= sinR
		verts[0].xyz[1] -= cosR
		setVert(verts[0], verts[0].xyz, 0, 0, cr, cgc, cb, 255)

		Q.VectorCopy(org, verts[1].xyz)
		verts[1].xyz[0] -= cosR
		verts[1].xyz[1] += sinR
		setVert(verts[1], verts[1].xyz, 0, 1, cr, cgc, cb, 255)

		Q.VectorCopy(org, verts[2].xyz)
		verts[2].xyz[0] += sinR
		verts[2].xyz[1] += cosR
		setVert(verts[2], verts[2].xyz, 1, 1, cr, cgc, cb, 255)

		Q.VectorCopy(org, verts[3].xyz)
		verts[3].xyz[0] += cosR
		verts[3].xyz[1] -= sinR
		setVert(verts[3], verts[3].xyz, 1, 0, cr, cgc, cb, 255)
	elseif ptype == P_FLAT then
		Q.VectorCopy(org, verts[0].xyz)
		verts[0].xyz[0] -= p.height
		verts[0].xyz[1] -= p.width
		setVert(verts[0], verts[0].xyz, 0, 0, 255, 255, 255, 255)

		Q.VectorCopy(org, verts[1].xyz)
		verts[1].xyz[0] -= p.height
		verts[1].xyz[1] += p.width
		setVert(verts[1], verts[1].xyz, 0, 1, 255, 255, 255, 255)

		Q.VectorCopy(org, verts[2].xyz)
		verts[2].xyz[0] += p.height
		verts[2].xyz[1] += p.width
		setVert(verts[2], verts[2].xyz, 1, 1, 255, 255, 255, 255)

		Q.VectorCopy(org, verts[3].xyz)
		verts[3].xyz[0] += p.height
		verts[3].xyz[1] -= p.width
		setVert(verts[3], verts[3].xyz, 1, 0, 255, 255, 255, 255)
	elseif ptype == P_ANIM then
		-- Ridah
		local rr = Q.vec3(0, 0, 0)
		local ru = Q.vec3(0, 0, 0)
		local rotate_ang = Q.vec3(0, 0, 0)

		local time = cg.time - p.time
		local time2 = p.endtime - p.time
		local ratio = time / time2
		if ratio >= 1.0 then
			ratio = 0.9999
		end

		local width = p.width + (ratio * (p.endwidth - p.width))
		local height = p.height + (ratio * (p.endheight - p.height))

		-- if we are "inside" this sprite, don't draw
		if Q.Distance(cg.snap.ps.origin, org) < width / 1.5 then
			return
		end

		local i = p.shaderAnim
		local j = Q.int(math.floor(ratio * G.shaderAnimCounts[p.shaderAnim]))
		p.pshader = G.shaderAnims[i][j]

		if p.roll ~= 0 then
			Q.vectoangles(cg.refdef.viewaxis[0], rotate_ang)
			rotate_ang[C.ROLL] += p.roll
			Q.AngleVectors(rotate_ang, nil, rr, ru)
		end

		if p.roll ~= 0 then
			Q.VectorMA(org, -height, ru, point)
			Q.VectorMA(point, -width, rr, point)
		else
			Q.VectorMA(org, -height, pvup, point)
			Q.VectorMA(point, -width, pvright, point)
		end
		setVert(verts[0], point, 0, 0, 255, 255, 255, 255)

		if p.roll ~= 0 then
			Q.VectorMA(point, 2 * height, ru, point)
		else
			Q.VectorMA(point, 2 * height, pvup, point)
		end
		setVert(verts[1], point, 0, 1, 255, 255, 255, 255)

		if p.roll ~= 0 then
			Q.VectorMA(point, 2 * width, rr, point)
		else
			Q.VectorMA(point, 2 * width, pvright, point)
		end
		setVert(verts[2], point, 1, 1, 255, 255, 255, 255)

		if p.roll ~= 0 then
			Q.VectorMA(point, -2 * height, ru, point)
		else
			Q.VectorMA(point, -2 * height, pvup, point)
		end
		setVert(verts[3], point, 1, 0, 255, 255, 255, 255)
	end

	if p.pshader == 0 then
		return
	end

	if ptype == P_WEATHER or ptype == P_WEATHER_TURBULENT or ptype == P_WEATHER_FLURRY then
		trap.R_AddPolyToScene(p.pshader, 3, TRIverts)
	else
		trap.R_AddPolyToScene(p.pshader, 4, verts)
	end
end

function G.CG_AddParticles()
	local cg = G.cg
	local org = Q.vec3(0, 0, 0)
	local rotate_ang = Q.vec3(0, 0, 0)

	if not G.initparticles then
		G.CG_ClearParticles()
	end

	Q.VectorCopy(cg.refdef.viewaxis[0], G.pvforward)
	Q.VectorCopy(cg.refdef.viewaxis[1], G.pvright)
	Q.VectorCopy(cg.refdef.viewaxis[2], G.pvup)

	Q.vectoangles(cg.refdef.viewaxis[0], rotate_ang)
	G.roll += ((cg.time - G.oldtime) * 0.1)
	rotate_ang[C.ROLL] += (G.roll * 0.9)
	Q.AngleVectors(rotate_ang, G.rforward, G.rright, G.rup)

	G.oldtime = cg.time

	local active = nil
	local tail = nil

	local p = G.active_particles
	while p ~= nil do
		local nextp = p.next

		local time = (cg.time - p.time) * 0.001

		local alpha = p.alpha + time * p.alphavel
		if alpha <= 0 then
			-- faded out
			freeParticle(p)
			p = nextp
			continue
		end

		if p.type == P_SMOKE or p.type == P_ANIM or p.type == P_BLEED or p.type == P_SMOKE_IMPACT then
			if cg.time > p.endtime then
				freeParticle(p)
				p = nextp
				continue
			end
		end

		if p.type == P_WEATHER_FLURRY then
			if cg.time > p.endtime then
				freeParticle(p)
				p = nextp
				continue
			end
		end

		if p.type == P_FLAT_SCALEUP_FADE then
			if cg.time > p.endtime then
				freeParticle(p)
				p = nextp
				continue
			end
		end

		if (p.type == P_BAT or p.type == P_SPRITE) and p.endtime < 0 then
			-- temporary sprite
			G.CG_AddParticleToScene(p, p.org, alpha)
			freeParticle(p)
			p = nextp
			continue
		end

		p.next = nil
		if tail == nil then
			tail = p
			active = p
		else
			tail.next = p
			tail = p
		end

		if alpha > 1.0 then
			alpha = 1
		end

		local time2 = time * time

		org[0] = p.org[0] + p.vel[0] * time + p.accel[0] * time2
		org[1] = p.org[1] + p.vel[1] * time + p.accel[1] * time2
		org[2] = p.org[2] + p.vel[2] * time + p.accel[2] * time2

		G.CG_AddParticleToScene(p, org, alpha)
		p = nextp
	end

	G.active_particles = active
end

function G.CG_ParticleSnowFlurry(pshader, cent)
	local turb = true

	if pshader == 0 then
		G.CG_Printf("CG_ParticleSnowFlurry pshader == ZERO!\n")
	end

	if G.free_particles == nil then
		return
	end
	local p = takeParticle()
	p.color = 0
	p.alpha = 0.90
	p.alphavel = 0

	p.start = cent.currentState.origin2[0]
	p.end_ = cent.currentState.origin2[1]

	p.endtime = G.cg.time + cent.currentState.time
	p.startfade = G.cg.time + cent.currentState.time2

	p.pshader = pshader

	if Q.rand() % 100 > 90 then
		p.height = 32
		p.width = 32
		p.alpha = 0.10
	else
		p.height = 1
		p.width = 1
	end

	p.vel[2] = -20

	p.type = P_WEATHER_FLURRY

	if turb then
		p.vel[2] = -10
	end

	Q.VectorCopy(cent.currentState.origin, p.org)

	p.vel[0] = 0
	p.vel[1] = 0

	p.accel[0] = 0
	p.accel[1] = 0
	p.accel[2] = 0

	p.vel[0] += cent.currentState.angles[0] * 32 + (Q.crandom() * 16)
	p.vel[1] += cent.currentState.angles[1] * 32 + (Q.crandom() * 16)
	p.vel[2] += cent.currentState.angles[2]

	if turb then
		p.accel[0] = Q.crandom() * 16
		p.accel[1] = Q.crandom() * 16
	end
end

function G.CG_ParticleSnow(pshader, origin, origin2, turb, range, snum)
	if pshader == 0 then
		G.CG_Printf("CG_ParticleSnow pshader == ZERO!\n")
	end

	if G.free_particles == nil then
		return
	end
	local p = takeParticle()
	p.color = 0
	p.alpha = 0.40
	p.alphavel = 0
	p.start = origin[2]
	p.end_ = origin2[2]
	p.pshader = pshader
	p.height = 1
	p.width = 1

	p.vel[2] = -50

	if turb ~= 0 then
		p.type = P_WEATHER_TURBULENT
		p.vel[2] = -50 * 1.3
	else
		p.type = P_WEATHER
	end

	Q.VectorCopy(origin, p.org)

	p.org[0] = p.org[0] + (Q.crandom() * range)
	p.org[1] = p.org[1] + (Q.crandom() * range)
	p.org[2] = p.org[2] + (Q.crandom() * (p.start - p.end_))

	p.vel[0] = 0
	p.vel[1] = 0

	p.accel[0] = 0
	p.accel[1] = 0
	p.accel[2] = 0

	if turb ~= 0 then
		p.vel[0] = Q.crandom() * 16
		p.vel[1] = Q.crandom() * 16
	end

	-- Rafael snow pvs check
	p.snum = snum
	p.link = true
end

function G.CG_ParticleBubble(pshader, origin, origin2, turb, range, snum)
	if pshader == 0 then
		G.CG_Printf("CG_ParticleSnow pshader == ZERO!\n")
	end

	if G.free_particles == nil then
		return
	end
	local p = takeParticle()
	p.color = 0
	p.alpha = 0.40
	p.alphavel = 0
	p.start = origin[2]
	p.end_ = origin2[2]
	p.pshader = pshader

	local randsize = 1 + (Q.crandom() * 0.5)

	p.height = randsize
	p.width = randsize

	p.vel[2] = 50 + (Q.crandom() * 10)

	if turb ~= 0 then
		p.type = P_BUBBLE_TURBULENT
		p.vel[2] = 50 * 1.3
	else
		p.type = P_BUBBLE
	end

	Q.VectorCopy(origin, p.org)

	p.org[0] = p.org[0] + (Q.crandom() * range)
	p.org[1] = p.org[1] + (Q.crandom() * range)
	p.org[2] = p.org[2] + (Q.crandom() * (p.start - p.end_))

	p.vel[0] = 0
	p.vel[1] = 0

	p.accel[0] = 0
	p.accel[1] = 0
	p.accel[2] = 0

	if turb ~= 0 then
		p.vel[0] = Q.crandom() * 4
		p.vel[1] = Q.crandom() * 4
	end

	-- Rafael snow pvs check
	p.snum = snum
	p.link = true
end

function G.CG_ParticleSmoke(pshader, cent)
	if pshader == 0 then
		G.CG_Printf("CG_ParticleSmoke == ZERO!\n")
	end

	if G.free_particles == nil then
		return
	end
	local p = takeParticle()

	p.endtime = G.cg.time + cent.currentState.time
	p.startfade = G.cg.time + cent.currentState.time2

	p.color = 0
	p.alpha = 1.0
	p.alphavel = 0
	p.start = cent.currentState.origin[2]
	p.end_ = cent.currentState.origin2[2]
	p.pshader = pshader
	p.rotate = false
	p.height = 8
	p.width = 8
	p.endheight = 32
	p.endwidth = 32
	p.type = P_SMOKE

	Q.VectorCopy(cent.currentState.origin, p.org)

	p.vel[0] = 0
	p.vel[1] = 0
	p.accel[0] = 0
	p.accel[1] = 0
	p.accel[2] = 0

	p.vel[2] = 5

	if cent.currentState.frame == 1 then -- reverse gravity
		p.vel[2] *= -1
	end

	p.roll = 8 + (Q.crandom() * 4)
end

function G.CG_ParticleBulletDebris(org, vel, duration)
	if G.free_particles == nil then
		return
	end
	local p = takeParticle()

	p.endtime = G.cg.time + duration
	p.startfade = G.cg.time + Q.idiv(duration, 2)

	p.color = EMISIVEFADE
	p.alpha = 1.0
	p.alphavel = 0

	p.height = 0.5
	p.width = 0.5
	p.endheight = 0.5
	p.endwidth = 0.5

	p.pshader = G.cgs.media.tracerShader

	p.type = P_SMOKE

	Q.VectorCopy(org, p.org)

	p.vel[0] = vel[0]
	p.vel[1] = vel[1]
	p.vel[2] = vel[2]
	p.accel[0] = 0
	p.accel[1] = 0
	p.accel[2] = 0

	p.accel[2] = -60
	p.vel[2] += -20
end

function G.CG_ParticleExplosion(animStr, origin, vel, duration, sizeStart, sizeEnd)
	if type(animStr) ~= "string" then
		G.CG_Error("CG_ParticleExplosion: animStr is probably an index rather than a string")
	end

	-- find the animation string
	local anim = 0
	while G.shaderAnimNames[anim] ~= nil do
		if Q.stricmp(animStr, G.shaderAnimNames[anim]) == 0 then
			break
		end
		anim += 1
	end
	if G.shaderAnimNames[anim] == nil then
		G.CG_Error(Q.va("CG_ParticleExplosion: unknown animation string: %s\n", animStr))
		return
	end

	if G.free_particles == nil then
		return
	end
	local p = takeParticle()
	p.alpha = 0.5
	p.alphavel = 0

	if duration < 0 then
		duration *= -1
		p.roll = 0
	else
		p.roll = Q.crandom() * 179
	end

	p.shaderAnim = anim

	p.width = sizeStart
	p.height = sizeStart * G.shaderAnimSTRatio[anim] -- for sprites that are stretch in either direction

	p.endheight = sizeEnd
	p.endwidth = sizeEnd * G.shaderAnimSTRatio[anim]

	p.endtime = G.cg.time + duration

	p.type = P_ANIM

	Q.VectorCopy(origin, p.org)
	Q.VectorCopy(vel, p.vel)
	Q.VectorClear(p.accel)
end

-- Rafael Shrapnel
function G.CG_AddParticleShrapnel(le)
	return
end

return G
