//! Bezier patch tessellation: port of ioquake3 `renderergl1/tr_curve.c`
//! `R_SubdividePatchToGrid` (GPL-2.0).
// Index loops mirror the C so the port stays line-for-line comparable.
#![allow(clippy::needless_range_loop)]

use super::DrawVert;

/// The engine's `r_subdivisions` default.
pub const R_SUBDIVISIONS: f32 = 4.0;

const MAX_GRID_SIZE: usize = 65;

type Ctrl = Vec<[DrawVert; MAX_GRID_SIZE]>;

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
        let w = self.width as u32;
        let mut out = Vec::with_capacity(
            (self.width.saturating_sub(1)) * (self.height.saturating_sub(1)) * 2,
        );
        for i in 0..self.height.saturating_sub(1) as u32 {
            for j in 0..w.saturating_sub(1) {
                let v1 = i * w + j + 1;
                let v2 = v1 - 1;
                let v3 = v2 + w;
                let v4 = v3 + 1;
                out.push([v2, v3, v1]);
                out.push([v1, v3, v4]);
            }
        }
        out
    }
}

fn lerp(a: &DrawVert, b: &DrawVert) -> DrawVert {
    let mut o = DrawVert::default();
    for k in 0..3 {
        o.xyz[k] = 0.5 * (a.xyz[k] + b.xyz[k]);
    }
    for k in 0..2 {
        o.st[k] = 0.5 * (a.st[k] + b.st[k]);
        o.lightmap[k] = 0.5 * (a.lightmap[k] + b.lightmap[k]);
    }
    for k in 0..4 {
        o.color[k] = ((a.color[k] as u32 + b.color[k] as u32) >> 1) as u8;
    }
    o
}

fn transpose(width: usize, height: usize, ctrl: &mut Ctrl) {
    let old = ctrl.clone();
    for i in 0..height {
        for j in 0..width {
            ctrl[j][i] = old[i][j];
        }
    }
}

fn invert_ctrl(width: usize, height: usize, ctrl: &mut Ctrl) {
    for row in ctrl.iter_mut().take(height) {
        row[..width].reverse();
    }
}

fn put_points_on_curve(ctrl: &mut Ctrl, width: usize, height: usize) {
    for i in 0..width {
        let mut j = 1;
        while j < height {
            let prev = lerp(&ctrl[j][i], &ctrl[j + 1][i]);
            let next = lerp(&ctrl[j][i], &ctrl[j - 1][i]);
            ctrl[j][i] = lerp(&prev, &next);
            j += 2;
        }
    }
    for j in 0..height {
        let mut i = 1;
        while i < width {
            let prev = lerp(&ctrl[j][i], &ctrl[j][i + 1]);
            let next = lerp(&ctrl[j][i], &ctrl[j][i - 1]);
            ctrl[j][i] = lerp(&prev, &next);
            i += 2;
        }
    }
}

fn sub(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}

fn length_squared(v: [f32; 3]) -> f32 {
    v[0] * v[0] + v[1] * v[1] + v[2] * v[2]
}

/// `VectorNormalize2`: returns the original length, zero vector if degenerate.
fn normalize(v: [f32; 3]) -> ([f32; 3], f32) {
    let len = length_squared(v).sqrt();
    if len == 0.0 {
        ([0.0; 3], 0.0)
    } else {
        let il = 1.0 / len;
        ([v[0] * il, v[1] * il, v[2] * il], len)
    }
}

fn cross(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}

/// Steps a neighbour coordinate across the seam of a closed patch the way
/// `MakeMeshNormals` does (the shared edge column/row is skipped).
fn wrap(v: i32, size: i32, wraps: bool) -> i32 {
    if !wraps {
        v
    } else if v < 0 {
        size - 1 + v
    } else if v >= size {
        1 + v - size
    } else {
        v
    }
}

fn make_mesh_normals(width: usize, height: usize, ctrl: &mut Ctrl) {
    const NEIGHBORS: [[i32; 2]; 8] = [
        [0, 1],
        [1, 1],
        [1, 0],
        [1, -1],
        [0, -1],
        [-1, -1],
        [-1, 0],
        [-1, 1],
    ];

    let wrap_width =
        (0..height).all(|i| length_squared(sub(ctrl[i][0].xyz, ctrl[i][width - 1].xyz)) <= 1.0);
    let wrap_height =
        (0..width).all(|i| length_squared(sub(ctrl[0][i].xyz, ctrl[height - 1][i].xyz)) <= 1.0);
    let (w, h) = (width as i32, height as i32);

    for i in 0..width {
        for j in 0..height {
            let base = ctrl[j][i].xyz;
            let mut around = [[0.0f32; 3]; 8];
            let mut good = [false; 8];
            for k in 0..8 {
                for dist in 1..=3i32 {
                    let x = wrap(i as i32 + NEIGHBORS[k][0] * dist, w, wrap_width);
                    let y = wrap(j as i32 + NEIGHBORS[k][1] * dist, h, wrap_height);
                    if x < 0 || x >= w || y < 0 || y >= h {
                        break;
                    }
                    let (t, len) = normalize(sub(ctrl[y as usize][x as usize].xyz, base));
                    if len == 0.0 {
                        continue;
                    }
                    good[k] = true;
                    around[k] = t;
                    break;
                }
            }
            let mut sum = [0.0f32; 3];
            for k in 0..8 {
                if !good[k] || !good[(k + 1) & 7] {
                    continue;
                }
                let (n, len) = normalize(cross(around[(k + 1) & 7], around[k]));
                if len == 0.0 {
                    continue;
                }
                for c in 0..3 {
                    sum[c] += n[c];
                }
            }
            ctrl[j][i].normal = normalize(sum).0;
        }
    }
}

