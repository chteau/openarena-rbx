//! `oaconv upload`: uploads what manifest.json lists and assets.lock.json
//! does not hold yet, recording each asset id as soon as it exists, so an
//! interrupted run resumes where it stopped.

use std::path::Path;

pub struct Options {
    pub dry_run: bool,
    /// Only this kind ("Model", "Image", "Audio").
    pub only: Option<crate::manifest::UploadKind>,
    /// Stop after this many uploads.
    pub limit: Option<usize>,
    /// Creator user id; default: the key's own user (introspection).
    pub user_id: Option<u64>,
}

/// Returns how many assets were uploaded.
pub fn run(_build: &Path, _opts: &Options) -> Result<usize, String> {
    todo!()
}
