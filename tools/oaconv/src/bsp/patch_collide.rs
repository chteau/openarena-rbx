//! Patch collision: port of ioquake3 `qcommon/cm_patch.c`
//! `CM_GeneratePatchCollide` (GPL-2.0), run offline so the Luau
//! collision code only loads the result.

mod grid;
mod polylib;

use grid::{Grid, POINT_EPSILON};
use polylib::{
    base_winding_for_plane, chop_winding, cross, dot, ma, normalize, sub, winding_bounds, Vec3,
    MAX_MAP_BOUNDS, SIDE_BACK, SIDE_FRONT, SIDE_ON,
};

pub const MAX_FACET_BEVELS: usize = 4 + 6 + 16;

const MAX_FACETS: usize = 1024;
const MAX_PATCH_PLANES: usize = 2048;
const MAX_GRID_SIZE: usize = 129;
const PLANE_TRI_EPSILON: f32 = 0.1;
const NORMAL_EPSILON: f32 = 0.0001;
const DIST_EPSILON: f32 = 0.02;
const ON_EPSILON: f32 = 0.1;

const EN_TOP: usize = 0;
const EN_RIGHT: usize = 1;
const EN_BOTTOM: usize = 2;
const EN_LEFT: usize = 3;

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

type GridPlanes = Vec<Vec<[i32; 2]>>;

fn normal_of(p: &[f32; 4]) -> Vec3 {
    [p[0], p[1], p[2]]
}

fn plane_from_points(a: &Vec3, b: &Vec3, c: &Vec3) -> Option<[f32; 4]> {
    let d1 = sub(b, a);
    let d2 = sub(c, a);
    let mut n = cross(&d2, &d1);
    if normalize(&mut n) == 0.0 {
        return None;
    }
    Some([n[0], n[1], n[2], dot(a, &n)])
}

fn signbits_for_normal(n: &[f32; 4]) -> i32 {
    (0..3).fold(0, |bits, i| if n[i] < 0.0 { bits | (1 << i) } else { bits })
}

/// `Some(flipped)` when `plane` matches `p` directly or inverted.
fn plane_equal(p: &PcPlane, plane: &[f32; 4]) -> Option<bool> {
    let close = |a: &[f32; 4], b: &[f32; 4]| {
        (a[0] - b[0]).abs() < NORMAL_EPSILON
            && (a[1] - b[1]).abs() < NORMAL_EPSILON
            && (a[2] - b[2]).abs() < NORMAL_EPSILON
            && (a[3] - b[3]).abs() < DIST_EPSILON
    };
    if close(&p.plane, plane) {
        return Some(false);
    }
    let inv = [-plane[0], -plane[1], -plane[2], -plane[3]];
    close(&p.plane, &inv).then_some(true)
}

fn snap_vector(normal: &mut Vec3) {
    for i in 0..3 {
        if (normal[i] - 1.0).abs() < NORMAL_EPSILON {
            *normal = [0.0; 3];
            normal[i] = 1.0;
            break;
        }
        if (normal[i] + 1.0).abs() < NORMAL_EPSILON {
            *normal = [0.0; 3];
            normal[i] = -1.0;
            break;
        }
    }
}

#[derive(Default)]
struct Builder {
    planes: Vec<PcPlane>,
    facets: Vec<Facet>,
}

impl Builder {
    fn push_plane(&mut self, plane: [f32; 4]) -> i32 {
        if self.planes.len() == MAX_PATCH_PLANES {
            panic!("MAX_PATCH_PLANES");
        }
        self.planes.push(PcPlane {
            plane,
            sign_bits: signbits_for_normal(&plane),
        });
        self.planes.len() as i32 - 1
    }

    fn find_plane2(&mut self, plane: &[f32; 4]) -> (i32, bool) {
        for (i, p) in self.planes.iter().enumerate() {
            if let Some(flipped) = plane_equal(p, plane) {
                return (i as i32, flipped);
            }
        }
        (self.push_plane(*plane), false)
    }

    fn find_plane(&mut self, p1: &Vec3, p2: &Vec3, p3: &Vec3) -> i32 {
        let Some(plane) = plane_from_points(p1, p2, p3) else {
            return -1;
        };
        let n = normal_of(&plane);
        for (i, p) in self.planes.iter().enumerate() {
            if dot(&n, &normal_of(&p.plane)) < 0.0 {
                continue;
            }
            let near =
                |pt: &Vec3| (dot(pt, &normal_of(&p.plane)) - p.plane[3]).abs() <= PLANE_TRI_EPSILON;
            if near(p1) && near(p2) && near(p3) {
                return i as i32;
            }
        }
        self.push_plane(plane)
    }

