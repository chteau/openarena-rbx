//! Light grid geometry, as `R_LoadLightGrid` (ioquake3 tr_bsp.c, GPL-2.0) derives it.

use serde::Serialize;

use super::{entities, Bsp};

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct LightGrid {
    pub origin: [f32; 3],
    pub size: [f32; 3],
    pub bounds: [i32; 3],
    /// 8 bytes per cell (ambient rgb, directed rgb, lat, lng), raw.
    #[serde(skip)]
    pub cells: Vec<u8>,
}

pub fn light_grid(bsp: &Bsp) -> Result<LightGrid, String> {
    let model = bsp.models.first().ok_or("no world model")?;
    let mut size = [64.0f32, 64.0, 128.0];
    let ents = entities::parse(&bsp.entities)?;
    if let Some(v) = ents.first().and_then(|w| w.get("gridsize")) {
        let p: Vec<f32> = v
            .split_whitespace()
            .filter_map(|t| t.parse().ok())
            .collect();
        if p.len() == 3 {
            size = [p[0], p[1], p[2]];
        }
    }
    if size.iter().any(|&s| s <= 0.0) {
        return Err("non-positive gridsize".into());
    }
    let mut origin = [0.0f32; 3];
    let mut bounds = [0i32; 3];
    for i in 0..3 {
        origin[i] = size[i] * (model.mins[i] / size[i]).ceil();
        let max = size[i] * (model.maxs[i] / size[i]).floor();
        bounds[i] = ((max - origin[i]) / size[i] + 1.0) as i32;
    }
    let count: i64 = bounds.iter().map(|&b| i64::from(b.max(0))).product();
    if bsp.light_grid.len() as i64 != count * 8 {
        return Err(format!(
            "light grid mismatch: lump is {} bytes, expected {}",
            bsp.light_grid.len(),
            count * 8
        ));
    }
    Ok(LightGrid {
        origin,
        size,
        bounds,
        cells: bsp.light_grid.clone(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cells_match_bounds() {
        for map in ["oa_dm1", "oa_ctf2", "am_thornish"] {
            let Some(bsp) = crate::testdata::bsp(map) else {
                return;
            };
            let g = light_grid(&bsp).unwrap();
            let n: i32 = g.bounds.iter().product();
            assert_eq!(g.cells.len(), n as usize * 8);
        }
    }
}
