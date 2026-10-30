--!strict
--[[
Copyright (C) 2026 openarena-rbx contributors

This file is part of openarena-rbx, a port of OpenArena to Roblox.

openarena-rbx is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version. See COPYING.
]]
-- Not a port: the Roblox route for what players type (docs/client-notes.md,
-- "Chat"). OA sends `say "text"` to the game, and G_Say sends every
-- recipient the line as a "chat"/"tchat" command. On Roblox a player's
-- text must go through TextChatService's filter, so:
--
--   * the client sends the text on TextChatService.OAChat.Say (say, and
--     tell with Metadata "tell <clientNum>") or .Team (say_team);
--   * on the first ShouldDeliverCallback of a message this module runs the
--     game's own G_Say (Cmd_Say_f / Cmd_Tell_f) with the text, catching the
--     commands it would send. Every client G_Say picked gets the message
--     from Roblox (filtered for that viewer) and, from here, a
--     `rchat <MessageId> <chat|tchat> "<name prefix>"` command; the client
--     puts the two together and runs the cgame's chat path. Everyone else
--     is refused delivery, so OA's rules (team, tell, tourney) decide who
--     sees what;
--   * bots get the line as OA sends it, with the text filtered for
--     broadcast (TextService), so a reply that quotes it is filtered too.
--
-- Players' `say`/`say_team`/`tell` commands are refused by the engine
-- (SV_ExecuteClientCommand): only bots and the server say things directly.
-- Each player's Player attribute OACanChat says whether
-- TextChatService:CanUserChatAsync allows them to chat.

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local TextService = game:GetService("TextService")

local Chat = {}

local function channel(folder: Instance, name: string): TextChannel
	local ch = Instance.new("TextChannel")
	ch.Name = name
	ch.Parent = folder
	return ch
end

-- TextChatMessage.Text escapes rich text
local function unescape(s: string): string
	return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&"))
end

-- what Cmd_Args_Sanitize and the quoted say command leave of a line
local function sanitize(s: string): string
	return (unescape(s):gsub("[%c;]", " "):gsub('"', "'"))
end

function Chat.Start(Game: any, clientOf: { [Player]: number })
	local G, C = Game.G, Game.C
	local folder = Instance.new("Folder")
	folder.Name = "OAChat"
	folder.Parent = TextChatService
	local say = channel(folder, "Say")
	local team = channel(folder, "Team")

	local function join(player: Player)
		for _, ch in { say, team } do
			pcall(function()
				ch:AddUserAsync(player.UserId)
			end)
		end
		local ok, can = pcall(function()
			return TextChatService:CanUserChatAsync(player.UserId)
		end)
		player:SetAttribute("OACanChat", ok and can == true)
	end
	Players.PlayerAdded:Connect(join)
	for _, p in Players:GetPlayers() do
		task.spawn(join, p)
	end

	-- the bots G_Say picked get the line with the text filtered for broadcast
	local function toBots(bots: { { n: number, cmd: string, prefix: string } }, text: string, userId: number)
		local ok, filtered = pcall(function()
			return TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PublicChat)
				:GetNonChatStringForBroadcastAsync()
		end)
		if not ok then
			return
		end
		filtered = string.sub(sanitize(filtered), 1, C.MAX_SAY_TEXT - 1)
		for _, b in bots do
			G.trap_SendServerCommand(b.n, string.format('%s "%s%s"', b.cmd, b.prefix, filtered))
		end
	end

	-- MessageId -> the clients G_Say sent the message to
	local routed: { [string]: { [number]: boolean } } = {}

	local function route(message: TextChatMessage, isTeam: boolean): { [number]: boolean }
		local to: { [number]: boolean } = {}
		routed[message.MessageId] = to
		task.delay(30, function()
			routed[message.MessageId] = nil
		end)
		local src = message.TextSource
		local sender = src and Players:GetPlayerByUserId(src.UserId)
		local n = sender and clientOf[sender]
		local ent = n and G.g_entities[n]
		if ent == nil or not ent.inuse or ent.client == nil then
			return to
		end
		local text = sanitize(message.Text)
		local mode, target = C.SAY_ALL, nil
		if isTeam then
			mode = C.SAY_TEAM
		else
			local t = tonumber(string.match(message.Metadata, "^tell (%d+)$"))
			if t then
				target = G.g_entities[t]
				if t >= G.level.maxclients or target == nil or not target.inuse or target.client == nil then
					return to
				end
				mode = C.SAY_TELL
			end
		end
		-- ClientCommand: say is CMD_MESSAGE|CMD_INTERMISSION, nothing else applies
		local sent: { { n: number, text: string } } = {}
		local send = G.trap_SendServerCommand
		G.trap_SendServerCommand = function(clientNum: number, cmd: string)
			table.insert(sent, { n = clientNum, text = cmd })
		end
		local ok, err = pcall(function()
			if mode == C.SAY_TELL then
				-- Cmd_Tell_f
				G.G_LogPrintf("tell: %s to %s: %s\n", ent.client.pers.netname, target.client.pers.netname, text)
				G.G_Say(ent, target, mode, text)
				if ent ~= target then
					G.G_Say(ent, ent, mode, text)
				end
			else
				G.G_Say(ent, nil, mode, text)
			end
		end)
		G.trap_SendServerCommand = send
		if not ok then
			warn("OpenArena chat: " .. tostring(err))
			return to
		end
		-- G_SayTo's command is `<cmd> "<prefix><text>"`, the text cut at MAX_SAY_TEXT
		local cut = #string.sub(text, 1, C.MAX_SAY_TEXT - 1)
		local bots = {}
		for _, s in sent do
			local cmd, inner = string.match(s.text, '^(t?chat) "(.*)"$')
			if cmd == nil then
				send(s.n, s.text) -- anything else (admin replies) goes out as is
				continue
			end
			local prefix = string.sub(inner, 1, #inner - cut)
			local other = G.g_entities[s.n]
			if bit32.band(other.r.svFlags, C.SVF_BOT) ~= 0 then
				table.insert(bots, { n = s.n, cmd = cmd, prefix = prefix })
			else
				to[s.n] = true
				send(s.n, string.format('rchat %s %s "%s"', message.MessageId, cmd, prefix))
			end
		end
		if #bots > 0 and text ~= "" then
			task.spawn(toBots, bots, text, (sender :: Player).UserId)
		end
		return to
	end

	local function deliver(isTeam: boolean)
		return function(message: TextChatMessage, recipient: TextSource): boolean
			local to = routed[message.MessageId] or route(message, isTeam)
			local p = Players:GetPlayerByUserId(recipient.UserId)
			local n = p and clientOf[p]
			return n ~= nil and to[n] == true
		end
	end
	say.ShouldDeliverCallback = deliver(false)
	team.ShouldDeliverCallback = deliver(true)
end

return Chat
