//! Per map: baked meshes + atlas pages, collision, entities, light grid, AAS.

use std::path::{Path, PathBuf};

use rayon::prelude::*;
use serde_json::{json, Value};

use oaconv::bake::{bake_map, Settings};
use oaconv::bsp::collision::CollisionMap;
use oaconv::bsp::{checksum::block_checksum, entities, lightgrid, Bsp};
use oaconv::luau::write_buffer_modules;
use oaconv::manifest::{write_json, Manifest, UploadKind};
use oaconv::shader::ShaderSet;
use oaconv::texture::encode_png;
use oaconv::vfs::Vfs;

use super::{display_name, err, rel, write_glbs};

type Uploads = Vec<(PathBuf, UploadKind, String)>;
type MapResult = Result<(Value, Uploads), String>;

fn write(path: &Path, bytes: &[u8]) -> Result<(), String> {
    std::fs::write(path, bytes).map_err(err(path.display()))
}

/// A blob as a raw file plus its Luau chunk modules under `luau/`.
fn blob(dir: &Path, file: &str, module: &str, bytes: &[u8]) -> Result<Value, String> {
    write(&dir.join(file), bytes)?;
    let modules = write_buffer_modules(&dir.join("luau"), module, bytes).map_err(err(module))?;
    Ok(
        json!({ "file": file, "bytes": bytes.len(), "module": format!("luau/{module}"), "chunks": modules.len() - 1 }),
    )
}

fn convert_map(vfs: &Vfs, shaders: &ShaderSet, out: &Path, name: &str, s: &Settings) -> MapResult {
    let dir = out.join("maps").join(name);
    std::fs::create_dir_all(&dir).map_err(err(dir.display()))?;
    let source = format!("maps/{name}.bsp");
    let bsp_bytes = vfs.read(&source).ok_or(format!("{source} unreadable"))?;
    let bsp = Bsp::parse(&bsp_bytes).map_err(err(&source))?;
    let mut uploads = Uploads::new();

    let baked = bake_map(name, &bsp, shaders, vfs, s);
    let mut atlas = Vec::new();
    for (i, page) in baked.pages.iter().enumerate() {
        let path = dir.join(format!("atlas_{i}.png"));
        write(&path, &encode_png(page))?;
        uploads.push((
            path,
            UploadKind::Image,
            display_name("OA atlas", &format!("{name} {i}")),
        ));
        atlas.push(format!("atlas_{i}.png"));
    }
    let glbs = write_glbs(&dir, "mesh", &baked.meshes)?;
    let mut mesh_files = Vec::new();
    for (path, infos) in &glbs {
        let file = rel(&dir, path);
        uploads.push((
            path.clone(),
            UploadKind::Model,
            display_name("OA map", &format!("{name} {file}")),
        ));
        mesh_files.push(json!({ "file": file, "meshes": infos }));
    }
    let triangles: usize = baked.meshes.iter().map(|m| m.tri_count()).sum();

    let cm = CollisionMap::build(&bsp);
    let collision = blob(&dir, "collision.bin", "Collision", &cm.to_bytes())?;
    let ents = entities::summarize(&bsp).map_err(err(format!("{name} entities")))?;
    let ent_blob = blob(
        &dir,
        "entities.json",
        "Entities",
        &serde_json::to_vec(&ents).unwrap_or_default(),
    )?;
    let grid = match lightgrid::light_grid(&bsp) {
        Ok(g) => {
            let mut v = serde_json::to_value(&g).unwrap_or_default();
            v["blob"] = blob(&dir, "lightgrid.bin", "LightGrid", &g.cells)?;
            v
        }
        Err(e) => json!({ "error": e }),
    };
    let aas = match vfs.read(&format!("maps/{name}.aas")) {
        Some(bytes) => blob(&dir, "map.aas", "Aas", &bytes)?,
        None => json!({ "error": "no .aas in the pk3s" }),
    };
    let mut stats = baked.stats.clone();
    stats["meshes"] = json!(baked.meshes.len());
    stats["triangles"] = json!(triangles);
    stats["glb_files"] = json!(glbs.len());
    let info = json!({
        "name": name,
        "source": vfs.source(&source),
        "dir": format!("maps/{name}"),
        "checksum": block_checksum(&bsp_bytes),
        "glb": mesh_files,
        "atlas": atlas,
        "texel_density": baked.density,
        "stats": stats,
        "collision": collision,
        "entities": { "blob": ent_blob, "count": ents["entities"].as_array().map_or(0, Vec::len), "counts": ents["counts"] },
        "lightgrid": grid,
        "aas": aas,
        "images": baked.images,
    });
    write_json(&dir.join("map.json"), &info).map_err(err("map.json"))?;
    Ok((info, uploads))
}

pub fn convert_all(
    vfs: &Vfs,
    shaders: &ShaderSet,
    out: &Path,
    only: Option<&[String]>,
    s: &Settings,
    manifest: &mut Manifest,
) -> Result<(), String> {
    let names: Vec<String> = vfs
        .list("maps/", &[".bsp"])
        .iter()
        .filter_map(|p| {
            p.strip_prefix("maps/")?
                .strip_suffix(".bsp")
                .map(str::to_string)
        })
        .filter(|n| !n.contains('/') && only.is_none_or(|o| o.contains(n)))
        .collect();
    if let Some(missing) = only.and_then(|o| o.iter().find(|n| !names.contains(n))) {
        return Err(format!("no maps/{missing}.bsp"));
    }
    if only.is_none() {
        manifest.maps.clear();
    }
    let results: Vec<(&String, MapResult)> = names
        .par_iter()
        .map(|n| {
            let r = convert_map(vfs, shaders, out, n, s);
            match &r {
                Ok((v, _)) => println!(
                    "map {n}: {} meshes, {} tris, {} atlas pages at {:.3} texels/unit",
                    v["stats"]["meshes"],
                    v["stats"]["triangles"],
                    v["stats"]["atlas_pages"],
                    v["texel_density"]
                ),
                Err(e) => eprintln!("map {n}: {e}"),
            }
            (n, r)
        })
        .collect();
    let mut failed = Vec::new();
    for (name, r) in results {
        match r {
            Ok((info, uploads)) => {
                manifest
                    .uploads
                    .retain(|u| !u.path.starts_with(&format!("maps/{name}/")));
                for (path, kind, display) in uploads {
                    manifest
                        .add_upload(out, &path, kind, &display)
                        .map_err(err(path.display()))?;
                }
                manifest.maps.insert(name.clone(), info);
            }
            Err(e) => failed.push(format!("{name}: {e}")),
        }
    }
    if failed.is_empty() {
        Ok(())
    } else {
        Err(format!(
            "{} map(s) failed:\n{}",
            failed.len(),
            failed.join("\n")
        ))
    }
}
