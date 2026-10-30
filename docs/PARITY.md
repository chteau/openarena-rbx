# Parity checklist

Status of every map, weapon, item, mode and HUD/menu screen against
OpenArena 0.8.8. Evidence kinds:

- **play**: seen in a Roblox playtest started from rbx-native
  (`docs/assembly-notes.md`, shots in `docs/parity/play/` and the
  play comparisons `ctf2_red_side.png` and `dm1_spawn_side.png`, ours
  left and OA 0.8.8 right, same origin and yaw via `setviewpos`);
- **sweep**: the server with 4 bots for 60 game seconds on the map's
  converted blobs (`docs/parity/sweep.txt`);
- **tests**: `tests/server/test_integration.luau` (every mode, fake
  clients, wire check), `tests/server/test_rules.luau` (damage, armor,
  items, CTF flows against 0.8.8's C), `tests/smoke.luau` (cgame and q3_ui
  frames), `tests/run.luau`;
- **edit**: `scripts/parity.py` fixtures in the editor (`hud_side`,
  `scores_side`, `menu_side`, see `docs/client-notes.md`).

Across the board in the playtest: **players and bots are invisible** (the
sandbox experience refuses EditableMesh), map surfaces whose atlas page has
no id yet are white, and nothing plays sound until the sound atlases have
ids. These are listed once here, not on every row.

## Modes

| mode | status | evidence |
|---|---|---|
| Free For All | works | play (oa_dm1 with 3 bots: join, move, shoot, frags, scoreboard); tests |
| Capture The Flag | works | play (oa_ctf2: spectator, `team red`, CTF HUD, bot team orders, a flag taken and returned; `ctf2_red_side.png`); tests (captures and returns in test_rules). Bots fall off oa_ctf2 often (9 `MOD_TRIGGER_HURT` deaths in about a minute): not compared with OA yet |
| Tournament | server only | tests |
| Team Deathmatch | server only | tests |
| One Flag CTF | server only | tests |
| Overload | server only | tests |
| Harvester | server only | tests |
| Elimination | server only | tests |
| CTF Elimination | server only | tests |
| Last Man Standing | server only | tests |
| Double Domination | server only | tests |
| Domination | server only | tests (no shipped map has domination points; the test adds three) |
| Single Player (arena ladder) | menu only | play (level select draws); the ladder flow was not played |
| instagib, all-rockets modifiers | server only | tests |

## HUD and menu screens

