//! The player roster the Roblox port ships, from `roster.json` (shared with
//! `tools/roster.py`, which applies the same path rules to the game's file
//! packs). `oaconv convert` drops every excluded path from its VFS, so an
//! excluded model produces no texture, icon, md3, sound or shader output.

use std::collections::BTreeMap;
use std::sync::OnceLock;

use serde::Deserialize;

#[derive(Deserialize)]
pub struct Roster {
    /// Kept model (or texture folder) -> why it passed review.
    pub kept: BTreeMap<String, String>,
    /// Excluded model or `model/skin` -> why.
    pub excluded: BTreeMap<String, String>,
    /// Path prefixes an excluded `model/skin` owns (its textures and shaders).
    #[serde(default)]
    pub files: BTreeMap<String, Vec<String>>,
    /// Dropped texture prefix -> the kept one shipped `.skin` files name instead.
    #[serde(default)]
    pub retexture: BTreeMap<String, String>,
    /// Path prefix -> why it ships only from the toned overlay
    /// (`assets/toned`), never from the pk3s.
    #[serde(default)]
    pub toned: BTreeMap<String, String>,
}

impl Roster {
    pub fn get() -> &'static Roster {
        static R: OnceLock<Roster> = OnceLock::new();
        R.get_or_init(|| serde_json::from_str(include_str!("../roster.json")).expect("roster.json"))
    }

    /// Whether `path` (a pk3 path or a shader name) belongs to an excluded
    /// model or skin.
    pub fn excludes(&self, path: &str) -> bool {
        let p = path.to_ascii_lowercase();
        self.excluded.keys().any(|key| match key.split_once('/') {
            Some((model, skin)) => {
                let dir = format!("models/players/{model}/");
                p.strip_prefix(&dir).is_some_and(|f| {
                    ["head_", "upper_", "lower_"]
                        .iter()
                        .any(|part| f == format!("{part}{skin}.skin"))
                        || ["icon_", "iconh_"]
                            .iter()
                            .any(|i| f.starts_with(&format!("{i}{skin}.")))
                }) || self
                    .files
                    .get(key)
                    .is_some_and(|fs| fs.iter().any(|f| p.starts_with(&f.to_ascii_lowercase())))
            }
            None => {
                [
                    format!("models/players/{key}/"),
                    format!("models/players/heads/{key}/"),
                    format!("sound/player/{key}/"),
                ]
                .iter()
                .any(|d| p.starts_with(d.as_str()))
                    || p == format!("scripts/{key}.vc")
                    || p == format!("scripts/player_{key}.shader")
            }
        })
    }

    /// Whether `path` may ship only from the toned overlay.
    pub fn toned_only(&self, path: &str) -> bool {
        let p = path.to_ascii_lowercase();
        self.toned
            .keys()
            .any(|t| p.starts_with(&t.to_ascii_lowercase()))
    }

    /// A `.skin` texture with a dropped prefix swapped for its kept one.
    pub fn retexture(&self, texture: &str) -> String {
        let low = texture.to_ascii_lowercase();
        self.retexture
            .iter()
            .find_map(|(from, to)| {
                low.starts_with(&from.to_ascii_lowercase())
                    .then(|| format!("{to}{}", &texture[from.len()..]))
            })
            .unwrap_or_else(|| texture.to_string())
    }

    /// Whether a build output (`images/<pk3 path>.png`, `md3/<pk3 dir>/...`)
    /// was made from an excluded path.
    pub fn excludes_output(&self, path: &str) -> bool {
        let Some((_, rest)) = path.split_once('/') else {
            return false;
        };
        let stem = rest.rsplit_once('.').map_or(rest, |(s, _)| s);
        self.excludes(rest)
            || ["tga", "jpg", "jpeg", "png"]
                .iter()
                .any(|e| self.excludes(&format!("{stem}.{e}")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn excludes_models_skins_and_their_files() {
        let r = Roster::get();
        for p in [
            "models/players/neko/lower.md3",
            "Models/Players/Angelyss/retro.tga",
            "models/players/hnt/skin.tga",
            "models/players/heads/kyonshi/kyonshi.md3",
            "sound/player/major/death1.wav",
            "scripts/sorceress.vc",
            "scripts/player_neko.shader",
            "models/players/merman/skin",
            "models/players/beret/upper_headcrash.skin",
            "models/players/beret/icon_headcrash.tga",
            "models/players/beret/headcrash1.jpg",
            "models/players/beret/headcrash2",
            "models/players/beret/upper_macho.skin",
            "models/players/beret/icon_macho.tga",
            "models/players/sarge/lower_classicblue.skin",
            "models/players/sarge/icon_classicred.tga",
            "models/players/grism/morphedg.tga",
            "models/players/grism/morphed2.tga",
        ] {
            assert!(r.excludes(p), "{p}");
        }
        for p in [
            "models/players/sarge/upper.md3",
            "models/players/grism/enkiskin.tga",
            "models/players/gargoyle/morphedgarg.tga",
            "models/players/heads/sergei/sergei.md3",
            "models/players/beret/upper_default.skin",
            "models/players/beret/skin2red.tga",
            "models/players/beret/skin1.tga",
            "models/players/beret/skin1red.tga",
            "models/players/sarge/upper_red.skin",
            "sound/player/sarge/death1.wav",
            "scripts/sarge.vc",
            "models/players/sergei/upper.md3",
        ] {
            assert!(!r.excludes(p), "{p}");
        }
        assert!(r.excludes_output("images/models/players/beret/headcrash1.png"));
        assert!(r.excludes_output("md3/models/players/neko/lower_static_0.glb"));
        assert!(!r.excludes_output("images/models/players/beret/skin1.png"));
        assert!(!r.excludes_output("images/models/players/beret/skin2.png"));
        for p in ["skin1.tga", "skin1red.tga", "skin1blue.tga"] {
            let p = format!("models/players/beret/{p}");
            assert!(r.toned_only(&p), "{p}");
            assert_eq!(r.retexture(&p), p, "beret wears skin1* again");
        }
        assert!(!r.toned_only("models/players/beret/skin2.tga"));
        for (from, to) in &r.retexture {
            assert!(
                r.excludes(from) && !r.excludes(to),
                "retexture {from} -> {to}"
            );
        }
        assert!(!r.excludes_output("sound/sfx_00.ogg"));
        for k in r.kept.keys() {
            assert!(!r.excluded.contains_key(k), "{k} is both kept and excluded");
        }
    }
}
