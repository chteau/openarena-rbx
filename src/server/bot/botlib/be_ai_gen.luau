--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_ai_gen.c).

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
-- Luau port of be_ai_gen.c. Genetic selection of bots by their rankings.

local B = require("./b_local")
local BC = require("./consts")
local Q = require("../../../shared/q_math")

function B.GeneticSelection(numranks, rankings)
	local sum = 0
	for i = 0, numranks - 1 do
		if rankings[i] < 0 then continue end
		sum += rankings[i]
	end
	if sum > 0 then
		for i = 0, numranks - 1 do
			if rankings[i] < 0 then continue end
			sum -= rankings[i]
			if sum <= 0 then return i end
		end
	end
	local index = Q.trunc(Q.random() * numranks)
	for _ = 0, numranks - 1 do
		if rankings[index] >= 0 then return index end
		index = (index + 1) % numranks
	end
	return 0
end

function B.GeneticParentsAndChildSelection(numranks, ranks)
	if numranks > 256 then
		B.botimport.Print(BC.PRT_WARNING, "GeneticParentsAndChildSelection: too many bots\n")
		return false, 0, 0, 0
	end
	local max = 0
	for i = 0, numranks - 1 do
		if ranks[i] < 0 then continue end
		max += 1
	end
	if max < 3 then
		B.botimport.Print(BC.PRT_WARNING, "GeneticParentsAndChildSelection: too few valid bots\n")
		return false, 0, 0, 0
	end
	local rankings = {}
	for i = 0, numranks - 1 do
		rankings[i] = ranks[i]
	end
	local parent1 = B.GeneticSelection(numranks, rankings)
	rankings[parent1] = -1
	local parent2 = B.GeneticSelection(numranks, rankings)
	rankings[parent2] = -1
	max = 0
	for i = 0, numranks - 1 do
		if rankings[i] < 0 then continue end
		if rankings[i] > max then max = rankings[i] end
	end
	for i = 0, numranks - 1 do
		if rankings[i] < 0 then continue end
		rankings[i] = max - rankings[i]
	end
	local child = B.GeneticSelection(numranks, rankings)
	return true, parent1, parent2, child
end

return nil
