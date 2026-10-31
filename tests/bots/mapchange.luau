-- Map change check: bots must keep playing on the map a vote changes to.
-- Two bots and a human on oa_dm1 for 15 s, then the human's
-- `callvote map am_galmevish` passes; from 2 s into the new map every
-- bot must have moved within a few seconds, long before the new map's
-- clock reaches the old map's.
--   lune run tests/bots/mapchange.luau
local Host = require("./simhost")
local FC = require("../server/fakeclient")
local S = require("../../src/shared/structs")
local C = require("../../src/server/g_defs")

local h = Host.new({ maps = {}, quiet = true })
local G, SV = h.G, h.SV
local clients = {}
SV.send = function(n, data)
	local c = clients[n]
	if c then
		c:receive(data)
	end
end

local function step()
	for n, fc in clients do
		local cmds = {}
		if fc.snap or fc.gamestates > 0 then
			local cmd = S.usercmd_t()
			fc.lastCmdTime = math.max((fc.lastCmdTime or 0) + 50, fc.serverTime + 50)
			cmd.serverTime = fc.lastCmdTime
			table.insert(cmds, cmd)
		end
		SV.SV_PacketEvent(n, fc:writePacket(cmds))
	end
	h.frame(50)
end
local function run(seconds: number)
	for _ = 1, seconds * 20 do
		step()
	end
end

local function bots(): { number }
	local out = {}
	for i = 0, C.MAX_CLIENTS - 1 do
		local ent = G.g_entities[i]
		if ent and ent.inuse and ent.client and bit32.band(ent.r.svFlags, C.SVF_BOT) ~= 0 then
			table.insert(out, i)
		end
	end
	return out
end

-- how far (x + y) each bot walked in `seconds`
local function walked(seconds: number): { [number]: number }
	local start = {}
	for _, i in bots() do
		local o = G.g_entities[i].client.ps.origin
		start[i] = { o[0], o[1] }
	end
	run(seconds)
	local out = {}
	for i, p in start do
		local o = G.g_entities[i].client.ps.origin
		out[i] = math.abs(o[0] - p[1]) + math.abs(o[1] - p[2])
	end
	return out
end

for _, m in { "oa_dm1", "am_galmevish" } do
	h.Game.Fs.Mount("maps/" .. m .. ".bsp", "")
end
h.Game.Command("bot_enable 1")
h.Game.Command("set g_allowVote 1")
h.Game.Command("map oa_dm1")
local fc = FC.new("Voter")
local n = assert(SV.SV_DirectConnect(
	"\\name\\Voter\\model\\sarge\\headmodel\\sarge\\handicap\\100\\snaps\\20\\rate\\25000",
	fc, "10.0.0.5:27960", SV.GuidFor(1001)
))
fc.clientNum = n
clients[n] = fc
run(1)
h.Game.Command("addbot sarge 4")
h.Game.Command("addbot tony 4")
run(15)

fc:addReliableCommand("callvote map am_galmevish")
while h.Game.Cvar.VariableString("mapname") ~= "am_galmevish" and SV.sv.time < 30000 do
	step()
end
local failures = 0
if h.Game.Cvar.VariableString("mapname") ~= "am_galmevish" then
	print("FAIL: the map vote did not pass")
	failures += 1
end
run(2)
local moved = walked(4)
local count = 0
for i, d in moved do
	count += 1
	if d < 64 then
		print(("FAIL: bot %d walked %.0f units in 4 s on the new map"):format(i, d))
		failures += 1
	end
end
if count ~= 2 then
	print(("FAIL: %d bots on the new map, want 2"):format(count))
	failures += 1
end
print(if failures == 0 then "mapchange: ok" else ("mapchange: %d failures"):format(failures))
if failures > 0 then
	error("mapchange failed")
end
