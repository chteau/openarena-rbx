//! `build/manifest.json`: every output, and the uploads an uploader must do.

use std::collections::BTreeMap;
use std::path::Path;

use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum UploadKind {
    /// `.glb`, uploaded as a `Model` (one MeshPart per mesh node).
    Model,
    /// `.png`, uploaded as a `Decal` (the asset id is used as an image id).
    Image,
    /// `.ogg`, uploaded as `Audio`.
    Audio,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Upload {
    /// Relative to `build/`, forward slashes.
    pub path: String,
    #[serde(rename = "type")]
    pub kind: UploadKind,
    pub sha256: String,
    pub bytes: u64,
    /// Roblox display name (<= 50 chars).
    pub name: String,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Manifest {
    pub version: u32,
    pub sources: Vec<String>,
    /// Per map: meshes, atlas pages, collision, entities, light grid, aas.
    pub maps: BTreeMap<String, Value>,
    pub models: Value,
    pub textures: Value,
    pub sounds: Value,
    pub shaders: Value,
    pub totals: Value,
    pub uploads: Vec<Upload>,
}

/// One lock entry in `build/assets.lock.json`, keyed by upload path.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Locked {
    pub sha256: String,
    #[serde(rename = "type")]
    pub kind: UploadKind,
    pub asset_id: u64,
}

pub type AssetLock = BTreeMap<String, Locked>;

impl Manifest {
    pub fn load(build: &Path) -> Result<Self, String> {
        let text = std::fs::read_to_string(build.join("manifest.json")).map_err(|e| format!("manifest.json: {e}"))?;
        serde_json::from_str(&text).map_err(|e| format!("manifest.json: {e}"))
    }

    pub fn save(&self, build: &Path) -> std::io::Result<()> {
        write_json(&build.join("manifest.json"), self)
    }

    /// Records `path` (absolute, under `build`) for upload.
    pub fn add_upload(&mut self, build: &Path, path: &Path, kind: UploadKind, name: &str) -> std::io::Result<()> {
        let bytes = std::fs::read(path)?;
        let rel = path.strip_prefix(build).unwrap_or(path).to_string_lossy().replace('\\', "/");
        let name: String = name.chars().take(50).collect();
        self.uploads.push(Upload {
            path: rel,
            kind,
            sha256: crate::luau::sha256_hex(&bytes),
            bytes: bytes.len() as u64,
            name,
        });
        Ok(())
    }
}

pub fn load_lock(build: &Path) -> AssetLock {
    std::fs::read_to_string(build.join("assets.lock.json"))
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or_default()
}

/// Written through a temp file and a rename so an interrupted upload never
/// leaves a torn lock.
pub fn save_lock(build: &Path, lock: &AssetLock) -> std::io::Result<()> {
    write_json(&build.join("assets.lock.json"), lock)
}

pub fn write_json<T: Serialize + ?Sized>(path: &Path, value: &T) -> std::io::Result<()> {
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, serde_json::to_vec_pretty(value).map_err(std::io::Error::other)?)?;
    std::fs::rename(tmp, path)
}
