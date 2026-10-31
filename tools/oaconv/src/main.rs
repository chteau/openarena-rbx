//! `oaconv convert | tone | preview | upload | fetch | publish`. See docs/conv-notes.md.

mod pipeline;

use std::path::{Path, PathBuf};

use oaconv::manifest::UploadKind;

const USAGE: &str = "\
usage:
  oaconv convert [--repo DIR] [--out DIR] [--maps a,b] [--only maps,models,images,sounds,shaders] [--max-pages N]
  oaconv tone [--repo DIR] [--preview DIR]
  oaconv preview --map NAME [--spawn N | --eye \"x y z yaw\" | --top] [--out FILE.png] [--size WxH] [--repo DIR]
  oaconv upload [--build DIR] [--dry-run] [--only Model|Image|Audio] [--limit N] [--user-id ID]
                [--hold FILE] [--pace-ms MS]
  oaconv fetch --out DIR ID...
  oaconv publish --universe ID --place ID [--saved] FILE.rbxl";

struct Args(Vec<String>);

impl Args {
    fn flag(&mut self, name: &str) -> bool {
        let at = self.0.iter().position(|a| a == name);
        at.map(|i| self.0.remove(i)).is_some()
    }
    fn value(&mut self, name: &str) -> Option<String> {
        let i = self.0.iter().position(|a| a == name)?;
        self.0.remove(i);
        (i < self.0.len()).then(|| self.0.remove(i))
    }
    fn number<T: std::str::FromStr>(&mut self, name: &str) -> Result<Option<T>, String> {
        self.value(name)
            .map(|v| v.parse().map_err(|_| format!("bad {name} {v}")))
            .transpose()
    }
    fn finish(self) -> Result<(), String> {
        match self.0.first() {
            Some(extra) => Err(format!("unexpected argument {extra}\n{USAGE}")),
            None => Ok(()),
        }
    }
}

/// The repo root: `--repo`, else the nearest ancestor of the cwd holding `vendor/oa088`.
fn repo_root(arg: Option<String>) -> Result<PathBuf, String> {
    if let Some(r) = arg {
        return Ok(PathBuf::from(r));
    }
    let cwd = std::env::current_dir().map_err(|e| e.to_string())?;
    cwd.ancestors()
        .find(|p| p.join("vendor/oa088").exists())
        .map(Path::to_path_buf)
        .ok_or_else(|| "no vendor/oa088 above the current directory; pass --repo".into())
}

fn list(v: Option<String>) -> Option<Vec<String>> {
    v.map(|m| m.split(',').map(str::to_string).collect())
}

fn run() -> Result<(), String> {
    let mut raw: Vec<String> = std::env::args().skip(1).collect();
    if raw.is_empty() {
        return Err(USAGE.into());
    }
    let command = raw.remove(0);
    let mut args = Args(raw);
    match command.as_str() {
        "convert" => {
            let repo = repo_root(args.value("--repo"))?;
            let opts = pipeline::Options {
                out: args
                    .value("--out")
                    .map(PathBuf::from)
                    .unwrap_or_else(|| repo.join("build")),
                maps: list(args.value("--maps")),
                only: list(args.value("--only")),
                max_pages: args.number("--max-pages")?,
                root: oaconv::vfs::default_root(&repo),
                overlay: Some(repo.join(oaconv::vfs::OVERLAY)).filter(|d| d.is_dir()),
            };
            args.finish()?;
            pipeline::convert(&opts)
        }
        "tone" => {
            let repo = repo_root(args.value("--repo"))?;
            let preview = args.value("--preview").map(PathBuf::from);
            args.finish()?;
            let written = oaconv::md3edit::run(&repo, preview.as_deref())?;
            println!(
                "wrote {} files under {}",
                written.len(),
                oaconv::vfs::OVERLAY
            );
            Ok(())
        }
        "preview" => {
            let repo = repo_root(args.value("--repo"))?;
            let map = args.value("--map").ok_or("--map is required")?;
            let spawn: Option<usize> = args.number("--spawn")?;
            let top = args.flag("--top");
            let eye = match args.value("--eye") {
                Some(v) => {
                    let n: Vec<f32> = v
                        .split_whitespace()
                        .filter_map(|x| x.parse().ok())
                        .collect();
                    Some(<[f32; 4]>::try_from(n).map_err(|_| "--eye takes \"x y z yaw\"")?)
                }
                None => None,
            };
            let out = args
                .value("--out")
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from(format!("{map}.png")));
            let (w, h) = match args.value("--size") {
                Some(s) => {
                    let (w, h) = s.split_once('x').ok_or("bad --size")?;
                    (
                        w.parse().map_err(|_| "bad --size")?,
                        h.parse().map_err(|_| "bad --size")?,
                    )
                }
                None => (1280, 720),
            };
            args.finish()?;
            let view = match (top, eye) {
                (true, _) => pipeline::View::Top,
                (_, Some(e)) => pipeline::View::Eye(e),
                _ => pipeline::View::Spawn(spawn.unwrap_or(0)),
            };
            pipeline::preview(&oaconv::vfs::default_root(&repo), &map, view, &out, w, h)
        }
        "upload" => {
            let build = match args.value("--build") {
                Some(b) => PathBuf::from(b),
                None => repo_root(None)?.join("build"),
            };
            let only = match args.value("--only").as_deref() {
                None => None,
                Some("Model") => Some(UploadKind::Model),
                Some("Image") => Some(UploadKind::Image),
                Some("Audio") => Some(UploadKind::Audio),
                Some(other) => {
                    return Err(format!("--only {other}: expected Model, Image or Audio"))
                }
            };
            let opts = oaconv::upload::Options {
                dry_run: args.flag("--dry-run"),
                only,
                limit: args.number("--limit")?,
                user_id: args.number("--user-id")?,
                hold: match args.value("--hold") {
                    Some(f) => std::fs::read_to_string(&f)
                        .map_err(|e| format!("--hold {f}: {e}"))?
                        .lines()
                        .map(str::trim)
                        .filter(|l| !l.is_empty() && !l.starts_with('#'))
                        .map(String::from)
                        .collect(),
                    None => Vec::new(),
                },
                pace: std::time::Duration::from_millis(args.number("--pace-ms")?.unwrap_or(1500)),
            };
            args.finish()?;
            let n = oaconv::upload::run(&build, &opts)?;
            println!("uploaded {n}");
            Ok(())
        }
        "fetch" => {
            let out = PathBuf::from(args.value("--out").ok_or("--out is required")?);
            let ids = args
                .0
                .iter()
                .map(|v| v.parse().map_err(|_| format!("bad asset id {v}")))
                .collect::<Result<Vec<u64>, String>>()?;
            oaconv::upload::fetch(&out, &ids)
        }
        "publish" => {
            let universe: u64 = args.number("--universe")?.ok_or("--universe is required")?;
            let place: u64 = args.number("--place")?.ok_or("--place is required")?;
            let saved = args.flag("--saved");
            let file = match args.0.len() {
                1 => PathBuf::from(args.0.remove(0)),
                _ => return Err(USAGE.into()),
            };
            let version = oaconv::upload::publish(&file, universe, place, saved)?;
            println!("place {place}: version {version}");
            Ok(())
        }
        _ => Err(USAGE.into()),
    }
}

fn main() {
    if let Err(e) = run() {
        eprintln!("oaconv: {e}");
        std::process::exit(1);
    }
}
