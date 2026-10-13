#!/usr/bin/env python3
"""Compare two main-RAM dumps (reference first): ramcmp.py REF.ram PORT.ram [maxranges]"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from lockstep_cmp import region, IGNORE
a = open(sys.argv[1], "rb").read()
b = open(sys.argv[2], "rb").read()
maxr = int(sys.argv[3]) if len(sys.argv) > 3 else 40
diffs = [i for i in range(len(a)) if a[i] != b[i] and not any(s <= 0x02000000 + i < e for s, e in IGNORE)]
ranges = []
for i in diffs:
    if ranges and i <= ranges[-1][1] + 4:
        ranges[-1][1] = i
    else:
        ranges.append([i, i])
print(f"{len(diffs)} bytes differ in {len(ranges)} ranges")
for s, e in ranges[:maxr]:
    addr = 0x02000000 + s
    n, off = region(addr)
    print(f"   {addr:08x}-{0x02000000 + e:08x} {n}+{off:#x}  ref={a[s:e + 1][:16].hex()} port={b[s:e + 1][:16].hex()}")
