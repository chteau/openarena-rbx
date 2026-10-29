--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/l_precomp.c, part 3 of 4).

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
-- Luau port of l_precomp.c (botlib/l_precomp.c, part 3 of 4): #if expression evaluation and conditional directives.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")

local MAX_VALUES = 64
local MAX_OPERATORS = 64

local priorities = {
	[BC.P_MUL] = 15,
	[BC.P_DIV] = 15,
	[BC.P_MOD] = 15,
	[BC.P_ADD] = 14,
	[BC.P_SUB] = 14,
	[BC.P_LOGIC_AND] = 7,
	[BC.P_LOGIC_OR] = 6,
	[BC.P_LOGIC_GEQ] = 12,
	[BC.P_LOGIC_LEQ] = 12,
	[BC.P_LOGIC_EQ] = 11,
	[BC.P_LOGIC_UNEQ] = 11,
	[BC.P_LOGIC_NOT] = 16,
	[BC.P_LOGIC_GREATER] = 12,
	[BC.P_LOGIC_LESS] = 12,
	[BC.P_RSHIFT] = 13,
	[BC.P_LSHIFT] = 13,
	[BC.P_BIN_AND] = 10,
	[BC.P_BIN_OR] = 8,
	[BC.P_BIN_XOR] = 9,
	[BC.P_BIN_NOT] = 16,
	[BC.P_COLON] = 5,
	[BC.P_QUESTIONMARK] = 5,
}

local binaryOperators = {
	[BC.P_MUL] = true,
	[BC.P_DIV] = true,
	[BC.P_MOD] = true,
	[BC.P_ADD] = true,
	[BC.P_LOGIC_AND] = true,
	[BC.P_LOGIC_OR] = true,
	[BC.P_LOGIC_GEQ] = true,
	[BC.P_LOGIC_LEQ] = true,
	[BC.P_LOGIC_EQ] = true,
	[BC.P_LOGIC_UNEQ] = true,
	[BC.P_LOGIC_GREATER] = true,
	[BC.P_LOGIC_LESS] = true,
	[BC.P_RSHIFT] = true,
	[BC.P_LSHIFT] = true,
	[BC.P_BIN_AND] = true,
	[BC.P_BIN_OR] = true,
	[BC.P_BIN_XOR] = true,
	[BC.P_COLON] = true,
	[BC.P_QUESTIONMARK] = true,
}

local function s32(x: number): number
	local u = bit32.band(x, 0xFFFFFFFF)
	if u >= 0x80000000 then
		return u - 0x100000000
	end
	return u
end

local function b2i(b: boolean): number
	if b then
		return 1
	end
	return 0
end

function B.PC_OperatorPriority(op)
	local p = priorities[op]
	if p == nil then
		return 0
	end
	return p
end

