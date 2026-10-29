//! Evaluates a static Q3 shader per atlas texel, the way the fixed-function
//! pipeline of ioquake3 `renderergl1` (tr_shade.c, tr_shade_calc.c, GPL-2.0)
//! would draw it: each stage's texture x rgbGen/alphaGen, blended into an
//! 8-bit framebuffer, then the hardware gamma ramp's overbright scale.

use std::collections::HashMap;
use std::sync::Arc;

use image::RgbaImage;

use crate::shader::{Shader, Stage};
use crate::vfs::Vfs;

/// `r_overBrightBits` default; `r_mapOverBrightBits` is 2, so lightmaps and
/// vertex colours are shifted left by `MAP_OVERBRIGHT - OVERBRIGHT` bits and
/// the gamma ramp multiplies the framebuffer by `1 << OVERBRIGHT`.
pub const OVERBRIGHT: u32 = 1;
pub const MAP_OVERBRIGHT: u32 = 2;

/// `R_ColorShiftLightingBytes`: shift, then scale back so the brightest
/// channel is 255 (keeps the hue instead of clipping to white).
pub fn color_shift(rgb: [u8; 3]) -> [u8; 3] {
    let shift = MAP_OVERBRIGHT - OVERBRIGHT;
    let mut c = rgb.map(|v| (v as u32) << shift);
    let max = c.into_iter().max().unwrap_or(0);
    if max > 255 {
        c = c.map(|v| v * 255 / max);
    }
    c.map(|v| v as u8)
}

/// A texture with a box-filtered mip chain, 8-bit like the engine's upload.
pub struct Tex {
    levels: Vec<(u32, u32, Vec<[u8; 4]>)>,
}

impl Tex {
    pub fn new(img: &RgbaImage) -> Self {
        let (mut w, mut h) = img.dimensions();
        let mut data: Vec<[u8; 4]> = img.pixels().map(|p| p.0).collect();
        let mut levels = Vec::new();
        loop {
            levels.push((w, h, data.clone()));
            if w == 1 && h == 1 {
                break;
            }
            let (nw, nh) = ((w / 2).max(1), (h / 2).max(1));
            let mut next = Vec::with_capacity((nw * nh) as usize);
            for y in 0..nh {
                for x in 0..nw {
                    let mut acc = [0u32; 4];
                    for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                        let sx = (x * 2 + dx).min(w - 1);
                        let sy = (y * 2 + dy).min(h - 1);
                        let p = data[(sy * w + sx) as usize];
                        for c in 0..4 {
                            acc[c] += p[c] as u32;
                        }
                    }
                    next.push(acc.map(|v| ((v + 2) / 4) as u8));
                }
            }
            (w, h, data) = (nw, nh, next);
        }
        Self { levels }
    }

    pub fn size(&self) -> (u32, u32) {
        (self.levels[0].0, self.levels[0].1)
    }

    fn texel(&self, level: usize, x: i64, y: i64, clamp: bool) -> [f32; 4] {
        let (w, h, data) = &self.levels[level];
        let (w, h) = (*w as i64, *h as i64);
        let (x, y) = if clamp {
            (x.clamp(0, w - 1), y.clamp(0, h - 1))
        } else {
            (x.rem_euclid(w), y.rem_euclid(h))
        };
        data[(y * w + x) as usize].map(|v| v as f32 / 255.0)
    }

    fn bilinear(&self, level: usize, s: f32, t: f32, clamp: bool) -> [f32; 4] {
        let (w, h, _) = &self.levels[level];
        let u = s * *w as f32 - 0.5;
        let v = t * *h as f32 - 0.5;
        let (x0, y0) = (u.floor(), v.floor());
        let (fx, fy) = (u - x0, v - y0);
        let (x0, y0) = (x0 as i64, y0 as i64);
        let a = self.texel(level, x0, y0, clamp);
        let b = self.texel(level, x0 + 1, y0, clamp);
        let c = self.texel(level, x0, y0 + 1, clamp);
        let d = self.texel(level, x0 + 1, y0 + 1, clamp);
        std::array::from_fn(|i| {
            let top = a[i] + (b[i] - a[i]) * fx;
            let bottom = c[i] + (d[i] - c[i]) * fx;
            top + (bottom - top) * fy
        })
    }

    /// Trilinear sample; `footprint` is how many level-0 texels one atlas texel spans.
    pub fn sample(&self, s: f32, t: f32, footprint: f32, clamp: bool) -> [f32; 4] {
        let lod = footprint
            .max(1.0)
            .log2()
            .min((self.levels.len() - 1) as f32);
        let l0 = lod.floor() as usize;
        let f = lod - l0 as f32;
        let a = self.bilinear(l0, s, t, clamp);
        if f < 1e-3 || l0 + 1 >= self.levels.len() {
            return a;
        }
        let b = self.bilinear(l0 + 1, s, t, clamp);
        std::array::from_fn(|i| a[i] + (b[i] - a[i]) * f)
    }
}

