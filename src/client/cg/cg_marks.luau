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
-- This part covers C lines 1-398 of the 0.8.8 source (mark polys); the particle system is in cg_marks2/cg_marks3.
-- cg_marks.c -- wall marks

local G = require(script.Parent.G)
local C = require(script.Parent.Parent.q.Consts)
local Q = require(script.Parent.Parent.q.Q)
local T = require(script.Parent.Parent.q.Types)
local trap = require(script.Parent.Parent.sys.Trap)

-- MARK POLYS

G.cg_activeMarkPolys = T.markPoly_t() -- double linked list
G.cg_freeMarkPolys = nil -- single linked list
G.cg_markPolys = {}
for i = 0, C.MAX_MARK_POLYS - 1 do
	G.cg_markPolys[i] = T.markPoly_t()
end
G.markTotal = 0

local function byte(x: number): number
	return bit32.band(Q.int(x), 255)
end

-- This is called at startup and for tournement restarts
function G.CG_InitMarkPolys()
	local polys = G.cg_markPolys
	for i = 0, C.MAX_MARK_POLYS - 1 do
		T.reset(polys[i], T.markPoly_t)
	end

	local active = G.cg_activeMarkPolys
	active.nextMark = active
	active.prevMark = active
	G.cg_freeMarkPolys = polys[0]
	for i = 0, C.MAX_MARK_POLYS - 2 do
		polys[i].nextMark = polys[i + 1]
	end
end

function G.CG_FreeMarkPoly(le)
	if le.prevMark == nil then
		G.CG_Error("CG_FreeLocalEntity: not active")
	end

	-- remove from the doubly linked active list
	le.prevMark.nextMark = le.nextMark
	le.nextMark.prevMark = le.prevMark

	-- the free list is only singly linked
	le.nextMark = G.cg_freeMarkPolys
	G.cg_freeMarkPolys = le
end

-- Will allways succeed, even if it requires freeing an old active mark
function G.CG_AllocMark()
	local active = G.cg_activeMarkPolys

	if G.cg_freeMarkPolys == nil then
		-- no free entities, so free the one at the end of the chain
		-- remove the oldest active entity
		local time = active.prevMark.time
		while active.prevMark ~= nil and time == active.prevMark.time do
			G.CG_FreeMarkPoly(active.prevMark)
		end
	end

	local le = G.cg_freeMarkPolys
	G.cg_freeMarkPolys = le.nextMark

	T.reset(le, T.markPoly_t)

	-- link into the active list
	le.nextMark = active.nextMark
	le.prevMark = active
	active.nextMark.prevMark = le
	active.nextMark = le
	return le
end

--[[
origin should be a point within a unit of the plane
dir should be the plane normal

temporary marks will not be stored or randomly oriented, but immediately
passed to the renderer.
]]
local MAX_MARK_FRAGMENTS = 128
local MAX_MARK_POINTS = 384