function B.PC_EvaluateTokens(source, tokens, integer)
	local o, firstoperator, lastoperator
	local v, firstvalue, lastvalue, v1, v2
	local t
	local brace = false
	local parentheses = 0
	local err = 0
	local lastwasvalue = 0
	local negativevalue = 0
	local questmarkintvalue = 0
	local questmarkfloatvalue = 0
	local gotquestmarkvalue = false

	local numoperators = 0
	local numvalues = 0

	local intvalue = 0
	local floatvalue = 0

	t = tokens
	while t ~= nil do
		repeat
			if t.type == BC.TT_NAME then
				if lastwasvalue ~= 0 or negativevalue ~= 0 then
					B.SourceError(source, "syntax error in #if/#elif")
					err = 1
					break
				end
				if t.string ~= "defined" then
					B.SourceError(source, "undefined name %s in #if/#elif", t.string)
					err = 1
					break
				end
				t = t.next
				if t ~= nil and t.string == "(" then
					brace = true
					t = t.next
				end
				if t == nil or t.type ~= BC.TT_NAME then
					B.SourceError(source, "defined without name in #if/#elif")
					err = 1
					break
				end
				if numvalues >= MAX_VALUES then
					B.SourceError(source, "out of value space")
					err = 1
					break
				end
				v = SB.value_t()
				numvalues = numvalues + 1
				if B.PC_FindHashedDefine(source.definehash, t.string) ~= nil then
					v.intvalue = 1
					v.floatvalue = 1
				else
					v.intvalue = 0
					v.floatvalue = 0
				end
				v.parentheses = parentheses
				v.next = nil
				v.prev = lastvalue
				if lastvalue ~= nil then
					lastvalue.next = v
				else
					firstvalue = v
				end
				lastvalue = v
				if brace then
					t = t.next
					if t == nil or t.string ~= ")" then
						B.SourceError(source, "defined without ) in #if/#elif")
						err = 1
						break
					end
				end
				brace = false
				lastwasvalue = 1
			elseif t.type == BC.TT_NUMBER then
				if lastwasvalue ~= 0 then
					B.SourceError(source, "syntax error in #if/#elif")
					err = 1
					break
				end
				if numvalues >= MAX_VALUES then
					B.SourceError(source, "out of value space")
					err = 1
					break
				end
				v = SB.value_t()
				numvalues = numvalues + 1
				if negativevalue ~= 0 then
					v.intvalue = -s32(t.intvalue)
					v.floatvalue = -t.floatvalue
				else
					v.intvalue = t.intvalue
					v.floatvalue = t.floatvalue
				end
				v.parentheses = parentheses
				v.next = nil
				v.prev = lastvalue
				if lastvalue ~= nil then
					lastvalue.next = v
				else
					firstvalue = v
				end
				lastvalue = v
				lastwasvalue = 1
				negativevalue = 0
			elseif t.type == BC.TT_PUNCTUATION then
				if negativevalue ~= 0 then
					B.SourceError(source, "misplaced minus sign in #if/#elif")
					err = 1
					break
				end
				local st = t.subtype
				if st == BC.P_PARENTHESESOPEN then
					parentheses = parentheses + 1
					break
				elseif st == BC.P_PARENTHESESCLOSE then
					parentheses = parentheses - 1
					if parentheses < 0 then
						B.SourceError(source, "too many ) in #if/#elsif")
						err = 1
					end
					break
				end
				if integer == 0 then
					if
						st == BC.P_BIN_NOT
						or st == BC.P_MOD
						or st == BC.P_RSHIFT
						or st == BC.P_LSHIFT
						or st == BC.P_BIN_AND
						or st == BC.P_BIN_OR
						or st == BC.P_BIN_XOR
					then
						B.SourceError(source, "illigal operator %s on floating point operands", t.string)
						err = 1
						break
					end
				end
				if st == BC.P_LOGIC_NOT or st == BC.P_BIN_NOT then
					if lastwasvalue ~= 0 then
						B.SourceError(source, "! or ~ after value in #if/#elif")
						err = 1
					end
				elseif st == BC.P_INC or st == BC.P_DEC then
					B.SourceError(source, "++ or -- used in #if/#elif")
				elseif st == BC.P_SUB or binaryOperators[st] then
					if st == BC.P_SUB and lastwasvalue == 0 then
						negativevalue = 1
					elseif lastwasvalue == 0 then
						B.SourceError(source, "operator %s after operator in #if/#elif", t.string)
						err = 1
					end
				else
					B.SourceError(source, "invalid operator %s in #if/#elif", t.string)
					err = 1
				end
				if err == 0 and negativevalue == 0 then
					if numoperators >= MAX_OPERATORS then
						B.SourceError(source, "out of operator space")
						err = 1
						break
					end
					o = SB.operator_t()
					numoperators = numoperators + 1
					o.operator = st
					o.priority = B.PC_OperatorPriority(st)
					o.parentheses = parentheses
					o.next = nil
					o.prev = lastoperator
					if lastoperator ~= nil then
						lastoperator.next = o
					else
						firstoperator = o
					end
					lastoperator = o
					lastwasvalue = 0
				end
			else
				B.SourceError(source, "unknown %s in #if/#elif", t.string)
				err = 1
				break
			end
		until true
		if err ~= 0 then
			break
		end
		t = t.next
	end
	if err == 0 then
		if lastwasvalue == 0 then
			B.SourceError(source, "trailing operator in #if/#elif")
			err = 1
		elseif parentheses ~= 0 then
			B.SourceError(source, "too many ( in #if/#elif")
			err = 1
		end
	end

	gotquestmarkvalue = false
	questmarkintvalue = 0
	questmarkfloatvalue = 0
	while err == 0 and firstoperator ~= nil do
		v = firstvalue
		o = firstoperator
		while o.next ~= nil do
			local nxt = o.next
			if o.parentheses > nxt.parentheses then
				break
			end
			if o.parentheses == nxt.parentheses then
				if o.priority >= nxt.priority then
					break
				end
			end
			if o.operator ~= BC.P_LOGIC_NOT and o.operator ~= BC.P_BIN_NOT then
				v = v.next
			end
			if v == nil then
				B.SourceError(source, "mising values in #if/#elif")
				err = 1
				break
			end
			o = o.next
		end
		if err ~= 0 then
			break
		end
		v1 = v
		v2 = v.next
		local op = o.operator
		if op == BC.P_LOGIC_NOT then
			v1.intvalue = b2i(v1.intvalue == 0)
			v1.floatvalue = b2i(v1.floatvalue == 0)
		elseif op == BC.P_BIN_NOT then
			v1.intvalue = s32(bit32.bnot(v1.intvalue))
		elseif op == BC.P_MUL then
			v1.intvalue = s32(v1.intvalue * v2.intvalue)
			v1.floatvalue = v1.floatvalue * v2.floatvalue
		elseif op == BC.P_DIV then
			if v2.intvalue == 0 or v2.floatvalue == 0 then
				B.SourceError(source, "divide by zero in #if/#elif")
				err = 1
			else
				v1.intvalue = Q.idiv(v1.intvalue, v2.intvalue)
				v1.floatvalue = v1.floatvalue / v2.floatvalue
			end
		elseif op == BC.P_MOD then
			if v2.intvalue == 0 then
				B.SourceError(source, "divide by zero in #if/#elif")
				err = 1
			else
				v1.intvalue = Q.imod(v1.intvalue, v2.intvalue)
			end
		elseif op == BC.P_ADD then
			v1.intvalue = s32(v1.intvalue + v2.intvalue)
			v1.floatvalue = v1.floatvalue + v2.floatvalue
		elseif op == BC.P_SUB then
			v1.intvalue = s32(v1.intvalue - v2.intvalue)
			v1.floatvalue = v1.floatvalue - v2.floatvalue
		elseif op == BC.P_LOGIC_AND then
			v1.intvalue = b2i(v1.intvalue ~= 0 and v2.intvalue ~= 0)
			v1.floatvalue = b2i(v1.floatvalue ~= 0 and v2.floatvalue ~= 0)
		elseif op == BC.P_LOGIC_OR then
			v1.intvalue = b2i(v1.intvalue ~= 0 or v2.intvalue ~= 0)
			v1.floatvalue = b2i(v1.floatvalue ~= 0 or v2.floatvalue ~= 0)
		elseif op == BC.P_LOGIC_GEQ then
			v1.intvalue = b2i(v1.intvalue >= v2.intvalue)
			v1.floatvalue = b2i(v1.floatvalue >= v2.floatvalue)
		elseif op == BC.P_LOGIC_LEQ then
			v1.intvalue = b2i(v1.intvalue <= v2.intvalue)
			v1.floatvalue = b2i(v1.floatvalue <= v2.floatvalue)
		elseif op == BC.P_LOGIC_EQ then
			v1.intvalue = b2i(v1.intvalue == v2.intvalue)
			v1.floatvalue = b2i(v1.floatvalue == v2.floatvalue)
		elseif op == BC.P_LOGIC_UNEQ then
			v1.intvalue = b2i(v1.intvalue ~= v2.intvalue)
			v1.floatvalue = b2i(v1.floatvalue ~= v2.floatvalue)
		elseif op == BC.P_LOGIC_GREATER then
			v1.intvalue = b2i(v1.intvalue > v2.intvalue)
			v1.floatvalue = b2i(v1.floatvalue > v2.floatvalue)
		elseif op == BC.P_LOGIC_LESS then
			v1.intvalue = b2i(v1.intvalue < v2.intvalue)
			v1.floatvalue = b2i(v1.floatvalue < v2.floatvalue)
		elseif op == BC.P_RSHIFT then
			v1.intvalue = bit32.arshift(v1.intvalue, v2.intvalue)
		elseif op == BC.P_LSHIFT then
			v1.intvalue = s32(bit32.lshift(v1.intvalue, v2.intvalue))
		elseif op == BC.P_BIN_AND then
			v1.intvalue = s32(bit32.band(v1.intvalue, v2.intvalue))
		elseif op == BC.P_BIN_OR then
			v1.intvalue = s32(bit32.bor(v1.intvalue, v2.intvalue))
		elseif op == BC.P_BIN_XOR then
			v1.intvalue = s32(bit32.bxor(v1.intvalue, v2.intvalue))
		elseif op == BC.P_COLON then
			if not gotquestmarkvalue then
				B.SourceError(source, ": without ? in #if/#elif")
				err = 1
			else
				if integer ~= 0 then
					if questmarkintvalue == 0 then
						v1.intvalue = v2.intvalue
					end
				else
					if questmarkfloatvalue == 0 then
						v1.floatvalue = v2.floatvalue
					end
				end
				gotquestmarkvalue = false
			end
		elseif op == BC.P_QUESTIONMARK then
			if gotquestmarkvalue then
				B.SourceError(source, "? after ? in #if/#elif")
				err = 1
			else
				questmarkintvalue = v1.intvalue
				questmarkfloatvalue = v1.floatvalue
				gotquestmarkvalue = true
			end
		end
		if err ~= 0 then
			break
		end
		if o.operator ~= BC.P_LOGIC_NOT and o.operator ~= BC.P_BIN_NOT then
			if o.operator ~= BC.P_QUESTIONMARK then
				v = v.next
			end
			if v ~= nil then
				if v.prev ~= nil then
					v.prev.next = v.next
				else
					firstvalue = v.next
				end
				if v.next ~= nil then
					v.next.prev = v.prev
				end
			end
		end
		if o.prev ~= nil then
			o.prev.next = o.next
		else
			firstoperator = o.next
		end
		if o.next ~= nil then
			o.next.prev = o.prev
		end
	end
	if firstvalue ~= nil then
		intvalue = firstvalue.intvalue
		floatvalue = firstvalue.floatvalue
	end
	if err == 0 then
		return 1, intvalue, floatvalue
	end
	return 0, 0, 0
