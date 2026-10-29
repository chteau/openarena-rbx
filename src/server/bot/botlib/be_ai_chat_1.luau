--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_ai_chat.c, part 1 of 4).

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
-- Luau port of be_ai_chat.c, part 1 of 4: chat states, console messages,
-- string helpers and synonym loading.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")
local QS = require("../../../shared/q_shared")

local SF = B.FileStatics("be_ai_chat")

local BOTFILESBASEFOLDER = "botfiles"

--escape character
SF.ESCAPE_CHAR = 0x01 --'_'

--match piece types
SF.MT_VARIABLE = 1 --variable match piece
SF.MT_STRING = 2 --string match piece
--reply chat key flags
SF.RCKFL_AND = 1 --key must be present
SF.RCKFL_NOT = 2 --key must be absent
SF.RCKFL_NAME = 4 --name of bot must be present
SF.RCKFL_STRING = 8 --key is a string
SF.RCKFL_VARIABLES = 16 --key is a match template
SF.RCKFL_BOTNAMES = 32 --key is a series of botnames
SF.RCKFL_GENDERFEMALE = 64 --bot must be female
SF.RCKFL_GENDERMALE = 128 --bot must be male
SF.RCKFL_GENDERLESS = 256 --bot must be genderless
--time to ignore a chat message after using it
SF.CHATMESSAGE_RECENTTIME = 20

SF.ichatdata = {}

SF.botchatstates = {}
--console message heap
SF.consolemessageheap = nil
SF.freeconsolemessages = nil
--list with match strings
SF.matchtemplates = nil
--list with synonyms
SF.synonyms = nil
--list with random strings
SF.randomstrings = nil
--reply chats
SF.replychats = nil

local function toupper(c: number): number
	if c >= 97 and c <= 122 then
		return c - 32
	end
	return c
end

function B.BotChatStateFromHandle(handle)
	if handle <= 0 or handle > BC.MAX_CLIENTS then
		B.botimport.Print(BC.PRT_FATAL, "chat state handle %d out of range\n", handle)
		return nil
	end
	if SF.botchatstates[handle] == nil then
		B.botimport.Print(BC.PRT_FATAL, "invalid chat state %d\n", handle)
		return nil
	end
	return SF.botchatstates[handle]
end

--initialize the heap with unused console messages
function B.InitConsoleMessageHeap()
	SF.consolemessageheap = nil
	local max_messages = Q.trunc(B.LibVarValue("max_messages", "1024"))
	local heap = {}
	for i = 0, max_messages - 1 do
		heap[i] = SB.bot_consolemessage_t()
	end
	SF.consolemessageheap = heap
	heap[0].prev = nil
	heap[0].next = heap[1]
	for i = 1, max_messages - 2 do
		heap[i].prev = heap[i - 1]
		heap[i].next = heap[i + 1]
	end
	heap[max_messages - 1].prev = heap[max_messages - 2]
	heap[max_messages - 1].next = nil
	--pointer to the free console messages
	SF.freeconsolemessages = heap[0]
end

--allocate one console message from the heap
function B.AllocConsoleMessage()
	local message = SF.freeconsolemessages
	if SF.freeconsolemessages ~= nil then
		SF.freeconsolemessages = SF.freeconsolemessages.next
	end
	if SF.freeconsolemessages ~= nil then
		SF.freeconsolemessages.prev = nil
	end
	return message
end

--deallocate one console message from the heap
function B.FreeConsoleMessage(message)
	if SF.freeconsolemessages ~= nil then
		SF.freeconsolemessages.prev = message
	end
	message.prev = nil
	message.next = SF.freeconsolemessages
	SF.freeconsolemessages = message
end

