//! Before/after sheets of a whole player (lower + upper + head on their
//! tags), clay-shaded and textured, with the preview rasterizer.

use std::collections::HashMap;

use image::{imageops, RgbaImage};

use super::math::{add, dot, normalize, scale, V3};
use crate::md3::{self, Md3};
use crate::mesh::Mesh;
use crate::preview::{render, Camera};
use crate::vfs::Vfs;

/// One player model: its three parts (upper/head may be missing) and skin.
pub struct Player {
    pub lower: Md3,
    pub upper: Option<Md3>,
    pub head: Option<Md3>,
    pub cfg: md3::AnimationCfg,
}

/// One cell of a sheet, framing the torso and hips.
const W: u32 = 220;
const H: u32 = 300;

/// Animation pairs (legs, torso) and a frame offset into each, per row.
const POSES: [(&str, &str, usize); 4] = [
    ("LEGS_IDLE", "TORSO_STAND", 0),
    ("LEGS_RUN", "TORSO_STAND", 3),
    ("LEGS_JUMP", "TORSO_STAND", 3),
    ("LEGS_IDLE", "TORSO_ATTACK", 2),
];

struct Place {
    origin: V3,
    axis: [V3; 3],
}

impl Place {
    fn apply(&self, p: V3) -> V3 {
        (0..3).fold(self.origin, |o, k| add(o, scale(self.axis[k], p[k])))
    }
    fn turn(&self, n: V3) -> V3 {
        (0..3).fold([0.0; 3], |o, k| add(o, scale(self.axis[k], n[k])))
    }
    /// `CG_PositionRotatedEntityOnTag`; `R_LerpTag` normalises the axes, which
    /// some models store scaled.
    fn child(&self, tag: &md3::Md3Tag) -> Place {
        Place {
            origin: (0..3).fold(self.origin, |o, i| {
                add(o, scale(self.axis[i], tag.origin[i]))
            }),
            axis: tag.axis.map(|row| self.turn(normalize(row))),
        }
    }
}

fn tag<'a>(m: &'a Md3, frame: usize, name: &str) -> Option<&'a md3::Md3Tag> {
    m.tags
        .get(frame.min(m.frames.len().saturating_sub(1)))?
        .iter()
        .find(|t| t.name == name)
}

fn part_meshes(
    m: &Md3,
    frame: usize,
    at: &Place,
    skin: &HashMap<String, String>,
    out: &mut Vec<Mesh>,
) {
    let frame = frame.min(m.frames.len().saturating_sub(1));
    for mut mesh in md3::static_meshes(m, frame, "p") {
        let surf = mesh.name.trim_start_matches("p_").to_string();
        if skin.get(&surf).is_some_and(|s| s == "null") {
            continue;
        }
        mesh.positions = mesh.positions.iter().map(|&p| at.apply(p)).collect();
        mesh.normals = mesh.normals.iter().map(|&n| at.turn(n)).collect();
        mesh.texture = skin.get(&surf).cloned();
        out.push(mesh);
    }
}

impl Player {
    /// Every part's meshes for `pose`, in world space.
    fn meshes(&self, pose: usize, skin: &HashMap<String, String>) -> Vec<Mesh> {
        let (legs, torso, step) = POSES[pose];
        let frame = |anim: &str, lower: bool| {
            super::anim_frame(&self.cfg, anim, lower).map_or(0, |f| f + step)
        };
        let lf = frame(legs, true);
        let uf = frame(torso, false);
        let root = Place {
            origin: [0.0; 3],
            axis: [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]],
        };
        let mut out = Vec::new();
        part_meshes(&self.lower, lf, &root, skin, &mut out);
        if let (Some(upper), Some(t)) = (&self.upper, tag(&self.lower, lf, "tag_torso")) {
            let torso = root.child(t);
            part_meshes(upper, uf, &torso, skin, &mut out);
            if let (Some(head), Some(t)) = (&self.head, tag(upper, uf, "tag_head")) {
                part_meshes(head, 0, &torso.child(t), skin, &mut out);
            }
        }
        out
    }
}

