--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_interface.c, part 2 of 2).

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
-- Luau port of be_interface.c, part 2 of 2: BotExportTest and the export table.

local B = require("./b_local")
local BC = require("./consts")

local BOTLIB_API_VERSION = 2

function B.BotExportTest(parm0, parm1, parm2, parm3)
	return 0
end

local function Init_AAS_Export()
	return {
		AAS_EntityInfo = B.AAS_EntityInfo,
		AAS_Initialized = B.AAS_Initialized,
		AAS_PresenceTypeBoundingBox = B.AAS_PresenceTypeBoundingBox,
		AAS_Time = B.AAS_Time,
		AAS_PointAreaNum = B.AAS_PointAreaNum,
		AAS_PointReachabilityAreaIndex = B.AAS_PointReachabilityAreaIndex,
		AAS_TraceAreas = B.AAS_TraceAreas,
		AAS_BBoxAreas = B.AAS_BBoxAreas,
		AAS_AreaInfo = B.AAS_AreaInfo,
		AAS_PointContents = B.AAS_PointContents,
		AAS_NextBSPEntity = B.AAS_NextBSPEntity,
		AAS_ValueForBSPEpairKey = B.AAS_ValueForBSPEpairKey,
		AAS_VectorForBSPEpairKey = B.AAS_VectorForBSPEpairKey,
		AAS_FloatForBSPEpairKey = B.AAS_FloatForBSPEpairKey,
		AAS_IntForBSPEpairKey = B.AAS_IntForBSPEpairKey,
		AAS_AreaReachability = B.AAS_AreaReachability,
		AAS_AreaTravelTimeToGoalArea = B.AAS_AreaTravelTimeToGoalArea,
		AAS_EnableRoutingArea = B.AAS_EnableRoutingArea,
		AAS_PredictRoute = B.AAS_PredictRoute,
		AAS_AlternativeRouteGoals = B.AAS_AlternativeRouteGoals,
		AAS_Swimming = B.AAS_Swimming,
		AAS_PredictClientMovement = B.AAS_PredictClientMovement,
	}
end

local function Init_EA_Export()
	return {
		EA_Command = B.EA_Command,
		EA_Say = B.EA_Say,
		EA_SayTeam = B.EA_SayTeam,
		EA_Action = B.EA_Action,
		EA_Gesture = B.EA_Gesture,
		EA_Talk = B.EA_Talk,
		EA_Attack = B.EA_Attack,
		EA_Use = B.EA_Use,
		EA_Respawn = B.EA_Respawn,
		EA_Crouch = B.EA_Crouch,
		EA_MoveUp = B.EA_MoveUp,
		EA_MoveDown = B.EA_MoveDown,
		EA_MoveForward = B.EA_MoveForward,
		EA_MoveBack = B.EA_MoveBack,
		EA_MoveLeft = B.EA_MoveLeft,
		EA_MoveRight = B.EA_MoveRight,
		EA_SelectWeapon = B.EA_SelectWeapon,
		EA_Jump = B.EA_Jump,
		EA_DelayedJump = B.EA_DelayedJump,
		EA_Move = B.EA_Move,
		EA_View = B.EA_View,
		EA_GetInput = B.EA_GetInput,
		EA_EndRegular = B.EA_EndRegular,
		EA_ResetInput = B.EA_ResetInput,
	}
end

