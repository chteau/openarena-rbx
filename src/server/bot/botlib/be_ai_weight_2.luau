--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_ai_weight.c, part 2 of 2).

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
-- Luau port of be_ai_weight.c (botlib/be_ai_weight.c, part 2 of 2): fuzzy weight evaluation, evolution, scaling, interbreeding.

local B = require("./b_local")
local BC = require("./consts")
local Q = require("../../../shared/q_math")

local SF = B.FileStatics("be_ai_weight")

local MAX_INVENTORYVALUE = 999999
local MAX_WEIGHT_FILES = 128

function B.FindFuzzyWeight(wc, name)
	for i = 0, wc.numweights - 1 do
		if wc.weights[i].name == name then
			return i
		end
	end
	return -1
end

function B.FuzzyWeight_r(inventory, fs)
	local scale, w1, w2

	if inventory[fs.index] < fs.value then
		if fs.child ~= nil then
			return B.FuzzyWeight_r(inventory, fs.child)
		else
			return fs.weight
		end
	elseif fs.next ~= nil then
		if inventory[fs.index] < fs.next.value then
			if fs.child ~= nil then
				w1 = B.FuzzyWeight_r(inventory, fs.child)
			else
				w1 = fs.weight
			end
			if fs.next.child ~= nil then
				w2 = B.FuzzyWeight_r(inventory, fs.next.child)
			else
				w2 = fs.next.weight
			end
			if fs.next.value == MAX_INVENTORYVALUE then
				return w2
			else
				scale = (inventory[fs.index] - fs.value) / (fs.next.value - fs.value)
			end
			return (1 - scale) * w1 + scale * w2
		end
		return B.FuzzyWeight_r(inventory, fs.next)
	end
	return fs.weight
end

function B.FuzzyWeightUndecided_r(inventory, fs)
	local scale, w1, w2

	if inventory[fs.index] < fs.value then
		if fs.child ~= nil then
			return B.FuzzyWeightUndecided_r(inventory, fs.child)
		else
			return fs.minweight + Q.random() * (fs.maxweight - fs.minweight)
		end
	elseif fs.next ~= nil then
		if inventory[fs.index] < fs.next.value then
			if fs.child ~= nil then
				w1 = B.FuzzyWeightUndecided_r(inventory, fs.child)
			else
				w1 = fs.minweight + Q.random() * (fs.maxweight - fs.minweight)
			end
			if fs.next.child ~= nil then
				w2 = B.FuzzyWeight_r(inventory, fs.next.child)
			else
				w2 = fs.next.minweight + Q.random() * (fs.next.maxweight - fs.next.minweight)
			end
			if fs.next.value == MAX_INVENTORYVALUE then
				return w2
			else
				scale = (inventory[fs.index] - fs.value) / (fs.next.value - fs.value)
			end
			return (1 - scale) * w1 + scale * w2
		end
		return B.FuzzyWeightUndecided_r(inventory, fs.next)
	end
	return fs.weight
end

function B.FuzzyWeight(inventory, wc, weightnum)
	return B.FuzzyWeight_r(inventory, wc.weights[weightnum].firstseperator)
end

function B.FuzzyWeightUndecided(inventory, wc, weightnum)
	return B.FuzzyWeightUndecided_r(inventory, wc.weights[weightnum].firstseperator)
end

function B.EvolveFuzzySeperator_r(fs)
	if fs.child ~= nil then
		B.EvolveFuzzySeperator_r(fs.child)
	elseif fs.type == BC.WT_BALANCE then
		-- every once in a while an evolution leap occurs, mutation
		if Q.random() < 0.01 then
			fs.weight += Q.crandom() * (fs.maxweight - fs.minweight)
		else
			fs.weight += Q.crandom() * (fs.maxweight - fs.minweight) * 0.5
		end
		-- modify bounds if necessary because of mutation
		if fs.weight < fs.minweight then
			fs.minweight = fs.weight
		elseif fs.weight > fs.maxweight then
			fs.maxweight = fs.weight
		end
	end
	if fs.next ~= nil then
		B.EvolveFuzzySeperator_r(fs.next)
	end
end

function B.EvolveWeightConfig(config)
	for i = 0, config.numweights - 1 do
		B.EvolveFuzzySeperator_r(config.weights[i].firstseperator)
	end
