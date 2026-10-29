//! The entity lump: parsed key/value pairs and a categorised summary.
//! Tokenising follows `COM_Parse` / `G_ParseSpawnVars` (OA gamecode g_spawn.c).

use std::collections::BTreeMap;

use serde_json::{json, Map, Value};

use super::Bsp;

/// One `{ ... }` block, pairs in file order.
#[derive(Clone, Debug, PartialEq)]
pub struct Entity {
    pub pairs: Vec<(String, String)>,
}

impl Entity {
    pub fn get(&self, key: &str) -> Option<&str> {
        self.pairs
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(key))
            .map(|(_, v)| v.as_str())
    }

    /// Like the engine's repeated `AddSpawnVar`, the last duplicate wins here.
    fn last(&self, key: &str) -> Option<&str> {
        self.pairs
            .iter()
            .rev()
            .find(|(k, _)| k.eq_ignore_ascii_case(key))
            .map(|(_, v)| v.as_str())
    }
}

struct Token {
    text: String,
    quoted: bool,
}

fn next_token(b: &[u8], pos: &mut usize) -> Result<Option<Token>, String> {
    loop {
        while *pos < b.len() && b[*pos] <= b' ' {
            *pos += 1;
        }
        if b[*pos..].starts_with(b"//") {
            while *pos < b.len() && b[*pos] != b'\n' {
                *pos += 1;
            }
        } else if b[*pos..].starts_with(b"/*") {
            *pos += 2;
            while *pos < b.len() && !b[*pos..].starts_with(b"*/") {
                *pos += 1;
            }
            *pos = (*pos + 2).min(b.len());
        } else {
            break;
        }
    }
    if *pos >= b.len() {
        return Ok(None);
    }
    if b[*pos] == b'"' {
        let start = *pos + 1;
        let len = b[start..]
            .iter()
            .position(|&c| c == b'"')
            .ok_or("unterminated string in entity lump")?;
        *pos = start + len + 1;
        let text = String::from_utf8_lossy(&b[start..start + len]).into_owned();
        return Ok(Some(Token { text, quoted: true }));
    }
    let start = *pos;
    if matches!(b[start], b'{' | b'}') {
        *pos += 1;
        return Ok(Some(Token {
            text: (b[start] as char).to_string(),
            quoted: false,
        }));
    }
    while *pos < b.len() && b[*pos] > b' ' && !matches!(b[*pos], b'{' | b'}' | b'"') {
        *pos += 1;
    }
    let text = String::from_utf8_lossy(&b[start..*pos]).into_owned();
    Ok(Some(Token {
        text,
        quoted: false,
    }))
}

pub fn parse(text: &str) -> Result<Vec<Entity>, String> {
    let b = text.as_bytes();
    let mut pos = 0;
    let mut out = Vec::new();
    while let Some(tok) = next_token(b, &mut pos)? {
        if tok.quoted || tok.text != "{" {
            return Err(format!("found '{}' when expecting '{{'", tok.text));
        }
        let mut pairs = Vec::new();
        loop {
            let key = next_token(b, &mut pos)?.ok_or("unbalanced braces: EOF inside entity")?;
            if !key.quoted && key.text == "}" {
                break;
            }
            let value = next_token(b, &mut pos)?.ok_or("unbalanced braces: EOF inside entity")?;
            if !value.quoted && value.text == "}" {
                return Err("closing brace without data".into());
            }
            pairs.push((key.text, value.text));
        }
        out.push(Entity { pairs });
    }
    Ok(out)
}

fn category(class: &str) -> &'static str {
    const POWERUPS: [&str; 6] = [
        "item_quad",
        "item_enviro",
        "item_haste",
        "item_invis",
        "item_regen",
        "item_flight",
    ];
    match class {
        "info_player_deathmatch"
        | "info_player_start"
        | "team_CTF_redplayer"
        | "team_CTF_blueplayer"
        | "team_CTF_redspawn"
        | "team_CTF_bluespawn"
        | "info_player_dom_red"
        | "info_player_dom_blue" => "spawn",
        "team_CTF_redflag" | "team_CTF_blueflag" | "team_CTF_neutralflag" => "flag",
        "team_redobelisk" | "team_blueobelisk" | "team_neutralobelisk" => "obelisk",
        "item_redcube" | "item_bluecube" | "item_neutralcube" => "harvester",
        "trigger_push" | "target_push" => "jumppad",
        "trigger_teleport" => "teleporter",
        "misc_teleporter_dest" => "teleport_dest",
        "light" | "lights" => "light",
        "target_position" | "info_notnull" => "target",
        c if POWERUPS.contains(&c) => "powerup",
        c if c.starts_with("weapon_") => "weapon",
        c if c.starts_with("ammo_") => "ammo",
        c if c.starts_with("holdable_") => "holdable",
        c if c.starts_with("item_") => "item",
        c if c.starts_with("func_") && is_mover(c) => "mover",
        c if c.starts_with("trigger_") => "trigger",
        c if c.starts_with("target_") => "target",
        c if c.starts_with("domination_") || c.starts_with("team_dom") => "domination",
        c if c.starts_with("misc_") || c.starts_with("info_") => "misc",
        _ => "other",
    }
}

