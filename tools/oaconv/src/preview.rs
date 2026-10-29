//! A small software rasterizer for checking baked maps without Roblox.

use std::collections::HashMap;

use image::{Rgba, RgbaImage};

use crate::mesh::Mesh;
use crate::shader::ShaderClass;

/// Quake-space camera, angles as in Q3 (`yaw` around +Z from +X, `pitch` positive looks down).
#[derive(Clone, Copy, Debug)]
pub struct Camera {
    pub origin: [f32; 3],
    pub yaw: f32,
    pub pitch: f32,
    pub fov_x: f32,
}

const SKY: [f32; 3] = [90.0, 130.0, 200.0];

/// Position (view space) followed by u, v, r, g, b, a.
type Vert = [f32; 9];

/// Screen x, y, depth (larger is nearer) and 1/w for perspective correction.
struct Screen {
    x: f32,
    y: f32,
    depth: f32,
    iw: f32,
}

fn sub(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}

fn dot(a: [f32; 3], b: [f32; 3]) -> f32 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

fn cross(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}

fn normalize(a: [f32; 3]) -> [f32; 3] {
    let l = dot(a, a).sqrt();
    if l == 0.0 {
        a
    } else {
        [a[0] / l, a[1] / l, a[2] / l]
    }
}

/// Sutherland-Hodgman against the plane z = 1 (view space, z forward).
fn clip_near(poly: &[Vert]) -> Vec<Vert> {
    let mut out = Vec::with_capacity(poly.len() + 1);
    for i in 0..poly.len() {
        let a = &poly[i];
        let b = &poly[(i + 1) % poly.len()];
        let (ain, bin) = (a[2] >= 1.0, b[2] >= 1.0);
        if ain {
            out.push(*a);
        }
        if ain != bin {
            let t = (1.0 - a[2]) / (b[2] - a[2]);
            let mut v = [0.0; 9];
            for k in 0..9 {
                v[k] = a[k] + (b[k] - a[k]) * t;
            }
            v[2] = 1.0;
            out.push(v);
        }
    }
    out
}

fn sample(img: &RgbaImage, u: f32, v: f32) -> [f32; 4] {
    let (w, h) = (img.width() as i64, img.height() as i64);
    let fx = u * w as f32 - 0.5;
    let fy = v * h as f32 - 0.5;
    let (x0, y0) = (fx.floor(), fy.floor());
    let (tx, ty) = (fx - x0, fy - y0);
    let texel = |x: i64, y: i64| {
        img.get_pixel(x.rem_euclid(w) as u32, y.rem_euclid(h) as u32)
            .0
    };
    let (x0, y0) = (x0 as i64, y0 as i64);
    let taps = [
        (texel(x0, y0), (1.0 - tx) * (1.0 - ty)),
        (texel(x0 + 1, y0), tx * (1.0 - ty)),
        (texel(x0, y0 + 1), (1.0 - tx) * ty),
        (texel(x0 + 1, y0 + 1), tx * ty),
    ];
    let mut out = [0.0; 4];
    for (t, wt) in taps {
        for c in 0..4 {
            out[c] += t[c] as f32 * wt;
        }
    }
    out
}

struct Target {
    w: u32,
    h: u32,
    img: RgbaImage,
    depth: Vec<f32>,
}

#[allow(clippy::too_many_arguments)]
fn fill(
    t: &mut Target,
    tri: &[(Screen, Vert); 3],
    two_sided: bool,
    class: ShaderClass,
    tex: Option<&RgbaImage>,
    atlas: bool,
) {
    let [(a, va), (b, vb), (c, vc)] = tri;
    let area = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y);
    if area == 0.0 || (area < 0.0 && !two_sided) {
        return;
    }
    let min_x = a.x.min(b.x).min(c.x).floor().max(0.0) as u32;
    let min_y = a.y.min(b.y).min(c.y).floor().max(0.0) as u32;
    let max_x = (a.x.max(b.x).max(c.x).ceil().max(0.0) as u32).min(t.w.saturating_sub(1));
    let max_y = (a.y.max(b.y).max(c.y).ceil().max(0.0) as u32).min(t.h.saturating_sub(1));
    let blend = class == ShaderClass::Blend;
    let sky = class == ShaderClass::Sky;
    let alpha_test = class == ShaderClass::AlphaTest;
    for y in min_y..=max_y {
        for x in min_x..=max_x {
            let (px, py) = (x as f32 + 0.5, y as f32 + 0.5);
            let l0 = ((b.x - px) * (c.y - py) - (c.x - px) * (b.y - py)) / area;
            let l1 = ((c.x - px) * (a.y - py) - (a.x - px) * (c.y - py)) / area;
            let l2 = 1.0 - l0 - l1;
            if l0 < 0.0 || l1 < 0.0 || l2 < 0.0 {
                continue;
            }
            let depth = l0 * a.depth + l1 * b.depth + l2 * c.depth;
            let idx = (y * t.w + x) as usize;
            if depth <= t.depth[idx] {
                continue;
            }
            let (w0, w1, w2) = (l0 * a.iw, l1 * b.iw, l2 * c.iw);
            let sum = w0 + w1 + w2;
            let attr = |k: usize| (w0 * va[k] + w1 * vb[k] + w2 * vc[k]) / sum;
            let vcol = [attr(5), attr(6), attr(7)];
            let mut rgb = vcol;
            if sky {
                rgb = SKY;
            } else if let Some(img) = tex {
                let s = sample(img, attr(3), attr(4));
                if alpha_test && s[3] < 128.0 {
                    continue;
                }
                rgb = if atlas {
                    [s[0], s[1], s[2]]
                } else {
                    [
                        s[0] * vcol[0] / 255.0,
                        s[1] * vcol[1] / 255.0,
                        s[2] * vcol[2] / 255.0,
                    ]
                };
            }
            let px = t.img.get_pixel_mut(x, y);
            for (k, &c) in rgb.iter().enumerate() {
                let v = if blend { px.0[k] as f32 + c } else { c };
                px.0[k] = v.clamp(0.0, 255.0).round() as u8;
            }
            if !blend {
                t.depth[idx] = depth;
            }
        }
    }
}

