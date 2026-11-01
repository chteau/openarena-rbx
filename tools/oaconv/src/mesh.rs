//! Render meshes in Quake space, before the glTF writer converts them.

use serde::Serialize;

use crate::shader::ShaderClass;

/// Roblox's per-MeshPart triangle limit.
pub const MAX_TRIS: usize = 20_000;
/// Roblox's largest part Size on any axis, in Quake units (2048 studs).
pub const MAX_EXTENT: f32 = 2048.0 * 8.0;

#[derive(Clone, Debug, Default)]
pub struct Mesh {
    /// Unique within its glTF file; becomes the MeshPart's name.
    pub name: String,
    pub class: ShaderClass,
    /// The shader the client animates (non-baked), or `"atlas"` for baked meshes.
    pub shader: String,
    /// Build-relative PNG this mesh is textured with.
    pub texture: Option<String>,
    /// Drawn over a baked copy of the same triangles: only the shader's
    /// animated stages, added on top (see docs/conv-notes.md).
    pub overlay: bool,
    /// Quake units and axes.
    pub positions: Vec<[f32; 3]>,
    pub normals: Vec<[f32; 3]>,
    pub uvs: Vec<[f32; 2]>,
    /// Vertex light with overbright applied: the fallback for non-baked meshes.
    pub colors: Vec<[u8; 4]>,
    /// Quake winding: clockwise seen from the front. The glTF writer flips it.
    pub indices: Vec<u32>,
}

/// What the manifest records per mesh so assembly can place it whatever the
/// importer does to the origin: Roblox studs and axes.
#[derive(Clone, Debug, Serialize)]
pub struct MeshInfo {
    pub name: String,
    pub class: ShaderClass,
    pub shader: String,
    pub texture: Option<String>,
    pub overlay: bool,
    pub triangles: usize,
    pub center: [f32; 3],
    pub size: [f32; 3],
}

impl Mesh {
    pub fn tri_count(&self) -> usize {
        self.indices.len() / 3
    }

    /// Appends `other`'s geometry (same material assumed).
    pub fn append(&mut self, other: &Mesh) {
        let base = self.positions.len() as u32;
        self.positions.extend_from_slice(&other.positions);
        self.normals.extend_from_slice(&other.normals);
        self.uvs.extend_from_slice(&other.uvs);
        self.colors.extend_from_slice(&other.colors);
        self.indices.extend(other.indices.iter().map(|i| i + base));
    }

    /// Splits into pieces of at most `max_tris` triangles, named `name_0`,
    /// `name_1`, ... (unchanged when it already fits). Vertices are
    /// re-indexed per piece.
    pub fn split(self, max_tris: usize) -> Vec<Mesh> {
        if self.tri_count() <= max_tris {
            return vec![self];
        }
        self.indices
            .chunks(max_tris * 3)
            .enumerate()
            .map(|(n, tris)| self.piece(n, tris.iter().copied()))
            .collect()
    }

    /// Splits into pieces no wider than `max` (Quake units) on any axis,
    /// named like `split`: triangles go to grid cells of `max / 2` by their
    /// centroid, so a piece stays within `max` unless one triangle alone is
    /// wider than half of it. Roblox clamps a part's Size to MAX_EXTENT
    /// studs, which squashes a bigger mesh.
    pub fn split_extent(self, max: f32) -> Vec<Mesh> {
        let (lo, hi) = self.bounds();
        if (0..3).all(|a| hi[a] - lo[a] <= max) {
            return vec![self];
        }
        let cell = max / 2.0;
        let mut cells: std::collections::BTreeMap<[i32; 3], Vec<u32>> = Default::default();
        for t in self.indices.chunks(3) {
            let key = std::array::from_fn(|a| {
                let c = t
                    .iter()
                    .map(|&i| self.positions[i as usize][a])
                    .sum::<f32>()
                    / 3.0;
                ((c - lo[a]) / cell).floor() as i32
            });
            cells.entry(key).or_default().extend_from_slice(t);
        }
        cells
            .values()
            .enumerate()
            .map(|(n, tris)| self.piece(n, tris.iter().copied()))
            .collect()
    }

    fn bounds(&self) -> ([f32; 3], [f32; 3]) {
        let mut lo = [f32::MAX; 3];
        let mut hi = [f32::MIN; 3];
        for p in &self.positions {
            for a in 0..3 {
                lo[a] = lo[a].min(p[a]);
                hi[a] = hi[a].max(p[a]);
            }
        }
        (lo, hi)
    }

    /// Piece `n` holding the triangles `indices` (re-indexed).
    fn piece(&self, n: usize, indices: impl Iterator<Item = u32>) -> Mesh {
        let mut remap = vec![u32::MAX; self.positions.len()];
        let mut piece = Mesh {
            name: format!("{}_{n}", self.name),
            class: self.class,
            shader: self.shader.clone(),
            texture: self.texture.clone(),
            overlay: self.overlay,
            ..Default::default()
        };
        for i in indices {
            let i = i as usize;
            if remap[i] == u32::MAX {
                remap[i] = piece.positions.len() as u32;
                piece.positions.push(self.positions[i]);
                piece.normals.push(self.normals[i]);
                piece.uvs.push(self.uvs[i]);
                piece.colors.push(self.colors[i]);
            }
            piece.indices.push(remap[i]);
        }
        piece
    }
}

/// Quake (x, y, z) units to Roblox (x, z, -y) studs (1 stud = 8 units).
pub fn to_roblox(p: [f32; 3]) -> [f32; 3] {
    [p[0] / 8.0, p[2] / 8.0, -p[1] / 8.0]
}

/// Same axes swap for a direction (no scale).
pub fn dir_to_roblox(n: [f32; 3]) -> [f32; 3] {
    [n[0], n[2], -n[1]]
}

#[cfg(test)]
mod tests {
    use super::*;

    fn quad_strip(quads: usize) -> Mesh {
        let mut m = Mesh {
            name: "m".into(),
            ..Default::default()
        };
        for q in 0..=quads {
            for y in 0..2 {
                m.positions.push([q as f32, y as f32, 0.0]);
                m.normals.push([0.0, 0.0, 1.0]);
                m.uvs.push([0.0, 0.0]);
                m.colors.push([255; 4]);
            }
        }
        for q in 0..quads as u32 {
            let a = q * 2;
            m.indices.extend([a, a + 1, a + 2, a + 1, a + 3, a + 2]);
        }
        m
    }

    #[test]
    fn split_keeps_every_triangle_under_the_limit() {
        let m = quad_strip(15);
        let total = m.tri_count();
        let pieces = m.split(7);
        assert_eq!(pieces.len(), 5);
        assert!(pieces.iter().all(|p| p.tri_count() <= 7));
        assert_eq!(pieces.iter().map(Mesh::tri_count).sum::<usize>(), total);
        assert!(pieces
            .iter()
            .all(|p| p.indices.iter().all(|&i| (i as usize) < p.positions.len())));
    }

    #[test]
    fn split_extent_keeps_every_piece_within_the_limit() {
        let m = quad_strip(40);
        let total = m.tri_count();
        let pieces = m.split_extent(10.0);
        assert!(pieces.len() > 1);
        assert_eq!(pieces.iter().map(Mesh::tri_count).sum::<usize>(), total);
        for p in &pieces {
            let (lo, hi) = p.bounds();
            assert!((0..3).all(|a| hi[a] - lo[a] <= 10.0), "{}", p.name);
        }
        assert_eq!(quad_strip(5).split_extent(10.0).len(), 1);
    }
}
