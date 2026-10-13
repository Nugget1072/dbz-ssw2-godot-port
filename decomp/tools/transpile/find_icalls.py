# Find indirect branches (bx/blx/mov pc) whose register holds a literal-pool function address, so Ghidra can be
# told the real callee (CALL_OVERRIDE_UNCONDITIONAL) and use its signature (arguments passed through registers).
import os, sys
# work directory layout (see run.sh): ghidra/{funcs.txt,funcs.json,out/,icall_overrides.txt}, ext/arm9.bin
os.chdir(os.environ.get("TRANSPILE_WORK", "."))
sys.path.insert(0, os.environ.get("CAPSTONE_PY", "/home/claude/tools/cs/bindings/python"))

import sys, struct, json
from capstone import *
from capstone.arm import *
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import image
funcs = set(int(k, 16) for k in json.load(open('ghidra/funcs.json')))
md = Cs(CS_ARCH_ARM, CS_MODE_ARM); md.detail = True; md.skipdata = True
res = []
insns = {}
for B, b, code in image.segments():
    for i in md.disasm(b, B):
        if i.id != 0: insns[i.address] = i
addrs = sorted(insns)
pos = {a: k for k, a in enumerate(addrs)}
for a in addrs:
    i = insns[a]
    reg = None
    kind = None
    if i.mnemonic.startswith('bx') and len(i.operands) == 1 and i.operands[0].type == ARM_OP_REG and i.reg_name(i.operands[0].reg) != 'lr':
        reg = i.operands[0].reg; kind = 'jump'
        prev = insns.get(a - 4)
        if prev is not None and prev.mnemonic == 'mov' and prev.op_str == 'lr, pc':
            kind = 'call'
    elif i.mnemonic.startswith('blx') and len(i.operands) == 1 and i.operands[0].type == ARM_OP_REG:
        reg = i.operands[0].reg; kind = 'call'
    if reg is None:
        continue
    # scan back for ldr reg, [pc, #imm]
    k = pos[a]
    tgt = None
    for j in range(k - 1, max(-1, k - 12), -1):
        p = insns[addrs[j]]
        if p.mnemonic in ('b', 'bx', 'pop', 'ldm') and p.address != a:
            if p.mnemonic in ('b', 'bx') or 'pc' in p.op_str: break
        writes = [p.reg_name(r) for r in p.regs_access()[1]]
        if p.reg_name(reg) in writes:
            if p.mnemonic == 'ldr' and len(p.operands) == 2 and p.operands[1].type == ARM_OP_MEM and p.operands[1].mem.base == ARM_REG_PC:
                la = p.address + 8 + p.operands[1].mem.disp
                tgt = image.word(la)
            break
    if tgt is not None and (tgt & ~1) in funcs:   # Thumb targets (odd addresses) too: BIOS wrappers via thunks
        res.append((a, tgt & ~1, kind))
open('ghidra/icall_overrides.txt', 'w').write('\n'.join(f"{a:#x} {t:#x} {k}" for a, t, k in res) + '\n')
print(len(res), 'overrides;', sum(1 for r in res if r[2] == 'jump'), 'tail jumps')