fn is_mover(class: &str) -> bool {
    matches!(
        class,
        "func_door"
            | "func_plat"
            | "func_button"
            | "func_train"
            | "func_bobbing"
            | "func_rotating"
            | "func_pendulum"
            | "func_static"
    )
}

fn floats(s: &str) -> Vec<Value> {
    s.split_whitespace()
        .filter_map(|t| t.parse::<f64>().ok())
        .filter_map(|f| serde_json::Number::from_f64(f).map(Value::Number))
        .collect()
}

fn vec3(e: &Entity, key: &str) -> Option<Vec<Value>> {
    Some(floats(e.last(key)?)).filter(|v| v.len() == 3)
}

fn number(e: &Entity, key: &str) -> Option<Value> {
    floats(e.last(key)?).into_iter().next()
}

fn dest_angle(e: &Entity) -> Value {
    number(e, "angle")
        .or_else(|| vec3(e, "angles").map(|a| a[1].clone()))
        .unwrap_or(json!(0))
}

fn submodel(e: &Entity, bsp: &Bsp) -> Option<usize> {
    let n: usize = e.last("model")?.strip_prefix('*')?.parse().ok()?;
    (n < bsp.models.len()).then_some(n)
}

/// The JSON written as `entities.json` (shape in docs/formats/entities.md).
pub fn summarize(bsp: &Bsp) -> Result<Value, String> {
    let ents = parse(&bsp.entities)?;
    let class_of = |e: &Entity| e.last("classname").unwrap_or("").to_string();
    let mut worldspawn = Map::new();
    if let Some(w) = ents.first().filter(|e| class_of(e) == "worldspawn") {
        for (k, v) in &w.pairs {
            worldspawn.insert(k.clone(), json!(v));
        }
    }
    let mut list = Vec::new();
    let mut counts: BTreeMap<String, u64> = BTreeMap::new();
    let (mut jumppads, mut teleporters, mut movers, mut spawns) = (vec![], vec![], vec![], vec![]);
    let find_target = |name: &str, me: usize, classes: Option<&[&str]>| {
        ents.iter().enumerate().find(|(j, t)| {
            *j != me
                && t.last("targetname") == Some(name)
                && classes.is_none_or(|c| c.contains(&class_of(t).as_str()))
        })
    };
    for (i, e) in ents.iter().enumerate() {
        let class = class_of(e);
        *counts.entry(class.clone()).or_default() += 1;
        let mut keys = Map::new();
        for (k, v) in &e.pairs {
            keys.insert(k.clone(), json!(v));
        }
        let origin = vec3(e, "origin");
        let angle = number(e, "angle");
        let sub = submodel(e, bsp);
        let mut obj =
            json!({"index": i, "classname": class, "keys": keys, "category": category(&class)});
        if let Some(o) = &origin {
            obj["origin"] = json!(o);
        }
        if let Some(a) = &angle {
            obj["angle"] = a.clone();
        }
        if let Some(a) = vec3(e, "angles") {
            obj["angles"] = json!(a);
        }
        if let Some(n) = sub {
            obj["submodel"] = json!(n);
        }
        list.push(obj);

        match class.as_str() {
            "trigger_push" | "target_push" => {
                if let Some(target) = e.last("target") {
                    let dest = find_target(target, i, Some(&["target_position", "info_notnull"]));
                    if let Some(o) = dest.and_then(|(_, d)| vec3(d, "origin")) {
                        jumppads.push(json!({"entity": i, "target": target, "target_origin": o}));
                    }
                }
            }
            "trigger_teleport" => {
                if let Some(target) = e.last("target") {
                    if let Some((j, d)) = find_target(target, i, None) {
                        let o = vec3(d, "origin").unwrap_or_else(|| floats("0 0 0"));
                        teleporters.push(json!({"entity": i, "target": target, "dest": j, "dest_origin": o, "dest_angle": dest_angle(d)}));
                    }
                }
            }
            "misc_teleporter_dest" => {
                let o = origin.clone().unwrap_or_else(|| floats("0 0 0"));
                let target = e.last("targetname").unwrap_or("");
                teleporters.push(json!({"entity": i, "target": target, "dest": i, "dest_origin": o, "dest_angle": dest_angle(e)}));
            }
            c if is_mover(c) => {
                if let Some(n) = sub {
                    movers.push(json!({"entity": i, "classname": c, "submodel": n}));
                }
            }
            _ => {}
        }
        if category(&class) == "spawn" {
            if let Some(o) = origin {
                spawns.push(json!({"entity": i, "classname": class, "origin": o, "angle": angle.unwrap_or(json!(0))}));
            }
        }
    }
    Ok(json!({
        "worldspawn": worldspawn,
        "entities": list,
        "counts": counts,
        "jumppads": jumppads,
        "teleporters": teleporters,
        "movers": movers,
        "spawns": spawns,
    }))
}

