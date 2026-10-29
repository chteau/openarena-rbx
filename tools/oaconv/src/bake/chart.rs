//! Charts: groups of triangles that get one rectangle of atlas space, with
//! a flat 2D parameterisation in world units.

use crate::bsp::DrawVert;

use super::shade::color_shift;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct BVert {
    pub pos: [f32; 3],
    pub normal: [f32; 3],
    pub st: [f32; 2],
    pub lm: [f32; 2],
    /// Vertex light after the overbright shift, 0..1.
    pub color: [f32; 4],
    /// Chart space, world units.
    pub uv: [f32; 2],
}

impl BVert {
    pub fn from_draw(v: &DrawVert) -> Self {
        let [r, g, b] = color_shift([v.color[0], v.color[1], v.color[2]]);
        Self {
            pos: v.xyz,
            normal: v.normal,
            st: v.st,
            lm: v.lightmap,
            color: [r, g, b, v.color[3]].map(|c| c as f32 / 255.0),
            uv: [0.0; 2],
        }
    }

    pub fn lerp(&self, o: &Self, t: f32) -> Self {
        fn l<const N: usize>(a: [f32; N], b: [f32; N], t: f32) -> [f32; N] {
            std::array::from_fn(|i| a[i] + (b[i] - a[i]) * t)
        }
        Self {
            pos: l(self.pos, o.pos, t),
            normal: l(self.normal, o.normal, t),
            st: l(self.st, o.st, t),
            lm: l(self.lm, o.lm, t),
            color: l(self.color, o.color, t),
            uv: l(self.uv, o.uv, t),
        }
    }
}

pub type Tri = [BVert; 3];

pub fn sub(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}
pub fn dot(a: [f32; 3], b: [f32; 3]) -> f32 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}
pub fn cross(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}
pub fn normalize(a: [f32; 3]) -> [f32; 3] {
    let l = dot(a, a).sqrt();
    if l > 0.0 {
        a.map(|v| v / l)
    } else {
        a
    }
}

/// Front-facing normal of a Quake (clockwise) triangle.
pub fn tri_normal(a: [f32; 3], b: [f32; 3], c: [f32; 3]) -> [f32; 3] {
    normalize(cross(sub(c, a), sub(b, a)))
}

fn basis(n: [f32; 3]) -> ([f32; 3], [f32; 3]) {
    let a = if n[2].abs() < 0.9 {
        [0.0, 0.0, 1.0]
    } else {
        [1.0, 0.0, 0.0]
    };
    let u = normalize(cross(a, n));
    (u, cross(n, u))
}

fn project(tris: &mut [Tri], n: [f32; 3]) {
    let (u, v) = basis(n);
    for t in tris.iter_mut() {
        for p in t.iter_mut() {
            p.uv = [dot(p.pos, u), dot(p.pos, v)];
        }
    }
}

fn find(parent: &mut [usize], mut i: usize) -> usize {
    while parent[i] != i {
        parent[i] = parent[parent[i]];
        i = parent[i];
    }
    i
}

/// Planar faces: one chart in the face plane.
pub fn planar(verts: &[DrawVert], tris: &[[u32; 3]], normal: [f32; 3]) -> Vec<Vec<Tri>> {
    let mut out: Vec<Tri> = tris
        .iter()
        .map(|t| t.map(|i| BVert::from_draw(&verts[i as usize])))
        .collect();
    let n = if dot(normal, normal) > 0.5 {
        normal
    } else {
        out.iter()
            .map(|t| tri_normal(t[0].pos, t[1].pos, t[2].pos))
            .find(|n| dot(*n, *n) > 0.5)
            .unwrap_or([0.0, 0.0, 1.0])
    };
    project(&mut out, n);
    vec![out]
}

