//! Binary glTF 2.0 (`.glb`) writer for [`Mesh`]es.

use serde_json::{json, Value};

use crate::mesh::{dir_to_roblox, to_roblox, Mesh, MeshInfo};

const FLOAT: u32 = 5126;
const UBYTE: u32 = 5121;
const USHORT: u32 = 5123;
const UINT: u32 = 5125;
const ARRAY_BUFFER: u32 = 34962;
const ELEMENT_ARRAY_BUFFER: u32 = 34963;

struct Builder {
    bin: Vec<u8>,
    views: Vec<Value>,
    accessors: Vec<Value>,
}

impl Builder {
    /// Appends a 4-byte aligned bufferView and `acc` (an accessor object
    /// without its bufferView) over it; returns the accessor index.
    fn add(&mut self, data: &[u8], target: u32, mut acc: Value) -> usize {
        pad(&mut self.bin, 0);
        self.views.push(json!({
            "buffer": 0, "byteOffset": self.bin.len(), "byteLength": data.len(), "target": target
        }));
        self.bin.extend_from_slice(data);
        acc["bufferView"] = json!(self.views.len() - 1);
        self.accessors.push(acc);
        self.accessors.len() - 1
    }
}

fn accessor(comp: u32, count: usize, ty: &str) -> Value {
    json!({ "componentType": comp, "count": count, "type": ty })
}

fn floats(v: impl Iterator<Item = f32>) -> Vec<u8> {
    v.flat_map(f32::to_le_bytes).collect()
}

fn normalize(n: [f32; 3]) -> [f32; 3] {
    let len = (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]).sqrt();
    if len > 0.0 && len.is_finite() {
        [n[0] / len, n[1] / len, n[2] / len]
    } else {
        [0.0, 1.0, 0.0]
    }
}

fn pad(buf: &mut Vec<u8>, byte: u8) {
    while !buf.len().is_multiple_of(4) {
        buf.push(byte);
    }
}

