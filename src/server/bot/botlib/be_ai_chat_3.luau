--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_ai_chat.c, part 3 of 4).

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
-- Luau port of botlib/be_ai_chat.c lines 1509-2214 (chat integrity checks, reply/initial chat loading).

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local QS = require("../../../shared/q_shared")

local ESCAPE_CHAR = 0x01
local MT_VARIABLE = 1
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

local BOTFILESBASEFOLDER = "botfiles"

local function fprintf(fp, fmt, ...)
	fp[#fp + 1] = QS.va(fmt, ...)
end

local function isDeveloper(): boolean
	local d = B.botDeveloper
	return d ~= nil and d ~= false and d ~= 0
end

function B.BotFindStringInList(list, string_)
	local s = list
	while s ~= nil do
		if s.string == string_ then return s end
		s = s.next
	end
	return nil
end

function B.BotCheckChatMessageIntegrety(message, stringlist)
	local msgptr = 0
	while B.ch(message, msgptr) ~= 0 do
		if B.ch(message, msgptr) == ESCAPE_CHAR then
			msgptr = msgptr + 1
			local c = B.ch(message, msgptr)
			if c == string.byte("v") then
				msgptr = msgptr + 1
				while B.ch(message, msgptr) ~= 0 and B.ch(message, msgptr) ~= ESCAPE_CHAR do msgptr = msgptr + 1 end
				if B.ch(message, msgptr) ~= 0 then msgptr = msgptr + 1 end
			elseif c == string.byte("r") then
				msgptr = msgptr + 1
				local start = msgptr
				while B.ch(message, msgptr) ~= 0 and B.ch(message, msgptr) ~= ESCAPE_CHAR do
					msgptr = msgptr + 1
				end
				local temp = string.sub(message, start + 1, msgptr)
				if B.ch(message, msgptr) ~= 0 then msgptr = msgptr + 1 end
				if B.RandomString(temp) == nil then
					if B.BotFindStringInList(stringlist, temp) == nil then
						B.Log_Write("%s = {\"%s\"} //MISSING RANDOM\r\n", temp, temp)
						local s = SB.bot_stringlist_t()
						s.string = temp
						s.next = stringlist
						stringlist = s
					end
				end
			else
				B.botimport.Print(BC.PRT_FATAL, "BotCheckChatMessageIntegrety: message \"%s\" invalid escape char\n", message)
			end
		else
			msgptr = msgptr + 1
		end
	end
	return stringlist
end

function B.BotCheckInitialChatIntegrety(chat)
	local stringlist = nil
	local t = chat.types
	while t ~= nil do
		local cm = t.firstchatmessage
		while cm ~= nil do
			stringlist = B.BotCheckChatMessageIntegrety(cm.chatmessage, stringlist)
			cm = cm.next
		end
		t = t.next
	end
	stringlist = nil
end

function B.BotCheckReplyChatIntegrety(replychat)
	local stringlist = nil
	local rp = replychat
	while rp ~= nil do
		local cm = rp.firstchatmessage
		while cm ~= nil do
			stringlist = B.BotCheckChatMessageIntegrety(cm.chatmessage, stringlist)
			cm = cm.next
		end
		rp = rp.next
	end
	stringlist = nil
end

function B.BotDumpReplyChat(replychat)
	local fp = B.Log_FilePointer()
	if fp == nil then return end
	fprintf(fp, "BotDumpReplyChat:\n")
	local rp = replychat
	while rp ~= nil do
		fprintf(fp, "[")
		local key = rp.keys
		while key ~= nil do
			if bit32.band(key.flags, RCKFL_AND) ~= 0 then fprintf(fp, "&")
			elseif bit32.band(key.flags, RCKFL_NOT) ~= 0 then fprintf(fp, "!") end
			if bit32.band(key.flags, RCKFL_NAME) ~= 0 then fprintf(fp, "name")
			elseif bit32.band(key.flags, RCKFL_GENDERFEMALE) ~= 0 then fprintf(fp, "female")
			elseif bit32.band(key.flags, RCKFL_GENDERMALE) ~= 0 then fprintf(fp, "male")
			elseif bit32.band(key.flags, RCKFL_GENDERLESS) ~= 0 then fprintf(fp, "it")
			elseif bit32.band(key.flags, RCKFL_VARIABLES) ~= 0 then
				fprintf(fp, "(")
				local mp = key.match
				while mp ~= nil do
					if mp.type == MT_STRING then fprintf(fp, "\"%s\"", mp.firststring.string)
					else fprintf(fp, "%d", mp.variable) end
					if mp.next ~= nil then fprintf(fp, ", ") end
					mp = mp.next
				end
				fprintf(fp, ")")
			elseif bit32.band(key.flags, RCKFL_STRING) ~= 0 then
				fprintf(fp, "\"%s\"", key.string)
			end
			if key.next ~= nil then fprintf(fp, ", ")
			else fprintf(fp, "] = %1.0f\n", rp.priority) end
			key = key.next
		end
		fprintf(fp, "{\n")
		local cm = rp.firstchatmessage
		while cm ~= nil do
			fprintf(fp, "\t\"%s\";\n", cm.chatmessage)
			cm = cm.next
		end
		fprintf(fp, "}\n")
		rp = rp.next
	end
end

function B.BotFreeReplyChat(replychat)
	local rp = replychat
	while rp ~= nil do
		local nextrp = rp.next
		local key = rp.keys
		while key ~= nil do
			local nextkey = key.next
			if key.match ~= nil then B.BotFreeMatchPieces(key.match) end
			key.string = nil
			key = nextkey
		end
		rp.keys = nil
		rp.firstchatmessage = nil
		rp = nextrp
	end
end

function B.BotCheckValidReplyChatKeySet(source, keys)
	local allprefixed = true
	local hasvariableskey = false
	local hasstringkey = false
	local key = keys
	while key ~= nil do
		if bit32.band(key.flags, bit32.bor(RCKFL_AND, RCKFL_NOT)) == 0 then
			allprefixed = false
			if bit32.band(key.flags, RCKFL_VARIABLES) ~= 0 then
				local m = key.match
				while m ~= nil do
					if m.type == MT_VARIABLE then hasvariableskey = true end
					m = m.next
				end
			elseif bit32.band(key.flags, RCKFL_STRING) ~= 0 then
				hasstringkey = true
			end
		elseif bit32.band(key.flags, RCKFL_AND) ~= 0 and bit32.band(key.flags, RCKFL_STRING) ~= 0 then
			local key2 = keys
			while key2 ~= nil do
				if key2 ~= key and bit32.band(key2.flags, RCKFL_NOT) == 0 then
					if bit32.band(key2.flags, RCKFL_VARIABLES) ~= 0 then
						local m = key2.match
						while m ~= nil do
							if m.type == MT_STRING then
								local ms = m.firststring
								while ms ~= nil do
									if B.StringContains(ms.string, key.string, false) ~= -1 then
										break
									end
									ms = ms.next
								end
								if ms ~= nil then break end
							elseif m.type == MT_VARIABLE then
								break
							end
							m = m.next
						end
						if m == nil then
							B.SourceWarning(source, "one of the match templates does not "
								.. "leave space for the key %s with the & prefix", key.string)
						end
					end
				end
				key2 = key2.next
			end
		end
		if bit32.band(key.flags, RCKFL_NOT) ~= 0 and bit32.band(key.flags, RCKFL_STRING) ~= 0 then
			local key2 = keys
			while key2 ~= nil do
				if key2 ~= key and bit32.band(key2.flags, RCKFL_NOT) == 0 then
					if bit32.band(key2.flags, RCKFL_STRING) ~= 0 then
						if B.StringContains(key2.string, key.string, false) ~= -1 then
							B.SourceWarning(source, "the key %s with prefix ! is inside the key %s", key.string, key2.string)
						end
					elseif bit32.band(key2.flags, RCKFL_VARIABLES) ~= 0 then
						local m = key2.match
						while m ~= nil do
							if m.type == MT_STRING then
								local ms = m.firststring
								while ms ~= nil do
									if B.StringContains(ms.string, key.string, false) ~= -1 then
										B.SourceWarning(source, "the key %s with prefix ! is inside "
											.. "the match template string %s", key.string, ms.string)
									end
									ms = ms.next
								end
							end
							m = m.next
						end
					end
				end
				key2 = key2.next
			end
		end
		key = key.next
	end
	if allprefixed then B.SourceWarning(source, "all keys have a & or ! prefix") end
	if hasvariableskey and hasstringkey then
		B.SourceWarning(source, "variables from the match template(s) could be "
			.. "invalid when outputting one of the chat messages")
	end
end

function B.BotLoadReplyChat(filename)
	local token = SB.token_t()

	B.PC_SetBaseFolder(BOTFILESBASEFOLDER)
	local source = B.LoadSourceFile(filename)
	if source == nil then
		B.botimport.Print(BC.PRT_ERROR, "couldn't load %s\n", filename)
		return nil
	end

	local replychatlist = nil

	while B.PC_ReadToken(source, token) ~= 0 do
		if token.string ~= "[" then
			B.SourceError(source, "expected [, found %s", token.string)
			B.BotFreeReplyChat(replychatlist)
			B.FreeSource(source)
			return nil
		end

		local replychat = SB.bot_replychat_t()
		replychat.keys = nil
		replychat.next = replychatlist
		replychatlist = replychat
		repeat
			local key = SB.bot_replychatkey_t()
			key.flags = 0
			key.string = nil
			key.match = nil
			key.next = replychat.keys
			replychat.keys = key
			if B.PC_CheckTokenString(source, "&") ~= 0 then key.flags = bit32.bor(key.flags, RCKFL_AND)
			elseif B.PC_CheckTokenString(source, "!") ~= 0 then key.flags = bit32.bor(key.flags, RCKFL_NOT) end
			if B.PC_CheckTokenString(source, "name") ~= 0 then key.flags = bit32.bor(key.flags, RCKFL_NAME)
			elseif B.PC_CheckTokenString(source, "female") ~= 0 then key.flags = bit32.bor(key.flags, RCKFL_GENDERFEMALE)
			elseif B.PC_CheckTokenString(source, "male") ~= 0 then key.flags = bit32.bor(key.flags, RCKFL_GENDERMALE)
			elseif B.PC_CheckTokenString(source, "it") ~= 0 then key.flags = bit32.bor(key.flags, RCKFL_GENDERLESS)
			elseif B.PC_CheckTokenString(source, "(") ~= 0 then
				key.flags = bit32.bor(key.flags, RCKFL_VARIABLES)
				key.match = B.BotLoadMatchPieces(source, ")")
				if key.match == nil then
					B.BotFreeReplyChat(replychatlist)
					return nil
				end
			elseif B.PC_CheckTokenString(source, "<") ~= 0 then
				key.flags = bit32.bor(key.flags, RCKFL_BOTNAMES)
				local namebuffer = ""
				repeat
					if B.PC_ExpectTokenType(source, BC.TT_STRING, 0, token) == 0 then
						B.BotFreeReplyChat(replychatlist)
						B.FreeSource(source)
						return nil
					end
					token.string = B.StripDoubleQuotes(token.string)
					if #namebuffer ~= 0 then namebuffer = namebuffer .. "\\" end
					namebuffer = namebuffer .. token.string
				until B.PC_CheckTokenString(source, ",") == 0
				if B.PC_ExpectTokenString(source, ">") == 0 then
					B.BotFreeReplyChat(replychatlist)
					B.FreeSource(source)
					return nil
				end
				key.string = namebuffer
			else
				key.flags = bit32.bor(key.flags, RCKFL_STRING)
				if B.PC_ExpectTokenType(source, BC.TT_STRING, 0, token) == 0 then
					B.BotFreeReplyChat(replychatlist)
					B.FreeSource(source)
					return nil
				end
				token.string = B.StripDoubleQuotes(token.string)
				key.string = token.string
			end
			B.PC_CheckTokenString(source, ",")
		until B.PC_CheckTokenString(source, "]") ~= 0

		B.BotCheckValidReplyChatKeySet(source, replychat.keys)
		if B.PC_ExpectTokenString(source, "=") == 0 or
			B.PC_ExpectTokenType(source, BC.TT_NUMBER, 0, token) == 0 then
			B.BotFreeReplyChat(replychatlist)
			B.FreeSource(source)
			return nil
		end
		replychat.priority = token.floatvalue
		if B.PC_ExpectTokenString(source, "{") == 0 then
			B.BotFreeReplyChat(replychatlist)
			B.FreeSource(source)
			return nil
		end
		replychat.numchatmessages = 0
		while B.PC_CheckTokenString(source, "}") == 0 do
			local ok, chatmessagestring = B.BotLoadChatMessage(source)
			if ok == 0 then
				B.BotFreeReplyChat(replychatlist)
				B.FreeSource(source)
				return nil
			end
			local chatmessage = SB.bot_chatmessage_t()
			chatmessage.chatmessage = chatmessagestring
			chatmessage.time = -2 * CHATMESSAGE_RECENTTIME
			chatmessage.next = replychat.firstchatmessage
			replychat.firstchatmessage = chatmessage
			replychat.numchatmessages = replychat.numchatmessages + 1
		end
	end
	B.FreeSource(source)
	B.botimport.Print(BC.PRT_MESSAGE, "loaded %s\n", filename)
	if isDeveloper() then
		B.BotCheckReplyChatIntegrety(replychatlist)
	end
	if replychatlist == nil then B.botimport.Print(BC.PRT_MESSAGE, "no rchats\n") end
	return replychatlist
end

function B.BotDumpInitialChat(chat)
	B.Log_Write("{")
	local t = chat.types
	while t ~= nil do
		B.Log_Write(" type \"%s\"", t.name)
		B.Log_Write(" {")
		B.Log_Write("  numchatmessages = %d", t.numchatmessages)
		local m = t.firstchatmessage
		while m ~= nil do
			B.Log_Write("  \"%s\"", m.chatmessage)
			m = m.next
		end
		B.Log_Write(" }")
		t = t.next
	end
	B.Log_Write("}")
end

function B.BotLoadInitialChat(chatfile, chatname)
	local token = SB.token_t()
	local chat = nil
	local chattype = nil
	local foundchat = false

	for pass = 0, 1 do
		B.PC_SetBaseFolder(BOTFILESBASEFOLDER)
		local source = B.LoadSourceFile(chatfile)
		if source == nil then
			B.botimport.Print(BC.PRT_ERROR, "couldn't load %s\n", chatfile)
			return nil
		end
		if pass ~= 0 then
			chat = SB.bot_chat_t()
		end
		while B.PC_ReadToken(source, token) ~= 0 do
			if token.string == "chat" then
				if B.PC_ExpectTokenType(source, BC.TT_STRING, 0, token) == 0 then
					B.FreeSource(source)
					return nil
				end
				token.string = B.StripDoubleQuotes(token.string)
				if B.PC_ExpectTokenString(source, "{") == 0 then
					B.FreeSource(source)
					return nil
				end
				if QS.Q_stricmp(token.string, chatname) == 0 then
					foundchat = true
					while true do
						if B.PC_ExpectAnyToken(source, token) == 0 then
							B.FreeSource(source)
							return nil
						end
						if token.string == "}" then break end
						if token.string ~= "type" then
							B.SourceError(source, "expected type found %s", token.string)
							B.FreeSource(source)
							return nil
						end
						if B.PC_ExpectTokenType(source, BC.TT_STRING, 0, token) == 0 or
							B.PC_ExpectTokenString(source, "{") == 0 then
							B.FreeSource(source)
							return nil
						end
						token.string = B.StripDoubleQuotes(token.string)
						if pass ~= 0 then
							chattype = SB.bot_chattype_t()
							chattype.name = QS.Q_strncpyz(token.string, BC.MAX_CHATTYPE_NAME)
							chattype.firstchatmessage = nil
							chattype.next = chat.types
							chat.types = chattype
						end
						while B.PC_CheckTokenString(source, "}") == 0 do
							local ok, chatmessagestring = B.BotLoadChatMessage(source)
							if ok == 0 then
								B.FreeSource(source)
								return nil
							end
							if pass ~= 0 then
								local chatmessage = SB.bot_chatmessage_t()
								chatmessage.time = -2 * CHATMESSAGE_RECENTTIME
								chatmessage.next = chattype.firstchatmessage
								chattype.firstchatmessage = chatmessage
								chatmessage.chatmessage = chatmessagestring
								chattype.numchatmessages = chattype.numchatmessages + 1
							end
						end
					end
				else
					local indent = 1
					while indent ~= 0 do
						if B.PC_ExpectAnyToken(source, token) == 0 then
							B.FreeSource(source)
							return nil
						end
						if token.string == "{" then indent = indent + 1
						elseif token.string == "}" then indent = indent - 1 end
					end
				end
			else
				B.SourceError(source, "unknown definition %s", token.string)
				B.FreeSource(source)
				return nil
			end
		end
		B.FreeSource(source)
		if not foundchat then
			B.botimport.Print(BC.PRT_ERROR, "couldn't find chat %s in %s\n", chatname, chatfile)
			return nil
		end
	end

	B.botimport.Print(BC.PRT_MESSAGE, "loaded %s from %s\n", chatname, chatfile)
	if isDeveloper() then
		B.BotCheckInitialChatIntegrety(chat)
	end
	return chat
end

function B.BotFreeChatFile(chatstate)
	local cs = B.BotChatStateFromHandle(chatstate)
	if cs == nil then return end
	cs.chat = nil
end

return nil
