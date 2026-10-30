//! The texture half of `oaconv tone`: bodysuits painted from an existing
//! toned skin's mask, shirts painted over bare torsos, painted dots (nipples) filled in, and the painted
//! detail inside the flattened regions smoothed away. Each image starts from
//! `assets/toned-src/<path>` when a hand-edited base exists there, else the
//! pk3 original, and is written to the overlay.

use std::collections::{BTreeMap, HashMap};
use std::path::Path;

use image::{Rgba, RgbaImage};
use serde::Deserialize;

use super::math::V3;
use super::paint::{coverage, piece_positions, smooth};
use super::Field;
use crate::md3::{self, Md3};
use crate::vfs::{Vfs, OVERLAY};

/// Hand-edited bases the texture pass starts from, relative to the repo root.
pub const SOURCES: &str = "assets/toned-src";

#[derive(Clone, Debug, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TextureCfg {
    /// Paint a bodysuit where the overlay copy of `mask` differs from its
    /// pk3 original (the same UV layout), shaded like that copy.
    #[serde(default)]
    pub suits: Vec<Suit>,
    /// Paint a shirt over a bare torso, found by 3D position on the model.
    #[serde(default)]
    pub shirts: Vec<Shirt>,
    /// Fill painted dots: per image, `[x, y, radius]` in texels.
    #[serde(default)]
    pub spots: BTreeMap<String, Vec<[f32; 3]>>,
    /// Blur painted detail inside a model's flattened regions.
    #[serde(default)]
    pub smooth: Vec<Smooth>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Suit {
    pub mask: String,
    /// Image -> suit colour (RGB).
    pub images: BTreeMap<String, [u8; 3]>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Shirt {
    pub model: String,
    pub part: String,
    /// Animation whose first frame the positions below are taken on.
    pub reference: String,
    pub surface: String,
    /// The shirt covers the pieces (UV-connected parts) of `surface` that
    /// hold the vertex nearest each of these points.
    pub pieces: Vec<V3>,
    /// Height of the neckline: above it the pieces stay bare.
    pub neckline: f32,
    /// Width (in units) of the soft edge at the neckline.
    pub feather: f32,
    /// Blur radius, in texels of a 512-wide image, of the shading taken
    /// from the original art (each material normalised to its mean).
    pub radius: u32,
    /// Fraction of that shading's contrast kept.
    pub contrast: f32,
    /// Image -> shirt colour (RGB).
    pub images: BTreeMap<String, [u8; 3]>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Smooth {
    pub model: String,
    pub images: Vec<String>,
    /// Blur radius in texels of a 512-wide image.
    pub radius: u32,
    /// The surfaces whose UVs map these images; by default, the surfaces
    /// the model's skins put each image on.
    #[serde(default)]
    pub surfaces: Vec<String>,
}

/// One edited part: its full-detail model, reference frame and offsets.
pub type PartField = (Md3, usize, Field);

struct Images<'a> {
    repo: &'a Path,
    base: &'a Vfs,
    open: BTreeMap<String, RgbaImage>,
}

impl Images<'_> {
    fn get(&mut self, path: &str) -> Result<&mut RgbaImage, String> {
        if !self.open.contains_key(path) {
            let src = self.repo.join(SOURCES).join(path);
            let bytes = match std::fs::read(&src) {
                Ok(b) => b,
                Err(_) => self
                    .base
                    .read(path)
                    .ok_or(format!("{path}: not in any pk3"))?,
            };
            let img = crate::texture::decode(&bytes, path)?;
            self.open.insert(path.to_string(), img);
        }
        Ok(self.open.get_mut(path).expect("inserted above"))
    }
}

fn luma(p: &Rgba<u8>) -> f32 {
    0.299 * p[0] as f32 + 0.587 * p[1] as f32 + 0.114 * p[2] as f32
}

