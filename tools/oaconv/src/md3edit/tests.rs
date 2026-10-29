use super::math::{dot, V3};
use super::*;
use crate::md3::{decode_normal, Md3Frame, Md3Surface};

/// A 13 x 13 sheet in the y-z plane facing +x, with a bump of `height` at
/// the centre, in two frames: as built, and turned 90 degrees about z.
fn bumped_sheet(height: f32) -> Md3 {
    let n = 13;
    let mut pos: Vec<V3> = Vec::new();
    for i in 0..n {
        for j in 0..n {
            let (y, z) = (i as f32 - 6.0, j as f32 - 6.0);
            let r2 = y * y + z * z;
            pos.push([height * (-r2 / 4.0).exp(), y, z]);
        }
    }
    let mut triangles = Vec::new();
    for i in 0..n - 1 {
        for j in 0..n - 1 {
            let a = (i * n + j) as u32;
            let (b, c, d) = (a + n as u32, a + 1, a + n as u32 + 1);
            triangles.push([a, c, b]);
            triangles.push([c, d, b]);
        }
    }
    let turn = |p: V3| [-p[1], p[0], p[2]];
    let frames = [
        pos.clone(),
        pos.iter().map(|&p| turn(p)).collect::<Vec<_>>(),
    ];
    let normals = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0]];
    Md3 {
        name: "sheet".into(),
        flags: 0,
        frames: (0..2)
            .map(|_| Md3Frame {
                bounds: [[-8.0; 3], [8.0; 3]],
                local_origin: [0.0; 3],
                radius: 8.0,
                name: String::new(),
            })
            .collect(),
        tags: vec![Vec::new(), Vec::new()],
        surfaces: vec![Md3Surface {
            name: "body".into(),
            flags: 0,
            shaders: Vec::new(),
            triangles,
            st: vec![[0.0; 2]; pos.len()],
            xyz: frames
                .iter()
                .map(|f| {
                    f.iter()
                        .map(|p| p.map(|c| (c / XYZ_SCALE).round() as i16))
                        .collect()
                })
                .collect(),
            normals: normals
                .iter()
                .map(|&n| vec![math::encode_normal(n); pos.len()])
                .collect(),
        }],
    }
}

fn chest() -> Region {
    Region {
        note: String::new(),
        center: [1.5, 0.0, 0.0],
        radius: [4.0, 4.5, 4.5],
        axis: [1.0, 0.0, 0.0],
        keep: 0.1,
        smooth: 2,
        core: 0.6,
        ring: 1.5,
        surfaces: Vec::new(),
    }
}

fn at(m: &Md3, f: usize, v: usize) -> V3 {
    m.surfaces[0].xyz[f][v].map(|c| c as f32 * XYZ_SCALE)
}

#[test]
fn flattens_the_bump_the_same_way_in_every_frame() {
    let model = bumped_sheet(3.0);
    let field = field(&model, 0, &[chest()]);
    let (out, moved) = apply(&model, 0, &field);
    assert!(moved > 0);
    let centre = 6 * 13 + 6;
    assert!(at(&out, 0, centre)[0] < 0.5, "{:?}", at(&out, 0, centre));
    for v in 0..169 {
        let (a, b) = (at(&out, 0, v), at(&out, 1, v));
        let turned = [-a[1], a[0], a[2]];
        for k in 0..3 {
            assert!(
                (turned[k] - b[k]).abs() < 0.05,
                "vertex {v}: {turned:?} vs {b:?}"
            );
        }
    }
    // The sheet's rim is outside the region and must not move.
    assert_eq!(out.surfaces[0].xyz[0][0], model.surfaces[0].xyz[0][0]);
    let n = decode_normal(out.surfaces[0].normals[0][centre]);
    assert!(dot(n, [1.0, 0.0, 0.0]) > 0.95, "{n:?}");
    let n = decode_normal(out.surfaces[0].normals[1][centre]);
    assert!(dot(n, [0.0, 1.0, 0.0]) > 0.95, "{n:?}");
}

#[test]
fn never_pushes_outward() {
    let model = bumped_sheet(-2.0);
    let (out, _) = apply(&model, 0, &field(&model, 0, &[chest()]));
    for v in 0..169 {
        assert!(at(&out, 0, v)[0] <= at(&model, 0, v)[0] + 1e-3);
    }
}

#[test]
fn a_lod_takes_the_full_models_offsets() {
    let full = bumped_sheet(3.0);
    let field = field(&full, 0, &[chest()]);
    let (a, _) = apply(&full, 0, &field);
    let (b, _) = apply(&bumped_sheet(3.0), 0, &field);
    assert_eq!(a.surfaces[0].xyz, b.surfaces[0].xyz);
}

/// The committed overlay is exactly what the config builds from the pk3s.
#[test]
fn overlay_matches_the_config() {
    let Some(base) = crate::testdata::vfs() else {
        return;
    };
    let repo = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let generated = generate(&repo, base).unwrap();
    assert!(!generated.files.is_empty());
    for (path, bytes) in &generated.files {
        let on_disk = std::fs::read(repo.join(crate::vfs::OVERLAY).join(path))
            .unwrap_or_else(|e| panic!("{path}: {e}; run `oaconv tone`"));
        assert!(on_disk == *bytes, "{path} is stale; run `oaconv tone`");
    }
}
