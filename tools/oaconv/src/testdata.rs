//! Real OA data for tests. Tests that need it return early (and say so)
//! when `vendor/` is missing, so the crate still tests without the pk3s.

use crate::vfs::Vfs;
use std::path::PathBuf;
use std::sync::OnceLock;

pub(crate) fn root() -> PathBuf {
    std::env::var_os("OA_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../vendor/oa088/openarena-0.8.8"))
}

/// The shared overlay of every pk3, opened once per test binary.
pub(crate) fn vfs() -> Option<&'static Vfs> {
    static VFS: OnceLock<Option<Vfs>> = OnceLock::new();
    VFS.get_or_init(|| Vfs::open(&root()).ok()).as_ref().or_else(|| {
        eprintln!("vendor/ missing: skipping real-data test");
        None
    })
}

pub(crate) fn bsp(map: &str) -> Option<crate::bsp::Bsp> {
    let bytes = vfs()?.read(&format!("maps/{map}.bsp"))?;
    Some(crate::bsp::Bsp::parse(&bytes).expect("parse bsp"))
}
