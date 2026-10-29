//! Texture side of the reshaping: where the flattened regions land in each
//! skin image, and the smoothing that takes painted detail (nipples, the
//! shading that drew the old shape) out of them.

use image::RgbaImage;

use super::Field;
use crate::md3::Md3;

/// Per texel of a `w` x `h` image, the strongest region weight among the
/// triangles of `surfaces` that cover it (0 where none does), plus whether
/// any of those surfaces covers the texel at all.
pub fn coverage(
    model: &Md3,
    reference: usize,
    field: &Field,
    surfaces: &[String],
    w: u32,
    h: u32,
) -> (Vec<f32>, Vec<bool>) {
    let mut weight = vec![0.0f32; (w * h) as usize];
    let mut covered = vec![false; (w * h) as usize];
    for s in model.surfaces.iter().filter(|s| surfaces.contains(&s.name)) {
        let strength: Vec<f32> = s.xyz[reference]
            .iter()
            .map(|p| field.at(p.map(|c| c as f32 * crate::md3::XYZ_SCALE)).1)
            .collect();
        for t in &s.triangles {
            let [a, b, c] = t.map(|i| i as usize);
            let uv = [a, b, c].map(|i| [s.st[i][0] * w as f32, s.st[i][1] * h as f32]);
            let ws = [strength[a], strength[b], strength[c]];
            raster(uv, w, h, |x, y, l| {
                let i = (y * w + x) as usize;
                covered[i] = true;
                weight[i] = weight[i].max(l[0] * ws[0] + l[1] * ws[1] + l[2] * ws[2]);
            });
        }
    }
    (weight, covered)
}

/// Calls `f(x, y, barycentrics)` for texel centres inside the UV triangle,
/// grown by a texel so islands keep their edges under bilinear filtering.
fn raster(p: [[f32; 2]; 3], w: u32, h: u32, mut f: impl FnMut(u32, u32, [f32; 3])) {
    let area =
        (p[1][0] - p[0][0]) * (p[2][1] - p[0][1]) - (p[2][0] - p[0][0]) * (p[1][1] - p[0][1]);
    if area.abs() < 1e-6 {
        return;
    }
    let lo = |k: usize| p.iter().map(|q| q[k]).fold(f32::MAX, f32::min).floor() - 1.0;
    let hi = |k: usize| p.iter().map(|q| q[k]).fold(f32::MIN, f32::max).ceil() + 1.0;
    let edge = 1.0 / area.abs().sqrt().max(1.0);
    for y in lo(1).max(0.0) as u32..(hi(1).max(0.0) as u32).min(h) {
        for x in lo(0).max(0.0) as u32..(hi(0).max(0.0) as u32).min(w) {
            let (px, py) = (x as f32 + 0.5, y as f32 + 0.5);
            let l0 = ((p[1][0] - px) * (p[2][1] - py) - (p[2][0] - px) * (p[1][1] - py)) / area;
            let l1 = ((p[2][0] - px) * (p[0][1] - py) - (p[0][0] - px) * (p[2][1] - py)) / area;
            let l2 = 1.0 - l0 - l1;
            if l0 >= -edge && l1 >= -edge && l2 >= -edge {
                f(x, y, [l0.max(0.0), l1.max(0.0), l2.max(0.0)]);
            }
        }
    }
}

/// Blurs `img` where `weight` > 0, mixing by weight: a box blur of `radius`
/// texels (three passes, close to a Gaussian) that only averages texels
/// `covered` by the model, so nothing bleeds in from neighbouring islands.
pub fn smooth(img: &RgbaImage, weight: &[f32], covered: &[bool], radius: u32) -> RgbaImage {
    let (w, h) = img.dimensions();
    let mut acc: Vec<[f32; 4]> = img
        .pixels()
        .zip(covered)
        .map(|(p, &c)| {
            if c {
                [p[0] as f32, p[1] as f32, p[2] as f32, 1.0]
            } else {
                [0.0; 4]
            }
        })
        .collect();
    for _ in 0..3 {
        acc = box_pass(&acc, w, h, radius, true);
        acc = box_pass(&acc, w, h, radius, false);
    }
    let mut out = img.clone();
    for (i, px) in out.pixels_mut().enumerate() {
        let k = weight[i].clamp(0.0, 1.0);
        if k <= 0.0 || acc[i][3] <= 1e-4 {
            continue;
        }
        for c in 0..3 {
            let blurred = acc[i][c] / acc[i][3];
            px[c] = (px[c] as f32 * (1.0 - k) + blurred * k)
                .round()
                .clamp(0.0, 255.0) as u8;
        }
    }
    out
}

fn box_pass(src: &[[f32; 4]], w: u32, h: u32, r: u32, horizontal: bool) -> Vec<[f32; 4]> {
    let (w, h, r) = (w as i64, h as i64, r as i64);
    let mut out = vec![[0.0; 4]; src.len()];
    let (outer, inner) = if horizontal { (h, w) } else { (w, h) };
    let at = |o: i64, i: i64| {
        if horizontal {
            (o * w + i) as usize
        } else {
            (i * w + o) as usize
        }
    };
    for o in 0..outer {
        let mut sum = [0.0f32; 4];
        for i in -r..=r {
            let s = src[at(o, i.clamp(0, inner - 1))];
            for c in 0..4 {
                sum[c] += s[c];
            }
        }
        for i in 0..inner {
            out[at(o, i)] = sum.map(|v| v / (2 * r + 1) as f32);
            let (add, sub) = (
                src[at(o, (i + r + 1).min(inner - 1))],
                src[at(o, (i - r).max(0))],
            );
            for c in 0..4 {
                sum[c] += add[c] - sub[c];
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn smoothing_removes_a_dot_and_keeps_other_islands() {
        let mut img = RgbaImage::from_pixel(32, 32, image::Rgba([100, 100, 100, 255]));
        img.put_pixel(10, 10, image::Rgba([0, 0, 0, 255]));
        img.put_pixel(25, 25, image::Rgba([255, 0, 0, 255]));
        let mut weight = vec![0.0; 32 * 32];
        let mut covered = vec![true; 32 * 32];
        for y in 0..20 {
            for x in 0..20 {
                weight[y * 32 + x] = 1.0;
            }
        }
        covered[25 * 32 + 25] = false;
        let out = smooth(&img, &weight, &covered, 3);
        assert!(out.get_pixel(10, 10)[0] > 95, "{:?}", out.get_pixel(10, 10));
        assert_eq!(out.get_pixel(25, 25), &image::Rgba([255, 0, 0, 255]));
        assert_eq!(out.get_pixel(0, 0)[0], 100);
    }
}
