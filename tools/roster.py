#!/usr/bin/env python3
"""The player roster the Roblox port ships (tools/oaconv/roster.json), applied
to the game's data: the client/server file pack (place/assemble.py,
scripts/client-dev-assets.py), the botfiles blob (tools/pack-botfiles.py) and
the lune test hosts.

- every path of an excluded model or skin is left out, with the same rules as
  oaconv's src/roster.rs;
- shipped .skin files name the kept texture (retexture) in place of a dropped
  one;
- toned paths ship only from assets/toned (oaconv's overlay), never from the
  pk3s;
- scripts/bots.txt moves the bots in bot_models to their kept model and loses
  the other bots whose model is excluded, and botfiles/ the character files
  only they use, so `addbot <name>` finds no such bot; bots changes or adds
  blocks, and assets/botfiles replaces or adds files under botfiles/;
- scripts/arenas.txt and *.arena name the roster's substitute (arena_bots)
  for every dropped bot.

  tools/roster.py files PREFIX...   the shipped text files under PREFIX, as JSON
  tools/roster.py check             validate roster.json against the pk3s and src/,
                                    and the bot chat (tools/check_botchat.py)
"""
import json
import os
import re
import sys
import zipfile
from functools import lru_cache

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, 'tools/oaconv/roster.json')
BASEOA = os.path.join(ROOT, 'vendor/oa088/openarena-0.8.8/baseoa')
TONED = os.path.join(ROOT, 'assets/toned')
BOTFILES = os.path.join(ROOT, 'assets/botfiles')
SKIP_PAKS = {'pak2-players-mature.pk3'}
TEXT_EXT = {'.cfg', '.skin', '.shader', '.arena', '.txt', '.menu'}


@lru_cache(None)
def config():
    with open(CONFIG) as f:
        return json.load(f)


def excludes(path):
    """Whether a pk3 path belongs to an excluded model or skin (src/roster.rs)."""
    p = path.lower()
    cfg = config()
    for key in cfg['excluded']:
        if '/' in key:
            model, skin = key.split('/', 1)
            d = 'models/players/%s/' % model
            if p.startswith(d):
                f = p[len(d):]
                if f in ('head_%s.skin' % skin, 'upper_%s.skin' % skin, 'lower_%s.skin' % skin) or \
                        f.startswith(('icon_%s.' % skin, 'iconh_%s.' % skin)):
                    return True
            if p.startswith(tuple(x.lower() for x in cfg.get('files', {}).get(key, []))):
                return True
        elif p.startswith(('models/players/%s/' % key, 'models/players/heads/%s/' % key, 'sound/player/%s/' % key)) \
                or p in ('scripts/%s.vc' % key, 'scripts/player_%s.shader' % key):
            return True
    return False


def toned_only(path):
    """Whether a path ships only from assets/toned (src/roster.rs)."""
    return path.lower().startswith(tuple(t.lower() for t in config().get('toned', {})))


def bot_blocks(text):
    """scripts/bots.txt as [(segment text, {key: value})]: each segment runs
    from the end of the previous block (its comments included) to its '}'."""
    out, pos = [], 0
    for m in re.finditer(r'\{(.*?)\}', text, re.S):
        info = {}
        for line in m.group(1).splitlines():
            t = line.split(None, 1)
            if len(t) == 2:
                info[t[0].lower()] = t[1].strip().strip('"')
        out.append((text[pos:m.end()], info))
        pos = m.end()
    out.append((text[pos:], None))
    return out


def model_excluded(model):
    model = model.lower()
    cfg = config()
    return model.split('/')[0] not in cfg['kept'] or model in cfg['excluded']


def bot_excluded(info):
    return info['name'].lower() not in config().get('bot_models', {}) and \
        any(model_excluded(info[k]) for k in ('model', 'headmodel') if info.get(k))


def move_bot(seg, info):
    """A bot block with its model swapped for its bot_models entry, if any."""
    model = config().get('bot_models', {}).get(info['name'].lower())
    if model is None:
        return seg
    return re.sub(r'(?im)^(\s*model\s+)"?[^"\s]*"?', lambda m: m.group(1) + model, seg, count=1)