    fn point_on_plane_side(&self, p: &Vec3, plane_num: i32) -> usize {
        if plane_num == -1 {
            return SIDE_ON;
        }
        let plane = &self.planes[plane_num as usize].plane;
        let d = dot(p, &normal_of(plane)) - plane[3];
        if d > POINT_EPSILON {
            SIDE_FRONT
        } else if d < -POINT_EPSILON {
            SIDE_BACK
        } else {
            SIDE_ON
        }
    }

    fn grid_plane(gp: &GridPlanes, i: usize, j: usize, tri: usize) -> i32 {
        let p = gp[i][j][tri];
        if p != -1 {
            return p;
        }
        let p = gp[i][j][1 - tri];
        if p == -1 {
            eprintln!("WARNING: CM_GridPlane unresolvable");
        }
        p
    }

    fn edge_plane_num(&mut self, g: &Grid, gp: &GridPlanes, i: usize, j: usize, k: usize) -> i32 {
        let c = &g.cols;
        let (tri, a, b, swap) = match k {
            0 => (0, c[i][j], c[i + 1][j], false),
            2 => (1, c[i][j + 1], c[i + 1][j + 1], true),
            3 => (1, c[i][j], c[i][j + 1], true),
            1 => (0, c[i + 1][j], c[i + 1][j + 1], false),
            4 => (0, c[i + 1][j + 1], c[i][j], false),
            5 => (1, c[i][j], c[i + 1][j + 1], false),
            _ => panic!("CM_EdgePlane: bad k"),
        };
        let p = Self::grid_plane(gp, i, j, tri);
        if p < 0 {
            return -1;
        }
        let up = ma(&a, 4.0, &normal_of(&self.planes[p as usize].plane));
        if swap {
            self.find_plane(&b, &a, &up)
        } else {
            self.find_plane(&a, &b, &up)
        }
    }

    fn set_border_inward(&self, f: &mut Facet, g: &Grid, i: usize, j: usize, which: i32) {
        let c = &g.cols;
        let points: Vec<Vec3> = match which {
            -1 => vec![c[i][j], c[i + 1][j], c[i + 1][j + 1], c[i][j + 1]],
            0 => vec![c[i + 1][j], c[i + 1][j + 1], c[i][j]],
            1 => vec![c[i + 1][j + 1], c[i][j + 1], c[i][j]],
            _ => panic!("CM_SetBorderInward: bad parameter {which}"),
        };
        for k in 0..f.num_borders as usize {
            let (mut front, mut back) = (0, 0);
            for p in &points {
                match self.point_on_plane_side(p, f.border_planes[k]) {
                    SIDE_FRONT => front += 1,
                    SIDE_BACK => back += 1,
                    _ => {}
                }
            }
            if front > 0 && back == 0 {
                f.border_inward[k] = 1;
            } else if back > 0 && front == 0 {
                f.border_inward[k] = 0;
            } else if front == 0 && back == 0 {
                // flat side border
                f.border_planes[k] = -1;
            } else {
                // bisecting side border
                f.border_inward[k] = 0;
            }
        }
    }

    /// Bounded winding of the facet face, or `None` when a border chops it away.
    fn facet_winding(&self, f: &Facet, skip_surface: bool) -> Option<polylib::Winding> {
        let sp = self.planes[f.surface_plane as usize].plane;
        let mut w = base_winding_for_plane(&normal_of(&sp), sp[3]);
        for j in 0..f.num_borders as usize {
            if f.border_planes[j] == -1 {
                return None;
            }
            if skip_surface && f.border_planes[j] == f.surface_plane {
                continue;
            }
            let mut plane = self.planes[f.border_planes[j] as usize].plane;
            if f.border_inward[j] == 0 {
                plane = plane.map(|v| -v);
            }
            w = chop_winding(w, &normal_of(&plane), plane[3], ON_EPSILON)?;
        }
        Some(w)
    }

