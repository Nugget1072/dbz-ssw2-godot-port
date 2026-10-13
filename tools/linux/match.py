# match.py REFDIR PORTDIR -- for each port shot p<N>.png find the closest melonDS frame r<i>.png (monotonic
# search: the original has lag frames while loading, the port does not) and print the differing pixel count
# for each port shot find the closest melonDS frame (monotonic search window)
import sys, glob, re, numpy as np
from PIL import Image
refdir, portdir = sys.argv[1], sys.argv[2]
R = {}
def ref(i):
    if i not in R: R[i] = np.asarray(Image.open(f'{refdir}/r{i}.png').convert('RGB')).astype(np.int16)
    return R[i]
shots = sorted(glob.glob(f'{portdir}/p*.png'), key=lambda f: int(re.findall(r'\d+', f.split('/')[-1])[0]))
last = int(__import__("os").environ.get("START", "1"))
nref = max(int(re.findall(r'\d+', f.split('/')[-1])[0]) for f in glob.glob(f'{refdir}/r*.png'))
for f in shots:
    n = int(re.findall(r'\d+', f.split('/')[-1])[0])
    p = np.asarray(Image.open(f).convert('RGB')).astype(np.int16)
    best = None
    for i in range(last, min(nref, last + 400) + 1):
        d = int((np.abs(p - ref(i)).sum(axis=2) > 0).sum())
        if best is None or d < best[0]: best = (d, i)
        if d == 0: break
    print(f'port {n:4d} -> ref {best[1]:4d}  diff px {best[0]}')
    if best[0] < 2000: last = best[1]
