//! Welded topology of one MD3 and the per-region flattening.

use std::collections::{BTreeMap, BTreeSet};

use super::math::{cross, dot, normalize, scale, sub, M3, V3};
use super::Region;
use crate::md3::{self, Md3, XYZ_SCALE};

/// Neighbours (by reference-frame distance) whose motion turns an offset.
const ROTATION_NEIGHBOURS: usize = 10;

/// Ring vertices must face this much along the axis.
const RING_FACING: f32 = 0.5;

/// Units behind the fitted surface past which a vertex is left alone.
const BEHIND: f32 = 2.5;

pub(super) struct Topology {
    /// Vertices (surface, index) that sit together in every frame.
    pub groups: Vec<Vec<(usize, usize)>>,
    /// Each group's position on the reference frame.
    pub reference: Vec<V3>,
    /// Stored normal of each group's first vertex, reference frame.
    facing: Vec<V3>,
    adjacent: Vec<BTreeSet<usize>>,
    triangles: Vec<[usize; 3]>,
    /// +1 when `cross(b - a, c - a)` points out of the surface, else -1.
    winding: f32,
    surfaces: Vec<String>,
}

fn pos(p: [i16; 3]) -> V3 {
    p.map(|c| c as f32 * XYZ_SCALE)
}

impl Topology {
    pub fn new(model: &Md3, reference: usize) -> Self {
        let mut by_track: BTreeMap<Vec<[i16; 3]>, usize> = BTreeMap::new();
        let mut groups: Vec<Vec<(usize, usize)>> = Vec::new();
        let mut of = Vec::new();
        for (s, surf) in model.surfaces.iter().enumerate() {
            let mut ids = Vec::with_capacity(surf.st.len());
            for v in 0..surf.st.len() {
                let track: Vec<[i16; 3]> = surf.xyz.iter().map(|f| f[v]).collect();
                let g = *by_track.entry(track).or_insert_with(|| {
                    groups.push(Vec::new());
                    groups.len() - 1
                });
                groups[g].push((s, v));
                ids.push(g);
            }
            of.push(ids);
        }
        let mut adjacent = vec![BTreeSet::new(); groups.len()];
        let mut triangles = Vec::new();
        for (s, surf) in model.surfaces.iter().enumerate() {
            for t in &surf.triangles {
                let g = t.map(|i| of[s][i as usize]);
                for k in 0..3 {
                    let (a, b) = (g[k], g[(k + 1) % 3]);
                    if a != b {
                        adjacent[a].insert(b);
                        adjacent[b].insert(a);
                    }
                }
                triangles.push(g);
            }
        }
        let first = |g: &Vec<(usize, usize)>| g[0];
        let frame = reference;
        let reference: Vec<V3> = groups
            .iter()
            .map(|g| {
                let (s, v) = first(g);
                pos(model.surfaces[s].xyz[reference][v])
            })
            .collect();
        let facing: Vec<V3> = groups
            .iter()
            .map(|g| {
                let (s, v) = first(g);
                md3::decode_normal(model.surfaces[s].normals[frame][v])
            })
            .collect();
        let mut agree = 0.0;
        for t in &triangles {
            let [a, b, c] = t.map(|g| reference[g]);
            agree += dot(cross(sub(b, a), sub(c, a)), facing[t[0]]);
        }
        let surfaces = groups
            .iter()
            .map(|g| model.surfaces[first(g).0].name.clone())
            .collect();
        Self {
            groups,
            reference,
            facing,
            adjacent,
            triangles,
            winding: if agree < 0.0 { -1.0 } else { 1.0 },
            surfaces,
        }
    }

    /// Each group's position in frame `f`.
    pub fn positions(&self, model: &Md3, f: usize) -> Vec<V3> {
        self.groups
            .iter()
            .map(|g| pos(model.surfaces[g[0].0].xyz[f][g[0].1]))
            .collect()
    }

    /// `(group, offset, strength)` for every group the region moves, in the
    /// reference frame.
    pub fn flatten(&self, region: &Region) -> Vec<(usize, V3, f32)> {
        let axis = normalize(region.axis);
        let helper = if axis[2].abs() < 0.9 {
            [0.0, 0.0, 1.0]
        } else {
            [1.0, 0.0, 0.0]
        };
        let u = normalize(cross(helper, axis));
        let v = cross(axis, u);
        let surface_ok = |g: usize| {
            region.surfaces.is_empty() || region.surfaces.iter().any(|s| *s == self.surfaces[g])
        };
        let mut zone = BTreeMap::new();
        let mut ring = Vec::new();
        for g in 0..self.groups.len() {
            let q = sub(self.reference[g], region.center);
            let n = [0, 1, 2].map(|k| q[k] / region.radius[k]);
            let d = dot(n, n).sqrt();
            if d >= region.ring || !surface_ok(g) {
                continue;
            }
            let facing = dot(self.facing[g], axis);
            let local = [dot(q, u), dot(q, v), dot(q, axis)];
            // Above and below only: beside the shape the body curves away.
            if d >= 1.0 && facing > RING_FACING && n[1].abs() < 0.8 {
                ring.push(local);
            }
            zone.insert(g, (local, d));
        }
        let Some(fit) = fit_height(&ring) else {
            return Vec::new();
        };
        // Far behind the fitted surface is the other side of the body (or an
        // arm), not part of the shape being flattened.
        zone.retain(|_, (l, _)| l[2] - fit(l[0], l[1]) > -BEHIND);
        let mut residual: BTreeMap<usize, f32> = zone
            .iter()
            .map(|(&g, (l, _))| (g, l[2] - fit(l[0], l[1])))
            .collect();
        if std::env::var_os("OACONV_TONE_PROBE").is_some() {
            let inside = zone.values().filter(|(_, d)| *d < 1.0).count();
            let peak = zone
                .iter()
                .filter(|(_, (_, d))| *d < 1.0)
                .max_by(|a, b| residual[a.0].total_cmp(&residual[b.0]));
            let at = peak.map(|(&g, _)| (self.reference[g], residual[&g]));
            eprintln!(
                "  {}: {inside} inside, {} ring, peak {at:?}",
                region.note,
                ring.len()
            );
        }
        for _ in 0..region.smooth {
            let prev = residual.clone();
            for (&g, &(_, d)) in &zone {
                if d >= 1.0 {
                    continue;
                }
                let near: Vec<f32> = self.adjacent[g]
                    .iter()
                    .filter_map(|n| prev.get(n).copied())
                    .collect();
                if !near.is_empty() {
                    let mean = near.iter().sum::<f32>() / near.len() as f32;
                    residual.insert(g, 0.5 * prev[&g] + 0.5 * mean);
                }
            }
        }
        zone.iter()
            .filter(|(_, (_, d))| *d < 1.0)
            .map(|(&g, (l, d))| {
                let t = ((1.0 - d) / (1.0 - region.core)).clamp(0.0, 1.0);
                let w = t * t * (3.0 - 2.0 * t);
                let target = fit(l[0], l[1]) + region.keep * residual[&g].max(0.0);
                (g, scale(axis, w * (target - l[2]).min(0.0)), w)
            })
            .collect()
    }