end

function B.PC_Evaluate(source, integer)
	local token = SB.token_t()
	local firsttoken, lasttoken
	local t, nexttoken
	local define
	local defined = false

	if B.PC_ReadLine(source, token) == 0 then
		B.SourceError(source, "no value after #if/#elif")
		return 0, 0, 0
	end
	firsttoken = nil
	lasttoken = nil
	repeat
		if token.type == BC.TT_NAME then
			if defined then
				defined = false
				t = B.PC_CopyToken(token)
				t.next = nil
				if lasttoken ~= nil then
					lasttoken.next = t
				else
					firsttoken = t
				end
				lasttoken = t
			elseif token.string == "defined" then
				defined = true
				t = B.PC_CopyToken(token)
				t.next = nil
				if lasttoken ~= nil then
					lasttoken.next = t
				else
					firsttoken = t
				end
				lasttoken = t
			else
				define = B.PC_FindHashedDefine(source.definehash, token.string)
				if define == nil then
					B.SourceError(source, "can't evaluate %s, not defined", token.string)
					return 0, 0, 0
				end
				if B.PC_ExpandDefineIntoSource(source, token, define) == 0 then
					return 0, 0, 0
				end
			end
		elseif token.type == BC.TT_NUMBER or token.type == BC.TT_PUNCTUATION then
			t = B.PC_CopyToken(token)
			t.next = nil
			if lasttoken ~= nil then
				lasttoken.next = t
			else
				firsttoken = t
			end
			lasttoken = t
		else
			B.SourceError(source, "can't evaluate %s", token.string)
			return 0, 0, 0
		end
	until B.PC_ReadLine(source, token) == 0

	local ok, intvalue, floatvalue = B.PC_EvaluateTokens(source, firsttoken, integer)
	if ok == 0 then
		return 0, 0, 0
	end
	t = firsttoken
	while t ~= nil do
		nexttoken = t.next
		B.PC_FreeToken(t)
		t = nexttoken
	end
	return 1, intvalue, floatvalue
