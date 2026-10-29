//! The engine's pk3 search path: every `baseoa/*.pk3` in alphabetical order
//! (later files override earlier ones), then `missionpack/*.pk3` on top.
//! Paths are matched case-insensitively, as `FS_FOpenFileRead` does on pk3s.
//! Our own modified art (`assets/toned/`, loose files at pk3 paths) is
//! searched after every pk3, like one last pk3.

use std::collections::BTreeMap;
use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

/// Never loaded: the mature player skins are left out of the port.
const SKIPPED: &[&str] = &["pak2-players-mature.pk3"];

/// The overlay of edited art, relative to the repo root.
pub const OVERLAY: &str = "assets/toned";

pub struct Vfs {
    pub pk3s: Vec<PathBuf>,
    /// The loose-file overlay, when one was given.
    pub overlay: Option<PathBuf>,
    archives: Vec<Mutex<zip::ZipArchive<File>>>,
    /// lowercased path -> where it resolves
    files: BTreeMap<String, Entry>,
}

enum Entry {
    /// archive index, entry name as stored
    Pk3(usize, String),
    /// a file under the overlay
    Loose(PathBuf),
}

impl Vfs {
    /// `root` is `vendor/oa088/openarena-0.8.8`.
    pub fn open(root: &Path) -> std::io::Result<Self> {
        Self::open_with_overlay(root, None)
    }

    /// The pk3s, then every file under `overlay` (paths relative to it) on top.
    pub fn open_with_overlay(root: &Path, overlay: Option<&Path>) -> std::io::Result<Self> {
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
                    files.insert(name.to_ascii_lowercase(), Entry::Pk3(i, name.to_string()));
                }
            }
            archives.push(Mutex::new(zip));
        }
        if let Some(dir) = overlay {
            let mut stack = vec![dir.to_path_buf()];
            while let Some(d) = stack.pop() {
                for e in std::fs::read_dir(&d)? {
                    let path = e?.path();
                    if path.is_dir() {
                        stack.push(path);
                    } else if let Ok(rel) = path.strip_prefix(dir) {
                        let key = rel
                            .to_string_lossy()
                            .replace('\\', "/")
                            .to_ascii_lowercase();
                        files.insert(key, Entry::Loose(path));
                    }
                }
            }
        }
        Ok(Self {
            pk3s,
            overlay: overlay.map(Path::to_path_buf),
            archives,
            files,
        })
    }

    pub fn exists(&self, path: &str) -> bool {
        self.files.contains_key(&path.to_ascii_lowercase())
    }

    pub fn read(&self, path: &str) -> Option<Vec<u8>> {
        let (i, name) = match self.files.get(&path.to_ascii_lowercase())? {
            Entry::Pk3(i, name) => (i, name),
            Entry::Loose(p) => return std::fs::read(p).ok(),
        };
        let mut zip = self.archives[*i].lock().ok()?;
        let mut entry = zip.by_name(name).ok()?;
        let mut out = Vec::with_capacity(entry.size() as usize);
        entry.read_to_end(&mut out).ok()?;
        Some(out)
    }

    /// The pk3 a path resolves to (file name only), or [`OVERLAY`], for provenance.
    pub fn source(&self, path: &str) -> Option<String> {
        match self.files.get(&path.to_ascii_lowercase())? {
            Entry::Pk3(i, _) => Some(self.pk3s[*i].file_name()?.to_string_lossy().into_owned()),
            Entry::Loose(_) => Some(OVERLAY.to_string()),
        }
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn write(path: &Path, bytes: &[u8]) {
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, bytes).unwrap();
    }

    #[test]
    fn overlay_wins_over_every_pk3() {
        let tmp = std::env::temp_dir().join(format!("oaconv-vfs-{}", std::process::id()));
        let root = tmp.join("oa");
        std::fs::create_dir_all(root.join("missionpack")).unwrap();
        std::fs::create_dir_all(root.join("baseoa")).unwrap();
        let mut zip = zip::ZipWriter::new(File::create(root.join("baseoa/pak0.pk3")).unwrap());
        let opts = zip::write::SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Stored);
        for (name, bytes) in [
            ("models/players/neko/Neko.tga", b"pk3".as_slice()),
            ("models/players/neko/hair.tga", b"hair"),
        ] {
            zip.start_file(name, opts).unwrap();
            zip.write_all(bytes).unwrap();
        }
        zip.finish().unwrap();
        let overlay = tmp.join("toned");
        write(&overlay.join("models/players/neko/neko.tga"), b"toned");

        let base = Vfs::open(&root).unwrap();
        assert_eq!(base.read("models/players/neko/neko.tga").unwrap(), b"pk3");
        let vfs = Vfs::open_with_overlay(&root, Some(&overlay)).unwrap();
        assert_eq!(vfs.read("models/players/neko/NEKO.tga").unwrap(), b"toned");
        assert_eq!(vfs.source("models/players/neko/neko.tga").unwrap(), OVERLAY);
        assert_eq!(vfs.read("models/players/neko/hair.tga").unwrap(), b"hair");
        assert_eq!(vfs.list("models/players/neko/", &[".tga"]).len(), 2);
        std::fs::remove_dir_all(&tmp).unwrap();
    }

    /// Every shipped overlay file replaces a real pk3 path (no typos that
    /// would add a new, unused image instead).
    #[test]
    fn toned_overlay_replaces_real_files() {
        let Some(base) = crate::testdata::vfs() else {
            return;
        };
        let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../..")
            .join(OVERLAY);
        let vfs = Vfs::open_with_overlay(&crate::testdata::root(), Some(&dir)).unwrap();
        let mut n = 0;
        for (key, entry) in &vfs.files {
            if let Entry::Loose(path) = entry {
                if key.ends_with(".md") {
                    continue;
                }
                assert!(base.exists(key), "{key} is not in any pk3");
                assert_eq!(vfs.read(key).unwrap(), std::fs::read(path).unwrap());
                assert_ne!(vfs.read(key), base.read(key), "{key} is unchanged");
                n += 1;
            }
        }
        assert!(n > 0, "no overlay files under {}", dir.display());
    }
}
