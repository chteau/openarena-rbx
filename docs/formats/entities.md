# Entities

`entities.json` is produced by `bsp::entities::summarize`; the Luau form is
`return ` + `to_luau(json)`.

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

## Luau

Strings escape `\`, `"`, newline, and other control bytes as `\ddd`. Arrays
are `{a, b}`, objects `{["key"] = v}`, null is `nil`, numbers as serde_json
writes them.
