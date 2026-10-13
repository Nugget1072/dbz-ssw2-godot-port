#!/usr/bin/env python3
"""Convert character sprites + frame info + palettes + behaviour scripts to Godot-ready files.

usage: convert_chara.py EXTRACT_DIR OUT_ASSETS_DIR [code ...]
  EXTRACT_DIR = output of nds_extract.py (needs fs/romdata/chara/* and arm9.bin)
Writes OUT/chara/<code>/
  atlas.png      8-bit greyscale: value = palette index (0..15, 0 = transparent), images cropped + packed
  palette.png    16x16 RGBA: row r = sub-palette r, colour 0 alpha 0
  images.json    per image: atlas rect + offset of the crop inside the original 128x128 texture
  frames.json    per frame: image, origin, boxes (from the frame-info GARC)
  script.json    behaviour chunk header + decoded bytecode (see charscript.py)
Stdlib + optional Pillow-free PNG writer (pure Python), so it runs on any Python >= 3.8.
"""
import json, os, struct, sys, zlib
sys.path.insert(0, os.path.dirname(__file__))
import garc, ndscomp, charscript

CHAR_TABLE = 0x020D62AC
CHAR_STRIDE = 0x43


def png_write(path, w, h, rows, mode):
    """mode 'L' (1 byte/px) or 'RGBA' (4 bytes/px); rows = list of bytes."""
    ct = {"L": 0, "RGBA": 6}[mode]
    raw = b"".join(b"\0" + r for r in rows)

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ct, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def char_table(arm9):
    out = []
    base = CHAR_TABLE - 0x02000000
    for i in range(80):
        e = base + i * CHAR_STRIDE
        path = arm9[e + 3:e + 3 + 64].split(b"\0")[0].decode("latin-1")
        if not path.startswith("/romdata/chara/"):
            break
        code = path.rsplit("/", 1)[1].replace("_img.arc", "")
        out.append({"id": i, "code": code, "script": arm9[e], "frameinfo": arm9[e + 1],
                    "palette": arm9[e + 2], "path": path})
    return out


def bgr555(c):
    return ((c & 31) * 255 // 31, ((c >> 5) & 31) * 255 // 31, ((c >> 10) & 31) * 255 // 31)


def decode_image(blob):
    # Main character frames are RLE (0x30) compressed 128x128 4bpp textures.
    # Effect archives (*_eff_img, cmneffect, win) are raw with per-entry formats: TODO (see DATA_NOTES).
    d = ndscomp.decompress(blob) if blob[:1] == b"\x30" else blob
    w = 128
    h = len(d) * 2 // w
    px = bytearray(w * h)
    for i, b in enumerate(d):
        px[2 * i] = b & 15
        px[2 * i + 1] = b >> 4
    return w, h, px


def pack(images, atlas_w=1024):
    """Shelf-pack cropped images. images: list of (w,h). returns positions, atlas height."""
    order = sorted(range(len(images)), key=lambda i: -images[i][1])
    pos = [None] * len(images)
    x = y = shelf = 0
    for i in order:
        w, h = images[i]
        if w == 0:
            pos[i] = (0, 0); continue
        if x + w > atlas_w:
            x, y, shelf = 0, y + shelf + 1, 0
        pos[i] = (x, y)
        x += w + 1
        shelf = max(shelf, h)
    return pos, y + shelf + 1


def convert(ext, out, entry, charadata):
    code = entry["code"]
    arc = open(os.path.join(ext, "fs/romdata/chara", code + "_img.arc"), "rb").read()
    imgs = garc.read(arc)
    crops, meta = [], []
    for blob in imgs:
        w, h, px = decode_image(blob)
        xs = [i % w for i, v in enumerate(px) if v]
        if not xs:
            crops.append((0, 0, b"")); meta.append({"crop": [0, 0, 0, 0]}); continue
        ys = [i // w for i, v in enumerate(px) if v]
        x0, x1, y0, y1 = min(xs), max(xs) + 1, min(ys), max(ys) + 1
        cw, ch = x1 - x0, y1 - y0
        data = b"".join(bytes(px[(y0 + r) * w + x0:(y0 + r) * w + x1]) for r in range(ch))
        crops.append((cw, ch, data))
        meta.append({"crop": [x0, y0, cw, ch], "tex": [w, h]})
    pos, ah = pack([(c[0], c[1]) for c in crops])
    aw = 1024
    atlas = [bytearray(aw) for _ in range(ah)]
    for (cw, ch, data), p, m in zip(crops, pos, meta):
        m["atlas"] = [p[0], p[1], cw, ch]
        for r in range(ch):
            atlas[p[1] + r][p[0]:p[0] + cw] = data[r * cw:(r + 1) * cw]
    od = os.path.join(out, "chara", code)
    os.makedirs(od, exist_ok=True)
    png_write(os.path.join(od, "atlas.png"), aw, ah, [bytes(r) for r in atlas], "L")
    json.dump({"code": code, "count": len(meta), "images": meta}, open(os.path.join(od, "images.json"), "w"))
    # palette
    pal = charadata[entry["palette"]]
    rows = []
    for r in range(16):
        row = bytearray()
        for c in range(16):
            o = (r * 16 + c) * 2
            v = struct.unpack_from("<H", pal, o)[0] if o + 2 <= len(pal) else 0
            rr, gg, bb = bgr555(v)
            row += bytes((rr, gg, bb, 0 if c == 0 else 255))
        rows.append(bytes(row))
    png_write(os.path.join(od, "palette.png"), 16, 16, rows, "RGBA")
    # frame info
    frames = []
    fi = charadata[entry["frameinfo"]]
    if fi[:4] == b"GARC":
        for f in garc.read(fi):
            img, ox, oy, n = struct.unpack_from("<4H", f, 0)
            boxes = [list(struct.unpack_from("<4hI", f, 8 + 12 * j)) for j in range(n)]
            frames.append({"image": img, "origin": [ox, oy], "boxes": boxes})
    json.dump({"code": code, "frames": frames}, open(os.path.join(od, "frames.json"), "w"))
    # behaviour script
    sc = charadata[entry["script"]]
    if sc[1:4].decode("latin-1", "replace") in (code[:3],) or sc[:1] in (b"c", b"e"):
        h, codez, errs = charscript.parse(sc)
        json.dump({"header": h, "code": codez, "errors": errs}, open(os.path.join(od, "script.json"), "w"))
        open(os.path.join(od, "script.bin"), "wb").write(sc)
    return {"code": code, "images": len(meta), "frames": len(frames), "atlas": [aw, ah]}


def main():
    ext, out = sys.argv[1], sys.argv[2]
    only = set(sys.argv[3:])
    arm9 = open(os.path.join(ext, "arm9.bin"), "rb").read()
    charadata = garc.read(open(os.path.join(ext, "fs/romdata/chara/charadata.arc"), "rb").read())
    table = char_table(arm9)
    os.makedirs(os.path.join(out, "chara"), exist_ok=True)
    json.dump(table, open(os.path.join(out, "chara", "table.json"), "w"), indent=1)
    for e in table:
        if only and e["code"] not in only:
            continue
        if e["code"].endswith("_eff") or e["code"] in ("cmneffect", "win"):
            continue  # effect sprite formats not decoded yet
        print(convert(ext, out, e, charadata), flush=True)


if __name__ == "__main__":
    main()
