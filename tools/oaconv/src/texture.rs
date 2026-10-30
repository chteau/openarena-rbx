//! Image decoding (TGA, JPEG, PNG) and the 1024 px cap.
//!
//! The TGA fallback follows ioquake3's LoadTGA
//! (code/renderercommon/tr_image_tga.c, GPL-2.0), which accepts files the
//! `image` crate rejects.

use image::imageops::{resize, FilterType};
use image::{ImageFormat, RgbaImage};

/// Roblox's texture size cap.
pub const MAX_SIZE: u32 = 1024;

pub fn decode(bytes: &[u8], path: &str) -> Result<RgbaImage, String> {
    let fmt = if bytes.starts_with(&[0x89, b'P', b'N', b'G']) {
        Some(ImageFormat::Png)
    } else if bytes.starts_with(&[0xFF, 0xD8]) {
        Some(ImageFormat::Jpeg)
    } else {
        None
    };
    match fmt {
        Some(f) => image::load_from_memory_with_format(bytes, f)
            .map(|i| i.to_rgba8())
            .map_err(|e| format!("{path}: {e}")),
        None => match image::load_from_memory_with_format(bytes, ImageFormat::Tga) {
            Ok(i) => Ok(i.to_rgba8()),
            Err(_) => decode_tga(bytes).map_err(|e| format!("{path}: {e}")),
        },
    }
}

fn decode_tga(b: &[u8]) -> Result<RgbaImage, String> {
    if b.len() < 18 {
        return Err("TGA too short".into());
    }
    let id_len = b[0] as usize;
    let cmap_type = b[1];
    let ty = b[2];
    let cmap_len = u16::from_le_bytes([b[5], b[6]]) as usize;
    let cmap_bits = b[7] as usize;
    let w = u16::from_le_bytes([b[12], b[13]]) as usize;
    let h = u16::from_le_bytes([b[14], b[15]]) as usize;
    let bpp = b[16] as usize;
    let top_down = b[17] & 0x20 != 0;
    if !matches!(ty, 2 | 3 | 10 | 11) {
        return Err(format!("unsupported TGA type {ty}"));
    }
    if !matches!(bpp, 8 | 24 | 32) {
        return Err(format!("unsupported TGA depth {bpp}"));
    }
    if w == 0 || h == 0 {
        return Err("empty TGA".into());
    }
    let cmap_bytes = if cmap_type != 0 {
        cmap_len * cmap_bits.div_ceil(8)
    } else {
        0
    };
    let mut pos = 18 + id_len + cmap_bytes;
    let bytes_pp = bpp / 8;
    let total = w * h;
    let mut px: Vec<[u8; 4]> = Vec::with_capacity(total);
    let conv = |p: &[u8]| -> [u8; 4] {
        match bytes_pp {
            1 => [p[0], p[0], p[0], 255],
            3 => [p[2], p[1], p[0], 255],
            _ => [p[2], p[1], p[0], p[3]],
        }
    };
    let eof = || "TGA truncated".to_string();
    if ty < 9 {
        let data = b.get(pos..pos + total * bytes_pp).ok_or_else(eof)?;
        px.extend(data.chunks_exact(bytes_pp).map(conv));
    } else {
        while px.len() < total {
            let head = *b.get(pos).ok_or_else(eof)?;
            pos += 1;
            let n = (head & 0x7F) as usize + 1;
            if head & 0x80 != 0 {
                let p = b.get(pos..pos + bytes_pp).ok_or_else(eof)?;
                pos += bytes_pp;
                let c = conv(p);
                px.extend(std::iter::repeat_n(c, n));
            } else {
                let data = b.get(pos..pos + n * bytes_pp).ok_or_else(eof)?;
                pos += n * bytes_pp;
                px.extend(data.chunks_exact(bytes_pp).map(conv));
            }
        }
        px.truncate(total);
    }
    let mut img = RgbaImage::new(w as u32, h as u32);
    for (i, c) in px.into_iter().enumerate() {
        let (x, row) = (i % w, i / w);
        let y = if top_down { row } else { h - 1 - row };
        img.put_pixel(x as u32, y as u32, image::Rgba(c));
    }
    Ok(img)
}

