//! The collision blob the Luau port of cm_load reads. Layout: docs/formats/collision.md.

use super::format::MST_PATCH;
use super::patch_collide::{generate, Facet, PatchCollide, PcPlane, MAX_FACET_BEVELS};
use super::Bsp;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CmShader {
    pub surface_flags: i32,
    pub content_flags: i32,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CmPlane {
    pub normal: [f32; 3],
    pub dist: f32,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CmNode {
    pub plane: i32,
    pub children: [i32; 2],
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CmLeaf {
    pub cluster: i32,
    pub area: i32,
    pub first_leaf_brush: i32,
    pub num_leaf_brushes: i32,
    pub first_leaf_surface: i32,
    pub num_leaf_surfaces: i32,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CmBrush {
    pub first_side: i32,
    pub num_sides: i32,
    pub shader: i32,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CmBrushSide {
    pub plane: i32,
    pub shader: i32,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CmSubmodel {
    pub mins: [f32; 3],
    pub maxs: [f32; 3],
    pub first_brush: i32,
    pub num_brushes: i32,
    pub first_surface: i32,
    pub num_surfaces: i32,
}

#[derive(Clone, Debug, PartialEq)]
pub struct CmPatch {
    pub surface: i32,
    pub contents: i32,
    pub surface_flags: i32,
    pub width: i32,
    pub height: i32,
    pub collide: PatchCollide,
}

#[derive(Clone, Debug, PartialEq, Default)]
pub struct CmVisibility {
    pub num_clusters: i32,
    pub cluster_bytes: i32,
    pub data: Vec<u8>,
}

/// What cm_load keeps of a map, patches already generated.
#[derive(Clone, Debug, PartialEq)]
pub struct CollisionMap {
    pub shaders: Vec<CmShader>,
    pub planes: Vec<CmPlane>,
    pub nodes: Vec<CmNode>,
    pub leafs: Vec<CmLeaf>,
    pub leaf_brushes: Vec<i32>,
    pub leaf_surfaces: Vec<i32>,
    pub brushes: Vec<CmBrush>,
    pub brush_sides: Vec<CmBrushSide>,
    pub submodels: Vec<CmSubmodel>,
    pub patches: Vec<CmPatch>,
    pub visibility: CmVisibility,
}

const MAGIC: &[u8; 4] = b"OACM";
const VERSION: u32 = 1;
const FACET_SIZE: usize = 8 + 4 * MAX_FACET_BEVELS + 2 * MAX_FACET_BEVELS;

fn put_i(b: &mut Vec<u8>, v: i32) {
    b.extend_from_slice(&v.to_le_bytes());
}

fn put_f(b: &mut Vec<u8>, v: f32) {
    b.extend_from_slice(&v.to_le_bytes());
}

fn put_f3(b: &mut Vec<u8>, v: &[f32; 3]) {
    v.iter().for_each(|&x| put_f(b, x));
}

struct Cur<'a> {
    d: &'a [u8],
    p: usize,
}

impl Cur<'_> {
    fn take(&mut self, n: usize) -> Result<&[u8], String> {
        let s = self
            .d
            .get(self.p..self.p + n)
            .ok_or("record out of range")?;
        self.p += n;
        Ok(s)
    }
    fn i(&mut self) -> Result<i32, String> {
        Ok(i32::from_le_bytes(self.take(4)?.try_into().unwrap()))
    }
    fn f(&mut self) -> Result<f32, String> {
        Ok(f32::from_bits(self.i()? as u32))
    }
    fn f3(&mut self) -> Result<[f32; 3], String> {
        Ok([self.f()?, self.f()?, self.f()?])
    }
    fn u8(&mut self) -> Result<u8, String> {
        Ok(self.take(1)?[0])
    }
}

type Section<'a> = ([u8; 4], usize, &'a [u8]);

fn find<'a>(secs: &[Section<'a>], id: &[u8; 4]) -> Result<(usize, &'a [u8]), String> {
    secs.iter()
        .find(|s| &s.0 == id)
        .map(|s| (s.1, s.2))
        .ok_or_else(|| format!("missing section {}", String::from_utf8_lossy(id)))
}

fn read_sec<T>(
    secs: &[Section],
    id: &[u8; 4],
    size: usize,
    mut f: impl FnMut(&mut Cur) -> Result<T, String>,
) -> Result<Vec<T>, String> {
    let (count, data) = find(secs, id)?;
    if count.checked_mul(size) != Some(data.len()) {
        return Err(format!(
            "section {} has a bad length",
            String::from_utf8_lossy(id)
        ));
    }
    let mut c = Cur { d: data, p: 0 };
    (0..count).map(|_| f(&mut c)).collect()
}

fn range<T>(all: &[T], first: i32, count: i32) -> Result<&[T], String> {
    let (first, count) = (usize::try_from(first), usize::try_from(count));
    match (first, count) {
        (Ok(a), Ok(n)) => all
            .get(a..a.checked_add(n).ok_or("bad range")?)
            .ok_or_else(|| "range out of bounds".into()),
        _ => Err("negative range".into()),
    }
}

impl CollisionMap {
    pub fn build(bsp: &Bsp) -> Self {
        let patches = bsp
            .surfaces
            .iter()
            .enumerate()
            .filter(|(_, s)| s.surface_type == MST_PATCH)
            .map(|(i, s)| {
                let (w, h) = (s.patch_width as usize, s.patch_height as usize);
                let points: Vec<[f32; 3]> = bsp.surface_verts(s)[..w * h]
                    .iter()
                    .map(|v| v.xyz)
                    .collect();
                let shader = &bsp.shaders[s.shader_num as usize];
                CmPatch {
                    surface: i as i32,
                    contents: shader.content_flags,
                    surface_flags: shader.surface_flags,
                    width: s.patch_width,
                    height: s.patch_height,
                    collide: generate(w, h, &points),
                }
            })
            .collect();
        let visibility = if bsp.visibility.len() < 8 {
            CmVisibility::default()
        } else {
            let v = &bsp.visibility;
            CmVisibility {
                num_clusters: i32::from_le_bytes(v[0..4].try_into().unwrap()),
                cluster_bytes: i32::from_le_bytes(v[4..8].try_into().unwrap()),
                data: v[8..].to_vec(),
            }
        };
        Self {
            shaders: bsp
                .shaders
                .iter()
                .map(|s| CmShader {
                    surface_flags: s.surface_flags,
                    content_flags: s.content_flags,
                })
                .collect(),
            planes: bsp
                .planes
                .iter()
                .map(|p| CmPlane {
                    normal: p.normal,
                    dist: p.dist,
                })
                .collect(),
            nodes: bsp
                .nodes
                .iter()
                .map(|n| CmNode {
                    plane: n.plane_num,
                    children: n.children,
                })
                .collect(),
            leafs: bsp
                .leafs
                .iter()
                .map(|l| CmLeaf {
                    cluster: l.cluster,
                    area: l.area,
                    first_leaf_brush: l.first_leaf_brush,
                    num_leaf_brushes: l.num_leaf_brushes,
                    first_leaf_surface: l.first_leaf_surface,
                    num_leaf_surfaces: l.num_leaf_surfaces,
                })
                .collect(),
            leaf_brushes: bsp.leaf_brushes.clone(),
            leaf_surfaces: bsp.leaf_surfaces.clone(),
            brushes: bsp
                .brushes
                .iter()
                .map(|b| CmBrush {
                    first_side: b.first_side,
                    num_sides: b.num_sides,
                    shader: b.shader_num,
                })
                .collect(),
            brush_sides: bsp
                .brush_sides
                .iter()
                .map(|s| CmBrushSide {
                    plane: s.plane_num,
                    shader: s.shader_num,
                })
                .collect(),
            submodels: bsp
                .models
                .iter()
                .map(|m| CmSubmodel {
                    mins: m.mins,
                    maxs: m.maxs,
                    first_brush: m.first_brush,
                    num_brushes: m.num_brushes,
                    first_surface: m.first_surface,
                    num_surfaces: m.num_surfaces,
                })
                .collect(),
            patches,
            visibility,
        }
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        let mut secs: Vec<([u8; 4], usize, Vec<u8>)> = Vec::new();
        let mut add = |id: &[u8; 4], count: usize, f: &mut dyn FnMut(&mut Vec<u8>)| {
            let mut b = Vec::new();
            f(&mut b);
            secs.push((*id, count, b));
        };
        add(b"SHDR", self.shaders.len(), &mut |b| {
            for s in &self.shaders {
                put_i(b, s.surface_flags);
                put_i(b, s.content_flags);
            }
        });
        add(b"PLAN", self.planes.len(), &mut |b| {
            for p in &self.planes {
                put_f3(b, &p.normal);
                put_f(b, p.dist);
            }
        });
        add(b"NODE", self.nodes.len(), &mut |b| {
            for n in &self.nodes {
                put_i(b, n.plane);
                n.children.iter().for_each(|&c| put_i(b, c));
            }
        });
        add(b"LEAF", self.leafs.len(), &mut |b| {
            for l in &self.leafs {
                for v in [
                    l.cluster,
                    l.area,
                    l.first_leaf_brush,
                    l.num_leaf_brushes,
                    l.first_leaf_surface,
                    l.num_leaf_surfaces,
                ] {
                    put_i(b, v);
                }
            }
        });
        add(b"LBRK", self.leaf_brushes.len(), &mut |b| {
            self.leaf_brushes.iter().for_each(|&v| put_i(b, v))
        });
        add(b"LSRF", self.leaf_surfaces.len(), &mut |b| {
            self.leaf_surfaces.iter().for_each(|&v| put_i(b, v))
        });
        add(b"BRSH", self.brushes.len(), &mut |b| {
            for br in &self.brushes {
                put_i(b, br.first_side);
                put_i(b, br.num_sides);
                put_i(b, br.shader);
            }
        });
        add(b"BSID", self.brush_sides.len(), &mut |b| {
            for s in &self.brush_sides {
                put_i(b, s.plane);
                put_i(b, s.shader);
            }
        });
        add(b"MODL", self.submodels.len(), &mut |b| {
            for m in &self.submodels {
                put_f3(b, &m.mins);
                put_f3(b, &m.maxs);
                for v in [
                    m.first_brush,
                    m.num_brushes,
                    m.first_surface,
                    m.num_surfaces,
                ] {
                    put_i(b, v);
                }
            }
        });
        let v = &self.visibility;
        add(b"VISI", v.data.len(), &mut |b| {
            put_i(b, v.num_clusters);
            put_i(b, v.cluster_bytes);
            b.extend_from_slice(&v.data);
            b.resize(b.len().next_multiple_of(4), 0);
        });
        let (mut pl, mut fc) = (0usize, 0usize);
        let mut patc = Vec::new();
        let mut pplane = Vec::new();
        let mut face = Vec::new();
        for p in &self.patches {
            let c = &p.collide;
            for v in [p.surface, p.contents, p.surface_flags, p.width, p.height] {
                put_i(&mut patc, v);
            }
            c.bounds.iter().for_each(|m| put_f3(&mut patc, m));
            for v in [pl, c.planes.len(), fc, c.facets.len()] {
                put_i(&mut patc, v as i32);
            }
            pl += c.planes.len();
            fc += c.facets.len();
            for q in &c.planes {
                q.plane.iter().for_each(|&x| put_f(&mut pplane, x));
                put_i(&mut pplane, q.sign_bits);
            }
            for f in &c.facets {
                put_i(&mut face, f.surface_plane);
                put_i(&mut face, f.num_borders);
                f.border_planes.iter().for_each(|&x| put_i(&mut face, x));
                face.extend(f.border_inward.iter().map(|&x| x as u8));
                face.extend(f.border_no_adjust.iter().map(|&x| x as u8));
                face.resize(face.len().next_multiple_of(4), 0);
            }
        }
        secs.push((*b"PATC", self.patches.len(), patc));
        secs.push((*b"PPLN", pl, pplane));
        secs.push((*b"FACE", fc, face));

        let mut out = Vec::new();
        out.extend_from_slice(MAGIC);
        out.extend_from_slice(&VERSION.to_le_bytes());
        out.extend_from_slice(&(secs.len() as u32).to_le_bytes());
        let mut offset = 12 + 16 * secs.len();
        for (id, count, data) in &secs {
            out.extend_from_slice(id);
            for v in [*count, offset, data.len()] {
                out.extend_from_slice(&(v as u32).to_le_bytes());
            }
            offset += data.len();
        }
        secs.iter().for_each(|s| out.extend_from_slice(&s.2));
        out
    }

    pub fn from_bytes(bytes: &[u8]) -> Result<Self, String> {
        if bytes.len() < 12 || &bytes[..4] != MAGIC {
            return Err("bad magic".into());
        }
        let word = |at: usize| u32::from_le_bytes(bytes[at..at + 4].try_into().unwrap()) as usize;
        if word(4) != VERSION as usize {
            return Err(format!("unsupported version {}", word(4)));
        }
        let n = word(8);
        if n > 64 || bytes.len() < 12 + 16 * n {
            return Err("truncated section table".into());
        }
        let mut secs: Vec<Section> = Vec::new();
        for i in 0..n {
            let at = 12 + 16 * i;
            let (ofs, len) = (word(at + 8), word(at + 12));
            let data = bytes
                .get(ofs..ofs.checked_add(len).ok_or("bad section")?)
                .ok_or("section out of range")?;
            secs.push((bytes[at..at + 4].try_into().unwrap(), word(at + 4), data));
        }

        let (vcount, vdata) = find(&secs, b"VISI")?;
        if vdata.len() != (8 + vcount).next_multiple_of(4) {
            return Err("bad VISI length".into());
        }
        let mut vc = Cur { d: vdata, p: 0 };
        let visibility = CmVisibility {
            num_clusters: vc.i()?,
            cluster_bytes: vc.i()?,
            data: vdata[8..8 + vcount].to_vec(),
        };

        let planes = read_sec(&secs, b"PPLN", 20, |c| {
            Ok(PcPlane {
                plane: [c.f()?, c.f()?, c.f()?, c.f()?],
                sign_bits: c.i()?,
            })
        })?;
        let facets = read_sec(&secs, b"FACE", FACET_SIZE, |c| {
            let surface_plane = c.i()?;
            let num_borders = c.i()?;
            let mut f = Facet {
                surface_plane,
                num_borders,
                border_planes: [0; MAX_FACET_BEVELS],
                border_inward: [0; MAX_FACET_BEVELS],
                border_no_adjust: [0; MAX_FACET_BEVELS],
            };
            for v in f.border_planes.iter_mut() {
                *v = c.i()?;
            }
            for v in f.border_inward.iter_mut() {
                *v = i32::from(c.u8()?);
            }
            for v in f.border_no_adjust.iter_mut() {
                *v = i32::from(c.u8()?);
            }
            c.take(FACET_SIZE - 8 - 4 * MAX_FACET_BEVELS - 2 * MAX_FACET_BEVELS)?;
            Ok(f)
        })?;
        let patches = read_sec(&secs, b"PATC", 60, |c| {
            let head = [c.i()?, c.i()?, c.i()?, c.i()?, c.i()?];
            let bounds = [c.f3()?, c.f3()?];
            let (pf, pn, ff, fnn) = (c.i()?, c.i()?, c.i()?, c.i()?);
            Ok(CmPatch {
                surface: head[0],
                contents: head[1],
                surface_flags: head[2],
                width: head[3],
                height: head[4],
                collide: PatchCollide {
                    bounds,
                    planes: range(&planes, pf, pn)?.to_vec(),
                    facets: range(&facets, ff, fnn)?.to_vec(),
                },
            })
        })?;

        Ok(Self {
            shaders: read_sec(&secs, b"SHDR", 8, |c| {
                Ok(CmShader {
                    surface_flags: c.i()?,
                    content_flags: c.i()?,
                })
            })?,
            planes: read_sec(&secs, b"PLAN", 16, |c| {
                Ok(CmPlane {
                    normal: c.f3()?,
                    dist: c.f()?,
                })
            })?,
            nodes: read_sec(&secs, b"NODE", 12, |c| {
                Ok(CmNode {
                    plane: c.i()?,
                    children: [c.i()?, c.i()?],
                })
            })?,
            leafs: read_sec(&secs, b"LEAF", 24, |c| {
                Ok(CmLeaf {
                    cluster: c.i()?,
                    area: c.i()?,
                    first_leaf_brush: c.i()?,
                    num_leaf_brushes: c.i()?,
                    first_leaf_surface: c.i()?,
                    num_leaf_surfaces: c.i()?,
                })
            })?,
            leaf_brushes: read_sec(&secs, b"LBRK", 4, |c| c.i())?,
            leaf_surfaces: read_sec(&secs, b"LSRF", 4, |c| c.i())?,
            brushes: read_sec(&secs, b"BRSH", 12, |c| {
                Ok(CmBrush {
                    first_side: c.i()?,
                    num_sides: c.i()?,
                    shader: c.i()?,
                })
            })?,
            brush_sides: read_sec(&secs, b"BSID", 8, |c| {
                Ok(CmBrushSide {
                    plane: c.i()?,
                    shader: c.i()?,
                })
            })?,
            submodels: read_sec(&secs, b"MODL", 40, |c| {
                Ok(CmSubmodel {
                    mins: c.f3()?,
                    maxs: c.f3()?,
                    first_brush: c.i()?,
                    num_brushes: c.i()?,
                    first_surface: c.i()?,
                    num_surfaces: c.i()?,
                })
            })?,
            patches,
            visibility,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn check(name: &str) {
        let Some(bsp) = crate::testdata::bsp(name) else {
            return;
        };
        let m = CollisionMap::build(&bsp);
        assert_eq!(m.shaders.len(), bsp.shaders.len());
        assert_eq!(m.planes.len(), bsp.planes.len());
        assert_eq!(m.nodes.len(), bsp.nodes.len());
        assert_eq!(m.leafs.len(), bsp.leafs.len());
        assert_eq!(m.leaf_brushes.len(), bsp.leaf_brushes.len());
        assert_eq!(m.leaf_surfaces.len(), bsp.leaf_surfaces.len());
        assert_eq!(m.brushes.len(), bsp.brushes.len());
        assert_eq!(m.brush_sides.len(), bsp.brush_sides.len());
        assert_eq!(m.submodels.len(), bsp.models.len());
        let n = bsp
            .surfaces
            .iter()
            .filter(|s| s.surface_type == MST_PATCH)
            .count();
        assert_eq!(m.patches.len(), n);

        let bytes = m.to_bytes();
        let back = CollisionMap::from_bytes(&bytes).unwrap();
        assert_eq!(back, m);
        assert_eq!(back.to_bytes(), bytes);

        let dir = std::env::temp_dir().join(format!("oaconv-cm-{name}-{}", std::process::id()));
        crate::luau::write_buffer_modules(&dir, "collision", &bytes).unwrap();
        let joined = crate::luau::read_buffer_modules(&dir, "collision").unwrap();
        std::fs::remove_dir_all(&dir).unwrap();
        assert_eq!(joined, bytes);
    }

    #[test]
    fn real_maps() {
        for m in ["oa_dm1", "oa_ctf2", "am_thornish"] {
            check(m);
        }
    }

    #[test]
    fn rejects_bad_blobs() {
        let m = CollisionMap {
            shaders: vec![],
            planes: vec![],
            nodes: vec![],
            leafs: vec![],
            leaf_brushes: vec![],
            leaf_surfaces: vec![],
            brushes: vec![],
            brush_sides: vec![],
            submodels: vec![],
            patches: vec![],
            visibility: CmVisibility::default(),
        };
        let bytes = m.to_bytes();
        assert_eq!(CollisionMap::from_bytes(&bytes).unwrap(), m);
        let mut bad = bytes.clone();
        bad[0] = b'X';
        assert!(CollisionMap::from_bytes(&bad).is_err());
        assert!(CollisionMap::from_bytes(&bytes[..bytes.len() - 1]).is_err());
        assert!(CollisionMap::from_bytes(&bytes[..20]).is_err());
    }
}
