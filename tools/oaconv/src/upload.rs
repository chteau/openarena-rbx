//! `oaconv upload`: uploads what manifest.json lists and assets.lock.json
//! does not hold yet, recording each asset id as soon as it exists, so an
//! interrupted run resumes where it stopped.

use std::collections::BTreeMap;
use std::path::Path;
use std::time::{Duration, Instant};

use serde_json::{json, Value};

use crate::manifest::{self, AssetLock, Locked, Manifest, Upload, UploadKind};

const DESCRIPTION: &str = "OpenArena 0.8.8 (GPL-2.0) asset for openarena-rbx";
const CREATE_URL: &str = "https://apis.roblox.com/assets/v1/assets";
const PROCESSING_LIMIT: Duration = Duration::from_secs(120);

pub struct Options {
    pub dry_run: bool,
    /// Only this kind ("Model", "Image", "Audio").
    pub only: Option<crate::manifest::UploadKind>,
    /// Stop after this many uploads.
    pub limit: Option<usize>,
    /// Creator user id; default: the key's own user (introspection).
    pub user_id: Option<u64>,
    /// Path prefixes held back from upload (moderation review pending).
    pub hold: Vec<String>,
    /// Pause between two creates, to stay well under the Assets API limit.
    pub pace: Duration,
}

/// Uploads still to do: manifest order, filtered by kind, minus those the
/// lock holds with the same hash.
fn pending<'a>(m: &'a Manifest, lock: &AssetLock, opts: &Options) -> Vec<&'a Upload> {
    m.uploads
        .iter()
        .filter(|u| opts.only.is_none_or(|k| k == u.kind))
        .filter(|u| !opts.hold.iter().any(|h| u.path.starts_with(h.as_str())))
        .filter(|u| lock.get(&u.path).is_none_or(|l| l.sha256 != u.sha256))
        .take(opts.limit.unwrap_or(usize::MAX))
        .collect()
}

fn print_summary(m: &Manifest, todo: &[&Upload], lock: &AssetLock) {
    let mut per: BTreeMap<UploadKind, (usize, u64)> = BTreeMap::new();
    for u in todo {
        let e = per.entry(u.kind).or_default();
        e.0 += 1;
        e.1 += u.bytes;
    }
    for (kind, (n, bytes)) in &per {
        println!("{kind:?}: {n} files, {:.2} MB", *bytes as f64 / 1e6);
    }
    let total: u64 = todo.iter().map(|u| u.bytes).sum();
    let locked = m.uploads.len() - todo.len().min(m.uploads.len());
    println!(
        "total: {} files, {:.2} MB; already locked or skipped: {locked} ({} lock entries)",
        todo.len(),
        total as f64 / 1e6,
        lock.len()
    );
    for u in todo {
        println!("{:?} {}", u.kind, u.path);
    }
}

/// Returns how many assets were uploaded.
pub fn run(build: &Path, opts: &Options) -> Result<usize, String> {
    let manifest = Manifest::load(build)?;
    let mut lock = manifest::load_lock(build);
    let todo = pending(&manifest, &lock, opts);
    if opts.dry_run {
        print_summary(&manifest, &todo, &lock);
        return Ok(0);
    }
    if todo.is_empty() {
        return Ok(0);
    }
    let key = rbx_cloud::ApiKey::from_env_or_config()
        .ok_or("no Open Cloud key: set RBX_API_KEY or sign in with rbxstudio")?;
    let client = rbx_cloud::Client::new(Some(key.clone()));
    let user = match opts.user_id {
        Some(u) => u,
        None => {
            client
                .introspect()
                .map_err(|e| format!("introspect: {e}"))?
                .authorized_user_id
        }
    };
    let mut done = 0;
    for (i, u) in todo.into_iter().enumerate() {
        if i > 0 {
            std::thread::sleep(opts.pace);
        }
        let result = upload_one(build, u, &client, &key, user);
        match result {
            Ok(id) => {
                lock.insert(
                    u.path.clone(),
                    Locked {
                        sha256: u.sha256.clone(),
                        kind: u.kind,
                        asset_id: id,
                    },
                );
                manifest::save_lock(build, &lock).map_err(|e| format!("assets.lock.json: {e}"))?;
                println!("{:?} {} -> {id}", u.kind, u.path);
                done += 1;
            }
            Err(e) => {
                let _ = manifest::save_lock(build, &lock);
                return Err(format!("{}: {e}", u.path));
            }
        }
    }
    Ok(done)
}

