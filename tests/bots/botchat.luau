-- Every packed chat file loads through the port's botlib (lune run
-- tests/bots/botchat.luau): syn.c, rnd.c, match.c and rchat.c at setup,
-- then each bots/*_t.c chat through BotLoadChatFile, with no error or
-- warning from the precompiler or the chat loader. tools/check_botchat.py
-- checks what the lines say; this checks botlib can still read them.
local Host = require("./simhost")

local log = {}
local h = Host.new({ maps = { "oa_dm1" }, quiet = true, log = log })
local G = h.G
h.Game.Command("bot_enable 1")
h.Game.Command("map oa_dm1")
for _ = 1, 10 do
	h.frame(50)
end

local failures = 0
local function problems(from: number, what: string)
	for i = from, #log do
		if string.find(log[i], "Error:", 1, true) or string.find(log[i], "Fatal:", 1, true)
			or string.find(log[i], "Warning:", 1, true) then
			failures += 1
			print("FAIL: " .. what .. ": " .. log[i])
		end
	end
end
problems(1, "setup")
local setup = table.concat(log)
for _, f in { "syn.c", "rnd.c", "match.c", "rchat.c" } do
	if not string.find(setup, "loaded " .. f, 1, true) then
		failures += 1
		print("FAIL: " .. f .. " was not loaded")
	end
end

-- the chat files in the packed blob, as Bots.MountBotfiles mounts them
local files = {}
local bin = buffer.fromstring(require("@lune/fs").readFile("build/botfiles/botfiles.bin"))
h.Bots.MountBotfiles(bin, function(path: string, data: string)
	local rel = string.match(path, "^botfiles/(bots/[%w_]+_t%.c)$")
	if rel then
		files[rel] = data
	end
end)

local chats = 0
for rel, data in files do
	for name in string.gmatch(data, 'chat%s+"([^"]+)"') do
		local cs = G.trap_BotAllocChatState()
		local mark = #log + 1
		local err = G.trap_BotLoadChatFile(cs, rel, name)
		if err ~= 0 then
			failures += 1
			print(string.format("FAIL: %s chat %s: error %d", rel, name, err))
		end
		problems(mark, rel)
		G.trap_BotFreeChatState(cs)
		chats += 1
	end
end
print(string.format("botchat: %d chats loaded, %d failure(s)", chats, failures))
require("@lune/process").exit(if failures > 0 or chats == 0 then 1 else 0)
