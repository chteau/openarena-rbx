--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_ai_chat.c, part 4 of 4).

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
-- Luau port of be_ai_chat.c (botlib/be_ai_chat.c, part 4 of 4): chat file loading, message construction, replies, state management.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")
local QS = require("../../../shared/q_shared")

local SF = B.FileStatics("be_ai_chat")

local ESCAPE_CHAR = 0x01
local MT_STRING = 2
local RCKFL_AND = 1
local RCKFL_NOT = 2
local RCKFL_NAME = 4
local RCKFL_STRING = 8
local RCKFL_VARIABLES = 16
local RCKFL_BOTNAMES = 32
local RCKFL_GENDERFEMALE = 64
local RCKFL_GENDERMALE = 128
local RCKFL_GENDERLESS = 256
local CHATMESSAGE_RECENTTIME = 20
local MAX_MATCHVARIABLES = 8

local function toSignedChar(v)
	v = bit32.band(v, 0xFF)
	if v >= 128 then
		return v - 256
	end
	return v
end

local function addMatchVariable(match, num, var, index)
	match.string = match.string .. var
	match.variables[num].offset = toSignedChar(index)
	match.variables[num].length = #var
	return index + #var
end

function B.BotLoadChatFile(chatstate, chatfile, chatname)
	local avail = 0

	local cs = B.BotChatStateFromHandle(chatstate)
	if cs == nil then return BC.BLERR_CANNOTLOADICHAT end
	B.BotFreeChatFile(chatstate)

	if B.LibVarGetValue("bot_reloadcharacters") == 0 then
		avail = -1
		for n = 0, BC.MAX_CLIENTS - 1 do
			local data = SF.ichatdata[n]
			if data == nil then
				if avail == -1 then
					avail = n
				end
			elseif chatfile == data.filename and chatname == data.chatname then
				cs.chat = data.chat
				return BC.BLERR_NOERROR
			end
		end

		if avail == -1 then
			B.botimport.Print(BC.PRT_FATAL, "ichatdata table full; couldn't load chat %s from %s\n", chatname, chatfile)
			return BC.BLERR_CANNOTLOADICHAT
		end
	end

	cs.chat = B.BotLoadInitialChat(chatfile, chatname)
	if cs.chat == nil then
		B.botimport.Print(BC.PRT_FATAL, "couldn't load chat %s from %s\n", chatname, chatfile)
		return BC.BLERR_CANNOTLOADICHAT
	end
	if B.LibVarGetValue("bot_reloadcharacters") == 0 then
		local data = SB.bot_ichatdata_t()
		data.chat = cs.chat
		data.chatname = QS.Q_strncpyz(chatname, BC.MAX_QPATH)
		data.filename = QS.Q_strncpyz(chatfile, BC.MAX_QPATH)
		SF.ichatdata[avail] = data
	end

	return BC.BLERR_NOERROR
end