def set_bot_fields(seg, fields):
    for k, v in fields.items():
        line = '%s\t\t%s' % (k, v)
        seg, n = re.subn(r'(?im)^\s*%s\s+.*$' % re.escape(k), lambda m: line, seg, count=1)
        if n == 0:
            seg = seg[:seg.rindex('}')] + line + '\n}'
    return seg


def filter_bots(text):
    """bots.txt as shipped: dropped bots out, bot_models moved, bots applied."""
    changes = {k.lower(): {f: v for f, v in b.items() if f != 'why'} for k, b in config().get('bots', {}).items()}
    out = []
    for seg, info in bot_blocks(text):
        if info is not None and not bot_excluded(info):
            seg = set_bot_fields(move_bot(seg, info), changes.pop(info['name'].lower(), {}))
        if info is None or not bot_excluded(info):
            out.append(seg)
    for fields in changes.values():
        out.append(set_bot_fields('\n// openarena-rbx (tools/oaconv/roster.json, bots)\n{\n}', fields) + '\n')
    return ''.join(out)


def retexture(text):
    """A .skin file with dropped texture prefixes swapped for kept ones (src/roster.rs)."""
    for old, new in config().get('retexture', {}).items():
        text = re.sub(r'(?im)(,\s*)' + re.escape(old), lambda m: m.group(1) + new, text)
    return text


def excluded_bots(bots_text):
    return {info['name'].lower() for _, info in bot_blocks(bots_text) if info and bot_excluded(info)}


def substitute_arena_bots(text, dropped):
    subs = {k.lower(): v for k, v in config()['arena_bots'].items()}

    def repl(m):
        names = []
        for n in m.group(2).split():
            if n.lower() in dropped:
                if n.lower() not in subs:
                    raise ValueError('arena bot %s is dropped and roster.json has no arena_bots entry' % n)
                n = subs[n.lower()].lower()
            names.append(n)
        return m.group(1) + ' '.join(names) + m.group(3)
    return re.sub(r'(?im)^(\s*bots\s+")([^"]*)(")', repl, text)


def pk3_owner(baseoa=BASEOA):
    """{lower path: (pk3, name)} in search order, mature pk3 skipped, before the roster."""
    paks = sorted(p for p in os.listdir(baseoa) if p.endswith('.pk3') and p not in SKIP_PAKS)
    owner = {}
    for p in paks:
        with zipfile.ZipFile(os.path.join(baseoa, p)) as z:
            for n in z.namelist():
                if not n.endswith('/'):
                    owner[n.lower()] = (p, n)
    return owner


