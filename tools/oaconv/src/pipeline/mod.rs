//! `oaconv convert`: every stage, in dependency order, into `build/`.

mod assets;
mod maps;
mod preview;

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

use serde_json::{json, Value};

use oaconv::manifest::{write_json, Manifest, UploadKind};
use oaconv::mesh::{Mesh, MeshInfo};
use oaconv::shader::ShaderSet;
use oaconv::vfs::Vfs;

pub use preview::{preview, View};

pub struct Options {
    pub root: PathBuf,
    /// Loose files searched after every pk3 (`assets/toned`), if it exists.
    pub overlay: Option<PathBuf>,
    pub out: PathBuf,
    pub maps: Option<Vec<String>>,
    pub only: Option<Vec<String>>,
    pub max_pages: Option<usize>,
}

/// Upload prefixes each stage owns, so a partial run replaces only its own.
const STAGES: &[(&str, &[&str])] = &[
    ("maps", &["maps/"]),
    ("models", &["md3/"]),
    ("images", &["images/"]),
    ("sounds", &["sound/", "music/"]),
    ("shaders", &[]),
];

/// Glb files stay under Roblox's 20 MB per-upload cap with room to spare.
const MAX_GLB_BYTES: usize = 18 << 20;

pub(crate) fn err<E: std::fmt::Display>(what: impl std::fmt::Display) -> impl FnOnce(E) -> String {
    move |e| format!("{what}: {e}")
}

/// A Roblox display name (<= 50 chars) keeping the informative tail of a path.
pub(crate) fn display_name(prefix: &str, path: &str) -> String {
    let room = 50 - prefix.len() - 1;
    let tail: String = path
        .chars()
        .rev()
        .take(room)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect();
    format!("{prefix} {tail}")
}

/// Writes meshes into as few `.glb` files as fit under [`MAX_GLB_BYTES`],
/// `dir/<stem>_N.glb`. Returns `(file, infos)` per glb.
pub(crate) fn write_glbs(
    dir: &Path,
    stem: &str,
    meshes: &[Mesh],
) -> Result<Vec<(PathBuf, Vec<MeshInfo>)>, String> {
    let estimate = |m: &Mesh| m.positions.len() * 40 + m.indices.len() * 4 + 1024;
    let mut groups: Vec<Vec<Mesh>> = vec![Vec::new()];
    let mut size = 0;
    for m in meshes.iter().filter(|m| m.tri_count() > 0) {
        if size + estimate(m) > MAX_GLB_BYTES && !groups.last().unwrap().is_empty() {
            groups.push(Vec::new());
            size = 0;
        }
        size += estimate(m);
        groups.last_mut().unwrap().push(m.clone());
    }
    std::fs::create_dir_all(dir).map_err(err(dir.display()))?;
    let mut out = Vec::new();
    for (i, group) in groups.into_iter().filter(|g| !g.is_empty()).enumerate() {
        let (bytes, infos) = oaconv::gltf::write_glb(&group);
        if bytes.len() > 20_000_000 {
            return Err(format!(
                "{stem}_{i}.glb is {} bytes, over Roblox's 20 MB upload cap",
                bytes.len()
            ));
        }
        let path = dir.join(format!("{stem}_{i}.glb"));
        std::fs::write(&path, bytes).map_err(err(path.display()))?;
        out.push((path, infos));
    }
    Ok(out)
}

pub(crate) fn rel(build: &Path, p: &Path) -> String {
    p.strip_prefix(build)
        .unwrap_or(p)
        .to_string_lossy()
        .replace('\\', "/")
}