/// Decoded textures for one map, keyed by resolved VFS path.
#[derive(Default)]
pub struct TexCache {
    map: HashMap<String, Option<Arc<Tex>>>,
    pub missing: Vec<String>,
}

impl TexCache {
    pub fn get(&mut self, vfs: &Vfs, name: &str) -> Option<Arc<Tex>> {
        let path = vfs.find_image(name);
        let key = path.clone().unwrap_or_else(|| name.to_string());
        if let Some(t) = self.map.get(&key) {
            return t.clone();
        }
        let tex = path
            .and_then(|p| vfs.read(&p).map(|b| (p, b)))
            .and_then(|(p, b)| crate::texture::decode(&b, &p).ok())
            .map(|img| Arc::new(Tex::new(&img)));
        if tex.is_none() {
            self.missing.push(name.to_string());
        }
        self.map.insert(key, tex.clone());
        tex
    }
}

/// Per-texel inputs, interpolated from the surface's vertices.
#[derive(Clone, Copy, Debug, Default)]
pub struct Texel {
    pub pos: [f32; 3],
    pub st: [f32; 2],
    pub lm: [f32; 2],
    /// Vertex colour after `color_shift`, 0..1.
    pub color: [f32; 4],
    /// d(st)/d(atlas texel) along x and y, and the same for lightmap coords
    /// and positions, for mip selection.
    pub dst: [[f32; 2]; 2],
    pub dlm: [[f32; 2]; 2],
    pub dpos: [[f32; 3]; 2],
}

#[derive(Clone)]
enum Src {
    Lightmap,
    White,
    Image(Arc<Tex>),
}

#[derive(Clone, Copy)]
enum Tc {
    Base,
    Lightmap,
    Vector([f32; 3], [f32; 3]),
}

#[derive(Clone, Copy)]
enum Gen {
    Const(f32, f32, f32),
    Vertex(f32),
    OneMinusVertex(f32),
}

#[derive(Clone, Copy)]
enum AGen {
    Texture,
    Const(f32),
    Vertex,
    OneMinusVertex,
}

#[derive(Clone, Copy)]
enum Factor {
    Zero,
    One,
    DstColor,
    OneMinusDstColor,
    SrcColor,
    OneMinusSrcColor,
    SrcAlpha,
    OneMinusSrcAlpha,
    DstAlpha,
    OneMinusDstAlpha,
}

#[derive(Clone)]
struct StageProg {
    src: Src,
    tc: Tc,
    /// s' = m[0] s + m[1] t + m[2]; t' = m[3] s + m[4] t + m[5]
    m: [f32; 6],
    clamp: bool,
    rgb: Gen,
    alpha: AGen,
    blend: Option<(Factor, Factor)>,
}

/// One shader compiled for baking.
#[derive(Clone)]
pub struct Program {
    stages: Vec<StageProg>,
}

fn num(tokens: &[String], i: usize) -> f32 {
    tokens.get(i).and_then(|t| t.parse().ok()).unwrap_or(0.0)
}

/// Numbers in a token list, skipping `(` and `)`.
fn nums(tokens: &[String]) -> Vec<f32> {
    tokens
        .iter()
        .filter_map(|t| t.trim_matches(|c| c == '(' || c == ')').parse().ok())
        .collect()
}

fn factor(name: &str) -> Factor {
    match name {
        "gl_zero" => Factor::Zero,
        "gl_dst_color" => Factor::DstColor,
        "gl_one_minus_dst_color" => Factor::OneMinusDstColor,
        "gl_src_color" => Factor::SrcColor,
        "gl_one_minus_src_color" => Factor::OneMinusSrcColor,
        "gl_src_alpha" => Factor::SrcAlpha,
        "gl_one_minus_src_alpha" => Factor::OneMinusSrcAlpha,
        "gl_dst_alpha" => Factor::DstAlpha,
        "gl_one_minus_dst_alpha" => Factor::OneMinusDstAlpha,
        _ => Factor::One,
    }
}

fn tc_matrix(stage: &Stage) -> [f32; 6] {
    let mut m = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0];
    for tcmod in &stage.tc_mods {
        let args = nums(&tcmod[1..]);
        let get = |i: usize| args.get(i).copied().unwrap_or(0.0);
        // Each tcMod maps (s, t) -> (s', t'); compose it after m.
        let step = match tcmod.first().map(String::as_str) {
            Some("scale") => [get(0), 0.0, 0.0, 0.0, get(1), 0.0],
            // RB_CalcTransformTexCoords: s' = s*m00 + t*m10 + t0, t' = s*m01 + t*m11 + t1
            Some("transform") => [get(0), get(2), get(4), get(1), get(3), get(5)],
            _ => continue,
        };
        m = [
            step[0] * m[0] + step[1] * m[3],
            step[0] * m[1] + step[1] * m[4],
            step[0] * m[2] + step[1] * m[5] + step[2],
            step[3] * m[0] + step[4] * m[3],
            step[3] * m[1] + step[4] * m[4],
            step[3] * m[2] + step[4] * m[5] + step[5],
        ];
    }
    m
}

