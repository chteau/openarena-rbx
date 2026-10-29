--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_ai_chat.c, part 2 of 4).

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
-- Luau port of be_ai_chat.c lines 770-1508: synonyms, random strings and match templates.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")
local QS = require("../../../shared/q_shared")

local SF = B.FileStatics("be_ai_chat")

local ESCAPE_CHAR = 0x01
local MT_VARIABLE = 1
local MT_STRING = 2
local BOTFILESBASEFOLDER = "botfiles"

-- bot_matchvariable_t.offset is a C signed char
local function toSignedChar(v)
	v = bit32.band(v, 0xFF)
	if v >= 128 then
		return v - 256
	end
	return v
end

function B.BotReplaceSynonyms(str, context)
	local syn = SF.synonyms
	while syn ~= nil do
		if bit32.band(syn.context, context) ~= 0 then
			local synonym = syn.firstsynonym.next
			while synonym ~= nil do
				str = B.StringReplaceWords(str, synonym.string, syn.firstsynonym.string)
				synonym = synonym.next
			end
		end
		syn = syn.next
	end
	return str
end

function B.BotReplaceWeightedSynonyms(str, context)
	local syn = SF.synonyms
	while syn ~= nil do
		if bit32.band(syn.context, context) ~= 0 then
			local weight = Q.random() * syn.totalweight
			if weight ~= 0 then
				local curweight = 0
				local replacement = syn.firstsynonym
				while replacement ~= nil do
					curweight = curweight + replacement.weight
					if weight < curweight then break end
					replacement = replacement.next
				end
				if replacement ~= nil then
					local synonym = syn.firstsynonym
					while synonym ~= nil do
						if synonym ~= replacement then
							str = B.StringReplaceWords(str, synonym.string, replacement.string)
						end
						synonym = synonym.next
					end
				end
			end
		end
		syn = syn.next
	end
	return str
end

