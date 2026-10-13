#!/usr/bin/env python3
"""Reference snapshot at a code address: run the original until the ARM9 reaches ADDR for the COUNT-th time
and dump main RAM there (code-point alignment for lockstep debugging).

usage: breakref.py STATE|boot ADDR[:COUNT] OUT.ram [max_frames]

Works by patching `b .` (0xEAFFFFFE) over the instruction at ADDR (ARM code in main RAM), running frame by
frame until the CPU spins there, then restoring the instruction (and, for COUNT > 1, stepping past it by
re-arming after the CPU leaves). Interrupts keep running while the CPU spins, as on hardware.
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from mh import MH

_REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
import glob as _g
ROM = os.environ.get("ROM") or (sorted(_g.glob(os.path.join(_REPO, "baseroms", "*.nds"))) or [""])[0]
SAV = os.environ.get("SAV") or (sorted(_g.glob(os.path.join(_REPO, "baseroms", "*.sav"))) or [""])[0]


def w32(e, a, v):
    e.lib.mh_poke32(a, v)


def main():
    state, spec, out = sys.argv[1], sys.argv[2], sys.argv[3]
    maxf = int(sys.argv[4]) if len(sys.argv) > 4 else 2000
    addr, count = (spec.split(":") + ["1"])[:2]
    addr, count = int(addr, 16), int(count)
    e = MH(ROM, SAV, jit=False)
    e.lib.mh_poke32.argtypes = [__import__("ctypes").c_uint32, __import__("ctypes").c_uint32]
    if state != "boot":
        e.load_state(state)
    orig = int.from_bytes(e.read(addr, 4), "little")
    hits = 0
    f = 0
    while f < maxf:
        w32(e, addr, 0xEAFFFFFE)
        while f < maxf:
            e.run(1)
            f += 1
            if e.regs()[15] in (addr, addr + 4, addr + 8):
                break
        else:
            break
        hits += 1
        w32(e, addr, orig)
        if hits == count:
            open(out, "wb").write(e.main_ram())
            dt, base = e.dtcm()
            open(out.replace(".ram", ".dtcm"), "wb").write(dt)
            r = e.regs()
            print(f"hit {hits} at frame {f}: r0-r3 {[hex(x) for x in r[:4]]} lr {r[14]:#x} sp {r[13]:#x}")
            return
        # let it execute past the instruction before re-arming (a few frames is too coarse: one frame)
        e.run(1)
        f += 1
    print("not reached", hits)


if __name__ == "__main__":
    main()
