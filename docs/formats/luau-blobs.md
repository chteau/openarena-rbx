# Luau buffer modules

Binary blobs the Roblox side reads at runtime (collision, entities, light
grid, AAS, MD3 frame data) ship as ModuleScripts, written by
`tools/oaconv/src/luau.rs`. A script's source must stay under 200,000
characters, so each blob is cut into chunk modules of at most 190,000
characters.

## Files

For a blob called `Name`:

| File | Returns |
|------|---------|
| `Name_000.luau`, `Name_001.luau`, ... | one `buffer`: that chunk's bytes |
| `Name.luau` (index) | `{ name, size, sha256, chunks = { "Name_000", ... } }` |

Every chunk carries the same small base64 decoder (`--!native`), so it works
wherever assembly puts it. Chunks hold standard base64 (RFC 4648, `+/`,
`=` padding); each chunk's text is a multiple of 4 characters, so chunks
decode independently and concatenating their buffers gives the blob.

`size` is the blob's byte length and `sha256` its lowercase hex digest, for
an integrity check after joining.

## Loading

Assembly makes the chunks siblings of the index:

```lua
local function load(index: ModuleScript): buffer
	local info = require(index)
	local parts, total = {}, 0
	for i, name in info.chunks do
		local b = require(index.Parent[name])
		parts[i] = b
		total += buffer.len(b)
	end
	assert(total == info.size, "blob size mismatch")
	local out = buffer.create(total)
	local o = 0
	for _, b in parts do
		buffer.copy(out, o, b)
		o += buffer.len(b)
	end
	return out
end
```

`read_buffer_modules` in `luau.rs` does the same join in Rust; the tests use
it for the round trip.

## Where they are

| Blob | Path under `build/` | Format |
|------|---------------------|--------|
| Collision | `maps/<map>/luau/Collision*` | `docs/formats/collision.md` |
| Entities | `maps/<map>/luau/Entities*` | UTF-8 JSON, `docs/formats/entities.md` |
| Light grid | `maps/<map>/luau/LightGrid*` | raw BSP light grid lump: 8 bytes per cell (ambient rgb, directed rgb, lat, lng), x fastest then y then z; `map.json` `lightgrid` gives `origin` and cell `size` in Quake units and `bounds` as cell counts per axis, as `R_LoadLightGrid` derives them |
| Bot navigation | `maps/<map>/luau/Aas*` | the map's `.aas` file, unchanged; `map.json` `checksum` is `Com_BlockChecksum` of the `.bsp` (`sv_mapChecksum`), which botlib checks against the `.aas` header |
| MD3 frames | `md3/<dir>/luau/<stem>*` | `docs/formats/md3.md` |

`SoundIndex.luau` is not a blob: it is a plain Luau table literal
(`path -> { atlas, start, length }`, seconds) mirroring `sound_index.json`,
small enough (about 78 KB) to fit one module.
