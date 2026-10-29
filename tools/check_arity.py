#!/usr/bin/env python3
"""Cross-file call arity check for the ported game module.

Every G.Name(...) call is compared with the parameter list of its
`function G.Name(...)` definition. Calls with MORE arguments than the
definition takes are errors: they are almost always a C out-parameter
that one file kept and another turned into a return value. Calls with
fewer are listed with --all (optional trailing parameters are common).

    python3 tools/check_arity.py [--all]
"""
import re,glob,sys
src={}
for p in glob.glob('src/server/**/*.luau',recursive=True)+glob.glob('src/shared/**/*.luau',recursive=True):
    src[p]=open(p).read()
defs={}
for p,s in src.items():
    for m in re.finditer(r'\nfunction G\.(\w+)\(([^)]*)\)',s):
        ps=[x.strip() for x in m.group(2).split(',') if x.strip()]
        ps=[re.sub(r':.*','',x) for x in ps]
        defs[m.group(1)]=(ps,p)
def split_args(s,i):
    # s[i] is '(' ; return list of args and end index
    depth=0;args=[];cur='';j=i
    instr=None
    while j<len(s):
        c=s[j]
        if instr:
            cur+=c
            if c=='\\': cur+=s[j+1]; j+=2; continue
            if c==instr: instr=None
        elif c in '"\'':
            instr=c;cur+=c
        elif c in '([{':
            depth+=1
            if depth>1: cur+=c
        elif c in ')]}':
            depth-=1
            if depth==0:
                if cur.strip(): args.append(cur)
                return args,j
            cur+=c
        elif c==',' and depth==1:
            args.append(cur);cur=''
        else: cur+=c
        j+=1
    return args,j
out=[]
for p,s in src.items():
    code=re.sub(r'--\[\[.*?\]\]','',s,flags=re.S)
    code=re.sub(r'--[^\n]*','',code)
    for m in re.finditer(r'G\.(\w+)\(',code):
        name=m.group(1)
        if name not in defs: continue
        if code[max(0,m.start()-9):m.start()]=='function ': continue
        args,_=split_args(code,m.end()-1)
        ps,dp=defs[name]
        if '...' in ps: continue
        last=args[-1].strip() if args else ''
        if args and (last=='...' or re.search(r'\)\s*$',last) and False): continue
        if len(args)!=len(ps):
            line=code[:m.start()].count('\n')+1
            kind='(more)' if len(args)>len(ps) else '(fewer)'
            out.append(f"{p}:~{line}: {kind} G.{name} called with {len(args)} args, defined with {len(ps)} ({', '.join(ps)}) in {dp}")
for o in sorted(out):
    if ' (more) ' in o or '--all' in sys.argv:
        print(o)
errors = sum(1 for o in out if ' (more) ' in o)
print(f"check_arity: {errors} call(s) with too many arguments")
sys.exit(1 if errors else 0)
