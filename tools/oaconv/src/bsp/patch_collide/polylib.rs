//! Port of ioquake3 qcommon/cm_polylib.c (GPL-2.0): the winding helpers
//! `CM_GeneratePatchCollide` needs, plus the q_shared vector math they use.

pub(super) type Vec3 = [f32; 3];
pub(super) type Winding = Vec<Vec3>;

pub(super) const MAX_MAP_BOUNDS: f32 = 65535.0;

pub(super) const SIDE_FRONT: usize = 0;
pub(super) const SIDE_BACK: usize = 1;
pub(super) const SIDE_ON: usize = 2;

pub(super) fn dot(a: &Vec3, b: &Vec3) -> f32 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

pub(super) fn sub(a: &Vec3, b: &Vec3) -> Vec3 {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}

pub(super) fn cross(a: &Vec3, b: &Vec3) -> Vec3 {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}

/// `v + s * b` (VectorMA).
pub(super) fn ma(v: &Vec3, s: f32, b: &Vec3) -> Vec3 {
    [v[0] + s * b[0], v[1] + s * b[1], v[2] + s * b[2]]
}

/// ioquake3's VectorNormalize: returns the old length (as `length *
/// ilength`) and leaves a zero vector alone.
pub(super) fn normalize(v: &mut Vec3) -> f32 {
    let mut length = dot(v, v);
    if length != 0.0 {
        let ilength = 1.0 / (f64::from(length).sqrt() as f32);
        length *= ilength;
        v[0] *= ilength;
        v[1] *= ilength;
        v[2] *= ilength;
    }
    length
}

/// `-eps <= d <= eps` the way C compares a float against a double
/// `#define` epsilon: in double.
pub(super) fn within(d: f32, eps: f64) -> bool {
    (-eps..=eps).contains(&f64::from(d))
}

pub(super) fn base_winding_for_plane(normal: &Vec3, dist: f32) -> Winding {
    let mut max = -MAX_MAP_BOUNDS;
    let mut x = None;
    for (i, n) in normal.iter().enumerate() {
        let v = n.abs();
        if v > max {
            x = Some(i);
            max = v;
        }
    }
    let Some(x) = x else {
        panic!("BaseWindingForPlane: no axis found");
    };
    let mut vup = match x {
        2 => [1.0, 0.0, 0.0],
        _ => [0.0, 0.0, 1.0],
    };
    let v = dot(&vup, normal);
    vup = ma(&vup, -v, normal);
    normalize(&mut vup);
    let org = [normal[0] * dist, normal[1] * dist, normal[2] * dist];
    let vright = cross(&vup, normal);
    let vup = vup.map(|c| c * MAX_MAP_BOUNDS);
    let vright = vright.map(|c| c * MAX_MAP_BOUNDS);
    let add = |a: &Vec3, b: &Vec3| [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
    vec![
        add(&sub(&org, &vright), &vup),
        add(&add(&org, &vright), &vup),
        sub(&add(&org, &vright), &vup),
        sub(&sub(&org, &vright), &vup),
    ]
}

/// ChopWindingInPlace: `None` when nothing is left in front of the plane.
pub(super) fn chop_winding(w: Winding, normal: &Vec3, dist: f32, epsilon: f32) -> Option<Winding> {
    let n = w.len();
    let mut dists = Vec::with_capacity(n + 1);
    let mut sides = Vec::with_capacity(n + 1);
    let mut counts = [0usize; 3];
    for p in &w {
        let d = dot(p, normal) - dist;
        let s = if d > epsilon {
            SIDE_FRONT
        } else if d < -epsilon {
            SIDE_BACK
        } else {
            SIDE_ON
        };
        dists.push(d);
        sides.push(s);
        counts[s] += 1;
    }
    sides.push(sides[0]);
    dists.push(dists[0]);

    if counts[SIDE_FRONT] == 0 {
        return None;
    }
    if counts[SIDE_BACK] == 0 {
        return Some(w);
    }

    let mut f = Vec::with_capacity(n + 4);
    for i in 0..n {
        let p1 = w[i];
        if sides[i] == SIDE_ON {
            f.push(p1);
            continue;
        }
        if sides[i] == SIDE_FRONT {
            f.push(p1);
        }
        if sides[i + 1] == SIDE_ON || sides[i + 1] == sides[i] {
            continue;
        }
        let p2 = w[(i + 1) % n];
        let t = dists[i] / (dists[i] - dists[i + 1]);
        f.push(std::array::from_fn(|j| {
            if normal[j] == 1.0 {
                dist
            } else if normal[j] == -1.0 {
                -dist
            } else {
                p1[j] + t * (p2[j] - p1[j])
            }
        }));
    }
    Some(f)
}

pub(super) fn winding_bounds(w: &Winding) -> (Vec3, Vec3) {
    let mut mins = [MAX_MAP_BOUNDS; 3];
    let mut maxs = [-MAX_MAP_BOUNDS; 3];
    for p in w {
        mins = std::array::from_fn(|j| mins[j].min(p[j]));
        maxs = std::array::from_fn(|j| maxs[j].max(p[j]));
    }
    (mins, maxs)
}