class Shipped:
    """The pk3 search path as the Roblox game ships it."""

    def __init__(self, baseoa=BASEOA):
        self.baseoa = baseoa
        self.zips = {}
        everything = pk3_owner(baseoa)
        self.bots_txt = (self._read(everything, 'scripts/bots.txt') or b'').decode('latin-1')
        self.dropped_bots = excluded_bots(self.bots_txt)
        blocks = [i for _, i in bot_blocks(self.bots_txt) if i]

        def stems(bots):
            return {os.path.basename(i.get('aifile', '')).lower().rsplit('_', 1)[0]
                    for i in blocks if i['name'].lower() in bots}
        self.shipped_bots = [i for _, i in bot_blocks(filter_bots(self.bots_txt)) if i]
        kept_stems = {os.path.basename(i.get('aifile', '')).lower().rsplit('_', 1)[0] for i in self.shipped_bots}
        # character files only dropped bots use (and Jenna's, which no bot uses)
        drop_stems = (stems(self.dropped_bots) | self.dropped_bots) - kept_stems
        self.owner = {low: v for low, v in everything.items() if not excludes(low) and not toned_only(low) and not (
            low.startswith('botfiles/bots/') and os.path.basename(low).rsplit('_', 1)[0] in drop_stems)}

    def _read(self, owner, low):
        if low not in owner:
            return None
        p, n = owner[low]
        if p not in self.zips:
            self.zips[p] = zipfile.ZipFile(os.path.join(self.baseoa, p))
        return self.zips[p].read(n)

    def read(self, low):
        """A shipped file's bytes, with bots.txt and arenas rewritten; None if not shipped."""
        data = self._read(self.owner, low)
        if data is None:
            return None
        if low == 'scripts/bots.txt':
            return filter_bots(data.decode('latin-1')).encode('latin-1')
        if low == 'scripts/arenas.txt' or low.endswith('.arena'):
            return substitute_arena_bots(data.decode('latin-1'), self.dropped_bots).encode('latin-1')
        if low.endswith('.skin'):
            return retexture(data.decode('latin-1')).encode('latin-1')
        return data

    def botfiles(self):
        """{path: bytes} of every shipped file under botfiles/, the overlay
        (assets/botfiles) over the pk3s."""
        out = {n: self._read(self.owner, low) for low, (_, n) in self.owner.items() if low.startswith('botfiles/')}
        for d, _, fs in os.walk(BOTFILES):
            for f in fs:
                rel = 'botfiles/' + os.path.relpath(os.path.join(d, f), BOTFILES).replace(os.sep, '/')
                out = {k: v for k, v in out.items() if k.lower() != rel.lower()}
                with open(os.path.join(d, f), 'rb') as fh:
                    out[rel] = fh.read()
        return out

    def text_files(self, prefixes=None):
        """The text files the game reads (the client/server FS pack), or
        those under `prefixes`."""
        def wanted(low):
            if prefixes:
                return low.startswith(prefixes)
            return low.startswith(('scripts/', 'models/', 'botfiles/', 'ui/')) or low.endswith('.cfg')
        out = {}
        for low in self.owner:
            if os.path.splitext(low)[1] in TEXT_EXT and wanted(low):
                out[low] = self.read(low).decode('latin-1')
        return out


# the characteristics that make a bot stronger the higher they are (lower,
# for the reaction time); the rest are personality
STRENGTH = re.compile(r'^(ATTACK_SKILL|AIM_SKILL|AIM_ACCURACY|VIEW_FACTOR|VIEW_MAXCHANGE|REACTIONTIME|ALERTNESS|'
                      r'AIM_ACCURACY_\w+|AIM_SKILL_\w+)$')


def character(text):
    """{skill: {characteristic: value}} of a botfiles character's numbers."""
    return {m.group(1): {k: float(v) for k, v in re.findall(r'CHARACTERISTIC_(\w+)\s+(\d+(?:\.\d+)?)\s*$',
                                                            m.group(2), re.M) if STRENGTH.match(k)}
            for m in re.finditer(r'skill\s+(\d)\s*\{(.*?)\}', text, re.S)}


def strength_problems(bots, botfiles):
    """strongest[0] at or above every other bot at every skill level and
    characteristic, strongest[1] at or above every other but below
    strongest[0] somewhere (ties only where a value is at its cap)."""
    order = [n.lower() for n in config().get('strongest', [])]
    chars = {}
    for i in bots:
        data = botfiles.get('botfiles/' + i.get('aifile', '').lower())
        if data:
            chars[i['name'].lower()] = character(data.decode('latin-1'))
    problems = []
    for rank, name in enumerate(order):
        if name not in chars:
            return ['strongest: %s is not a shipped bot' % name]
        others = [b for b in chars if b not in order[:rank + 1]]
        for skill, values in chars[name].items():
            for k, v in values.items():
                better = (lambda a, b: a <= b) if k == 'REACTIONTIME' else (lambda a, b: a >= b)
                worse = [b for b in others if k in chars[b].get(skill, {}) and not better(v, chars[b][skill][k])]
                if worse:
                    problems.append('strongest: %s skill %s %s %g is below %s' % (name, skill, k, v, ', '.join(worse)))
    if len(order) == 2 and order[0] in chars and order[1] in chars and chars[order[0]] == chars[order[1]]:
        problems.append('strongest: %s is no stronger than %s' % tuple(order))
    return problems


