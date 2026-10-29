#!/usr/bin/env python3
"""Dev asset pack for the client, straight from the OA pk3s.

Until the converter's uploads exist (build/assets.lock.json), this gives the
client real OA data to run against in rbx-native's editor:

  build/client/Files/           FS pack: text files (cfg, skin, shader, arena,
                                bot scripts) and the list of every data path
  build/client/AssetIndex/      images -> rbxasset://openarena/<path>.png + size
  <cache>/native/openarena/...  the PNGs, where rbx-native's asset cache
                                resolves rbxasset://openarena/<path>

<cache> is $RBX_ASSET_CACHE, else $XDG_CACHE_HOME/rbx-native/assets.
Both module folders are split into parts under 190k characters (the size a
ModuleScript source can hold), merged by their init.luau.
"""
import base64
import os
import re
import struct
import subprocess
import tempfile
import zipfile
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import roster  # noqa: E402
BASEOA = os.path.join(ROOT, 'vendor/oa088/openarena-0.8.8/baseoa')
OUT = os.path.join(ROOT, 'build/client')
CACHE = os.environ.get('RBX_ASSET_CACHE') or os.path.join(
    os.environ.get('XDG_CACHE_HOME', os.path.expanduser('~/.cache')), 'rbx-native/assets')
NATIVE = os.path.join(CACHE, 'native/openarena')
IMAGE_EXT = {'.tga', '.jpg', '.png'}
IMAGE_DIRS = ('gfx/', 'menu/', 'icons/', 'levelshots/', 'sprites/', 'ui/', 'env/')
LIMIT = 190_000

FULL_MODELS = os.environ.get('OA_DEV_FULL_MODELS') == '1'


def md3_lite(blob):
    """MD3 header + frames + tags, no surfaces: enough for registration,
    bounds and tags (the player models' surfaces are ~50 MB of base64)."""
    h = list(struct.unpack_from('<4si64si8i', blob, 0))
    num_frames, num_tags = h[4], h[5]
    ofs_frames, ofs_tags = h[8], h[9]
    frames = blob[ofs_frames:ofs_frames + num_frames * 56]
    tags = blob[ofs_tags:ofs_tags + num_tags * num_frames * 112]
    end = 108 + len(frames) + len(tags)
    h[6] = 0                      # numSurfaces
    h[8], h[9] = 108, 108 + len(frames)
    h[10], h[11] = end, end       # ofsSurfaces, ofsEnd
    return struct.pack('<4si64si8i', *h) + frames + tags


# 2D shaders whose stages multiply (filter / dst_color blends): GUI images
# only alpha-blend, so these are composited here at time 0 (tcMod scroll and
# friends are frozen, docs/client-notes.md "2D shaders")
BAKE_2D = ('menuback', 'menuback_blueish', 'menubacknologo', 'menubacknologo_blueish')
BAKE_SIZE = 512


def parse_shader(text, name):
    m = re.search(r'(?ims)^\s*' + re.escape(name) + r'\s*\{(.*?)^\}', text)
    if not m:
        return None
    stages, depth, cur = [], 0, None
    for line in m.group(1).splitlines():
        line = line.split('//')[0].strip()
        if line == '{':
            cur = {'blend': 'opaque', 'rgb': (1, 1, 1), 'scale': (1, 1)}
        elif line == '}':
            stages.append(cur)
            cur = None
        elif cur is not None and line:
            t = line.split()
            k = t[0].lower()
            if k in ('map', 'clampmap'):
                cur['map'] = t[1]
            elif k == 'blendfunc':
                b = ' '.join(x.lower() for x in t[1:])
                cur['blend'] = {'filter': 'mul', 'gl_dst_color gl_zero': 'mul', 'gl_zero gl_src_color': 'mul',
                                'gl_dst_color gl_src_color': 'mul2', 'add': 'add', 'gl_one gl_one': 'add',
                                'blend': 'blend', 'gl_src_alpha gl_one_minus_src_alpha': 'blend'}.get(b, b)
            elif k == 'rgbgen' and t[1].lower() == 'const':
                cur['rgb'] = tuple(float(x) for x in t[3:6])
            elif k == 'tcmod' and t[1].lower() == 'scale':
                cur['scale'] = (float(t[2]), float(t[3]))
    return stages


