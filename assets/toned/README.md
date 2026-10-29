# Toned-down player skins

Modified copies of OpenArena 0.8.8 art (GPL-2.0, same licence as the
originals), kept at the same paths as in the pk3s. `tools/oaconv` reads this
folder after every pk3, so these files replace the originals in `build/`.

Why: two characters' outfits were too revealing for Roblox's rules on
suggestive content. They keep their faces, hair, colours and silhouettes; the
outfits now cover the chest, midriff and hips.

| File | Change |
|---|---|
| `models/players/neko/neko.tga` | dark charcoal high-neck bodysuit, cut at mid-thigh with silver trim |
| `models/players/neko/neko_red.tga` | same suit in the red team's deep red |
| `models/players/neko/neko_blue.tga` | same suit in the blue team's navy |
| `models/players/neko/neko_old.tga` | charcoal suit with gold trim, her gold choker kept |
| `models/players/neko/icon_{default,red,blue}.tga`, `iconh_old.tga` | re-rendered from the new skins; `iconh_old` is now framed on the face |
| `models/players/angelyss/retro.tga` | navy high-neck bodysuit (the scarf's colour), cut at mid-thigh with grey trim |
| `models/players/angelyss/retroclothes.tga` | bikini strings and crotch piece painted to match the suit |
| `models/players/angelyss/icon_retro.tga` | re-rendered from the new skin |

The suit is painted only inside the UV islands that map to the torso and
hips, chosen by each texel's position on the idle-pose mesh, with soft
shading taken from the original art. Angelyss's red, blue and dark skins use
`models/players/hnt/` textures that only ship in the mature pk3, which the
port never reads, so there is nothing of theirs to edit; their icons already
show a high collar and stay as they were.

Before/after: `docs/toned-skins.jpg`.
