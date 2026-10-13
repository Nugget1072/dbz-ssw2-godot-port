#!/usr/bin/env python3
"""Compare two `lanhash=FILE` logs of a LAN battle (part 30, docs/LAN_DESIGN.md 8).

usage: lan_cmp.py HOST.txt GUEST.txt
Lines: "LANH B<battle> L<lockstep frame> f<port frame> sc <scene/state> st <state> rng <state> gp <gameplay hash> G <block hash>".
Prints the number of lockstep frames both have, the first frame whose gameplay hash (the desync checksum: drawing-only
fields excluded) differs, the first frame whose whole battle-globals hash differs (expected with different CAMERA ZOOM /
DETAILED SHADOWS on the two machines), and the scenes the battle went through. Exit code 1 when the gameplay hash differs.
"""
import sys


def load(path):
    d = {}
    for line in open(path):
        t = line.split()
        if not t or t[0] != "LANH":
            continue
        kv = {"B": t[1][1:], "L": int(t[2][1:]), "f": t[3][1:]}
        for k in ("sc", "st", "rng", "gp", "G"):
            if k in t:
                kv[k] = t[t.index(k) + 1]
        d[(kv["B"], kv["L"])] = kv
    return d


a = load(sys.argv[1])
b = load(sys.argv[2])
common = sorted(set(a) & set(b), key=lambda k: (int(k[0]), k[1]))
print("frames: host %d guest %d common %d" % (len(a), len(b), len(common)))
first = {}
for k in common:
    for f in ("gp", "G", "rng", "sc"):
        if a[k].get(f) != b[k].get(f) and f not in first:
            first[f] = k
for f in ("gp", "rng", "sc", "G"):
    print("%-3s first diff: %s" % (f, "none" if f not in first else "B%s L%d (host %s guest %s)" % (
        first[f][0], first[f][1], a[first[f]].get(f), b[first[f]].get(f))))
scenes = []
for k in common:
    s = a[k]["sc"]
    if not scenes or scenes[-1][1] != s:
        scenes.append((k[1], s))
print("scene/state changes (L:sc): " + " ".join("%d:%s" % x for x in scenes))
print("distinct gameplay hashes: %d" % len(set(a[k]["gp"] for k in common)))
sys.exit(1 if "gp" in first else 0)
