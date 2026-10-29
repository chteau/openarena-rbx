//! Shader script parsing (ioquake3 tr_shader.c, GPL-2.0).

use super::{Shader, ShaderSet};
use crate::vfs::Vfs;

/// COM_Parse-style tokens with line breaks kept as `"\n"` tokens; `//` and
/// `/* */` comments removed; quoted strings unquoted.
pub fn tokenize(_text: &str) -> Vec<String> {
    todo!()
}

/// Every shader in one script file, in file order (`source` = `file`).
pub fn parse_text(_text: &str, _file: &str) -> Vec<Shader> {
    todo!()
}

pub(super) fn load(_vfs: &Vfs) -> ShaderSet {
    todo!()
}

pub(super) fn implicit(_name: &str, _lightmapped: bool, _vfs: &Vfs) -> Shader {
    todo!()
}
