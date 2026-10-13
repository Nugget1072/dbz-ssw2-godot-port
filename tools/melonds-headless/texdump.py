#!/usr/bin/env python3
"""Dump every textured polygon rendered in a frame: decoded texture (from emulated VRAM),
screen quad, and the ROM file entry the texels came from (by searching all extracted data).

usage: texdump.py STATE FRAMES OUTDIR [--index index.pkl]
"""
import sys, os, struct, json, pickle
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../decomp/tools"))
from mh import MH
from PIL import Image

_REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
import glob as _g
ROM = os.environ.get("ROM") or (sorted(_g.glob(os.path.join(_REPO, "baseroms", "*.nds"))) or [""])[0]
SAV = os.environ.get("SAV") or (sorted(_g.glob(os.path.join(_REPO, "baseroms", "*.sav"))) or [""])[0]
EXT = os.environ.get("EXT", "/home/claude/work/ext")


def tp_decode(t):
    return dict(off=(t & 0xFFFF) * 8, w=8 << ((t >> 20) & 7), h=8 << ((t >> 23) & 7), fmt=(t >> 26) & 7,
                c0=(t >> 29) & 1, rep=(t >> 16) & 3, flip=(t >> 18) & 3)


def tex_slots(e):
    """Concatenate texture image slots 0-3 and palette slots from banks per VRAMCNT."""
    img = bytearray(0x80000); pal = bytearray(0x18000)
    sizes = [0x20000, 0x20000, 0x20000, 0x20000, 0x10000, 0x4000, 0x4000, 0x8000, 0x4000]
    for b in range(9):
        cnt = e.vramcnt(b)
        if not cnt & 0x80: continue
        mst, ofs = cnt & 7, (cnt >> 3) & 3
        data = e.vram(b)
        if b <= 3 and mst == 3:
            img[ofs * 0x20000: ofs * 0x20000 + len(data)] = data
        elif b == 4 and mst == 3:
            pal[0:0x10000] = data
        elif b in (5, 6) and mst == 3:
            o = (ofs & 1) * 0x4000 + (ofs >> 1) * 0x10000
            pal[o:o + 0x4000] = data
    return bytes(img), bytes(pal)


def decode_tex(img, pal, tp, palbase):
    w, h, fmt, off = tp["w"], tp["h"], tp["fmt"], tp["off"]
    bpp = {1: 8, 2: 2, 3: 4, 4: 8, 6: 8, 7: 16}.get(fmt, 0)
    if not bpp: return None, b""
    nbytes = w * h * bpp // 8
    raw = img[off:off + nbytes]
    pb = palbase * (8 if fmt == 2 else 16)
    out = Image.new("RGBA", (w, h)); px = out.load()
    for y in range(h):
        for x in range(w):
            i = y * w + x
            a = 255
            if fmt == 3: v = (raw[i // 2] >> (4 * (i & 1))) & 15
            elif fmt == 4: v = raw[i]
            elif fmt == 2: v = (raw[i // 4] >> (2 * (i & 3))) & 3
            elif fmt == 6: v = raw[i] & 7; a = (raw[i] >> 3) * 255 // 31
            elif fmt == 1: v = raw[i] & 31; a = (raw[i] >> 5) * 255 // 7
            elif fmt == 7:
                c = raw[2 * i] | raw[2 * i + 1] << 8
                px[x, y] = ((c & 31) * 8, ((c >> 5) & 31) * 8, ((c >> 10) & 31) * 8, 255 if c & 0x8000 else 0); continue
            if v == 0 and tp["c0"] and fmt in (2, 3, 4): a = 0
            c = pal[pb + 2 * v] | pal[pb + 2 * v + 1] << 8
            px[x, y] = ((c & 31) * 8, ((c >> 5) & 31) * 8, ((c >> 10) & 31) * 8, a)
    return out, raw


def build_index():
    """All candidate data blobs: GARC entries and pack members (decompressed)."""
    import garc, binpack, ndscomp
    blobs = []
    for root, _, files in os.walk(os.path.join(EXT, "fs")):
        for f in files:
            p = os.path.join(root, f); rel = os.path.relpath(p, os.path.join(EXT, "fs"))
            d = open(p, "rb").read()
            if d[:4] == b"GARC":
                for i, x in enumerate(garc.read(d)):
                    if x[:1] == b"\x30" and len(x) > 4:
                        try: x = ndscomp.decompress(x)
                        except Exception: pass
                    blobs.append((f"{rel}#{i}", x))
            elif binpack.is_pack(d):
                try:
                    for n, x, c in binpack.read(d): blobs.append((f"{rel}:{n}", x))
                except Exception: pass
    return blobs


def main():
    state, frames, outdir = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    os.makedirs(outdir, exist_ok=True)
    idx_path = "/tmp/blob_index.pkl"
    if os.path.exists(idx_path): blobs = pickle.load(open(idx_path, "rb"))
    else:
        blobs = build_index(); pickle.dump(blobs, open(idx_path, "wb"))
    e = MH(ROM, SAV); e.load_state(state); e.run(frames)
    e.screens().save(os.path.join(outdir, "_screen.png"))
    img, pal = tex_slots(e)
    seen = {}; recs = []
    for n, p in enumerate(e.polys()):
        tp = tp_decode(p["texparam"])
        key = (p["texparam"], p["texpal"])
        if key not in seen:
            im, raw = decode_tex(img, pal, tp, p["texpal"])
            src = None
            if raw and len(raw) >= 32 and any(raw):
                probe = raw[:min(len(raw), 256)]
                for name, b in blobs:
                    i = b.find(probe)
                    if i >= 0: src = f"{name}@{i:#x}"; break
            fn = f"t{len(seen):03d}.png"
            if im: im.save(os.path.join(outdir, fn))
            seen[key] = (fn, src)
        fn, src = seen[key]
        xs = [v[6] for v in p["verts"]]; ys = [v[7] for v in p["verts"]]
        recs.append({"poly": n, "attr": hex(p["attr"]), "tex": tp, "texpal": p["texpal"], "img": fn, "src": src,
                     "screen": [min(xs), min(ys), max(xs), max(ys)], "w": p["verts"][0][3],
                     "verts": [[v[4] / 16, v[5] / 16, v[6], v[7], v[8], v[9], v[10]] for v in p["verts"]]})
    json.dump(recs, open(os.path.join(outdir, "polys.json"), "w"), indent=1)
    for r in recs:
        if r["tex"]["w"] == 256 and r["tex"]["fmt"] == 4: continue
        print(r["poly"], r["img"], r["tex"]["w"], r["tex"]["h"], r["tex"]["fmt"], hex(r["tex"]["off"]), r["texpal"], r["screen"], r["src"])


if __name__ == "__main__":
    main()