/// `ctrl` is `width * height` control points, row-major.
pub fn subdivide_patch(width: usize, height: usize, ctrl: &[DrawVert], subdivisions: f32) -> Grid {
    let (mut width, mut height) = (width, height);
    let mut grid: Ctrl = vec![[DrawVert::default(); MAX_GRID_SIZE]; MAX_GRID_SIZE];
    for j in 0..height {
        for i in 0..width {
            grid[j][i] = ctrl[j * width + i];
        }
    }
    let mut error_table = [[0.0f32; MAX_GRID_SIZE]; 2];

    for dir in 0..2 {
        let mut j = 0;
        while j + 2 < width {
            let mut max_len = 0.0f32;
            for i in 0..height {
                let a = grid[i][j].xyz;
                let b = grid[i][j + 1].xyz;
                let c = grid[i][j + 2].xyz;
                // Distance of the curve midpoint from the chord; ignores texture
                // warping but yields far fewer polygons than midpoint distance.
                let mid = [
                    (a[0] + b[0] * 2.0 + c[0]) * 0.25 - a[0],
                    (a[1] + b[1] * 2.0 + c[1]) * 0.25 - a[1],
                    (a[2] + b[2] * 2.0 + c[2]) * 0.25 - a[2],
                ];
                let (d, _) = normalize(sub(c, a));
                let dp = mid[0] * d[0] + mid[1] * d[1] + mid[2] * d[2];
                let off = [mid[0] - d[0] * dp, mid[1] - d[1] * dp, mid[2] - d[2] * dp];
                max_len = max_len.max(length_squared(off));
            }
            max_len = max_len.sqrt();

            if max_len < 0.1 {
                error_table[dir][j + 1] = 999.0;
                j += 2;
                continue;
            }
            if width + 2 > MAX_GRID_SIZE || max_len <= subdivisions {
                error_table[dir][j + 1] = 1.0 / max_len;
                j += 2;
                continue;
            }
            error_table[dir][j + 2] = 1.0 / max_len;

            width += 2;
            for row in grid.iter_mut().take(height) {
                let prev = lerp(&row[j], &row[j + 1]);
                let next = lerp(&row[j + 1], &row[j + 2]);
                let mid = lerp(&prev, &next);
                let mut k = width - 1;
                while k > j + 3 {
                    row[k] = row[k - 2];
                    k -= 1;
                }
                row[j + 1] = prev;
                row[j + 2] = mid;
                row[j + 3] = next;
            }
            // Recheck the same span: it may need more subdivision.
        }

        transpose(width, height, &mut grid);
        std::mem::swap(&mut width, &mut height);
    }

    put_points_on_curve(&mut grid, width, height);

    // Cull colinear columns, then rows. Like the C, the index advances past
    // a removal, so a colinear neighbour shifted into place is kept.
    let mut i = 1;
    while i + 1 < width {
        if error_table[0][i] == 999.0 {
            for j in i + 1..width {
                for row in grid.iter_mut().take(height) {
                    row[j - 1] = row[j];
                }
                error_table[0][j - 1] = error_table[0][j];
            }
            width -= 1;
        }
        i += 1;
    }
    let mut i = 1;
    while i + 1 < height {
        if error_table[1][i] == 999.0 {
            for j in i + 1..height {
                grid[j - 1] = grid[j];
                error_table[1][j - 1] = error_table[1][j];
            }
            height -= 1;
        }
        i += 1;
    }

    // Longest strips first; transpose + mirror keeps the winding.
    if height > width {
        transpose(width, height, &mut grid);
        std::mem::swap(&mut width, &mut height);
        invert_ctrl(width, height, &mut grid);
    }

    make_mesh_normals(width, height, &mut grid);

    let mut verts = Vec::with_capacity(width * height);
    for row in grid.iter().take(height) {
        verts.extend_from_slice(&row[..width]);
    }
    Grid {
        width,
        height,
        verts,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bsp::MST_PATCH;

    fn dv(x: f32, y: f32, z: f32) -> DrawVert {
        DrawVert {
            xyz: [x, y, z],
            ..DrawVert::default()
        }
    }

    fn dot(a: [f32; 3], b: [f32; 3]) -> f32 {
        a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
    }

    /// Planar, but the centre point is pulled off both chords by 2 units:
    /// above the colinear cull threshold, below `r_subdivisions`.
    fn flat_patch() -> Vec<DrawVert> {
        let mut c = Vec::new();
        for j in 0..3 {
            for i in 0..3 {
                let e = if i == 1 && j == 1 { 4.0 } else { 0.0 };
                c.push(dv(32.0 * i as f32 + e, 32.0 * j as f32 + e, 0.0));
            }
        }
        c
    }

    /// Straight along rows (x), a quarter circle of radius 64 along columns.
    fn quarter_cylinder() -> Vec<DrawVert> {
        let arc = [[64.0, 0.0], [64.0, 64.0], [0.0, 64.0]];
        let mut c = Vec::new();
        for j in 0..3 {
            for p in arc {
                c.push(dv(64.0 * j as f32, p[0], p[1]));
            }
        }
        c
    }

    fn assert_corners(g: &Grid, ctrl: &[DrawVert]) {
        let (w, h) = (g.width, g.height);
        assert_eq!(g.verts[0].xyz, ctrl[0].xyz);
        assert_eq!(g.verts[w - 1].xyz, ctrl[2].xyz);
        assert_eq!(g.verts[(h - 1) * w].xyz, ctrl[6].xyz);
        assert_eq!(g.verts[h * w - 1].xyz, ctrl[8].xyz);
    }

    #[test]
    fn flat_patch_stays_3x3_and_winds_clockwise() {
        let ctrl = flat_patch();
        let g = subdivide_patch(3, 3, &ctrl, R_SUBDIVISIONS);
        assert_eq!((g.width, g.height), (3, 3));
        assert_eq!(g.verts.len(), 9);
        assert_corners(&g, &ctrl);
        let tris = g.triangles();
        assert_eq!(tris.len(), 8);
        for t in tris {
            let [a, b, c] = t.map(|k| g.verts[k as usize]);
            let n = cross(sub(b.xyz, a.xyz), sub(c.xyz, a.xyz));
            for v in [a, b, c] {
                assert!((normalize(v.normal).1 - 1.0).abs() < 1e-4);
                assert!(
                    dot(n, v.normal) < 0.0,
                    "triangle {t:?} winds with its normal"
                );
            }
        }
    }

    #[test]
    fn quarter_cylinder_subdivides_curved_direction_only() {
        let ctrl = quarter_cylinder();
        let g = subdivide_patch(3, 3, &ctrl, R_SUBDIVISIONS);
        assert!(g.width > 3, "curved direction not subdivided: {}", g.width);
        assert_eq!(
            g.height, 2,
            "straight direction should cull its colinear middle row"
        );
        assert_eq!(g.verts.len(), g.width * g.height);
        assert_eq!(g.triangles().len(), (g.width - 1) * (g.height - 1) * 2);
        assert_corners(&g, &ctrl);
        // A quadratic Bezier quarter circle bulges to ~67.9 at its middle.
        for v in &g.verts {
            let r = (v.xyz[1] * v.xyz[1] + v.xyz[2] * v.xyz[2]).sqrt();
            assert!((63.9..68.0).contains(&r), "vertex off the arc: {:?}", v.xyz);
        }
    }

    #[test]
    fn real_patches_tessellate() {
        for map in ["oa_dm1", "oa_ctf2", "am_thornish"] {
            let Some(bsp) = crate::testdata::bsp(map) else {
                continue;
            };
            let (mut agree, mut total, mut patches) = (0usize, 0usize, 0usize);
            for s in bsp.surfaces.iter().filter(|s| s.surface_type == MST_PATCH) {
                patches += 1;
                let first = s.first_vert as usize;
                let ctrl = &bsp.verts[first..first + s.num_verts as usize];
                let g = subdivide_patch(
                    s.patch_width as usize,
                    s.patch_height as usize,
                    ctrl,
                    R_SUBDIVISIONS,
                );
                assert!(
                    g.width <= MAX_GRID_SIZE && g.height <= MAX_GRID_SIZE,
                    "{map}: {}x{}",
                    g.width,
                    g.height
                );
                assert_eq!(g.verts.len(), g.width * g.height);
                for v in &g.verts {
                    assert!(v.xyz.iter().all(|c| c.is_finite()), "{map}: {:?}", v.xyz);
                    let len = normalize(v.normal).1;
                    assert!(
                        len == 0.0 || (len - 1.0).abs() < 1e-3,
                        "{map}: normal length {len}"
                    );
                }
                let tris = g.triangles();
                assert_eq!(tris.len(), (g.width - 1) * (g.height - 1) * 2);
                for t in tris {
                    let [a, b, c] = t.map(|k| g.verts[k as usize]);
                    let n = cross(sub(b.xyz, a.xyz), sub(c.xyz, a.xyz));
                    let vn = [0, 1, 2].map(|k| a.normal[k] + b.normal[k] + c.normal[k]);
                    if normalize(n).1 < 1e-4 || normalize(vn).1 < 1e-4 {
                        continue;
                    }
                    total += 1;
                    if dot(n, vn) < 0.0 {
                        agree += 1;
                    }
                }
            }
            assert!(
                agree as f64 >= 0.9 * total as f64,
                "{map}: {agree}/{total} triangles wind against their normals ({patches} patches)"
            );
        }
    }
}
