//! Fills one chart's rectangle: every texel takes the closest point of the
//! closest triangle (distance 0 inside), so the padding ring continues the
//! surface's own colours and bilinear filtering never reads a neighbour.

use super::chart::Tri;
use super::shade::{Program, Tex, Texel};

struct Prepared {
    p: [[f32; 2]; 3],
    /// Inverse of the 2x2 edge matrix: texel offset -> (l1, l2).
    inv: [f32; 4],
}

impl Prepared {
    fn new(p: [[f32; 2]; 3]) -> Option<Self> {
        let (e1, e2) = (
            [p[1][0] - p[0][0], p[1][1] - p[0][1]],
            [p[2][0] - p[0][0], p[2][1] - p[0][1]],
        );
        let det = e1[0] * e2[1] - e2[0] * e1[1];
        if det.abs() < 1e-9 {
            return None;
        }
        Some(Self {
            p,
            inv: [e2[1] / det, -e2[0] / det, -e1[1] / det, e1[0] / det],
        })
    }

    fn bary(&self, q: [f32; 2]) -> [f32; 3] {
        let d = [q[0] - self.p[0][0], q[1] - self.p[0][1]];
        let l1 = self.inv[0] * d[0] + self.inv[1] * d[1];
        let l2 = self.inv[2] * d[0] + self.inv[3] * d[1];
        [1.0 - l1 - l2, l1, l2]
    }

    /// Closest point of the triangle to `q` and its squared distance.
    fn closest(&self, q: [f32; 2]) -> ([f32; 2], f32) {
        let b = self.bary(q);
        if b.iter().all(|&v| v >= 0.0) {
            return (q, 0.0);
        }
        let mut best = (q, f32::MAX);
        for k in 0..3 {
            let (a, c) = (self.p[k], self.p[(k + 1) % 3]);
            let e = [c[0] - a[0], c[1] - a[1]];
            let len2 = e[0] * e[0] + e[1] * e[1];
            let t = if len2 > 0.0 {
                (((q[0] - a[0]) * e[0] + (q[1] - a[1]) * e[1]) / len2).clamp(0.0, 1.0)
            } else {
                0.0
            };
            let s = [a[0] + e[0] * t, a[1] + e[1] * t];
            let d2 = (q[0] - s[0]).powi(2) + (q[1] - s[1]).powi(2);
            if d2 < best.1 {
                best = (s, d2);
            }
        }
        best
    }
}

/// d(attr)/d(texel x, y) for an attribute with values `a` at the corners.
fn gradient<const N: usize>(t: &Prepared, a: [[f32; N]; 3]) -> [[f32; N]; 2] {
    // attr(q) = a0 + (a1-a0) l1 + (a2-a0) l2, with l = inv * (q - p0)
    let d1: [f32; N] = std::array::from_fn(|i| a[1][i] - a[0][i]);
    let d2: [f32; N] = std::array::from_fn(|i| a[2][i] - a[0][i]);
    [
        std::array::from_fn(|i| d1[i] * t.inv[0] + d2[i] * t.inv[2]),
        std::array::from_fn(|i| d1[i] * t.inv[1] + d2[i] * t.inv[3]),
    ]
}

/// Texel space of a chart: `(uv - min) * density + pad`.
pub struct Frame {
    pub min: [f32; 2],
    pub density: f32,
    pub pad: f32,
    pub w: u32,
    pub h: u32,
}

impl Frame {
    pub fn to_texel(&self, uv: [f32; 2]) -> [f32; 2] {
        [
            (uv[0] - self.min[0]) * self.density + self.pad,
            (uv[1] - self.min[1]) * self.density + self.pad,
        ]
    }
}

/// RGB per texel of the chart rectangle, row-major `w * h`.
pub fn raster(tris: &[Tri], frame: &Frame, prog: &Program, lightmap: Option<&Tex>) -> Vec<[u8; 3]> {
    let (w, h) = (frame.w as usize, frame.h as usize);
    let reach = frame.pad + 1.5;
    let mut best = vec![(f32::MAX, usize::MAX, [0.0f32; 2]); w * h];
    let prepared: Vec<Option<Prepared>> = tris
        .iter()
        .map(|t| Prepared::new(t.map(|v| frame.to_texel(v.uv))))
        .collect();
    for (ti, prep) in prepared.iter().enumerate() {
        let Some(prep) = prep else { continue };
        let lo = |k: usize| {
            (prep.p.iter().map(|p| p[k]).fold(f32::MAX, f32::min) - reach)
                .floor()
                .max(0.0) as usize
        };
        let hi = |k: usize, n: usize| {
            ((prep.p.iter().map(|p| p[k]).fold(f32::MIN, f32::max) + reach)
                .ceil()
                .max(0.0) as usize)
                .min(n)
        };
        for y in lo(1)..hi(1, h) {
            for x in lo(0)..hi(0, w) {
                let q = [x as f32 + 0.5, y as f32 + 0.5];
                let (point, d2) = prep.closest(q);
                let slot = &mut best[y * w + x];
                if d2 < slot.0 && d2 <= reach * reach {
                    *slot = (d2, ti, point);
                }
            }
        }
    }
    let grads: Vec<Option<_>> = prepared
        .iter()
        .zip(tris)
        .map(|(p, t)| {
            p.as_ref().map(|p| {
                (
                    gradient(p, t.map(|v| v.st)),
                    gradient(p, t.map(|v| v.lm)),
                    gradient(p, t.map(|v| v.pos)),
                )
            })
        })
        .collect();
    best.iter()
        .map(|&(_, ti, point)| {
            if ti == usize::MAX {
                return [0, 0, 0];
            }
            let (Some(prep), Some((dst, dlm, dpos))) = (&prepared[ti], &grads[ti]) else {
                return [0, 0, 0];
            };
            let b = prep.bary(point);
            let t = &tris[ti];
            fn mix<const N: usize>(b: [f32; 3], a: [[f32; N]; 3]) -> [f32; N] {
                std::array::from_fn(|i| a[0][i] * b[0] + a[1][i] * b[1] + a[2][i] * b[2])
            }
            let texel = Texel {
                pos: mix(b, t.map(|v| v.pos)),
                st: mix(b, t.map(|v| v.st)),
                lm: mix(b, t.map(|v| v.lm)),
                color: mix(b, t.map(|v| v.color)),
                dst: *dst,
                dlm: *dlm,
                dpos: *dpos,
            };
            prog.shade(&texel, lightmap)
        })
        .collect()
}