function G.CG_ImpactMark(markShader, origin, dir, orientation, red, green, blue, alpha, alphaFade, radius, temporary)
	if G.cg_addMarks.integer == 0 then
		return
	end

	if radius <= 0 then
		G.CG_Error("CG_ImpactMark called with <= 0 radius")
	end

	-- create the texture axis
	local axis = { [0] = Q.vec3(0, 0, 0), [1] = Q.vec3(0, 0, 0), [2] = Q.vec3(0, 0, 0) }
	Q.VectorNormalize2(dir, axis[0])
	Q.PerpendicularVector(axis[1], axis[0])
	if G.cg_leiEnhancement.integer ~= 0 then -- LEILEI HACK HACK HACK - don't spin atlas variated particles (for consistent lighting on the texture)
		orientation = 90
	end

	Q.RotatePointAroundVector(axis[2], axis[0], axis[1], orientation)
	Q.CrossProduct(axis[0], axis[2], axis[1])

	local texCoordScale = 0.5 * 1.0 / radius

	-- create the full polygon
	local originalPoints = {}
	for i = 0, 3 do
		originalPoints[i] = Q.vec3(0, 0, 0)
	end
	for i = 0, 2 do
		originalPoints[0][i] = origin[i] - radius * axis[1][i] - radius * axis[2][i]
		originalPoints[1][i] = origin[i] + radius * axis[1][i] - radius * axis[2][i]
		originalPoints[2][i] = origin[i] + radius * axis[1][i] + radius * axis[2][i]
		originalPoints[3][i] = origin[i] - radius * axis[1][i] + radius * axis[2][i]
	end

	-- get the fragments
	local markPoints = {}
	for i = 0, MAX_MARK_POINTS - 1 do
		markPoints[i] = Q.vec3(0, 0, 0)
	end
	local markFragments = {}
	for i = 0, MAX_MARK_FRAGMENTS - 1 do
		markFragments[i] = T.markFragment_t()
	end
	local projection = Q.vec3(0, 0, 0)
	Q.VectorScale(dir, -20, projection)
	local numFragments = trap.CM_MarkFragments(
		4,
		originalPoints,
		projection,
		MAX_MARK_POINTS,
		markPoints,
		MAX_MARK_FRAGMENTS,
		markFragments
	)

	local colors = { [0] = byte(red * 255), byte(green * 255), byte(blue * 255), byte(alpha * 255) }

	for i = 0, numFragments - 1 do
		local mf = markFragments[i]
		local verts = {}

		-- we have an upper limit on the complexity of polygons
		-- that we store persistantly
		if mf.numPoints > C.MAX_VERTS_ON_POLY then
			mf.numPoints = C.MAX_VERTS_ON_POLY
		end
		for j = 0, mf.numPoints - 1 do
			local v = T.polyVert_t()
			verts[j] = v
			local delta = Q.vec3(0, 0, 0)

			Q.VectorCopy(markPoints[mf.firstPoint + j], v.xyz)

			Q.VectorSubtract(v.xyz, origin, delta)
			v.st[0] = 0.5 + Q.DotProduct(delta, axis[1]) * texCoordScale
			v.st[1] = 0.5 + Q.DotProduct(delta, axis[2]) * texCoordScale
			for k = 0, 3 do
				v.modulate[k] = colors[k]
			end
		end

		-- if it is a temporary (shadow) mark, add it immediately and forget about it
		if temporary then
			trap.R_AddPolyToScene(markShader, mf.numPoints, verts)
			continue
		end

		-- otherwise save it persistantly
		local mark = G.CG_AllocMark()
		mark.time = G.cg.time
		mark.alphaFade = alphaFade
		mark.markShader = markShader
		mark.poly.numVerts = mf.numPoints
		mark.color[0] = red
		mark.color[1] = green
		mark.color[2] = blue
		mark.color[3] = alpha
		for j = 0, mf.numPoints - 1 do
			T.assign(mark.verts[j], verts[j])
		end
		G.markTotal += 1
	end
end

local MARK_TOTAL_TIME = 10000
local MARK_FADE_TIME = 1000

function G.CG_AddMarks()
	if G.cg_addMarks.integer == 0 then
		return
	end

	local active = G.cg_activeMarkPolys
	local cg = G.cg
	local mp = active.nextMark
	while mp ~= active do
		-- grab next now, so if the local entity is freed we
		-- still have it
		local nextMp = mp.nextMark

		-- see if it is time to completely remove it
		if cg.time > mp.time + MARK_TOTAL_TIME then
			G.CG_FreeMarkPoly(mp)
			mp = nextMp
			continue
		end

		-- fade out the energy bursts
		if mp.markShader == G.cgs.media.energyMarkShader then
			local fade = Q.int(450 - 450 * ((cg.time - mp.time) / 3000.0))
			if fade < 255 then
				if fade < 0 then
					fade = 0
				end
				if mp.verts[0].modulate[0] ~= 0 then
					for j = 0, mp.poly.numVerts - 1 do
						local m = mp.verts[j].modulate
						m[0] = byte(mp.color[0] * fade)
						m[1] = byte(mp.color[1] * fade)
						m[2] = byte(mp.color[2] * fade)
					end
				end
			end
		end

		-- fade all marks out with time
		local t = mp.time + MARK_TOTAL_TIME - cg.time
		if t < MARK_FADE_TIME then
			local fade = Q.idiv(255 * t, MARK_FADE_TIME)
			if mp.alphaFade then
				for j = 0, mp.poly.numVerts - 1 do
					mp.verts[j].modulate[3] = bit32.band(fade, 255)
				end
			else
				for j = 0, mp.poly.numVerts - 1 do
					local m = mp.verts[j].modulate
					m[0] = byte(mp.color[0] * fade)
					m[1] = byte(mp.color[1] * fade)
					m[2] = byte(mp.color[2] * fade)
				end
			end
		end

		trap.R_AddPolyToScene(mp.markShader, mp.poly.numVerts, mp.verts)
		mp = nextMp
	end
end

return G
