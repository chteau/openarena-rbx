# MD3, animation.cfg, .skin

Source: ioquake3 `qcommon/qfiles.h`, `renderergl1/tr_model.c`, `tr_surface.c`,
OA `cgame/cg_players.c`. Implementation: `tools/oaconv/src/md3.rs`.

## MD3 file (little endian)

| Struct | Size | Fields |
|---|---|---|
| header | 108 | ident "IDP3", i32 version (15), char name[64], i32 flags, numFrames, numTags, numSurfaces, numSkins, ofsFrames, ofsTags, ofsSurfaces, ofsEnd |
| frame | 56 | f32 bounds[2][3], f32 localOrigin[3], f32 radius, char name[16] |
| tag | 112 | char name[64], f32 origin[3], f32 axis[3][3]; stored `numFrames * numTags` (frame-major) |
| surface | 108 | ident "IDP3", char name[64], i32 flags, numFrames, numShaders, numVerts, numTriangles, ofsTriangles, ofsShaders, ofsSt, ofsXyzNormal, ofsEnd (all offsets relative to the surface start) |
| shader | 68 | char name[64], i32 shaderIndex |
| triangle | 12 | i32 index[3] |
| st | 8 | f32 s, t |
| xyznormal | 8 | i16 xyz[3], u16 normal; stored `numFrames * numVerts` |

Surfaces follow each other at `ofsEnd`.

## Decoding

- Position: `i16 * 1/64` Quake units.
- Normal: `lat = ((n>>8)&255) * 2π/255`, `lng = (n&255) * 2π/255`;
  `x = cos(lat)*sin(lng)`, `y = sin(lat)*sin(lng)`, `z = cos(lng)`
  (the engine uses a 256-step table with the same convention).
- Quake to Roblox: `(x, y, z) -> (x, z, -y) / 8` studs.
- Frame lerp (`RB_SurfaceMesh`/`LerpMeshVertexes`): `p = old*(1-b) + new*b` on
  positions after scaling by 1/64; normals are lerped likewise and renormalised.
- Tag attachment, `CG_PositionEntityOnTag`: `origin = parent.origin +
  sum_i(lerpedTag.origin[i] * parent.axis[i])`, `axis = lerpedTag.axis * parent.axis`
  (tag lerped between frames per component, axes renormalised).
  `CG_PositionRotatedEntityOnTag` additionally pre-multiplies by the entity's own
  axis: `axis = (entity.axis * lerpedTag.axis) * parent.axis`.

## Runtime buffer `OAM3` (`to_buffer`)

All little endian. Sections are 4-byte aligned. `str` = u8 length + bytes.
F frames, T tags, S surfaces.

| Section | Layout |
|---|---|
| header (12) | "OAM3", u16 version=1, u16 F, u16 T, u16 S |
| frames (40*F) | per frame: f32 mins[3], maxs[3], localOrigin[3], radius |
| tag names | T `str`, padded to 4 |
| tag data (48*F*T) | frame-major; per tag f32 origin[3], axis[3][3] (rows) |
| per surface | `str` name, u8 numShaders, numShaders `str`, pad4; u32 numVerts; u32 numTris; u16 indices[3*numTris], pad4; f32 st[numVerts][2]; then per frame numVerts * (i16 x, y, z, u16 normal) |

Positions are raw 1/64 units and normals raw lat/lng. Total length is
`12 + 40F + pad4(sum(1+len(tag))) + 48FT + sum_surfaces(pad4(1+len(name)+1+sum(1+len(shader))) + 8 + pad4(6*tris) + 8*verts + 8*F*verts)`.

Winding: indices keep MD3 order, which is clockwise seen from the front (Quake).
Roblox `EditableMesh:AddTriangle` wants counter-clockwise front faces, so the
Luau side must swap two indices of each triangle (and the axes swap (x, z, -y) also
flips handedness, so check by rendering).

## animation.cfg (JSON)

```json
{"sex":"m","footsteps":"normal","headoffset":[0,0,0],"fixedlegs":false,"fixedtorso":false,
 "animations":[[firstFrame,numFrames,loopingFrames,fps], ...]}
```

Rows are in `animNumber_t` order (BOTH_DEATH1 first), raw as written; `//` comments
are stripped. Keywords: footsteps, headoffset, sex, fixedlegs, fixedtorso.

## .skin (list)

Lowercased `[surface, shader]` pairs from `surface,shader` lines; `tag_*` surfaces
and empty shaders are skipped (as `RE_RegisterSkin`).
