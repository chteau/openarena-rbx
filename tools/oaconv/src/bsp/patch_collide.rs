//! Patch collision: port of ioquake3 `qcommon/cm_patch.c`
//! `CM_GeneratePatchCollide` (GPL-2.0), run offline so the Luau
//! collision code only loads the result.

pub const MAX_FACET_BEVELS: usize = 4 + 6 + 16;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PcPlane {
    pub plane: [f32; 4],
    pub sign_bits: i32,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Facet {
    pub surface_plane: i32,
    pub num_borders: i32,
    pub border_planes: [i32; MAX_FACET_BEVELS],
    pub border_inward: [i32; MAX_FACET_BEVELS],
    pub border_no_adjust: [i32; MAX_FACET_BEVELS],
}

#[derive(Clone, Debug, PartialEq)]
pub struct PatchCollide {
    pub bounds: [[f32; 3]; 2],
    pub planes: Vec<PcPlane>,
    pub facets: Vec<Facet>,
}

/// `points` is the patch's `width * height` control points, row-major.
pub fn generate(_width: usize, _height: usize, _points: &[[f32; 3]]) -> PatchCollide {
    todo!()
}