-- returns (expansion, outmessage)
function B.BotExpandChatMessage(outmessage, message, mcontext, match, vcontext, reply)
	local expansion = 0
	local msgptr = 0
	local out = ""
	local len = 0

	while B.ch(message, msgptr) ~= 0 do
		if B.ch(message, msgptr) == ESCAPE_CHAR then
			msgptr = msgptr + 1
			local c = B.ch(message, msgptr)
			if c == string.byte("v") then
				msgptr = msgptr + 1
				local num = 0
				while B.ch(message, msgptr) ~= 0 and B.ch(message, msgptr) ~= ESCAPE_CHAR do
					num = num * 10 + B.ch(message, msgptr) - string.byte("0")
					msgptr = msgptr + 1
				end
				if B.ch(message, msgptr) ~= 0 then msgptr = msgptr + 1 end
				if num > MAX_MATCHVARIABLES then
					B.botimport.Print(BC.PRT_ERROR, "BotConstructChat: message %s variable %d out of range\n", message, num)
					return 0, out
				end
				local var = match.variables[num]
				if var ~= nil and var.offset >= 0 then
					local temp = string.sub(match.string, var.offset + 1, var.offset + var.length)
					if reply ~= 0 then
						temp = B.BotReplaceReplySynonyms(temp, vcontext)
					else
						temp = B.BotReplaceSynonyms(temp, vcontext)
					end
					if len + #temp >= BC.MAX_MESSAGE_SIZE then
						B.botimport.Print(BC.PRT_ERROR, "BotConstructChat: message %s too long\n", message)
						return 0, out
					end
					out = out .. temp
					len = len + #temp
				end
			elseif c == string.byte("r") then
				msgptr = msgptr + 1
				local start = msgptr
				while B.ch(message, msgptr) ~= 0 and B.ch(message, msgptr) ~= ESCAPE_CHAR do
					msgptr = msgptr + 1
				end
				local temp = string.sub(message, start + 1, msgptr)
				if B.ch(message, msgptr) ~= 0 then msgptr = msgptr + 1 end
				local ptr = B.RandomString(temp)
				if ptr == nil then
					B.botimport.Print(BC.PRT_ERROR, "BotConstructChat: unknown random string %s\n", temp)
					return 0, out
				end
				if len + #ptr >= BC.MAX_MESSAGE_SIZE then
					B.botimport.Print(BC.PRT_ERROR, "BotConstructChat: message \"%s\" too long\n", message)
					return 0, out
				end
				out = out .. ptr
				len = len + #ptr
				expansion = 1
			else
				B.botimport.Print(BC.PRT_FATAL, "BotConstructChat: message \"%s\" invalid escape char\n", message)
			end
		else
			out = out .. string.sub(message, msgptr + 1, msgptr + 1)
			msgptr = msgptr + 1
			len = len + 1
			if len >= BC.MAX_MESSAGE_SIZE then
				B.botimport.Print(BC.PRT_ERROR, "BotConstructChat: message \"%s\" too long\n", message)
				break
			end
		end
	end
	out = B.BotReplaceWeightedSynonyms(out, mcontext)
	return expansion, out
end

function B.BotConstructChatMessage(chatstate, message, mcontext, match, vcontext, reply)
	local srcmessage = message
	local i = 0
	while i < 10 do
		local expansion, out = B.BotExpandChatMessage(chatstate.chatmessage, srcmessage, mcontext, match, vcontext, reply)
		chatstate.chatmessage = out
		if expansion == 0 then
			break
		end
		srcmessage = chatstate.chatmessage
		i = i + 1
	end
	if i >= 10 then
		B.botimport.Print(BC.PRT_WARNING, "too many expansions in chat message\n")
		B.botimport.Print(BC.PRT_WARNING, "%s\n", chatstate.chatmessage)
	end
end

-- randomly chooses one of the chat message of the given type
function B.BotChooseInitialChatMessage(cs, type)
	local chat = cs.chat
	local t = chat.types
	while t ~= nil do
		if QS.Q_stricmp(t.name, type) == 0 then
			local numchatmessages = 0
			local m = t.firstchatmessage
			while m ~= nil do
				if not (m.time > B.AAS_Time()) then
					numchatmessages = numchatmessages + 1
				end
				m = m.next
			end
			if numchatmessages <= 0 then
				local besttime = 0
				local bestchatmessage = nil
				m = t.firstchatmessage
				while m ~= nil do
					if besttime == 0 or m.time < besttime then
						bestchatmessage = m
						besttime = m.time
					end
					m = m.next
				end
				if bestchatmessage ~= nil then return bestchatmessage.chatmessage end
			else
				local n = Q.trunc(Q.random() * numchatmessages)
				m = t.firstchatmessage
				while m ~= nil do
					if not (m.time > B.AAS_Time()) then
						n = n - 1
						if n < 0 then
							m.time = B.AAS_Time() + CHATMESSAGE_RECENTTIME
							return m.chatmessage
						end
					end
					m = m.next
				end
			end
			return nil
		end
		t = t.next
	end
	return nil
end

function B.BotNumInitialChats(chatstate, type)
	local cs = B.BotChatStateFromHandle(chatstate)
	if cs == nil then return 0 end

	local t = cs.chat.types
	while t ~= nil do
		if QS.Q_stricmp(t.name, type) == 0 then
			if B.LibVarGetValue("bot_testichat") ~= 0 then
				B.botimport.Print(BC.PRT_MESSAGE, "%s has %d chat lines\n", type, t.numchatmessages)
				B.botimport.Print(BC.PRT_MESSAGE, "-------------------\n")
			end
			return t.numchatmessages
		end
		t = t.next
	end
	return 0
