-- The server transport's player <-> slot bookkeeping (sv/transport_roblox
-- Transport.Sessions) against a stub engine: a reconnect from the same
-- player keeps the slot with no drop and no kick, as ioq3's
-- SV_DirectConnect does for the same address.

local Transport = H.require("server/sv/transport_roblox")

local function stubs()
	local log = {}
	local slots = {} -- address -> clientNum
	local nextSlot = 0
	local SV = {}
	SV.refuse = nil
	function SV.GuidFor(id)
		return "G" .. tostring(id)
	end
	function SV.SV_DirectConnect(_userinfo, _player, address, _guid, first)
		table.insert(log, "connect " .. address .. " " .. tostring(first))
		if SV.refuse then
			return nil, SV.refuse
		end
		local n = slots[address]
		if n == nil then
			n = nextSlot
			nextSlot += 1
			slots[address] = n
		end
		return n, nil
	end
	function SV.SV_Disconnect(n)
		table.insert(log, "disconnect " .. n)
	end
	local avatars = {
		Set = function(n, id)
			table.insert(log, "avatar " .. n .. " " .. id)
		end,
		Clear = function(n)
			table.insert(log, "clear " .. n)
		end,
	}
	local kicks = {}
	local s = Transport.Sessions(SV, avatars, function(player, reason)
		table.insert(kicks, player.Name .. ": " .. reason)
	end)
	return s, SV, log, kicks
end

local function has(log, line)
	for _, l in log do
		if l == line then
			return true
		end
	end
	return false
end

H.test("transport.reconnect keeps the slot", function()
	local s, _, log, kicks = stubs()
	local alice = { Name = "Alice", UserId = 7 }
	local bob = { Name = "Bob", UserId = 8 }
	H.eq(s.connect(alice, "\\name\\a", 1), 0)
	H.eq(s.connect(bob, "\\name\\b", 1), 1)
	-- Alice's client reconnects (a `connect`, a map load): same slot, no
	-- engine drop, no avatar clear, no kick
	H.eq(s.connect(alice, "\\name\\a", 900), 0)
	H.eq(has(log, "disconnect 0"), false)
	H.eq(has(log, "clear 0"), false)
	H.eq(#kicks, 0)
	H.eq(has(log, "connect rbx:7 900"), true)
	H.eq(s.clientOf[alice], 0)
	H.eq(s.playerOf[0], alice)
	H.eq(s.clientOf[bob], 1)
end)

H.test("transport.refused reconnect forgets the player", function()
	local s, SV, log, kicks = stubs()
	local alice = { Name = "Alice", UserId = 7 }
	H.eq(s.connect(alice, "", 1), 0)
	SV.refuse = "Banned."
	local n, reason = s.connect(alice, "", 50)
	H.eq(n, nil)
	H.eq(reason, "Banned.")
	H.eq(s.clientOf[alice], nil)
	H.eq(s.playerOf[0], nil)
	H.eq(has(log, "clear 0"), true)
	H.eq(#kicks, 0)
end)

H.test("transport.drop kicks, leaving disconnects", function()
	local s, _, log, kicks = stubs()
	local alice = { Name = "Alice", UserId = 7 }
	local bob = { Name = "Bob", UserId = 8 }
	s.connect(alice, "", 1)
	s.connect(bob, "", 1)
	-- the engine drops Alice (kick, timeout): she is kicked from the place
	s.onDrop(0, "was kicked")
	H.eq(kicks[1], "Alice: was kicked")
	H.eq(s.clientOf[alice], nil)
	-- Bob leaves the place: the engine hears it, nobody is kicked
	s.remove(bob)
	H.eq(has(log, "disconnect 1"), true)
	H.eq(#kicks, 1)
	H.eq(s.playerOf[1], nil)
end)

-- client/sys/Net: a new gamestate (map change) starts the clock over, as
-- CL_ClearState does, so the first usercmd of the new level can't carry the
-- old level's later serverTime
H.test("transport.gamestate resets the client clock", function()
	local C = H.require("client/q/Consts")
	local Net = H.require("client/sys/Net")
	Net.state = C.CA_ACTIVE
	Net.serverTime = 217400
	Net.oldServerTime = 217400
	Net.serverTimeDelta = -5000
	Net.ReceiveGamestate({ [0] = "\\g_gametype\\0" }, 10, 1)
	H.eq(Net.state, C.CA_PRIMED)
	H.eq(Net.serverTime, 0)
	H.eq(Net.oldServerTime, 0)
	H.eq(Net.serverTimeDelta, 0)
	H.eq(Net.ConfigString(C.CS_SERVERINFO), "\\g_gametype\\0")
end)

-- the cgame restarted by a map change carries on from the last server
-- command the old one ran (CL_InitCGame's clc.lastExecutedServerCommand)
H.test("transport.gamestate keeps the executed command count", function()
	local Net = H.require("client/sys/Net")
	Net.ReceiveGamestate({}, 10, 1)
	for n = 1, 300 do
		Net.ReceiveServerCommand(10 + n, "print \"x\"")
		Net.GetServerCommand(10 + n)
	end
	H.eq(Net.lastExecutedServerCommand, 310)
	-- a map change: the same connection, numbering goes on
	Net.ReceiveGamestate({}, 320, 1)
	H.eq(Net.lastExecutedServerCommand, 310)
	-- a new connection numbers from its own start
	Net.ReceiveGamestate({}, 4, 1)
	H.eq(Net.lastExecutedServerCommand, 4)
end)
