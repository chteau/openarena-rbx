#!/usr/bin/env python3
"""Checks every line a bot can say against the term list in
tools/botchat_terms.txt. Bot chat is fixed text from botfiles/ (shown to
every player without Roblox's text filter), so it has to pass on its own.

Reads the botfiles as tools/pack-botfiles.py packs them (the pk3s with
the assets/botfiles overlay, tools/roster.py), then:
- parses the character chat files (bots/*_t.c with teamplay.h), rnd.c,
  rchat.c, syn.c and match.c the way botlib's precompiler does (#include,
  #define; a number in a message is a match variable, a name a random
  string from rnd.c);
- assembles each message from its fragments, expanding the random strings
  (every choice of every slot appears in at least one assembled line);
- adds the synonyms botlib may swap in (syn.c), match.c's templates
  (they only read other players' chat: checked for slurs and hate) and
  the English string literals the bot code in src/server/bot says itself;
- flags any line holding a listed term, and any structural problem: an
  empty chat type (in a chat file a shipped character uses) or random
  string, an unknown random string, or a chat
  type the vendor file has that the shipped one lost.

The term list is ROT13 so the repo holds no plain slur list. One term per
line, "category<TAB>rot13 term". A term is one or more words; a "*" at
either end of a word matches any prefix/suffix ("frag*"). Matching is on
lowercased words with common digit/symbol swaps undone (0->o, 1->i, 3->e,
4->a, 5->s, @->a, $->s). Add a term with
    tools/check_botchat.py add <category> "<term>"
which encodes it. Categories: slur, hate, sexual, drugs, profanity, harm,
gore, sensitive (politics, religion, real people). A list misses
innuendo: read new or changed lines too.

Usage:
  tools/check_botchat.py            check; exit 1 on any problem
  tools/check_botchat.py dump       print every assembled line (for review)
  tools/check_botchat.py add CAT T  add a term
"""
import codecs
import itertools
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import roster  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
TERMS = Path(__file__).resolve().parent / 'botchat_terms.txt'
FULL = 2000  # assemble every combination up to this many per message

TOKEN = re.compile(r'\s+|//[^\n]*|/\*.*?\*/|"((?:\\.|[^"\\])*)"|(#\w+)|(\$?[A-Za-z_]\w*)|(\d+(?:\.\d+)?)|(\S)', re.S)
LEET = str.maketrans('013457@$', 'oieastas')


def tokens(files, name, defines, seen=()):
    """botlib's precompiler, as far as botfiles use it: [(kind, value, where)]."""
    text = files[name].decode('latin-1')
    out, pos, line = [], 0, 1
    while pos < len(text):
        m = TOKEN.match(text, pos)
        where = '%s:%d' % (name, line)
        line += m.group(0).count('\n')
        pos = m.end()
        s, d, n, num, p = m.groups()
        if d == '#include':
            m = TOKEN.match(text, pos)
            while m.group(1) is None:
                pos = m.end()
                m = TOKEN.match(text, pos)
            pos = m.end()
            inc = next(c for c in (os.path.dirname(name) + '/' + m.group(1), 'botfiles/' + m.group(1)) if c in files)
            if inc not in seen:
                out += tokens(files, inc, defines, seen + (inc,))
        elif d == '#define':
            end = text.find('\n', pos)
            body = re.sub(r'//.*', '', text[pos:end]).split(None, 1)
            defines[body[0]] = body[1].strip() if len(body) > 1 else ''
            pos = end
        elif d:
            pos = text.find('\n', pos)
        elif s is not None:
            s = bytes(s, 'latin-1').decode('unicode_escape', 'replace')
            if out and out[-1][0] == 'str':  # strings behind each other are joined
                out[-1] = ('str', out[-1][1] + s, out[-1][2])
            else:
                out.append(('str', s, where))
        elif n:
            v = defines.get(n)
            out.append(('num', v, where) if v and v.isdigit() else ('name', n, where))
        elif num:
            out.append(('num', num, where))
        elif p:
            out.append(('p', p, where))
    return out


class Stream:
    def __init__(self, toks):
        self.t, self.i = toks, 0

    def more(self):
        return self.i < len(self.t)

    def peek(self):
        return self.t[self.i][1] if self.more() else None

    def next(self):
        self.i += 1
        return self.t[self.i - 1]

    def expect(self, v):
        tok = self.next()
        if tok[1] != v:
            raise SyntaxError('%s: expected %r, got %r' % (tok[2], v, tok[1]))

    def messages(self):
        """'{' message; ... '}' -> [(where, [(kind, value)])]"""
        self.expect('{')
        out = []
        while self.peek() != '}':
            parts, where = [], self.t[self.i][2]
            while True:
                kind, v, w = self.next()
                if kind == 'p':
                    raise SyntaxError('%s: unexpected %r' % (w, v))
                parts.append((kind, v))
                if self.next()[1] == ';':
                    break
            out.append((where, parts))
        self.next()
        return out


def chat_file(files, name):
    """{chatname: {type: [message]}}"""
    st, chats = Stream(tokens(files, name, {})), {}
    while st.more():
        st.expect('chat')
        types = chats.setdefault(st.next()[1], {})
        st.expect('{')
        while st.peek() != '}':
            st.expect('type')
            t = st.next()[1]
            types[t] = st.messages()
        st.next()
    return chats


def random_strings(files):
    st, out = Stream(tokens(files, 'botfiles/rnd.c', {})), {}
    while st.more():
        name = st.next()[1]
        st.expect('=')
        out[name] = st.messages()
    return out


