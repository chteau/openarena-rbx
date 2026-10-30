# openarena-rbx

[OpenArena](https://openarena.ws) 0.8.8 running on Roblox. Same maps, same
weapons, same bots, same feel, just in a Roblox game.

This is a proof of concept for [rbx-native](https://github.com/chteau/rbx-native),
my native take on Roblox Studio. I wanted to show you can make a real game
with it, so the whole place was built through rbx-native's MCP server: every
script, folder, map and mesh got in there through its tools, nothing was put
together in Roblox Studio.

## Download

Grab `openarena.rbxl` from the [latest release](https://github.com/chteau/openarena-rbx/releases/latest).
It's one place with all 72 maps, the experience doesn't need any other place.

To run it in your own experience:

1. Publish it as a place of your experience. The server list, single player
   and hosted servers use teleports, reserved servers, MemoryStore and
   DataStore, and those only work in a published game
2. Game Settings › Security › turn on **Allow Mesh / Image APIs**. Without
   it the player and bot models are invisible and the animated surfaces don't
   move
3. Game Settings › Security › turn on **Enable Studio Access to API Services**,
   only if you want to test it from Studio
4. Set Max Players to 12

Heads up: the sounds are uploaded under my account and Roblox keeps audio
private to the experiences its owner allows, so your copy might be silent.
Textures and meshes load fine. Some animated map surfaces stay still in
someone else's game tho, Roblox only lets an `EditableMesh` be made from a
mesh the game's owner has access to.

## What's in

- All of OpenArena 0.8.8's maps, weapons, items and game modes
- Its bots, ported with their AAS navigation and chat
- Single player, with its arena ladder
- Multiplayer on Roblox servers: a server browser (Internet, Local = your
  friends' servers, Favorites), Start Server for your own private server and
  6 character join codes
- OA's HUD, menus, scoreboard, console and chat
- Lightmaps baked into the textures so the maps look like they do in OA

## What's different from OpenArena

- Roblox doesn't do LAN or connecting by IP, so servers are Roblox servers
  and you join them by code
- The female player models and a few skins are left out to stay on the safe
  side of Roblox moderation
- Bots wear Roblox avatars and names. The single player opponents are a fixed
  list of accounts, the same for everyone (`src/server/sv/botroster.luau`)
- Chat goes through Roblox's text filter, and the bots' chat lines got
  scrubbed of anything that wouldn't pass
- **P** opens the OA menu, since Esc is Roblox's own menu

## How it's made

- `src/` is a Luau port of OpenArena's game code (the [0.8.8 release
  code](https://github.com/OpenArena/gamecode)) plus the parts of the
  engine the game needs from [ioquake3](https://github.com/ioquake/ioq3):
  collision, bot routing, the network model. 1 stud is 8 Quake units
- `tools/oaconv/` is a Rust converter that turns OA's pk3s into Roblox
  assets: maps into meshes with baked lightmaps, models, textures and sound
  atlases
- `place/assemble.py` builds the place by talking to rbx-native's MCP server

`scripts/fetch-vendor.sh` grabs the OA data and sources into `vendor/`. The
notes in `docs/` go into the details, `docs/ARCHITECTURE.md` is the place to
start.

## Thanks

Huge thanks to the [OpenArena](https://openarena.ws) team and everyone who
made its maps, models, textures, sounds and bots. All of it is theirs, I
just moved it over to Roblox. Their code is on GitHub:
[gamecode](https://github.com/OpenArena/gamecode),
[engine](https://github.com/OpenArena/engine) and
[legacy](https://github.com/OpenArena/legacy) (the 0.8.8 engine and game
code).

Thanks to the [ioquake3](https://github.com/ioquake/ioq3) folks too, and to
id Software for releasing [Quake III Arena's source](https://github.com/id-Software/Quake-III-Arena)
under the GPL, none of this exists without it.

## License

GPL-2.0, same as OpenArena. See [`LICENSE`](LICENSE).