fn paint_suit(repo: &Path, base: &Vfs, suit: &Suit, images: &mut Images) -> Result<(), String> {
    let decode = |bytes: Option<Vec<u8>>, what: &str| {
        crate::texture::decode(&bytes.ok_or(format!("{what}: missing"))?, what)
    };
    let original = decode(base.read(&suit.mask), &suit.mask)?;
    let toned = decode(
        std::fs::read(repo.join(SOURCES).join(&suit.mask))
            .or_else(|_| std::fs::read(repo.join(OVERLAY).join(&suit.mask)))
            .ok(),
        &suit.mask,
    )?;
    let inside: Vec<bool> = original
        .pixels()
        .zip(toned.pixels())
        .map(|(a, b)| (0..3).any(|c| (a[c] as i32 - b[c] as i32).abs() > 8))
        .collect();
    let mean = {
        let l: Vec<f32> = toned
            .pixels()
            .zip(&inside)
            .filter(|(_, &i)| i)
            .map(|(p, _)| luma(p))
            .collect();
        l.iter().sum::<f32>() / l.len().max(1) as f32
    };
    for (path, colour) in &suit.images {
        let img = images.get(path)?;
        if img.dimensions() != toned.dimensions() {
            return Err(format!("{path}: size differs from {}", suit.mask));
        }
        for ((px, shade), &i) in img.pixels_mut().zip(toned.pixels()).zip(&inside) {
            if i {
                let k = luma(shade) / mean.max(1.0);
                for c in 0..3 {
                    px[c] = (colour[c] as f32 * k).round().clamp(0.0, 255.0) as u8;
                }
            }
        }
    }
    Ok(())
}

fn paint_shirt(base: &Vfs, shirt: &Shirt, images: &mut Images) -> Result<(), String> {
    let dir = format!("models/players/{}", shirt.model);
    let read = |p: String| base.read(&p).ok_or(format!("{p}: not in any pk3"));
    let cfg = md3::parse_animation_cfg(&String::from_utf8_lossy(&read(format!(
        "{dir}/animation.cfg"
    ))?))?;
    let model = md3::parse(&read(format!("{dir}/{}.md3", shirt.part))?)?;
    let frame = super::anim_frame(&cfg, &shirt.reference, shirt.part == "lower")?;
    for (path, colour) in &shirt.images {
        let img = images.get(path)?;
        let (w, h) = img.dimensions();
        let at = piece_positions(&model, frame, &shirt.surface, &shirt.pieces, w, h)?;
        let covered: Vec<bool> = at.iter().map(Option::is_some).collect();
        let weight: Vec<f32> = at
            .iter()
            .map(|p| {
                p.map_or(0.0, |p| {
                    ((shirt.neckline - p[2]) / shirt.feather + 0.5).clamp(0.0, 1.0)
                })
            })
            .collect();
        // Shading: luma over each material's mean (grey cloth vs. skin), so
        // the old top's edges don't print through, then blurred flat.
        let grey =
            |p: &Rgba<u8>| p.0[..3].iter().max().unwrap() - p.0[..3].iter().min().unwrap() < 32;
        let mut mean = [(0.0f32, 0u32); 2];
        for (p, _) in img.pixels().zip(&weight).filter(|(_, &k)| k > 0.0) {
            let m = &mut mean[grey(p) as usize];
            m.0 += luma(p);
            m.1 += 1;
        }
        let mean = mean.map(|(sum, n)| sum / n.max(1) as f32);
        let mut shade = img.clone();
        for (s, p) in shade.pixels_mut().zip(img.pixels()) {
            let k = luma(p) / mean[grey(p) as usize].max(1.0) * 128.0;
            *s = Rgba([k.round().clamp(0.0, 255.0) as u8, 0, 0, 255]);
        }
        let shade = smooth(
            &shade,
            &vec![1.0; covered.len()],
            &covered,
            (shirt.radius * w).div_ceil(512),
        );
        for ((px, s), &k) in img.pixels_mut().zip(shade.pixels()).zip(&weight) {
            if k <= 0.0 {
                continue;
            }
            let light = 1.0 + (s[0] as f32 / 128.0 - 1.0) * shirt.contrast;
            for c in 0..3 {
                let cloth = colour[c] as f32 * light;
                px[c] = (px[c] as f32 * (1.0 - k) + cloth * k)
                    .round()
                    .clamp(0.0, 255.0) as u8;
            }
        }
    }
    Ok(())
}