pub fn downscale_max(img: &RgbaImage, max: u32) -> RgbaImage {
    let (w, h) = img.dimensions();
    if w <= max && h <= max {
        return img.clone();
    }
    let s = max as f64 / w.max(h) as f64;
    let nw = ((w as f64 * s).round() as u32).clamp(1, max);
    let nh = ((h as f64 * s).round() as u32).clamp(1, max);
    let mut pre = img.clone();
    for p in pre.pixels_mut() {
        let a = p[3] as u32;
        for c in &mut p.0[..3] {
            *c = ((*c as u32 * a + 127) / 255) as u8;
        }
    }
    let mut out = resize(&pre, nw, nh, FilterType::Triangle);
    for p in out.pixels_mut() {
        let a = p[3] as u32;
        if a == 0 {
            p.0 = [0; 4];
            continue;
        }
        for c in &mut p.0[..3] {
            *c = ((*c as u32 * 255 + a / 2) / a).min(255) as u8;
        }
    }
    out
}

pub fn has_alpha(img: &RgbaImage) -> bool {
    img.pixels().any(|p| p[3] < 255)
}

pub fn encode_png(img: &RgbaImage) -> Vec<u8> {
    let mut out = Vec::new();
    let cur = &mut std::io::Cursor::new(&mut out);
    if has_alpha(img) {
        img.write_to(cur, ImageFormat::Png).expect("png encode");
    } else {
        image::DynamicImage::ImageRgba8(img.clone())
            .to_rgb8()
            .write_to(cur, ImageFormat::Png)
            .expect("png encode");
    }
    out
}

fn factor_code(f: &str) -> Option<&'static str> {
    Some(match f {
        "gl_one" => "1",
        "gl_zero" => "0",
        "gl_src_alpha" => "sa",
        "gl_one_minus_src_alpha" => "isa",
        "gl_src_color" => "sc",
        "gl_one_minus_src_color" => "isc",
        "gl_dst_color" => "dc",
        "gl_one_minus_dst_color" => "idc",
        "gl_dst_alpha" => "da",
        "gl_one_minus_dst_alpha" => "ida",
        _ => return None,
    })
}

/// Output-name suffix of the alpha-blended stand-in for a stage drawn with
/// `blendFunc src dst` (`~1_1` for `add`, `~dc_0` for `filter`), or None when
/// Roblox draws the image as is (opaque, or plain `blend`). The client
/// computes the same suffix (src/client/sys/Assets.luau, `StageImage`).
pub fn blend_suffix(blend: &[String; 2]) -> Option<String> {
    let (s, d) = (factor_code(&blend[0])?, factor_code(&blend[1])?);
    match (s, d) {
        ("1", "0") | ("sa", "isa") => None,
        _ => Some(format!("~{s}_{d}")),
    }
}

