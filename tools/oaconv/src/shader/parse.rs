//! Shader script parsing (ioquake3 tr_shader.c, GPL-2.0).
//!
//! Precedence: the engine concatenates the script files sorted by name and
//! `FindShaderInShaderText` returns the first match, so the first definition wins.

use super::{classify, strip_ext, Shader, ShaderSet, Stage};
use crate::vfs::Vfs;

/// COM_Parse-style tokens with line breaks kept as `"\n"` tokens; `//` and
/// `/* */` comments removed; quoted strings unquoted.
pub fn tokenize(text: &str) -> Vec<String> {
    let c: Vec<char> = text.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while i < c.len() {
        let ch = c[i];
        if ch == '\n' {
            out.push("\n".to_string());
            i += 1;
        } else if ch <= ' ' {
            i += 1;
        } else if ch == '/' && c.get(i + 1) == Some(&'/') {
            while i < c.len() && c[i] != '\n' {
                i += 1;
            }
        } else if ch == '/' && c.get(i + 1) == Some(&'*') {
            i += 2;
            while i < c.len() && !(c[i] == '*' && c.get(i + 1) == Some(&'/')) {
                i += 1;
            }
            i += 2;
        } else if ch == '"' {
            i += 1;
            let start = i;
            while i < c.len() && c[i] != '"' {
                i += 1;
            }
            out.push(c[start..i.min(c.len())].iter().collect());
            i += 1;
        } else {
            let start = i;
            while i < c.len() && c[i] > ' ' {
                i += 1;
            }
            out.push(c[start..i].iter().collect());
        }
    }
    out
}

/// Tokens grouped into lines; a lone brace token is always its own line.
fn lines(text: &str) -> Vec<Vec<String>> {
    let mut out = Vec::new();
    let mut cur: Vec<String> = Vec::new();
    for t in tokenize(text) {
        if t == "\n" {
            if !cur.is_empty() {
                out.push(std::mem::take(&mut cur));
            }
        } else if t == "{" || t == "}" {
            if !cur.is_empty() {
                out.push(std::mem::take(&mut cur));
            }
            out.push(vec![t]);
        } else {
            cur.push(t.to_ascii_lowercase());
        }
    }
    if !cur.is_empty() {
        out.push(cur);
    }
    out
}

fn parse_stage(ls: &[Vec<String>], i: &mut usize) -> Option<Stage> {
    let mut st = Stage::default();
    let mut explicit_depth = false;
    loop {
        let l = ls.get(*i)?;
        *i += 1;
        if l[0] == "}" {
            break;
        }
        let args = &l[1..];
        let arg = |n: usize| args.get(n).cloned().unwrap_or_default();
        match l[0].as_str() {
            "map" | "clampmap" => {
                st.clamp = l[0] == "clampmap";
                st.maps = vec![arg(0)];
            }
            "animmap" => {
                st.anim_freq = args.first().and_then(|f| f.parse().ok());
                st.maps = args.iter().skip(1).cloned().collect();
            }
            "videomap" => st.video = Some(arg(0)),
            "blendfunc" => {
                let pair = |a: &str, b: &str| Some([a.to_string(), b.to_string()]);
                st.blend = match (args.len(), arg(0).as_str()) {
                    (1, "add") => pair("gl_one", "gl_one"),
                    (1, "filter") => pair("gl_dst_color", "gl_zero"),
                    (1, "blend") => pair("gl_src_alpha", "gl_one_minus_src_alpha"),
                    (n, _) if n >= 2 => pair(&arg(0), &arg(1)),
                    _ => None,
                };
            }
            "rgbgen" => st.rgb_gen = args.to_vec(),
            "alphagen" => st.alpha_gen = args.to_vec(),
            "tcgen" | "texgen" => st.tc_gen = args.to_vec(),
            "tcmod" => st.tc_mods.push(args.to_vec()),
            "alphafunc" => st.alpha_func = args.first().cloned(),
            "depthfunc" => st.depth_func = args.first().cloned(),
            "depthwrite" => explicit_depth = true,
            "detail" => st.detail = true,
            _ => {}
        }
    }
    let opaque = st
        .blend
        .as_ref()
        .is_none_or(|b| b[0] == "gl_one" && b[1] == "gl_zero");
    st.depth_write = explicit_depth || opaque;
    st.rgb_gen_default = if opaque {
        "identitylighting"
    } else {
        "identity"
    }
    .to_string();
    Some(st)
}

