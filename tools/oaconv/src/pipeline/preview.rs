//! `oaconv preview`: bakes one map in memory and renders it with the
//! software rasterizer, from a spawn point (eye height) or from above.

use std::collections::HashMap;
use std::path::Path;

use oaconv::bake::{bake_map, image_output, Settings};
use oaconv::bsp::{entities, Bsp};
use oaconv::preview::{render, render_top, Camera};
use oaconv::shader::ShaderSet;
use oaconv::vfs::Vfs;

use super::err;

pub enum View {
    Top,
    /// The Nth entry of the map's spawn list.
    Spawn(usize),
    /// Eye position and yaw, as the engine's `viewpos` prints them.
    Eye([f32; 4]),
}

/// `DEFAULT_VIEWHEIGHT` in bg_public.h.
const VIEW_HEIGHT: f32 = 26.0;

pub fn preview(
    root: &Path,
    map: &str,
    view: View,
    out: &Path,
    w: u32,
    h: u32,
) -> Result<(), String> {
    let vfs = Vfs::open(root).map_err(err(root.display()))?;
    let shaders = ShaderSet::load(&vfs);
    let source = format!("maps/{map}.bsp");
    let bsp =
        Bsp::parse(&vfs.read(&source).ok_or(format!("no {source}"))?).map_err(err(&source))?;
    let baked = bake_map(map, &bsp, &shaders, &vfs, &Settings::default());
    let mut textures = HashMap::new();
    for (i, page) in baked.pages.iter().enumerate() {
        textures.insert(format!("maps/{map}/atlas_{i}.png"), page.clone());
    }
    for img in &baked.images {
        if let Some(t) = vfs
            .read(img)
            .and_then(|b| oaconv::texture::decode(&b, img).ok())
        {
            textures.insert(image_output(img), t);
        }
    }
    let image = match view {
        View::Top => render_top(&baked.meshes, &textures, w, h),
        View::Eye([x, y, z, yaw]) => render(
            &baked.meshes,
            &textures,
            Camera {
                origin: [x, y, z],
                yaw,
                pitch: 0.0,
                fov_x: 90.0,
            },
            w,
            h,
        ),
        View::Spawn(n) => {
            let ents = entities::summarize(&bsp)?;
            let spawns = ents["spawns"].as_array().cloned().unwrap_or_default();
            let spawn = spawns
                .get(n)
                .ok_or(format!("{map} has {} spawns", spawns.len()))?;
            let o = &spawn["origin"];
            let f = |i: usize| o[i].as_f64().unwrap_or(0.0) as f32;
            let cam = Camera {
                origin: [f(0), f(1), f(2) + VIEW_HEIGHT],
                yaw: spawn["angle"].as_f64().unwrap_or(0.0) as f32,
                pitch: 0.0,
                fov_x: 90.0,
            };
            println!(
                "camera: setviewpos {} {} {} {}",
                cam.origin[0],
                cam.origin[1],
                cam.origin[2] - VIEW_HEIGHT,
                cam.yaw
            );
            render(&baked.meshes, &textures, cam, w, h)
        }
    };
    image.save(out).map_err(err(out.display()))?;
    println!(
        "{}: {}",
        out.display(),
        serde_json::to_string(&baked.stats).unwrap_or_default()
    );
    Ok(())
}
