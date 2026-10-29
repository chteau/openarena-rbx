//! Turns a map's draw surfaces into meshes. Opaque (static) shaders are
//! baked: every surface gets its own rectangle of atlas texels holding
//! diffuse x lightmap x overbright, evaluated stage by stage like the
//! engine draws it. Everything else keeps its tiled texture and vertex light.
//! The density trade-off is documented in docs/conv-notes.md.

mod chart;
mod pack;
mod raster;
pub mod shade;

use std::collections::{BTreeMap, BTreeSet, HashMap};

use image::RgbaImage;
use rayon::prelude::*;
use serde_json::{json, Value};

use crate::bsp::curve::{subdivide_patch, R_SUBDIVISIONS};
use crate::bsp::{Bsp, DrawVert, MST_PATCH, MST_PLANAR, MST_TRIANGLE_SOUP};
use crate::mesh::{Mesh, MAX_TRIS};
use crate::shader::{Shader, ShaderClass, ShaderSet};
use crate::vfs::Vfs;

use chart::{BVert, Tri};
use shade::{Program, TexCache};

const SURF_NODRAW: i32 = 0x80;

#[derive(Clone, Copy, Debug)]
pub struct Settings {
    /// Atlas pages a map may use before the texel density is lowered.
    pub max_pages: usize,
    /// Texels per world unit, upper and lower bound.
    pub max_density: f32,
    pub min_density: f32,
    pub page: u32,
    /// Texels of padding around each chart.
    pub pad: u32,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            max_pages: 16,
            max_density: 1.0,
            min_density: 1.0 / 16.0,
            page: 1024,
            pad: 2,
        }
    }
}

pub struct BakedMap {
    pub pages: Vec<RgbaImage>,
    /// Baked meshes (shader "atlas", texture `maps/<map>/atlas_N.png`) and
    /// non-baked ones (texture = `images/<path>.png`), each <= MAX_TRIS.
    pub meshes: Vec<Mesh>,
    pub density: f32,
    /// VFS image paths non-baked meshes are textured with.
    pub images: BTreeSet<String>,
    pub stats: Value,
}

/// Where the converted copy of a VFS image lives under `build/`.
pub fn image_output(path: &str) -> String {
    format!("images/{}.png", crate::shader::strip_ext(path))
}

/// First image a shader's stages draw, resolved the engine's way.
pub fn first_image(shader: &Shader, vfs: &Vfs) -> Option<String> {
    shader
        .stages
        .iter()
        .flat_map(|s| s.maps.iter())
        .filter(|m| !m.starts_with('$') && !m.starts_with('*'))
        .find_map(|m| vfs.find_image(m))
}

struct Surface {
    model: usize,
    shader: usize,
    lightmap: i32,
    verts: Vec<DrawVert>,
    tris: Vec<[u32; 3]>,
    grid: Option<(usize, usize)>,
    normal: [f32; 3],
}

fn surfaces(bsp: &Bsp) -> Vec<Surface> {
    let mut out = Vec::new();
    for (model, m) in bsp.models.iter().enumerate() {
        for si in m.first_surface..m.first_surface + m.num_surfaces {
            let s = &bsp.surfaces[si as usize];
            let Some(ds) = bsp.shaders.get(s.shader_num as usize) else {
                continue;
            };
            if ds.surface_flags & SURF_NODRAW != 0 {
                continue;
            }
            let verts = bsp.surface_verts(s);
            let (verts, tris, grid) = match s.surface_type {
                MST_PLANAR | MST_TRIANGLE_SOUP => {
                    let tris = bsp
                        .surface_indexes(s)
                        .as_chunks::<3>()
                        .0
                        .iter()
                        .map(|c| c.map(|i| i as u32))
                        .filter(|t| t.iter().all(|&i| (i as usize) < verts.len()))
                        .collect();
                    (verts.to_vec(), tris, None)
                }
                MST_PATCH => {
                    let (w, h) = (s.patch_width as usize, s.patch_height as usize);
                    if w < 3 || h < 3 || w * h != verts.len() {
                        continue;
                    }
                    let grid = subdivide_patch(w, h, verts, R_SUBDIVISIONS);
                    let tris = grid.triangles();
                    (grid.verts, tris, Some((grid.width, grid.height)))
                }
                _ => continue,
            };
            out.push(Surface {
                model,
                shader: s.shader_num as usize,
                lightmap: s.lightmap_num,
                verts,
                tris,
                grid,
                normal: if s.surface_type == MST_PLANAR {
                    s.lightmap_vecs[2]
                } else {
                    [0.0; 3]
                },
            });
        }
    }
    out
}

fn prefix(model: usize) -> String {
    if model == 0 {
        "world".into()
    } else {
        format!("model{model}")
    }
}

fn sanitize(name: &str) -> String {
    name.chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '_' })
        .collect()
}

struct Chart {
    model: usize,
    program: usize,
    lightmap: i32,
    tris: Vec<Tri>,
}