function B.BotRemoveConsoleMessage(chatstate, handle)
	local cs = B.BotChatStateFromHandle(chatstate)
	if cs == nil then
		return
	end

	local m = cs.firstmessage
	while m ~= nil do
		local nextm = m.next
		if m.handle == handle then
			if m.next ~= nil then
				m.next.prev = m.prev
			else
				cs.lastmessage = m.prev
			end
			if m.prev ~= nil then
				m.prev.next = m.next
			else
				cs.firstmessage = m.next
			end

			B.FreeConsoleMessage(m)
			cs.numconsolemessages = cs.numconsolemessages - 1
			break
		end
		m = nextm
	end
end

function B.BotQueueConsoleMessage(chatstate, type_, message)
	local cs = B.BotChatStateFromHandle(chatstate)
	if cs == nil then
		return
	end

	local m = B.AllocConsoleMessage()
	if m == nil then
		B.botimport.Print(BC.PRT_ERROR, "empty console message heap\n")
		return
	end
	cs.handle = cs.handle + 1
	if cs.handle <= 0 or cs.handle > 8192 then
		cs.handle = 1
	end
	m.handle = cs.handle
	m.time = B.AAS_Time()
	m.type = type_
	m.message = QS.Q_strncpyz(message, BC.MAX_MESSAGE_SIZE)
	m.next = nil
	if cs.lastmessage ~= nil then
		cs.lastmessage.next = m
		m.prev = cs.lastmessage
		cs.lastmessage = m
	else
		cs.lastmessage = m
		cs.firstmessage = m
		m.prev = nil
	end
	cs.numconsolemessages = cs.numconsolemessages + 1
end

function B.BotNextConsoleMessage(chatstate, cm)
	local cs = B.BotChatStateFromHandle(chatstate)
	if cs == nil then
		return 0
	end
	local firstmsg = cs.firstmessage
	if firstmsg ~= nil then
		cm.handle = firstmsg.handle
		cm.time = firstmsg.time
		cm.type = firstmsg.type
		cm.message = QS.Q_strncpyz(firstmsg.message, BC.MAX_MESSAGE_SIZE)

		-- the two list pointers in cm are deliberately not set; callers don't need them
		return cm.handle
	end
	return 0
end

function B.BotNumConsoleMessages(chatstate)
	local cs = B.BotChatStateFromHandle(chatstate)
	if cs == nil then
		return 0
	end
	return cs.numconsolemessages
end

function B.IsWhiteSpace(c)
	if (c >= 97 and c <= 122)
		or (c >= 65 and c <= 90)
		or (c >= 48 and c <= 57)
		or c == 40 or c == 41 -- ( )
		or c == 63 or c == 58 -- ? :
		or c == 39 or c == 47 -- ' /
		or c == 44 or c == 46 -- , .
		or c == 91 or c == 93 -- [ ]
		or c == 45 or c == 95 -- - _
		or c == 43 or c == 61 then -- + =
		return 0
	end
	return 1
end

function B.BotRemoveTildes(message)
	--remove all tildes from the chat message
	local i = 0
	while B.ch(message, i) ~= 0 do
		if B.ch(message, i) == 126 then
			message = string.sub(message, 1, i) .. string.sub(message, i + 2)
		end
		i = i + 1
	end
	return message
end

function B.UnifyWhiteSpaces(str)
	local ptr = 0
	local oldptr = 0
	while B.ch(str, ptr) ~= 0 do
		while B.ch(str, ptr) ~= 0 and B.IsWhiteSpace(B.ch(str, ptr)) ~= 0 do
			ptr = ptr + 1
		end
		if ptr > oldptr then
			--if not at the start and not at the end of the string
			--write only one space
			if oldptr > 0 and B.ch(str, ptr) ~= 0 then
				str = string.sub(str, 1, oldptr) .. " " .. string.sub(str, oldptr + 2)
				oldptr = oldptr + 1
			end
			--remove all other white spaces
			if ptr > oldptr then
				str = string.sub(str, 1, oldptr) .. string.sub(str, ptr + 1)
			end
		end
		while B.ch(str, ptr) ~= 0 and B.IsWhiteSpace(B.ch(str, ptr)) == 0 do
			ptr = ptr + 1
		end
		oldptr = ptr
	end
	return str
