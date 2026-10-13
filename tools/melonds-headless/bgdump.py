#!/usr/bin/env python3
"""Identify where every 2D layer of a DS screen comes from (ROM file + offset), and dump layers.

usage: bgdump.py STATE FRAMES ENGINE(0=A top,1=B bottom) OUTDIR
For each enabled BG: control bits, map, tile data source, palette source; for OBJ: OAM entries.
"""
import sys, os, struct, json, pickle
sys.path.insert(0, os.path.dirname(__file__))
from mh import MH
import texdump
from PIL import Image


def find(blobs, probe, minlen=32):
    if len(probe) < minlen or not any(probe):
        return None
    for name, b in blobs:
        i = b.find(probe)
        if i >= 0:
            return f"{name}@{i:#x}"
    return None


def main():
    state, frames, eng, outdir = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    os.makedirs(outdir, exist_ok=True)
    blobs = pickle.load(open("/tmp/blob_index.pkl", "rb")) if os.path.exists("/tmp/blob_index.pkl") else texdump.build_index()
    e = MH(texdump.ROM, texdump.SAV); e.load_state(state); e.run(frames)
    e.screens().save(os.path.join(outdir, "_screen.png"))
    g = e.gpu2d(eng)
    disp = g["dispcnt"]
    vbase = 0x06000000 if eng == 0 else 0x06200000
    palbase = 0x05000000 if eng == 0 else 0x05000400
    cb_off = ((disp >> 24) & 7) * 0x10000 if eng == 0 else 0
    sb_off = ((disp >> 27) & 7) * 0x10000 if eng == 0 else 0
    mode = disp & 7
    info = {"dispcnt": hex(disp), "mode": mode, "layers": []}
    pal = e.read(palbase, 0x200)
    for bg in range(4):
        if not (disp >> (8 + bg)) & 1: continue
        if eng == 0 and bg == 0 and disp & 8: info["layers"].append({"bg": 0, "type": "3D"}); continue
        cnt = g["bgcnt"][bg]
        cb = ((cnt >> 2) & 15) * 0x4000 + cb_off; sb = ((cnt >> 8) & 31) * 0x800 + sb_off
        bpp8 = (cnt >> 7) & 1; size = (cnt >> 14) & 3
        affine = (mode == 1 and bg == 3) or (mode == 2 and bg >= 2) or (mode >= 3 and bg == 3)
        if affine:
            side = 16 << size; mapbytes = side * side
        else:
            w = 32 << (size & 1); h = 32 << (size >> 1); mapbytes = w * h * 2
        m = e.read(vbase + sb, mapbytes)
        ents = set()
        if affine: ents = set(m)
        else:
            for i in range(0, len(m), 2): ents.add(struct.unpack_from("<H", m, i)[0] & 0x3FF)
        maxt = max(ents) + 1 if ents else 1
        tb = 64 if (bpp8 or affine) else 32
        tiles = e.read(vbase + cb, maxt * tb)
        # use a non-empty run of tiles as probe
        probe_off = next((t * tb for t in sorted(ents) if any(tiles[t * tb:(t + 1) * tb])), 0)
        src_t = find(blobs, tiles[probe_off:probe_off + 4 * tb])
        src_m = find(blobs, m[:256], 64)
        L = {"bg": bg, "cnt": hex(cnt), "prio": cnt & 3, "char_base": hex(cb), "screen_base": hex(sb), "bpp": 8 if bpp8 or affine else 4,
             "affine": affine, "size": size, "tiles_used": maxt, "tiles_src": src_t, "tiles_probe_off": probe_off, "map_src": src_m,
             "hofs": g["hofs"][bg], "vofs": g["vofs"][bg]}
        info["layers"].append(L)
        open(os.path.join(outdir, f"bg{bg}_map.bin"), "wb").write(m)
        open(os.path.join(outdir, f"bg{bg}_tiles.bin"), "wb").write(tiles)
    # palettes (find which 16-colour rows come from which file)
    prow = []
    for r in range(16):
        seg = pal[r * 32:(r + 1) * 32]
        if any(seg[2:]): prow.append((r, find(blobs, seg[2:32], 16)))
    info["pal_rows"] = prow
    open(os.path.join(outdir, "pal.bin"), "wb").write(pal)
    # OBJ
    if (disp >> 12) & 1:
        oam = e.read(0x07000000 if eng == 0 else 0x07000400, 0x400)
        objs = []
        for i in range(128):
            a0, a1, a2 = struct.unpack_from("<3H", oam, i * 8)
            if (a0 >> 8) & 3 == 2: continue  # disabled
            shape, sz = a0 >> 14, a1 >> 14
            W = [[8, 16, 32, 64], [16, 32, 32, 64], [8, 8, 16, 32]][shape][sz]
            H = [[8, 16, 32, 64], [8, 8, 16, 32], [16, 32, 32, 64]][shape][sz]
            objs.append({"i": i, "x": a1 & 511, "y": a0 & 255, "w": W, "h": H, "tile": a2 & 1023, "pal": a2 >> 12,
                         "prio": (a2 >> 10) & 3, "bpp8": (a0 >> 13) & 1, "hflip": (a1 >> 12) & 1, "vflip": (a1 >> 13) & 1,
                         "affine": (a0 >> 8) & 1})
        info["obj"] = objs
        obase = 0x06400000 if eng == 0 else 0x06600000
        info["obj_vram_head"] = e.read(obase, 64).hex()
        open(os.path.join(outdir, "obj_vram.bin"), "wb").write(e.read(obase, 0x8000))
        open(os.path.join(outdir, "obj_pal.bin"), "wb").write(e.read(palbase + 0x200, 0x200))
    json.dump(info, open(os.path.join(outdir, "layers.json"), "w"), indent=1)
    print(json.dumps(info, indent=1)[:4000])


if __name__ == "__main__":
    main()
