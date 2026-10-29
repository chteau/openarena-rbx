-- A loopback world for the server tests: one Game, fake clients wired to
-- it through SV.send / SV.SV_PacketEvent, and a frame driver that runs
-- the server and every client at 50 ms steps.
local H = require("./host")
local FC = require("./fakeclient")
local S = require("../../src/shared/structs")

local W = {}
W.__index = W

function W.new(opts)
	local self = setmetatable({}, W)
	self.log = {}
	self.Game = H.newGame({
		quiet = not (opts and opts.verbose),
		log = self.log,
		patchEntities = opts and opts.patchEntities,
	})
	self.SV = self.Game.SV
	self.G = self.Game.G
	self.clients = {} -- clientNum -> FC
	self.SV.send = function(n: number, data: buffer)
		local c = self.clients[n]
		if c then
			c:receive(data)
			if self.onSnapshot and c.snap and c.snap.messageNum == c.serverMessageSequence then
				self.onSnapshot(n, c)
			end
		end
	end
	return self
end

function W:command(text: string)
	self.Game.Command(text)
end

function W:connect(name: string, extra: string?): any
	local userinfo = "\\name\\" .. name .. "\\model\\sarge\\headmodel\\sarge\\handicap\\100\\snaps\\20\\rate\\25000"
		.. (extra or "")
	local fc = FC.new(name)
	self.nextId = (self.nextId or 1000) + 1
	local n, reason = self.SV.SV_DirectConnect(userinfo, fc, "10.0.0." .. tostring(self.nextId % 250) .. ":27960", self.SV.GuidFor(self.nextId))
	assert(n, reason)
	fc.clientNum = n
	self.clients[n] = fc
	fc.wish = S.usercmd_t()
	return fc
end

-- one 50 ms step: every client sends a packet with one usercmd, then the
-- server runs a frame (which sends the snapshots)
function W:step(ms: number?)
	ms = ms or 50
	for n, fc in self.clients do
		if fc.disconnected then
			continue
		end
		local cmds = {}
		if fc.snap or fc.gamestates > 0 then
			local cmd = S.usercmd_t()
			S.copy_usercmd_t(cmd, fc.wish)
			fc.lastCmdTime = math.max((fc.lastCmdTime or 0) + ms, fc.serverTime + ms)
			cmd.serverTime = fc.lastCmdTime
			table.insert(cmds, cmd)
		end
		self.SV.SV_PacketEvent(n, fc:writePacket(cmds))
	end
	self.Game.Frame(ms)
end

function W:run(seconds: number)
	for _ = 1, math.floor(seconds * 20) do
		self:step(50)
	end
end

function W:printed(pattern: string): boolean
	for _, l in self.log do
		if string.find(l, pattern) then
			return true
		end
	end
	return false
end

return W