def reply_chats(files):
    st, out = Stream(tokens(files, 'botfiles/rchat.c', {})), []
    while st.more():
        while st.peek() != '{':
            st.next()
        out += st.messages()
    return out


def strings(files, name):
    """Every string literal of a file (syn.c's synonyms, match.c's templates)."""
    return [(w, v) for kind, v, w in tokens(files, name, {}) if kind == 'str']


def code_strings():
    """English text the bot code says without a botfile."""
    out = []
    for d, _, fs in os.walk(ROOT / 'src/server/bot'):
        for f in fs:
            if f.startswith('ai_') and f.endswith('.luau'):
                path = os.path.join(d, f)
                for i, line in enumerate(open(path, encoding='utf-8'), 1):
                    for s in re.findall(r'"([^"]* [^"]*)"', line):
                        out.append(('%s:%d' % (os.path.relpath(path, ROOT), i), s))
    return out


class Assembler:
    def __init__(self, rnd):
        self.rnd, self.cache, self.problems = rnd, {}, []

    def choices(self, name, where):
        if name not in self.cache:
            if name not in self.rnd:
                self.problems.append('%s: unknown random string %s' % (where, name))
                return ['{%s}' % name]
            self.cache[name] = ['{%s}' % name]  # a loop expands to its own name
            self.cache[name] = [s for w, m in self.rnd[name] for s in self.lines(m, w)]
        return self.cache[name]

    def lines(self, msg, where):
        slots = [[v] if k == 'str' else ['{v%s}' % v] if k == 'num' else self.choices(v, where) for k, v in msg]
        total = 1
        for s in slots:
            total *= len(s)
        if total <= FULL:
            return [''.join(c) for c in itertools.product(*slots)]
        return [''.join(s[i % len(s)] for s in slots) for i in range(max(map(len, slots)))]


def load_terms():
    out = []
    for line in TERMS.read_text().splitlines():
        if line.strip() and not line.startswith('#'):
            cat, term = line.split('\t', 1)
            words = codecs.decode(term, 'rot13').lower().split()
            out.append((cat, words, re.compile(r'\s'.join(
                ('' if w.startswith('*') else r'\b') + re.escape(w.strip('*')) + ('' if w.endswith('*') else r'\b')
                for w in words))))
    return out


def flags(text, terms):
    norm = ' '.join(re.findall(r"[a-z]+", text.lower().translate(LEET)))
    return sorted({cat for cat, _, rx in terms if rx.search(norm)})


def corpus(files=None):
    """(lines, problems): lines are (where, text) for everything a bot can say."""
    files = files or roster.Shipped().botfiles()
    files = {k.replace('\\', '/'): v for k, v in files.items()}
    lower = {k.lower(): k for k in files}
    rnd = random_strings(files)
    asm = Assembler(rnd)
    problems, lines = asm.problems, []
    vendor = roster.Shipped()
    used = {'botfiles/' + m.decode().lower() for k, v in files.items() if k.lower().endswith('_c.c')
            for m in re.findall(rb'CHARACTERISTIC_CHAT_FILE\s+"([^"]+)"', v)}
    for name in sorted(files):
        if not re.match(r'botfiles/bots/\w+_t\.c$', name, re.I):
            continue
        orig = vendor._read(vendor.owner, name.lower())
        orig_types = {t for c in chat_file({**files, name: orig}, name).values() for t in c} if orig else set()
        chats = chat_file(files, name)
        types = {t for c in chats.values() for t in c}
        for t in sorted(orig_types - types):
            problems.append('%s: chat type %s is gone' % (name, t))
        for c in chats.values():
            for t, msgs in c.items():
                if not msgs and name.lower() in used:
                    problems.append('%s: chat type %s is empty' % (name, t))
                for w, m in msgs:
                    lines += [(w, s) for s in asm.lines(m, w)]
    for name, msgs in rnd.items():
        if not msgs:
            problems.append('botfiles/rnd.c: random string %s is empty' % name)
        for w, m in msgs:
            asm.lines(m, w)  # unused ones too
    lines += [(w, s) for w, m in reply_chats(files) for s in asm.lines(m, w)]
    for f in ('botfiles/syn.c', 'botfiles/match.c'):
        lines += strings(files, lower[f])
    lines += code_strings()
    return sorted(set(lines)), problems


def check():
    try:
        lines, problems = corpus()
    except SyntaxError as e:
        print('botchat: %s' % e)
        return False
    terms = load_terms()
    # match.c's templates read other players' chat, bots never say them
    bad = [(w, s, f) for w, s in lines
           if (f := [c for c in flags(s, terms) if c in ('slur', 'hate') or not w.startswith('botfiles/match.c')])]
    for w, s, f in bad:
        print('%s: [%s] %s' % (w, ','.join(f), s))
    for p in problems:
        print(p)
    print('botchat: %d lines checked, %d flagged, %d problem(s)' % (len(lines), len(bad), len(problems)))
    return not bad and not problems


def main():
    if sys.argv[1:2] == ['add'] and len(sys.argv) == 4:
        with open(TERMS, 'a') as f:
            f.write('%s\t%s\n' % (sys.argv[2], codecs.encode(sys.argv[3].lower(), 'rot13')))
    elif sys.argv[1:2] == ['dump']:
        for w, s in corpus()[0]:
            print('%s\t%s' % (w, s))
    elif len(sys.argv) == 1:
        sys.exit(0 if check() else 1)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
