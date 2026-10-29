local BC = require("../../src/server/bot/botlib/consts")
local SB = require("../../src/server/bot/botlib/structs")
local AC = require("../../src/server/bot/ai_consts")
local SA = require("../../src/server/bot/ai_structs")
local n = 0
for k, f in SB do if type(f) == "function" and not k:find("^copy_") and k ~= "arr" and k ~= "vec3" and k ~= "deepcopy" then local t = f(); SB["copy_" .. k](f(), t); n += 1 end end
for k, f in SA do if type(f) == "function" and not k:find("^copy_") and k ~= "arr" and k ~= "vec3" and k ~= "deepcopy" then local t = f(); SA["copy_" .. k](f(), t); n += 1 end end
print("structs ok", n, BC.TFL_DEFAULT, AC.INVENTORY_HEALTH, AC.CHARACTERISTIC_AIM_ACCURACY)
