-- Game rule unit tests (lune run tests/server/test_rules.luau): the
-- damage / armor / quad formulas, item respawn timers, the CTF capture
-- and return flows and the 0.8.8 numbering, run on the real game code with
-- fake clients. Expected values are computed here from OpenArena 0.8.8's C
-- (gamecode 9e0f0c0: g_combat.c CheckArmor, g_weapon.c, g_items.c
-- RESPAWN_* and LaunchItem's 30 s flag return, g_main.c's cvar defaults),
-- not by calling the port.
local W = require("./world")
local K = require("../../src/shared/consts")
local S = require("../../src/shared/structs")

local failures, passes = 0, 0
local function eq(got: any, want: any, what: string)
	if got == want then
		passes += 1
	else
		failures += 1
		print(string.format("FAIL: %s: got %s, want %s", what, tostring(got), tostring(want)))
	end
end

local band = bit32.band
local ARMOR_PROTECTION = 0.66 -- bg_public.h, a double constant

-- CheckArmor: save = ceil(damage * ARMOR_PROTECTION), at most the armor
local function expectArmor(damage: number, armor: number): (number, number)
	local save = math.ceil(damage * ARMOR_PROTECTION)
	if save >= armor then
		save = armor
	end
	return damage - save, save
end

local function setup(gametype: number, map: string, names: { string })
	local w = W.new()
	w:command("set g_gametype " .. gametype)
	w:command("set g_doWarmup 0")
	w:command("set fraglimit 0")
	w:command("set timelimit 0")
	w:command("set capturelimit 0")
	w:command("map " .. map)
	local cs = {}
	for i, n in names do
		cs[i] = w:connect(n)
	end
	w:run(1.5)
	return w, cs
end

local function ent(w, clientNum)
	return w.G.g_entities[clientNum]
end

