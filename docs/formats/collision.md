# Collision blob (`OACM`)

Purpose: everything `vendor/ioq3/code/qcommon/cm_load.c` `CM_LoadMap` keeps of a
BSP, in the BSP's own order and indices, plus patch collision already generated
(`CM_LoadPatches` / `CM_GeneratePatchCollide`, done offline). The Luau port of
cm_load reads it instead of parsing the BSP.

## Shipping

The blob goes through `crate::luau` chunked buffer modules: `name_000.luau`,
`name_001.luau`, ... each return one `buffer`, and the index module `name.luau`
lists them with size and sha256. Join the chunks in order to get the blob.

## Header

All values little-endian, every record 4-byte aligned.

| Offset | Type | Field |
|---|---|---|
| 0 | char[4] | magic `OACM` |
| 4 | u32 | version = 1 |
| 8 | u32 | section count N |
| 12 | N x 16 bytes | section table |

Section table entry: `u32 fourcc` (ASCII id), `u32 record count`, `u32 byte offset` (from blob start), `u32 byte length`.
Sections follow the table in this order: SHDR PLAN NODE LEAF LBRK LSRF BRSH BSID MODL VISI PATC PPLN FACE.

## Sections

Fixed sections have length = count x record size.

### SHDR (8 bytes) - CM_LoadShaders

| Off | Type | Field | Meaning |
|---|---|---|---|
| 0 | i32 | surface_flags | dshader surfaceFlags |
| 4 | i32 | content_flags | dshader contentFlags |

### PLAN (16) - CM_LoadPlanes

| Off | Type | Field | Meaning |
|---|---|---|---|
| 0 | f32[3] | normal | plane normal |
| 12 | f32 | dist | plane distance |

### NODE (12) - CM_LoadNodes

| Off | Type | Field | Meaning |
|---|---|---|---|
| 0 | i32 | plane | index into PLAN |
| 4 | i32[2] | children | negative = `-(leaf+1)` |

### LEAF (24) - CM_LoadLeafs

| Off | Type | Field | Meaning |
|---|---|---|---|
| 0 | i32 | cluster | visibility cluster |
| 4 | i32 | area | area number |
| 8 | i32 | first_leaf_brush | into LBRK |
| 12 | i32 | num_leaf_brushes | count |
| 16 | i32 | first_leaf_surface | into LSRF |
| 20 | i32 | num_leaf_surfaces | count |

### LBRK / LSRF (4) - CM_LoadLeafBrushes / CM_LoadLeafSurfaces

`i32` brush index / surface index per record.

### BRSH (12) - CM_LoadBrushes

| Off | Type | Field | Meaning |
|---|---|---|---|
| 0 | i32 | first_side | into BSID |
| 4 | i32 | num_sides | count |
| 8 | i32 | shader | into SHDR |

### BSID (8) - CM_LoadBrushSides

| Off | Type | Field | Meaning |
|---|---|---|---|
| 0 | i32 | plane | into PLAN |
| 4 | i32 | shader | into SHDR |

### MODL (40) - CM_LoadSubmodels

| Off | Type | Field | Meaning |
|---|---|---|---|
| 0 | f32[3] | mins | model bounds (the loader applies the 1-unit expansion) |
| 12 | f32[3] | maxs | model bounds |
| 24 | i32 | first_brush | submodel brushes (model 0 uses the BSP tree) |
| 28 | i32 | num_brushes | count |
| 32 | i32 | first_surface | submodel surfaces (patches are picked from these) |
| 36 | i32 | num_surfaces | count |

### VISI - CM_LoadVisibility

Record count = number of data bytes. Length = 8 + data, padded to 4. Empty lump: zeros and no data.

| Off | Type | Field | Meaning |
|---|---|---|---|
| 0 | i32 | num_clusters | numClusters |
| 4 | i32 | cluster_bytes | clusterBytes |
| 8 | u8[count] | data | PVS bits, then padding |

### PATC (60) - CM_LoadPatches, one per MST_PATCH surface

| Off | Type | Field | Meaning |
|---|---|---|---|
| 0 | i32 | surface | surface index in the BSP |
| 4 | i32 | contents | shader contentFlags |
| 8 | i32 | surface_flags | shader surfaceFlags |
| 12 | i32 | width | patchWidth |
| 16 | i32 | height | patchHeight |
| 20 | f32[3] | mins | bounds, already expanded by 1 |
| 32 | f32[3] | maxs | bounds, already expanded by 1 |
| 44 | i32 | plane_first | first PPLN record of this patch |
| 48 | i32 | plane_count | count |
| 52 | i32 | facet_first | first FACE record of this patch |
| 56 | i32 | facet_count | count |

Plane and facet indices inside FACE are relative to the patch's own plane range.

### PPLN (20) - patchPlane_t

| Off | Type | Field | Meaning |
|---|---|---|---|
| 0 | f32[4] | plane | normal xyz, dist |
| 16 | i32 | sign_bits | signbits of the normal |

### FACE (164) - facet_t

| Off | Type | Field | Meaning |
|---|---|---|---|
| 0 | i32 | surface_plane | patch-relative plane |
| 4 | i32 | num_borders | used entries (max 26) |
| 8 | i32[26] | border_planes | patch-relative plane, -1 = none |
| 112 | u8[26] | border_inward | 0/1 |
| 138 | u8[26] | border_no_adjust | 0/1 |
| 164 | | | (164 = 8+104+52, no extra padding) |

## What the Luau loader must still compute

- Plane `type` (PlaneTypeForNormal) and `signbits` (SetPlaneSignbits) for PLAN.
- Brush bounds from sides (CM_BoundBrush), brush `contents` from the shader, and the bevel-free side planes.
- Leaf `area` count, `numAreas`, and CM_FloodAreaConnections (area portals).
- Submodel leaf (brush and patch lists) and 1-unit bounds expansion as in CM_LoadSubmodels.
- Per-patch `checkcount` and the `(cluster)` PVS lookup via VISI.
