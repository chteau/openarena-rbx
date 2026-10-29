//! A small software rasterizer for checking baked maps without Roblox.

use std::collections::HashMap;

use image::RgbaImage;

use crate::mesh::Mesh;

/// Quake-space camera, angles as in Q3 (`yaw` around +Z from +X, `pitch` positive looks down).
#[derive(Clone, Copy, Debug)]
pub struct Camera {
    pub origin: [f32; 3],
    pub yaw: f32,
    pub pitch: f32,
    pub fov_x: f32,
}

/// Perspective render of `meshes` (Quake space, Quake winding, back faces culled
/// unless `two_sided`). Each mesh samples `textures[mesh.texture]` bilinearly with
/// wrap, times its vertex colour unless the shader is `"atlas"`; untextured
/// meshes use vertex colour. Pixels with no geometry are black.
pub fn render(_meshes: &[Mesh], _textures: &HashMap<String, RgbaImage>, _cam: Camera, _width: u32, _height: u32) -> RgbaImage {
    todo!()
}

/// Orthographic top-down render (looking down -Z) fitted to the meshes' XY bounds.
pub fn render_top(_meshes: &[Mesh], _textures: &HashMap<String, RgbaImage>, _width: u32, _height: u32) -> RgbaImage {
    todo!()
}