end

function B.PC_DollarEvaluate(source, integer)
	local indent
	local defined = false
	local token = SB.token_t()
	local firsttoken, lasttoken
	local t, nexttoken
	local define

	if B.PC_ReadSourceToken(source, token) == 0 then
		B.SourceError(source, "no leading ( after $evalint/$evalfloat")
		return 0, 0, 0
	end
	if B.PC_ReadSourceToken(source, token) == 0 then
		B.SourceError(source, "nothing to evaluate")
		return 0, 0, 0
	end
	indent = 1
	firsttoken = nil
	lasttoken = nil
	repeat
		if token.type == BC.TT_NAME then
			if defined then
				defined = false
				t = B.PC_CopyToken(token)
				t.next = nil
				if lasttoken ~= nil then
					lasttoken.next = t
				else
					firsttoken = t
				end
				lasttoken = t
			elseif token.string == "defined" then
				defined = true
				t = B.PC_CopyToken(token)
				t.next = nil
				if lasttoken ~= nil then
					lasttoken.next = t
				else
					firsttoken = t
				end
				lasttoken = t
			else
				define = B.PC_FindHashedDefine(source.definehash, token.string)
				if define == nil then
					B.SourceError(source, "can't evaluate %s, not defined", token.string)
					return 0, 0, 0
				end
				if B.PC_ExpandDefineIntoSource(source, token, define) == 0 then
					return 0, 0, 0
				end
			end
		elseif token.type == BC.TT_NUMBER or token.type == BC.TT_PUNCTUATION then
			local c = string.sub(token.string, 1, 1)
			if c == "(" then
				indent = indent + 1
			elseif c == ")" then
				indent = indent - 1
			end
			if indent <= 0 then
				break
			end
			t = B.PC_CopyToken(token)
			t.next = nil
			if lasttoken ~= nil then
				lasttoken.next = t
			else
				firsttoken = t
			end
			lasttoken = t
		else
			B.SourceError(source, "can't evaluate %s", token.string)
			return 0, 0, 0
		end
	until B.PC_ReadSourceToken(source, token) == 0

	local ok, intvalue, floatvalue = B.PC_EvaluateTokens(source, firsttoken, integer)
	if ok == 0 then
		return 0, 0, 0
	end
	t = firsttoken
	while t ~= nil do
		nexttoken = t.next
		B.PC_FreeToken(t)
		t = nexttoken
	end
	return 1, intvalue, floatvalue