fn fill_spots(img: &mut RgbaImage, spots: &[[f32; 3]]) {
    let (w, h) = img.dimensions();
    let covered = vec![true; (w * h) as usize];
    for &[sx, sy, r] in spots {
        let weight: Vec<f32> = (0..w * h)
            .map(|i| {
                let (x, y) = ((i % w) as f32 + 0.5, (i / w) as f32 + 0.5);
                let d = ((x - sx).powi(2) + (y - sy).powi(2)).sqrt() / r;
                (1.5 - d).clamp(0.0, 1.0)
            })
            .collect();
        *img = smooth(img, &weight, &covered, r.ceil() as u32 * 2);
    }
}

/// Uncompressed 32-bit TGA, rows bottom-up: ioquake3's loader ignores the
/// top-down flag other writers set, which would flip the image in game.
fn encode_tga(img: &RgbaImage) -> Vec<u8> {
    let (w, h) = img.dimensions();
    let mut out = vec![0u8, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    out.extend_from_slice(&(w as u16).to_le_bytes());
    out.extend_from_slice(&(h as u16).to_le_bytes());
    out.extend_from_slice(&[32, 8]);
    for y in (0..h).rev() {
        for x in 0..w {
            let p = img.get_pixel(x, y);
            out.extend_from_slice(&[p[2], p[1], p[0], p[3]]);
        }
    }
    out
}

/// `surface -> image` over every skin of `model`'s `part`.
fn skin_surfaces(base: &Vfs, model: &str, part: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    for skin in base.list(&format!("models/players/{model}/{part}_"), &[".skin"]) {
        let text = String::from_utf8_lossy(&base.read(&skin).unwrap_or_default()).into_owned();
        for (surf, shader) in md3::parse_skin(&text) {
            if let Some(image) = base.find_image(&shader) {
                out.push((surf, image));
            }
        }
    }
    out
}

/// Runs every texture edit; returns overlay path -> TGA bytes.
pub fn run(
    repo: &Path,
    base: &Vfs,
    cfg: &TextureCfg,
    fields: &HashMap<String, Vec<(String, PartField)>>,
) -> Result<Vec<(String, Vec<u8>)>, String> {
    let mut images = Images {
        repo,
        base,
        open: BTreeMap::new(),
    };
    for suit in &cfg.suits {
        paint_suit(repo, base, suit, &mut images)?;
    }
    for shirt in &cfg.shirts {
        paint_shirt(base, shirt, &mut images)?;
    }
    for (path, spots) in &cfg.spots {
        fill_spots(images.get(path)?, spots);
    }
    for s in &cfg.smooth {
        for path in &s.images {
            let img = images.get(path)?;
            let (w, h) = img.dimensions();
            let (mut weight, mut covered) = (
                vec![0.0f32; (w * h) as usize],
                vec![false; (w * h) as usize],
            );
            for (part, (model, reference, field)) in fields.get(&s.model).into_iter().flatten() {
                let surfaces: Vec<String> = if s.surfaces.is_empty() {
                    skin_surfaces(base, &s.model, part)
                        .into_iter()
                        .filter(|(_, image)| image == path)
                        .map(|(surf, _)| surf)
                        .collect()
                } else {
                    s.surfaces.clone()
                };
                let (pw, pc) = coverage(model, *reference, field, &surfaces, w, h);
                for i in 0..weight.len() {
                    weight[i] = weight[i].max(pw[i]);
                    covered[i] |= pc[i];
                }
            }
            if weight.iter().all(|&k| k <= 0.0) {
                return Err(format!(
                    "{path}: no flattened region of {} maps onto it",
                    s.model
                ));
            }
            *img = smooth(img, &weight, &covered, (s.radius * w).div_ceil(512));
        }
    }
    Ok(images
        .open
        .iter()
        .map(|(path, img)| (path.clone(), encode_tga(img)))
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tga_round_trips_bottom_up() {
        let mut img = RgbaImage::from_pixel(3, 2, Rgba([1, 2, 3, 255]));
        img.put_pixel(0, 0, Rgba([200, 10, 20, 128]));
        let bytes = encode_tga(&img);
        assert_eq!(bytes[17] & 0x20, 0, "must not declare top-down rows");
        let back = crate::texture::decode(&bytes, "x.tga").unwrap();
        assert_eq!(back, img);
    }
}