impl Program {
    /// `lightmapped`: the surface has a lightmap; a `$lightmap` stage on a
    /// vertex-lit surface reads white, as `ParseStage` substitutes `tr.whiteImage`.
    pub fn compile(
        shader: &Shader,
        lightmapped: bool,
        mut image: impl FnMut(&str) -> Option<Arc<Tex>>,
    ) -> Self {
        let identity_light = 1.0 / (1 << OVERBRIGHT) as f32;
        let stages = shader
            .stages
            .iter()
            .map(|stage| {
                let name = stage
                    .maps
                    .first()
                    .map(String::as_str)
                    .unwrap_or("$whiteimage");
                let src = match name {
                    "$lightmap" if lightmapped => Src::Lightmap,
                    "$lightmap" | "$whiteimage" | "*white" => Src::White,
                    _ => image(name).map(Src::Image).unwrap_or(Src::White),
                };
                let tc = match stage.tc_gen.first().map(String::as_str) {
                    Some("lightmap") => Tc::Lightmap,
                    Some("vector") => {
                        let v = nums(&stage.tc_gen[1..]);
                        let g = |i: usize| v.get(i).copied().unwrap_or(0.0);
                        Tc::Vector([g(0), g(1), g(2)], [g(3), g(4), g(5)])
                    }
                    _ if name == "$lightmap" => Tc::Lightmap,
                    _ => Tc::Base,
                };
                let gen: Vec<String> = if stage.rgb_gen.is_empty() {
                    vec![stage.rgb_gen_default.clone()]
                } else {
                    stage.rgb_gen.clone()
                };
                let rgb = match gen[0].as_str() {
                    "identitylighting" => {
                        Gen::Const(identity_light, identity_light, identity_light)
                    }
                    "vertex" => Gen::Vertex(identity_light),
                    "exactvertex" => Gen::Vertex(1.0),
                    "oneminusvertex" => Gen::OneMinusVertex(identity_light),
                    "const" | "constant" => {
                        let v = nums(&gen[1..]);
                        let g = |i: usize| v.get(i).copied().unwrap_or(1.0);
                        Gen::Const(g(0), g(1), g(2))
                    }
                    _ => Gen::Const(1.0, 1.0, 1.0),
                };
                let alpha = match stage.alpha_gen.first().map(String::as_str) {
                    Some("const") | Some("constant") => AGen::Const(num(&stage.alpha_gen, 1)),
                    Some("vertex") => AGen::Vertex,
                    Some("oneminusvertex") => AGen::OneMinusVertex,
                    Some("identity") => AGen::Const(1.0),
                    _ => AGen::Texture,
                };
                StageProg {
                    src,
                    tc,
                    m: tc_matrix(stage),
                    clamp: stage.clamp,
                    rgb,
                    alpha,
                    blend: stage.blend.as_ref().map(|[s, d]| (factor(s), factor(d))),
                }
            })
            .collect();
        Self { stages }
    }