| screen | status | evidence |
|---|---|---|
| main menu | draws; no 3D banner, background is the baked frame | play `menu_main.png`; edit `menu_side.png` |
| single player level select | draws | play `menu_sp.png` |
| first connect (name, rate) | draws, accepts | play `first_connect.png` (was crashing: fixed) |
| multiplayer / server browser -> local server | works | play (join path used for every playtest) |
| Arena Servers (Internet / Local / Favorites tabs, sort, gametype filter, show full/empty, SERVER INFO, Join) | works on Roblox servers; ping `?` except for your own server, nettype `RBX` | play on Sober `servers/internet_public.png`, `servers/favorites.png`, `servers/internet_after_teleport.png`, MCP `servers/browser_local.png`; tests (servers.test) |
| Specify (join by code) | works; port ignored | play `servers/specify_code.png` -> `servers/rejoin_private.png` (empty private server restarted with its settings) |
| Add to favorites | works, saved per user in a DataStore | play `servers/private_serverinfo.png`, `servers/favorites.png` (read back in the next server) |
| Start Server -> reserved server | works; "Pure Server" is "Public Server" (listed or code only) | play `servers/start_server_options.png`, `servers/private_arrival_ingame.png`; CTF settings (capturelimit, timelimit, maxclients, bots per team) seen in the server's InitGame |
| host in-game menu (ADD BOTS, REMOVE BOTS, RESTART ARENA) and Start Server from the host | works (rcon allow-list, no `say`) | play `servers/host_ingame_menu.png`, `servers/host_addbots.png`, `servers/host_apply_ctf.png` |
| Single Player arena in a solo reserved server | works | play `servers/sp_solo.png` |
| public server rotation (FFA / TDM / CTF, bot_minplayers) | works | play (rotation with bots, registry entry dumped server side); tests (test_servers) |
| password-protected servers (needPass menu) | not ported | Roblox reserved servers are private by code instead |
| loading screen (map, items) | draws | play `loading.png` |
| HUD: health, ammo, armor, weapon icon, score boxes, pickup line, crosshair, crosshair names | draws | play `dm1_respawn.png`, `dm1_pickup.png`, `dm1_firing.png`; edit `hud_side.png` |
| HUD: CTF flag status and team scores, team chat | draws | play `ctf2_red.png`, `ctf2_red_side.png` |
| HUD: 3D head and 3D icons | missing | EditableMesh refused (2D icons drawn where OA allows `cg_draw3dIcons 0`) |
| first-person weapon | draws | play `dm1_respawn.png`, `dm1_spawn_side.png` |
| textured world, lightmaps, sky | matches at the same viewpoint | play `dm1_spawn_side.png`, `ctf2_red_side.png` (both maps with all atlas pages) |
| scoreboard (FFA) | draws | play `dm1_fragged_scores.png`; edit `scores_side.png` |
| scoreboard (team) | not checked in play | smoke |
| "Fragged by", "Click FIRE to respawn", spectator banner | draws | play `dm1_fragged_scores.png`, `ctf2_spectator.png` |
| in-game menu, team join menu, setup screens, vote menus, demos, mods, credits | ported, not opened in play | smoke (menu frames) |
| console | ported, not opened in play (F10 does not reach the embedded client) | - |
| no Roblox player list, chat window, input bar or bubbles | done | play `chat/menu_no_playerlist.png` and every shot in `chat/` |
| Tab: OA's scoreboard (`+scores`, default.cfg) | works | play `chat/tab_scores.png` |
| notify lines (3 lines, `con_notifytime`, word wrap, colours) | matches | play `chat/bot_taunts.png`; OA `ref/chat_say.png` |
| `say:` prompt (T, `messagemode`) and `say_team:` (`messagemode2`, no default key as in 0.8.8) | matches; uniform scale, not stretched (see client notes) | play `chat/say_prompt.png`, `chat/team_prompt.png`; side by side `chat/say_side.png`, `chat/team_side.png` (OA left) |
| say / say_team lines through Roblox's filter, name colours, team prefix | works | play `chat/say_line.png`, `chat/team_line.png`; a bot teammate got the team line; tests `chat.test.luau` |
| bot chat (taunts, team orders) | works | play `chat/bot_taunts.png` (`bot_fastchat 1`) |
| talk sound | called (`sound/player/talk.wav`), silent until the sound atlases have ids | play (hooked `Snd.StartSound`) |

## Weapons

Seen in play: Machinegun (fired by the player: ammo 124 -> 67, brass,
marks, crosshair names) and Rocket Launcher (bots: `MOD_ROCKET`,
`MOD_ROCKET_SPLASH` kills in the server log). The rest are exercised by the
bot sweep and the rules test on the server; their first-person and world
models are converted (table below) but were not looked at in play.
Railgun damage and the armor/quad formulas are checked against 0.8.8's C in
`test_rules`.

## Items and maps

Generated by `place/parity_table.py` (converter output, resolved ids, bot
sweep). "icon uploaded" and "atlas pages uploaded" count ids in
`place/asset-ids.json`; held files (gibs, blood, player skins) stay pending
until moderation clears them.

