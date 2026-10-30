-- The chat line (sys/Chat.luau) and the console's line wrapping.

H.test("chat.field", function()
	local C = H.require("client/q/Consts")
	local Chat = H.require("client/sys/Chat")
	local f = Chat.field
	for _, ch in { "h", "e", "l", "o" } do
		Chat.Key(0, ch)
	end
	Chat.Key(C.K_LEFTARROW)
	Chat.Key(0, "l")
	H.eq(f.buffer, "hello")
	Chat.Key(C.K_HOME)
	Chat.Key(C.K_DEL)
	Chat.Key(C.K_END)
	Chat.Key(C.K_BACKSPACE)
	H.eq(f.buffer, "ell")
	H.eq(f.cursor, 3)
	Chat.Key(C.K_ESCAPE)
	H.eq(f.buffer, "")
end)

H.test("chat.nochat", function()
	local C = H.require("client/q/Consts")
	local Chat = H.require("client/sys/Chat")
	local Keys = H.require("client/sys/Keys")
	local cmds = {}
	Chat.Register({ AddCommand = function(name, fn)
		cmds[name] = fn
	end }, function()
		return 1
	end)
	-- no OACanChat attribute: no prompt
	cmds.messagemode()
	cmds.messagemode2()
	cmds.messagemode3()
	H.eq(bit32.band(Keys.GetCatcher(), C.KEYCATCH_MESSAGE), 0)
end)

H.test("chat.join", function()
	local Chat = H.require("client/sys/Chat")
	local got = {}
	local function drain()
		Chat.Drain(function(cmd, line)
			table.insert(got, cmd .. "|" .. line)
		end)
	end
	Chat.Frame("a", "chat", "Name^7\25: ^2")
	drain()
	H.eq(#got, 0)
	Chat.Text("a", "hi &lt;3")
	Chat.Text("a", "hi &lt;3") -- the sender also gets SendAsync's copy
	Chat.Text("b", "####")
	Chat.Frame("b", "tchat", "\25(Name^7\25)\25: ^5")
	Chat.Frame("c", "print", "x")
	drain()
	H.eq(#got, 2)
	H.eq(got[1], "chat|Name^7\25: ^2hi <3")
	H.eq(got[2], "tchat|\25(Name^7\25)\25: ^5####")
end)

H.test("console.wrap", function()
	local Console = H.require("client/sys/Console")
	H.require("client/sys/R2D").width = 640
	local n = #Console.lines
	-- 78 columns (640 / 8 - 2)
	Console.Print(string.rep("abcd ", 20) .. "\n")
	H.eq(#Console.lines, n + 2)
	H.eq(Console.lines[n + 1], string.rep("abcd ", 15))
	Console.Print("^1red " .. string.rep("x", 80) .. "\n")
	-- CL_ConsolePrint measures the rest of the word at every character, so
	-- a word longer than the line breaks where its tail first fits
	H.eq(Console.lines[n + 3], "^1red xxx")
	H.eq(Console.lines[n + 4], "^1" .. string.rep("x", 77))
end)