struct Job<'a> {
    chart: &'a Chart,
    tris: Vec<Tri>,
    min: [f32; 2],
    w: u32,
    h: u32,
}

/// Splits and sizes every chart at density `d`.
fn layout<'a>(charts: &'a [Chart], d: f32, s: &Settings) -> Vec<Job<'a>> {
    let max_extent = (s.page - 2 * s.pad - 1) as f32 / d;
    charts
        .iter()
        .flat_map(|chart| {
            chart::split(chart.tris.clone(), max_extent)
                .into_iter()
                .map(move |tris| {
                    let (min, max) = chart::bounds(&tris);
                    let size = |k: usize| {
                        (((max[k] - min[k]) * d).ceil() as u32 + 2 * s.pad)
                            .clamp(2 * s.pad + 1, s.page)
                    };
                    Job {
                        chart,
                        w: size(0),
                        h: size(1),
                        min,
                        tris,
                    }
                })
        })
        .collect()
}

/// Display colour of a vertex light (shifted, then the gamma ramp's scale).
fn vertex_light(v: &DrawVert) -> [u8; 4] {
    let c = BVert::from_draw(v).color;
    let scale = (1 << shade::OVERBRIGHT) as f32;
    let ch = |x: f32| ((x * scale).min(1.0) * 255.0 + 0.5) as u8;
    [ch(c[0]), ch(c[1]), ch(c[2]), v.color[3]]
}

