#!/usr/bin/env python3
# Copyright (C) 2026 openarena-rbx contributors
# This file is part of openarena-rbx. GPL-2.0-or-later, see COPYING.
"""Generates the R15 animation set for Roblox avatars from OpenArena's sarge.

    tools/gen_avatar_anims.py            # writes src/client/avatar/anims/*.luau
    tools/gen_avatar_anims.py --check    # fails if the committed files differ

Reads models/players/sarge/{animation.cfg,lower.md3,upper.md3} from the 0.8.8
pk3s in vendor/ and measures, frame by frame:

  legs   (lower.md3)  hip, knee and foot vertex clusters picked on the idle
                      frame and followed by vertex index, plus tag_torso;
  torso  (upper.md3)  tag_head, tag_weapon and the shoulder clusters.

Each frame becomes R15 joint rotations by two-bone IK in leg/arm-length
units, so an avatar of any proportions gets the same angles; positions are
ratios of sarge's leg length. The runtime (src/client/avatar/AvatarAnim.luau)
turns the data into KeyframeSequences and samples it. Rotations are written
in the character's own axes (X right, Y up, -Z forward), the frame an R15
rig's joints share at rest; docs/client-notes.md, "Roblox avatars", explains
every measurement and choice.
"""
import math
import os
import struct
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASEOA = os.path.join(ROOT, 'vendor/oa088/openarena-0.8.8/baseoa')
OUT = os.path.join(ROOT, 'src/client/avatar/anims')
MODEL = 'models/players/sarge/'

NAMES = ['BOTH_DEATH1', 'BOTH_DEAD1', 'BOTH_DEATH2', 'BOTH_DEAD2', 'BOTH_DEATH3', 'BOTH_DEAD3',
         'TORSO_GESTURE', 'TORSO_ATTACK', 'TORSO_ATTACK2', 'TORSO_DROP', 'TORSO_RAISE',
         'TORSO_STAND', 'TORSO_STAND2',
         'LEGS_WALKCR', 'LEGS_WALK', 'LEGS_RUN', 'LEGS_BACK', 'LEGS_SWIM',
         'LEGS_JUMP', 'LEGS_LAND', 'LEGS_JUMPB', 'LEGS_LANDB', 'LEGS_IDLE', 'LEGS_IDLECR', 'LEGS_TURN']

# Ground speed (u/s) each locomotion cycle is played at in OA: pm_runspeed 320,
# a walk is a half stick (forwardmove 64 of 127), crouching is pm_duckScale 0.25.
# The planted foot is stretched to this speed so it doesn't skate (see notes).
STRIDE_SPEED = {'LEGS_RUN': 320, 'LEGS_BACK': 320, 'LEGS_WALK': 160, 'LEGS_WALKCR': 80}

# IK segment ratios (of the limb's length): sarge's thigh/shin from the idle
# frame; R15's upper arm against lower arm + half the hand.
LEG_SPLIT = None  # measured
ARM_SPLIT = 0.48

# vector / quaternion helpers -------------------------------------------------
def add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def mul(a, s): return (a[0] * s, a[1] * s, a[2] * s)
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def length(a): return math.sqrt(dot(a, a))
def norm(a):
    n = length(a)
    return mul(a, 1 / n) if n > 1e-9 else (0.0, 0.0, 0.0)
def centroid(frame, ids): return mul(tuple(map(sum, zip(*(frame[i] for i in ids)))), 1 / len(ids))
def perp(v, axis): return norm(sub(v, mul(axis, dot(v, axis))))

# OA model axes (x forward, y left, z up) -> character axes (X right, Y up, Z back)
def rbx(v): return (-v[1], v[2], -v[0])

# matrices are column triples (X, Y, Z) of the rotated frame
def mat_from_axes(x, y, z): return (x, y, z)
def mat_mul(a, b):
    # (a * b) column j = a applied to b's column j
    return tuple(mat_vec(a, b[j]) for j in range(3))
def mat_vec(m, v): return add(add(mul(m[0], v[0]), mul(m[1], v[1])), mul(m[2], v[2]))
def mat_t(m): return ((m[0][0], m[1][0], m[2][0]), (m[0][1], m[1][1], m[2][1]), (m[0][2], m[1][2], m[2][2]))
IDENT = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))