end

function B.BotInitialChat(chatstate, type, mcontext, var0, var1, var2, var3, var4, var5, var6, var7)
	local cs = B.BotChatStateFromHandle(chatstate)
	if cs == nil then return end
	if cs.chat == nil then return end
	local message = B.BotChooseInitialChatMessage(cs, type)
	if message == nil then
		return
	end
	local match = SB.bot_match_t()
	local index = 0
	if var0 ~= nil then index = addMatchVariable(match, 0, var0, index) end
	if var1 ~= nil then index = addMatchVariable(match, 1, var1, index) end
	if var2 ~= nil then index = addMatchVariable(match, 2, var2, index) end
	if var3 ~= nil then index = addMatchVariable(match, 3, var3, index) end
	if var4 ~= nil then index = addMatchVariable(match, 4, var4, index) end
	if var5 ~= nil then index = addMatchVariable(match, 5, var5, index) end
	if var6 ~= nil then index = addMatchVariable(match, 6, var6, index) end
	if var7 ~= nil then addMatchVariable(match, 7, var7, index) end
	B.BotConstructChatMessage(cs, message, mcontext, match, 0, 0)
end

function B.BotPrintReplyChatKeys(replychat)
	B.botimport.Print(BC.PRT_MESSAGE, "[")
	local key = replychat.keys
	while key ~= nil do
		local flags = key.flags
		if bit32.band(flags, RCKFL_AND) ~= 0 then B.botimport.Print(BC.PRT_MESSAGE, "&")
		elseif bit32.band(flags, RCKFL_NOT) ~= 0 then B.botimport.Print(BC.PRT_MESSAGE, "!") end
		if bit32.band(flags, RCKFL_NAME) ~= 0 then B.botimport.Print(BC.PRT_MESSAGE, "name")
		elseif bit32.band(flags, RCKFL_GENDERFEMALE) ~= 0 then B.botimport.Print(BC.PRT_MESSAGE, "female")
		elseif bit32.band(flags, RCKFL_GENDERMALE) ~= 0 then B.botimport.Print(BC.PRT_MESSAGE, "male")
		elseif bit32.band(flags, RCKFL_GENDERLESS) ~= 0 then B.botimport.Print(BC.PRT_MESSAGE, "it")
		elseif bit32.band(flags, RCKFL_VARIABLES) ~= 0 then
			B.botimport.Print(BC.PRT_MESSAGE, "(")
			local mp = key.match
			while mp ~= nil do
				if mp.type == MT_STRING then B.botimport.Print(BC.PRT_MESSAGE, "\"%s\"", mp.firststring.string)
				else B.botimport.Print(BC.PRT_MESSAGE, "%d", mp.variable) end
				if mp.next ~= nil then B.botimport.Print(BC.PRT_MESSAGE, ", ") end
				mp = mp.next
			end
			B.botimport.Print(BC.PRT_MESSAGE, ")")
		elseif bit32.band(flags, RCKFL_STRING) ~= 0 then
			B.botimport.Print(BC.PRT_MESSAGE, "\"%s\"", key.string)
		end
		if key.next ~= nil then B.botimport.Print(BC.PRT_MESSAGE, ", ")
		else B.botimport.Print(BC.PRT_MESSAGE, "] = %1.0f\n", replychat.priority) end
		key = key.next
	end
	B.botimport.Print(BC.PRT_MESSAGE, "{\n")
end

