# Entities

`entities.json` is produced by `bsp::entities::summarize`. In `build/maps/<map>/`
it ships twice: `entities.json`, and the same JSON bytes as chunked buffer
modules `luau/Entities_NNN.luau` + index `luau/Entities.luau` (format in
`luau-blobs.md`); the game joins the chunks and runs `HttpService:JSONDecode`
on `buffer.tostring` of the result. Large maps' literals pass Roblox's 200k
character script limit, which is why the JSON goes through buffers rather
than one Luau table literal.

## Shape

- `worldspawn`: every key/value of entity 0 (strings).
- `entities[]`: `index`, `classname`, `keys` (all pairs, later duplicates win),
  `category`, and when present `origin` [x,y,z], `angle`, `angles` [p,y,r],
  `submodel` (n from `model "*n"`, only if n < number of BSP models).
- `counts`: classname to number of entities.
- `jumppads[]`: `entity`, `target`, `target_origin` for `trigger_push` /
  `target_push` whose target is a `target_position` or `info_notnull`.
- `teleporters[]`: `entity`, `target`, `dest` (entity index), `dest_origin`,
  `dest_angle`; from `trigger_teleport` and `misc_teleporter_dest` (the latter
  is its own destination).
- `movers[]`: `entity`, `classname`, `submodel` for func_door, func_plat,
  func_button, func_train, func_bobbing, func_rotating, func_pendulum,
  func_static.
- `spawns[]`: `entity`, `classname`, `origin`, `angle` for deathmatch/start,
  CTF player/spawn and domination red/blue spawns.

## Categories

spawn, item, weapon, ammo, powerup, holdable, flag, mover, trigger, jumppad,
teleporter, target, teleport_dest, light, misc, domination, harvester,
obelisk, other.

## Luau literals (`to_luau`)

Used for small tables such as `build/SoundIndex.luau`.

Strings escape `\`, `"`, newline, and other control bytes as `\ddd`. Arrays
are `{a, b}`, objects `{["key"] = v}`, null is `nil`, numbers as serde_json
writes them.