def bake_2d(files, by_base, zips, owner, tmp):
    """Composite each BAKE_2D shader into <cache>/native/openarena/gfx/baked/<name>.png."""
    text = ''.join(v for k, v in files.items() if k.endswith('.shader'))
    out = {}
    for name in BAKE_2D:
        stages = parse_shader(text, name)
        if not stages:
            continue
        canvas = os.path.join(tmp, name + '.miff')
        ok = True
        for i, st in enumerate(stages):
            layer = os.path.join(tmp, f'{name}_{i}.miff')
            src = st.get('map', '$whiteimage')
            if src.startswith('$'):
                subprocess.run(['convert', '-size', f'{BAKE_SIZE}x{BAKE_SIZE}', 'xc:white', layer], check=True)
            else:
                low = by_base.get(os.path.splitext(src.lower())[0])
                if low is None:
                    ok = False
                    break
                raw = os.path.join(tmp, 'raw_' + os.path.basename(low))
                data = zips[owner[low][0]].read(owner[low][1])
                open(raw, 'wb').write(tga_for_magick(data) if low.endswith('.tga') else data)
                sx, sy = st['scale']
                tw, th = max(1, round(BAKE_SIZE / abs(sx))), max(1, round(BAKE_SIZE / abs(sy)))
                flips = (['-flop'] if sx < 0 else []) + (['-flip'] if sy < 0 else [])
                subprocess.run(['convert', '-size', f'{BAKE_SIZE}x{BAKE_SIZE}',
                                '(', raw + '[0]', '-resize', f'{tw}x{th}!', *flips, '-write', 'mpr:t', '+delete', ')',
                                'tile:mpr:t', layer], check=True)
            r, g, b = st['rgb']
            if (r, g, b) != (1, 1, 1):
                subprocess.run(['convert', layer, '-color-matrix', f'{r} 0 0 0 {g} 0 0 0 {b}', layer], check=True)
            if i == 0:
                os.replace(layer, canvas)
                continue
            op = {'mul': ['-compose', 'Multiply'], 'mul2': ['-compose', 'Multiply'], 'add': ['-compose', 'Plus'],
                  'blend': ['-compose', 'Over']}.get(st['blend'])
            if op is None:
                ok = False
                break
            cmd = ['convert', canvas, layer, *op, '-composite']
            if st['blend'] == 'mul2':
                cmd += ['-evaluate', 'multiply', '2']
            subprocess.run(cmd + [canvas], check=True)
            os.remove(layer)
        if ok:
            dst = os.path.join(NATIVE, 'gfx/baked', name + '.png')
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            subprocess.run(['convert', canvas, '-alpha', 'off', dst], check=True)
            out[name] = 'gfx/baked/' + name
        for f in os.listdir(tmp):
            if f.startswith(name) or f.startswith('raw_'):
                os.remove(os.path.join(tmp, f))
    return out


MERGE = {
    'Files': '''local out = { files = {}, paths = {} }
for i = 1, @N do
	for k, v in require(script:FindFirstChild("part_" .. i)) do
		if type(k) == "number" then
			table.insert(out.paths, v)
		else
			out.files[k] = v
		end
	end
end
return out
''',
    'AssetIndex': '''local out = { images = {}, models = {} }
for i = 1, @N do
	for k, v in require(script:FindFirstChild("part_" .. i)) do
		if k == "baked2d" then
			out.baked2d = v
		elseif v.md3b64 then
			out.models[k] = v
		else
			out.images[k] = v
		end
	end
end
return out
''',
}


def tga_for_magick(blob):
    """Drop a TGA 2.0 footer/extension area: its attributes type often says
    "no alpha" while the pixels carry it, and ImageMagick believes it (Q3
    doesn't read it)."""
    if len(blob) > 26 and blob[-18:-2] == b'TRUEVISION-XFILE':
        ext, dev = struct.unpack_from('<II', blob, len(blob) - 26)
        cut = min(x for x in (ext, dev, len(blob) - 26) if x > 0)
        return blob[:cut]
    return blob


def lua_str(s):
    return '"' + (s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
                  .replace('\r', '\\r').replace('\0', '')) + '"'


def write_parts(name, header, entries):
    d = os.path.join(OUT, name)
    os.makedirs(d, exist_ok=True)
    for f in os.listdir(d):
        os.remove(os.path.join(d, f))
    parts, cur, size = [], [], 0
    for e in entries:
        if size + len(e) > LIMIT and cur:
            parts.append(cur)
            cur, size = [], 0
        cur.append(e)
        size += len(e) + 2
    if cur:
        parts.append(cur)
    for i, p in enumerate(parts, 1):
        with open(os.path.join(d, f'part_{i}.luau'), 'w') as f:
            f.write('-- generated by scripts/client-dev-assets.py\nreturn {\n' + ',\n'.join(p) + '\n}\n')
    with open(os.path.join(d, 'init.luau'), 'w') as f:
        f.write('-- generated by scripts/client-dev-assets.py: ' + header + '\n')
        f.write(MERGE[name].replace('@N', str(len(parts))))