    /// Best-fit rotation of `g`'s neighbourhood from the reference frame to `now`.
    pub fn rotation(&self, now: &[V3], near: &[usize]) -> M3 {
        let from: Vec<V3> = near.iter().map(|&n| self.reference[n]).collect();
        let to: Vec<V3> = near.iter().map(|&n| now[n]).collect();
        super::math::best_rotation(&from, &to, &vec![1.0; near.len()])
    }

    /// The groups nearest `g` in the reference frame, `g` included.
    pub fn nearest(&self, g: usize) -> Vec<usize> {
        let mut all: Vec<(f32, usize)> = (0..self.reference.len())
            .map(|n| {
                let d = sub(self.reference[n], self.reference[g]);
                (dot(d, d), n)
            })
            .collect();
        all.sort_by(|a, b| a.0.total_cmp(&b.0));
        all.into_iter()
            .take(ROTATION_NEIGHBOURS)
            .map(|(_, n)| n)
            .collect()
    }

    /// `groups` plus everything sharing an edge with them, sorted.
    pub fn with_neighbours(&self, groups: &[usize]) -> Vec<usize> {
        let mut out: BTreeSet<usize> = groups.iter().copied().collect();
        for &g in groups {
            out.extend(self.adjacent[g].iter().copied());
        }
        out.into_iter().collect()
    }

    /// Area-weighted vertex normals of `groups` at `positions`.
    pub fn normals(&self, positions: &[V3], groups: &[usize]) -> Vec<V3> {
        let want: BTreeMap<usize, usize> =
            groups.iter().enumerate().map(|(i, &g)| (g, i)).collect();
        let mut out = vec![[0.0; 3]; groups.len()];
        for t in &self.triangles {
            if !t.iter().any(|g| want.contains_key(g)) {
                continue;
            }
            let [a, b, c] = t.map(|g| positions[g]);
            let n = scale(cross(sub(b, a), sub(c, a)), self.winding);
            for g in t {
                if let Some(&i) = want.get(g) {
                    out[i] = super::math::add(out[i], n);
                }
            }
        }
        out.into_iter().map(normalize).collect()
    }
}

/// Least-squares `h(u, v)`: a plane, curved along `v` (up the body, for a
/// chest) when the ring is big enough. No curvature across: the body's
/// sides would bend it down, and only what sticks out over it moves.
fn fit_height(ring: &[V3]) -> Option<impl Fn(f32, f32) -> f32> {
    let quad = ring.len() >= 8;
    let terms = move |u: f32, v: f32| -> [f64; 6] {
        let (u, v) = (u as f64, v as f64);
        if quad {
            [1.0, u, v, v * v, 0.0, 0.0]
        } else {
            [1.0, u, v, 0.0, 0.0, 0.0]
        }
    };
    if ring.len() < 3 {
        return None;
    }
    let mut a = [[0.0f64; 7]; 6];
    for p in ring {
        let t = terms(p[0], p[1]);
        for i in 0..6 {
            for j in 0..6 {
                a[i][j] += t[i] * t[j];
            }
            a[i][6] += t[i] * p[2] as f64;
        }
    }
    // A little ridge keeps the unused (or badly constrained) terms at zero.
    for (i, row) in a.iter_mut().enumerate() {
        row[i] += 1e-6;
    }
    let c = solve6(a)?;
    Some(move |u: f32, v: f32| {
        let t = terms(u, v);
        (0..6).map(|i| c[i] * t[i]).sum::<f64>() as f32
    })
}

/// Gauss-Jordan with partial pivoting on an augmented 6x7 system.
#[allow(clippy::needless_range_loop)] // textbook matrix indexing
fn solve6(mut a: [[f64; 7]; 6]) -> Option<[f64; 6]> {
    for col in 0..6 {
        let pivot = (col..6).max_by(|&x, &y| a[x][col].abs().total_cmp(&a[y][col].abs()))?;
        if a[pivot][col].abs() < 1e-12 {
            return None;
        }
        a.swap(col, pivot);
        for row in 0..6 {
            if row != col {
                let k = a[row][col] / a[col][col];
                for j in col..7 {
                    a[row][j] -= k * a[col][j];
                }
            }
        }
    }
    Some([0, 1, 2, 3, 4, 5].map(|i| a[i][6] / a[i][i]))
}