/// Draws every mesh: `to_view` maps a world point into the space `project`
/// consumes; `clip` enables near-plane clipping (perspective only).
fn raster(
    meshes: &[Mesh],
    textures: &HashMap<String, RgbaImage>,
    w: u32,
    h: u32,
    clip: bool,
    to_view: impl Fn([f32; 3]) -> [f32; 3],
    project: impl Fn([f32; 3]) -> Screen,
) -> RgbaImage {
    let mut t = Target {
        w,
        h,
        img: RgbaImage::from_pixel(w, h, Rgba([0, 0, 0, 255])),
        depth: vec![f32::NEG_INFINITY; (w * h) as usize],
    };
    let blend_pass = |m: &&Mesh| m.class == ShaderClass::Blend;
    let opaque = meshes.iter().filter(|m| !blend_pass(m));
    let blended = meshes.iter().filter(blend_pass);
    for m in opaque.chain(blended) {
        let two_sided = matches!(
            m.class,
            ShaderClass::Sky | ShaderClass::Blend | ShaderClass::AlphaTest | ShaderClass::Deform
        );
        let tex = m.texture.as_ref().and_then(|n| textures.get(n));
        let atlas = m.shader == "atlas";
        let vert = |i: u32| -> Vert {
            let i = i as usize;
            let p = to_view(m.positions[i]);
            let uv = m.uvs.get(i).copied().unwrap_or([0.0; 2]);
            let c = m.colors.get(i).copied().unwrap_or([255; 4]);
            [
                p[0],
                p[1],
                p[2],
                uv[0],
                uv[1],
                c[0] as f32,
                c[1] as f32,
                c[2] as f32,
                c[3] as f32,
            ]
        };
        for tri in m.indices.chunks(3).filter(|t| t.len() == 3) {
            let poly = [vert(tri[0]), vert(tri[1]), vert(tri[2])];
            let poly = if clip {
                clip_near(&poly)
            } else {
                poly.to_vec()
            };
            for k in 1..poly.len().saturating_sub(1) {
                let pick = |v: &Vert| (project([v[0], v[1], v[2]]), *v);
                let st = [pick(&poly[0]), pick(&poly[k]), pick(&poly[k + 1])];
                fill(&mut t, &st, two_sided, m.class, tex, atlas);
            }
        }
    }
    t.img
}

/// Perspective render of `meshes` (Quake space, Quake winding, back faces culled
/// unless `two_sided`). Each mesh samples `textures[mesh.texture]` bilinearly with
/// wrap, times its vertex colour unless the shader is `"atlas"`; untextured
/// meshes use vertex colour. Pixels with no geometry are black.
pub fn render(
    meshes: &[Mesh],
    textures: &HashMap<String, RgbaImage>,
    cam: Camera,
    width: u32,
    height: u32,
) -> RgbaImage {
    let (yaw, pitch) = (cam.yaw.to_radians(), cam.pitch.to_radians());
    let fwd = [
        pitch.cos() * yaw.cos(),
        pitch.cos() * yaw.sin(),
        -pitch.sin(),
    ];
    let right = normalize(cross(fwd, [0.0, 0.0, 1.0]));
    let up = cross(right, fwd);
    let focal = width as f32 / 2.0 / (cam.fov_x.to_radians() / 2.0).tan();
    let (cx, cy) = (width as f32 / 2.0, height as f32 / 2.0);
    raster(
        meshes,
        textures,
        width,
        height,
        true,
        |p| {
            let d = sub(p, cam.origin);
            [dot(d, right), dot(d, up), dot(d, fwd)]
        },
        |v| {
            let iw = 1.0 / v[2];
            Screen {
                x: cx + v[0] * iw * focal,
                y: cy - v[1] * iw * focal,
                depth: iw,
                iw,
            }
        },
    )
}

