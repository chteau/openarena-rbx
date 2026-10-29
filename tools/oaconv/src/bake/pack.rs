//! Shelf packing of chart rectangles into square atlas pages.

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Placed {
    pub page: usize,
    pub x: u32,
    pub y: u32,
}

struct Shelf {
    y: u32,
    h: u32,
    x: u32,
}

/// Places every `(w, h)` (each <= `page`) and returns positions in input
/// order plus each page's used height. Tallest rects go first so shelves
/// waste little height.
pub fn pack(sizes: &[(u32, u32)], page: u32) -> (Vec<Placed>, Vec<u32>) {
    let mut order: Vec<usize> = (0..sizes.len()).collect();
    order.sort_by_key(|&i| (std::cmp::Reverse(sizes[i].1), std::cmp::Reverse(sizes[i].0)));
    let mut pages: Vec<Vec<Shelf>> = Vec::new();
    let mut out = vec![
        Placed {
            page: 0,
            x: 0,
            y: 0
        };
        sizes.len()
    ];
    for i in order {
        let (w, h) = sizes[i];
        assert!(w <= page && h <= page, "chart {w}x{h} larger than a page");
        let mut spot = None;
        'pages: for (p, shelves) in pages.iter_mut().enumerate() {
            for s in shelves.iter_mut() {
                if h <= s.h && s.x + w <= page {
                    spot = Some(Placed {
                        page: p,
                        x: s.x,
                        y: s.y,
                    });
                    s.x += w;
                    break 'pages;
                }
            }
            let top = shelves.last().map_or(0, |s| s.y + s.h);
            if top + h <= page {
                shelves.push(Shelf { y: top, h, x: w });
                spot = Some(Placed {
                    page: p,
                    x: 0,
                    y: top,
                });
                break;
            }
        }
        out[i] = spot.unwrap_or_else(|| {
            pages.push(vec![Shelf { y: 0, h, x: w }]);
            Placed {
                page: pages.len() - 1,
                x: 0,
                y: 0,
            }
        });
    }
    let heights = pages
        .iter()
        .map(|s| s.last().map_or(0, |s| s.y + s.h))
        .collect();
    (out, heights)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_overlaps_and_inside_pages() {
        let sizes: Vec<(u32, u32)> = (0..500)
            .map(|i| (5 + (i * 37) % 120, 5 + (i * 53) % 90))
            .collect();
        let (placed, heights) = pack(&sizes, 256);
        for (i, a) in placed.iter().enumerate() {
            let (w, h) = sizes[i];
            assert!(a.x + w <= 256 && a.y + h <= heights[a.page]);
            for (j, b) in placed.iter().enumerate().skip(i + 1) {
                if a.page != b.page {
                    continue;
                }
                let (bw, bh) = sizes[j];
                let apart = a.x + w <= b.x || b.x + bw <= a.x || a.y + h <= b.y || b.y + bh <= a.y;
                assert!(apart, "{i} and {j} overlap");
            }
        }
        let used: u32 = sizes.iter().map(|(w, h)| w * h).sum();
        let pages = heights.len() as u32;
        assert!(
            used as f32 / (pages * 256 * 256) as f32 > 0.6,
            "packing too loose: {pages} pages"
        );
    }
}
