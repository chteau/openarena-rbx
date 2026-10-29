//! `Com_BlockChecksum` (ioquake3 qcommon/md4.c, GPL-2.0): the MD4 digest's
//! four little-endian words xor-ed together. `CM_LoadMap` computes it over
//! the whole `.bsp`, the server publishes it as `sv_mapChecksum`, and
//! botlib refuses an `.aas` whose header names another checksum.

fn md4(data: &[u8]) -> [u32; 4] {
    let mut msg = data.to_vec();
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&((data.len() as u64).wrapping_mul(8)).to_le_bytes());

    let f = |x: u32, y: u32, z: u32| (x & y) | (!x & z);
    let g = |x: u32, y: u32, z: u32| (x & y) | (x & z) | (y & z);
    let h = |x: u32, y: u32, z: u32| x ^ y ^ z;
    let mut s = [0x6745_2301u32, 0xefcd_ab89, 0x98ba_dcfe, 0x1032_5476];
    for block in msg.as_chunks::<64>().0 {
        let x: Vec<u32> = block
            .as_chunks::<4>()
            .0
            .iter()
            .map(|w| u32::from_le_bytes(*w))
            .collect();
        let [mut a, mut b, mut c, mut d] = s;
        for i in 0..16 {
            let t = a.wrapping_add(f(b, c, d)).wrapping_add(x[i]);
            (a, b, c, d) = (d, t.rotate_left([3, 7, 11, 19][i % 4]), b, c);
        }
        for i in 0..16 {
            let k = (i % 4) * 4 + i / 4;
            let t = a
                .wrapping_add(g(b, c, d))
                .wrapping_add(x[k])
                .wrapping_add(0x5a82_7999);
            (a, b, c, d) = (d, t.rotate_left([3, 5, 9, 13][i % 4]), b, c);
        }
        for i in 0..16 {
            let k = [0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15][i];
            let t = a
                .wrapping_add(h(b, c, d))
                .wrapping_add(x[k])
                .wrapping_add(0x6ed9_eba1);
            (a, b, c, d) = (d, t.rotate_left([3, 9, 11, 15][i % 4]), b, c);
        }
        s = [
            s[0].wrapping_add(a),
            s[1].wrapping_add(b),
            s[2].wrapping_add(c),
            s[3].wrapping_add(d),
        ];
    }
    s
}

/// `Com_BlockChecksum`, as the signed int `sv_mapChecksum` prints (`%i`).
pub fn block_checksum(data: &[u8]) -> i32 {
    let d = md4(data);
    (d[0] ^ d[1] ^ d[2] ^ d[3]) as i32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn md4_rfc1320_vectors() {
        let hex = |d: [u32; 4]| {
            d.iter()
                .map(|w| format!("{:08x}", w.swap_bytes()))
                .collect::<String>()
        };
        assert_eq!(hex(md4(b"")), "31d6cfe0d16ae931b73c59d7e0c089c0");
        assert_eq!(hex(md4(b"abc")), "a448017aaf21d8525fc10ae87aa6729d");
        assert_eq!(
            hex(md4(
                b"12345678901234567890123456789012345678901234567890123456789012345678901234567890"
            )),
            "e33b4ddc9c38f2199c3e7b164fcc0536"
        );
    }

    /// The values botlib's native oracle and tests/bots/md4.luau give.
    #[test]
    fn map_checksums() {
        let Some(vfs) = crate::testdata::vfs() else {
            return;
        };
        for (map, want) in [
            ("oa_dm1", 1737490240),
            ("oa_ctf2", -967542298),
            ("am_thornish", 1384519091),
            ("oa_bases7", 600114830),
        ] {
            let bytes = vfs.read(&format!("maps/{map}.bsp")).expect("bsp");
            assert_eq!(block_checksum(&bytes), want, "{map}");
        }
    }
}