def check():
    """roster.json is consistent with the pk3s and src/ hardcodes no dropped bot or model."""
    cfg, s = config(), Shipped()
    problems = []
    every = pk3_owner()
    dirs = {low.split('/')[2] for low in every if low.startswith('models/players/') and low.count('/') > 2}
    for d in sorted(dirs - {'heads'}):
        if d not in cfg['kept'] and d not in cfg['excluded']:
            files = [low for low in every if low.startswith('models/players/%s/' % d)]
            problems.append('models/players/%s (%d files) is neither kept nor excluded' % (d, len(files)))
    for low in every:
        if low.startswith('models/players/') and low.count('/') > 2 and low.split('/')[2] != 'heads' \
                and model_excluded(low.split('/')[2]) and low in s.owner:
            problems.append('%s ships' % low)
    kept_bots = {i['name'].lower() for i in s.shipped_bots}
    botfiles = {k.lower(): v for k, v in s.botfiles().items()}
    for i in s.shipped_bots:
        if 'botfiles/' + i.get('aifile', '').lower() not in botfiles:
            problems.append('bot %s: no character file %s' % (i['name'], i.get('aifile')))
    problems += strength_problems(s.shipped_bots, botfiles)
    for _, i in bot_blocks(s.read('scripts/bots.txt').decode('latin-1')):
        if i and any(model_excluded(i[k]) for k in ('model', 'headmodel') if i.get(k)):
            problems.append('bot %s wears dropped model %s' % (i['name'], i.get('model')))
    for low in s.owner:
        if low.endswith('.skin'):
            for line in s.read(low).decode('latin-1').splitlines():
                tex = line.split(',', 1)[1].strip() if ',' in line else ''
                if tex and excludes(tex):
                    problems.append('%s names dropped texture %s' % (low, tex))
                elif tex and toned_only(tex) and not os.path.isfile(os.path.join(TONED, tex.lower())):
                    problems.append('%s names %s, which ships only toned and assets/toned has no copy' % (low, tex))
    for low in every:
        if toned_only(low) and not os.path.isfile(os.path.join(TONED, low)):
            problems.append('%s is toned-only but assets/toned has no copy' % low)
    for bot, sub in cfg['arena_bots'].items():
        if sub.lower() not in kept_bots:
            problems.append('arena_bots %s -> %s: not a kept bot' % (bot, sub))
    for low in s.owner:
        if low == 'scripts/arenas.txt' or low.endswith('.arena'):
            for m in re.finditer(r'(?im)^\s*bots\s+"([^"]*)"', s.read(low).decode('latin-1')):
                bad = [n for n in m.group(1).split() if n.lower() in s.dropped_bots]
                if bad:
                    problems.append('%s still names %s' % (low, bad))
    names = s.dropped_bots | {k.split('/')[-1] for k in cfg['excluded']}
    pat = re.compile(r'"(%s)"' % '|'.join(sorted(map(re.escape, names))), re.I)
    for d, _, fs in os.walk(os.path.join(ROOT, 'src')):
        for f in fs:
            path = os.path.join(d, f)
            for i, line in enumerate(open(path, encoding='utf-8', errors='replace'), 1):
                if pat.search(line):
                    problems.append('%s:%d names a dropped bot or model: %s' % (os.path.relpath(path, ROOT), i,
                                                                               line.strip()))
    for p in problems:
        print(p)
    import check_botchat  # it imports this module
    chat_ok = check_botchat.check()
    print('roster: %d kept bots, %d dropped (%s), %d problem(s)' % (
        len(kept_bots), len(s.dropped_bots), ' '.join(sorted(s.dropped_bots)), len(problems)))
    return not problems and chat_ok


def main():
    if sys.argv[1:2] == ['files']:
        s = Shipped()
        prefixes = tuple(a.lower() for a in sys.argv[2:])
        json.dump(s.text_files(prefixes), sys.stdout)
    elif sys.argv[1:2] == ['check']:
        sys.exit(0 if check() else 1)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
