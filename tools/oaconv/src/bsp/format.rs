//! IBSP version 46 lumps, as laid out in ioquake3's `qcommon/qfiles.h`
//! (GPL-2.0). Every field is little-endian.

pub const LIGHTMAP_SIZE: usize = 128;

pub const MST_PLANAR: i32 = 1;
pub const MST_PATCH: i32 = 2;
pub const MST_TRIANGLE_SOUP: i32 = 3;
pub const MST_FLARE: i32 = 4;

#[derive(Clone, Debug)]
pub struct DShader {
    pub name: String,
    pub surface_flags: i32,
    pub content_flags: i32,
}

#[derive(Clone, Copy, Debug)]
pub struct DPlane {
    pub normal: [f32; 3],
    pub dist: f32,
}

#[derive(Clone, Copy, Debug)]
pub struct DNode {
    pub plane_num: i32,
    /// Negative numbers are `-(leaf + 1)`.
    pub children: [i32; 2],
    pub mins: [i32; 3],
    pub maxs: [i32; 3],
}

#[derive(Clone, Copy, Debug)]
pub struct DLeaf {
    pub cluster: i32,
    pub area: i32,
    pub mins: [i32; 3],
    pub maxs: [i32; 3],
    pub first_leaf_surface: i32,
    pub num_leaf_surfaces: i32,
    pub first_leaf_brush: i32,
    pub num_leaf_brushes: i32,
}

#[derive(Clone, Copy, Debug)]
pub struct DModel {
    pub mins: [f32; 3],
    pub maxs: [f32; 3],
    pub first_surface: i32,
    pub num_surfaces: i32,
    pub first_brush: i32,
    pub num_brushes: i32,
}

#[derive(Clone, Copy, Debug)]
pub struct DBrush {
    pub first_side: i32,
    pub num_sides: i32,
    pub shader_num: i32,
}

#[derive(Clone, Copy, Debug)]
pub struct DBrushSide {
    pub plane_num: i32,
    pub shader_num: i32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct DrawVert {
    pub xyz: [f32; 3],
    pub st: [f32; 2],
    pub lightmap: [f32; 2],
    pub normal: [f32; 3],
    pub color: [u8; 4],
}

#[derive(Clone, Debug)]
pub struct DFog {
    pub shader: String,
    pub brush_num: i32,
    pub visible_side: i32,
}

#[derive(Clone, Copy, Debug)]
pub struct DSurface {
    pub shader_num: i32,
    pub fog_num: i32,
    pub surface_type: i32,
    pub first_vert: i32,
    pub num_verts: i32,
    pub first_index: i32,
    pub num_indexes: i32,
    /// -1: vertex lit. Indexes `Bsp::lightmaps`.
    pub lightmap_num: i32,
    pub lightmap_x: i32,
    pub lightmap_y: i32,
    pub lightmap_width: i32,
    pub lightmap_height: i32,
    pub lightmap_origin: [f32; 3],
    /// For MST_PLANAR, `[2]` is the face normal.
    pub lightmap_vecs: [[f32; 3]; 3],
    pub patch_width: i32,
    pub patch_height: i32,
}

/// One parsed map. Lumps are kept as-is; nothing is transformed.
#[derive(Clone, Debug)]
pub struct Bsp {
    pub entities: String,
    pub shaders: Vec<DShader>,
    pub planes: Vec<DPlane>,
    pub nodes: Vec<DNode>,
    pub leafs: Vec<DLeaf>,
    pub leaf_surfaces: Vec<i32>,
    pub leaf_brushes: Vec<i32>,
    pub models: Vec<DModel>,
    pub brushes: Vec<DBrush>,
    pub brush_sides: Vec<DBrushSide>,
    pub verts: Vec<DrawVert>,
    pub indexes: Vec<i32>,
    pub fogs: Vec<DFog>,
    pub surfaces: Vec<DSurface>,
    /// 128x128 RGB each, raw bytes as stored (no overbright shift).
    pub lightmaps: Vec<Vec<u8>>,
    pub light_grid: Vec<u8>,
    pub visibility: Vec<u8>,
}

struct Reader<'a> {
    data: &'a [u8],
    pos: usize,
}

impl Reader<'_> {
    fn i32(&mut self) -> i32 {
        let v = i32::from_le_bytes(self.data[self.pos..self.pos + 4].try_into().unwrap());
        self.pos += 4;
        v
    }
    fn f32(&mut self) -> f32 {
        f32::from_bits(self.i32() as u32)
    }
    fn i3(&mut self) -> [i32; 3] {
        [self.i32(), self.i32(), self.i32()]
    }
    fn f3(&mut self) -> [f32; 3] {
        [self.f32(), self.f32(), self.f32()]
    }
    fn f2(&mut self) -> [f32; 2] {
        [self.f32(), self.f32()]
    }
    fn name(&mut self, len: usize) -> String {
        let raw = &self.data[self.pos..self.pos + len];
        self.pos += len;
        let end = raw.iter().position(|&b| b == 0).unwrap_or(len);
        String::from_utf8_lossy(&raw[..end]).into_owned()
    }
    fn bytes<const N: usize>(&mut self) -> [u8; N] {
        let v = self.data[self.pos..self.pos + N].try_into().unwrap();
        self.pos += N;
        v
    }
}

