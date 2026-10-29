--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (the engine side of server/sv_bot.c).

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
-- The BotGame adapter: everything the bot code needs from the server
-- engine, in one table, so sv_bot.luau (the engine half of the bots)
-- does not reach into engine internals. docs/bots-notes.md lists every
-- field and where the engine calls back into the bots.
--
-- BotGame.FromEngine builds it from the game branch's engine modules
-- (src/server/sv/*, src/shared/Collision); a different host can build the
-- same table by hand.

local BotGame = {}

export type Adapter = {
	-- console
	Com_Printf: (text: string) -> (),
	Com_Error: (level: number, text: string) -> (),
	Sys_Milliseconds: () -> number,
	-- cvars (Cvar_Get returns the cvar_t-like table: .integer .value .string)
	Cvar_Get: (name: string, value: string, flags: number) -> any,
	Cvar_VariableIntegerValue: (name: string) -> number,
	Cvar_VariableString: (name: string) -> string,
	-- whole files for botlib: botfiles/*, maps/<map>.aas (nil if missing)
	FS_ReadFile: (path: string) -> buffer?,
	-- collision / world, ioquake3 semantics (SV_Trace, SV_ClipToEntity,
	-- SV_PointContents, SV_inPVS, CM_EntityString, CM_InlineModel, CM_ModelBounds)
	trace_t: () -> any,
	SV_Trace: (results: any, start: any, mins: any, maxs: any, end_: any, passEntityNum: number, contentmask: number, capsule: boolean) -> (),
	SV_ClipToEntity: (results: any, start: any, mins: any, maxs: any, end_: any, entityNum: number, contentmask: number, capsule: boolean) -> (),
	SV_PointContents: (p: any, passEntityNum: number) -> number,
	SV_inPVS: (p1: any, p2: any) -> boolean,
	CM_EntityString: () -> string,
	CM_InlineModel: (index: number) -> number,
	CM_ModelBounds: (model: number, mins: any, maxs: any) -> (),
	-- clients: svs.clients[n] (client_t: reliableCommands/Sequence/Acknowledge,
	-- frames[], outgoingSequence, lastPacketTime, lastUsercmd, gentity)
	GetClient: (clientNum: number) -> any,
	svsTime: () -> number,
	MAX_RELIABLE_COMMANDS: number,
	PACKET_MASK: number,
	-- entity number of the sequence-th entity in a client snapshot frame
	SnapshotEntityNumber: (frame: any, sequence: number) -> number,
	-- SV_ClientThink(&svs.clients[n], cmd) and SV_ExecuteClientCommand(&svs.clients[n], s, clientOK)
	SV_ClientThink: (clientNum: number, cmd: any) -> (),
	SV_ExecuteClientCommand: (clientNum: number, command: string, clientOK: boolean) -> (),
	-- the game module: is it running (gvm), and VM_Call(gvm, BOTAI_START_FRAME, time)
	GameRunning: () -> boolean,
	VM_Call_BotAIStartFrame: (time: number) -> (),
}

-- The adapter over the game branch's engine: SV (sv_main), W (sv_world),
-- Cvar, Fs, Collision, the game namespace G with its defs C, and the
-- shared structs module (for trace_t).
function BotGame.FromEngine(m: { SV: any, W: any, Cvar: any, Fs: any, Collision: any, G: any, C: any, structs: any }): Adapter
	local SV, W, Cvar, Fs, Collision, G, C = m.SV, m.W, m.Cvar, m.Fs, m.Collision, m.G, m.C
	return {
		Com_Printf = function(text)
			SV.Com_Printf(text)
		end,
		Com_Error = function(level, text)
			error(text, 0)
		end,
		Sys_Milliseconds = function()
			return SV.Sys_Milliseconds()
		end,
		Cvar_Get = Cvar.Get,
		Cvar_VariableIntegerValue = Cvar.VariableIntegerValue,
		Cvar_VariableString = Cvar.VariableString,
		FS_ReadFile = function(path)
			local s = Fs.ReadFile(path)
			return if s then buffer.fromstring(s) else nil
		end,
		trace_t = m.structs.trace_t,
		SV_Trace = W.SV_Trace,
		SV_ClipToEntity = W.SV_ClipToEntity,
		SV_PointContents = W.SV_PointContents,
		SV_inPVS = W.SV_inPVS,
		CM_EntityString = Collision.EntityString,
		CM_InlineModel = Collision.InlineModel,
		CM_ModelBounds = Collision.ModelBounds,
		GetClient = function(n)
			return SV.svs.clients[n]
		end,
		svsTime = function()
			return SV.svs.time
		end,
		MAX_RELIABLE_COMMANDS = SV.MAX_RELIABLE_COMMANDS,
		PACKET_MASK = SV.PACKET_MASK,
		-- the game engine keeps each snapshot's entity states in frame.entities[]
		SnapshotEntityNumber = function(frame, sequence)
			return frame.entities[sequence].number
		end,
		SV_ClientThink = function(n, cmd)
			SV.SV_ClientThink(SV.svs.clients[n], cmd)
		end,
		SV_ExecuteClientCommand = function(n, s, ok)
			SV.SV_ExecuteClientCommand(SV.svs.clients[n], s, ok)
		end,
		GameRunning = function()
			return SV.sv.gameRunning == true
		end,
		VM_Call_BotAIStartFrame = function(time)
			G.vmMain(C.BOTAI_START_FRAME, time)
		end,
	}
end

return BotGame