/// Re-expresses `out = src * F_src + dst * F_dst` as the closest image Roblox
/// can draw (`out = C * A + dst * (1 - A)`), per pixel. The blend becomes a
/// contribution `c` and a per-channel multiplier `d` on what's behind
/// (framebuffer alpha counts as 1, as in OA):
/// - additive (`d` = 1): `A = max(c)`, `C = c / A` (un-premultiplied), so it
///   is exact over black and with a `LightEmission = 1` Beam;
/// - multiplicative (`filter`, `gl_zero gl_one_minus_src_color`): `A = 1 -
///   luminance(d)`, `C` black plus the tint that matches over mid-grey;
/// - `d` above 1 (`gl_dst_color gl_src_color` brightening) turns into a white
///   contribution that matches over mid-grey.
pub fn blend_to_alpha(img: &RgbaImage, blend: &[String; 2]) -> RgbaImage {
    let lum = |v: [f32; 3]| 0.299 * v[0] + 0.587 * v[1] + 0.114 * v[2];
    let mut out = img.clone();
    for p in out.pixels_mut() {
        let s = [p[0], p[1], p[2]].map(|x| x as f32 / 255.0);
        let a = p[3] as f32 / 255.0;
        let (mut c, mut d) = ([0f32; 3], [0f32; 3]);
        for i in 0..3 {
            match blend[0].as_str() {
                "gl_one" | "gl_dst_alpha" => c[i] += s[i],
                "gl_src_alpha" => c[i] += s[i] * a,
                "gl_one_minus_src_alpha" => c[i] += s[i] * (1.0 - a),
                "gl_src_color" => c[i] += s[i] * s[i],
                "gl_one_minus_src_color" => c[i] += s[i] * (1.0 - s[i]),
                "gl_dst_color" => d[i] += s[i],
                "gl_one_minus_dst_color" => {
                    c[i] += s[i];
                    d[i] -= s[i];
                }
                _ => {}
            }
            d[i] += match blend[1].as_str() {
                "gl_one" | "gl_dst_alpha" => 1.0,
                "gl_src_alpha" => a,
                "gl_one_minus_src_alpha" => 1.0 - a,
                "gl_src_color" => s[i],
                "gl_one_minus_src_color" => 1.0 - s[i],
                // dst * dst: taken at mid-grey
                "gl_dst_color" | "gl_one_minus_dst_color" => 0.5,
                _ => 0.0,
            };
            c[i] += (d[i] - 1.0).max(0.0);
            d[i] = d[i].min(1.0);
        }
        let ld = lum(d);
        let alpha = (1.0 - ld).max(c[0].max(c[1]).max(c[2])).clamp(0.0, 1.0);
        if alpha * 255.0 < 0.5 {
            p.0 = [0; 4];
            continue;
        }
        let ch = |i: usize| {
            let v = (c[i] + 0.5 * (d[i] - ld)) / alpha;
            (v.clamp(0.0, 1.0) * 255.0).round() as u8
        };
        p.0 = [ch(0), ch(1), ch(2), (alpha * 255.0).round() as u8];
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::Rgba;

    fn bf(s: &str, d: &str) -> [String; 2] {
        [s.to_string(), d.to_string()]
    }

    fn px(rgba: [u8; 4], blend: &[String; 2]) -> [u8; 4] {
        let img = RgbaImage::from_pixel(1, 1, Rgba(rgba));
        blend_to_alpha(&img, blend).get_pixel(0, 0).0
    }

    #[test]
    fn suffixes() {
        assert_eq!(
            blend_suffix(&bf("gl_one", "gl_one")).as_deref(),
            Some("~1_1")
        );
        assert_eq!(
            blend_suffix(&bf("gl_dst_color", "gl_zero")).as_deref(),
            Some("~dc_0")
        );
        assert_eq!(
            blend_suffix(&bf("gl_zero", "gl_one_minus_src_color")).as_deref(),
            Some("~0_isc")
        );
        assert_eq!(blend_suffix(&bf("gl_one", "gl_zero")), None);
        assert_eq!(
            blend_suffix(&bf("gl_src_alpha", "gl_one_minus_src_alpha")),
            None
        );
        assert_eq!(blend_suffix(&bf("gl_bogus", "gl_one")), None);
    }

    #[test]
    fn additive_unpremultiplies() {
        let add = bf("gl_one", "gl_one");
        assert_eq!(px([0, 0, 0, 255], &add), [0, 0, 0, 0]);
        assert_eq!(px([255, 255, 255, 255], &add), [255, 255, 255, 255]);
        assert_eq!(px([128, 64, 0, 255], &add), [255, 128, 0, 128]);
        // gl_src_alpha gl_one: the texture's alpha scales the contribution
        assert_eq!(
            px([255, 0, 0, 128], &bf("gl_src_alpha", "gl_one")),
            [255, 0, 0, 128]
        );
        assert_eq!(
            px([255, 0, 0, 0], &bf("gl_src_alpha", "gl_one")),
            [0, 0, 0, 0]
        );
    }

    #[test]
    fn filters_darken() {
        let filter = bf("gl_dst_color", "gl_zero");
        assert_eq!(px([255, 255, 255, 255], &filter), [0, 0, 0, 0]);
        assert_eq!(px([0, 0, 0, 255], &filter), [0, 0, 0, 255]);
        assert_eq!(px([191, 191, 191, 255], &filter), [0, 0, 0, 64]);
        let inv = bf("gl_zero", "gl_one_minus_src_color");
        assert_eq!(px([0, 0, 0, 255], &inv), [0, 0, 0, 0]);
        assert_eq!(px([255, 255, 255, 255], &inv), [0, 0, 0, 255]);
        // a tinted filter keeps its tint over mid-grey
        let [r, g, b, _] = px([255, 128, 128, 255], &filter);
        assert!(r > g && g == b, "{r} {g} {b}");
    }

    #[test]
    fn modulate_2x_lightens_and_darkens() {
        let m2 = bf("gl_dst_color", "gl_src_color");
        assert!(px([128, 128, 128, 255], &m2)[3] <= 1);
        assert_eq!(px([255, 255, 255, 255], &m2), [255, 255, 255, 255]);
        assert_eq!(px([0, 0, 0, 255], &m2), [0, 0, 0, 255]);
    }

    #[test]
    fn real_effects_get_alpha() {
        let Some(vfs) = crate::testdata::vfs() else {
            return;
        };
        let img = |p: &str| decode(&vfs.read(p).expect(p), p).unwrap();
        let add = bf("gl_one", "gl_one");
        // the rocket explosion's black surround and the bullet mark's square
        let boom = blend_to_alpha(&img("models/weaphits/rlboom/rlboom_1.jpg"), &add);
        assert!(boom.get_pixel(0, 0)[3] < 8);
        assert!(boom.pixels().any(|p| p[3] > 200));
        let mark = img(&vfs.find_image("gfx/damage/bulletmult").unwrap());
        let mark = blend_to_alpha(&mark, &bf("gl_dst_color", "gl_src_color"));
        assert!(mark.get_pixel(0, 0)[3] < 8);
    }

    #[test]
    fn all_vfs_images_decode() {
        let Some(vfs) = crate::testdata::vfs() else {
            return;
        };
        let mut fails = Vec::new();
        let mut n = 0;
        for p in vfs.list("", &["tga", "jpg", "jpeg", "png"]) {
            n += 1;
            let bytes = vfs.read(&p).expect("read");
            if let Err(e) = decode(&bytes, &p) {
                fails.push(e);
            }
        }
        println!("decoded {n} images");
        assert!(fails.is_empty(), "{fails:?}");
    }

    #[test]
    fn downscale_dims() {
        let img = RgbaImage::new(2048, 512);
        assert_eq!(downscale_max(&img, 1024).dimensions(), (1024, 256));
    }

    #[test]
    fn alpha_preserved() {
        let img = RgbaImage::from_pixel(2048, 2048, Rgba([200, 100, 50, 128]));
        let d = downscale_max(&img, 1024);
        let p = d.get_pixel(10, 10);
        assert_eq!(p[3], 128);
        assert!((p[0] as i32 - 200).abs() <= 2);
        assert!(has_alpha(&d));
    }

    #[test]
    fn png_round_trip() {
        let mut img = RgbaImage::from_pixel(4, 3, Rgba([1, 2, 3, 255]));
        assert_eq!(decode(&encode_png(&img), "a.png").unwrap(), img);
        img.put_pixel(1, 1, Rgba([9, 8, 7, 5]));
        assert_eq!(decode(&encode_png(&img), "a.png").unwrap(), img);
    }

    #[test]
    fn tga_rle_crossing_rows() {
        let mut t = vec![0, 0, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 2, 0, 24, 0x20];
        t.extend([0x83, 1, 2, 3]);
        let img = decode_tga(&t).unwrap();
        assert_eq!(img.get_pixel(1, 1).0, [3, 2, 1, 255]);
    }
}