end

function B.ScaleFuzzySeperator_r(fs, scale)
	if fs.child ~= nil then
		B.ScaleFuzzySeperator_r(fs.child, scale)
	elseif fs.type == BC.WT_BALANCE then
		fs.weight = (fs.maxweight + fs.minweight) * scale
		-- get the weight between bounds
		if fs.weight < fs.minweight then
			fs.weight = fs.minweight
		elseif fs.weight > fs.maxweight then
			fs.weight = fs.maxweight
		end
	end
	if fs.next ~= nil then
		B.ScaleFuzzySeperator_r(fs.next, scale)
	end
end

function B.ScaleWeight(config, name, scale)
	if scale < 0 then
		scale = 0
	elseif scale > 1 then
		scale = 1
	end
	for i = 0, config.numweights - 1 do
		if name == config.weights[i].name then
			B.ScaleFuzzySeperator_r(config.weights[i].firstseperator, scale)
			break
		end
	end
end

function B.ScaleFuzzySeperatorBalanceRange_r(fs, scale)
	if fs.child ~= nil then
		B.ScaleFuzzySeperatorBalanceRange_r(fs.child, scale)
	elseif fs.type == BC.WT_BALANCE then
		local mid = (fs.minweight + fs.maxweight) * 0.5
		-- get the weight between bounds
		fs.maxweight = mid + (fs.maxweight - mid) * scale
		fs.minweight = mid + (fs.minweight - mid) * scale
		if fs.maxweight < fs.minweight then
			fs.maxweight = fs.minweight
		end
	end
	if fs.next ~= nil then
		B.ScaleFuzzySeperatorBalanceRange_r(fs.next, scale)
	end
end

function B.ScaleFuzzyBalanceRange(config, scale)
	if scale < 0 then
		scale = 0
	elseif scale > 100 then
		scale = 100
	end
	for i = 0, config.numweights - 1 do
		B.ScaleFuzzySeperatorBalanceRange_r(config.weights[i].firstseperator, scale)
	end
end

function B.InterbreedFuzzySeperator_r(fs1, fs2, fsout)
	if fs1.child ~= nil then
		if fs2.child == nil or fsout.child == nil then
			B.botimport.Print(BC.PRT_ERROR, "cannot interbreed weight configs, unequal child\n")
			return 0
		end
		if B.InterbreedFuzzySeperator_r(fs2.child, fs2.child, fsout.child) == 0 then
			return 0
		end
	elseif fs1.type == BC.WT_BALANCE then
		if fs2.type ~= BC.WT_BALANCE or fsout.type ~= BC.WT_BALANCE then
			B.botimport.Print(BC.PRT_ERROR, "cannot interbreed weight configs, unequal balance\n")
			return 0
		end
		fsout.weight = (fs1.weight + fs2.weight) / 2
		if fsout.weight > fsout.maxweight then
			fsout.maxweight = fsout.weight
		end
		if fsout.weight > fsout.minweight then
			fsout.minweight = fsout.weight
		end
	end
	if fs1.next ~= nil then
		if fs2.next == nil or fsout.next == nil then
			B.botimport.Print(BC.PRT_ERROR, "cannot interbreed weight configs, unequal next\n")
			return 0
		end
		if B.InterbreedFuzzySeperator_r(fs1.next, fs2.next, fsout.next) == 0 then
			return 0
		end
	end
	return 1
end

-- config1 and config2 are interbreeded and stored in configout
function B.InterbreedWeightConfigs(config1, config2, configout)
	if config1.numweights ~= config2.numweights or config1.numweights ~= configout.numweights then
		B.botimport.Print(BC.PRT_ERROR, "cannot interbreed weight configs, unequal numweights\n")
		return
	end
	for i = 0, config1.numweights - 1 do
		B.InterbreedFuzzySeperator_r(
			config1.weights[i].firstseperator,
			config2.weights[i].firstseperator,
			configout.weights[i].firstseperator
		)
	end
end

function B.BotShutdownWeights()
	for i = 0, MAX_WEIGHT_FILES - 1 do
		if SF.weightFileList[i] ~= nil then
			B.FreeWeightConfig2(SF.weightFileList[i])
			SF.weightFileList[i] = nil
		end
	end
end

return nil