fn upload_one(
    build: &Path,
    u: &Upload,
    client: &rbx_cloud::Client,
    key: &rbx_cloud::ApiKey,
    user: u64,
) -> Result<u64, String> {
    let bytes = std::fs::read(build.join(&u.path)).map_err(|e| e.to_string())?;
    if crate::luau::sha256_hex(&bytes) != u.sha256 {
        return Err("file differs from manifest sha256: rebuild first".into());
    }
    let file_name = u.path.rsplit('/').next().unwrap_or(&u.path);
    match u.kind {
        UploadKind::Model => client
            .create_model_asset(
                &u.name,
                DESCRIPTION,
                user,
                &rbx_cloud::ModelFile {
                    name: file_name,
                    content_type: "model/gltf-binary",
                    bytes: &bytes,
                },
            )
            .map_err(|e| e.to_string()),
        UploadKind::Image => client
            .create_image_asset(&u.name, DESCRIPTION, user, &bytes)
            .map_err(|e| e.to_string()),
        UploadKind::Audio => upload_audio(key.expose_secret(), &u.name, file_name, user, &bytes),
    }
}

fn audio_multipart(
    name: &str,
    file_name: &str,
    user: u64,
    bytes: &[u8],
    boundary: &str,
) -> Vec<u8> {
    let request = json!({
        "assetType": "Audio",
        "displayName": name,
        "description": DESCRIPTION,
        "creationContext": { "creator": { "userId": user.to_string() } },
    });
    let file_name: String = file_name
        .chars()
        .filter(|c| !matches!(c, '"' | '\r' | '\n'))
        .collect();
    let mut body = format!(
        "--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\n\
         Content-Type: application/json\r\n\r\n{request}\r\n\
         --{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"{file_name}\"\r\n\
         Content-Type: audio/ogg\r\n\r\n"
    )
    .into_bytes();
    body.extend_from_slice(bytes);
    body.extend_from_slice(format!("\r\n--{boundary}--\r\n").as_bytes());
    body
}

/// A boundary that does not occur in `bytes`.
fn boundary(bytes: &[u8]) -> String {
    (0u32..)
        .map(|n| format!("oaconv-{n:08x}"))
        .find(|c| !bytes.windows(c.len()).any(|w| w == c.as_bytes()))
        .expect("some boundary is absent from any finite body")
}

struct Reply {
    status: u16,
    retry_after: Option<u64>,
    body: Vec<u8>,
}

fn http(key: &str, url: &str, post: Option<(&str, &[u8])>) -> Result<Reply, String> {
    let sent = match post {
        Some((ct, body)) => ureq::post(url)
            .header("x-api-key", key)
            .header("Content-Type", ct)
            .config()
            .http_status_as_error(false)
            .build()
            .send(body),
        None => ureq::get(url)
            .header("x-api-key", key)
            .config()
            .http_status_as_error(false)
            .build()
            .call(),
    };
    let mut resp = sent.map_err(|e| e.to_string())?;
    let status = resp.status().as_u16();
    let retry_after = resp
        .headers()
        .get("retry-after")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.trim().parse().ok());
    let body = resp.body_mut().read_to_vec().map_err(|e| e.to_string())?;
    Ok(Reply {
        status,
        retry_after,
        body,
    })
}

fn json_reply(r: Reply) -> Result<Value, String> {
    if (200..300).contains(&r.status) {
        serde_json::from_slice(&r.body).map_err(|e| e.to_string())
    } else {
        Err(format!(
            "HTTP {}: {}",
            r.status,
            String::from_utf8_lossy(&r.body)
        ))
    }
}

fn upload_audio(
    key: &str,
    name: &str,
    file_name: &str,
    user: u64,
    bytes: &[u8],
) -> Result<u64, String> {
    let b = boundary(bytes);
    let body = audio_multipart(name, file_name, user, bytes, &b);
    let ct = format!("multipart/form-data; boundary={b}");
    let mut attempt = 0;
    let reply = loop {
        let r = http(key, CREATE_URL, Some((&ct, &body)))?;
        if r.status == 429 && attempt < 5 {
            attempt += 1;
            std::thread::sleep(Duration::from_secs(r.retry_after.unwrap_or(30)));
            continue;
        }
        break r;
    };
    let mut op = json_reply(reply)?;
    let started = Instant::now();
    let mut delay = Duration::from_millis(500);
    loop {
        if let Some(id) = parse_operation(&op)? {
            return Ok(id);
        }
        if started.elapsed() > PROCESSING_LIMIT {
            return Err(format!(
                "still processing after {}s",
                PROCESSING_LIMIT.as_secs()
            ));
        }
        std::thread::sleep(delay);
        delay = (delay * 2).min(Duration::from_secs(5));
        let url = operation_url(&op)?;
        op = json_reply(http(key, &url, None)?)?;
    }
}