-- 1. damage, armor and quad
do
	local w, cs = setup(K.GT_FFA, "oa_dm1", { "Attacker", "Target" })
	local G = w.G
	local a, t = ent(w, cs[1].clientNum), ent(w, cs[2].clientNum)
	local dir = { [0] = 1, 0, 0 }

	for _, case in {
		{ dmg = 100, armor = 100 },
		{ dmg = 100, armor = 50 },
		{ dmg = 33, armor = 200 },
		{ dmg = 7, armor = 0 },
		{ dmg = 150, armor = 75 },
	} do
		t.health = 200
		t.client.ps.stats[K.STAT_HEALTH] = 200
		t.client.ps.stats[K.STAT_ARMOR] = case.armor
		G.G_Damage(t, a, a, dir, t.r.currentOrigin, case.dmg, 0, K.MOD_RAILGUN)
		local take, save = expectArmor(case.dmg, case.armor)
		eq(t.health, 200 - take, string.format("G_Damage %d on %d armor: health", case.dmg, case.armor))
		eq(t.client.ps.stats[K.STAT_ARMOR], case.armor - save, string.format("G_Damage %d on %d armor: armor left", case.dmg, case.armor))
	end

	-- self damage is halved (after knockback), then armor applies
	a.health = 100
	a.client.ps.stats[K.STAT_ARMOR] = 0
	G.G_Damage(a, a, a, dir, a.r.currentOrigin, 100, 0, K.MOD_ROCKET_SPLASH)
	eq(a.health, 50, "self damage is halved")

	-- handicap: damage * max_health / 100
	a.health = 100
	t.health = 100
	t.client.ps.stats[K.STAT_ARMOR] = 0
	local savedMax = a.client.ps.stats[K.STAT_MAX_HEALTH]
	a.client.ps.stats[K.STAT_MAX_HEALTH] = 50
	G.G_Damage(t, a, a, dir, t.r.currentOrigin, 40, 0, K.MOD_RAILGUN)
	eq(t.health, 100 - (40 * 50 // 100), "handicap 50 halves damage")
	a.client.ps.stats[K.STAT_MAX_HEALTH] = savedMax

	-- quad: the railgun does 100 * g_quadfactor through FireWeapon
	local quad = w.Game.Cvar.VariableValue("g_quadfactor")
	eq(quad, 3, "g_quadfactor default")
	-- put the target 128 units in front of the attacker, both on the ground
	local o = a.client.ps.origin
	local function place(e, x, y, z, yaw)
		local origin = { [0] = x, y, z }
		G.TeleportPlayer(e, origin, { [0] = 0, yaw, 0 })
	end
	-- pick a direction with room for the shot
	local yaw, dx, dy = 0, 1, 0
	for _, d in { { 0, 1, 0 }, { 90, 0, 1 }, { 180, -1, 0 }, { 270, 0, -1 } } do
		local tr = S.trace_t()
		local eye = { [0] = o[0], o[1], o[2] + 26 }
		G.trap_Trace(tr, eye, nil, nil, { [0] = eye[0] + d[2] * 400, eye[1] + d[3] * 400, eye[2] }, a.s.number, K.MASK_SOLID)
		if tr.fraction == 1 then
			yaw, dx, dy = d[1], d[2], d[3]
			break
		end
	end
	place(a, o[0], o[1], o[2], yaw)
	place(t, o[0] + dx * 160, o[1] + dy * 160, o[2], yaw + 180)
	w:run(0.2) -- let the teleport events and the spawn protection settle
	t.health = 1000
	t.client.ps.stats[K.STAT_ARMOR] = 0
	a.client.ps.powerups[K.PW_QUAD] = G.level.time + 30000
	a.client.ps.stats[K.STAT_WEAPONS] = bit32.bor(a.client.ps.stats[K.STAT_WEAPONS], bit32.lshift(1, K.WP_RAILGUN))
	a.client.ps.ammo[K.WP_RAILGUN] = 10
	a.client.ps.weapon = K.WP_RAILGUN
	a.s.weapon = K.WP_RAILGUN
	a.client.ps.viewangles[0], a.client.ps.viewangles[1], a.client.ps.viewangles[2] = 0, yaw, 0
	t.client.ps.powerups[K.PW_BATTLESUIT] = 0
	t.client.spawnprotected = false
	G.FireWeapon(a)
	eq(1000 - t.health, 100 * 3, "railgun with quad does 100 * g_quadfactor")
	a.client.ps.powerups[K.PW_QUAD] = 0
	t.health = 1000
	G.FireWeapon(a)
	eq(1000 - t.health, 100, "railgun without quad does 100")
end

-- 2. item respawn timers
do
	local function respawnCase(gametype, map, wanted: { [string]: number })
		local w, cs = setup(gametype, map, { "Picker" })
		local G = w.G
		local p = ent(w, cs[1].clientNum)
		local trace = S.trace_t()
		for classname, seconds in wanted do
			local it = G.G_Find(nil, "classname", classname)
			while it and (it.wait ~= 0 or it.random ~= 0) do
				it = G.G_Find(it, "classname", classname)
			end
			if not it then
				print("SKIP: no " .. classname .. " on " .. map)
				continue
			end
			-- make the item worth picking up
			p.health = 10
			p.client.ps.stats[K.STAT_HEALTH] = 10
			p.client.ps.stats[K.STAT_ARMOR] = 0
			p.client.ps.stats[K.STAT_WEAPONS] = bit32.lshift(1, K.WP_MACHINEGUN)
			for i = 0, 15 do
				p.client.ps.ammo[i] = 0
			end
			-- powerups first appear 45 +- 15 s into the level (FinishSpawningItem)
			for _ = 1, 70 do
				if band(it.s.eFlags, K.EF_NODRAW) == 0 then
					break
				end
				w:run(1)
			end
			eq(band(it.s.eFlags, K.EF_NODRAW), 0, classname .. " is there before the pickup")
			G.Touch_Item(it, p, trace)
			eq(band(it.s.eFlags, K.EF_NODRAW) ~= 0, true, classname .. " is hidden after the pickup")
			eq(it.r.contents, 0, classname .. " can't be touched while respawning")
			eq(it.nextthink - G.level.time, seconds * 1000, classname .. " respawn time")
			-- just before: still hidden; after: back
			w:run(seconds - 0.2)
			eq(band(it.s.eFlags, K.EF_NODRAW) ~= 0, true, classname .. " still hidden before the timer")
			w:run(0.4)
			eq(band(it.s.eFlags, K.EF_NODRAW), 0, classname .. " respawned after " .. seconds .. " s")
			eq(it.r.contents, K.CONTENTS_TRIGGER, classname .. " touchable again")
		end
	end
	-- g_items.c: weapons g_weaponrespawn (5) / g_weaponTeamRespawn (30) in
	-- TDM, RESPAWN_ARMOR 25, RESPAWN_HEALTH 35, RESPAWN_MEGAHEALTH 35,
	-- RESPAWN_AMMO 40, RESPAWN_POWERUP 120
	respawnCase(K.GT_FFA, "ps37ctf", {
		weapon_railgun = 5,
		item_armor_combat = 25,
		item_health = 35,
		item_health_mega = 35,
		ammo_shells = 40,
		item_regen = 120,
	})
	respawnCase(K.GT_TEAM, "oa_dm4", { weapon_rocketlauncher = 30 })
end

-- 3. CTF capture and return
do
	local w, cs = setup(K.GT_CTF, "oa_ctf2", { "Red", "Blue" })
	local G = w.G
	cs[1]:addReliableCommand("team red")
	cs[2]:addReliableCommand("team blue")
	w:run(5) -- respawn delay after the team change
	local red, blue = ent(w, cs[1].clientNum), ent(w, cs[2].clientNum)
	eq(red.client.sess.sessionTeam, K.TEAM_RED, "red player is on red")
	eq(blue.client.sess.sessionTeam, K.TEAM_BLUE, "blue player is on blue")
	local redFlag = G.G_Find(nil, "classname", "team_CTF_redflag")
	local blueFlag = G.G_Find(nil, "classname", "team_CTF_blueflag")
	local trace = S.trace_t()

	-- red takes the blue flag
	G.Touch_Item(blueFlag, red, trace)
	eq(red.client.ps.powerups[K.PW_BLUEFLAG] ~= 0, true, "red carries the blue flag")
	eq(G.teamgame.blueStatus, K.FLAG_TAKEN, "blue flag status: taken")

	-- and brings it to the red flag at base
	local before = G.level.teamScores[K.TEAM_RED]
	G.Touch_Item(redFlag, red, trace)
	eq(G.level.teamScores[K.TEAM_RED], before + 1, "capture scores one point for red")
	eq(red.client.ps.powerups[K.PW_BLUEFLAG], 0, "the carrier drops the flag on capture")
	eq(G.teamgame.blueStatus, K.FLAG_ATBASE, "the captured flag goes back to base")
	eq(red.client.ps.persistant[K.PERS_CAPTURES], 1, "the capture is credited")

	-- red takes it again and dies: the flag drops
	w:run(1)
	G.Touch_Item(blueFlag, red, trace)
	eq(G.teamgame.blueStatus, K.FLAG_TAKEN, "blue flag taken again")
	red.client.ps.stats[K.STAT_ARMOR] = 0
	G.G_Damage(red, blue, blue, nil, nil, 1000, w.Game.C.DAMAGE_NO_PROTECTION, K.MOD_RAILGUN)
	eq(G.teamgame.blueStatus, K.FLAG_DROPPED, "killing the carrier drops the flag")
	local dropped = nil
	local e = G.G_Find(nil, "classname", "team_CTF_blueflag")
	while e do
		if band(e.flags, w.Game.C.FL_DROPPED_ITEM) ~= 0 then
			dropped = e
		end
		e = G.G_Find(e, "classname", "team_CTF_blueflag")
	end
	eq(dropped ~= nil, true, "a dropped blue flag entity exists")

	-- a blue player touching it returns it
	if dropped then
		w:run(1) -- dropped items can't be picked up in their first second
		local returnsBefore = blue.client.pers.teamState.flagrecovery
		G.Touch_Item(dropped, blue, trace)
		eq(G.teamgame.blueStatus, K.FLAG_ATBASE, "touching our dropped flag returns it")
		eq(blue.client.pers.teamState.flagrecovery, returnsBefore + 1, "the return is credited")
	end

	-- dropped and left alone, it returns by itself: LaunchItem gives
	-- dropped flags Team_DroppedFlagThink 30 s later (g_team.h's
	-- CTF_FLAG_RETURN_TIME of 40 s is never used)
	-- red respawns (dead players come back by pressing attack)
	cs[1].wish.buttons = 1
	for _ = 1, 100 do
		if red.health > 0 and red.client.ps.pm_type == 0 then
			break
		end
		w:step(50)
	end
	cs[1].wish.buttons = 0
	eq(red.health > 0, true, "red respawned")
	G.Touch_Item(blueFlag, red, trace)
	G.G_Damage(red, blue, blue, nil, nil, 1000, w.Game.C.DAMAGE_NO_PROTECTION, K.MOD_RAILGUN)
	eq(G.teamgame.blueStatus, K.FLAG_DROPPED, "dropped again")
	w:run(29)
	eq(G.teamgame.blueStatus, K.FLAG_DROPPED, "still dropped after 29 s")
	w:run(1.5)
	eq(G.teamgame.blueStatus, K.FLAG_ATBASE, "auto-returned after 30 s")
end

-- 4. 0.8.8 numbering and modes (bg_public.h, g_main.c): the client and
-- the wire format index stats and gametypes by these numbers
do
	eq(K.STAT_HOLDABLE_ITEM, 1, "STAT_HOLDABLE_ITEM")
	eq(K.STAT_PERSISTANT_POWERUP, 2, "STAT_PERSISTANT_POWERUP comes before STAT_WEAPONS")
	eq(K.STAT_WEAPONS, 3, "STAT_WEAPONS")
	eq(K.STAT_MAX_HEALTH, 7, "STAT_MAX_HEALTH is last")
	eq(K.GT_DOMINATION, 12, "GT_DOMINATION")
	eq(K.GT_MAX_GAME_TYPE, 13, "no Possession gametype")
	eq(K.EV_TAUNT_PATROL, 82, "EV_TAUNT_PATROL is the last event")
	eq(K.EV_FOOTSTEP_SNOW, nil, "no extra footstep / bullet-hit events")
	eq(#require("../../src/shared/BG").eventnames, 75, "eventnames[] ends at EV_TAUNT, as in 0.8.8's bg_misc.c")
	eq(K.MAX_TOTALANIMATIONS, 37, "no OA3 torso / strafe animations")
	local w = W.new()
	w:command("set g_gametype 13")
	w:command("map oa_dm1")
	w:run(0.5)
	eq(w.G.g_gametype.integer, 0, "g_gametype 13 is out of range and falls back to FFA")
	eq(w.Game.Cvar.VariableString("g_voteGametypes"), "/0/1/3/4/5/6/7/8/9/10/11/12/", "g_voteGametypes default")
	eq(w.Game.Cvar.VariableString("g_voteNames"), "/map_restart/nextmap/map/g_gametype/kick/clientkick/g_doWarmup/timelimit/fraglimit/shuffle/", "g_voteNames default has shuffle")
	eq(w.Game.Cvar.FindVar("g_enableQ"), nil, "no g_enableQ")
end

-- the roster (tools/oaconv/roster.json): the host mounts the scripts and
-- skins as the place ships them (tools/roster.py), so dropped bots are
-- unknown, arenas name kept bots, and a dropped model becomes sarge
do
	local w, cs = setup(K.GT_FFA, "oa_dm1", { "Player" })
	local G = w.G
	-- G_AddBot prints "Bot '<name>' not defined" when this finds nothing
	-- (tests/bots/roster.luau runs the addbot itself, with AAS loaded)
	for _, name in { "neko", "Angelyss", "merman", "headcrash", "kyonshi", "major", "sorceress", "jenna" } do
		eq(G.G_GetBotInfoByName(name), nil, "no bot " .. name)
	end
	eq(G.G_GetBotInfoByName("Sergei") ~= nil, true, "Sergei is still a bot")
	local QS = require("../../src/shared/q_shared")
	local bots, i = {}, 0
	while G.G_GetBotInfoByNumber(i) do
		table.insert(bots, string.lower(QS.Info_ValueForKey(G.G_GetBotInfoByNumber(i), "name")))
		i += 1
	end
	eq(table.concat(bots, " "), "assassin ghost beret morgan gargoyle broadklin cyber-garg liz penguin sarge andriy grism sergei skelebot metalbot grunt s_marine tony", "the bots left")
	local arena = G.G_GetArenaInfoByMap("oa_dm1")
	eq(QS.Info_ValueForKey(arena, "bots"), "sarge", "oa_dm1's Sorceress is Sarge")

	local n = cs[1].clientNum
	local function modelAfter(model: string, head: string): string
		local info = G.trap_GetUserinfo(n)
		info = QS.Info_SetValueForKey(info, "model", model)
		info = QS.Info_SetValueForKey(info, "headmodel", head)
		G.trap_SetUserinfo(n, info)
		G.ClientUserinfoChanged(n)
		local cs = G.trap_GetConfigstring(K.CS_PLAYERS + n)
		return QS.Info_ValueForKey(cs, "model") .. " " .. QS.Info_ValueForKey(cs, "hmodel")
	end
	eq(modelAfter("neko", "neko/red"), "sarge sarge", "model neko falls back to sarge")
	eq(modelAfter("beret/headcrash", "merman"), "sarge sarge", "dropped skin and head fall back to sarge")
	eq(modelAfter("tony/blue", "sergei"), "tony/blue sergei", "kept models stay")
end

print(string.format("rules: %d passed, %d failed", passes, failures))
require("@lune/process").exit(if failures > 0 then 1 else 0)
