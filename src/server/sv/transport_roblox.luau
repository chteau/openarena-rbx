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

-- Starts the transport and the frame driver. Call after Game.Init and the
-- first "map" command.
function Transport.Start(Game: Game)
	local SV = Game.SV
	local reliable, unreliable = remotes()
	Avatars.Start(Game)

	local clientOf: { [Player]: number } = {}
	local playerOf: { [number]: Player } = {}
	Chat.Start(Game, clientOf)

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

	-- the engine dropped a client (kick, timeout, server command overflow):
	-- give the "disconnect" command a moment to arrive, then remove them
	SV.onDrop = function(clientNum: number, reason: string)
		local player = playerOf[clientNum]
		playerOf[clientNum] = nil
		Avatars.Clear(clientNum)
		if player then
			clientOf[player] = nil
			task.delay(1, function()
				if player.Parent == Players then
					player:Kick(reason)
				end
			end)
		end
	end

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

	reliable.OnServerEvent:Connect(function(player: Player, kind: any, data: any)
		if kind == "p" then
			packet(player, data)
		elseif kind == "connect" then
			if typeof(data) ~= "string" or #data > 1024 then
				return
			end
			local old = clientOf[player]
			if old ~= nil then
				-- a reconnect (new map load on the client, cgame restart)
				SV.SV_Disconnect(old)
				Avatars.Clear(old)
				playerOf[old] = nil
				clientOf[player] = nil
			end
			local address = "rbx:" .. tostring(player.UserId)
			local n, reason = SV.SV_DirectConnect(data, player, address, SV.GuidFor(player.UserId))
			if n == nil then
				reliable:FireClient(player, "refused", reason or "refused")
				return
			end
			clientOf[player] = n
			playerOf[n] = player
			Avatars.Set(n, player)
			reliable:FireClient(player, "connected", n)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local n = clientOf[player]
		if n ~= nil then
			clientOf[player] = nil
			playerOf[n] = nil
			Avatars.Clear(n)
			SV.SV_Disconnect(n)
		end
	end)

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
