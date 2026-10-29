//! `oaconv tone`: regenerates the reshaped MD3s in the overlay from the pk3
//! originals and the config, and optionally writes before/after sheets.

use std::collections::{BTreeMap, HashMap};
use std::path::Path;

use super::view::{load_skin, sheet, Player};
use super::Config;
use crate::md3::{self, Md3};
use crate::vfs::{default_root, Vfs, OVERLAY};

/// The config, relative to the repo root.
pub const CONFIG: &str = "assets/toned-models.json";

/// LOD suffixes the engine loads (`_1`, `_2` for r_lodbias).
const LODS: [&str; 3] = ["", "_1", "_2"];

fn load(vfs: &Vfs, path: &str) -> Result<Option<(Vec<u8>, Md3)>, String> {
    let Some(bytes) = vfs.read(path) else {
        return Ok(None);
    };
    let model = md3::parse(&bytes).map_err(|e| format!("{path}: {e}"))?;
    Ok(Some((bytes, model)))
}

/// What one pass over the config produces.
pub struct Generated {
    /// Overlay path -> file bytes.
    pub files: Vec<(String, Vec<u8>)>,
    edited: HashMap<(String, String), Md3>,
    cfgs: BTreeMap<String, md3::AnimationCfg>,
}

/// Builds every configured part and skin from the pk3 originals (and
/// `assets/toned-src`), without writing anything.
pub fn generate(repo: &Path, base: &Vfs) -> Result<Generated, String> {
    let text = std::fs::read_to_string(repo.join(CONFIG)).map_err(|e| format!("{CONFIG}: {e}"))?;
    let config: Config = serde_json::from_str(&text).map_err(|e| format!("{CONFIG}: {e}"))?;
    let mut out = Generated {
        files: Vec::new(),
        edited: HashMap::new(),
        cfgs: BTreeMap::new(),
    };
    let mut fields = HashMap::new();
    for (name, parts) in &config.models {
        let dir = format!("models/players/{name}");
        let cfg_text = base
            .read(&format!("{dir}/animation.cfg"))
            .ok_or(format!("{dir}: no animation.cfg"))?;
        let cfg = md3::parse_animation_cfg(&String::from_utf8_lossy(&cfg_text))?;
        let mut model_fields = Vec::new();
        for (part, pc) in parts {
            let reference = super::anim_frame(&cfg, &pc.reference, part == "lower")?;
            let mut field = None;
            for lod in LODS {
                let path = format!("{dir}/{part}{lod}.md3");
                let Some((bytes, model)) = load(base, &path)? else {
                    continue;
                };
                let reference = reference.min(model.frames.len() - 1);
                let field =
                    field.get_or_insert_with(|| super::field(&model, reference, &pc.regions));
                let (edited, moved) = super::apply(&model, reference, field);
                if moved == 0 {
                    return Err(format!("{path}: no vertex inside any region"));
                }
                out.files.push((path, super::patch(&bytes, &edited)?));
                if lod.is_empty() {
                    out.edited.insert((name.clone(), part.clone()), edited);
                    model_fields.push((part.clone(), (model, reference, field.clone())));
                }
            }
        }
        fields.insert(name.clone(), model_fields);
        out.cfgs.insert(name.clone(), cfg);
    }
    out.files
        .extend(super::textures::run(repo, base, &config.textures, &fields)?);
    Ok(out)
}

/// Writes every configured part and skin under `<repo>/assets/toned/`;
/// returns the paths written. With `preview`, also `<preview>/<model>_<skin>.png`.
pub fn run(repo: &Path, preview: Option<&Path>) -> Result<Vec<String>, String> {
    let root = default_root(repo);
    let base = Vfs::open(&root).map_err(|e| e.to_string())?;
    let generated = generate(repo, &base)?;
    let mut written = Vec::new();
    for (path, bytes) in &generated.files {
        let file = repo.join(OVERLAY).join(path);
        std::fs::create_dir_all(file.parent().unwrap_or(repo)).map_err(|e| e.to_string())?;
        std::fs::write(&file, bytes).map_err(|e| format!("{path}: {e}"))?;
        written.push(path.clone());
    }
    if let Some(dir_out) = preview {
        let overlay =
            Vfs::open_with_overlay(&root, Some(&repo.join(OVERLAY))).map_err(|e| e.to_string())?;
        std::fs::create_dir_all(dir_out).map_err(|e| e.to_string())?;
        for (name, cfg) in &generated.cfgs {
            let player = |use_edits: bool| -> Result<Option<Player>, String> {
                let part =
                    |p: &str| -> Result<Option<Md3>, String> {
                        match generated
                            .edited
                            .get(&(name.clone(), p.to_string()))
                            .filter(|_| use_edits)
                        {
                            Some(m) => Ok(Some(m.clone())),
                            None => Ok(load(&base, &format!("models/players/{name}/{p}.md3"))?
                                .map(|(_, m)| m)),
                        }
                    };
                let Some(lower) = part("lower")? else {
                    return Ok(None);
                };
                Ok(Some(Player {
                    lower,
                    upper: part("upper")?,
                    head: part("head")?,
                    cfg: cfg.clone(),
                }))
            };
            let (Some(before), Some(after)) = (player(false)?, player(true)?) else {
                continue;
            };
            for skin in ["default", "red", "blue", "retro"] {
                let mut textures = HashMap::new();
                let map = load_skin(&overlay, name, skin, &mut textures);
                if !map.is_empty() {
                    let out = dir_out.join(format!("{name}_{skin}.png"));
                    sheet(&before, &after, &map, &textures)
                        .save(&out)
                        .map_err(|e| e.to_string())?;
                }
            }
        }
    }
    Ok(written)
}
