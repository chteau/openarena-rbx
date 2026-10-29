//! The collision blob the Luau port of cm_load reads. Layout: docs/formats/collision.md.

use super::patch_collide::PatchCollide;
use super::Bsp;

/// What cm_load keeps of a map, patches already generated.
#[derive(Clone, Debug, PartialEq)]
pub struct CollisionMap {
    todo_fields: (),
}

impl CollisionMap {
    pub fn build(_bsp: &Bsp) -> Self {
        todo!()
    }
    pub fn to_bytes(&self) -> Vec<u8> {
        todo!()
    }
    pub fn from_bytes(_bytes: &[u8]) -> Result<Self, String> {
        todo!()
    }
}

#[allow(dead_code)]
fn _uses(_: PatchCollide) {}
