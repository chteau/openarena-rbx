//! Small vector helpers, the best-fit rotation between two point sets and
//! the MD3 lat/long normal encoding.

pub type V3 = [f32; 3];

pub fn add(a: V3, b: V3) -> V3 {
    [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
}

pub fn sub(a: V3, b: V3) -> V3 {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}

pub fn scale(a: V3, s: f32) -> V3 {
    [a[0] * s, a[1] * s, a[2] * s]
}

pub fn dot(a: V3, b: V3) -> f32 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

pub fn cross(a: V3, b: V3) -> V3 {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}

pub fn normalize(a: V3) -> V3 {
    let l = dot(a, a).sqrt();
    if l > 1e-12 {
        scale(a, 1.0 / l)
    } else {
        a
    }
}

/// Row-major 3x3 rotation.
pub type M3 = [V3; 3];

pub fn mul(m: &M3, v: V3) -> V3 {
    [dot(m[0], v), dot(m[1], v), dot(m[2], v)]
}

/// Eigenvalues and eigenvectors (columns of `v`) of a symmetric 4x4 matrix, by Jacobi rotations.
#[allow(clippy::needless_range_loop)] // textbook matrix indexing
fn jacobi4(mut a: [[f64; 4]; 4]) -> ([f64; 4], [[f64; 4]; 4]) {
    let mut v = [[0.0; 4]; 4];
    for (i, row) in v.iter_mut().enumerate() {
        row[i] = 1.0;
    }
    for _ in 0..50 {
        let off: f64 = (0..4)
            .flat_map(|i| (0..4).filter(move |&j| j != i).map(move |j| (i, j)))
            .map(|(i, j)| a[i][j] * a[i][j])
            .sum();
        if off < 1e-24 {
            break;
        }
        for p in 0..3 {
            for q in p + 1..4 {
                if a[p][q].abs() < 1e-300 {
                    continue;
                }
                let theta = (a[q][q] - a[p][p]) / (2.0 * a[p][q]);
                let t = theta.signum() / (theta.abs() + (theta * theta + 1.0).sqrt());
                let t = if theta == 0.0 { 1.0 } else { t };
                let c = 1.0 / (t * t + 1.0).sqrt();
                let s = t * c;
                for k in 0..4 {
                    let (akp, akq) = (a[k][p], a[k][q]);
                    a[k][p] = c * akp - s * akq;
                    a[k][q] = s * akp + c * akq;
                }
                for k in 0..4 {
                    let (apk, aqk) = (a[p][k], a[q][k]);
                    a[p][k] = c * apk - s * aqk;
                    a[q][k] = s * apk + c * aqk;
                }
                for row in v.iter_mut() {
                    let (vp, vq) = (row[p], row[q]);
                    row[p] = c * vp - s * vq;
                    row[q] = s * vp + c * vq;
                }
            }
        }
    }
    ([a[0][0], a[1][1], a[2][2], a[3][3]], v)
}

/// The rotation that best maps the centred `from` points onto the centred
/// `to` points (Horn's quaternion method), weighted. Stable for flat sets.
pub fn best_rotation(from: &[V3], to: &[V3], w: &[f32]) -> M3 {
    let total: f32 = w.iter().sum();
    let centroid = |pts: &[V3]| {
        let mut c = [0.0; 3];
        for (p, &wi) in pts.iter().zip(w) {
            c = add(c, scale(*p, wi / total));
        }
        c
    };
    let (cf, ct) = (centroid(from), centroid(to));
    let mut s = [[0.0f64; 3]; 3];
    for ((p, q), &wi) in from.iter().zip(to).zip(w) {
        let (p, q) = (sub(*p, cf), sub(*q, ct));
        for i in 0..3 {
            for j in 0..3 {
                s[i][j] += (wi * p[i] * q[j]) as f64;
            }
        }
    }
    let n = [
        [
            s[0][0] + s[1][1] + s[2][2],
            s[1][2] - s[2][1],
            s[2][0] - s[0][2],
            s[0][1] - s[1][0],
        ],
        [
            s[1][2] - s[2][1],
            s[0][0] - s[1][1] - s[2][2],
            s[0][1] + s[1][0],
            s[2][0] + s[0][2],
        ],
        [
            s[2][0] - s[0][2],
            s[0][1] + s[1][0],
            -s[0][0] + s[1][1] - s[2][2],
            s[1][2] + s[2][1],
        ],
        [
            s[0][1] - s[1][0],
            s[2][0] + s[0][2],
            s[1][2] + s[2][1],
            -s[0][0] - s[1][1] + s[2][2],
        ],
    ];
    let (vals, vecs) = jacobi4(n);
    let best = (0..4)
        .max_by(|&a, &b| vals[a].total_cmp(&vals[b]))
        .unwrap_or(0);
    let [w, x, y, z] = [0, 1, 2, 3].map(|r| vecs[r][best] as f32);
    [
        [
            w * w + x * x - y * y - z * z,
            2.0 * (x * y - w * z),
            2.0 * (x * z + w * y),
        ],
        [
            2.0 * (x * y + w * z),
            w * w - x * x + y * y - z * z,
            2.0 * (y * z - w * x),
        ],
        [
            2.0 * (x * z - w * y),
            2.0 * (y * z + w * x),
            w * w - x * x - y * y + z * z,
        ],
    ]
}

/// The inverse of [`crate::md3::decode_normal`]: `lat << 8 | lng`, 2π/256 per step.
pub fn encode_normal(n: V3) -> u16 {
    let n = normalize(n);
    let k = 256.0 / (2.0 * std::f32::consts::PI);
    if n[0].abs() < 1e-6 && n[1].abs() < 1e-6 {
        return if n[2] > 0.0 { 0 } else { 128 };
    }
    let lat = (n[1].atan2(n[0]) * k).round().rem_euclid(256.0) as u16;
    let lng = (n[2].clamp(-1.0, 1.0).acos() * k).round().min(128.0) as u16;
    (lat << 8) | lng
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normal_round_trip() {
        for n in [
            [1.0, 0.0, 0.0],
            [0.0, -1.0, 0.0],
            [0.0, 0.0, 1.0],
            [0.0, 0.0, -1.0],
            [0.3, -0.5, 0.8],
        ] {
            let back = crate::md3::decode_normal(encode_normal(n));
            assert!(dot(normalize(n), back) > 0.998, "{n:?} -> {back:?}");
        }
    }

    #[test]
    fn recovers_a_rotation_of_a_flat_set() {
        let (c, s) = (0.6f32, 0.8f32);
        let r: M3 = [[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]];
        let from = [
            [0.0, 0.0, 0.0],
            [1.0, 0.0, 0.0],
            [0.0, 1.0, 0.0],
            [1.0, 1.0, 0.0],
        ];
        let to: Vec<V3> = from
            .iter()
            .map(|p| add(mul(&r, *p), [5.0, 2.0, 1.0]))
            .collect();
        let got = best_rotation(&from, &to, &[1.0; 4]);
        for i in 0..3 {
            for j in 0..3 {
                assert!((got[i][j] - r[i][j]).abs() < 1e-4, "{got:?}");
            }
        }
    }
}
