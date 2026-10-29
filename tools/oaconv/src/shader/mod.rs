//! Q3 shader scripts (`scripts/*.shader`): parsing, the engine's implicit
//! shaders, and the render class each shader gets in the port.
//! Parsing follows ioquake3 `renderergl1/tr_shader.c` (GPL-2.0).

use serde::Serialize;
use std::collections::BTreeMap;

use crate::vfs::Vfs;

mod classify;
mod parse;

pub use classify::{classify, stage_animated};
pub use parse::{parse_text, tokenize};

/// How the port draws a surface using this shader.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ShaderClass {
    #[default]
    /// Static stages only: diffuse x lightmap (x static extra stages) is baked into the atlas.
    Opaque,
    Sky,
    AlphaTest,
    /// Translucent first stage (blendFunc add/filter/blend), fog, portals.
    Blend,
    /// tcMod scroll/rotate/turb/stretch, animMap, videoMap, rgbGen/alphaGen wave,
    /// tcGen environment, rgbGen entity...: the client animates it.
    Animated,
    /// Any deformVertexes.
    Deform,
    /// Never drawn: nodraw, flares, `noshader`, shaders without stages.
    Nodraw,
}

/// One stage (`{ ... }` block). Directive arguments are kept as lowercased
/// tokens so the client can animate them exactly as written.
#[derive(Clone, Debug, Default, PartialEq, Serialize)]
pub struct Stage {
    /// `map`/`clampMap`: one entry. `animMap`: every frame. Special names
    /// `$lightmap` and `$whiteimage` are kept as written (lowercased).
    pub maps: Vec<String>,
    pub clamp: bool,
    /// `animMap` frequency.
    pub anim_freq: Option<f32>,
    pub video: Option<String>,
    /// Normalised to `[src, dst]` GL names ("gl_one", "gl_zero", ...);
    /// shorthands `add`, `filter`, `blend` are expanded as tr_shader.c does.
    /// `None` = no blendFunc (opaque replace).
    pub blend: Option<[String; 2]>,
    /// Tokens after `rgbGen`, e.g. `["wave","sin","0","1","0","1"]`. Empty when the
    /// script has none; `rgb_gen_default` then names what the engine picks.
    pub rgb_gen: Vec<String>,
    /// "identity" or "identitylighting": tr_shader.c's default when `rgb_gen` is empty.
    pub rgb_gen_default: String,
    pub alpha_gen: Vec<String>,
    /// Tokens after `tcGen`/`texGen`; empty = base (lightmap for `$lightmap`).
    pub tc_gen: Vec<String>,
    /// Each `tcMod` line's tokens after `tcMod`, in order.
    pub tc_mods: Vec<Vec<String>>,
    /// "gt0", "lt128", "ge128".
    pub alpha_func: Option<String>,
    pub depth_func: Option<String>,
    pub depth_write: bool,
    pub detail: bool,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize)]
pub struct Shader {
    /// Lowercased, no extension, as surfaces reference it.
    pub name: String,
    /// `scripts/x.shader`, or `<implicit>` for a shader the engine makes from an image.
    pub source: String,
    pub surfaceparms: Vec<String>,
    /// "front" (default), "back" or "none" ("twosided"/"disable" map to "none").
    pub cull: String,
    pub sort: Option<String>,
    /// `skyParms` tokens: `[farbox, cloudheight, nearbox]`.
    pub sky_parms: Option<Vec<String>>,
    /// Each `deformVertexes` line's tokens after the keyword.
    pub deforms: Vec<Vec<String>>,
    pub fog_parms: Option<Vec<String>>,
    pub polygon_offset: bool,
    pub portal: bool,
    pub entity_merge: bool,
    /// Directives the engine reads that have no field above (`light`, `q3map_*` are dropped).
    pub other: Vec<Vec<String>>,
    pub stages: Vec<Stage>,
    pub class: ShaderClass,
}

/// Every scripted shader, with the engine's precedence when two files
/// define the same name.
#[derive(Default)]
pub struct ShaderSet {
    pub shaders: BTreeMap<String, Shader>,
}

impl ShaderSet {
    /// Parses every `scripts/*.shader` in the VFS.
    pub fn load(vfs: &Vfs) -> Self {
        parse::load(vfs)
    }

    pub fn get(&self, name: &str) -> Option<&Shader> {
        self.shaders.get(&strip_ext(name))
    }

    /// The scripted shader, or the implicit one `CreateDefaultShader` builds
    /// from the image of the same name. `lightmapped`: the surface has a
    /// lightmap (index >= 0); otherwise the implicit stage is vertex lit
    /// (`rgbGen exactVertex`). A missing image gives a stageless (Nodraw) shader.
    pub fn resolve(&self, name: &str, lightmapped: bool, vfs: &Vfs) -> Shader {
        if let Some(s) = self.get(name) {
            return s.clone();
        }
        parse::implicit(name, lightmapped, vfs)
    }
}

pub fn strip_ext(name: &str) -> String {
    let lower = name.to_ascii_lowercase().replace('\\', "/");
    match lower.rfind('.') {
        Some(dot) if !lower[dot..].contains('/') => lower[..dot].to_string(),
        _ => lower,
    }
}
