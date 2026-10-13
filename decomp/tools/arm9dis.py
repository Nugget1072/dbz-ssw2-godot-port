#!/usr/bin/env python3
"""Disassemble the ARM9 binary.  usage: arm9dis.py ADDR [COUNT] [t]   (t = Thumb)
Needs capstone (cloud: PYTHONPATH=/home/claude/tools/cs/bindings/python)."""
import struct, sys, os
import capstone
BASE = 0x02000000
ARM9 = os.environ.get("ARM9", os.path.join(os.path.dirname(__file__), "../extract/arm9.bin"))
d = open(ARM9, "rb").read()
a = int(sys.argv[1], 16); n = int(sys.argv[2]) if len(sys.argv) > 2 else 64
thumb = len(sys.argv) > 3 and sys.argv[3] == "t"
md = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB if thumb else capstone.CS_MODE_ARM)
off = a - BASE
for ins in md.disasm(d[off:off + n * 4], a):
    extra = ""
    if "[pc, #" in ins.op_str and ins.mnemonic.startswith("ldr"):
        imm = int(ins.op_str.split("#")[1].rstrip("]"), 0)
        pc = (ins.address + (4 if thumb else 8)) & ~3
        lit = struct.unpack_from("<I", d, pc + imm - BASE)[0]
        extra = f"   ; ={lit:#x}"
    print(f"{ins.address:08x}: {ins.bytes.hex():10s} {ins.mnemonic:8s} {ins.op_str}{extra}")
    n -= 1
    if n <= 0: break