end

function B.StringContains(str1, str2, casesensitive)
	if str1 == nil or str2 == nil then
		return -1
	end

	local len = #str1 - #str2
	for i = 0, len do
		local j = 0
		while B.ch(str2, j) ~= 0 do
			if casesensitive ~= 0 then
				if B.ch(str1, i + j) ~= B.ch(str2, j) then
					break
				end
			else
				if toupper(B.ch(str1, i + j)) ~= toupper(B.ch(str2, j)) then
					break
				end
			end
			j = j + 1
		end
		if B.ch(str2, j) == 0 then
			return i
		end
	end
	return -1
end

-- returns the 0-based offset of the word in str1, or nil
function B.StringContainsWord(str1, str2, casesensitive)
	local len = #str1 - #str2
	local p = 0
	for i = 0, len do
		--if not at the start of the string
		if i ~= 0 then
			--skip to the start of the next word
			while B.ch(str1, p) ~= 0 and B.ch(str1, p) ~= 32 and B.ch(str1, p) ~= 46
				and B.ch(str1, p) ~= 44 and B.ch(str1, p) ~= 33 do
				p = p + 1
			end
			if B.ch(str1, p) == 0 then
				break
			end
			p = p + 1
		end
		--compare the word
		local j = 0
		while B.ch(str2, j) ~= 0 do
			if casesensitive then
				if B.ch(str1, p + j) ~= B.ch(str2, j) then
					break
				end
			else
				if toupper(B.ch(str1, p + j)) ~= toupper(B.ch(str2, j)) then
					break
				end
			end
			j = j + 1
		end
		--if there was a word match
		if B.ch(str2, j) == 0 then
			--if the first string has an end of word
			local c = B.ch(str1, p + j)
			if c == 0 or c == 32 or c == 46 or c == 44 or c == 33 then
				return p
			end
		end
		p = p + 1
	end
	return nil
end

local function ContainsWordFrom(str: string, base: number, word: string): number?
	local r = B.StringContainsWord(string.sub(str, base + 1), word, false)
	if r == nil then
		return nil
	end
	return r + base
end

