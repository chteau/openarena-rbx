//! Image decoding (TGA, JPEG, PNG) and the 1024 px cap.

use image::RgbaImage;

/// Roblox's texture size cap.
pub const MAX_SIZE: u32 = 1024;

pub fn decode(_bytes: &[u8], _path: &str) -> Result<RgbaImage, String> {
    todo!()
}

pub fn downscale_max(_img: &RgbaImage, _max: u32) -> RgbaImage {
    todo!()
}

pub fn has_alpha(_img: &RgbaImage) -> bool {
    todo!()
}

pub fn encode_png(_img: &RgbaImage) -> Vec<u8> {
    todo!()
}
