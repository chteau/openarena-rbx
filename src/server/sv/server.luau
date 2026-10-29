--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (ioquake3 code/server/server.h).

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
-- Server engine state (ioquake3 server/server.h): the sv (per map) and svs
-- (persistent) records the trap_* layer, the world links and the snapshot
-- builder share. The game module never touches these directly.

local S = require("../../shared/structs")
local C = require("../g_defs")

local SV = {}

SV.MAX_ENT_CLUSTERS = 16
SV.PACKET_BACKUP = 32
SV.PACKET_MASK = SV.PACKET_BACKUP - 1
SV.MAX_RELIABLE_COMMANDS = 64
SV.MAX_SNAPSHOT_ENTITIES = 256

-- serverState_t
SV.SS_DEAD = 0
SV.SS_LOADING = 1
SV.SS_GAME = 2

-- clientState_t
SV.CS_FREE = 0
SV.CS_ZOMBIE = 1
SV.CS_CONNECTED = 2
SV.CS_PRIMED = 3
SV.CS_ACTIVE = 4

function SV.newSvEntity()
	local clusternums = {}
	for i = 0, SV.MAX_ENT_CLUSTERS - 1 do
		clusternums[i] = 0
	end
	return {
		worldSector = nil,
		nextEntityInWorldSector = nil,
		baseline = S.entityState_t(),
		numClusters = 0,
		clusternums = clusternums,
		lastCluster = 0,
		areanum = 0,
		areanum2 = 0,
		snapshotCounter = 0,
		index = 0,
	}
end

-- server_t
SV.sv = {
	state = SV.SS_DEAD,
	restarting = false,
	serverId = 0,
	restartedServerId = 0,
	snapshotCounter = 0,
	timeResidual = 0,
	nextFrameTime = 0,
	configstrings = {}, -- [0..MAX_CONFIGSTRINGS-1] strings
	svEntities = {},
	entityParsePoint = nil, -- QS cursor over the entity string
	gentities = nil, -- G.g_entities
	num_entities = 0,
	gameClients = nil, -- level.clients (gclient_t, whose first member is ps)
	restartTime = 0,
	time = 0,
	mapname = "",
	checksumFeed = 0,
	gameRunning = false,
}
for i = 0, C.MAX_GENTITIES - 1 do
	local e = SV.newSvEntity()
	e.index = i
	SV.sv.svEntities[i] = e
end

-- serverStatic_t
SV.svs = {
	initialized = false,
	time = 0,
	snapFlagServerBit = 0,
	clients = {}, -- [0..sv_maxclients-1] client_t
	nextSnapshotEntities = 0,
}

function SV.newClientSnapshot()
	return {
		areabytes = 0,
		areabits = buffer.create(C.MAX_MAP_AREA_BYTES),
		ps = S.playerState_t(),
		num_entities = 0,
		entities = {}, -- entityState_t copies, in increasing number order
		messageSent = 0,
		messageAcked = 0,
		messageSize = 0,
	}
end

-- client_t (the parts a Roblox transport needs; no UDP netchan)
function SV.newClient(i: number)
	local frames = {}
	for k = 0, SV.PACKET_BACKUP - 1 do
		frames[k] = SV.newClientSnapshot()
	end
	return {
		index = i,
		state = SV.CS_FREE,
		userinfo = "",
		reliableCommands = {}, -- [seq & (MAX_RELIABLE_COMMANDS-1)] = text
		reliableSequence = 0,
		reliableAcknowledge = 0,
		reliableSent = 0,
		messageAcknowledge = 0,
		gamestateMessageNum = -1,
		lastUsercmd = S.usercmd_t(),
		lastMessageNum = 0,
		lastClientCommand = 0,
		lastClientCommandString = "",
		gentity = nil,
		name = "",
		deltaMessage = -1,
		nextReliableTime = 0,
		lastPacketTime = 0,
		lastConnectTime = 0,
		lastSnapshotTime = 0,
		timeoutCount = 0,
		frames = frames,
		ping = 0,
		rate = 25000,
		snapshotMsec = 50,
		oldServerTime = 0,
		outgoingSequence = 1, -- snapshot message number
		csUpdated = {},
		isBot = false,
		player = nil, -- transport handle (a Roblox Player), set by the host
		address = nil, -- stable pseudo address standing in for the IP
		guid = nil, -- cl_guid forced into the userinfo (SV.GuidFor)
		incomingSequence = 0, -- last client packet sequence (netchan)
		rateDelayed = false,
	}
end

return SV