local function Init_AI_Export()
	return {
		BotLoadCharacter = B.BotLoadCharacter,
		BotFreeCharacter = B.BotFreeCharacter,
		Characteristic_Float = B.Characteristic_Float,
		Characteristic_BFloat = B.Characteristic_BFloat,
		Characteristic_Integer = B.Characteristic_Integer,
		Characteristic_BInteger = B.Characteristic_BInteger,
		Characteristic_String = B.Characteristic_String,
		BotAllocChatState = B.BotAllocChatState,
		BotFreeChatState = B.BotFreeChatState,
		BotQueueConsoleMessage = B.BotQueueConsoleMessage,
		BotRemoveConsoleMessage = B.BotRemoveConsoleMessage,
		BotNextConsoleMessage = B.BotNextConsoleMessage,
		BotNumConsoleMessages = B.BotNumConsoleMessages,
		BotInitialChat = B.BotInitialChat,
		BotNumInitialChats = B.BotNumInitialChats,
		BotReplyChat = B.BotReplyChat,
		BotChatLength = B.BotChatLength,
		BotEnterChat = B.BotEnterChat,
		BotGetChatMessage = B.BotGetChatMessage,
		StringContains = B.StringContains,
		BotFindMatch = B.BotFindMatch,
		BotMatchVariable = B.BotMatchVariable,
		UnifyWhiteSpaces = B.UnifyWhiteSpaces,
		BotReplaceSynonyms = B.BotReplaceSynonyms,
		BotLoadChatFile = B.BotLoadChatFile,
		BotSetChatGender = B.BotSetChatGender,
		BotSetChatName = B.BotSetChatName,
		BotResetGoalState = B.BotResetGoalState,
		BotResetAvoidGoals = B.BotResetAvoidGoals,
		BotRemoveFromAvoidGoals = B.BotRemoveFromAvoidGoals,
		BotPushGoal = B.BotPushGoal,
		BotPopGoal = B.BotPopGoal,
		BotEmptyGoalStack = B.BotEmptyGoalStack,
		BotDumpAvoidGoals = B.BotDumpAvoidGoals,
		BotDumpGoalStack = B.BotDumpGoalStack,
		BotGoalName = B.BotGoalName,
		BotGetTopGoal = B.BotGetTopGoal,
		BotGetSecondGoal = B.BotGetSecondGoal,
		BotChooseLTGItem = B.BotChooseLTGItem,
		BotChooseNBGItem = B.BotChooseNBGItem,
		BotTouchingGoal = B.BotTouchingGoal,
		BotItemGoalInVisButNotVisible = B.BotItemGoalInVisButNotVisible,
		BotGetLevelItemGoal = B.BotGetLevelItemGoal,
		BotGetNextCampSpotGoal = B.BotGetNextCampSpotGoal,
		BotGetMapLocationGoal = B.BotGetMapLocationGoal,
		BotAvoidGoalTime = B.BotAvoidGoalTime,
		BotSetAvoidGoalTime = B.BotSetAvoidGoalTime,
		BotInitLevelItems = B.BotInitLevelItems,
		BotUpdateEntityItems = B.BotUpdateEntityItems,
		BotLoadItemWeights = B.BotLoadItemWeights,
		BotFreeItemWeights = B.BotFreeItemWeights,
		BotInterbreedGoalFuzzyLogic = B.BotInterbreedGoalFuzzyLogic,
		BotSaveGoalFuzzyLogic = B.BotSaveGoalFuzzyLogic,
		BotMutateGoalFuzzyLogic = B.BotMutateGoalFuzzyLogic,
		BotAllocGoalState = B.BotAllocGoalState,
		BotFreeGoalState = B.BotFreeGoalState,
		BotResetMoveState = B.BotResetMoveState,
		BotMoveToGoal = B.BotMoveToGoal,
		BotMoveInDirection = B.BotMoveInDirection,
		BotResetAvoidReach = B.BotResetAvoidReach,
		BotResetLastAvoidReach = B.BotResetLastAvoidReach,
		BotReachabilityArea = B.BotReachabilityArea,
		BotMovementViewTarget = B.BotMovementViewTarget,
		BotPredictVisiblePosition = B.BotPredictVisiblePosition,
		BotAllocMoveState = B.BotAllocMoveState,
		BotFreeMoveState = B.BotFreeMoveState,
		BotInitMoveState = B.BotInitMoveState,
		BotAddAvoidSpot = B.BotAddAvoidSpot,
		BotChooseBestFightWeapon = B.BotChooseBestFightWeapon,
		BotGetWeaponInfo = B.BotGetWeaponInfo,
		BotLoadWeaponWeights = B.BotLoadWeaponWeights,
		BotAllocWeaponState = B.BotAllocWeaponState,
		BotFreeWeaponState = B.BotFreeWeaponState,
		BotResetWeaponState = B.BotResetWeaponState,
		GeneticParentsAndChildSelection = B.GeneticParentsAndChildSelection,
	}
end

function B.GetBotLibAPI(apiVersion, import)
	assert(import)
	B.botimport = import
	assert(B.botimport.Print)

	if apiVersion ~= BOTLIB_API_VERSION then
		B.botimport.Print(
			BC.PRT_ERROR,
			"Mismatched BOTLIB_API_VERSION: expected %i, got %i\n",
			BOTLIB_API_VERSION,
			apiVersion
		)
		return nil
	end

	local export = {
		aas = Init_AAS_Export(),
		ea = Init_EA_Export(),
		ai = Init_AI_Export(),
		BotLibSetup = B.Export_BotLibSetup,
		BotLibShutdown = B.Export_BotLibShutdown,
		BotLibVarSet = B.Export_BotLibVarSet,
		BotLibVarGet = B.Export_BotLibVarGet,
		PC_AddGlobalDefine = B.PC_AddGlobalDefine,
		PC_LoadSourceHandle = B.PC_LoadSourceHandle,
		PC_FreeSourceHandle = B.PC_FreeSourceHandle,
		PC_ReadTokenHandle = B.PC_ReadTokenHandle,
		PC_SourceFileAndLine = B.PC_SourceFileAndLine,
		BotLibStartFrame = B.Export_BotLibStartFrame,
		BotLibLoadMap = B.Export_BotLibLoadMap,
		BotLibUpdateEntity = B.Export_BotLibUpdateEntity,
		Test = B.BotExportTest,
	}
	return export
end

return nil
