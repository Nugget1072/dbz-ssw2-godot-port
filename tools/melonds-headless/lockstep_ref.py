#!/usr/bin/env python3
"""Produce reference RAM snapshots from the original game for lockstep-testing the port.

usage: lockstep_ref.py STATE OUTDIR "cmds"     (cmds = mhs-style: run:N press:A+Right:N ...)
Writes OUTDIR/frame_0000.ram (main RAM 4 MiB) + .dtcm (16 KiB) + frame_0000.io (ARM9 IO 0x04000000-0x040010FF) + inputs.json (per frame: key mask, 0x027FFFA8)
for frame 0 (the loaded state) and every following frame.
"""
import sys, os, json
sys.path.insert(0, os.path.dirname(__file__))
from mh import MH, BTN

MAIN_COUNTER = 0x020DD4C0       # u16 incremented once per NitroMain loop iteration (game logic step)
OS_THREAD_INFO = 0x020E31BC     # OSThreadInfo (+8 = current thread); see decomp/DATA_NOTES.md
LAUNCHER_THREAD = 0x020E32A4    # OSThread of NitroMain (context: +0 cpsr, +4 r0-r12, +0x38 sp, +0x3C lr, +0x40 pc+4)
_REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
import glob as _g
ROM = os.environ.get("ROM") or (sorted(_g.glob(os.path.join(_REPO, "baseroms", "*.nds"))) or [""])[0]
SAV = os.environ.get("SAV") or (sorted(_g.glob(os.path.join(_REPO, "baseroms", "*.sav"))) or [""])[0]


def main():
    state, out, cmds = sys.argv[1], sys.argv[2], sys.argv[3].split()
    os.makedirs(out, exist_ok=True)
    e = MH(ROM, SAV)
    if state != "boot":      # "boot": start from power-on (direct boot), frame 0 = memory before the first ARM9 instruction
        e.load_state(state)
    frames = []
    for c in cmds:
        p = c.split(":")
        if p[0] == "run":
            frames += [[]] * int(p[1])
        elif p[0] in ("press", "hold"):
            frames += [p[1].split("+")] * (int(p[2]) if len(p) > 2 else 4)

    def dump(k):
        open(os.path.join(out, f"frame_{k:04d}.ram"), "wb").write(e.main_ram())
        dt, base = e.dtcm()
        # (DTCM is only mapped at 0x027E0000 once the game set up CP15; at power-on it is elsewhere)
        open(os.path.join(out, f"frame_{k:04d}.dtcm"), "wb").write(dt)

    dump(0)
    counter0 = e.u16(MAIN_COUNTER)
    # ARM9 IO registers at the start frame (2D engines A/B, DMA, timers, IRQ, GX status); the port's io model is
    # seeded from this so register-dependent code (DISPSTAT, IE, ...) behaves like the original
    open(os.path.join(out, "frame_0000.io"), "wb").write(e.read32(0x04000000, 0x1100 // 4))
    info = []
    for k, btns in enumerate(frames, 1):
        e.input(btns)
        e.run(1)
        mask = 0
        for b in btns:
            if BTN[b] < 10:
                mask |= 1 << BTN[b]
        # Is NitroMain's thread parked in its vblank wait? On a thread switch the halted main thread's context
        # (pc in the BIOS IntrWait loop) is saved in its OSThread; the CPU may be running another thread.
        pc = e.regs()[15]
        cur = int.from_bytes(e.read(OS_THREAD_INFO + 8, 4), "little")
        if cur == LAUNCHER_THREAD or cur == 0:
            waiting = pc >= 0xFFFF0000
        else:
            waiting = int.from_bytes(e.read(LAUNCHER_THREAD + 0x40, 4), "little") - 4 >= 0xFFFF0000
        info.append({"frame": k, "main_waiting": waiting, "counter": e.u16(MAIN_COUNTER), "buttons": btns, "keyinput": (~mask) & 0x3FF, "xy": e.u16(0x027FFFA8),
                     "touch_raw": int.from_bytes(e.read(0x027FFFAA, 4), "little"),
                     "pc": hex(e.regs()[15])})
        dump(k)
    json.dump(info, open(os.path.join(out, "inputs.json"), "w"), indent=0)
    json.dump({"counter0": counter0, "boot": state == "boot"}, open(os.path.join(out, "start.json"), "w"))
    print("dumped", len(frames) + 1, "frames ->", out)


if __name__ == "__main__":
    main()
