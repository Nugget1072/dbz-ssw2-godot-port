#!/usr/bin/env python3
"""Compare port RAM dumps with reference dumps frame by frame; report differing ranges by region.
usage: lockstep_cmp.py REFDIR OUTDIR
Regions owned by NitroSDK internals (replaced by HLE in the port: sound driver, file system, OS) are skipped unless
ALL=1 is set: their contents depend on the ARM7 and on hardware the port does not emulate."""
import sys, os, glob

REGIONS = [  # (start, end, name) — main RAM addresses
    (0x021075C8, 0x021075C8 + 0x8E8, "P1 team (0x8E8)"),
    (0x021075C8 + 0x8E8, 0x021075C8 + 2 * 0x8E8, "P2 team (0x8E8)"),
    (0x02108C44, 0x02108C44 + 0x30 * 0x164 + 0x42C0, "battle objects"),
    (0x021003D0, 0x02100420, "camera"),
    (0x020DD4C0, 0x020DD500, "main loop / keys"),
    (0x020E2000, 0x020E6680, "SDK bss"),
    (0x02000000, 0x020B7000, "ARM9 code+rodata"),
    (0x020B7000, 0x02100000, "ARM9 data/bss"),
    (0x02100000, 0x023FF000, "heap"),
    (0x023FF000, 0x02400000, "system area"),
]


IGNORE = [] if os.environ.get("ALL") else [(0x020E2000, 0x020E6680)]


def region(a):
    for s, e, n in REGIONS:
        if s <= a < e:
            return n, a - s
    return "?", 0


def main():
    ref, out = sys.argv[1], sys.argv[2]
    frames = sorted(int(os.path.basename(f)[6:10]) for f in glob.glob(os.path.join(out, "frame_*.ram")))
    import json
    info = {}
    ip = os.path.join(ref, "inputs.json")
    if os.path.exists(ip):
        info = {x["frame"]: x for x in json.load(open(ip))}
    for k in frames:
        # the emulator frame ended while the game logic was still running (e.g. a slow file read): that snapshot
        # is mid-frame, so there is nothing to compare against until the next frame that ends in IntrWait
        if k in info and not info[k].get("main_waiting", info[k].get("pc") == "0xffff0238"):
            print(f"frame {k}: skipped (reference snapshot taken mid-logic at pc {info[k]['pc']})")
            continue
        a = open(os.path.join(ref, f"frame_{k:04d}.ram"), "rb").read()
        b = open(os.path.join(out, f"frame_{k:04d}.ram"), "rb").read()
        diffs = [i for i in range(len(a)) if a[i] != b[i]] if a != b else []
        diffs = [i for i in diffs if not any(s <= 0x02000000 + i < e for s, e in IGNORE)]
        # group into ranges
        ranges = []
        for i in diffs:
            if ranges and i <= ranges[-1][1] + 4:
                ranges[-1][1] = i
            else:
                ranges.append([i, i])
        print(f"frame {k}: {len(diffs)} bytes differ in {len(ranges)} ranges")
        for s, e in ranges[:int(os.environ.get("MAXR", "25"))]:
            addr = 0x02000000 + s
            n, off = region(addr)
            print(f"   {addr:08x}-{0x02000000 + e:08x} {n}+{off:#x}  ref={a[s:e + 1][:16].hex()} port={b[s:e + 1][:16].hex()}")


if __name__ == "__main__":
    main()
