-- Parses Quake III shader scripts (scripts/*.shader) into plain tables.
-- This is the client's own reading of the shader language, used when the
-- converter's build/shaders.json isn't available and for 2D shaders; the
-- table shape is documented in docs/client-notes.md ("Shader table").
local ShaderParse = {}

local function tokenizer(text: string)
	local i, n = 1, #text
	local t = {}
	-- next token; `crossLine` false stops at the end of the current line
	function t.next(crossLine: boolean): string
		while true do
			while i <= n do
				local c = text:sub(i, i)
				if c == "\n" then
					if not crossLine then
						return ""
					end
					i += 1
				elseif c <= " " then
					i += 1
				else
					break
				end
			end
			if i > n then
				return ""
			end
			local two = text:sub(i, i + 1)
			if two == "//" then
				local e = text:find("\n", i, true)
				i = e or (n + 1)
			elseif two == "/*" then
				local e = text:find("*/", i + 2, true)
				i = if e then e + 2 else n + 1
			else
				break
			end
		end
		local c = text:sub(i, i)
		if c == '"' then
			local e = text:find('"', i + 1, true) or (n + 1)
			local s = text:sub(i + 1, e - 1)
			i = e + 1
			return s
		end
		local s = i
		while i <= n and text:sub(i, i) > " " do
			i += 1
		end
		return text:sub(s, i - 1)
	end
	function t.skipRestOfLine()
		local e = text:find("\n", i, true)
		i = e or (n + 1)
	end
	function t.skipBlock()
		local depth = 1
		while depth > 0 do
			local tok = t.next(true)
			if tok == "" then
				return
			elseif tok == "{" then
				depth += 1
			elseif tok == "}" then
				depth -= 1
			end
		end
	end
	return t
end

local function num(s: string): number
	return tonumber(s) or 0
end

local function lineArgs(tk): { string }
	local out = {}
	while true do
		local tok = tk.next(false)
		if tok == "" then
			return out
		end
		table.insert(out, tok)
	end
end

local function wave(a: { string }, at: number)
	return {
		func = string.lower(a[at] or "sin"),
		base = num(a[at + 1]),
		amp = num(a[at + 2]),
		phase = num(a[at + 3]),
		freq = num(a[at + 4]),
	}
end

local BLEND_SHORT = {
	add = { "gl_one", "gl_one" },
	filter = { "gl_dst_color", "gl_zero" },
	blend = { "gl_src_alpha", "gl_one_minus_src_alpha" },
}

local function parseStage(tk)
	local st = { tcMod = {} }
	while true do
		local tok = tk.next(true)
		if tok == "" or tok == "}" then
			break
		end
		local k = string.lower(tok)
		local a = lineArgs(tk)
		if k == "map" or k == "clampmap" then
			st.map = a[1]
			st.clamp = k == "clampmap"
		elseif k == "animmap" then
			st.animMap = { freq = num(a[1]), images = table.move(a, 2, #a, 1, {}) }
		elseif k == "videomap" then
			st.videoMap = a[1]
		elseif k == "blendfunc" then
			local short = BLEND_SHORT[string.lower(a[1] or "")]
			st.blendFunc = short and { short[1], short[2] } or { string.lower(a[1] or ""), string.lower(a[2] or "") }
		elseif k == "rgbgen" then
			local ty = string.lower(a[1] or "")
			st.rgbGen = { type = ty }
			if ty == "wave" then
				st.rgbGen.wave = wave(a, 2)
			elseif ty == "const" then
				-- rgbGen const ( r g b )
				local v = {}
				for _, x in a do
					if tonumber(x) then
						table.insert(v, tonumber(x))
					end
				end
				st.rgbGen.color = v
			end
		elseif k == "alphagen" then
			local ty = string.lower(a[1] or "")
			st.alphaGen = { type = ty }
			if ty == "wave" then
				st.alphaGen.wave = wave(a, 2)
			elseif ty == "const" then
				st.alphaGen.value = num(a[2])
			elseif ty == "portal" then
				st.alphaGen.range = num(a[2])
			end
		elseif k == "tcgen" or k == "texgen" then
			st.tcGen = string.lower(a[1] or "")
		elseif k == "tcmod" then
			local ty = string.lower(a[1] or "")
			local m = { type = ty }
			if ty == "scroll" then
				m.s, m.t = num(a[2]), num(a[3])
			elseif ty == "scale" then
				m.s, m.t = num(a[2]), num(a[3])
			elseif ty == "rotate" then
				m.degPerSec = num(a[2])
			elseif ty == "turb" then
				-- tcMod turb <base> <amp> <phase> <freq>
				m.wave = { func = "sin", base = num(a[2]), amp = num(a[3]), phase = num(a[4]), freq = num(a[5]) }
			elseif ty == "stretch" then
				m.wave = wave(a, 2)
			elseif ty == "transform" then
				m.m = { num(a[2]), num(a[3]), num(a[4]), num(a[5]), num(a[6]), num(a[7]) }
			end
			table.insert(st.tcMod, m)
		elseif k == "alphafunc" then
			st.alphaFunc = string.lower(a[1] or "")
		elseif k == "depthwrite" then
			st.depthWrite = true
		elseif k == "depthfunc" then
			st.depthFunc = string.lower(a[1] or "")
		elseif k == "detail" then
			st.detail = true
		end
	end
	return st
end

local function parseShader(tk)
	local sh = { stages = {}, surfaceparms = {}, deforms = {}, cull = "front" }
	while true do
		local tok = tk.next(true)
		if tok == "" or tok == "}" then
			break
		end
		if tok == "{" then
			table.insert(sh.stages, parseStage(tk))
		else
			local k = string.lower(tok)
			local a = lineArgs(tk)
			if k == "surfaceparm" then
				sh.surfaceparms[string.lower(a[1] or "")] = true
			elseif k == "skyparms" then
				sh.sky = { outer = a[1], cloudHeight = num(a[2]), inner = a[3] }
			elseif k == "fogparms" then
				local v = {}
				for _, x in a do
					if tonumber(x) then
						table.insert(v, tonumber(x))
					end
				end
				sh.fogParms = { color = { v[1] or 0, v[2] or 0, v[3] or 0 }, depthForOpaque = v[4] or 0 }
			elseif k == "cull" then
				sh.cull = string.lower(a[1] or "front")
			elseif k == "deformvertexes" then
				local d = { type = string.lower(a[1] or "") }
				if d.type == "wave" then
					d.div = num(a[2])
					d.wave = wave(a, 3)
				elseif d.type == "move" then
					d.vec = { num(a[2]), num(a[3]), num(a[4]) }
					d.wave = wave(a, 5)
				elseif d.type == "bulge" then
					d.width, d.height, d.speed = num(a[2]), num(a[3]), num(a[4])
				end
				table.insert(sh.deforms, d)
			elseif k == "sort" then
				sh.sort = a[1]
			elseif k == "nopicmip" or k == "nomipmaps" or k == "polygonoffset" or k == "entitymergable" or k == "portal" then
				sh[k] = true
			elseif k == "sky" then
				sh.sky = { outer = a[1], cloudHeight = 128 }
			end
		end
	end
	return sh
end

-- Parses one .shader file's text into {[lower-case name] = shader}.
function ShaderParse.parse(text: string, into: { [string]: any }?): { [string]: any }
	local out = into or {}
	local tk = tokenizer(text)
	while true do
		local name = tk.next(true)
		if name == "" then
			break
		end
		local brace = tk.next(true)
		if brace ~= "{" then
			-- malformed: skip to the next block
			if brace == "" then
				break
			end
		else
			local sh = parseShader(tk)
			sh.name = name
			local key = string.lower(name):gsub("%.%a+$", "")
			-- the first definition wins, as in Q3 (later files are scanned first there,
			-- but duplicates across OA's own scripts are identical in practice)
			if out[key] == nil then
				out[key] = sh
			end
		end
	end
	return out
end

return ShaderParse
