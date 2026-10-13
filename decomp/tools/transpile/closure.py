# add every called-but-undefined function address (func_0x..., FUN_... without a body) to ghidra/funcs.txt
import os, sys
# work directory layout (see run.sh): ghidra/{funcs.txt,funcs.json,out/,icall_overrides.txt}, ext/arm9.bin
os.chdir(os.environ.get("TRANSPILE_WORK", "."))
sys.path.insert(0, os.environ.get("CAPSTONE_PY", "/home/claude/tools/cs/bindings/python"))

import json, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import image
idx = json.load(open('ghidra/funcs.json'))
have = set(int(k, 16) for k in idx)
txt = open('ghidra/funcs.txt').read().split()
known = set(int(x, 16) for x in txt)
new = set()
for k, v in idx.items():
    for m in re.findall(r'\b(?:func_0x|FUN_)([0-9a-f]{8})\b', v):
        a = int(m, 16)
        if a not in have and a not in known and image.in_code(a):
            new.add(a)
with open('ghidra/funcs.txt', 'a') as f:
    for a in sorted(new):
        f.write(f"{a:#x}\n")
print('added', len(new), [hex(a) for a in sorted(new)])
