//! Binary glTF 2.0 (`.glb`) writer for [`Mesh`]es.

use crate::mesh::{Mesh, MeshInfo};

/// One `.glb` holding every mesh as its own node (named after the mesh),
/// converted to Roblox studs/axes. Returns the file and each mesh's info.
pub fn write_glb(_meshes: &[Mesh]) -> (Vec<u8>, Vec<MeshInfo>) {
    todo!()
}
