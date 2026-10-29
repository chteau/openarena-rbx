//! The entity lump: parsed key/value pairs and a categorised summary.

use serde_json::Value;

use super::Bsp;

/// One `{ ... }` block, pairs in file order.
#[derive(Clone, Debug, PartialEq)]
pub struct Entity {
    pub pairs: Vec<(String, String)>,
}

impl Entity {
    pub fn get(&self, key: &str) -> Option<&str> {
        self.pairs.iter().find(|(k, _)| k.eq_ignore_ascii_case(key)).map(|(_, v)| v.as_str())
    }
}

pub fn parse(_text: &str) -> Result<Vec<Entity>, String> {
    todo!()
}

/// The JSON written as `entities.json` (shape in docs/formats/entities.md).
pub fn summarize(_bsp: &Bsp) -> Result<Value, String> {
    todo!()
}

/// A Luau literal for any JSON value (`return <literal>` makes a ModuleScript).
pub fn to_luau(_value: &Value) -> String {
    todo!()
}