def main():
    # Q3 search order (the alphabetically last pk3 wins), with the player
    # roster applied: tools/roster.py, tools/oaconv/roster.json
    shipped = roster.Shipped(BASEOA)
    owner = shipped.owner
    paks = sorted({p for p, _ in owner.values()})
    zips = {p: zipfile.ZipFile(os.path.join(BASEOA, p)) for p in paks}
    files, images = shipped.text_files(), set()
    for low in owner:
        ext = os.path.splitext(low)[1]
        if ext in IMAGE_EXT and (low.startswith(IMAGE_DIRS)
                                   or re.match(r'models/players/[^/]+/icon_', low)):
            images.add(low)
    # sky box faces named by skyparms
    by_base = {}
    for low in owner:
        if os.path.splitext(low)[1] in IMAGE_EXT:
            by_base.setdefault(os.path.splitext(low)[0], low)
    for low, text in files.items():
        if low.endswith('.shader'):
            for m in re.finditer(r'(?im)^\s*skyparms\s+(\S+)', text):
                for s in ('rt', 'bk', 'lf', 'ft', 'up', 'dn'):
                    b = m.group(1).lower() + '_' + s
                    if b in by_base:
                        images.add(by_base[b])
    # one file per base name, in the renderer's lookup order (tga, png, jpg)
    order = {'.tga': 0, '.png': 1, '.jpg': 2}
    pick = {}
    for low in sorted(images, key=lambda l: order[os.path.splitext(l)[1]]):
        pick.setdefault(os.path.splitext(low)[0], low)
    images = set(pick.values())
    blobs = {low: zips[owner[low][0]].read(owner[low][1]) for low in images}
    os.makedirs(NATIVE, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix='oa-dev-assets-', dir=OUT)

    def convert(low):
        base = os.path.splitext(low)[0]
        dst = os.path.join(NATIVE, base + '.png')
        src = os.path.join(tmp, low.replace('/', '__'))
        with open(src, 'wb') as f:
            f.write(tga_for_magick(blobs[low]) if low.endswith('.tga') else blobs[low])
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        r = subprocess.run(['convert', src + '[0]', dst], capture_output=True)
        os.remove(src)
        if r.returncode != 0:
            print('skip (convert failed):', low)
            return None
        wh = subprocess.run(['identify', '-format', '%w %h', dst], capture_output=True, text=True).stdout.split()
        if len(wh) < 2:
            print('skip (identify failed):', low)
            return None
        return base, int(wh[0]), int(wh[1])

    with ThreadPoolExecutor(12) as ex:
        results = [r for r in ex.map(convert, sorted(images)) if r]
    baked = bake_2d(files, by_base, zips, owner, tmp)
    os.rmdir(tmp)
    results += [(b, BAKE_SIZE, BAKE_SIZE) for b in baked.values()]
    entries = ['[%s] = { id = %s, w = %d, h = %d }' % (lua_str(b), lua_str('rbxasset://openarena/' + b + '.png'), w, h)
               for b, w, h in sorted(results)]
    entries.append('baked2d = { %s }' % ', '.join('[%s] = %s' % (lua_str(k), lua_str(v)) for k, v in sorted(baked.items())))
    for low in sorted(owner):
        if low.endswith('.md3') and low.startswith('models/'):
            blob = zips[owner[low][0]].read(owner[low][1])
            if not (FULL_MODELS or len(blob) < 64 * 1024 and not low.startswith('models/players/')):
                blob = md3_lite(blob)
            entries.append('[%s] = { md3b64 = %s }' % (lua_str(low[:-4]), lua_str(base64.b64encode(blob).decode())))
    write_parts('AssetIndex', 'OA 2D images in the local rbx-native asset cache, MD3 models', entries)
    fentries = ['[%s] = %s' % (lua_str(k), lua_str(v)) for k, v in sorted(files.items())]
    fentries += [lua_str(k) for k in sorted(owner) if k not in files]
    write_parts('Files', 'OA text files and the list of every data path', fentries)
    print(f'{len(results)} images -> {NATIVE}; {len(files)} text files, {len(owner)} paths -> {OUT}')


if __name__ == '__main__':
    main()