function B.BotReplyChat(chatstate, message, mcontext, vcontext, var0, var1, var2, var3, var4, var5, var6, var7)
	local cs = B.BotChatStateFromHandle(chatstate)
	if cs == nil then return 0 end
	local match = SB.bot_match_t()
	local bestmatch = SB.bot_match_t()
	match.string = message
	local bestpriority = -1
	local bestchatmessage = nil
	local bestrchat = nil
	local rchat = SF.replychats
	while rchat ~= nil do
		local found = false
		local key = rchat.keys
		while key ~= nil do
			local res = false
			local flags = key.flags
			if bit32.band(flags, RCKFL_NAME) ~= 0 then res = (B.StringContains(message, cs.name, false) ~= -1)
			elseif bit32.band(flags, RCKFL_BOTNAMES) ~= 0 then res = (B.StringContains(key.string, cs.name, false) ~= -1)
			elseif bit32.band(flags, RCKFL_GENDERFEMALE) ~= 0 then res = (cs.gender == BC.CHAT_GENDERFEMALE)
			elseif bit32.band(flags, RCKFL_GENDERMALE) ~= 0 then res = (cs.gender == BC.CHAT_GENDERMALE)
			elseif bit32.band(flags, RCKFL_GENDERLESS) ~= 0 then res = (cs.gender == BC.CHAT_GENDERLESS)
			elseif bit32.band(flags, RCKFL_VARIABLES) ~= 0 then res = (B.StringsMatch(key.match, match) ~= 0)
			elseif bit32.band(flags, RCKFL_STRING) ~= 0 then res = (B.StringContainsWord(message, key.string, false) ~= nil) end
			if bit32.band(flags, RCKFL_AND) ~= 0 then
				if not res then
					found = false
					break
				end
			elseif bit32.band(flags, RCKFL_NOT) ~= 0 then
				if res then
					found = false
					break
				end
			elseif res then
				found = true
			end
			key = key.next
		end
		if found then
			if rchat.priority > bestpriority then
				local numchatmessages = 0
				local m = rchat.firstchatmessage
				while m ~= nil do
					if not (m.time > B.AAS_Time()) then
						numchatmessages = numchatmessages + 1
					end
					m = m.next
				end
				local num = Q.trunc(Q.random() * numchatmessages)
				m = rchat.firstchatmessage
				while m ~= nil do
					num = num - 1
					if num < 0 then break end
					m = m.next
				end
				if m ~= nil then
					SB.copy_bot_match_t(bestmatch, match)
					bestchatmessage = m
					bestrchat = rchat
					bestpriority = rchat.priority
				end
			end
		end
		rchat = rchat.next
	end
	if bestchatmessage ~= nil then
		local index = #bestmatch.string
		if var0 ~= nil then index = addMatchVariable(bestmatch, 0, var0, index) end
		if var1 ~= nil then index = addMatchVariable(bestmatch, 1, var1, index) end
		if var2 ~= nil then index = addMatchVariable(bestmatch, 2, var2, index) end
		if var3 ~= nil then index = addMatchVariable(bestmatch, 3, var3, index) end
		if var4 ~= nil then index = addMatchVariable(bestmatch, 4, var4, index) end
		if var5 ~= nil then index = addMatchVariable(bestmatch, 5, var5, index) end
		if var6 ~= nil then index = addMatchVariable(bestmatch, 6, var6, index) end
		if var7 ~= nil then addMatchVariable(bestmatch, 7, var7, index) end
		if B.LibVarGetValue("bot_testrchat") ~= 0 then
			local m = bestrchat.firstchatmessage
			while m ~= nil do
				B.BotConstructChatMessage(cs, m.chatmessage, mcontext, bestmatch, vcontext, 1)
				cs.chatmessage = B.BotRemoveTildes(cs.chatmessage)
				B.botimport.Print(BC.PRT_MESSAGE, "%s\n", cs.chatmessage)
				m = m.next
			end
		else
			bestchatmessage.time = B.AAS_Time() + CHATMESSAGE_RECENTTIME
			B.BotConstructChatMessage(cs, bestchatmessage.chatmessage, mcontext, bestmatch, vcontext, 1)
		end
		return 1
	end
	return 0
end

function B.BotChatLength(chatstate)
	local cs = B.BotChatStateFromHandle(chatstate)
	if cs == nil then return 0 end
	return #cs.chatmessage
end

function B.BotEnterChat(chatstate, clientto, sendto)
	local cs = B.BotChatStateFromHandle(chatstate)
	if cs == nil then return end

	if #cs.chatmessage ~= 0 then
		cs.chatmessage = B.BotRemoveTildes(cs.chatmessage)
		if B.LibVarGetValue("bot_testichat") ~= 0 then
			B.botimport.Print(BC.PRT_MESSAGE, "%s\n", cs.chatmessage)
		else
			if sendto == BC.CHAT_TEAM then
				B.EA_Command(cs.client, QS.va("say_team %s", cs.chatmessage))
			elseif sendto == BC.CHAT_TELL then
				B.EA_Command(cs.client, QS.va("tell %d %s", clientto, cs.chatmessage))
			else
				B.EA_Command(cs.client, QS.va("say %s", cs.chatmessage))
			end
		end
		cs.chatmessage = ""
	end