/// Triangle soups: connected triangles sharing a plane form one chart each.
pub fn soup(verts: &[DrawVert], tris: &[[u32; 3]]) -> Vec<Vec<Tri>> {
    let keys: Vec<Option<([i32; 3], i32)>> = tris
        .iter()
        .map(|t| {
            let [a, b, c] = t.map(|i| verts[i as usize].xyz);
            let n = tri_normal(a, b, c);
            (dot(n, n) > 0.5).then(|| {
                (
                    n.map(|v| (v * 64.0).round() as i32),
                    (dot(n, a) / 2.0).round() as i32,
                )
            })
        })
        .collect();
    let mut parent: Vec<usize> = (0..tris.len()).collect();
    let mut owner: std::collections::HashMap<(u32, ([i32; 3], i32)), usize> = Default::default();
    for (ti, t) in tris.iter().enumerate() {
        let Some(key) = keys[ti] else { continue };
        for &v in t {
            match owner.get(&(v, key)) {
                Some(&o) => {
                    let (a, b) = (find(&mut parent, o), find(&mut parent, ti));
                    parent[a] = b;
                }
                None => {
                    owner.insert((v, key), ti);
                }
            }
        }
    }
    let mut groups: std::collections::BTreeMap<usize, Vec<usize>> = Default::default();
    for (ti, key) in keys.iter().enumerate() {
        if key.is_some() {
            groups.entry(find(&mut parent, ti)).or_default().push(ti);
        }
    }
    groups
        .into_values()
        .map(|members| {
            let t0 = tris[members[0]].map(|i| verts[i as usize].xyz);
            let n = tri_normal(t0[0], t0[1], t0[2]);
            let mut out: Vec<Tri> = members
                .iter()
                .map(|&ti| tris[ti].map(|i| BVert::from_draw(&verts[i as usize])))
                .collect();
            project(&mut out, n);
            out
        })
        .collect()
}

/// Tessellated patches: one chart laid out on the grid, columns and rows
/// spaced by their average arc length.
pub fn patch(verts: &[DrawVert], width: usize, height: usize, tris: &[[u32; 3]]) -> Vec<Vec<Tri>> {
    let dist = |a: usize, b: usize| {
        let d = sub(verts[a].xyz, verts[b].xyz);
        dot(d, d).sqrt()
    };
    let mut u = vec![0.0f32; width];
    for i in 1..width {
        let step: f32 = (0..height)
            .map(|j| dist(j * width + i, j * width + i - 1))
            .sum::<f32>()
            / height as f32;
        u[i] = u[i - 1] + step;
    }
    let mut v = vec![0.0f32; height];
    for j in 1..height {
        let step: f32 = (0..width)
            .map(|i| dist(j * width + i, (j - 1) * width + i))
            .sum::<f32>()
            / width as f32;
        v[j] = v[j - 1] + step;
    }
    let out = tris
        .iter()
        .filter(|t| {
            let [a, b, c] = t.map(|i| verts[i as usize].xyz);
            dot(cross(sub(b, a), sub(c, a)), cross(sub(b, a), sub(c, a))) > 1e-8
        })
        .map(|t| {
            t.map(|i| {
                let i = i as usize;
                let mut p = BVert::from_draw(&verts[i]);
                p.uv = [u[i % width], v[i / width]];
                p
            })
        })
        .collect();
    vec![out]
}

pub fn bounds(tris: &[Tri]) -> ([f32; 2], [f32; 2]) {
    let mut min = [f32::MAX; 2];
    let mut max = [f32::MIN; 2];
    for p in tris.iter().flatten() {
        for k in 0..2 {
            min[k] = min[k].min(p.uv[k]);
            max[k] = max[k].max(p.uv[k]);
        }
    }
    (min, max)
}

fn clip(poly: &[BVert], axis: usize, value: f32, keep_above: bool) -> Vec<BVert> {
    let inside = |p: &BVert| {
        if keep_above {
            p.uv[axis] >= value
        } else {
            p.uv[axis] <= value
        }
    };
    let mut out = Vec::with_capacity(poly.len() + 2);
    for i in 0..poly.len() {
        let (a, b) = (&poly[i], &poly[(i + 1) % poly.len()]);
        if inside(a) {
            out.push(*a);
        }
        if inside(a) != inside(b) {
            let t = (value - a.uv[axis]) / (b.uv[axis] - a.uv[axis]);
            out.push(a.lerp(b, t));
        }
    }
    out
}

