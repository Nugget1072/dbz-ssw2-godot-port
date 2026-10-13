import os, sys
# work directory layout (see run.sh): ghidra/{funcs.txt,funcs.json,out/,icall_overrides.txt}, ext/arm9.bin
os.chdir(os.environ.get("TRANSPILE_WORK", "."))
sys.path.insert(0, os.environ.get("CAPSTONE_PY", "/home/claude/tools/cs/bindings/python"))

import re,json
import glob
s=open(sorted(glob.glob('ghidra/out/decomp_*.c'))[-1]).read()
d={}
for p in re.split(r'(?m)^(?=// ===== )',s):
    m=re.match(r'// ===== \S+ @ ([0-9a-f]{8})',p)
    if m: d[m.group(1)]=p
json.dump(d,open('ghidra/funcs.json','w'))
print(len(d))
