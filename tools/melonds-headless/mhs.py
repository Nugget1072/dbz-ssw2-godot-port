#!/usr/bin/env python3
"""Run a command list against the headless emulator, starting from a savestate (or boot).
usage: mhs.py ROM SAV IN_STATE|- OUT_STATE|- SHOTDIR cmd [cmd ...]
cmds: run:N  press:A+B:N  hold:Right:N  touch:X:Y:N  shot:name  save:path"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from mh import MH
rom, sav, sin, sout, shots = sys.argv[1:6]
e = MH(rom, sav)
if sin != "-":
    e.load_state(sin)
os.makedirs(shots, exist_ok=True)
for c in sys.argv[6:]:
    p = c.split(":")
    if p[0] == "run": e.run(int(p[1]))
    elif p[0] in ("press", "hold"): e.press(p[1].split("+"), int(p[2]) if len(p) > 2 else 4)
    elif p[0] == "touch": e.touch(int(p[1]), int(p[2]), int(p[3]) if len(p) > 3 else 4)
    elif p[0] == "shot": e.screens().save(os.path.join(shots, p[1] + ".png")); print("shot", p[1], e.frame)
    elif p[0] == "save": e.save_state(p[1])
    else: raise SystemExit("bad cmd " + c)
if sout != "-":
    e.save_state(sout)
