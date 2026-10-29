//! oaconv: OpenArena 0.8.8 data (`vendor/`) to Roblox-ready assets (`build/`).
//! Every module documents the engine code it follows; ported ioquake3 code
//! keeps its GPL-2.0 origin noted at the top of the file.

pub mod bake;
pub mod bsp;
pub mod gltf;
pub mod luau;
pub mod manifest;
pub mod md3;
pub mod md3edit;
pub mod mesh;
pub mod preview;
pub mod shader;
pub mod sound;
pub mod texture;
pub mod upload;
pub mod vfs;

#[cfg(test)]
pub(crate) mod testdata;
