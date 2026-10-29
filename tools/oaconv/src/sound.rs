//! Sound effects packed into long OGG atlases with silence gaps, because
//! Roblox caps audio uploads per month. Encoding uses `ffmpeg` (libvorbis).

use std::collections::BTreeMap;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use rayon::prelude::*;
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

/// Runs ffmpeg, feeding `input` on stdin from a separate thread so a full
/// stdout pipe cannot deadlock against a full stdin pipe.
fn run_ffmpeg(args: &[&str], input: Vec<u8>) -> Result<Vec<u8>, String> {
    let mut child = Command::new("ffmpeg")
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("cannot run ffmpeg: {e}"))?;
    let mut stdin = child.stdin.take().expect("piped stdin");
    let writer = std::thread::spawn(move || {
        // A write error means ffmpeg exited early; its stderr explains why.
        let _ = stdin.write_all(&input);
    });
    let out = child
        .wait_with_output()
        .map_err(|e| format!("ffmpeg failed: {e}"))?;
    let _ = writer.join();
    if out.status.success() {
        Ok(out.stdout)
    } else {
        Err(String::from_utf8_lossy(&out.stderr).trim().to_string())
    }
}

/// Fails with a clear message when `ffmpeg` is not on PATH or lacks libvorbis.
pub fn check_ffmpeg() -> Result<(), String> {
    let out = Command::new("ffmpeg")
        .args(["-hide_banner", "-encoders"])
        .output()
        .map_err(|e| format!("ffmpeg not found on PATH: {e}"))?;
    if String::from_utf8_lossy(&out.stdout).contains("libvorbis") {
        Ok(())
    } else {
        Err(
            "ffmpeg lacks the libvorbis encoder; install an ffmpeg build with libvorbis"
                .to_string(),
        )
    }
}

fn decode(clip: &Clip) -> Result<Vec<f32>, String> {
    let args = [
        "-v", "error", "-i", "pipe:0", "-f", "f32le", "-ac", "1", "-ar", "44100", "pipe:1",
    ];
    let raw = run_ffmpeg(&args, clip.bytes.clone())
        .map_err(|e| format!("{}: ffmpeg decode failed: {e}", clip.path))?;
    Ok(raw
        .as_chunks::<4>()
        .0
        .iter()
        .map(|b| f32::from_le_bytes(*b))
        .collect())
}

fn gap_samples() -> usize {
    (GAP_SECONDS * SAMPLE_RATE as f64).round() as usize
}

/// One atlas layout: `(clip index, start sample)` pairs and the total length.
struct Layout {
    placed: Vec<(usize, usize)>,
    total: usize,
}

/// Packs clips of the given sample lengths in order, starting a new atlas when
/// the next clip plus its gap would exceed `max_seconds`.
fn pack(lens: &[usize], max_seconds: f64) -> Result<Vec<Layout>, String> {
    let max = (max_seconds * SAMPLE_RATE as f64) as usize;
    let gap = gap_samples();
    let mut out: Vec<Layout> = Vec::new();
    for (i, &len) in lens.iter().enumerate() {
        if len > max {
            return Err(format!(
                "clip #{i} is {len} samples, longer than the {max_seconds}s atlas limit"
            ));
        }
        let fits = out.last().is_some_and(|l| l.total + len + gap <= max);
        if !fits {
            out.push(Layout {
                placed: Vec::new(),
                total: 0,
            });
        }
        let cur = out.last_mut().expect("layout exists");
        cur.placed.push((i, cur.total));
        cur.total += len + gap;
    }
    Ok(out)
}

fn f32_bytes(samples: &[f32]) -> Vec<u8> {
    samples.iter().flat_map(|s| s.to_le_bytes()).collect()
}

