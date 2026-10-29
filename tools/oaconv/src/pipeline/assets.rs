//! Models (MD3, skins, animation.cfg), images and sounds.

use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use rayon::prelude::*;
use serde_json::{json, Value};

use oaconv::bake::{first_image, image_output};
use oaconv::bsp::entities::to_luau;
use oaconv::luau::write_buffer_modules;
use oaconv::manifest::{write_json, Manifest, UploadKind};
use oaconv::shader::{strip_ext, ShaderClass, ShaderSet};
use oaconv::vfs::Vfs;
use oaconv::{md3, sound, texture};

use super::{display_name, err, rel, write_glbs};

fn sanitize(name: &str) -> String {
    name.chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '_' })
        .collect()
}

fn parent_and_stem(path: &str) -> (&str, String) {
    let (dir, file) = path.rsplit_once('/').unwrap_or(("", path));
    (dir, strip_ext(file))
}

/// Every MD3 as a runtime buffer (Luau modules) and a frame-0 glb; static
/// (single-frame) models also bundled for upload. Skins and animation.cfg as JSON.
pub fn models(
    vfs: &Vfs,
    shaders: &ShaderSet,
    out: &Path,
    manifest: &mut Manifest,
) -> Result<(), String> {
    let paths = vfs.list("models/", &[".md3"]);
    let mut index = BTreeMap::new();
    let mut images = BTreeSet::new();
    let mut statics = Vec::new();
    let mut failed = Vec::new();
    let texture_of = |shader: &str| -> Option<String> {
        (!shader.is_empty())
            .then(|| first_image(&shaders.resolve(shader, false, vfs), vfs))
            .flatten()
    };
    for path in &paths {
        let model = match vfs
            .read(path)
            .ok_or("unreadable".to_string())
            .and_then(|b| md3::parse(&b))
        {
            Ok(m) => m,
            Err(e) => {
                failed.push(format!("{path}: {e}"));
                continue;
            }
        };
        let (dir, stem) = parent_and_stem(path);
        let dir_out = out.join("md3").join(dir);
        let buffer = md3::to_buffer(&model);
        std::fs::create_dir_all(&dir_out).map_err(err(dir_out.display()))?;
        std::fs::write(dir_out.join(format!("{stem}.oam3")), &buffer).map_err(err(path))?;
        write_buffer_modules(&dir_out.join("luau"), &stem, &buffer).map_err(err(path))?;
        let mut meshes = md3::static_meshes(&model, 0, &sanitize(&strip_ext(path)));
        for m in &mut meshes {
            if let Some(img) = texture_of(&m.shader) {
                m.texture = Some(image_output(&img));
                images.insert(img);
            }
        }
        let glb = write_glbs(&dir_out, &format!("{stem}_static"), &meshes)?;
        let is_static = model.frames.len() == 1;
        if is_static {
            statics.extend(meshes);
        }
        index.insert(
            path.clone(),
            json!({
                "frames": model.frames.len(),
                "tags": model.tags.first().map(|t| t.iter().map(|t| t.name.clone()).collect::<Vec<_>>()),
                "surfaces": model.surfaces.iter().map(|s| json!({
                    "name": s.name, "shaders": s.shaders, "verts": s.st.len(), "tris": s.triangles.len(),
                })).collect::<Vec<_>>(),
                "buffer": format!("md3/{dir}/{stem}.oam3"),
                "module": format!("md3/{dir}/luau/{stem}"),
                "glb": glb.first().map(|(p, _)| rel(out, p)),
                "static": is_static,
            }),
        );
    }
    let bundle = write_glbs(&out.join("md3"), "static_bundle", &statics)?;
    let mut bundles = Vec::new();
    for (path, infos) in &bundle {
        manifest
            .add_upload(
                out,
                path,
                UploadKind::Model,
                &display_name("OA md3", &rel(out, path)),
            )
            .map_err(err(path.display()))?;
        bundles.push(json!({ "file": rel(out, path), "meshes": infos }));
    }

    let mut skins = BTreeMap::new();
    for path in vfs.list("models/", &[".skin"]) {
        let text = String::from_utf8_lossy(&vfs.read(&path).unwrap_or_default()).into_owned();
        let pairs = md3::parse_skin(&text);
        for (_, shader) in &pairs {
            if let Some(img) = texture_of(shader) {
                images.insert(img);
            }
        }
        skins.insert(path, pairs);
    }
    let mut animations = BTreeMap::new();
    for path in vfs.list("models/", &["animation.cfg"]) {
        let text = String::from_utf8_lossy(&vfs.read(&path).unwrap_or_default()).into_owned();
        match md3::parse_animation_cfg(&text) {
            Ok(cfg) => {
                animations.insert(path, cfg);
            }
            Err(e) => failed.push(format!("{path}: {e}")),
        }
    }
    let doc = json!({ "md3": index, "static_bundles": bundles, "skins": skins, "animations": animations });
    write_json(&out.join("models.json"), &doc).map_err(err("models.json"))?;
    println!(
        "models: {} md3 ({} static), {} skins, {} animation.cfg",
        index.len(),
        doc["md3"]
            .as_object()
            .map_or(0, |m| m.values().filter(|v| v["static"] == true).count()),
        skins.len(),
        animations.len()
    );
    if !failed.is_empty() {
        return Err(format!("models failed:\n{}", failed.join("\n")));
    }
    manifest.models = json!({
        "file": "models.json",
        "md3": index.len(),
        "static_bundles": bundle.len(),
        "skins": skins.len(),
        "animations": animations.len(),
        "images": images,
    });
    Ok(())
}

