#!/usr/bin/env python3
"""Resolve the upload lock's asset ids into the ids a place references, and
write them to place/asset-ids.json (committed: asset ids are not secret).

  place/resolve_ids.py [--lock PATH]

`oaconv upload` records one asset id per uploaded file. What each one is,
checked with Open Cloud (assets/v1 metadata + asset-delivery-api):

- Model (.glb): an asset of type Model (delivery assetTypeId 10), a binary
  .rbxm holding a Model per glTF node with one MeshPart each, named after
  the manifest mesh. The MeshParts carry MeshContent = rbxassetid://<mesh>
  and no texture. The importer turns the scene 180 degrees about Y: a part
  sits at (-x, y, -z) of the manifest's center.
- Image (.png): uploaded as assetType Decal (delivery assetTypeId 13). Its
  content is a Decal whose Texture is http://www.roblox.com/asset/?id=<image>,
  and <image> is a separate asset of type Image (assetTypeId 1). A Texture,
  ImageLabel or MeshPart.TextureID needs the image id, not the decal id.
- Audio (.ogg): the asset id is the Sound id.

The key comes from the keyring entry rbx-native stores (never printed or
written anywhere). Already resolved entries are kept, so a re-run after the
upload grows only resolves what is new.
"""
import argparse
import gzip
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'place', 'asset-ids.json')
DEFAULT_LOCK = os.path.join(os.path.dirname(ROOT), 'conv', 'build', 'assets.lock.json')
LUNE = os.environ.get('LUNE', os.path.expanduser('~/.local/bin/lune'))

MESHES_LUAU = '''
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local out = {}
for _, inst in roblox.deserializeModel(fs.readFile(process.args[1])) do
	for _, d in inst:GetDescendants() do
		if d:IsA("MeshPart") then
			local c = d.MeshContent
			local p = d.CFrame.Position
			local s = d.InitialSize
			table.insert(out, string.format('"%s":{"mesh":"%s","pos":[%g,%g,%g],"size":[%g,%g,%g]}',
				d.Name, tostring(c.Uri), p.X, p.Y, p.Z, s.X, s.Y, s.Z))
		end
	end
end
print("{" .. table.concat(out, ",") .. "}")
'''


def api_key():
    import gi
    gi.require_version('Secret', '1')
    from gi.repository import Secret
    key = Secret.password_lookup_sync(None, {'url': 'https://apis.roblox.com/rbx-native'}, None)
    if not key:
        sys.exit('no Open Cloud key in the keyring')
    return key


KEY = None


def get(url, keyed=True, tries=5):
    for attempt in range(tries):
        req = urllib.request.Request(url, headers={'x-api-key': KEY} if keyed else {})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504) and attempt < tries - 1:
                time.sleep(2 ** attempt)
                continue
            raise
        except urllib.error.URLError:
            if attempt < tries - 1:
                time.sleep(2 ** attempt)
                continue
            raise


def delivery(asset_id):
    d = json.loads(get(f'https://apis.roblox.com/asset-delivery-api/v1/assetId/{asset_id}'))
    body = get(d['location'], keyed=False)
    if body[:2] == b'\x1f\x8b':
        body = gzip.decompress(body)
    return d.get('assetTypeId'), body


def resolve_image(decal_id):
    kind, body = delivery(decal_id)
    if kind == 1:  # already an Image
        return decal_id
    m = re.search(rb'<Content name="Texture">\s*<url>[^<]*?id=(\d+)', body)
    if kind != 13 or not m:
        raise RuntimeError(f'{decal_id}: assetTypeId {kind}, no Decal texture')
    return int(m.group(1))


def resolve_model(model_id):
    kind, body = delivery(model_id)
    if kind != 10:
        raise RuntimeError(f'{model_id}: assetTypeId {kind}, not a Model')
    with tempfile.TemporaryDirectory() as tmp:
        rbxm, script = os.path.join(tmp, 'm.rbxm'), os.path.join(tmp, 'meshes.luau')
        open(rbxm, 'wb').write(body)
        open(script, 'w').write(MESHES_LUAU)
        out = subprocess.run([LUNE, 'run', script, rbxm], capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def main():
    global KEY
    ap = argparse.ArgumentParser()
    ap.add_argument('--lock', default=DEFAULT_LOCK)
    args = ap.parse_args()
    lock = json.load(open(args.lock))
    ids = json.load(open(OUT)) if os.path.exists(OUT) else {}
    ids.setdefault('images', {})
    ids.setdefault('models', {})
    ids.setdefault('audio', {})
    KEY = api_key()

    todo = []
    for path, e in sorted(lock.items()):
        aid = e['asset_id']
        if e['type'] == 'Image':
            have = ids['images'].get(path)
            if not have or have['decal'] != aid:
                todo.append(('images', path, aid, resolve_image))
        elif e['type'] == 'Model':
            have = ids['models'].get(path)
            if not have or have['asset'] != aid:
                todo.append(('models', path, aid, resolve_model))
        elif e['type'] == 'Audio':
            ids['audio'][path] = aid

    def work(job):
        kind, path, aid, fn = job
        try:
            return kind, path, aid, fn(aid), None
        except Exception as ex:  # report and keep going: a re-run retries it
            return kind, path, aid, None, str(ex)

    failed = 0
    with ThreadPoolExecutor(8) as ex:
        for n, (kind, path, aid, res, err) in enumerate(ex.map(work, todo), 1):
            if err:
                failed += 1
                print('failed', path, err)
            elif kind == 'images':
                ids['images'][path] = {'decal': aid, 'image': res}
            else:
                ids['models'][path] = {'asset': aid, 'meshes': res}
            if n % 200 == 0:
                print(f'{n}/{len(todo)}')
    for k in ids:
        ids[k] = dict(sorted(ids[k].items()))
    with open(OUT, 'w') as f:
        json.dump(ids, f, indent=1, sort_keys=True)
        f.write('\n')
    print(f"{len(todo) - failed} resolved, {failed} failed; images {len(ids['images'])}, "
          f"models {len(ids['models'])}, audio {len(ids['audio'])} -> {OUT}")


if __name__ == '__main__':
    main()