| map | mesh | atlas pages uploaded | aas | FFA sweep | CTF sweep |
|---|---|---|---|---|---|
| aggressor | yes | 13/13 | yes | ok (11 kills) | - |
| am_galmevish | yes | 13/13 | yes | ok (15 kills) | - |
| am_galmevish2 | yes | 14/14 | yes | ok (11 kills) | not-a-ctf-map |
| am_lavaarena | yes | 15/15 | yes | ok (9 kills) | - |
| am_lavactf | yes | 14/14 | yes | ok (23 kills) | ok (9 kills) |
| am_lavactfxl | yes | 14/14 | yes | ok (8 kills) | ok (4 kills) |
| am_mckinleyish2 | yes | 14/14 | yes | ok (10 kills) | ok (1 kills) |
| am_spacecont | yes | 15/15 | yes | ok (11 kills) | - |
| am_thornish | yes | 14/14 | yes | ok (11 kills) | ok (7 kills) |
| am_underworks | yes | 13/13 | yes | ok (13 kills) | - |
| am_underworks2 | yes | 15/15 | yes | ok (12 kills) | - |
| blitzkrieg3 | yes | 13/13 | yes | ok (11 kills) | - |
| cbctf1 | yes | 14/14 | yes | ok (2 kills) | ok (2 kills) |
| ce1m7 | yes | 13/13 | yes | ok (12 kills) | - |
| ctf_compromise | yes | 14/14 | yes | ok (6 kills) | ok (1 kills) |
| ctf_gate1 | yes | 13/13 | yes | ok (11 kills) | ok (8 kills) |
| ctf_inyard | yes | 14/14 | yes | ok (8 kills) | ok (2 kills) |
| czest1dm | yes | 14/14 | yes | ok (10 kills) | - |
| czest1tourney | yes | 14/14 | yes | ok (10 kills) | - |
| czest2ctf | yes | 14/14 | yes | ok (19 kills) | ok (4 kills) |
| czest3ctf | yes | 14/14 | yes | ok (11 kills) | ok (0 kills) |
| delta | yes | 14/14 | yes | ok (8 kills) | ok (7 kills) |
| dm4ish | yes | 14/14 | yes | ok (12 kills) | - |
| dm6ish | yes | 13/13 | yes | ok (12 kills) | - |
| fan | yes | 14/14 | yes | ok (15 kills) | - |
| hydronex | yes | 14/14 | yes | ok (7 kills) | ok (5 kills) |
| hydronex2 | yes | 14/14 | yes | ok (4 kills) | ok (4 kills) |
| islandctf | yes | 15/15 | none in pk3 | no-bots | no-bots |
| islanddm | yes | 14/14 | yes | ok (6 kills) | - |
| kaos | yes | 14/14 | yes | ok (6 kills) | - |
| kaos2 | yes | 14/14 | yes | ok (7 kills) | - |
| mlca1 | yes | 14/14 | yes | ok (7 kills) | - |
| mlctf1beta | yes | 13/13 | yes | ok (15 kills) | ok (5 kills) |
| oa_bases3 | yes | 14/14 | yes | ok (3 kills) | ok (3 kills) |
| oa_bases3cl | yes | 13/13 | yes | ok (11 kills) | ok (5 kills) |
| oa_bases3p3ta | yes | 14/14 | yes | ok (7 kills) | ok (3 kills) |
| oa_bases3plus3 | yes | 14/14 | yes | ok (7 kills) | ok (6 kills) |
| oa_bases5 | yes | 14/14 | yes | ok (8 kills) | ok (7 kills) |
| oa_bases7 | yes | 13/13 | yes | ok (4 kills) | ok (3 kills) |
| oa_ctf2 | yes | 14/14 | yes | ok (9 kills) | ok (8 kills) |
| oa_ctf2old | yes | 15/15 | yes | ok (11 kills) | ok (5 kills) |
| oa_ctf4ish | yes | 13/13 | yes | ok (20 kills) | ok (7 kills) |
| oa_dm1 | yes | 13/13 | yes | ok (13 kills) | - |
| oa_dm2 | yes | 8/13 | yes | ok (14 kills) | - |
| oa_dm3 | yes | 0/13 | yes | ok (4 kills) | - |
| oa_dm4 | yes | 0/13 | yes | ok (15 kills) | - |
| oa_dm5 | yes | 0/14 | yes | ok (13 kills) | - |
| oa_dm6 | yes | 0/14 | yes | ok (11 kills) | - |
| oa_dm7 | yes | 0/14 | yes | ok (10 kills) | - |
| oa_koth1 | yes | 0/13 | yes | error: src/server/bot/botlib/be_aas_route_2:270: attempt to perform arithmetic | - |
| oa_koth2 | yes | 0/13 | yes | ok (9 kills) | - |
| oa_minia | yes | 0/13 | yes | ok (10 kills) | ok (9 kills) |
| oa_pvomit | yes | 0/14 | yes | ok (5 kills) | - |
| oa_reptctf11 | yes | 0/13 | yes | ok (11 kills) | ok (10 kills) |
| oa_rpg3dm2 | yes | 0/14 | yes | ok (14 kills) | - |
| oa_shine | yes | 0/14 | yes | ok (11 kills) | - |
| oa_shouse | yes | 0/13 | yes | ok (12 kills) | - |
| oa_spirit3 | yes | 0/13 | yes | ok (11 kills) | ok (3 kills) |
| oa_thor | yes | 0/16 | yes | ok (11 kills) | ok (6 kills) |
| oasago1 | yes | 0/15 | yes | ok (7 kills) | ok (3 kills) |
| oasago2 | yes | 0/13 | yes | ok (12 kills) | ok (6 kills) |
| ps37ctf | yes | 0/13 | yes | ok (12 kills) | ok (8 kills) |
| ps37ctf2 | yes | 0/14 | yes | ok (10 kills) | ok (6 kills) |
| ps9ctf | yes | 0/13 | yes | ok (10 kills) | ok (5 kills) |
| pul1ctf | yes | 0/14 | yes | ok (10 kills) | ok (4 kills) |
| pul1duel-oa | yes | 0/13 | yes | ok (9 kills) | - |
| pxlfan | yes | 0/14 | yes | ok (15 kills) | - |
| q3dm6ish | yes | 0/13 | yes | ok (12 kills) | - |
| sleekgrinder | yes | 0/14 | yes | ok (10 kills) | - |
| slimefac | yes | 0/13 | yes | ok (8 kills) | ok (8 kills) |
| suspended | yes | 0/14 | yes | ok (4 kills) | - |
| wrackdm17 | yes | 0/13 | yes | ok (12 kills) | - |

