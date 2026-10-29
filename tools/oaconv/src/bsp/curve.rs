//! Bezier patch tessellation: port of ioquake3 `renderergl1/tr_curve.c`
//! `R_SubdividePatchToGrid` (GPL-2.0).

use super::DrawVert;

/// The engine's `r_subdivisions` default.
pub const R_SUBDIVISIONS: f32 = 4.0;

/// A tessellated patch. `verts[j * width + i]`, row-major like `srfGridMesh_t`.
#[derive(Clone, Debug)]
pub struct Grid {
    pub width: usize,
    pub height: usize,
    pub verts: Vec<DrawVert>,
}

impl Grid {
    /// Triangles with the index order and winding `RB_SurfaceGrid` emits at
    /// full LOD (every row and column).
    pub fn triangles(&self) -> Vec<[u32; 3]> {
        todo!()
    }
}

/// `ctrl` is `width * height` control points, row-major.
pub fn subdivide_patch(_width: usize, _height: usize, _ctrl: &[DrawVert], _subdivisions: f32) -> Grid {
    todo!()
}
