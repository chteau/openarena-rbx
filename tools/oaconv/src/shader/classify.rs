//! The render class of a parsed shader.

use super::{Shader, ShaderClass, Stage};

fn first_is(tokens: &[String], names: &[&str]) -> bool {
    tokens.first().is_some_and(|t| names.contains(&t.as_str()))
}

/// A stage the client must animate (not bakeable).
pub fn stage_animated(s: &Stage) -> bool {
    s.maps.len() > 1
        || s.video.is_some()
        || s.tc_mods
            .iter()
            .any(|m| !first_is(m, &["scale", "transform"]))
        || first_is(
            &s.rgb_gen,
            &["wave", "entity", "oneminusentity", "lightingdiffuse"],
        )
        || first_is(
            &s.alpha_gen,
            &[
                "wave",
                "entity",
                "oneminusentity",
                "lightingspecular",
                "portal",
            ],
        )
        || first_is(&s.tc_gen, &["environment"])
}

pub fn classify(shader: &Shader) -> ShaderClass {
    let has_parm = |p: &str| shader.surfaceparms.iter().any(|s| s == p);
    if shader.sky_parms.is_some() || has_parm("sky") {
        return ShaderClass::Sky;
    }
    if has_parm("nodraw") || shader.name == "noshader" || shader.stages.is_empty() {
        return ShaderClass::Nodraw;
    }
    if !shader.deforms.is_empty() {
        return ShaderClass::Deform;
    }
    if shader.stages.iter().any(|s| s.alpha_func.is_some()) {
        return ShaderClass::AlphaTest;
    }
    let opaque_first = shader.stages[0]
        .blend
        .as_ref()
        .is_none_or(|b| b[0] == "gl_one" && b[1] == "gl_zero");
    if shader.fog_parms.is_some() || has_parm("fog") || shader.portal || !opaque_first {
        return ShaderClass::Blend;
    }
    if shader.stages.iter().any(stage_animated) {
        return ShaderClass::Animated;
    }
    ShaderClass::Opaque
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::shader::parse_text;

    fn class_of(text: &str) -> ShaderClass {
        parse_text(text, "t.shader").remove(0).class
    }

    #[test]
    fn classes() {
        assert_eq!(class_of("a\n{\nskyParms x 512 -\n}"), ShaderClass::Sky);
        assert_eq!(
            class_of("a\n{\nsurfaceparm nodraw\n{\nmap a.tga\n}\n}"),
            ShaderClass::Nodraw
        );
        assert_eq!(
            class_of("a\n{\ndeformVertexes wave 1 sin 0 1 0 1\n{\nmap a.tga\n}\n}"),
            ShaderClass::Deform
        );
        assert_eq!(
            class_of("a\n{\n{\nmap a.tga\nalphaFunc GT0\n}\n}"),
            ShaderClass::AlphaTest
        );
        assert_eq!(
            class_of("a\n{\n{\nmap a.tga\nblendFunc add\n}\n}"),
            ShaderClass::Blend
        );
        assert_eq!(
            class_of("a\n{\n{\nmap a.tga\ntcMod scroll 1 0\n}\n}"),
            ShaderClass::Animated
        );
        assert_eq!(
            class_of("a\n{\n{\nmap a.tga\ntcMod scale 2 2\n}\n}"),
            ShaderClass::Opaque
        );
    }
}