fn luau_string(s: &str, out: &mut String) {
    out.push('"');
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            c if (c as u32) < 0x20 || c as u32 == 0x7f => {
                out.push_str(&format!("\\{:03}", c as u32))
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

fn luau_value(v: &Value, out: &mut String) {
    match v {
        Value::Null => out.push_str("nil"),
        Value::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        Value::Number(n) => out.push_str(&n.to_string()),
        Value::String(s) => luau_string(s, out),
        Value::Array(a) => {
            out.push('{');
            for (i, x) in a.iter().enumerate() {
                if i > 0 {
                    out.push_str(", ");
                }
                luau_value(x, out);
            }
            out.push('}');
        }
        Value::Object(m) => {
            out.push('{');
            for (i, (k, x)) in m.iter().enumerate() {
                if i > 0 {
                    out.push_str(", ");
                }
                out.push('[');
                luau_string(k, out);
                out.push_str("] = ");
                luau_value(x, out);
            }
            out.push('}');
        }
    }
}

/// A Luau literal for any JSON value (`return <literal>` makes a ModuleScript).
pub fn to_luau(value: &Value) -> String {
    let mut out = String::new();
    luau_value(value, &mut out);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_pairs_and_comments() {
        let e = parse("// c\n{ \"classname\" \"worldspawn\" \"a\" \"1\" }\n{\"x\" \"y\"}").unwrap();
        assert_eq!(e.len(), 2);
        assert_eq!(e[0].get("A"), Some("1"));
    }

    #[test]
    fn rejects_unbalanced() {
        assert!(parse("{ \"a\" \"b\"").is_err());
        assert!(parse("\"a\" \"b\" }").is_err());
        assert!(parse("{ \"a\" }").is_err());
    }

    #[test]
    fn luau_escaping() {
        let v = json!({"k\"": ["a\\b\n\u{1}", null, 1.5, true]});
        assert_eq!(
            to_luau(&v),
            "{[\"k\\\"\"] = {\"a\\\\b\\n\\001\", nil, 1.5, true}}"
        );
    }

    fn check(map: &str) -> Option<Value> {
        let bsp = crate::testdata::bsp(map)?;
        let s = summarize(&bsp).unwrap();
        let list = s["entities"].as_array().unwrap();
        assert_eq!(list.len(), bsp.entities.matches("\"classname\"").count());
        assert_eq!(list[0]["classname"], "worldspawn");
        for e in list {
            if let Some(n) = e.get("submodel") {
                assert!((n.as_u64().unwrap() as usize) < bsp.models.len());
            }
        }
        let dm = bsp.entities.matches("\"info_player_deathmatch\"").count() as u64;
        assert_eq!(
            s["counts"]["info_player_deathmatch"].as_u64().unwrap_or(0),
            dm
        );
        for t in s["teleporters"].as_array().unwrap() {
            let j = t["dest"].as_u64().unwrap() as usize;
            assert!(j < list.len());
        }
        Some(s)
    }

    #[test]
    fn real_maps() {
        check("oa_dm1");
        check("am_thornish");
        if let Some(s) = check("oa_ctf2") {
            assert!(s["counts"]["team_CTF_redflag"].as_u64().unwrap() >= 1);
            assert!(s["counts"]["team_CTF_blueflag"].as_u64().unwrap() >= 1);
        }
    }
}