end

function B.BotGetChatMessage(chatstate, size)
	local cs = B.BotChatStateFromHandle(chatstate)
	if cs == nil then return "" end

	cs.chatmessage = B.BotRemoveTildes(cs.chatmessage)
	local buf = QS.Q_strncpyz(cs.chatmessage, size)
	cs.chatmessage = ""
	return buf
end

function B.BotSetChatGender(chatstate, gender)
	local cs = B.BotChatStateFromHandle(chatstate)
	if cs == nil then return end
	if gender == BC.CHAT_GENDERFEMALE then cs.gender = BC.CHAT_GENDERFEMALE
	elseif gender == BC.CHAT_GENDERMALE then cs.gender = BC.CHAT_GENDERMALE
	else cs.gender = BC.CHAT_GENDERLESS end
end

function B.BotSetChatName(chatstate, name, client)
	local cs = B.BotChatStateFromHandle(chatstate)
	if cs == nil then return end
	cs.client = client
	cs.name = QS.Q_strncpyz(name, 32)
end

function B.BotResetChatAI()
	local rchat = SF.replychats
	while rchat ~= nil do
		local m = rchat.firstchatmessage
		while m ~= nil do
			m.time = 0
			m = m.next
		end
		rchat = rchat.next
	end
end

function B.BotAllocChatState()
	for i = 1, BC.MAX_CLIENTS do
		if SF.botchatstates[i] == nil then
			SF.botchatstates[i] = SB.bot_chatstate_t()
			return i
		end
	end
	return 0
end

function B.BotFreeChatState(handle)
	if handle <= 0 or handle > BC.MAX_CLIENTS then
		B.botimport.Print(BC.PRT_FATAL, "chat state handle %d out of range\n", handle)
		return
	end
	if SF.botchatstates[handle] == nil then
		B.botimport.Print(BC.PRT_FATAL, "invalid chat state %d\n", handle)
		return
	end
	if B.LibVarGetValue("bot_reloadcharacters") ~= 0 then
		B.BotFreeChatFile(handle)
	end
	local m = SB.bot_consolemessage_t()
	local h = B.BotNextConsoleMessage(handle, m)
	while h ~= 0 do
		B.BotRemoveConsoleMessage(handle, h)
		h = B.BotNextConsoleMessage(handle, m)
	end
	SF.botchatstates[handle] = nil
end

function B.BotSetupChatAI()
	local file = B.LibVarString("synfile", "syn.c")
	SF.synonyms = B.BotLoadSynonyms(file)
	file = B.LibVarString("rndfile", "rnd.c")
	SF.randomstrings = B.BotLoadRandomStrings(file)
	file = B.LibVarString("matchfile", "match.c")
	SF.matchtemplates = B.BotLoadMatchTemplates(file)
	if B.LibVarValue("nochat", "0") == 0 then
		file = B.LibVarString("rchatfile", "rchat.c")
		SF.replychats = B.BotLoadReplyChat(file)
	end

	B.InitConsoleMessageHeap()

	return BC.BLERR_NOERROR
end

function B.BotShutdownChatAI()
	for i = 0, BC.MAX_CLIENTS - 1 do
		if SF.botchatstates[i] ~= nil then
			B.BotFreeChatState(i)
		end
	end
	for i = 0, BC.MAX_CLIENTS - 1 do
		if SF.ichatdata[i] ~= nil then
			SF.ichatdata[i] = nil
		end
	end
	SF.consolemessageheap = nil
	if SF.matchtemplates ~= nil then B.BotFreeMatchTemplates(SF.matchtemplates) end
	SF.matchtemplates = nil
	SF.randomstrings = nil
	SF.synonyms = nil
	if SF.replychats ~= nil then B.BotFreeReplyChat(SF.replychats) end
	SF.replychats = nil
end

return nil
