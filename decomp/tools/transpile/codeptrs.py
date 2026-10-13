# code addresses used as values (callbacks, _jt targets) that are not yet function starts
import os, sys
# work directory layout (see run.sh): ghidra/{funcs.txt,funcs.json,out/,icall_overrides.txt}, ext/arm9.bin
os.chdir(os.environ.get("TRANSPILE_WORK", "."))
sys.path.insert(0, os.environ.get("CAPSTONE_PY", "/home/claude/tools/cs/bindings/python"))

import json, re, struct, sys
from capstone import *
idx = json.load(open('ghidra/funcs.json'))
have = set(int(k, 16) for k in idx)
known = set(int(x, 16) for x in open('ghidra/funcs.txt').read().split())
gd = open(os.environ.get('GD_OUT', 'repo/GodotGame/new-game-project/scripts/gen/ds_game.gd')).read()
b = open('ext/arm9.bin', 'rb').read()
md = Cs(CS_ARCH_ARM, CS_MODE_ARM)
cands = set()
# addresses the code reads or writes as data are not functions
data = set(int(m.group(1), 16) for m in re.finditer(r'0x(20[0-9A-B][0-9A-F]{4})\b\s*(?:\+\s*\(?[^)]*\)?\s*)?-\s*0x2000000', gd))
for m in re.finditer(r'0x(20[0-9A-B][0-9A-F]{4})\b(?!\s*-\s*0x2000000)(?!\s*\+)', gd):
    a = int(m.group(1), 16)
    if a % 4 or a >= 0x20b6268 or a in have or a in known or a in data:
        continue
    ctx = gd[max(0, m.start() - 12):m.start()]
    if 'decode' in ctx:
        continue
    ins = list(md.disasm(b[a - 0x2000000:a - 0x2000000 + 4], a))
    prevs = [list(md.disasm(b[a - 0x2000000 - 4 * k:a - 0x2000000 - 4 * k + 4], a - 4 * k)) for k in range(1, 5)]
    ret = any(p and (p[0].mnemonic == 'bx' and p[0].op_str == 'lr' or (p[0].mnemonic in ('pop', 'ldm') and 'pc' in p[0].op_str)) for p in prevs)
    if ins and (ins[0].mnemonic in ('push', 'stmdb') or ret):
        cands.add(a)
        continue
    # a leaf function after a literal pool (e.g. an interrupt handler passed to OS_SetIrqFunction): the value
    # is a call argument and the code from there decodes to a return within a few instructions
    if not re.search(r'[(,]\s*$', ctx):
        continue
    body = list(md.disasm(b[a - 0x2000000:a - 0x2000000 + 64], a))
    for k, i in enumerate(body):
        if i.address != a + 4 * k:
            break
        if i.mnemonic == 'bx' and i.op_str == 'lr' or (i.mnemonic in ('pop', 'ldm') and 'pc' in i.op_str):
            cands.add(a)
            break
# function addresses stored in literal pools / tables (task callbacks, small thunks ending in `bx ip`) that the
# decompiled code only passes around as values: a word in the binary pointing at code that follows a
# return/branch or a literal pool entry, and that reaches a return or tail jump within a few instructions
END = 0x20b6268


def _body_ok(a):
    ins = list(md.disasm(b[a - 0x2000000:a - 0x2000000 + 96], a))
    for k, i in enumerate(ins):
        if i.address != a + 4 * k:
            return False
        if i.mnemonic in ('bx', 'b') or (i.mnemonic in ('pop', 'ldm') and 'pc' in i.op_str):
            return True
    return False


for o in range(0, len(b) - 4, 4):
    v = struct.unpack_from('<I', b, o)[0]
    if not (0x2000000 < v < END) or v % 4 or v in have or v in known or v in data or v in cands:
        continue
    prev = list(md.disasm(b[v - 0x2000000 - 4:v - 0x2000000], v - 4))
    pw = struct.unpack_from('<I', b, v - 0x2000000 - 4)[0]
    after_end = bool(prev) and (prev[0].mnemonic in ('bx', 'b') or (prev[0].mnemonic in ('pop', 'ldm') and 'pc' in prev[0].op_str))
    after_pool = 0x1ff8000 <= pw < 0x2400000 or 0x4000000 <= pw < 0x5000000
    if (after_end or after_pool) and _body_ok(v):
        cands.add(v)
with open('ghidra/funcs.txt', 'a') as f:
    for a in sorted(cands):
        f.write(f"{a:#x}\n")
print('added', len(cands), [hex(a) for a in sorted(cands)][:40])