fn operation_url(op: &Value) -> Result<String, String> {
    let id = op
        .get("operationId")
        .and_then(Value::as_str)
        .or_else(|| {
            op.get("path")
                .and_then(Value::as_str)
                .and_then(|p| p.strip_prefix("operations/"))
        })
        .filter(|id| !id.is_empty() && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-'))
        .ok_or("upload answered no operation")?;
    Ok(format!("https://apis.roblox.com/assets/v1/operations/{id}"))
}

/// `None` while the operation runs; the asset id once it is done.
fn parse_operation(op: &Value) -> Result<Option<u64>, String> {
    if !op.get("done").and_then(Value::as_bool).unwrap_or(false) {
        return Ok(None);
    }
    if let Some(err) = op.get("error").filter(|e| !e.is_null()) {
        let msg = err
            .get("message")
            .and_then(Value::as_str)
            .map_or_else(|| err.to_string(), str::to_string);
        return Err(msg);
    }
    let resp = op.get("response").unwrap_or(&Value::Null);
    let state = resp
        .pointer("/moderationResult/moderationState")
        .and_then(Value::as_str)
        .unwrap_or("");
    if state.to_ascii_lowercase().contains("rejected") {
        return Err("Roblox moderation rejected the upload".into());
    }
    match resp.get("assetId") {
        Some(Value::Number(n)) => n.as_u64(),
        Some(Value::String(s)) => s.parse().ok(),
        _ => None,
    }
    .map(Some)
    .ok_or_else(|| "finished upload names no assetId".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn up(path: &str, kind: UploadKind, sha: &str) -> Upload {
        Upload {
            path: path.into(),
            kind,
            sha256: sha.into(),
            bytes: 1_000_000,
            name: path.into(),
        }
    }

    fn fake() -> Manifest {
        Manifest {
            uploads: vec![
                up("a.glb", UploadKind::Model, "1"),
                up("b.png", UploadKind::Image, "2"),
                up("c.ogg", UploadKind::Audio, "3"),
                up("d.glb", UploadKind::Model, "4"),
            ],
            ..Default::default()
        }
    }

    fn opts(only: Option<UploadKind>, limit: Option<usize>) -> Options {
        Options {
            dry_run: true,
            only,
            limit,
            user_id: None,
            hold: vec!["images/models/gibs/".into()],
            pace: Duration::ZERO,
        }
    }

    fn locked(sha: &str) -> Locked {
        Locked {
            sha256: sha.into(),
            kind: UploadKind::Model,
            asset_id: 9,
        }
    }

    #[test]
    fn pending_skips_locked_and_reuploads_changed() {
        let m = fake();
        let mut lock = AssetLock::new();
        lock.insert("a.glb".into(), locked("1"));
        lock.insert("d.glb".into(), locked("old"));
        let p: Vec<_> = pending(&m, &lock, &opts(None, None))
            .iter()
            .map(|u| u.path.as_str())
            .collect();
        assert_eq!(p, ["b.png", "c.ogg", "d.glb"]);
    }

    #[test]
    fn pending_filters_and_limits() {
        let m = fake();
        let lock = AssetLock::new();
        let p = pending(&m, &lock, &opts(Some(UploadKind::Model), None));
        assert_eq!(p.len(), 2);
        let p = pending(&m, &lock, &opts(None, Some(3)));
        assert_eq!(p.len(), 3);
        assert_eq!(p[2].path, "c.ogg");
    }

    #[test]
    fn dry_run_needs_no_key() {
        let dir = std::env::temp_dir().join(format!("oaconv-upload-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        fake().save(&dir).unwrap();
        assert_eq!(run(&dir, &opts(None, None)), Ok(0));
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn audio_body_has_request_and_file() {
        let body = audio_multipart("Snd", "x.ogg", 42, b"OggS data", "B");
        let text = String::from_utf8(body).unwrap();
        assert!(text.starts_with("--B\r\nContent-Disposition: form-data; name=\"request\""));
        assert!(text.contains("\"assetType\":\"Audio\""));
        assert!(text.contains("\"userId\":\"42\""));
        assert!(text.contains(
            "filename=\"x.ogg\"\r\nContent-Type: audio/ogg\r\n\r\nOggS data\r\n--B--\r\n"
        ));
    }

    #[test]
    fn operation_parsing() {
        assert_eq!(parse_operation(&json!({"done": false})), Ok(None));
        assert_eq!(
            parse_operation(&json!({"done": true, "response": {"assetId": 7}})),
            Ok(Some(7))
        );
        assert_eq!(
            parse_operation(&json!({"done": true, "response": {"assetId": "12"}})),
            Ok(Some(12))
        );
        assert_eq!(
            parse_operation(&json!({"done": true, "error": {"message": "bad"}})),
            Err("bad".to_string())
        );
        assert!(operation_url(&json!({"path": "operations/a-1"}))
            .unwrap()
            .ends_with("/a-1"));
    }
}
