//! Grid subdivision from ioquake3 qcommon/cm_patch.c (GPL-2.0). Columns are
//! stored as `cols[i][j]`, matching the C `points[i][j]`; growable instead of
//! the fixed MAX_GRID_SIZE array.

use super::polylib::{dot, sub, within, Vec3};

pub(super) const SUBDIVIDE_DISTANCE: f32 = 16.0;
// C `#define`s, so the comparisons against them happen in double
const POINT_EPSILON: f64 = 0.1;
const WRAP_POINT_EPSILON: f64 = 0.1;

pub(super) struct Grid {
    pub cols: Vec<Vec<Vec3>>,
    pub wrap_width: bool,
    pub wrap_height: bool,
}

fn needs_subdivision(a: &Vec3, b: &Vec3, c: &Vec3) -> bool {
    let lmid: Vec3 = std::array::from_fn(|i| 0.5 * (a[i] + c[i]));
    let cmid: Vec3 = std::array::from_fn(|i| 0.5 * (0.5 * (a[i] + b[i]) + 0.5 * (b[i] + c[i])));
    let delta = sub(&cmid, &lmid);
    let dist = f64::from(dot(&delta, &delta)).sqrt() as f32;
    dist >= SUBDIVIDE_DISTANCE
}

fn subdivide(a: &Vec3, b: &Vec3, c: &Vec3) -> (Vec3, Vec3, Vec3) {
    let out1: Vec3 = std::array::from_fn(|i| 0.5 * (a[i] + b[i]));
    let out3: Vec3 = std::array::from_fn(|i| 0.5 * (b[i] + c[i]));
    let out2: Vec3 = std::array::from_fn(|i| 0.5 * (out1[i] + out3[i]));
    (out1, out2, out3)
}

fn compare_points(a: &Vec3, b: &Vec3) -> bool {
    (0..3).all(|i| {
        within(a[i] - b[i], POINT_EPSILON)
    })
}

impl Grid {
    pub fn width(&self) -> usize {
        self.cols.len()
    }

    pub fn height(&self) -> usize {
        self.cols[0].len()
    }

    pub fn set_wrap_width(&mut self) {
        let first = &self.cols[0];
        let last = &self.cols[self.cols.len() - 1];
        self.wrap_width = first.iter().zip(last).all(|(a, b)| {
            (0..3).all(|j| {
                within(a[j] - b[j], WRAP_POINT_EPSILON)
            })
        });
    }

    pub fn subdivide_columns(&mut self) {
        let mut i = 0;
        while i + 2 < self.width() {
            // cols[i] and cols[i+2] interpolate, cols[i+1] only approximates.
            let h = self.height();
            let flat = (0..h).all(|j| {
                !needs_subdivision(&self.cols[i][j], &self.cols[i + 1][j], &self.cols[i + 2][j])
            });
            if flat {
                self.cols.remove(i + 1);
                i += 1;
                continue;
            }
            let mut c1 = Vec::with_capacity(h);
            let mut c2 = Vec::with_capacity(h);
            let mut c3 = Vec::with_capacity(h);
            for j in 0..h {
                let (o1, o2, o3) =
                    subdivide(&self.cols[i][j], &self.cols[i + 1][j], &self.cols[i + 2][j]);
                c1.push(o1);
                c2.push(o2);
                c3.push(o3);
            }
            self.cols[i + 1] = c1;
            self.cols.insert(i + 2, c2);
            self.cols.insert(i + 3, c3);
            // the new approximating column at i+1 may need subdividing too
        }
    }

    pub fn remove_degenerate_columns(&mut self) {
        let mut i = 0;
        while i + 1 < self.width() {
            let degenerate = self.cols[i]
                .iter()
                .zip(&self.cols[i + 1])
                .all(|(a, b)| compare_points(a, b));
            if degenerate {
                self.cols.remove(i + 1);
            } else {
                i += 1;
            }
        }
    }

    pub fn transpose(&mut self) {
        let (w, h) = (self.width(), self.height());
        let cols = (0..h)
            .map(|j| (0..w).map(|i| self.cols[i][j]).collect())
            .collect();
        self.cols = cols;
        std::mem::swap(&mut self.wrap_width, &mut self.wrap_height);
    }
}