fn lump<T>(data: &[u8], size: usize, mut read: impl FnMut(&mut Reader) -> T) -> Vec<T> {
    let mut r = Reader { data, pos: 0 };
    (0..data.len() / size).map(|_| read(&mut r)).collect()
}

impl Bsp {
    pub fn parse(data: &[u8]) -> Result<Self, String> {
        if data.len() < 8 + 17 * 8 || &data[..4] != b"IBSP" {
            return Err("not an IBSP file".into());
        }
        let version = i32::from_le_bytes(data[4..8].try_into().unwrap());
        if version != 46 {
            return Err(format!("IBSP version {version}, expected 46"));
        }
        let mut lumps = Vec::with_capacity(17);
        for i in 0..17 {
            let at = 8 + i * 8;
            let ofs = i32::from_le_bytes(data[at..at + 4].try_into().unwrap()) as usize;
            let len = i32::from_le_bytes(data[at + 4..at + 8].try_into().unwrap()) as usize;
            let slice = data
                .get(ofs..ofs + len)
                .ok_or(format!("lump {i} out of range"))?;
            lumps.push(slice);
        }
        let entities = {
            let raw = lumps[0];
            let end = raw.iter().position(|&b| b == 0).unwrap_or(raw.len());
            String::from_utf8_lossy(&raw[..end]).into_owned()
        };
        let ints = |d: &[u8]| lump(d, 4, |r| r.i32());
        Ok(Self {
            entities,
            shaders: lump(lumps[1], 72, |r| DShader {
                name: r.name(64),
                surface_flags: r.i32(),
                content_flags: r.i32(),
            }),
            planes: lump(lumps[2], 16, |r| DPlane {
                normal: r.f3(),
                dist: r.f32(),
            }),
            nodes: lump(lumps[3], 36, |r| DNode {
                plane_num: r.i32(),
                children: [r.i32(), r.i32()],
                mins: r.i3(),
                maxs: r.i3(),
            }),
            leafs: lump(lumps[4], 48, |r| DLeaf {
                cluster: r.i32(),
                area: r.i32(),
                mins: r.i3(),
                maxs: r.i3(),
                first_leaf_surface: r.i32(),
                num_leaf_surfaces: r.i32(),
                first_leaf_brush: r.i32(),
                num_leaf_brushes: r.i32(),
            }),
            leaf_surfaces: ints(lumps[5]),
            leaf_brushes: ints(lumps[6]),
            models: lump(lumps[7], 40, |r| DModel {
                mins: r.f3(),
                maxs: r.f3(),
                first_surface: r.i32(),
                num_surfaces: r.i32(),
                first_brush: r.i32(),
                num_brushes: r.i32(),
            }),
            brushes: lump(lumps[8], 12, |r| DBrush {
                first_side: r.i32(),
                num_sides: r.i32(),
                shader_num: r.i32(),
            }),
            brush_sides: lump(lumps[9], 8, |r| DBrushSide {
                plane_num: r.i32(),
                shader_num: r.i32(),
            }),
            verts: lump(lumps[10], 44, |r| DrawVert {
                xyz: r.f3(),
                st: r.f2(),
                lightmap: r.f2(),
                normal: r.f3(),
                color: r.bytes::<4>(),
            }),
            indexes: ints(lumps[11]),
            fogs: lump(lumps[12], 72, |r| DFog {
                shader: r.name(64),
                brush_num: r.i32(),
                visible_side: r.i32(),
            }),
            surfaces: lump(lumps[13], 104, |r| DSurface {
                shader_num: r.i32(),
                fog_num: r.i32(),
                surface_type: r.i32(),
                first_vert: r.i32(),
                num_verts: r.i32(),
                first_index: r.i32(),
                num_indexes: r.i32(),
                lightmap_num: r.i32(),
                lightmap_x: r.i32(),
                lightmap_y: r.i32(),
                lightmap_width: r.i32(),
                lightmap_height: r.i32(),
                lightmap_origin: r.f3(),
                lightmap_vecs: [r.f3(), r.f3(), r.f3()],
                patch_width: r.i32(),
                patch_height: r.i32(),
            }),
            lightmaps: lumps[14]
                .as_chunks::<{ LIGHTMAP_SIZE * LIGHTMAP_SIZE * 3 }>()
                .0
                .iter()
                .map(|c| c.to_vec())
                .collect(),
            light_grid: lumps[15].to_vec(),
            visibility: lumps[16].to_vec(),
        })
    }

    pub fn surface_verts(&self, s: &DSurface) -> &[DrawVert] {
        &self.verts[s.first_vert as usize..(s.first_vert + s.num_verts) as usize]
    }

    pub fn surface_indexes(&self, s: &DSurface) -> &[i32] {
        &self.indexes[s.first_index as usize..(s.first_index + s.num_indexes) as usize]
    }
}