fn parse_shader(name: &str, file: &str, ls: &[Vec<String>], i: &mut usize) -> Option<Shader> {
    let mut sh = Shader {
        name: strip_ext(name),
        source: file.to_string(),
        cull: "front".to_string(),
        ..Shader::default()
    };
    loop {
        let l = ls.get(*i)?;
        *i += 1;
        let args = l[1..].to_vec();
        match l[0].as_str() {
            "}" => break,
            "{" => sh.stages.push(parse_stage(ls, i)?),
            "surfaceparm" => sh.surfaceparms.extend(args.first().cloned()),
            "cull" => {
                sh.cull = match args.first().map(String::as_str) {
                    Some("twosided" | "disable" | "none") => "none",
                    Some("back" | "backside" | "backsided") => "back",
                    _ => "front",
                }
                .to_string();
            }
            "sort" => sh.sort = args.first().cloned(),
            "skyparms" => sh.sky_parms = Some(args),
            "deformvertexes" => sh.deforms.push(args),
            "fogparms" => sh.fog_parms = Some(args),
            "polygonoffset" => sh.polygon_offset = true,
            "portal" => sh.portal = true,
            "entitymergable" => sh.entity_merge = true,
            k if k.starts_with("q3map_")
                || k.starts_with("qer_")
                || k.starts_with("light")
                || k == "tesssize" => {}
            _ => sh.other.push(l.clone()),
        }
    }
    sh.class = classify(&sh);
    Some(sh)
}

/// Every shader in one script file, in file order (`source` = `file`).
pub fn parse_text(text: &str, file: &str) -> Vec<Shader> {
    let ls = lines(text);
    let mut out = Vec::new();
    let mut i = 0;
    while i < ls.len() {
        let name = ls[i][0].clone();
        i += 1;
        if ls.get(i).is_none_or(|l| l[0] != "{") {
            eprintln!("{file}: shader '{name}' without opening brace, skipped");
            continue;
        }
        i += 1;
        match parse_shader(&name, file, &ls, &mut i) {
            Some(s) => out.push(s),
            None => eprintln!("{file}: shader '{name}' is unterminated, skipped"),
        }
    }
    out
}

pub(super) fn load(vfs: &Vfs) -> ShaderSet {
    let mut set = ShaderSet::default();
    for path in vfs.list("scripts/", &[".shader"]) {
        let Some(bytes) = vfs.read(&path) else {
            continue;
        };
        for s in parse_text(&String::from_utf8_lossy(&bytes), &path) {
            set.shaders.entry(s.name.clone()).or_insert(s);
        }
    }
    set
}

pub(super) fn implicit(name: &str, lightmapped: bool, vfs: &Vfs) -> Shader {
    let name = strip_ext(name);
    let mut sh = Shader {
        name: name.clone(),
        source: "<implicit>".to_string(),
        cull: "front".to_string(),
        ..Shader::default()
    };
    if vfs.find_image(&name).is_some() {
        let base = Stage {
            maps: vec![name],
            depth_write: true,
            rgb_gen_default: "identitylighting".to_string(),
            ..Stage::default()
        };
        if lightmapped {
            sh.stages.push(Stage {
                maps: vec!["$lightmap".to_string()],
                depth_write: true,
                rgb_gen_default: "identity".to_string(),
                ..Stage::default()
            });
            sh.stages.push(Stage {
                blend: Some(["gl_dst_color".to_string(), "gl_zero".to_string()]),
                depth_write: false,
                rgb_gen_default: "identity".to_string(),
                ..base
            });
        } else {
            sh.stages.push(Stage {
                rgb_gen: vec!["exactvertex".to_string()],
                ..base
            });
        }
    }
    sh.class = classify(&sh);
    sh
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::shader::ShaderClass;
    use std::collections::BTreeMap;

    #[test]
    fn snippets() {
        let t = "// c\nfoo /* x */\n{\n cull twosided\n {\n map a.tga\n blendFunc filter\n }\n {\n map b.tga\n blendFunc GL_ONE GL_ONE\n depthWrite\n }\n}\n";
        let s = &parse_text(t, "f")[0];
        assert_eq!(s.cull, "none");
        assert_eq!(s.stages[0].blend.as_ref().unwrap()[0], "gl_dst_color");
        assert_eq!(s.stages[0].rgb_gen_default, "identity");
        assert!(!s.stages[0].depth_write);
        assert!(s.stages[1].depth_write);
    }

    #[test]
    fn real_data() {
        let Some(vfs) = crate::testdata::vfs() else {
            return;
        };
        let set = ShaderSet::load(vfs);
        assert!(set.shaders.len() > 1000);
        let mut hist: BTreeMap<ShaderClass, usize> = BTreeMap::new();
        for s in set.shaders.values() {
            *hist.entry(s.class).or_default() += 1;
        }
        eprintln!("{hist:?}");
        assert_eq!(
            set.get("textures/common/caulk").unwrap().class,
            ShaderClass::Nodraw
        );
        assert!(set
            .shaders
            .values()
            .any(|s| s.sky_parms.is_some() && s.class == ShaderClass::Sky));
        let r = set.resolve("textures/gothic_block/blocks10", true, vfs);
        assert_eq!(r.stages.len(), 2);
        assert_eq!(r.class, ShaderClass::Opaque);
        for m in ["oa_dm1", "oa_ctf2", "am_thornish"] {
            if let Some(b) = crate::testdata::bsp(m) {
                for sh in &b.shaders {
                    set.resolve(&sh.name, true, vfs);
                }
            }
        }
    }
}