pub fn bake_map(map: &str, bsp: &Bsp, shaders: &ShaderSet, vfs: &Vfs, s: &Settings) -> BakedMap {
    let mut resolved: HashMap<(usize, bool), Shader> = HashMap::new();
    let mut programs: Vec<Program> = Vec::new();
    let mut program_of: HashMap<(usize, bool), usize> = HashMap::new();
    let mut cache = TexCache::default();
    let mut charts: Vec<Chart> = Vec::new();
    let mut loose: BTreeMap<(usize, ShaderClass, String), Mesh> = BTreeMap::new();
    let mut images = BTreeSet::new();
    let mut class_tris: BTreeMap<ShaderClass, usize> = BTreeMap::new();

    for surf in surfaces(bsp) {
        let lit = surf.lightmap >= 0 && (surf.lightmap as usize) < bsp.lightmaps.len();
        let shader = resolved
            .entry((surf.shader, lit))
            .or_insert_with(|| shaders.resolve(&bsp.shaders[surf.shader].name, lit, vfs))
            .clone();
        *class_tris.entry(shader.class).or_default() += surf.tris.len();
        match shader.class {
            ShaderClass::Nodraw => {}
            ShaderClass::Opaque => {
                let program = *program_of.entry((surf.shader, lit)).or_insert_with(|| {
                    programs.push(Program::compile(&shader, lit, |name| cache.get(vfs, name)));
                    programs.len() - 1
                });
                let pieces = match surf.grid {
                    Some((w, h)) => chart::patch(&surf.verts, w, h, &surf.tris),
                    None if surf.normal != [0.0; 3] => {
                        chart::planar(&surf.verts, &surf.tris, surf.normal)
                    }
                    None => chart::soup(&surf.verts, &surf.tris),
                };
                let lightmap = if lit { surf.lightmap } else { -1 };
                charts.extend(
                    pieces
                        .into_iter()
                        .filter(|p| !p.is_empty())
                        .map(|tris| Chart {
                            model: surf.model,
                            program,
                            lightmap,
                            tris,
                        }),
                );
            }
            class => {
                let texture = first_image(&shader, vfs);
                if let Some(t) = &texture {
                    images.insert(t.clone());
                }
                let mesh = loose
                    .entry((surf.model, class, shader.name.clone()))
                    .or_insert_with(|| Mesh {
                        name: format!("{}_{}", prefix(surf.model), sanitize(&shader.name)),
                        class,
                        shader: shader.name.clone(),
                        texture: texture.as_deref().map(image_output),
                        ..Default::default()
                    });
                let base = mesh.positions.len() as u32;
                for v in &surf.verts {
                    mesh.positions.push(v.xyz);
                    mesh.normals.push(v.normal);
                    mesh.uvs.push(v.st);
                    mesh.colors.push(vertex_light(v));
                }
                mesh.indices
                    .extend(surf.tris.iter().flat_map(|t| t.map(|i| i + base)));
            }
        }
    }

    // Texel density: as high as the page budget allows, within bounds.
    let area: f32 = charts
        .iter()
        .map(|c| {
            let (min, max) = chart::bounds(&c.tris);
            (max[0] - min[0]).max(1.0) * (max[1] - min[1]).max(1.0)
        })
        .sum();
    let budget = s.max_pages as f32 * (s.page * s.page) as f32 * 0.7;
    let mut d = (budget / area.max(1.0))
        .sqrt()
        .clamp(s.min_density, s.max_density);
    let (jobs, placed, heights) = loop {
        let jobs = layout(&charts, d, s);
        let sizes: Vec<(u32, u32)> = jobs.iter().map(|j| (j.w, j.h)).collect();
        let (placed, heights) = pack::pack(&sizes, s.page);
        if heights.len() <= s.max_pages || d <= s.min_density {
            break (jobs, placed, heights);
        }
        d = (d * 0.9).max(s.min_density);
    };

    let lightmaps: Vec<shade::Tex> = bsp
        .lightmaps
        .iter()
        .map(|l| shade::lightmap_tex(l))
        .collect();
    let frame = |j: &Job| raster::Frame {
        min: j.min,
        density: d,
        pad: s.pad as f32,
        w: j.w,
        h: j.h,
    };
    let rendered: Vec<Vec<[u8; 3]>> = jobs
        .par_iter()
        .map(|j| {
            let lm = (j.chart.lightmap >= 0).then(|| &lightmaps[j.chart.lightmap as usize]);
            raster::raster(&j.tris, &frame(j), &programs[j.chart.program], lm)
        })
        .collect();

    let page_h: Vec<u32> = heights
        .iter()
        .map(|h| h.next_power_of_two().clamp(4, s.page))
        .collect();
    let mut pages: Vec<RgbaImage> = page_h.iter().map(|&h| RgbaImage::new(s.page, h)).collect();
    let mut baked: BTreeMap<(usize, usize), Mesh> = BTreeMap::new();
    for ((job, at), pixels) in jobs.iter().zip(&placed).zip(&rendered) {
        let page = &mut pages[at.page];
        for y in 0..job.h {
            for x in 0..job.w {
                let [r, g, b] = pixels[(y * job.w + x) as usize];
                page.put_pixel(at.x + x, at.y + y, image::Rgba([r, g, b, 255]));
            }
        }
        let f = frame(job);
        let mesh = baked
            .entry((job.chart.model, at.page))
            .or_insert_with(|| Mesh {
                name: format!("{}_atlas{}", prefix(job.chart.model), at.page),
                class: ShaderClass::Opaque,
                shader: "atlas".into(),
                texture: Some(format!("maps/{map}/atlas_{}.png", at.page)),
                ..Default::default()
            });
        for v in job.tris.iter().flatten() {
            let p = f.to_texel(v.uv);
            mesh.indices.push(mesh.positions.len() as u32);
            mesh.positions.push(v.pos);
            mesh.normals.push(chart::normalize(v.normal));
            mesh.uvs.push([
                (at.x as f32 + p[0]) / s.page as f32,
                (at.y as f32 + p[1]) / page_h[at.page] as f32,
            ]);
            mesh.colors.push([255; 4]);
        }
    }

    let mut meshes: Vec<Mesh> = Vec::new();
    for m in baked.into_values().chain(loose.into_values()) {
        meshes.extend(weld(m).split(MAX_TRIS));
    }
    let mut seen = BTreeSet::new();
    for m in &mut meshes {
        let base = m.name.clone();
        let mut n = 1;
        while !seen.insert(m.name.clone()) {
            m.name = format!("{base}_{n}");
            n += 1;
        }
    }
    let texels: f64 = jobs.iter().map(|j| j.w as f64 * j.h as f64).sum();
    let page_texels: f64 = pages
        .iter()
        .map(|p| p.width() as f64 * p.height() as f64)
        .sum();
    let stats = json!({
        "density": d,
        "units_per_texel": 1.0 / d,
        "charts": jobs.len(),
        "atlas_pages": pages.len(),
        "atlas_fill": texels / page_texels.max(1.0),
        "triangles_by_class": class_tris,
        "missing_images": cache.missing,
    });
    BakedMap {
        pages,
        meshes,
        density: d,
        images,
        stats,
    }
}

/// Merges identical vertices (baked triangles arrive unshared).
fn weld(m: Mesh) -> Mesh {
    let mut index: HashMap<[u32; 12], u32> = HashMap::new();
    let mut out = Mesh {
        name: m.name,
        class: m.class,
        shader: m.shader,
        texture: m.texture,
        ..Default::default()
    };
    let remap: Vec<u32> = (0..m.positions.len())
        .map(|i| {
            let (p, n, u, c) = (m.positions[i], m.normals[i], m.uvs[i], m.colors[i]);
            let mut key = [0u32; 12];
            for (k, v) in p.iter().chain(&n).chain(&u).enumerate() {
                key[k] = v.to_bits();
            }
            key[8..].copy_from_slice(&c.map(u32::from));
            *index.entry(key).or_insert_with(|| {
                out.positions.push(p);
                out.normals.push(n);
                out.uvs.push(u);
                out.colors.push(c);
                (out.positions.len() - 1) as u32
            })
        })
        .collect();
    out.indices = m.indices.iter().map(|&i| remap[i as usize]).collect();
    out
}