/// Orthographic top-down render (looking down -Z) fitted to the meshes' XY bounds.
pub fn render_top(
    meshes: &[Mesh],
    textures: &HashMap<String, RgbaImage>,
    width: u32,
    height: u32,
) -> RgbaImage {
    let (mut lo, mut hi) = ([f32::MAX; 2], [f32::MIN; 2]);
    for p in meshes.iter().flat_map(|m| m.positions.iter()) {
        for k in 0..2 {
            lo[k] = lo[k].min(p[k]);
            hi[k] = hi[k].max(p[k]);
        }
    }
    if lo[0] > hi[0] {
        return RgbaImage::from_pixel(width, height, Rgba([0, 0, 0, 255]));
    }
    let span = (hi[0] - lo[0]).max(1e-3).max(0.0);
    let span_y = (hi[1] - lo[1]).max(1e-3);
    let scale = (width as f32 / span).min(height as f32 / span_y);
    let mid = [(lo[0] + hi[0]) / 2.0, (lo[1] + hi[1]) / 2.0];
    let (cx, cy) = (width as f32 / 2.0, height as f32 / 2.0);
    raster(
        meshes,
        textures,
        width,
        height,
        false,
        |p| {
            [
                cx + (p[0] - mid[0]) * scale,
                cy - (p[1] - mid[1]) * scale,
                p[2],
            ]
        },
        |v| Screen {
            x: v[0],
            y: v[1],
            depth: v[2],
            iw: 1.0,
        },
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn quad(x: f32, color: [u8; 4]) -> Mesh {
        Mesh {
            name: "q".into(),
            positions: vec![
                [x, 10.0, 10.0],
                [x, -10.0, 10.0],
                [x, -10.0, -10.0],
                [x, 10.0, -10.0],
            ],
            normals: vec![[-1.0, 0.0, 0.0]; 4],
            uvs: vec![[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]],
            colors: vec![color; 4],
            indices: vec![0, 1, 2, 0, 2, 3],
            ..Default::default()
        }
    }

    fn cam(x: f32, yaw: f32) -> Camera {
        Camera {
            origin: [x, 0.0, 0.0],
            yaw,
            pitch: 0.0,
            fov_x: 90.0,
        }
    }

    #[test]
    fn textured_quad_fills_center() {
        let mut m = quad(0.0, [255; 4]);
        m.texture = Some("t".into());
        m.shader = "atlas".into();
        let mut tex = HashMap::new();
        tex.insert(
            "t".to_string(),
            RgbaImage::from_pixel(2, 2, Rgba([200, 20, 30, 255])),
        );
        let img = render(&[m], &tex, cam(-100.0, 0.0), 64, 64);
        assert_eq!(img.get_pixel(32, 32).0, [200, 20, 30, 255]);
    }

    #[test]
    fn back_face_is_culled() {
        let img = render(
            &[quad(0.0, [255; 4])],
            &HashMap::new(),
            cam(100.0, 180.0),
            64,
            64,
        );
        assert_eq!(img.get_pixel(32, 32).0, [0, 0, 0, 255]);
    }

    #[test]
    fn depth_wins_over_draw_order() {
        let near = quad(-50.0, [0, 255, 0, 255]);
        let far = quad(0.0, [255, 0, 0, 255]);
        let img = render(&[near, far], &HashMap::new(), cam(-100.0, 0.0), 64, 64);
        assert_eq!(img.get_pixel(32, 32).0, [0, 255, 0, 255]);
    }

    #[test]
    fn near_plane_clip_does_not_panic() {
        let m = Mesh {
            positions: vec![[-200.0, -50.0, 0.0], [200.0, -50.0, 0.0], [0.0, 50.0, 0.0]],
            colors: vec![[255; 4]; 3],
            uvs: vec![[0.0; 2]; 3],
            indices: vec![0, 1, 2],
            class: ShaderClass::Sky,
            ..Default::default()
        };
        let _ = render(&[m], &HashMap::new(), cam(0.0, 90.0), 32, 32);
    }

    #[test]
    fn top_view_of_floor_is_not_black() {
        let m = Mesh {
            positions: vec![
                [0.0, 0.0, 0.0],
                [0.0, 100.0, 0.0],
                [100.0, 100.0, 0.0],
                [100.0, 0.0, 0.0],
            ],
            colors: vec![[255; 4]; 4],
            uvs: vec![[0.0; 2]; 4],
            indices: vec![0, 1, 2, 0, 2, 3],
            ..Default::default()
        };
        let img = render_top(&[m], &HashMap::new(), 32, 32);
        assert_ne!(img.get_pixel(16, 16).0, [0, 0, 0, 255]);
    }
}