end

function B.PC_Directive_elif(source)
	local type_, skip = B.PC_PopIndent(source)
	if type_ == 0 or type_ == BC.INDENT_ELSE then
		B.SourceError(source, "misplaced #elif")
		return 0
	end
	local ok, value = B.PC_Evaluate(source, 1)
	if ok == 0 then
		return 0
	end
	skip = if value == 0 then 1 else 0
	B.PC_PushIndent(source, BC.INDENT_ELIF, skip)
	return 1
end

function B.PC_Directive_if(source)
	local ok, value = B.PC_Evaluate(source, 1)
	if ok == 0 then
		return 0
	end
	local skip = if value == 0 then 1 else 0
	B.PC_PushIndent(source, BC.INDENT_IF, skip)
	return 1
end

function B.PC_Directive_line(source)
	B.SourceError(source, "#line directive not supported")
	return 0
end

function B.PC_Directive_error(source)
	local token = SB.token_t()

	token.string = ""
	B.PC_ReadSourceToken(source, token)
	B.SourceError(source, "#error directive: %s", token.string)
	return 0
end

function B.PC_Directive_pragma(source)
	local token = SB.token_t()

	B.SourceWarning(source, "#pragma directive not supported")
	while B.PC_ReadLine(source, token) ~= 0 do
	end
	return 1
end

function B.UnreadSignToken(source)
	local token = SB.token_t()

	token.line = source.scriptstack.line
	token.whitespace_p = source.scriptstack.script_p
	token.endwhitespace_p = source.scriptstack.script_p
	token.linescrossed = 0
	token.string = "-"
	token.type = BC.TT_PUNCTUATION
	token.subtype = BC.P_SUB
	B.PC_UnreadSourceToken(source, token)
end

return nil