/// Decodes every clip to mono f32 PCM at [`SAMPLE_RATE`], packs them in path
/// order into atlases of at most [`MAX_ATLAS_SECONDS`] with [`GAP_SECONDS`] of
/// silence after each clip, writes `out_dir/sfx_NN.ogg`, and returns the
/// atlases and the index (OA path -> atlas, start, length in seconds).
pub fn build_atlases(
    clips: &[Clip],
    out_dir: &Path,
) -> Result<(Vec<Atlas>, BTreeMap<String, IndexEntry>), String> {
    let decoded: Vec<Vec<f32>> = clips.par_iter().map(decode).collect::<Result<_, _>>()?;
    let lens: Vec<usize> = decoded.iter().map(Vec::len).collect();
    let layouts = pack(&lens, MAX_ATLAS_SECONDS)?;
    std::fs::create_dir_all(out_dir).map_err(|e| format!("{}: {e}", out_dir.display()))?;
    let rate = SAMPLE_RATE as f64;
    let mut atlases = Vec::new();
    let mut index = BTreeMap::new();
    for (n, layout) in layouts.iter().enumerate() {
        let file = format!("sfx_{n:02}.ogg");
        let mut pcm = Vec::with_capacity(layout.total);
        for &(i, start) in &layout.placed {
            debug_assert_eq!(pcm.len(), start);
            pcm.extend_from_slice(&decoded[i]);
            pcm.resize(start + lens[i] + gap_samples(), 0.0);
            index.insert(
                clips[i].path.clone(),
                IndexEntry {
                    atlas: file.clone(),
                    start: start as f64 / rate,
                    length: lens[i] as f64 / rate,
                },
            );
        }
        let out_path = out_dir.join(&file);
        let out_str = out_path.to_string_lossy().into_owned();
        let args = [
            "-v",
            "error",
            "-y",
            "-f",
            "f32le",
            "-ar",
            "44100",
            "-ac",
            "1",
            "-i",
            "pipe:0",
            "-c:a",
            "libvorbis",
            "-q:a",
            "5",
            // Fixed Ogg serials and no encoder tag: same input, same bytes,
            // so the upload lock keeps matching across converts.
            "-fflags",
            "+bitexact",
            "-flags:a",
            "+bitexact",
            &out_str,
        ];
        run_ffmpeg(&args, f32_bytes(&pcm))
            .map_err(|e| format!("{file}: ffmpeg encode failed: {e}"))?;
        atlases.push(Atlas {
            file,
            seconds: layout.total as f64 / rate,
            clips: layout.placed.len(),
        });
    }
    Ok((atlases, index))
}