def orthonormal(y, zhint):
    """Frame with Y along y and Z as close to zhint as possible."""
    y = norm(y)
    z = perp(zhint, y)
    if length(z) < 1e-6:
        z = perp((0, 0, 1), y)
    return mat_from_axes(cross(y, z), y, z)

def rot_between(a, b):
    """Shortest rotation taking direction a onto b, as a matrix."""
    a, b = norm(a), norm(b)
    v = cross(a, b)
    c = dot(a, b)
    s = length(v)
    if s < 1e-9:
        return IDENT
    k = mul(v, 1 / s)
    ang = math.atan2(s, c)
    return axis_angle(k, ang)

def axis_angle(k, ang):
    c, s = math.cos(ang), math.sin(ang)
    def r(v): return add(add(mul(v, c), mul(cross(k, v), s)), mul(k, dot(k, v) * (1 - c)))
    return (r((1, 0, 0)), r((0, 1, 0)), r((0, 0, 1)))

def quat(m):
    (xx, yx, zx), (xy, yy, zy), (xz, yz, zz) = m[0], m[1], m[2]
    # m[c][r]: column c, row r. Rotation matrix rows: R[r][c]
    R = [[m[c][r] for c in range(3)] for r in range(3)]
    tr = R[0][0] + R[1][1] + R[2][2]
    if tr > 0:
        s = math.sqrt(tr + 1) * 2
        w, x, y, z = s / 4, (R[2][1] - R[1][2]) / s, (R[0][2] - R[2][0]) / s, (R[1][0] - R[0][1]) / s
    elif R[0][0] > R[1][1] and R[0][0] > R[2][2]:
        s = math.sqrt(1 + R[0][0] - R[1][1] - R[2][2]) * 2
        w, x, y, z = (R[2][1] - R[1][2]) / s, s / 4, (R[0][1] + R[1][0]) / s, (R[0][2] + R[2][0]) / s
    elif R[1][1] > R[2][2]:
        s = math.sqrt(1 + R[1][1] - R[0][0] - R[2][2]) * 2
        w, x, y, z = (R[0][2] - R[2][0]) / s, (R[0][1] + R[1][0]) / s, s / 4, (R[1][2] + R[2][1]) / s
    else:
        s = math.sqrt(1 + R[2][2] - R[0][0] - R[1][1]) * 2
        w, x, y, z = (R[1][0] - R[0][1]) / s, (R[0][2] + R[2][0]) / s, (R[1][2] + R[2][1]) / s, s / 4
    if w < 0:
        w, x, y, z = -w, -x, -y, -z
    return (x, y, z, w)

def tag_mat(axis):
    """An md3 tag's axis (forward, left, up rows, possibly scaled) in character axes."""
    f, l, u = norm(axis[0:3]), norm(axis[3:6]), norm(axis[6:9])
    return mat_from_axes(norm(rbx(mul(l, -1))), norm(rbx(u)), norm(rbx(mul(f, -1))))

# md3 / pk3 ---------------------------------------------------------------------
def pk3_file(name):
    """The file as OA resolves it: the last pk3 in sorted order wins."""
    data = None
    for p in sorted(os.listdir(BASEOA)):
        if p.endswith('.pk3') and 'mature' not in p:
            with zipfile.ZipFile(os.path.join(BASEOA, p)) as z:
                if name in z.namelist():
                    data = z.read(name)
    if data is None:
        sys.exit('missing %s in %s' % (name, BASEOA))
    return data

def md3(b):
    _, _, _, _, nF, nT, nS, _, oF, oT, oS, _ = struct.unpack_from('<4si64s9i', b, 0)
    tags = []
    for f in range(nF):
        d = {}
        for t in range(nT):
            r = struct.unpack_from('<64s3f9f', b, oT + (f * nT + t) * 112)
            d[r[0].split(b'\0')[0].decode()] = (tuple(r[1:4]), tuple(r[4:13]))
        tags.append(d)
    verts = [[] for _ in range(nF)]
    o = oS
    for _ in range(nS):
        _, _, _, snF, _, nV, _, _, _, _, oXyz, oEnd = struct.unpack_from('<4s64s10i', b, o)
        for f in range(snF):
            for v in range(nV):
                x, y, z, _ = struct.unpack_from('<hhhh', b, o + oXyz + (f * nV + v) * 8)
                verts[f].append((x / 64, y / 64, z / 64))
        o += oEnd
    return {'frames': nF, 'tags': tags, 'verts': verts}