/// Cuts a chart into pieces no larger than `max_extent` (world units) on
/// either axis, clipping triangles on a regular grid.
pub fn split(tris: Vec<Tri>, max_extent: f32) -> Vec<Vec<Tri>> {
    let (min, max) = bounds(&tris);
    let nx = ((max[0] - min[0]) / max_extent).ceil().max(1.0) as usize;
    let ny = ((max[1] - min[1]) / max_extent).ceil().max(1.0) as usize;
    if nx == 1 && ny == 1 {
        return vec![tris];
    }
    let cw = (max[0] - min[0]) / nx as f32;
    let ch = (max[1] - min[1]) / ny as f32;
    let mut cells: Vec<Vec<Tri>> = vec![Vec::new(); nx * ny];
    for t in &tris {
        let (tmin, tmax) = bounds(std::slice::from_ref(t));
        let cell = |v: f32, lo: f32, size: f32, n: usize| {
            (((v - lo) / size).floor().max(0.0) as usize).min(n - 1)
        };
        for cy in cell(tmin[1], min[1], ch, ny)..=cell(tmax[1], min[1], ch, ny) {
            for cx in cell(tmin[0], min[0], cw, nx)..=cell(tmax[0], min[0], cw, nx) {
                let x0 = min[0] + cx as f32 * cw;
                let y0 = min[1] + cy as f32 * ch;
                let mut poly = t.to_vec();
                if cx > 0 {
                    poly = clip(&poly, 0, x0, true);
                }
                if cx + 1 < nx {
                    poly = clip(&poly, 0, x0 + cw, false);
                }
                if cy > 0 {
                    poly = clip(&poly, 1, y0, true);
                }
                if cy + 1 < ny {
                    poly = clip(&poly, 1, y0 + ch, false);
                }
                for k in 1..poly.len().saturating_sub(1) {
                    cells[cy * nx + cx].push([poly[0], poly[k], poly[k + 1]]);
                }
            }
        }
    }
    cells.into_iter().filter(|c| !c.is_empty()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dv(x: f32, y: f32) -> DrawVert {
        DrawVert {
            xyz: [x, y, 0.0],
            st: [x / 64.0, y / 64.0],
            ..Default::default()
        }
    }

    #[test]
    fn split_covers_the_same_area() {
        let verts = [
            dv(0.0, 0.0),
            dv(1000.0, 0.0),
            dv(0.0, 700.0),
            dv(1000.0, 700.0),
        ];
        let tris = [[0, 2, 1], [1, 2, 3]];
        let charts = planar(&verts, &tris, [0.0, 0.0, 1.0]);
        let area = |ts: &[Tri]| -> f32 {
            ts.iter()
                .map(|t| {
                    let c = cross(sub(t[1].pos, t[0].pos), sub(t[2].pos, t[0].pos));
                    dot(c, c).sqrt() / 2.0
                })
                .sum()
        };
        let pieces = split(charts[0].clone(), 300.0);
        assert_eq!(pieces.len(), 4 * 3);
        let total: f32 = pieces.iter().map(|p| area(p)).sum();
        assert!((total - 700_000.0).abs() < 1.0, "{total}");
        for p in &pieces {
            let (min, max) = bounds(p);
            assert!(max[0] - min[0] <= 300.0 + 1e-3 && max[1] - min[1] <= 300.0 + 1e-3);
        }
        // Attributes are interpolated with the cut, not copied.
        let any = pieces
            .iter()
            .flatten()
            .flatten()
            .find(|v| v.pos[0] > 1.0 && v.pos[0] < 999.0)
            .unwrap();
        assert!((any.st[0] - any.pos[0] / 64.0).abs() < 1e-3);
    }

    #[test]
    fn soup_groups_coplanar_connected_triangles() {
        // Two coplanar triangles sharing an edge + one far away on another plane.
        let mut verts: Vec<DrawVert> =
            vec![dv(0.0, 0.0), dv(10.0, 0.0), dv(0.0, 10.0), dv(10.0, 10.0)];
        verts.extend(
            [[0.0, 0.0, 50.0], [0.0, 10.0, 50.0], [0.0, 0.0, 60.0]].map(|p| DrawVert {
                xyz: p,
                ..Default::default()
            }),
        );
        let charts = soup(&verts, &[[0, 2, 1], [1, 2, 3], [4, 5, 6]]);
        let mut sizes: Vec<usize> = charts.iter().map(Vec::len).collect();
        sizes.sort();
        assert_eq!(sizes, vec![1, 2]);
    }
}