/// Music tracks are not packed: copied as-is when OGG, else re-encoded to OGG.
pub fn write_music(clip: &Clip, out_dir: &Path) -> Result<PathBuf, String> {
    let name = Path::new(&clip.path)
        .file_name()
        .ok_or_else(|| format!("{}: no file name", clip.path))?;
    std::fs::create_dir_all(out_dir).map_err(|e| format!("{}: {e}", out_dir.display()))?;
    let is_ogg = Path::new(&clip.path)
        .extension()
        .is_some_and(|e| e.eq_ignore_ascii_case("ogg"));
    if is_ogg {
        let dest = out_dir.join(name);
        std::fs::write(&dest, &clip.bytes).map_err(|e| format!("{}: {e}", dest.display()))?;
        return Ok(dest);
    }
    let dest = out_dir.join(name).with_extension("ogg");
    let dest_str = dest.to_string_lossy().into_owned();
    let args = [
        "-v",
        "error",
        "-y",
        "-i",
        "pipe:0",
        "-c:a",
        "libvorbis",
        "-q:a",
        "5",
        "-fflags",
        "+bitexact",
        "-flags:a",
        "+bitexact",
        &dest_str,
    ];
    run_ffmpeg(&args, clip.bytes.clone())
        .map_err(|e| format!("{}: ffmpeg encode failed: {e}", clip.path))?;
    Ok(dest)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wav(seconds: f64) -> Vec<u8> {
        let n = (seconds * SAMPLE_RATE as f64) as usize;
        let data_len = (n * 2) as u32;
        let mut v = Vec::new();
        v.extend_from_slice(b"RIFF");
        v.extend_from_slice(&(36 + data_len).to_le_bytes());
        v.extend_from_slice(b"WAVEfmt ");
        v.extend_from_slice(&16u32.to_le_bytes());
        v.extend_from_slice(&1u16.to_le_bytes());
        v.extend_from_slice(&1u16.to_le_bytes());
        v.extend_from_slice(&SAMPLE_RATE.to_le_bytes());
        v.extend_from_slice(&(SAMPLE_RATE * 2).to_le_bytes());
        v.extend_from_slice(&2u16.to_le_bytes());
        v.extend_from_slice(&16u16.to_le_bytes());
        v.extend_from_slice(b"data");
        v.extend_from_slice(&data_len.to_le_bytes());
        for i in 0..n {
            let s = ((i as f64 * 0.05).sin() * 8000.0) as i16;
            v.extend_from_slice(&s.to_le_bytes());
        }
        v
    }

    fn have_ffmpeg() -> bool {
        let ok = check_ffmpeg().is_ok();
        if !ok {
            eprintln!("ffmpeg with libvorbis missing: skipping");
        }
        ok
    }

    #[test]
    fn packs_three_clips_into_one_atlas() {
        if !have_ffmpeg() {
            return;
        }
        let clips: Vec<Clip> = [("a.wav", 1.0), ("b.wav", 0.5), ("c.wav", 2.0)]
            .iter()
            .map(|(p, s)| Clip {
                path: p.to_string(),
                bytes: wav(*s),
            })
            .collect();
        let dir = std::env::temp_dir().join(format!("oaconv_sound_{}", std::process::id()));
        let result = build_atlases(&clips, &dir);
        let (atlases, index) = match result {
            Ok(r) => r,
            Err(e) => {
                let _ = std::fs::remove_dir_all(&dir);
                panic!("{e}");
            }
        };
        assert_eq!(atlases.len(), 1);
        for (path, start, len) in [
            ("a.wav", 0.0, 1.0),
            ("b.wav", 1.25, 0.5),
            ("c.wav", 2.0, 2.0),
        ] {
            let e = &index[path];
            assert!((e.start - start).abs() < 1e-3, "{path} start {}", e.start);
            assert!((e.length - len).abs() < 1e-3, "{path} length {}", e.length);
        }
        let ogg = dir.join("sfx_00.ogg");
        assert!(ogg.exists());
        let probe = Command::new("ffprobe")
            .args([
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-of",
                "csv=p=0",
            ])
            .arg(&ogg)
            .output();
        let _ = std::fs::remove_dir_all(&dir);
        if let Ok(p) = probe {
            let d: f64 = String::from_utf8_lossy(&p.stdout)
                .trim()
                .parse()
                .expect("duration");
            assert!((d - atlases[0].seconds).abs() < 0.1, "duration {d}");
        }
    }

    #[test]
    fn splits_when_over_max() {
        let r = SAMPLE_RATE as usize;
        let layouts = pack(&[r, r, r], 2.5).unwrap();
        assert_eq!(layouts.len(), 2);
        assert_eq!(layouts[0].placed.len(), 2);
        let layouts = pack(&[r, r / 4, r], 2.0).unwrap();
        assert_eq!(layouts.len(), 2);
        assert_eq!(layouts[0].placed, vec![(0, 0), (1, r + gap_samples())]);
        assert!(pack(&[3 * r], 2.0).is_err());
    }

    #[test]
    fn decodes_real_wav() {
        if !have_ffmpeg() {
            return;
        }
        let Some(vfs) = crate::testdata::vfs() else {
            return;
        };
        let Some(path) = vfs.list("sound/weapons/", &[".wav"]).into_iter().next() else {
            return;
        };
        let clip = Clip {
            bytes: vfs.read(&path).expect("read"),
            path,
        };
        assert!(!decode(&clip).expect("decode").is_empty());
    }
}
