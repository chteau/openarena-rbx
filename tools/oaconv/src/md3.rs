//! MD3 models (ioquake3 `qcommon/qfiles.h` md3 structs, GPL-2.0),
//! `animation.cfg` and `.skin` files. Runtime layout: docs/formats/md3.md.

use serde::Serialize;

use crate::mesh::Mesh;
use crate::shader::ShaderClass;

/// `MD3_XYZ_SCALE`: stored positions are 1/64 unit.
pub const XYZ_SCALE: f32 = 1.0 / 64.0;

const IDENT: &[u8; 4] = b"IDP3";
const VERSION: i32 = 15;
const HEADER_SIZE: usize = 108;
const FRAME_SIZE: usize = 56;
const TAG_SIZE: usize = 112;
const SURFACE_SIZE: usize = 108;
const SHADER_SIZE: usize = 68;

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Md3Frame {
    pub bounds: [[f32; 3]; 2],
    pub local_origin: [f32; 3],
    pub radius: f32,
    pub name: String,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Md3Tag {
    pub name: String,
    pub origin: [f32; 3],
    pub axis: [[f32; 3]; 3],
}

#[derive(Clone, Debug, PartialEq)]
pub struct Md3Surface {
    pub name: String,
    pub flags: i32,
    /// Shader names as stored (lowercased, extension kept).
    pub shaders: Vec<String>,
    /// Indices as stored (MD3 winding).
    pub triangles: Vec<[u32; 3]>,
    pub st: Vec<[f32; 2]>,
    /// Per frame, per vertex: position in 1/64 units, exactly as stored.
    pub xyz: Vec<Vec<[i16; 3]>>,
    /// Per frame, per vertex: the stored lat/lng normal (`lat << 8 | lng`).
    pub normals: Vec<Vec<u16>>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Md3 {
    pub name: String,
    pub flags: i32,
    pub frames: Vec<Md3Frame>,
    /// `tags[frame][tag]`.
    pub tags: Vec<Vec<Md3Tag>>,
    pub surfaces: Vec<Md3Surface>,
}

struct Reader<'a>(&'a [u8]);

impl Reader<'_> {
    fn bytes(&self, off: usize, len: usize) -> Result<&[u8], String> {
        off.checked_add(len)
            .and_then(|end| self.0.get(off..end))
            .ok_or_else(|| format!("range {off}+{len} outside file of {} bytes", self.0.len()))
    }

    fn i32(&self, off: usize) -> Result<i32, String> {
        let b = self.bytes(off, 4)?;
        Ok(i32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }

    fn f32(&self, off: usize) -> Result<f32, String> {
        Ok(f32::from_bits(self.i32(off)? as u32))
    }

    fn f32s<const N: usize>(&self, off: usize) -> Result<[f32; N], String> {
        let mut out = [0.0; N];
        for (i, v) in out.iter_mut().enumerate() {
            *v = self.f32(off + i * 4)?;
        }
        Ok(out)
    }

    fn i16(&self, off: usize) -> Result<i16, String> {
        let b = self.bytes(off, 2)?;
        Ok(i16::from_le_bytes([b[0], b[1]]))
    }

    fn count(&self, off: usize) -> Result<usize, String> {
        usize::try_from(self.i32(off)?).map_err(|_| format!("negative count at {off}"))
    }

    fn cstr(&self, off: usize, len: usize) -> Result<String, String> {
        let b = self.bytes(off, len)?;
        let end = b.iter().position(|&c| c == 0).unwrap_or(len);
        Ok(String::from_utf8_lossy(&b[..end]).into_owned())
    }
}

pub fn parse(bytes: &[u8]) -> Result<Md3, String> {
    let r = Reader(bytes);
    if r.bytes(0, 4)? != IDENT {
        return Err("not an IDP3 file".into());
    }
    let version = r.i32(4)?;
    if version != VERSION {
        return Err(format!("md3 version {version}, expected {VERSION}"));
    }
    r.bytes(0, HEADER_SIZE)?;
    let name = r.cstr(8, 64)?;
    let flags = r.i32(72)?;
    let num_frames = r.count(76)?;
    let num_tags = r.count(80)?;
    let num_surfaces = r.count(84)?;
    let ofs_frames = r.count(92)?;
    let ofs_tags = r.count(96)?;
    let ofs_surfaces = r.count(100)?;

    r.bytes(ofs_frames, num_frames.saturating_mul(FRAME_SIZE))?;
    let mut frames = Vec::with_capacity(num_frames);
    for f in 0..num_frames {
        let o = ofs_frames + f * FRAME_SIZE;
        let b: [f32; 6] = r.f32s(o)?;
        frames.push(Md3Frame {
            bounds: [[b[0], b[1], b[2]], [b[3], b[4], b[5]]],
            local_origin: r.f32s(o + 24)?,
            radius: r.f32(o + 36)?,
            name: r.cstr(o + 40, 16)?,
        });
    }

    r.bytes(
        ofs_tags,
        num_frames.saturating_mul(num_tags).saturating_mul(TAG_SIZE),
    )?;
    let mut tags = Vec::with_capacity(num_frames);
    for f in 0..num_frames {
        let mut row = Vec::with_capacity(num_tags);
        for t in 0..num_tags {
            let o = ofs_tags + (f * num_tags + t) * TAG_SIZE;
            let m: [f32; 9] = r.f32s(o + 76)?;
            row.push(Md3Tag {
                name: r.cstr(o, 64)?,
                origin: r.f32s(o + 64)?,
                axis: [[m[0], m[1], m[2]], [m[3], m[4], m[5]], [m[6], m[7], m[8]]],
            });
        }
        tags.push(row);
    }

    let mut surfaces = Vec::with_capacity(num_surfaces);
    let mut at = ofs_surfaces;
    for _ in 0..num_surfaces {
        let (s, end) = parse_surface(&r, at, num_frames)?;
        surfaces.push(s);
        at = at.checked_add(end).ok_or("surface offset overflow")?;
    }
    Ok(Md3 {
        name,
        flags,
        frames,
        tags,
        surfaces,
    })
}

fn parse_surface(r: &Reader, at: usize, num_frames: usize) -> Result<(Md3Surface, usize), String> {
    r.bytes(at, SURFACE_SIZE)?;
    if r.bytes(at, 4)? != IDENT {
        return Err("bad surface ident".into());
    }
    let name = r.cstr(at + 4, 64)?.to_lowercase();
    let flags = r.i32(at + 68)?;
    if r.count(at + 72)? != num_frames {
        return Err(format!("surface {name}: frame count differs from header"));
    }
    let num_shaders = r.count(at + 76)?;
    let num_verts = r.count(at + 80)?;
    let num_tris = r.count(at + 84)?;
    let ofs_tris = at + r.count(at + 88)?;
    let ofs_shaders = at + r.count(at + 92)?;
    let ofs_st = at + r.count(at + 96)?;
    let ofs_xyz = at + r.count(at + 100)?;
    let ofs_end = r.count(at + 104)?;
    if ofs_end < SURFACE_SIZE {
        return Err(format!("surface {name}: bad end offset"));
    }

    r.bytes(ofs_shaders, num_shaders.saturating_mul(SHADER_SIZE))?;
    let shaders = (0..num_shaders)
        .map(|i| Ok(r.cstr(ofs_shaders + i * SHADER_SIZE, 64)?.to_lowercase()))
        .collect::<Result<Vec<_>, String>>()?;

    r.bytes(ofs_tris, num_tris.saturating_mul(12))?;
    let mut triangles = Vec::with_capacity(num_tris);
    for t in 0..num_tris {
        let mut tri = [0u32; 3];
        for (k, v) in tri.iter_mut().enumerate() {
            let i = r.i32(ofs_tris + t * 12 + k * 4)?;
            if i < 0 || i as usize >= num_verts {
                return Err(format!("surface {name}: index {i} out of range"));
            }
            *v = i as u32;
        }
        triangles.push(tri);
    }

    r.bytes(ofs_st, num_verts.saturating_mul(8))?;
    let st = (0..num_verts)
        .map(|v| r.f32s(ofs_st + v * 8))
        .collect::<Result<Vec<_>, _>>()?;

    r.bytes(
        ofs_xyz,
        num_frames.saturating_mul(num_verts).saturating_mul(8),
    )?;
    let mut xyz = Vec::with_capacity(num_frames);
    let mut normals = Vec::with_capacity(num_frames);
    for f in 0..num_frames {
        let mut fx = Vec::with_capacity(num_verts);
        let mut fnorm = Vec::with_capacity(num_verts);
        for v in 0..num_verts {
            let o = ofs_xyz + (f * num_verts + v) * 8;
            fx.push([r.i16(o)?, r.i16(o + 2)?, r.i16(o + 4)?]);
            fnorm.push(r.i16(o + 6)? as u16);
        }
        xyz.push(fx);
        normals.push(fnorm);
    }
    Ok((
        Md3Surface {
            name,
            flags,
            shaders,
            triangles,
            st,
            xyz,
            normals,
        },
        ofs_end,
    ))
}

/// Decodes a stored lat/lng normal as the engine does (`R_LatLongToNormal`-style tables).
pub fn decode_normal(latlng: u16) -> [f32; 3] {
    let k = 2.0 * std::f32::consts::PI / 255.0;
    let lat = ((latlng >> 8) & 255) as f32 * k;
    let lng = (latlng & 255) as f32 * k;
    [lat.cos() * lng.sin(), lat.sin() * lng.sin(), lng.cos()]
}

fn pad4(buf: &mut Vec<u8>) {
    while !buf.len().is_multiple_of(4) {
        buf.push(0);
    }
}

fn put_str(buf: &mut Vec<u8>, s: &str) {
    let b = &s.as_bytes()[..s.len().min(255)];
    buf.push(b.len() as u8);
    buf.extend_from_slice(b);
}

fn put_f32s(buf: &mut Vec<u8>, v: &[f32]) {
    for x in v {
        buf.extend_from_slice(&x.to_le_bytes());
    }
}

/// The runtime buffer (docs/formats/md3.md) for EditableMesh animation.
pub fn to_buffer(md3: &Md3) -> Vec<u8> {
    let num_tags = md3.tags.first().map_or(0, Vec::len);
    let mut b = Vec::new();
    b.extend_from_slice(b"OAM3");
    b.extend_from_slice(&1u16.to_le_bytes());
    b.extend_from_slice(&(md3.frames.len() as u16).to_le_bytes());
    b.extend_from_slice(&(num_tags as u16).to_le_bytes());
    b.extend_from_slice(&(md3.surfaces.len() as u16).to_le_bytes());

    for f in &md3.frames {
        put_f32s(&mut b, &f.bounds[0]);
        put_f32s(&mut b, &f.bounds[1]);
        put_f32s(&mut b, &f.local_origin);
        put_f32s(&mut b, &[f.radius]);
    }
    if let Some(first) = md3.tags.first() {
        for t in first {
            put_str(&mut b, &t.name);
        }
    }
    pad4(&mut b);
    for row in &md3.tags {
        for t in row {
            put_f32s(&mut b, &t.origin);
            for a in &t.axis {
                put_f32s(&mut b, a);
            }
        }
    }

    for s in &md3.surfaces {
        put_str(&mut b, &s.name);
        b.push(s.shaders.len().min(255) as u8);
        for sh in s.shaders.iter().take(255) {
            put_str(&mut b, sh);
        }
        pad4(&mut b);
        b.extend_from_slice(&(s.st.len() as u32).to_le_bytes());
        b.extend_from_slice(&(s.triangles.len() as u32).to_le_bytes());
        for t in &s.triangles {
            for &i in t {
                b.extend_from_slice(&(i as u16).to_le_bytes());
            }
        }
        pad4(&mut b);
        for uv in &s.st {
            put_f32s(&mut b, uv);
        }
        for (fx, fnorm) in s.xyz.iter().zip(&s.normals) {
            for (p, n) in fx.iter().zip(fnorm) {
                for c in p {
                    b.extend_from_slice(&c.to_le_bytes());
                }
                b.extend_from_slice(&n.to_le_bytes());
            }
        }
    }
    b
}

/// One frame as static meshes, one per surface, named `<prefix>_<surface>`.
/// `texture` is `None`; the caller assigns textures from shaders/skins.
pub fn static_meshes(md3: &Md3, frame: usize, prefix: &str) -> Vec<Mesh> {
    md3.surfaces
        .iter()
        .map(|s| {
            let f = frame.min(s.xyz.len().saturating_sub(1));
            let (xyz, norms) = match (s.xyz.get(f), s.normals.get(f)) {
                (Some(x), Some(n)) => (x.as_slice(), n.as_slice()),
                _ => (&[][..], &[][..]),
            };
            Mesh {
                name: format!("{prefix}_{}", s.name),
                class: ShaderClass::Opaque,
                shader: s.shaders.first().cloned().unwrap_or_default(),
                texture: None,
                positions: xyz
                    .iter()
                    .map(|p| {
                        [
                            p[0] as f32 * XYZ_SCALE,
                            p[1] as f32 * XYZ_SCALE,
                            p[2] as f32 * XYZ_SCALE,
                        ]
                    })
                    .collect(),
                normals: norms.iter().map(|&n| decode_normal(n)).collect(),
                uvs: s.st.clone(),
                colors: vec![[255; 4]; xyz.len()],
                indices: s.triangles.iter().flatten().copied().collect(),
            }
        })
        .collect()
}

#[derive(Clone, Debug, Default, PartialEq, Serialize)]
pub struct AnimationCfg {
    pub sex: Option<String>,
    pub footsteps: Option<String>,
    pub headoffset: Option<[f32; 3]>,
    pub fixedlegs: bool,
    pub fixedtorso: bool,
    /// `[first_frame, num_frames, looping_frames, fps]` in file order
    /// (BOTH_DEATH1 ... per bg_public.h `animNumber_t`), raw as written.
    pub animations: Vec<[i32; 4]>,
}

/// Parses like cg_players.c `CG_ParseAnimationFile` (without the leg-frame skip,
/// which the client applies).
pub fn parse_animation_cfg(text: &str) -> Result<AnimationCfg, String> {
    let mut cfg = AnimationCfg::default();
    for (n, line) in text.lines().enumerate() {
        let line = line.split("//").next().unwrap_or("");
        let mut tok = line.split_whitespace();
        let Some(first) = tok.next() else { continue };
        match first.to_lowercase().as_str() {
            "footsteps" => cfg.footsteps = tok.next().map(str::to_lowercase),
            "sex" => cfg.sex = tok.next().map(str::to_lowercase),
            "fixedlegs" => cfg.fixedlegs = true,
            "fixedtorso" => cfg.fixedtorso = true,
            "headoffset" => {
                let v = tok
                    .map(str::parse::<f32>)
                    .collect::<Result<Vec<_>, _>>()
                    .map_err(|e| format!("line {}: {e}", n + 1))?;
                if v.len() < 3 {
                    return Err(format!("line {}: headoffset needs 3 numbers", n + 1));
                }
                cfg.headoffset = Some([v[0], v[1], v[2]]);
            }
            _ if first.starts_with(|c: char| c.is_ascii_digit()) => {
                let v = std::iter::once(first)
                    .chain(tok)
                    .map(str::parse::<i32>)
                    .collect::<Result<Vec<_>, _>>()
                    .map_err(|e| format!("line {}: {e}", n + 1))?;
                if v.len() < 4 {
                    return Err(format!("line {}: animation row needs 4 numbers", n + 1));
                }
                cfg.animations.push([v[0], v[1], v[2], v[3]]);
            }
            _ => {}
        }
    }
    Ok(cfg)
}

/// `.skin`: `surface,shader` lines; `tag_*` lines and empty shaders skipped.
pub fn parse_skin(text: &str) -> Vec<(String, String)> {
    text.lines()
        .filter_map(|line| {
            let line = line.trim().to_lowercase();
            let (surf, shader) = line.split_once(',')?;
            let (surf, shader) = (surf.trim(), shader.trim());
            (!surf.is_empty() && !surf.starts_with("tag_") && !shader.is_empty())
                .then(|| (surf.to_string(), shader.to_string()))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pad(n: usize) -> usize {
        n.div_ceil(4) * 4
    }

    fn expected_len(m: &Md3) -> usize {
        let f = m.frames.len();
        let t = m.tags.first().map_or(0, Vec::len);
        let tag_names: usize = m
            .tags
            .first()
            .map_or(0, |r| r.iter().map(|t| 1 + t.name.len()).sum());
        let mut n = 12 + 40 * f + pad(tag_names) + f * t * 48;
        for s in &m.surfaces {
            let head = 1 + s.name.len() + 1 + s.shaders.iter().map(|x| 1 + x.len()).sum::<usize>();
            n += pad(head) + 8 + pad(s.triangles.len() * 6) + s.st.len() * 8 + f * s.st.len() * 8;
        }
        n
    }

    fn all_md3() -> Vec<(String, Md3)> {
        let Some(vfs) = crate::testdata::vfs() else {
            return vec![];
        };
        let mut out = vec![];
        let mut failed = vec![];
        for p in vfs.list("models/", &[".md3"]) {
            match vfs
                .read(&p)
                .ok_or("unreadable".to_string())
                .and_then(|b| parse(&b))
            {
                Ok(m) => out.push((p, m)),
                Err(e) => failed.push(format!("{p}: {e}")),
            }
        }
        for f in &failed {
            eprintln!("{f}");
        }
        assert!(failed.is_empty(), "{} md3 failed", failed.len());
        out
    }

    #[test]
    fn every_md3_parses_and_converts() {
        for (p, m) in all_md3() {
            assert_eq!(to_buffer(&m).len(), expected_len(&m), "{p}");
            for (s, mesh) in m.surfaces.iter().zip(static_meshes(&m, 0, "x")) {
                assert_eq!(mesh.positions.len(), s.st.len(), "{p}");
                assert_eq!(mesh.normals.len(), s.st.len(), "{p}");
            }
        }
    }

    #[test]
    fn normals_are_unit() {
        for n in [0u16, 0x0101, 0x40ff, 0xff80, 0x8040] {
            let v = decode_normal(n);
            let l = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt();
            assert!((l - 1.0).abs() < 1e-4);
        }
    }

    #[test]
    fn rocket_launcher_has_flash_tag() {
        let Some(vfs) = crate::testdata::vfs() else {
            return;
        };
        let Some(bytes) = vfs.read("models/weapons2/rocketl/rocketl.md3") else {
            return;
        };
        let m = parse(&bytes).unwrap();
        assert!(m.tags[0].iter().any(|t| t.name == "tag_flash"));
    }

    #[test]
    fn animation_cfgs_and_skins_parse() {
        let Some(vfs) = crate::testdata::vfs() else {
            return;
        };
        for p in vfs.list("models/players/", &["animation.cfg"]) {
            let text = String::from_utf8_lossy(&vfs.read(&p).unwrap()).into_owned();
            let cfg = parse_animation_cfg(&text).unwrap_or_else(|e| panic!("{p}: {e}"));
            assert!(cfg.animations.len() >= 25, "{p}: {}", cfg.animations.len());
        }
        for p in vfs.list("models/", &[".skin"]) {
            let text = String::from_utf8_lossy(&vfs.read(&p).unwrap()).into_owned();
            parse_skin(&text);
        }
    }

    #[test]
    fn skin_skips_tags() {
        let s = parse_skin("Tag_Head,\nh_head,models/x.tga\n");
        assert_eq!(s, vec![("h_head".to_string(), "models/x.tga".to_string())]);
    }
}