    /// The displayed colour of one texel, 0..255.
    pub fn shade(&self, t: &Texel, lightmap: Option<&Tex>) -> [u8; 3] {
        let mut fb = [0.0f32; 4];
        for stage in &self.stages {
            let (base, d) = match stage.tc {
                Tc::Base => (t.st, t.dst),
                Tc::Lightmap => (t.lm, t.dlm),
                Tc::Vector(s, tv) => {
                    let dot = |a: [f32; 3], b: [f32; 3]| a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
                    (
                        [dot(t.pos, s), dot(t.pos, tv)],
                        [
                            [dot(t.dpos[0], s), dot(t.dpos[0], tv)],
                            [dot(t.dpos[1], s), dot(t.dpos[1], tv)],
                        ],
                    )
                }
            };
            let m = stage.m;
            let st = [
                m[0] * base[0] + m[1] * base[1] + m[2],
                m[3] * base[0] + m[4] * base[1] + m[5],
            ];
            let lin = |v: [f32; 2]| [m[0] * v[0] + m[1] * v[1], m[3] * v[0] + m[4] * v[1]];
            let (dx, dy) = (lin(d[0]), lin(d[1]));
            let tex = match &stage.src {
                Src::White => [1.0; 4],
                Src::Lightmap => match lightmap {
                    Some(lm) => lm.sample(st[0], st[1], 1.0, true),
                    None => [1.0; 4],
                },
                Src::Image(img) => {
                    let (w, h) = img.size();
                    let fx = ((dx[0] * w as f32).powi(2) + (dx[1] * h as f32).powi(2)).sqrt();
                    let fy = ((dy[0] * w as f32).powi(2) + (dy[1] * h as f32).powi(2)).sqrt();
                    img.sample(st[0], st[1], fx.max(fy), stage.clamp)
                }
            };
            let c = t.color;
            let gen = match stage.rgb {
                Gen::Const(r, g, b) => [r, g, b],
                Gen::Vertex(k) => [c[0] * k, c[1] * k, c[2] * k],
                Gen::OneMinusVertex(k) => [(1.0 - c[0]) * k, (1.0 - c[1]) * k, (1.0 - c[2]) * k],
            };
            let a = match stage.alpha {
                AGen::Texture => tex[3],
                AGen::Const(v) => tex[3] * v,
                AGen::Vertex => tex[3] * c[3],
                AGen::OneMinusVertex => tex[3] * (1.0 - c[3]),
            };
            let src = [tex[0] * gen[0], tex[1] * gen[1], tex[2] * gen[2], a];
            fb = match stage.blend {
                None => src,
                Some((sf, df)) => {
                    let f = |factor: Factor, i: usize| match factor {
                        Factor::Zero => 0.0,
                        Factor::One => 1.0,
                        Factor::DstColor => fb[i],
                        Factor::OneMinusDstColor => 1.0 - fb[i],
                        Factor::SrcColor => src[i],
                        Factor::OneMinusSrcColor => 1.0 - src[i],
                        Factor::SrcAlpha => src[3],
                        Factor::OneMinusSrcAlpha => 1.0 - src[3],
                        Factor::DstAlpha => fb[3],
                        Factor::OneMinusDstAlpha => 1.0 - fb[3],
                    };
                    std::array::from_fn(|i| src[i] * f(sf, i) + fb[i] * f(df, i))
                }
            }
            .map(|v| v.clamp(0.0, 1.0));
        }
        let scale = (1 << OVERBRIGHT) as f32;
        [0, 1, 2].map(|i| ((fb[i] * scale).min(1.0) * 255.0 + 0.5) as u8)
    }
}

/// A lightmap page as a texture, colour-shifted like `R_LoadLightmaps`.
pub fn lightmap_tex(raw: &[u8]) -> Tex {
    let size = crate::bsp::LIGHTMAP_SIZE as u32;
    let img = RgbaImage::from_fn(size, size, |x, y| {
        let i = ((y * size + x) * 3) as usize;
        let [r, g, b] = color_shift([raw[i], raw[i + 1], raw[i + 2]]);
        image::Rgba([r, g, b, 255])
    });
    Tex::new(&img)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::shader::Stage;

    fn stage(maps: &[&str], blend: Option<[&str; 2]>, default: &str) -> Stage {
        Stage {
            maps: maps.iter().map(|s| s.to_string()).collect(),
            blend: blend.map(|b| b.map(String::from)),
            rgb_gen_default: default.into(),
            depth_write: true,
            ..Default::default()
        }
    }

    #[test]
    fn color_shift_keeps_hue_when_saturating() {
        assert_eq!(color_shift([100, 50, 10]), [200, 100, 20]);
        assert_eq!(color_shift([200, 100, 0]), [255, 127, 0]);
    }

    #[test]
    fn lightmap_times_white_texture_is_four_times_the_stored_light() {
        // $lightmap, then a white diffuse with blendFunc filter: the
        // display shows lightmap << 1 (map shift) << 1 (gamma ramp).
        let shader = Shader {
            stages: vec![
                stage(&["$lightmap"], None, "identity"),
                stage(
                    &["$whiteimage"],
                    Some(["gl_dst_color", "gl_zero"]),
                    "identity",
                ),
            ],
            ..Default::default()
        };
        let vfs_free = Program::compile(&shader, true, |_| None);
        let mut raw = vec![0u8; 128 * 128 * 3];
        raw.iter_mut().step_by(3).for_each(|v| *v = 40);
        let lm = lightmap_tex(&raw);
        let texel = Texel {
            lm: [0.5, 0.5],
            ..Default::default()
        };
        assert_eq!(vfs_free.shade(&texel, Some(&lm)), [160, 0, 0]);
    }

    #[test]
    fn mips_average_and_wrap() {
        let img = RgbaImage::from_fn(4, 4, |x, _| {
            image::Rgba(if x % 2 == 0 { [255; 4] } else { [0, 0, 0, 255] })
        });
        let tex = Tex::new(&img);
        let far = tex.sample(0.3, 0.3, 4.0, false);
        assert!((far[0] - 0.5).abs() < 0.02, "{far:?}");
        let near = tex.sample(0.125, 0.125, 1.0, false);
        assert!(near[0] > 0.99);
    }
}