/// One `.glb` holding every mesh as its own node (named after the mesh),
/// converted to Roblox studs/axes. Returns the file and each mesh's info.
pub fn write_glb(meshes: &[Mesh]) -> (Vec<u8>, Vec<MeshInfo>) {
    let mut b = Builder {
        bin: Vec::new(),
        views: Vec::new(),
        accessors: Vec::new(),
    };
    let mut gmeshes = Vec::new();
    let mut nodes = Vec::new();
    let mut materials = Vec::new();
    let mut infos = Vec::new();

    for m in meshes
        .iter()
        .filter(|m| m.tri_count() > 0 && !m.positions.is_empty())
    {
        let mut qmin = [f32::INFINITY; 3];
        let mut qmax = [f32::NEG_INFINITY; 3];
        for p in &m.positions {
            for k in 0..3 {
                qmin[k] = qmin[k].min(p[k]);
                qmax[k] = qmax[k].max(p[k]);
            }
        }
        let center = to_roblox([
            (qmin[0] + qmax[0]) / 2.0,
            (qmin[1] + qmax[1]) / 2.0,
            (qmin[2] + qmax[2]) / 2.0,
        ]);
        let pos: Vec<[f32; 3]> = m
            .positions
            .iter()
            .map(|&p| {
                let r = to_roblox(p);
                [r[0] - center[0], r[1] - center[1], r[2] - center[2]]
            })
            .collect();
        let mut min = [f32::INFINITY; 3];
        let mut max = [f32::NEG_INFINITY; 3];
        for p in &pos {
            for k in 0..3 {
                min[k] = min[k].min(p[k]);
                max[k] = max[k].max(p[k]);
            }
        }
        let n = pos.len();
        let mut pos_acc = accessor(FLOAT, n, "VEC3");
        pos_acc["min"] = json!(min);
        pos_acc["max"] = json!(max);
        let a_pos = b.add(
            &floats(pos.iter().flatten().copied()),
            ARRAY_BUFFER,
            pos_acc,
        );
        let norms =
            floats((0..n).flat_map(|i| {
                normalize(dir_to_roblox(m.normals.get(i).copied().unwrap_or([0.0; 3])))
            }));
        let a_nrm = b.add(&norms, ARRAY_BUFFER, accessor(FLOAT, n, "VEC3"));
        let uvs = floats((0..n).flat_map(|i| m.uvs.get(i).copied().unwrap_or([0.0; 2])));
        let a_uv = b.add(&uvs, ARRAY_BUFFER, accessor(FLOAT, n, "VEC2"));
        let mut attrs = json!({ "POSITION": a_pos, "NORMAL": a_nrm, "TEXCOORD_0": a_uv });
        if m.shader != "atlas" && m.colors.len() == n {
            let cols: Vec<u8> = m.colors.iter().flatten().copied().collect();
            let mut col_acc = accessor(UBYTE, n, "VEC4");
            col_acc["normalized"] = json!(true);
            attrs["COLOR_0"] = json!(b.add(&cols, ARRAY_BUFFER, col_acc));
        }
        let mut idx = m.indices[..m.tri_count() * 3].to_vec();
        for t in idx.as_chunks_mut::<3>().0 {
            t.swap(1, 2);
        }
        let (bytes, comp): (Vec<u8>, u32) = if n < 65536 {
            (
                idx.iter().flat_map(|&i| (i as u16).to_le_bytes()).collect(),
                USHORT,
            )
        } else {
            (idx.iter().flat_map(|i| i.to_le_bytes()).collect(), UINT)
        };
        let a_idx = b.add(
            &bytes,
            ELEMENT_ARRAY_BUFFER,
            accessor(comp, idx.len(), "SCALAR"),
        );

        let mat_name = m.texture.clone().unwrap_or_else(|| m.shader.clone());
        materials.push(json!({
            "name": mat_name,
            "pbrMetallicRoughness": { "baseColorFactor": [1.0, 1.0, 1.0, 1.0], "metallicFactor": 0.0, "roughnessFactor": 1.0 }
        }));
        gmeshes.push(json!({
            "name": m.name,
            "primitives": [{ "attributes": attrs, "indices": a_idx, "material": materials.len() - 1 }]
        }));
        nodes.push(json!({ "name": m.name, "mesh": gmeshes.len() - 1, "translation": center }));
        infos.push(MeshInfo {
            name: m.name.clone(),
            class: m.class,
            shader: m.shader.clone(),
            texture: m.texture.clone(),
            triangles: m.tri_count(),
            center,
            size: [max[0] - min[0], max[1] - min[1], max[2] - min[2]],
        });
    }

    pad(&mut b.bin, 0);
    let scene: Vec<usize> = (0..nodes.len()).collect();
    let mut doc = json!({
        "asset": { "version": "2.0", "generator": "oaconv" },
        "scene": 0,
        "scenes": [{ "nodes": scene }],
        "nodes": nodes,
        "meshes": gmeshes,
        "materials": materials,
        "buffers": [{ "byteLength": b.bin.len() }],
        "bufferViews": b.views,
        "accessors": b.accessors,
    });
    if infos.is_empty() {
        let o = doc.as_object_mut().expect("object");
        for k in ["meshes", "materials", "bufferViews", "accessors", "buffers"] {
            o.remove(k);
        }
    }
    let mut js = serde_json::to_vec(&doc).expect("serialize json");
    pad(&mut js, b' ');

    let total = 12 + 8 + js.len() + 8 + b.bin.len();
    let mut out = Vec::with_capacity(total);
    out.extend_from_slice(&0x4654_6C67u32.to_le_bytes());
    out.extend_from_slice(&2u32.to_le_bytes());
    out.extend_from_slice(&(total as u32).to_le_bytes());
    out.extend_from_slice(&(js.len() as u32).to_le_bytes());
    out.extend_from_slice(&0x4E4F_534Au32.to_le_bytes());
    out.extend_from_slice(&js);
    out.extend_from_slice(&(b.bin.len() as u32).to_le_bytes());
    out.extend_from_slice(&0x004E_4942u32.to_le_bytes());
    out.extend_from_slice(&b.bin);
    (out, infos)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tri(shader: &str, verts: usize) -> Mesh {
        let mut m = Mesh {
            name: "t".into(),
            shader: shader.into(),
            ..Default::default()
        };
        for i in 0..verts {
            m.positions
                .push([(i % 3) as f32 * 8.0, (i % 2) as f32 * 16.0, 0.0]);
            m.normals.push([0.0, 0.0, 0.0]);
            m.uvs.push([0.0, 0.0]);
            m.colors.push([255; 4]);
        }
        m.indices = vec![0, 1, 2];
        m
    }

    fn parse(glb: &[u8]) -> (Value, &[u8]) {
        assert_eq!(&glb[0..4], b"glTF");
        assert_eq!(u32::from_le_bytes(glb[4..8].try_into().unwrap()), 2);
        assert_eq!(
            u32::from_le_bytes(glb[8..12].try_into().unwrap()) as usize,
            glb.len()
        );
        let jl = u32::from_le_bytes(glb[12..16].try_into().unwrap()) as usize;
        assert_eq!(jl % 4, 0);
        let json: Value = serde_json::from_slice(&glb[20..20 + jl]).unwrap();
        let bl = u32::from_le_bytes(glb[20 + jl..24 + jl].try_into().unwrap()) as usize;
        assert_eq!(bl % 4, 0);
        (json, &glb[28 + jl..28 + jl + bl])
    }

    #[test]
    fn structure_and_bounds() {
        let (glb, infos) = write_glb(&[tri("x", 3), Mesh::default()]);
        assert_eq!(infos.len(), 1);
        let (j, bin) = parse(&glb);
        for v in j["bufferViews"].as_array().unwrap() {
            let off = v["byteOffset"].as_u64().unwrap() as usize;
            assert_eq!(off % 4, 0);
            assert!(off + v["byteLength"].as_u64().unwrap() as usize <= bin.len());
        }
        assert_eq!(j["accessors"][0]["count"], 3);
        assert_eq!(j["asset"]["generator"], "oaconv");
    }

    #[test]
    fn winding_flipped_and_center_size() {
        let (glb, infos) = write_glb(&[tri("x", 3)]);
        let (j, bin) = parse(&glb);
        let a =
            &j["accessors"][j["meshes"][0]["primitives"][0]["indices"].as_u64().unwrap() as usize];
        assert_eq!(a["componentType"], USHORT);
        let v = &j["bufferViews"][a["bufferView"].as_u64().unwrap() as usize];
        let off = v["byteOffset"].as_u64().unwrap() as usize;
        let idx: Vec<u16> = (0..3)
            .map(|i| u16::from_le_bytes(bin[off + i * 2..off + i * 2 + 2].try_into().unwrap()))
            .collect();
        assert_eq!(idx, vec![0, 2, 1]);
        assert_eq!(infos[0].center, [1.0, 0.0, -1.0]);
        assert_eq!(infos[0].size, [2.0, 0.0, 2.0]);
    }

    #[test]
    fn index_width_and_color() {
        let (glb, _) = write_glb(&[tri("atlas", 70000)]);
        let (j, _) = parse(&glb);
        let p = &j["meshes"][0]["primitives"][0];
        assert!(p["attributes"].get("COLOR_0").is_none());
        assert_eq!(
            j["accessors"][p["indices"].as_u64().unwrap() as usize]["componentType"],
            UINT
        );
        let (glb, _) = write_glb(&[tri("foo", 3)]);
        let (j, _) = parse(&glb);
        assert!(j["meshes"][0]["primitives"][0]["attributes"]
            .get("COLOR_0")
            .is_some());
    }
}
