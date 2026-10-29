#!/usr/bin/env python3
"""Visual parity driver: renders the client's fixtures (src/client/dev/Scene)
in rbx-native's editor over MCP and puts them next to the reference shots.

  scripts/parity.py [--push] [menu hud scores]

Needs a running rbxstudio (with the MCP beta on) that can resolve
rbxasset://openarena/... from its asset cache (scripts/client-dev-assets.py
fills it), and RBXSTUDIO pointing at that binary. XDG_CONFIG_HOME must be the
editor's, so `rbxstudio --mcp` finds it.

--push copies src/ and build/client/{Files,AssetIndex} into
ReplicatedStorage.OA as ModuleScripts first (needed after any source change).
Each fixture is drawn into a 640x360 frame (half the reference) on a magenta
background (the reference shots clear to magenta: r_clear 1), captured,
cropped (build/parity/<name>.png) and put beside the reference in
docs/parity/<name>_side.png (reference left, ours right).
"""
import base64
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import queue

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RBX = os.environ.get('RBXSTUDIO', 'rbxstudio')
# rbx-native has no UIScale: draw straight at half the reference size
W, H = 640, 360


class MCP:
    def __init__(self):
        self.p = subprocess.Popen([RBX, '--mcp'], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL)
        self.q, self.id = queue.Queue(), 0
        threading.Thread(target=self._read, daemon=True).start()
        self.call('initialize', {'protocolVersion': '2025-06-18', 'capabilities': {},
                                 'clientInfo': {'name': 'oa-parity', 'version': '1'}})
        self._send({'jsonrpc': '2.0', 'method': 'notifications/initialized', 'params': {}})
        studios = self.tool('list_roblox_studios', {})
        self.studio = None
        self.studio = json.loads(studios[0]['text'])['studios'][0]['id']

    def _read(self):
        for line in self.p.stdout:
            try:
                self.q.put(json.loads(line))
            except ValueError:
                pass

    def _send(self, msg):
        self.p.stdin.write((json.dumps(msg) + '\n').encode())
        self.p.stdin.flush()

    def call(self, method, params, timeout=600):
        self.id += 1
        i = self.id
        self._send({'jsonrpc': '2.0', 'id': i, 'method': method, 'params': params})
        end = time.time() + timeout
        while time.time() < end:
            try:
                msg = self.q.get(timeout=1)
            except queue.Empty:
                continue
            if msg.get('id') == i:
                if 'error' in msg:
                    raise RuntimeError(msg['error'])
                return msg['result']
        raise TimeoutError(method)

    def tool(self, name, args):
        if getattr(self, 'studio', None):
            args = dict(args, studio_id=self.studio)
        r = self.call('tools/call', {'name': name, 'arguments': args})
        if r.get('isError'):
            raise RuntimeError(f'{name}: ' + json.dumps(r['content'])[:2000])
        return r['content']

    def luau(self, code):
        out = self.tool('execute_luau', {'code': code, 'datamodel_type': 'Edit'})
        return ''.join(c.get('text', '') for c in out)

    def close(self):
        self.p.terminate()
        self.p.wait()


def long_string(s):
    level = 1
    while (']' + '=' * level + ']') in s:
        level += 1
    eq = '=' * level
    return '[' + eq + '[\n' + s + ']' + eq + ']'


def modules():
    """(instance path under ReplicatedStorage.OA, source) for every module."""
    out = []
    src = os.path.join(ROOT, 'src')
    for dirpath, _, files in os.walk(src):
        for f in sorted(files):
            if not f.endswith('.luau') or f.endswith('.client.luau') or f.endswith('.server.luau'):
                continue
            rel = os.path.relpath(os.path.join(dirpath, f), src)[:-5].split(os.sep)
            out.append((rel, open(os.path.join(dirpath, f)).read()))
    for pack in ('Files', 'AssetIndex'):
        d = os.path.join(ROOT, 'build/client', pack)
        for f in sorted(os.listdir(d)):
            rel = ['client', 'sys', pack] + ([] if f == 'init.luau' else [f[:-5]])
            out.append((rel, open(os.path.join(d, f)).read()))
    # parents before children (an init module is its folder)
    out.sort(key=lambda m: (len(m[0]), m[0]))
    return out


PUSH_HEAD = '''
local RS = game:GetService("ReplicatedStorage")
local function at(path, isModule)
	local node = RS:FindFirstChild("OA")
	if node == nil then
		node = Instance.new("Folder")
		node.Name = "OA"
		node.Parent = RS
	end
	for i, name in path do
		local child = node:FindFirstChild(name)
		local last = i == #path
		if child and last and isModule and not child:IsA("ModuleScript") then
			-- a folder that turns out to have an init module
			local m = Instance.new("ModuleScript")
			m.Name = name
			for _, c in child:GetChildren() do
				c.Parent = m
			end
			child:Destroy()
			m.Parent = node
			child = m
		end
		if child == nil then
			child = Instance.new(if last and isModule then "ModuleScript" else "Folder")
			child.Name = name
			child.Parent = node
		end
		node = child
	end
	return node
end
'''