    fn validate_facet(&self, f: &Facet) -> bool {
        if f.surface_plane == -1 {
            return false;
        }
        let Some(w) = self.facet_winding(f, false) else {
            return false;
        };
        let (mins, maxs) = winding_bounds(&w);
        (0..3).all(|j| {
            maxs[j] - mins[j] <= MAX_MAP_BOUNDS
                && mins[j] < MAX_MAP_BOUNDS
                && maxs[j] > -MAX_MAP_BOUNDS
        })
    }

    fn has_border(&self, f: &Facet, plane: &[f32; 4]) -> bool {
        f.border_planes[..f.num_borders as usize]
            .iter()
            .any(|&b| plane_equal(&self.planes[b as usize], plane).is_some())
    }

    fn add_facet_bevels(&mut self, f: &mut Facet) {
        let Some(w) = self.facet_winding(f, true) else {
            return;
        };
        let (mins, maxs) = winding_bounds(&w);
        let surface = self.planes[f.surface_plane as usize];

        for axis in 0..3 {
            for dir in [-1.0f32, 1.0] {
                let mut plane = [0.0f32; 4];
                plane[axis] = dir;
                plane[3] = if dir == 1.0 { maxs[axis] } else { -mins[axis] };
                if plane_equal(&surface, &plane).is_some() || self.has_border(f, &plane) {
                    continue;
                }
                if f.num_borders as usize >= MAX_FACET_BEVELS {
                    eprintln!("ERROR: too many bevels");
                    continue;
                }
                let (idx, flipped) = self.find_plane2(&plane);
                self.push_border(f, idx, flipped);
            }
        }

        let n = w.len();
        for j in 0..n {
            let mut vec = sub(&w[j], &w[(j + 1) % n]);
            if normalize(&mut vec) < 0.5 {
                continue;
            }
            snap_vector(&mut vec);
            if vec.iter().any(|&x| x == 1.0 || x == -1.0) {
                continue;
            }
            for axis in 0..3 {
                for dir in [-1.0f32, 1.0] {
                    let mut vec2 = [0.0f32; 3];
                    vec2[axis] = dir;
                    let mut nrm = cross(&vec, &vec2);
                    if normalize(&mut nrm) < 0.5 {
                        continue;
                    }
                    let plane = [nrm[0], nrm[1], nrm[2], dot(&w[j], &nrm)];
                    if w.iter().any(|p| dot(p, &nrm) - plane[3] > 0.1) {
                        continue;
                    }
                    if plane_equal(&surface, &plane).is_some() || self.has_border(f, &plane) {
                        continue;
                    }
                    if f.num_borders as usize >= MAX_FACET_BEVELS {
                        eprintln!("ERROR: too many bevels");
                        continue;
                    }
                    let (idx, flipped) = self.find_plane2(&plane);
                    let mut newplane = self.planes[idx as usize].plane;
                    if !flipped {
                        newplane = newplane.map(|v| -v);
                    }
                    if chop_winding(w.clone(), &normal_of(&newplane), newplane[3], ON_EPSILON)
                        .is_none()
                    {
                        continue;
                    }
                    self.push_border(f, idx, flipped);
                }
            }
        }

        if (f.num_borders as usize) < MAX_FACET_BEVELS {
            self.push_border(f, f.surface_plane, false);
            f.border_inward[f.num_borders as usize - 1] = 1;
        } else {
            eprintln!("ERROR: too many bevels");
        }
    }

    fn push_border(&self, f: &mut Facet, plane: i32, inward: bool) {
        let n = f.num_borders as usize;
        f.border_planes[n] = plane;
        f.border_no_adjust[n] = 0;
        f.border_inward[n] = i32::from(inward);
        f.num_borders += 1;
    }

    fn new_facet(&self, surface_plane: i32) -> Facet {
        if self.facets.len() == MAX_FACETS {
            panic!("MAX_FACETS");
        }
        Facet {
            surface_plane,
            num_borders: 0,
            border_planes: [0; MAX_FACET_BEVELS],
            border_inward: [0; MAX_FACET_BEVELS],
            border_no_adjust: [0; MAX_FACET_BEVELS],
        }
    }

    fn finish_facet(&mut self, mut f: Facet) {
        if self.validate_facet(&f) {
            self.add_facet_bevels(&mut f);
            self.facets.push(f);
        }
    }

