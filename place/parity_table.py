#!/usr/bin/env python3
"""Print the generated tables of docs/PARITY.md (maps and items) from the
converter output (build/), the resolved asset ids (place/asset-ids.json)
and the headless bot sweep (docs/parity/sweep.txt).

  place/parity_table.py > /tmp/tables.md
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
B = os.path.join(ROOT, 'build')
ids = json.load(open(os.path.join(ROOT, 'place', 'asset-ids.json')))
images, models = ids['images'], ids['models']

sweep = {}
for line in open(os.path.join(ROOT, 'docs', 'parity', 'sweep.txt')):
    if line.startswith('#') or not line.strip():
        continue
    m, gt, rest = line.split(' ', 2)
    res = rest.rsplit(' ', 3)
    sweep[(m, gt)] = (res[0], res[1:])


def sweep_cell(m, gt):
    if (m, gt) not in sweep:
        return '-'
    r, (bots, kills, items) = sweep[(m, gt)]
    if r == 'ok':
        return f'ok ({kills} kills)'
    return r.split(' (')[0]


maps = sorted(d for d in os.listdir(os.path.join(B, 'maps')) if os.path.isdir(os.path.join(B, 'maps', d)))
print('| map | mesh | atlas pages uploaded | aas | FFA sweep | CTF sweep |')
print('|---|---|---|---|---|---|')
used = {}
for m in maps:
    j = json.load(open(os.path.join(B, 'maps', m, 'map.json')))
    for cls, n in j['entities']['counts'].items():
        used.setdefault(cls, []).append(m)
    mesh = 'yes' if f'maps/{m}/mesh_0.glb' in models else 'no'
    pages = j.get('atlas', [])
    up = sum(1 for p in pages if images.get(f'maps/{m}/{p}', {}).get('image'))
    aas = 'yes' if 'module' in j.get('aas', {}) else 'none in pk3'
    print(f'| {m} | {mesh} | {up}/{len(pages)} | {aas} | {sweep_cell(m, "ffa")} | {sweep_cell(m, "ctf")} |')

md3 = json.load(open(os.path.join(B, 'models.json')))['md3']
md3_names = set(md3) if isinstance(md3, dict) else {x if isinstance(x, str) else x.get('path') for x in md3}
print()
print('| item | pickup name | maps placing it | world model converted | icon uploaded |')
print('|---|---|---|---|---|')
src = open(os.path.join(ROOT, 'src', 'shared', 'bg', 'bg_itemlist.luau')).read()
for m in re.finditer(r'classname = "([^"]+)".*?world_model = \{ \[0\] = (?:"([^"]*)"|nil).*?icon = (?:"([^"]*)"|nil), pickup_name = "([^"]*)"', src):
    cls, model, icon, name = m.groups()
    stem = (model or '').rsplit('.', 1)[0]
    conv = 'yes' if model and any(stem in n for n in md3_names) else ('-' if not model else 'no')
    ic = '-' if not icon else ('yes' if images.get(f'images/{icon}.png', {}).get('image') else 'pending/held')
    print(f'| {cls} | {name} | {len(used.get(cls, []))} | {conv} | {ic} |')
