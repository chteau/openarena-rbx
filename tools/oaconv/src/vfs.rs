//! The engine's pk3 search path: every `baseoa/*.pk3` in alphabetical order
//! (later files override earlier ones), then `missionpack/*.pk3` on top.
//! Paths are matched case-insensitively, as `FS_FOpenFileRead` does on pk3s.

use std::collections::BTreeMap;
use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

/// Never loaded: the mature player skins are left out of the port.
const SKIPPED: &[&str] = &["pak2-players-mature.pk3"];

pub struct Vfs {
    pub pk3s: Vec<PathBuf>,
    archives: Vec<Mutex<zip::ZipArchive<File>>>,
    /// lowercased path -> (archive index, entry name as stored)
    files: BTreeMap<String, (usize, String)>,
}

impl Vfs {
    /// `root` is `vendor/oa088/openarena-0.8.8`.
    pub fn open(root: &Path) -> std::io::Result<Self> {
        let mut pk3s = Vec::new();
        for dir in ["baseoa", "missionpack"] {
            let mut found: Vec<PathBuf> = std::fs::read_dir(root.join(dir))?
                .filter_map(|e| e.ok().map(|e| e.path()))
                .filter(|p| p.extension().is_some_and(|e| e.eq_ignore_ascii_case("pk3")))
                .filter(|p| {
                    !SKIPPED
                        .iter()
                        .any(|s| p.file_name().is_some_and(|n| n == *s))
                })
                .collect();
            found.sort();
            pk3s.extend(found);
        }
        let mut archives = Vec::new();
        let mut files = BTreeMap::new();
        for (i, path) in pk3s.iter().enumerate() {
            let zip = zip::ZipArchive::new(File::open(path)?).map_err(std::io::Error::other)?;
            for name in zip.file_names() {
                if !name.ends_with('/') {
                    files.insert(name.to_ascii_lowercase(), (i, name.to_string()));
                }
            }
            archives.push(Mutex::new(zip));
        }
        Ok(Self {
            pk3s,
            archives,
            files,
        })
    }

    pub fn exists(&self, path: &str) -> bool {
        self.files.contains_key(&path.to_ascii_lowercase())
    }

    pub fn read(&self, path: &str) -> Option<Vec<u8>> {
        let (i, name) = self.files.get(&path.to_ascii_lowercase())?;
        let mut zip = self.archives[*i].lock().ok()?;
        let mut entry = zip.by_name(name).ok()?;
        let mut out = Vec::with_capacity(entry.size() as usize);
        entry.read_to_end(&mut out).ok()?;
        Some(out)
    }

    /// The pk3 a path resolves to (file name only), for provenance.
    pub fn source(&self, path: &str) -> Option<String> {
        let (i, _) = self.files.get(&path.to_ascii_lowercase())?;
        Some(self.pk3s[*i].file_name()?.to_string_lossy().into_owned())
    }

    /// Every resolved (lowercased) path under `prefix` ending in one of `exts`.
    pub fn list(&self, prefix: &str, exts: &[&str]) -> Vec<String> {
        self.files
            .range(prefix.to_string()..)
            .take_while(|(k, _)| k.starts_with(prefix))
            .map(|(k, _)| k.clone())
            .filter(|k| exts.is_empty() || exts.iter().any(|e| k.ends_with(e)))
            .collect()
    }

    /// Finds an image the way `R_FindImageFile` does: the name as given,
    /// then with its extension swapped for `.tga`, `.jpg`, `.png`.
    pub fn find_image(&self, name: &str) -> Option<String> {
        let lower = name.to_ascii_lowercase();
        if self.files.contains_key(&lower) {
            return Some(lower);
        }
        let stem = match lower.rfind('.') {
            Some(dot) if !lower[dot..].contains('/') => &lower[..dot],
            _ => &lower[..],
        };
        ["tga", "jpg", "png", "jpeg"]
            .iter()
            .map(|e| format!("{stem}.{e}"))
            .find(|p| self.files.contains_key(p))
    }
}

/// `vendor/oa088/openarena-0.8.8` under the repo root.
pub fn default_root(repo: &Path) -> PathBuf {
    repo.join("vendor/oa088/openarena-0.8.8")
}
