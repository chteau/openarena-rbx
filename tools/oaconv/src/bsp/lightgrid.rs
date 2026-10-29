//! Light grid geometry, as `R_LoadLightGrid` (ioquake3 tr_bsp.c, GPL-2.0) derives it.

use serde::Serialize;

use super::Bsp;

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct LightGrid {
    pub origin: [f32; 3],
    pub size: [f32; 3],
    pub bounds: [i32; 3],
    /// 8 bytes per cell (ambient rgb, directed rgb, lat, lng), raw.
    #[serde(skip)]
    pub cells: Vec<u8>,
}

pub fn light_grid(_bsp: &Bsp) -> Result<LightGrid, String> {
    todo!()
}