def push(mcp):
    mcp.luau('local o = game:GetService("ReplicatedStorage"):FindFirstChild("OA") if o then o:Destroy() end')
    batch, size, n = [], 0, 0
    mods = modules()

    def flush():
        nonlocal batch, size
        if batch:
            mcp.luau(PUSH_HEAD + '\n'.join(batch))
            batch, size = [], 0
    for path, source in mods:
        line = 'at({%s}, true).Source = %s' % (', '.join(json.dumps(p) for p in path), long_string(source))
        if size + len(line) > 900_000:
            flush()
        batch.append(line)
        size += len(line)
        n += 1
    flush()
    print(f'pushed {n} modules')


RUN = '''
local SG = game:GetService("StarterGui")
local old = SG:FindFirstChild("OAParity")
if old then old:Destroy() end
-- a fresh copy of the modules: require caches by instance, each fixture
-- boots a clean client
local src = game:GetService("ReplicatedStorage").OA:Clone()
src.Name = "OAParityRun"
src.Parent = game:GetService("ReplicatedStorage")
local gui = Instance.new("ScreenGui")
gui.Name = "OAParity"
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 100
local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.fromRGB(255, 0, 128)
bg.BorderSizePixel = 0
bg.Parent = gui
local frame = Instance.new("Frame")
frame.Name = "Screen"
frame.Size = UDim2.fromOffset(%(w)d, %(h)d)
frame.BackgroundTransparency = 1
frame.ClipsDescendants = true
frame.Parent = bg
-- scale marker: a 100 px green square right of the screen, so the capture's
-- scale (the editor may present the viewport scaled) can be measured
local mark = Instance.new("Frame")
mark.Name = "ScaleMark"
mark.Position = UDim2.fromOffset(%(w)d + 20, 0)
mark.Size = UDim2.fromOffset(100, 100)
mark.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
mark.BorderSizePixel = 0
mark.Parent = bg
gui.Parent = SG
local Scene = require(src.client.dev.Scene)
local ok, err = pcall(function()
	Scene.boot(frame, %(w)d, %(h)d)
	Scene.%(name)s()
end)
local n = Scene.census(frame)
src:Destroy()
return (if ok then "ok" else "error: " .. tostring(err)) .. " labels=" .. n
'''


def capture(mcp, name):
    out = mcp.tool('screen_capture', {'capture_id': 'oa_' + name})
    for c in out:
        if c.get('type') == 'image':
            return base64.b64decode(c['data'])
    raise RuntimeError('no image in screen_capture: ' + json.dumps(out)[:500])


def main():
    args = sys.argv[1:]
    do_push = '--push' in args
    names = [a for a in args if not a.startswith('--')] or ['menu', 'hud', 'scores']
    mcp = MCP()
    try:
        if do_push:
            push(mcp)
        for name in names:
            print(name, mcp.luau(RUN % {'name': name, 'w': W, 'h': H}))
            time.sleep(1.0)
            jpg = capture(mcp, name)
            with tempfile.TemporaryDirectory(dir=os.path.join(ROOT, 'build')) as tmp:
                raw = os.path.join(tmp, 'raw.jpg')
                open(raw, 'wb').write(jpg)
                w, h = W, H
                os.makedirs(os.path.join(ROOT, 'build/parity'), exist_ok=True)
                ours = os.path.join(ROOT, 'build/parity', name + '.png')
                ref = os.path.join(ROOT, 'docs/parity/ref', {'menu': 'menu_main', 'hud': 'hud_ffa',
                                                            'scores': 'scoreboard_ffa'}[name] + '.png')
                # the marker's top rows: nothing else green sits at the top edge
                geo = subprocess.run(['convert', raw, '-crop', 'x3+0+1', '+repage',
                                      '-fuzz', '30%', '-fill', 'black', '+opaque', '#00ff00',
                                      '-trim', '-format', '%w %h %X %Y', 'info:'],
                                     capture_output=True, text=True, check=True).stdout.split()
                scale = int(geo[0]) / 100.0
                cw, ch = round(w * scale), round(h * scale)
                subprocess.run(['convert', raw, '-crop', f'{cw}x{ch}+0+0', '+repage', '-resize', f'{w}x{h}!',
                                ours], check=True)
                if abs(scale - 1) > 0.01:
                    print(f'  capture scale {scale:.3f}, resampled')
                side = os.path.join(ROOT, 'docs/parity', name + '_side.png')
                subprocess.run(['convert', '(', ref, '-resize', f'{w}x{h}', ')', ours, '+append', side], check=True)
                diff = subprocess.run(['compare', '-metric', 'RMSE', '(', ref, '-resize', f'{w}x{h}', ')', ours,
                                       'null:'], capture_output=True, text=True).stderr.strip()
                print(f'  {side}  RMSE {diff}')
    finally:
        mcp.luau('local g = game:GetService("StarterGui"):FindFirstChild("OAParity") if g then g:Destroy() end')
        mcp.close()


if __name__ == '__main__':
    main()
