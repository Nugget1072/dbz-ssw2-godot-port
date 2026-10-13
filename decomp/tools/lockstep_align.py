#!/usr/bin/env python3
"""Match the port's frames to the reference frames and report RAM differences.

usage: lockstep_align.py REFDIR OUTDIR [--ranges N] [--window W]

The port presents a frame at every vblank wait; the original only shows a wait in a snapshot when the wait
spans a frame boundary (a wait that starts during the active display after a slow step is invisible), and it
also has lag frames. So each port frame (OUTDIR/sync_XXXX.ram, counters in syncs.json) is matched to the
reference frame, among the next W waiting frames with the same NitroMain loop counter, whose RAM is closest.
Regions owned by the ARM7 / NitroSDK internals are ignored (see lockstep_cmp.IGNORE + ARM7 main RAM).
"""
import sys, os, json
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from lockstep_cmp import region, IGNORE

IGNORE_ALL = IGNORE + [(0x023E0000, 0x023FF000)]   # ARM7-owned part of main RAM


def load(path):
    a = np.frombuffer(open(path, "rb").read(), dtype=np.uint8).copy()
    for s, e in IGNORE_ALL:
        a[s - 0x02000000:e - 0x02000000] = 0
    return a


def main():
    ref, out = sys.argv[1], sys.argv[2]
    nr = int(sys.argv[sys.argv.index("--ranges") + 1]) if "--ranges" in sys.argv else 8
    win = int(sys.argv[sys.argv.index("--window") + 1]) if "--window" in sys.argv else 6
    info = json.load(open(os.path.join(ref, "inputs.json")))
    waiting = [(e["frame"], e.get("counter", -1)) for e in info if e.get("main_waiting")]
    syncs = json.load(open(os.path.join(out, "syncs.json")))
    last = 0
    cache = {}
    for s in syncs:
        k, c = s["sync"], s["counter"]
        cands = [f for f, cc in waiting if f > last and cc == c][:win]
        p = load(os.path.join(out, f"sync_{k:04d}.ram"))
        best = None
        for f in cands:
            if f not in cache:
                cache[f] = load(os.path.join(ref, f"frame_{f:04d}.ram"))
            d = int(np.count_nonzero(cache[f] != p))
            if best is None or d < best[1]:
                best = (f, d)
        if best is None:
            print(f"port {k:4d} (counter {c}): no reference frame")
            continue
        f, d = best
        last = f
        r = cache[f]
        idx = np.nonzero(r != p)[0]
        ranges = []
        for i in idx.tolist():
            if ranges and i <= ranges[-1][1] + 4:
                ranges[-1][1] = i
            else:
                ranges.append([i, i])
        print(f"port {k:4d} (counter {c}) ~ ref {f:4d}: {d} bytes differ in {len(ranges)} ranges")
        for a0, a1 in ranges[:nr]:
            addr = 0x02000000 + a0
            n, off = region(addr)
            print(f"   {addr:08x}-{0x02000000 + a1:08x} {n}+{off:#x}  ref={bytes(r[a0:a1 + 1][:16]).hex()} port={bytes(p[a0:a1 + 1][:16]).hex()}")


if __name__ == "__main__":
    main()