pub fn convert(o: &Options) -> Result<(), String> {
    let wants = |s: &str| o.only.as_ref().is_none_or(|v| v.iter().any(|x| x == s));
    if let Some(only) = &o.only {
        if let Some(bad) = only.iter().find(|s| !STAGES.iter().any(|(n, _)| n == s)) {
            return Err(format!(
                "--only {bad}: expected maps, models, images, sounds or shaders"
            ));
        }
    }
    let out = &o.out;
    std::fs::create_dir_all(out).map_err(err(out.display()))?;
    let vfs =
        Vfs::open_with_overlay(&o.root, o.overlay.as_deref()).map_err(err(o.root.display()))?;
    let shaders = ShaderSet::load(&vfs);
    let mut manifest = Manifest::load(out).unwrap_or_default();
    manifest.version = 1;
    manifest.sources = vfs.pk3s.iter().map(|p| rel(&o.root, p)).collect();
    if vfs.overlay.is_some() {
        manifest.sources.push(oaconv::vfs::OVERLAY.to_string());
    }
    for (stage, prefixes) in STAGES {
        if wants(stage) && (*stage != "maps" || o.maps.is_none()) {
            manifest
                .uploads
                .retain(|u| !prefixes.iter().any(|p| u.path.starts_with(p)));
        }
    }

    if wants("shaders") {
        let mut classes: BTreeMap<String, usize> = BTreeMap::new();
        for s in shaders.shaders.values() {
            *classes
                .entry(format!("{:?}", s.class).to_lowercase())
                .or_default() += 1;
        }
        write_json(&out.join("shaders.json"), &shaders.shaders).map_err(err("shaders.json"))?;
        manifest.shaders =
            json!({ "file": "shaders.json", "count": shaders.shaders.len(), "classes": classes });
        println!("shaders: {} ({classes:?})", shaders.shaders.len());
    }
    if wants("maps") {
        let settings = oaconv::bake::Settings {
            max_pages: o
                .max_pages
                .unwrap_or(oaconv::bake::Settings::default().max_pages),
            ..Default::default()
        };
        maps::convert_all(
            &vfs,
            &shaders,
            out,
            o.maps.as_deref(),
            &settings,
            &mut manifest,
        )?;
    }
    if wants("models") {
        assets::models(&vfs, &shaders, out, &mut manifest)?;
    }
    if wants("images") {
        let mut runtime: BTreeSet<String> = BTreeSet::new();
        let listed = manifest
            .maps
            .values()
            .chain(std::iter::once(&manifest.models));
        for v in listed
            .filter_map(|v| v.get("images"))
            .filter_map(Value::as_array)
        {
            runtime.extend(v.iter().filter_map(Value::as_str).map(str::to_string));
        }
        assets::images(&vfs, &shaders, out, &runtime, &mut manifest)?;
    }
    if wants("sounds") {
        assets::sounds(&vfs, out, &mut manifest)?;
    }

    manifest
        .uploads
        .sort_by(|a, b| (a.kind, &a.path).cmp(&(b.kind, &b.path)));
    let count = |k: UploadKind| manifest.uploads.iter().filter(|u| u.kind == k).count();
    let maps = manifest.maps.values();
    let sum = |key: &str| -> u64 {
        manifest
            .maps
            .values()
            .filter_map(|m| m["stats"][key].as_u64())
            .sum()
    };
    manifest.totals = json!({
        "maps": maps.len(),
        "map_meshes": sum("meshes"),
        "map_triangles": sum("triangles"),
        "atlas_pages": sum("atlas_pages"),
        "images_converted": manifest.textures["count"],
        "md3_models": manifest.models["md3"],
        "sound_clips": manifest.sounds["clips"],
        "audio_files": count(UploadKind::Audio),
        "uploads": { "Model": count(UploadKind::Model), "Image": count(UploadKind::Image), "Audio": count(UploadKind::Audio) },
        "upload_bytes": manifest.uploads.iter().map(|u| u.bytes).sum::<u64>(),
    });
    manifest.save(out).map_err(err("manifest.json"))?;
    println!(
        "totals: {}",
        serde_json::to_string_pretty(&manifest.totals).unwrap_or_default()
    );
    Ok(())
}
