//! Sound effects packed into long OGG atlases with silence gaps, because
//! Roblox caps audio uploads per month. Encoding uses `ffmpeg` (libvorbis).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde::Serialize;

/// Roblox's per-audio-asset duration cap is 7 minutes.
pub const MAX_ATLAS_SECONDS: f64 = 420.0;
pub const GAP_SECONDS: f64 = 0.25;
pub const SAMPLE_RATE: u32 = 44_100;

pub struct Clip {
    /// OA path, lowercased (`sound/weapons/rocket/rocklf1a.wav`).
    pub path: String,
    pub bytes: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct IndexEntry {
    /// Atlas file name, e.g. `sfx_00.ogg`.
    pub atlas: String,
    pub start: f64,
    pub length: f64,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Atlas {
    pub file: String,
    pub seconds: f64,
    pub clips: usize,
}

/// Fails with a clear message when `ffmpeg` is not on PATH or lacks libvorbis.
pub fn check_ffmpeg() -> Result<(), String> {
    todo!()
}

/// Decodes every clip to mono f32 PCM at [`SAMPLE_RATE`], packs them in path
/// order into atlases of at most [`MAX_ATLAS_SECONDS`] with [`GAP_SECONDS`] of
/// silence after each clip, writes `out_dir/sfx_NN.ogg`, and returns the
/// atlases and the index (OA path -> atlas, start, length in seconds).
pub fn build_atlases(_clips: &[Clip], _out_dir: &Path) -> Result<(Vec<Atlas>, BTreeMap<String, IndexEntry>), String> {
    todo!()
}

/// Music tracks are not packed: copied as-is when OGG, else re-encoded to OGG.
pub fn write_music(_clip: &Clip, _out_dir: &Path) -> Result<PathBuf, String> {
    todo!()
}