function B.StringReplaceWords(str, synonym, replacement)
	--find the synonym in the string
	local at = B.StringContainsWord(str, synonym, false)
	--if the synonym occurred in the string
	while at ~= nil do
		--if the synonym isn't part of the replacement which is already in the string
		--useful for abbreviations
		local str2 = B.StringContainsWord(str, replacement, false)
		while str2 ~= nil do
			if str2 <= at and at < str2 + #replacement then
				break
			end
			str2 = ContainsWordFrom(str, str2 + 1, replacement)
		end
		if str2 == nil then
			--append the synonum replacement
			str = string.sub(str, 1, at) .. replacement .. string.sub(str, at + #synonym + 1)
		end
		--find the next synonym in the string
		at = ContainsWordFrom(str, at + #replacement, synonym)
	end
	return str
end

function B.BotDumpSynonymList(synlist)
	local fp = B.Log_FilePointer()
	if fp == nil then
		return
	end
	local syn = synlist
	while syn ~= nil do
		fp[#fp + 1] = string.format("%d : [", syn.context)
		local synonym = syn.firstsynonym
		while synonym ~= nil do
			fp[#fp + 1] = string.format("(\"%s\", %1.2f)", synonym.string, synonym.weight)
			if synonym.next ~= nil then
				fp[#fp + 1] = ", "
			end
			synonym = synonym.next
		end
		fp[#fp + 1] = "]\n"
		syn = syn.next
	end
end

function B.BotLoadSynonyms(filename)
	local contextstack = {}
	local have = false
	local size = 0
	local synlist = nil
	local syn = nil
	local synonym = nil
	--the synonyms are parsed in two phases
	for pass = 0, 1 do
		if pass ~= 0 and size ~= 0 then
			have = true
		end
		B.PC_SetBaseFolder(BOTFILESBASEFOLDER)
		local source = B.LoadSourceFile(filename)
		if source == nil then
			B.botimport.Print(BC.PRT_ERROR, "couldn't load %s\n", filename)
			return nil
		end

		local context = 0
		local contextlevel = 0
		synlist = nil --list synonyms
		local lastsyn = nil --last synonym in the list
		local token = SB.token_t()

		while B.PC_ReadToken(source, token) ~= 0 do
			if token.type == BC.TT_NUMBER then
				context = bit32.bor(context, token.intvalue)
				contextstack[contextlevel] = token.intvalue
				contextlevel = contextlevel + 1
				if contextlevel >= 32 then
					B.SourceError(source, "more than 32 context levels")
					B.FreeSource(source)
					return nil
				end
				if B.PC_ExpectTokenString(source, "{") == 0 then
					B.FreeSource(source)
					return nil
				end
			elseif token.type == BC.TT_PUNCTUATION then
				if token.string == "}" then
					contextlevel = contextlevel - 1
					if contextlevel < 0 then
						B.SourceError(source, "too many }")
						B.FreeSource(source)
						return nil
					end
					context = bit32.band(context, bit32.bnot(contextstack[contextlevel]))
				elseif token.string == "[" then
					size = size + --[[sizeof(bot_synonymlist_t)]] 32
					if pass ~= 0 and have then
						syn = SB.bot_synonymlist_t()
						syn.context = context
						syn.firstsynonym = nil
						syn.next = nil
						if lastsyn ~= nil then
							lastsyn.next = syn
						else
							synlist = syn
						end
						lastsyn = syn
					end
					local numsynonyms = 0
					local lastsynonym = nil
					while true do
						if B.PC_ExpectTokenString(source, "(") == 0
							or B.PC_ExpectTokenType(source, BC.TT_STRING, 0, token) == 0 then
							B.FreeSource(source)
							return nil
						end
						token.string = B.StripDoubleQuotes(token.string)
						if #token.string <= 0 then
							B.SourceError(source, "empty string")
							B.FreeSource(source)
							return nil
						end
						local len = #token.string + 1
						len = bit32.band(len + 7, bit32.bnot(7)) --PAD(len, sizeof(long))
						size = size + --[[sizeof(bot_synonym_t)]] 24 + len
						if pass ~= 0 and have then
							synonym = SB.bot_synonym_t()
							synonym.string = token.string
							if lastsynonym ~= nil then
								lastsynonym.next = synonym
							else
								syn.firstsynonym = synonym
							end
							lastsynonym = synonym
						end
						numsynonyms = numsynonyms + 1
						if B.PC_ExpectTokenString(source, ",") == 0
							or B.PC_ExpectTokenType(source, BC.TT_NUMBER, 0, token) == 0
							or B.PC_ExpectTokenString(source, ")") == 0 then
							B.FreeSource(source)
							return nil
						end
						if pass ~= 0 and have then
							synonym.weight = token.floatvalue
							syn.totalweight = syn.totalweight + synonym.weight
						end
						if B.PC_CheckTokenString(source, "]") ~= 0 then
							break
						end
						if B.PC_ExpectTokenString(source, ",") == 0 then
							B.FreeSource(source)
							return nil
						end
					end
					if numsynonyms < 2 then
						B.SourceError(source, "synonym must have at least two entries")
						B.FreeSource(source)
						return nil
					end
				else
					B.SourceError(source, "unexpected %s", token.string)
					B.FreeSource(source)
					return nil
				end
			end
		end

		B.FreeSource(source)

		if contextlevel > 0 then
			B.SourceError(source, "missing }")
			return nil
		end
	end
	B.botimport.Print(BC.PRT_MESSAGE, "loaded %s\n", filename)

	return synlist
end

return nil
