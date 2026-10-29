//! MD3 models (ioquake3 `qcommon/qfiles.h` md3 structs, GPL-2.0),
//! `animation.cfg` and `.skin` files. Runtime layout: docs/formats/md3.md.

use serde::Serialize;

use crate::mesh::Mesh;

/// `MD3_XYZ_SCALE`: stored positions are 1/64 unit.
pub const XYZ_SCALE: f32 = 1.0 / 64.0;

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Md3Frame {
    pub bounds: [[f32; 3]; 2],
    pub local_origin: [f32; 3],
    pub radius: f32,
    pub name: String,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Md3Tag {
    pub name: String,
    pub origin: [f32; 3],
    pub axis: [[f32; 3]; 3],
}

#[derive(Clone, Debug, PartialEq)]
pub struct Md3Surface {
    pub name: String,
    pub flags: i32,
    /// Shader names as stored (lowercased, extension kept).
    pub shaders: Vec<String>,
    /// Indices as stored (MD3 winding).
    pub triangles: Vec<[u32; 3]>,
    pub st: Vec<[f32; 2]>,
    /// Per frame, per vertex: position in 1/64 units, exactly as stored.
    pub xyz: Vec<Vec<[i16; 3]>>,
    /// Per frame, per vertex: the stored lat/lng normal (`lat << 8 | lng`).
    pub normals: Vec<Vec<u16>>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Md3 {
    pub name: String,
    pub flags: i32,
    pub frames: Vec<Md3Frame>,
    /// `tags[frame][tag]`.
    pub tags: Vec<Vec<Md3Tag>>,
    pub surfaces: Vec<Md3Surface>,
}

pub fn parse(_bytes: &[u8]) -> Result<Md3, String> {
    todo!()
}

/// Decodes a stored lat/lng normal as the engine does (`R_LatLongToNormal`-style tables).
pub fn decode_normal(_latlng: u16) -> [f32; 3] {
    todo!()
}

/// The runtime buffer (docs/formats/md3.md) for EditableMesh animation.
pub fn to_buffer(_md3: &Md3) -> Vec<u8> {
    todo!()
}

/// One frame as static meshes, one per surface, named `<prefix>_<surface>`.
/// `texture` is `None`; the caller assigns textures from shaders/skins.
pub fn static_meshes(_md3: &Md3, _frame: usize, _prefix: &str) -> Vec<Mesh> {
    todo!()
}

#[derive(Clone, Debug, Default, PartialEq, Serialize)]
pub struct AnimationCfg {
    pub sex: Option<String>,
    pub footsteps: Option<String>,
    pub headoffset: Option<[f32; 3]>,
    pub fixedlegs: bool,
    pub fixedtorso: bool,
    /// `[first_frame, num_frames, looping_frames, fps]` in file order
    /// (BOTH_DEATH1 ... per bg_public.h `animNumber_t`), raw as written.
    pub animations: Vec<[i32; 4]>,
}

/// Parses like cg_players.c `CG_ParseAnimationFile` (without the leg-frame skip,
/// which the client applies).
pub fn parse_animation_cfg(_text: &str) -> Result<AnimationCfg, String> {
    todo!()
}

/// `.skin`: `surface,shader` lines; `tag_*` lines and empty shaders skipped.
pub fn parse_skin(_text: &str) -> Vec<(String, String)> {
    todo!()
}