/// `surface -> image path` from the model's `<part>_<skin>.skin` files, with
/// every image decoded into `textures`.
pub fn load_skin(
    vfs: &Vfs,
    model: &str,
    skin: &str,
    textures: &mut HashMap<String, RgbaImage>,
) -> HashMap<String, String> {
    let mut out = HashMap::new();
    for part in ["lower", "upper", "head"] {
        let Some(text) = vfs.read(&format!("models/players/{model}/{part}_{skin}.skin")) else {
            continue;
        };
        for (surf, shader) in md3::parse_skin(&String::from_utf8_lossy(&text)) {
            let image = vfs.find_image(&shader);
            if let Some(img) = image.as_ref().filter(|i| !textures.contains_key(*i)) {
                if let Some(decoded) = vfs
                    .read(img)
                    .and_then(|b| crate::texture::decode(&b, img).ok())
                {
                    textures.insert(img.clone(), decoded);
                }
            }
            let value = if shader == "null" {
                shader
            } else {
                image.unwrap_or_default()
            };
            out.insert(surf, value);
        }
    }
    out
}

/// `heat`: the same meshes before the edit; moved vertices are tinted red
/// (full red at 2 units).
fn shot(
    meshes: &[Mesh],
    textures: &HashMap<String, RgbaImage>,
    yaw: f32,
    textured: bool,
    heat: Option<&[Mesh]>,
) -> RgbaImage {
    let (w, h) = (W, H);
    let r = yaw.to_radians();
    // From the camera, a little to the side and above, so curvature reads.
    let light = normalize([-r.cos() - 0.4 * r.sin(), -r.sin() + 0.4 * r.cos(), 0.6]);
    let meshes: Vec<Mesh> = meshes
        .iter()
        .cloned()
        .enumerate()
        .map(|(i, mut m)| {
            if !textured {
                m.texture = None;
            }
            m.colors = m
                .normals
                .iter()
                .map(|&n| {
                    let l = (0.25 + 0.75 * dot(n, light).max(0.0)) * 255.0;
                    [l as u8, l as u8, l as u8, 255]
                })
                .collect();
            if let Some(old) = heat.and_then(|h| h.get(i)) {
                for (c, (p, q)) in m
                    .colors
                    .iter_mut()
                    .zip(m.positions.iter().zip(&old.positions))
                {
                    let d = super::math::sub(*p, *q);
                    let k = 1.0 - (dot(d, d).sqrt() / 2.0).min(1.0);
                    c[1] = (c[1] as f32 * k) as u8;
                    c[2] = (c[2] as f32 * k) as u8;
                }
            }
            m
        })
        .collect();
    let fov_y: f32 = 26.0;
    let fov_x = 2.0 * ((w as f32 / h as f32) * (fov_y.to_radians() / 2.0).tan()).atan();
    let dist = 95.0;
    let target = [0.0, 0.0, 14.0];
    let cam = Camera {
        origin: [
            target[0] - r.cos() * dist,
            target[1] - r.sin() * dist,
            target[2],
        ],
        yaw,
        pitch: 0.0,
        fov_x: fov_x.to_degrees(),
    };
    render(&meshes, textures, cam, w, h)
}

/// A grid: one row per pose; columns are before/after pairs seen from the
/// front, the side and the back (clay), then the front textured, then the
/// moved vertices in red, front and back.
pub fn sheet(
    before: &Player,
    after: &Player,
    skin: &HashMap<String, String>,
    textures: &HashMap<String, RgbaImage>,
) -> RgbaImage {
    let views: [(f32, bool); 4] = [(180.0, false), (90.0, false), (0.0, false), (180.0, true)];
    let (w, h) = (W, H);
    let mut out = RgbaImage::new(w * 10, h * POSES.len() as u32);
    for pose in 0..POSES.len() {
        let pair = [before.meshes(pose, skin), after.meshes(pose, skin)];
        for (v, &(yaw, textured)) in views.iter().enumerate() {
            for (k, meshes) in pair.iter().enumerate() {
                let img = shot(meshes, textures, yaw, textured, None);
                let x = (v as u32 * 2 + k as u32) * w;
                imageops::overlay(&mut out, &img, x as i64, (pose as u32 * h) as i64);
            }
        }
        for (k, yaw) in [180.0, 0.0].into_iter().enumerate() {
            let img = shot(&pair[1], textures, yaw, false, Some(&pair[0]));
            imageops::overlay(
                &mut out,
                &img,
                (w * (8 + k as u32)) as i64,
                (pose as u32 * h) as i64,
            );
        }
    }
    out
}