| item | pickup name | maps placing it | world model converted | icon uploaded |
|---|---|---|---|---|
| item_armor_shard | Armor Shard | 49 | yes | yes |
| item_armor_combat | Armor | 52 | yes | yes |
| item_armor_body | Heavy Armor | 43 | yes | yes |
| item_health_small | 5 Health | 47 | yes | yes |
| item_health | 25 Health | 67 | yes | yes |
| item_health_large | 50 Health | 38 | yes | yes |
| item_health_mega | Mega Health | 45 | yes | yes |
| weapon_gauntlet | Gauntlet | 0 | yes | yes |
| weapon_shotgun | Shotgun | 67 | yes | yes |
| weapon_machinegun | Machinegun | 0 | yes | yes |
| weapon_grenadelauncher | Grenade Launcher | 45 | yes | yes |
| weapon_rocketlauncher | Rocket Launcher | 72 | yes | yes |
| weapon_lightning | Lightning Gun | 58 | yes | yes |
| weapon_railgun | Railgun | 61 | yes | yes |
| weapon_plasmagun | Plasma Gun | 60 | yes | yes |
| weapon_bfg | BFG10K | 6 | yes | yes |
| weapon_grapplinghook | Grappling Hook | 0 | yes | yes |
| ammo_shells | Shells | 61 | yes | yes |
| ammo_bullets | Bullets | 52 | yes | yes |
| ammo_grenades | Grenades | 35 | yes | yes |
| ammo_cells | Cells | 57 | yes | yes |
| ammo_lightning | Lightning | 53 | yes | yes |
| ammo_rockets | Rockets | 70 | yes | yes |
| ammo_slugs | Slugs | 46 | yes | yes |
| ammo_bfg | Bfg Ammo | 2 | yes | yes |
| holdable_teleporter | Personal Teleporter | 6 | yes | yes |
| holdable_medkit | Medkit | 4 | yes | yes |
| item_quad | Quad Damage | 37 | yes | yes |
| item_enviro | Battle Suit | 11 | yes | yes |
| item_haste | Speed | 9 | yes | yes |
| item_invis | Invisibility | 11 | yes | yes |
| item_regen | Regeneration | 13 | yes | yes |
| item_flight | Flight | 3 | yes | yes |
| team_CTF_redflag | Red Flag | 36 | yes | yes |
| team_CTF_blueflag | Blue Flag | 36 | yes | yes |
| holdable_kamikaze | Kamikaze | 5 | yes | yes |
| holdable_portal | Portal | 0 | no | yes |
| holdable_invulnerability | Invulnerability | 4 | yes | yes |
| ammo_nails | Nails | 14 | yes | yes |
| ammo_mines | Proximity Mines | 5 | yes | yes |
| ammo_belt | Chaingun Belt | 7 | yes | yes |
| item_scout | Scout | 13 | yes | yes |
| item_guard | Guard | 17 | yes | yes |
| item_doubler | Doubler | 15 | yes | yes |
| item_ammoregen | Ammo Regen | 12 | yes | yes |
| team_CTF_neutralflag | Neutral Flag | 30 | yes | yes |
| item_redcube | Red Cube | 0 | yes | yes |
| item_bluecube | Blue Cube | 0 | yes | yes |
| weapon_nailgun | Nailgun | 17 | yes | yes |
| weapon_prox_launcher | Prox Launcher | 7 | yes | yes |
| weapon_chaingun | Chaingun | 8 | yes | yes |
| team_DD_pointAblue | Point A (Blue) | 0 | yes | yes |
| team_DD_pointBblue | Point B (Blue) | 0 | yes | yes |
| team_DD_pointAred | Point A (Red) | 0 | yes | yes |
| team_DD_pointBred | Point B (Red) | 0 | yes | yes |
| team_DD_pointAwhite | Point A (White) | 0 | yes | yes |
| team_DD_pointBwhite | Point B (White) | 0 | yes | yes |
| team_dom_pointWhite | Neutral domination point | 0 | yes | yes |
| team_dom_pointRed | Red domination point | 0 | yes | yes |
| team_dom_pointBlue | Blue domination point | 0 | yes | yes |