    fn add_grid_facets(&mut self, g: &Grid) {
        let (w, h) = (g.width(), g.height());
        let c = &g.cols;
        let mut gp: GridPlanes = vec![vec![[-1; 2]; h - 1]; w - 1];
        for i in 0..w - 1 {
            for j in 0..h - 1 {
                gp[i][j][0] = self.find_plane(&c[i][j], &c[i + 1][j], &c[i + 1][j + 1]);
                gp[i][j][1] = self.find_plane(&c[i + 1][j + 1], &c[i][j + 1], &c[i][j]);
            }
        }

        for i in 0..w - 1 {
            for j in 0..h - 1 {
                let mut borders = [-1i32; 4];
                let mut no_adjust = [0i32; 4];

                if j > 0 {
                    borders[EN_TOP] = gp[i][j - 1][1];
                } else if g.wrap_height {
                    borders[EN_TOP] = gp[i][h - 2][1];
                }
                no_adjust[EN_TOP] = i32::from(borders[EN_TOP] == gp[i][j][0]);
                if borders[EN_TOP] == -1 || no_adjust[EN_TOP] != 0 {
                    borders[EN_TOP] = self.edge_plane_num(g, &gp, i, j, 0);
                }

                if j < h - 2 {
                    borders[EN_BOTTOM] = gp[i][j + 1][0];
                } else if g.wrap_height {
                    borders[EN_BOTTOM] = gp[i][0][0];
                }
                no_adjust[EN_BOTTOM] = i32::from(borders[EN_BOTTOM] == gp[i][j][1]);
                if borders[EN_BOTTOM] == -1 || no_adjust[EN_BOTTOM] != 0 {
                    borders[EN_BOTTOM] = self.edge_plane_num(g, &gp, i, j, 2);
                }

                if i > 0 {
                    borders[EN_LEFT] = gp[i - 1][j][0];
                } else if g.wrap_width {
                    borders[EN_LEFT] = gp[w - 2][j][0];
                }
                no_adjust[EN_LEFT] = i32::from(borders[EN_LEFT] == gp[i][j][1]);
                if borders[EN_LEFT] == -1 || no_adjust[EN_LEFT] != 0 {
                    borders[EN_LEFT] = self.edge_plane_num(g, &gp, i, j, 3);
                }

                if i < w - 2 {
                    borders[EN_RIGHT] = gp[i + 1][j][1];
                } else if g.wrap_width {
                    borders[EN_RIGHT] = gp[0][j][1];
                }
                no_adjust[EN_RIGHT] = i32::from(borders[EN_RIGHT] == gp[i][j][0]);
                if borders[EN_RIGHT] == -1 || no_adjust[EN_RIGHT] != 0 {
                    borders[EN_RIGHT] = self.edge_plane_num(g, &gp, i, j, 1);
                }

                let mut facet = self.new_facet(gp[i][j][0]);
                if gp[i][j][0] == gp[i][j][1] {
                    if gp[i][j][0] == -1 {
                        continue;
                    }
                    facet.num_borders = 4;
                    for (k, e) in [EN_TOP, EN_BOTTOM, EN_LEFT, EN_RIGHT]
                        .into_iter()
                        .enumerate()
                    {
                        facet.border_planes[k] = borders[e];
                        facet.border_no_adjust[k] = no_adjust[e];
                    }
                    self.set_border_inward(&mut facet, g, i, j, -1);
                    self.finish_facet(facet);
                } else {
                    facet.num_borders = 3;
                    facet.border_planes[0] = borders[EN_TOP];
                    facet.border_no_adjust[0] = no_adjust[EN_TOP];
                    facet.border_planes[1] = borders[EN_RIGHT];
                    facet.border_no_adjust[1] = no_adjust[EN_RIGHT];
                    facet.border_planes[2] = self.edge_plane_num(g, &gp, i, j, 4);
                    self.set_border_inward(&mut facet, g, i, j, 0);
                    self.finish_facet(facet);

                    let mut facet = self.new_facet(gp[i][j][1]);
                    facet.num_borders = 3;
                    facet.border_planes[0] = borders[EN_BOTTOM];
                    facet.border_no_adjust[0] = no_adjust[EN_BOTTOM];
                    facet.border_planes[1] = borders[EN_LEFT];
                    facet.border_no_adjust[1] = no_adjust[EN_LEFT];
                    facet.border_planes[2] = self.edge_plane_num(g, &gp, i, j, 5);
                    self.set_border_inward(&mut facet, g, i, j, 1);
                    self.finish_facet(facet);
                }
            }
        }
    }
}

