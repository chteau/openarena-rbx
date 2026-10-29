//! Render meshes in Quake space, before the glTF writer converts them.

use serde::Serialize;

use crate::shader::ShaderClass;

/// Roblox's per-MeshPart triangle limit.
pub const MAX_TRIS: usize = 20_000;

#[derive(Clone, Debug, Default)]
pub struct Mesh {
    /// Unique within its glTF file; becomes the MeshPart's name.
    pub name: String,
    pub class: ShaderClass,
    /// The shader the client animates (non-baked), or `"atlas"` for baked meshes.
    pub shader: String,
    /// Build-relative PNG this mesh is textured with.
    pub texture: Option<String>,
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
            .map(|(n, tris)| {
                let mut remap = vec![u32::MAX; self.positions.len()];
                let mut piece = Mesh {
                    name: format!("{}_{n}", self.name),
                    class: self.class,
                    shader: self.shader.clone(),
                    texture: self.texture.clone(),
                    ..Default::default()
                };
                for &i in tris {
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
            })
            .collect()
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
        let mut m = Mesh { name: "m".into(), ..Default::default() };
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
        assert!(pieces.iter().all(|p| p.indices.iter().all(|&i| (i as usize) < p.positions.len())));
    }
}
