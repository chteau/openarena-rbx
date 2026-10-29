//! Reshapes player MD3s (`oaconv tone`): flattens the regions listed in
//! `assets/toned-models.json` towards a smooth surface fitted around them,
//! the same way in every frame, and writes the result into the overlay,
//! then edits the skins to match (`textures`).
//!
//! A region is an ellipsoid in the part's own space, picked on a reference
//! frame (the idle pose). Around it, a ring of vertices facing along the
//! region's axis gets a quadratic height field; inside, each vertex's height
//! over that field is smoothed and scaled down, fading to nothing at the
//! ellipsoid's edge so there is no seam. Each frame then moves a vertex by
//! that same offset, turned by the best-fit rotation of its neighbourhood
//! between the reference frame and that frame, so bent poses keep the shape.

pub mod math;
mod paint;
mod run;
mod shape;
mod textures;
mod view;

pub use run::{generate, run, CONFIG};

use std::collections::BTreeMap;

use serde::Deserialize;

use crate::md3::{self, Md3, XYZ_SCALE};
use math::{add, encode_normal, normalize, sub, V3};

/// `assets/toned-models.json`.
#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    /// Model -> part (`upper`, `lower`, `head`) -> edits.
    pub models: BTreeMap<String, BTreeMap<String, PartCfg>>,
    #[serde(default)]
    pub textures: textures::TextureCfg,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PartCfg {
    /// Animation (as named in `animation.cfg` order, e.g. `LEGS_IDLE`) whose
    /// first frame the regions are picked on.
    pub reference: String,
    pub regions: Vec<Region>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Region {
    /// What this region is for, kept in the config for readers.
    #[serde(default)]
    pub note: String,
    pub center: V3,
    /// Ellipsoid half-sizes along x, y, z.
    pub radius: V3,
    /// Direction the shape sticks out along (forward for a chest).
    pub axis: V3,
    /// Fraction of the height over the fitted surface that stays.
    pub keep: f32,
    /// Neighbour-averaging passes over that height, which rounds off tips.
    #[serde(default)]
    pub smooth: u32,
    /// Fraction of the ellipsoid (by normalised distance) at full strength.
    #[serde(default = "default_core")]
    pub core: f32,
    /// The fit ring reaches out to this normalised distance.
    #[serde(default = "default_ring")]
    pub ring: f32,
    /// Only these surfaces (lowercase); all when empty.
    #[serde(default)]
    pub surfaces: Vec<String>,
}

fn default_core() -> f32 {
    0.45
}

fn default_ring() -> f32 {
    1.5
}

/// `animation.cfg` row names, in file order (`animNumber_t`).
pub const ANIMS: [&str; 25] = [
    "BOTH_DEATH1",
    "BOTH_DEAD1",
    "BOTH_DEATH2",
    "BOTH_DEAD2",
    "BOTH_DEATH3",
    "BOTH_DEAD3",
    "TORSO_GESTURE",
    "TORSO_ATTACK",
    "TORSO_ATTACK2",
    "TORSO_DROP",
    "TORSO_RAISE",
    "TORSO_STAND",
    "TORSO_STAND2",
    "LEGS_WALKCR",
    "LEGS_WALK",
    "LEGS_RUN",
    "LEGS_BACK",
    "LEGS_SWIM",
    "LEGS_JUMP",
    "LEGS_LAND",
    "LEGS_JUMPB",
    "LEGS_LANDB",
    "LEGS_IDLE",
    "LEGS_IDLECR",
    "LEGS_TURN",
];

/// The md3 frame an animation starts on, for `part`'s file: leg frames are
/// numbered after the torso ones in `animation.cfg`, and `lower.md3` skips
/// those (`CG_ParseAnimationFile`).
pub fn anim_frame(cfg: &md3::AnimationCfg, anim: &str, lower: bool) -> Result<usize, String> {
    let row = |name: &str| {
        let i = ANIMS
            .iter()
            .position(|a| *a == name)
            .ok_or(format!("unknown animation {name}"))?;
        cfg.animations
            .get(i)
            .ok_or(format!("animation.cfg has no {name}"))
    };
    let first = row(anim)?[0];
    let skip = if lower && anim.starts_with("LEGS_") {
        row("LEGS_WALKCR")?[0] - row("TORSO_GESTURE")?[0]
    } else {
        0
    };
    usize::try_from(first - skip).map_err(|_| format!("{anim}: negative frame"))
}

/// Reference-frame offsets the regions give each vertex of one model.
#[derive(Clone)]
pub struct Field {
    points: Vec<V3>,
    offsets: Vec<V3>,
    strength: Vec<f32>,
}

/// LOD vertices take the offsets of the full model's vertices within this
/// distance (inverse-distance weighted), so every LOD gets the same shape.
const LOD_REACH: f32 = 2.0;

/// The offsets `regions` give `model`'s vertices on frame `reference`.
pub fn field(model: &Md3, reference: usize, regions: &[Region]) -> Field {
    let mesh = shape::Topology::new(model, reference);
    let mut offsets = vec![[0.0f32; 3]; mesh.groups.len()];
    let mut strength = vec![0.0f32; mesh.groups.len()];
    for region in regions {
        for (g, d, w) in mesh.flatten(region) {
            offsets[g] = add(offsets[g], d);
            strength[g] = strength[g].max(w);
        }
    }
    Field {
        points: mesh.reference.clone(),
        offsets,
        strength,
    }
}

impl Field {
    /// The offset and strength at `p`: exact for the model the field came
    /// from, blended from the nearest points for a LOD.
    fn at(&self, p: V3) -> (V3, f32) {
        let (mut sum, mut s, mut total) = ([0.0; 3], 0.0, 0.0);
        for ((q, o), w) in self.points.iter().zip(&self.offsets).zip(&self.strength) {
            let d = sub(*q, p);
            let d2 = math::dot(d, d);
            if d2 < 1e-6 {
                return (*o, *w);
            }
            if d2 < LOD_REACH * LOD_REACH {
                let k = 1.0 / d2;
                sum = add(sum, math::scale(*o, k));
                s += w * k;
                total += k;
            }
        }
        if total == 0.0 {
            return ([0.0; 3], 0.0);
        }
        (math::scale(sum, 1.0 / total), s / total)
    }
}

/// Moves `model`'s vertices by `field` in every frame. Returns the edited
/// model and the number of vertices moved.
pub fn apply(model: &Md3, reference: usize, field: &Field) -> (Md3, usize) {
    let mesh = shape::Topology::new(model, reference);
    let (offsets, strength): (Vec<V3>, Vec<f32>) =
        mesh.reference.iter().map(|&p| field.at(p)).unzip();
    let moved: Vec<usize> = (0..offsets.len())
        .filter(|&g| math::dot(offsets[g], offsets[g]) > 1e-8)
        .collect();
    let near: Vec<Vec<usize>> = moved.iter().map(|&g| mesh.nearest(g)).collect();
    let mut out = model.clone();
    for f in 0..model.frames.len() {
        let old: Vec<V3> = mesh.positions(model, f);
        let mut new = old.clone();
        for (&g, near) in moved.iter().zip(&near) {
            let rot = mesh.rotation(&old, near);
            new[g] = add(old[g], math::mul(&rot, offsets[g]));
        }
        let affected = mesh.with_neighbours(&moved);
        let n_old = mesh.normals(&old, &affected);
        let n_new = mesh.normals(&new, &affected);
        for (&g, (a, b)) in affected.iter().zip(n_old.iter().zip(&n_new)) {
            let delta = sub(*b, *a);
            for &(s, v) in &mesh.groups[g] {
                let surf = &mut out.surfaces[s];
                let stored = md3::decode_normal(surf.normals[f][v]);
                let kept = normalize(add(stored, delta));
                let n = normalize(add(
                    math::scale(kept, 1.0 - strength[g]),
                    math::scale(*b, strength[g]),
                ));
                surf.normals[f][v] = encode_normal(n);
                surf.xyz[f][v] = new[g].map(|c| (c / XYZ_SCALE).round() as i16);
            }
        }
    }
    (out, moved.iter().map(|&g| mesh.groups[g].len()).sum())
}

/// `original` with every surface's positions and normals replaced by
/// `edited`'s; headers, frames, tags, UVs and names stay byte for byte.
pub fn patch(original: &[u8], edited: &Md3) -> Result<Vec<u8>, String> {
    let mut out = original.to_vec();
    let i32_at = |b: &[u8], o: usize| -> Result<usize, String> {
        let s = b.get(o..o + 4).ok_or("truncated md3")?;
        usize::try_from(i32::from_le_bytes([s[0], s[1], s[2], s[3]]))
            .map_err(|_| "bad offset".into())
    };
    let mut at = i32_at(original, 100)?;
    for s in &edited.surfaces {
        let verts = i32_at(original, at + 80)?;
        let xyz = at + i32_at(original, at + 100)?;
        if verts != s.st.len() {
            return Err(format!("surface {}: vertex count differs", s.name));
        }
        for (f, (pos, nrm)) in s.xyz.iter().zip(&s.normals).enumerate() {
            for (v, (p, n)) in pos.iter().zip(nrm).enumerate() {
                let o = xyz + (f * verts + v) * 8;
                let dst = out.get_mut(o..o + 8).ok_or("truncated md3")?;
                for (k, c) in p.iter().enumerate() {
                    dst[k * 2..k * 2 + 2].copy_from_slice(&c.to_le_bytes());
                }
                dst[6..8].copy_from_slice(&n.to_le_bytes());
            }
        }
        at += i32_at(original, at + 104)?;
    }
    Ok(out)
}

#[cfg(test)]
mod tests;
