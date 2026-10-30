--!strict
-- Roblox transport for the server engine (the part of ioquake3's
-- net_ip.c / netchan.c a Roblox place needs). It moves the engine's
-- message buffers over two remotes in ReplicatedStorage.OANet:
--
--   Unreliable (UnreliableRemoteEvent)  client packets (usercmds), and
--                                       server messages up to 800 bytes
--   Reliable   (RemoteEvent)            connect/refuse handshake, client
--                                       packets that carry long commands,
--                                       server messages over 800 bytes
--
-- Every packet starts with its sequence number, and both ends drop
-- anything older than what they already processed, so the two channels
-- can interleave freely. The format is in docs/formats/net.md.
--
-- This file is GPL-2.0 like the rest of the port; it has no C original.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Avatars = require("./avatars_roblox")
local Chat = require("./chat_roblox")

local Transport = {}

-- an UnreliableRemoteEvent payload must stay under Roblox's ~1000 byte
-- limit (documented as 900 bytes of serialized payload); keep a margin
-- for the serialization overhead
Transport.UNRELIABLE_MAX = 800
-- MAX_MSGLEN: anything larger is not a message the engine wrote
Transport.MAX_PACKET = 16384

type Game = {
	SV: any,
	Frame: (msec: number) -> (),
}

local function remotes()
	local folder = ReplicatedStorage:FindFirstChild("OANet")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "OANet"
		folder.Parent = ReplicatedStorage
	end
	local reliable = folder:FindFirstChild("Reliable") :: RemoteEvent?
	if not reliable then
		local r = Instance.new("RemoteEvent")
		r.Name = "Reliable"
		r.Parent = folder
		reliable = r
	end
	local unreliable = folder:FindFirstChild("Unreliable") :: UnreliableRemoteEvent?
	if not unreliable then
		local u = Instance.new("UnreliableRemoteEvent")
		u.Name = "Unreliable"
		u.Parent = folder
		unreliable = u
	end
	return reliable :: RemoteEvent, unreliable :: UnreliableRemoteEvent
end

-- The player <-> client slot bookkeeping, apart from the remotes so the
-- tests can drive it. `avatars` is Avatars (Set/Clear); `kick(player,
-- reason)` runs a second after the engine drops a player.
function Transport.Sessions(SV: any, avatars: any, kick: (player: any, reason: string) -> ())
	local self = {
		clientOf = {} :: { [any]: number },
		playerOf = {} :: { [number]: any },
	}
	local clientOf, playerOf = self.clientOf, self.playerOf

	-- the engine dropped a client (kick, timeout, server command overflow):
	-- give the "disconnect" command a moment to arrive, then remove them
	function self.onDrop(clientNum: number, reason: string)
		local player = playerOf[clientNum]
		playerOf[clientNum] = nil
		avatars.Clear(clientNum)
		if player then
			clientOf[player] = nil
			kick(player, reason)
		end
	end

	-- "connect": the first one, or a reconnect (a `connect`/`reconnect`
	-- command, the client restarting). A reconnect keeps the player's slot
	-- and never drops them (SV_DirectConnect, as ioq3), so nobody sees a
	-- "disconnected" line and the player is not kicked.
	function self.connect(player: any, userinfo: string, firstSequence: number?): (number?, string?)
		local old = clientOf[player]
		local address = "rbx:" .. tostring(player.UserId)
		local n, reason = SV.SV_DirectConnect(userinfo, player, address, SV.GuidFor(player.UserId), firstSequence)
		if old ~= nil and old ~= n then
			-- refused, or (never with the same address) a different slot
			playerOf[old] = nil
			clientOf[player] = nil
			avatars.Clear(old)
		end
		if n == nil then
			return nil, reason or "refused"
		end
		clientOf[player] = n
		playerOf[n] = player
		avatars.Set(n, player.UserId)
		return n, nil
	end

	-- the player left the server
	function self.remove(player: any)
		local n = clientOf[player]
		if n ~= nil then
			clientOf[player] = nil
			playerOf[n] = nil
			avatars.Clear(n)
			SV.SV_Disconnect(n)
		end
	end

	return self
end

-- Starts the transport and the frame driver. Call after Game.Init and the
-- first "map" command.
function Transport.Start(Game: Game)
	local SV = Game.SV
	local reliable, unreliable = remotes()
	Avatars.Start(Game)

	local sessions = Transport.Sessions(SV, Avatars, function(player: Player, reason: string)
		task.delay(1, function()
			if player.Parent == Players then
				player:Kick(reason)
			end
		end)
	end)
	local clientOf: { [Player]: number } = sessions.clientOf
	local playerOf: { [number]: Player } = sessions.playerOf
	Chat.Start(Game, clientOf)

	SV.play = function(name: string)
		for player in clientOf do
			if player.Parent == Players then
				reliable:FireClient(player, "play", name)
			end
		end
	end
	SV.send = function(clientNum: number, data: buffer)
		local player = playerOf[clientNum]
		if not player or player.Parent ~= Players then
			return
		end
		if buffer.len(data) <= Transport.UNRELIABLE_MAX then
			unreliable:FireClient(player, data)
		else
			reliable:FireClient(player, "p", data)
		end
	end

	SV.onDrop = sessions.onDrop

	local function packet(player: Player, data: any)
		local n = clientOf[player]
		if n == nil or typeof(data) ~= "buffer" then
			return
		end
		local len = buffer.len(data)
		if len < 4 or len > Transport.MAX_PACKET then
			return
		end
		SV.SV_PacketEvent(n, data)
	end

	unreliable.OnServerEvent:Connect(packet)

	reliable.OnServerEvent:Connect(function(player: Player, kind: any, data: any, seq: any)
		if kind == "p" then
			packet(player, data)
		elseif kind == "disconnect" then
			-- the client went back to its menu: drop it from the game, but
			-- the player stays in the place and can connect again
			sessions.remove(player)
		elseif kind == "connect" then
			if typeof(data) ~= "string" or #data > 1024 then
				return
			end
			local first = if typeof(seq) == "number" and seq == seq and seq >= 1 and seq < 2 ^ 31
				then math.floor(seq)
				else nil
			local n, reason = sessions.connect(player, data, first)
			if n == nil then
				reliable:FireClient(player, "refused", reason)
				return
			end
			-- the first packet number the client will see from the server
			reliable:FireClient(player, "connected", n, SV.svs.clients[n].outgoingSequence)
		end
	end)

	Players.PlayerRemoving:Connect(sessions.remove)

	-- the host clock: whole milliseconds into the engine, the remainder
	-- carried, so sv_fps frames land on the same msec boundaries as Q3
	local carry = 0
	RunService.Heartbeat:Connect(function(dt: number)
		local ms = dt * 1000 + carry
		local whole = math.floor(ms)
		carry = ms - whole
		if whole > 0 then
			Game.Frame(whole)
		end
	end)
end

return Transport