function B.BotReplaceReplySynonyms(str, context)
	local str1 = 0
	while B.ch(str, str1) ~= 0 do
		while B.ch(str, str1) ~= 0 and B.ch(str, str1) <= 32 do str1 = str1 + 1 end
		if B.ch(str, str1) == 0 then break end
		local syn = SF.synonyms
		while syn ~= nil do
			local synonym = nil
			if bit32.band(syn.context, context) ~= 0 then
				synonym = syn.firstsynonym.next
				while synonym ~= nil do
					local rest = string.sub(str, str1 + 1)
					local str2 = B.StringContainsWord(rest, synonym.string, false)
					local replaced = false
					if str2 ~= nil and str2 == 0 then
						local replacement = syn.firstsynonym.string
						str2 = B.StringContainsWord(rest, replacement, false)
						if not (str2 ~= nil and str2 == 0) then
							str = string.sub(str, 1, str1) .. replacement .. string.sub(str, str1 + #synonym.string + 1)
							replaced = true
						end
					end
					if replaced then break end
					synonym = synonym.next
				end
			end
			if synonym ~= nil then break end
			syn = syn.next
		end
		while B.ch(str, str1) ~= 0 and B.ch(str, str1) > 32 do str1 = str1 + 1 end
		if B.ch(str, str1) == 0 then break end
	end
	return str
end

function B.BotLoadChatMessage(source)
	local ptr = ""
	local token = SB.token_t()
	while true do
		if B.PC_ExpectAnyToken(source, token) == 0 then return 0, ptr end
		if token.type == BC.TT_STRING then
			token.string = B.StripDoubleQuotes(token.string)
			if #ptr + #token.string + 1 > BC.MAX_MESSAGE_SIZE then
				B.SourceError(source, "chat message too long")
				return 0, ptr
			end
			ptr = ptr .. token.string
		elseif token.type == BC.TT_NUMBER and bit32.band(token.subtype, BC.TT_INTEGER) ~= 0 then
			if #ptr + 7 > BC.MAX_MESSAGE_SIZE then
				B.SourceError(source, "chat message too long")
				return 0, ptr
			end
			ptr = ptr .. QS.va("%cv%d%c", ESCAPE_CHAR, token.intvalue, ESCAPE_CHAR)
		elseif token.type == BC.TT_NAME then
			if #ptr + 7 > BC.MAX_MESSAGE_SIZE then
				B.SourceError(source, "chat message too long")
				return 0, ptr
			end
			ptr = ptr .. QS.va("%cr%s%c", ESCAPE_CHAR, token.string, ESCAPE_CHAR)
		else
			B.SourceError(source, "unknown message component %s", token.string)
			return 0, ptr
		end
		if B.PC_CheckTokenString(source, ";") ~= 0 then break end
		if B.PC_ExpectTokenString(source, ",") == 0 then return 0, ptr end
	end
	return 1, ptr
end

function B.BotDumpRandomStringList(randomlist)
	local fp = B.Log_FilePointer()
	if fp == nil then return end
	local random = randomlist
	while random ~= nil do
		fp[#fp + 1] = QS.va("%s = {", random.string)
		local rs = random.firstrandomstring
		while rs ~= nil do
			fp[#fp + 1] = QS.va("\"%s\"", rs.string)
			if rs.next ~= nil then
				fp[#fp + 1] = ", "
			else
				fp[#fp + 1] = "}\n"
			end
			rs = rs.next
		end
		random = random.next
	end
end

function B.BotLoadRandomStrings(filename)
	local size = 0
	local ptr = false
	local randomlist = nil
	local random = nil

	for pass = 0, 1 do
		if pass ~= 0 and size ~= 0 then ptr = true end
		B.PC_SetBaseFolder(BOTFILESBASEFOLDER)
		local source = B.LoadSourceFile(filename)
		if source == nil then
			B.botimport.Print(BC.PRT_ERROR, "couldn't load %s\n", filename)
			return nil
		end
		randomlist = nil
		local lastrandom = nil
		local token = SB.token_t()
		while B.PC_ReadToken(source, token) ~= 0 do
			if token.type ~= BC.TT_NAME then
				B.SourceError(source, "unknown random %s", token.string)
				B.FreeSource(source)
				return nil
			end
			local len = #token.string + 1
			len = bit32.band(len + 7, bit32.bnot(7))
			size = size + 24 + len
			if pass ~= 0 and ptr then
				random = SB.bot_randomlist_t()
				random.string = token.string
				random.firstrandomstring = nil
				random.numstrings = 0
				if lastrandom ~= nil then
					lastrandom.next = random
				else
					randomlist = random
				end
				lastrandom = random
			end
			if B.PC_ExpectTokenString(source, "=") == 0 or B.PC_ExpectTokenString(source, "{") == 0 then
				B.FreeSource(source)
				return nil
			end
			while B.PC_CheckTokenString(source, "}") == 0 do
				local ok, chatmessagestring = B.BotLoadChatMessage(source)
				if ok == 0 then
					B.FreeSource(source)
					return nil
				end
				len = #chatmessagestring + 1
				len = bit32.band(len + 7, bit32.bnot(7))
				size = size + 16 + len
				if pass ~= 0 and ptr then
					local randomstring = SB.bot_randomstring_t()
					randomstring.string = chatmessagestring
					random.numstrings = random.numstrings + 1
					randomstring.next = random.firstrandomstring
					random.firstrandomstring = randomstring
				end
			end
		end
		B.FreeSource(source)
	end
	B.botimport.Print(BC.PRT_MESSAGE, "loaded %s\n", filename)
	return randomlist
end

function B.RandomString(name)
	local random = SF.randomstrings
	while random ~= nil do
		if random.string == name then
			local i = Q.trunc(Q.random() * random.numstrings)
			local rs = random.firstrandomstring
			while rs ~= nil do
				i = i - 1
				if i < 0 then break end
				rs = rs.next
			end
			if rs ~= nil then
				return rs.string
			end
		end
		random = random.next
	end
	return nil
end

function B.BotDumpMatchTemplates(matches)
	local fp = B.Log_FilePointer()
	if fp == nil then return end
	local mt = matches
	while mt ~= nil do
		fp[#fp + 1] = "{ "
		local mp = mt.first
		while mp ~= nil do
			if mp.type == MT_STRING then
				local ms = mp.firststring
				while ms ~= nil do
					fp[#fp + 1] = QS.va("\"%s\"", ms.string)
					if ms.next ~= nil then fp[#fp + 1] = "|" end
					ms = ms.next
				end
			elseif mp.type == MT_VARIABLE then
				fp[#fp + 1] = QS.va("%d", mp.variable)
			end
			if mp.next ~= nil then fp[#fp + 1] = ", " end
			mp = mp.next
		end
		fp[#fp + 1] = QS.va(" = (%d, %d);}\n", mt.type, mt.subtype)
		mt = mt.next
	end
end

function B.BotFreeMatchPieces(matchpieces)
	local mp = matchpieces
	while mp ~= nil do
		local nextmp = mp.next
		if mp.type == MT_STRING then
			local ms = mp.firststring
			while ms ~= nil do
				local nextms = ms.next
				ms.next = nil
				ms = nextms
			end
			mp.firststring = nil
		end
		mp.next = nil
		mp = nextmp
	end
end

function B.BotLoadMatchPieces(source, endtoken)
	local firstpiece = nil
	local lastpiece = nil
	local lastwasvariable = false
	local token = SB.token_t()

	while B.PC_ReadToken(source, token) ~= 0 do
		if token.type == BC.TT_NUMBER and bit32.band(token.subtype, BC.TT_INTEGER) ~= 0 then
			if token.intvalue >= BC.MAX_MATCHVARIABLES then
				B.SourceError(source, "can't have more than %d match variables", BC.MAX_MATCHVARIABLES)
				B.FreeSource(source)
				B.BotFreeMatchPieces(firstpiece)
				return nil
			end
			if lastwasvariable then
				B.SourceError(source, "not allowed to have adjacent variables")
				B.FreeSource(source)
				B.BotFreeMatchPieces(firstpiece)
				return nil
			end
			lastwasvariable = true
			local matchpiece = SB.bot_matchpiece_t()
			matchpiece.type = MT_VARIABLE
			matchpiece.variable = token.intvalue
			matchpiece.next = nil
			if lastpiece ~= nil then
				lastpiece.next = matchpiece
			else
				firstpiece = matchpiece
			end
			lastpiece = matchpiece
		elseif token.type == BC.TT_STRING then
			local matchpiece = SB.bot_matchpiece_t()
			matchpiece.firststring = nil
			matchpiece.type = MT_STRING
			matchpiece.variable = 0
			matchpiece.next = nil
			if lastpiece ~= nil then
				lastpiece.next = matchpiece
			else
				firstpiece = matchpiece
			end
			lastpiece = matchpiece
			local lastmatchstring = nil
			local emptystring = false
			repeat
				if matchpiece.firststring ~= nil then
					if B.PC_ExpectTokenType(source, BC.TT_STRING, 0, token) == 0 then
						B.FreeSource(source)
						B.BotFreeMatchPieces(firstpiece)
						return nil
					end
				end
				token.string = B.StripDoubleQuotes(token.string)
				local matchstring = SB.bot_matchstring_t()
				matchstring.string = token.string
				if #token.string == 0 then emptystring = true end
				matchstring.next = nil
				if lastmatchstring ~= nil then
					lastmatchstring.next = matchstring
				else
					matchpiece.firststring = matchstring
				end
				lastmatchstring = matchstring
			until B.PC_CheckTokenString(source, "|") == 0
			if not emptystring then lastwasvariable = false end
		else
			B.SourceError(source, "invalid token %s", token.string)
			B.FreeSource(source)
			B.BotFreeMatchPieces(firstpiece)
			return nil
		end
		if B.PC_CheckTokenString(source, endtoken) ~= 0 then break end
		if B.PC_ExpectTokenString(source, ",") == 0 then
			B.FreeSource(source)
			B.BotFreeMatchPieces(firstpiece)
			return nil
		end
	end
	return firstpiece
end

function B.BotFreeMatchTemplates(mt)
	while mt ~= nil do
		local nextmt = mt.next
		B.BotFreeMatchPieces(mt.first)
		mt.next = nil
		mt = nextmt
	end
end

function B.BotLoadMatchTemplates(matchfile)
	B.PC_SetBaseFolder(BOTFILESBASEFOLDER)
	local source = B.LoadSourceFile(matchfile)
	if source == nil then
		B.botimport.Print(BC.PRT_ERROR, "couldn't load %s\n", matchfile)
		return nil
	end
	local matches = nil
	local lastmatch = nil
	local token = SB.token_t()

	while B.PC_ReadToken(source, token) ~= 0 do
		if token.type ~= BC.TT_NUMBER or bit32.band(token.subtype, BC.TT_INTEGER) == 0 then
			B.SourceError(source, "expected integer, found %s", token.string)
			B.BotFreeMatchTemplates(matches)
			B.FreeSource(source)
			return nil
		end
		local context = token.intvalue
		if B.PC_ExpectTokenString(source, "{") == 0 then
			B.BotFreeMatchTemplates(matches)
			B.FreeSource(source)
			return nil
		end
		while B.PC_ReadToken(source, token) ~= 0 do
			if token.string == "}" then break end
			B.PC_UnreadLastToken(source)
			local matchtemplate = SB.bot_matchtemplate_t()
			matchtemplate.context = context
			matchtemplate.next = nil
			if lastmatch ~= nil then
				lastmatch.next = matchtemplate
			else
				matches = matchtemplate
			end
			lastmatch = matchtemplate
			matchtemplate.first = B.BotLoadMatchPieces(source, "=")
			if matchtemplate.first == nil then
				B.BotFreeMatchTemplates(matches)
				return nil
			end
			if B.PC_ExpectTokenString(source, "(") == 0
				or B.PC_ExpectTokenType(source, BC.TT_NUMBER, BC.TT_INTEGER, token) == 0 then
				B.BotFreeMatchTemplates(matches)
				B.FreeSource(source)
				return nil
			end
			matchtemplate.type = token.intvalue
			if B.PC_ExpectTokenString(source, ",") == 0
				or B.PC_ExpectTokenType(source, BC.TT_NUMBER, BC.TT_INTEGER, token) == 0 then
				B.BotFreeMatchTemplates(matches)
				B.FreeSource(source)
				return nil
			end
			matchtemplate.subtype = token.intvalue
			if B.PC_ExpectTokenString(source, ")") == 0 or B.PC_ExpectTokenString(source, ";") == 0 then
				B.BotFreeMatchTemplates(matches)
				B.FreeSource(source)
				return nil
			end
		end
	end
	B.FreeSource(source)
	B.botimport.Print(BC.PRT_MESSAGE, "loaded %s\n", matchfile)
	return matches
end

function B.StringsMatch(pieces, match)
	local lastvariable = -1
	local strptr = 0
	local mp = pieces
	while mp ~= nil do
		if mp.type == MT_STRING then
			local newstrptr = nil
			local ms = mp.firststring
			while ms ~= nil do
				if #ms.string == 0 then
					newstrptr = strptr
					break
				end
				local index = B.StringContains(string.sub(match.string, strptr + 1), ms.string, false)
				if index >= 0 then
					newstrptr = strptr + index
					if lastvariable >= 0 then
						match.variables[lastvariable].length = newstrptr - match.variables[lastvariable].offset
						lastvariable = -1
						break
					elseif index == 0 then
						break
					end
					newstrptr = nil
				end
				ms = ms.next
			end
			if newstrptr == nil then return 0 end
			strptr = newstrptr + #ms.string
		elseif mp.type == MT_VARIABLE then
			match.variables[mp.variable].offset = toSignedChar(strptr)
			lastvariable = mp.variable
		end
		mp = mp.next
	end
	if mp == nil and (lastvariable >= 0 or #match.string - strptr == 0) then
		if lastvariable >= 0 then
			match.variables[lastvariable].length = #match.string - match.variables[lastvariable].offset
		end
		return 1
	end
	return 0
end

function B.BotFindMatch(str, match, context)
	match.string = QS.Q_strncpyz(str, BC.MAX_MESSAGE_SIZE)
	while #match.string > 0 and B.ch(match.string, #match.string - 1) == 10 do
		match.string = string.sub(match.string, 1, #match.string - 1)
	end
	local ms = SF.matchtemplates
	while ms ~= nil do
		if bit32.band(ms.context, context) ~= 0 then
			for i = 0, BC.MAX_MATCHVARIABLES - 1 do match.variables[i].offset = -1 end
			if B.StringsMatch(ms.first, match) ~= 0 then
				match.type = ms.type
				match.subtype = ms.subtype
				return 1
			end
		end
		ms = ms.next
	end
	return 0
end

function B.BotMatchVariable(match, variable, size)
	if variable < 0 or variable >= BC.MAX_MATCHVARIABLES then
		B.botimport.Print(BC.PRT_FATAL, "BotMatchVariable: variable out of range\n")
		return ""
	end

	if match.variables[variable].offset >= 0 then
		if match.variables[variable].length < size then
			size = match.variables[variable].length + 1
		end
		return QS.Q_strncpyz(string.sub(match.string, match.variables[variable].offset + 1), size)
	end
	return ""
end

return nil