def parse_cfg(text):
    nums = []
    for line in text.splitlines():
        line = line.split('//')[0].split()
        if len(line) == 4 and all(t.lstrip('-').replace('.', '').isdigit() for t in line):
            nums.append((int(line[0]), int(line[1]), int(line[2]), float(line[3])))
    assert len(nums) == len(NAMES), 'animation.cfg: %d entries' % len(nums)
    return dict(zip(NAMES, nums))

# legs ----------------------------------------------------------------------------
GROUND = -24.0  # MINS z: the bottom of the player box, where the feet stand

class Legs:
    def __init__(self, lower, idle):
        self.m = lower
        I = lower['verts'][idle]
        self.sets = {}
        for side, sg in (('L', 1), ('R', -1)):
            self.sets[side + 'hip'] = [i for i, v in enumerate(I) if v[1] * sg > 1 and -3 < v[2] < 1]
            self.sets[side + 'knee'] = [i for i, v in enumerate(I) if v[1] * sg > 1 and -13 < v[2] < -9]
            foot = [i for i, v in enumerate(I) if v[1] * sg > 1 and v[2] < -20]
            foot.sort(key=lambda i: I[i][0])
            third = max(1, len(foot) // 3)
            self.sets[side + 'foot'] = foot
            self.sets[side + 'heel'] = foot[:third]
            self.sets[side + 'toe'] = foot[-third:]
        p = self.points(idle)
        thigh = (length(sub(p['Lknee'], p['Lhip'])) + length(sub(p['Rknee'], p['Rhip']))) / 2
        shin = (length(sub(p['Lfoot'], p['Lknee'])) + length(sub(p['Rfoot'], p['Rknee']))) / 2
        foot_h = (p['Lfoot'][2] + p['Rfoot'][2]) / 2 - GROUND
        self.split = thigh / (thigh + shin)
        self.chain = thigh + shin            # hip -> foot point
        self.length = thigh + shin + foot_h  # hip -> sole, straight
        self.foot_h = foot_h
        self.foot_z = (p['Lfoot'][2] + p['Rfoot'][2]) / 2
        mid = mul(add(p['Lhip'], p['Rhip']), 0.5)
        self.idle_spine = sub(lower['tags'][idle]['tag_torso'][0], mid)

    def points(self, f):
        V = self.m['verts'][f]
        return {k: centroid(V, ids) for k, ids in self.sets.items()}

    def frame(self, f, stride=1.0):
        p = self.points(f)
        tag_o, tag_ax = self.m['tags'][f]['tag_torso']
        mid = mul(add(p['Lhip'], p['Rhip']), 0.5)
        # pelvis: tilt from the idle spine (hip middle -> tag_torso) to this
        # frame's, then yaw/roll so the hip line matches
        tilt = rot_between(rbx(self.idle_spine), rbx(sub(tag_o, mid)))
        right = rbx(sub(p['Rhip'], p['Lhip']))
        up = mat_vec(tilt, (0, 1, 0))
        x = perp(right, up)
        pelvis = mat_from_axes(x, up, cross(x, up))
        pt = mat_t(pelvis)
        out = {'pelvis': pelvis,
               # how far the lower foot is off the floor (a jump's tuck), in leg lengths
               'clear': max(0.0, (min(p['Lfoot'][2], p['Rfoot'][2]) - self.foot_z) / self.length),
               'pos': rbx(((mid[0]) / self.length, (mid[1]) / self.length, (mid[2] - GROUND) / self.length)),
               'waist': mat_mul(pt, tag_mat(tag_ax))}
        for side in 'LR':
            hip = rbx(p[side + 'hip'])
            target = rbx(p[side + 'foot'])
            rel = sub(target, hip)
            # longer strides for the speed the cycle plays at (z is back in
            # character axes, so scale the forward component in body space)
            rel = mat_vec(pt, rel)
            rel = (rel[0], rel[1], rel[2] * stride)
            knee_hint = mat_vec(pt, sub(rbx(p[side + 'knee']), hip))
            toe = mat_vec(pt, rbx(sub(p[side + 'toe'], p[side + 'heel'])))
            # where the knee points: off the hip -> foot line when that agrees
            # with the foot (within 60 degrees), else where the toes point. A
            # near-straight md3 leg's knee wanders, and following it twisted
            # an R15 thigh sideways (sarge's idle right leg by 109 degrees).
            off = sub(knee_hint, mul(norm(rel), dot(knee_hint, norm(rel))))
            along = perp(toe, norm(rel))
            if length(along) < 1e-6:
                along = (0.0, 0.0, -1.0)
            front = norm(off) if length(off) > 0.5 and dot(norm(off), along) > 0.5 else along
            thigh, shin = two_bone(mul(rel, 1 / self.chain), self.split, 1 - self.split, front, (0, 0, -1))
            thigh_m = frame_for(thigh, perp(front, thigh))
            shin_m = frame_for(shin, perp(front, shin))
            foot_m = foot_frame(toe)
            name = 'Left' if side == 'L' else 'Right'
            out[name + 'UpperLeg'] = thigh_m
            out[name + 'LowerLeg'] = mat_mul(mat_t(thigh_m), shin_m)
            out[name + 'Foot'] = mat_mul(mat_t(shin_m), foot_m)
        return out

def frame_for(bone, front):
    """Segment frame: Y up the bone (towards its parent joint), -Z = front."""
    y = mul(norm(bone), -1)
    z = perp(mul(front, -1), y)
    if length(z) < 1e-6:
        z = perp((0, 0, 1), y)
    return mat_from_axes(cross(y, z), y, z)

def foot_frame(toe):
    fwd = norm(toe)
    z = mul(fwd, -1)
    y = perp((0, 1, 0), z)
    return mat_from_axes(cross(y, z), y, z)

def two_bone(rel, l1, l2, pole, fallback):
    """Directions of the two segments reaching rel (lengths in limb units)."""
    d = length(rel)
    dirv = norm(rel) if d > 1e-6 else (0, -1, 0)
    d = min(max(d, abs(l1 - l2) + 1e-4), (l1 + l2) * 0.9995)
    ca = (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)
    a = math.acos(max(-1, min(1, ca)))
    p = perp(pole, dirv)
    if length(p) < 1e-6:
        p = perp(fallback, dirv)
    joint = add(mul(dirv, l1 * math.cos(a)), mul(p, l1 * math.sin(a)))
    end = mul(dirv, d)
    return norm(joint), norm(sub(end, joint))

# torso ---------------------------------------------------------------------------
class Torso:
    def __init__(self, upper, stand):
        self.m = upper
        S = upper['verts'][stand]
        self.sets = {
            'L': [i for i, v in enumerate(S) if v[1] > 5 and v[2] > 12.5],
            'R': [i for i, v in enumerate(S) if v[1] < -4.5 and v[2] > 10],
        }
        st = upper['tags'][stand]
        self.spine0 = rbx(st['tag_head'][0])
        self.shoulders0 = self.shoulder_line(stand)
        self.head0 = tag_mat(st['tag_head'][1])
        # sarge's arm: the longest shoulder -> tag_weapon reach of any frame
        self.arm = max(length(sub(self.m['tags'][f]['tag_weapon'][0], centroid(self.m['verts'][f], self.sets['R'])))
                       for f in range(upper['frames']))
        self.stand = stand

    def shoulder_line(self, f):
        V = self.m['verts'][f]
        return rbx(sub(centroid(V, self.sets['R']), centroid(V, self.sets['L'])))

    def frame(self, f, left_mode):
        tg = self.m['tags'][f]
        V = self.m['verts'][f]
        spine = rbx(tg['tag_head'][0])
        swing = rot_between(self.spine0, spine)
        # twist about the spine so the shoulder line matches
        sw_r = perp(mat_vec(swing, self.shoulders0), norm(spine))
        now_r = perp(self.shoulder_line(f), norm(spine))
        ang = math.atan2(dot(cross(sw_r, now_r), norm(spine)), dot(sw_r, now_r))
        chest = mat_mul(axis_angle(norm(spine), ang), swing)
        ct = mat_t(chest)
        out = {'UpperTorso': chest,
               'Head': mat_mul(ct, mat_mul(tag_mat(tg['tag_head'][1]), mat_t(self.head0)))}
        sR = rbx(centroid(V, self.sets['R']))
        sL = rbx(centroid(V, self.sets['L']))
        wpos = rbx(tg['tag_weapon'][0])
        wrot = mat_mul(ct, tag_mat(tg['tag_weapon'][1]))
        targets = {'Right': mat_vec(ct, sub(wpos, sR))}
        if left_mode == 'mirror':
            # across the legs' middle plane, not the chest's: a body rolled on
            # its side would otherwise throw the other arm into the air
            r = sub(wpos, sR)
            targets['Left'] = mat_vec(ct, (-r[0], r[1], r[2]))
        else:
            # relaxed: hand at the hip, a little forward; guard: fist up in
            # front of the chest (gauntlet)
            # in front of the chest (gauntlet); both move with the chest
            hand = (7.0, 4.0, 9.0) if left_mode == 'guard' else (1.5, 8.5, 1.5)
            targets['Left'] = sub(rbx(hand), mat_vec(ct, sL))
        for side, sx in (('Right', 1), ('Left', -1)):
            rel = mul(targets[side], 1 / self.arm)
            pole = norm((0.15 * sx, -0.45, 1.0))  # elbow: back, down, a little out
            up_d, lo_d = two_bone(rel, ARM_SPLIT, 1 - ARM_SPLIT, pole, (0, 0, 1))
            up_m = frame_for(up_d, mul(perp(pole, up_d), -1))
            lo_m = frame_for(lo_d, mul(perp(pole, lo_d), -1))
            hand_m = wrot if side == 'Right' else lo_m
            out[side + 'UpperArm'] = up_m
            out[side + 'LowerArm'] = mat_mul(mat_t(up_m), lo_m)
            out[side + 'Hand'] = mat_mul(mat_t(lo_m), hand_m)
        return out

LEFT_MODE = {'TORSO_STAND2': 'guard', 'TORSO_ATTACK2': 'guard'}

# output --------------------------------------------------------------------------
def q4(m):
    return '{%s}' % ', '.join('%.4f' % c for c in quat(m))

def v3(v):
    return '{%s}' % ', '.join('%.4f' % c for c in v)

HEADER = '''--[[
Copyright (C) 2026 openarena-rbx contributors

This file is part of openarena-rbx, a port of OpenArena to Roblox.

openarena-rbx is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version. See COPYING.
]]
-- Generated by tools/gen_avatar_anims.py from OpenArena 0.8.8's sarge
-- (animation.cfg, lower.md3, upper.md3). Do not edit: re-run the script.
'''

def emit(cfg, legs, torso, stats):
    files = {}
    skip = cfg['LEGS_WALKCR'][0] - cfg['TORSO_GESTURE'][0]
    lines = [HEADER, '-- %s' % stats['summary'], 'return {']
    lines.append('\tlegLength = %.4f, -- hip to sole, straight, in OA units' % legs.length)
    lines.append('\tanims = {')
    for name in NAMES:
        if name.startswith('TORSO_'):
            continue
        first, num, loop, fps = cfg[name]
        base = first - skip if name.startswith('LEGS_') else first
        stride = 1.0
        if name in STRIDE_SPEED:
            stride = stats['stride'][name]
        lines.append('\t\t%s = { first = %d, num = %d, loop = %d, fps = %g, frames = {' % (name, first, num, loop, fps))
        for k in range(num):
            fr = legs.frame(base + k, stride)
            parts = ['pos = %s' % v3(fr['pos']), 'pelvis = %s' % q4(fr['pelvis']), 'waist = %s' % q4(fr['waist'])]
            if not name.startswith('BOTH_'):
                # deaths lie on whatever part is lowest, so they have no foot clearance
                parts.append('clear = %.4f' % fr['clear'])
            for j in ('LeftUpperLeg', 'LeftLowerLeg', 'LeftFoot', 'RightUpperLeg', 'RightLowerLeg', 'RightFoot'):
                parts.append('%s = %s' % (j, q4(fr[j])))
            lines.append('\t\t\t{ %s },' % ', '.join(parts))
        lines.append('\t\t} },')
    lines.append('\t},')
    lines.append('}')
    files['Legs.luau'] = '\n'.join(lines) + '\n'

    lines = [HEADER, 'return {', '\tanims = {']
    for name in NAMES:
        if name.startswith('LEGS_'):
            continue
        first, num, loop, fps = cfg[name]
        mode = LEFT_MODE.get(name, 'mirror' if name.startswith('BOTH_') else 'relaxed')
        lines.append('\t\t%s = { first = %d, num = %d, loop = %d, fps = %g, frames = {' % (name, first, num, loop, fps))
        for k in range(num):
            fr = torso.frame(first + k, mode)
            parts = ['%s = %s' % (j, q4(fr[j])) for j in ('UpperTorso', 'Head', 'RightUpperArm', 'RightLowerArm', 'RightHand',
                                                          'LeftUpperArm', 'LeftLowerArm', 'LeftHand')]
            lines.append('\t\t\t{ %s },' % ', '.join(parts))
        lines.append('\t\t} },')
    lines.append('\t},')
    lines.append('}')
    files['Torso.luau'] = '\n'.join(lines) + '\n'
    return files

def stance_speed(legs, base, num, fps):
    """Mean speed (u/s) of a planted foot against the hips, in the cycle."""
    speeds = []
    for side in 'LR':
        pts = [legs.points(base + k) for k in range(num)]
        low = min(p[side + 'foot'][2] for p in pts)
        for k in range(num):
            a, b = pts[k], pts[(k + 1) % num]
            if a[side + 'foot'][2] < low + 1.0 and b[side + 'foot'][2] < low + 1.0:
                ra = a[side + 'foot'][0] - (a['Lhip'][0] + a['Rhip'][0]) / 2
                rb = b[side + 'foot'][0] - (b['Lhip'][0] + b['Rhip'][0]) / 2
                speeds.append(abs(rb - ra) * fps)
    return sum(speeds) / len(speeds) if speeds else 0.0

def main():
    cfg = parse_cfg(pk3_file(MODEL + 'animation.cfg').decode('latin-1'))
    lower = md3(pk3_file(MODEL + 'lower.md3'))
    upper = md3(pk3_file(MODEL + 'upper.md3'))
    head = md3(pk3_file(MODEL + 'head.md3'))
    skip = cfg['LEGS_WALKCR'][0] - cfg['TORSO_GESTURE'][0]
    idle = cfg['LEGS_IDLE'][0] - skip
    stand = cfg['TORSO_STAND'][0]
    legs = Legs(lower, idle)
    torso = Torso(upper, stand)

    # the model's standing height: idle legs, standing torso, head on its tag
    t_o, t_ax = lower['tags'][idle]['tag_torso']
    h_o, h_ax = upper['tags'][stand]['tag_head']
    def place(o, ax, v):  # tag frame -> parent: o + v . rows(ax)
        return add(o, add(add(mul(ax[0:3], v[0]), mul(ax[3:6], v[1])), mul(ax[6:9], v[2])))
    top = max(place(t_o, t_ax, place(h_o, h_ax, v))[2] for v in head['verts'][0])
    height = top - GROUND

    stats = {'stride': {}}
    report = []
    for name, speed in STRIDE_SPEED.items():
        first, num, loop, fps = cfg[name]
        measured = stance_speed(legs, first - skip, num, fps)
        k = min(1.5, max(1.0, speed / measured)) if measured > 0 else 1.0
        stats['stride'][name] = k
        report.append('%s %.0f u/s planted, x%.2f for %d' % (name, measured, k, speed))
    summary = 'sarge: height %.2f u, leg %.2f u, arm %.2f u; %s' % (height, legs.length, torso.arm, '; '.join(report))
    print(summary)
    stats['summary'] = summary
    files = emit(cfg, legs, torso, stats)
    files['Legs.luau'] = files['Legs.luau'].replace("return {\n", "return {\n\theight = %.4f, -- idle legs + stand torso + head, sole to crown, OA units\n" % height, 1)

    check = '--check' in sys.argv
    os.makedirs(OUT, exist_ok=True)
    bad = False
    for name, text in files.items():
        path = os.path.join(OUT, name)
        if check:
            old = open(path).read() if os.path.exists(path) else ''
            if old != text:
                print('differs: ' + path)
                bad = True
        else:
            with open(path, 'w') as f:
                f.write(text)
            print('wrote ' + os.path.relpath(path, ROOT))
    sys.exit(1 if bad else 0)

if __name__ == '__main__':
    main()