/// `points` is the patch's `width * height` control points, row-major.
pub fn generate(width: usize, height: usize, points: &[[f32; 3]]) -> PatchCollide {
    if width <= 2 || height <= 2 || points.len() < width * height {
        panic!(
            "CM_GeneratePatchFacets: bad parameters: ({width}, {height}, {})",
            points.len()
        );
    }
    if width & 1 == 0 || height & 1 == 0 {
        panic!("CM_GeneratePatchFacets: even sizes are invalid for quadratic meshes");
    }
    if width > MAX_GRID_SIZE || height > MAX_GRID_SIZE {
        panic!("CM_GeneratePatchFacets: source is > MAX_GRID_SIZE");
    }

    let mut grid = Grid {
        cols: (0..width)
            .map(|i| (0..height).map(|j| points[j * width + i]).collect())
            .collect(),
        wrap_width: false,
        wrap_height: false,
    };
    grid.set_wrap_width();
    grid.subdivide_columns();
    grid.remove_degenerate_columns();
    grid.transpose();
    grid.set_wrap_width();
    grid.subdivide_columns();
    grid.remove_degenerate_columns();

    let mut mins = [99999.0f32; 3];
    let mut maxs = [-99999.0f32; 3];
    for p in grid.cols.iter().flatten() {
        mins = std::array::from_fn(|j| mins[j].min(p[j]));
        maxs = std::array::from_fn(|j| maxs[j].max(p[j]));
    }

    let mut b = Builder::default();
    b.add_grid_facets(&grid);

    // expand by one unit for epsilon issues in the collision code
    PatchCollide {
        bounds: [mins.map(|v| v - 1.0), maxs.map(|v| v + 1.0)],
        planes: b.planes,
        facets: b.facets,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn flat() -> Vec<[f32; 3]> {
        (0..3)
            .flat_map(|y| (0..3).map(move |x| [x as f32 * 64.0, y as f32 * 64.0, 0.0]))
            .collect()
    }

    #[test]
    fn flat_patch_is_one_facet() {
        let pc = generate(3, 3, &flat());
        assert_eq!(pc.facets.len(), 1);
        let f = &pc.facets[0];
        let sp = pc.planes[f.surface_plane as usize].plane;
        assert_eq!(sp[2].abs(), 1.0);
        assert_eq!(sp[3], 0.0);
        assert!(f.num_borders >= 5);
        let last = f.num_borders as usize - 1;
        assert_eq!(f.border_planes[last], f.surface_plane);
        assert_eq!(f.border_inward[last], 1);
    }

    #[test]
    fn curved_patch_has_several_facets() {
        let mut pts = flat();
        pts[4][2] = 200.0;
        assert!(generate(3, 3, &pts).facets.len() > 1);
    }

    fn check_map(name: &str) {
        let Some(bsp) = crate::testdata::bsp(name) else {
            return;
        };
        for s in bsp.surfaces.iter().filter(|s| s.surface_type == 2) {
            let (w, h) = (s.patch_width as usize, s.patch_height as usize);
            let first = s.first_vert as usize;
            let pts: Vec<[f32; 3]> = bsp.verts[first..first + w * h]
                .iter()
                .map(|v| v.xyz)
                .collect();
            let pc = generate(w, h, &pts);
            assert!(pc.planes.len() <= MAX_PATCH_PLANES);
            for f in &pc.facets {
                assert!((f.surface_plane as usize) < pc.planes.len());
                for &b in &f.border_planes[..f.num_borders as usize] {
                    assert!((b as usize) < pc.planes.len());
                }
            }
            for p in &pc.planes {
                let n = normal_of(&p.plane);
                assert!((dot(&n, &n).sqrt() - 1.0).abs() < 1e-3);
            }
            for c in [pts[0], pts[w - 1], pts[(h - 1) * w], pts[w * h - 1]] {
                for (k, v) in c.iter().enumerate() {
                    assert!(*v >= pc.bounds[0][k] && *v <= pc.bounds[1][k]);
                }
            }
        }
    }

    #[test]
    fn real_maps() {
        for m in ["oa_dm1", "oa_ctf2", "am_thornish"] {
            check_map(m);
        }
    }
}