/// Per image: (was downscaled, has alpha).
type ImageResult = Result<(bool, bool), String>;

/// Every image to PNG (<= 1024 px). Uploads: everything outside `textures/`
/// (UI, models, sprites, skies), plus world textures that something draws
/// unbaked (`runtime`, or a non-opaque script shader).
pub fn images(
    vfs: &Vfs,
    shaders: &ShaderSet,
    out: &Path,
    runtime: &BTreeSet<String>,
    manifest: &mut Manifest,
) -> Result<(), String> {
    // Several stems ship in two formats (`decal2.tga` and `decal2.jpg`) and
    // both would land on the same PNG; keep the one the engine loads.
    let paths: Vec<String> = vfs
        .list("", &[".tga", ".jpg", ".jpeg", ".png"])
        .into_iter()
        .filter(|p| vfs.find_image(&strip_ext(p)).as_deref() == Some(p.as_str()))
        .collect();
    let mut live: BTreeSet<String> = runtime.clone();
    for s in shaders.shaders.values() {
        if !matches!(s.class, ShaderClass::Opaque | ShaderClass::Nodraw)
            || !s.name.starts_with("textures/")
        {
            live.extend(
                s.stages
                    .iter()
                    .flat_map(|st| st.maps.iter())
                    .filter_map(|m| vfs.find_image(m)),
            );
        }
    }
    let results: Vec<(&String, ImageResult)> = paths
        .par_iter()
        .map(|p| {
            let r = (|| {
                let img = texture::decode(&vfs.read(p).ok_or("unreadable")?, p)?;
                let small = texture::downscale_max(&img, texture::MAX_SIZE);
                let dest = out.join(image_output(p));
                std::fs::create_dir_all(dest.parent().unwrap()).map_err(|e| e.to_string())?;
                std::fs::write(&dest, texture::encode_png(&small)).map_err(|e| e.to_string())?;
                Ok((
                    small.dimensions() != img.dimensions(),
                    texture::has_alpha(&small),
                ))
            })();
            (p, r)
        })
        .collect();
    let mut failed = Vec::new();
    let (mut uploaded, mut downscaled, mut alpha) = (0, 0, 0);
    for (p, r) in &results {
        match r {
            Ok((down, a)) => {
                downscaled += *down as usize;
                alpha += *a as usize;
                if !p.starts_with("textures/") || live.contains(*p) {
                    let dest = out.join(image_output(p));
                    manifest
                        .add_upload(
                            out,
                            &dest,
                            UploadKind::Image,
                            &display_name("OA", &strip_ext(p)),
                        )
                        .map_err(err(p))?;
                    uploaded += 1;
                }
            }
            Err(e) => failed.push(format!("{p}: {e}")),
        }
    }
    println!(
        "images: {} converted, {downscaled} downscaled, {uploaded} to upload, {} failed",
        results.len() - failed.len(),
        failed.len()
    );
    manifest.textures = json!({
        "dir": "images",
        "count": results.len() - failed.len(),
        "downscaled": downscaled,
        "with_alpha": alpha,
        "uploads": uploaded,
        "failed": failed,
    });
    Ok(())
}

/// Effects into OGG atlases + `sound_index.json`; music copied separately.
pub fn sounds(vfs: &Vfs, out: &Path, manifest: &mut Manifest) -> Result<(), String> {
    sound::check_ffmpeg()?;
    let load = |paths: Vec<String>| -> Vec<sound::Clip> {
        paths
            .into_iter()
            .filter_map(|path| {
                Some(sound::Clip {
                    bytes: vfs.read(&path)?,
                    path,
                })
            })
            .collect()
    };
    let clips = load(vfs.list("sound/", &[".wav", ".ogg"]));
    let dir = out.join("sound");
    std::fs::create_dir_all(&dir).map_err(err(dir.display()))?;
    let (atlases, index) = sound::build_atlases(&clips, &dir)?;
    write_json(&out.join("sound_index.json"), &index).map_err(err("sound_index.json"))?;
    let literal = format!(
        "-- Generated by oaconv: OA sound path -> atlas, start, length (seconds).\nreturn {}\n",
        to_luau(&serde_json::to_value(&index).unwrap_or_default())
    );
    if literal.len() < oaconv::luau::MAX_MODULE_CHARS {
        std::fs::write(out.join("SoundIndex.luau"), literal).map_err(err("SoundIndex.luau"))?;
    }
    for a in &atlases {
        let path = dir.join(&a.file);
        manifest
            .add_upload(
                out,
                &path,
                UploadKind::Audio,
                &display_name("OA sfx", &a.file),
            )
            .map_err(err(&a.file))?;
    }
    let music_dir = out.join("music");
    std::fs::create_dir_all(&music_dir).map_err(err(music_dir.display()))?;
    let mut music = Vec::new();
    for clip in load(vfs.list("music/", &[".ogg", ".wav"])) {
        let path = sound::write_music(&clip, &music_dir)?;
        manifest
            .add_upload(
                out,
                &path,
                UploadKind::Audio,
                &display_name("OA music", &clip.path),
            )
            .map_err(err(&clip.path))?;
        music.push(json!({ "source": clip.path, "file": rel(out, &path) }));
    }
    println!(
        "sounds: {} clips in {} atlases, {} music tracks",
        index.len(),
        atlases.len(),
        music.len()
    );
    manifest.sounds = json!({
        "index": "sound_index.json",
        "clips": index.len(),
        "atlases": atlases.iter().map(|a| json!({ "file": format!("sound/{}", a.file), "seconds": a.seconds, "clips": a.clips })).collect::<Vec<Value>>(),
        "music": music,
    });
    Ok(())
}
