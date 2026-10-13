#!/usr/bin/env python3
"""Convert battle stages: 3D panorama objects + textures + 2D sky/horizon BG layers.

usage: convert_stage.py EXTRACT_DIR OUT_ASSETS_DIR
Writes OUT/stage/stage_XX/ (XX = stage id 0..14, file stg_{XX+1}):
  mesh.json      objects: texture index, triangles; vertex = [x, y, z, u, v (texels), r, g, b (0..31, DS-lit)]
  tex_N.png      textures from stg_N_tex.bin (RGBA, colour 0 transparent)
  bg2.png        512x256 horizon layer (engine A BG2), index 0 transparent
  bg3.png        256x256 sky layer (engine A BG3)
  stage.json     metadata (BG table row, texture sizes, flags)
See DATA_NOTES.md "Stages" for the formats and the camera model.
"""
import json, os, struct, sys
sys.path.insert(0, os.path.dirname(__file__))
import garc, gx
from convert_chara import png_write

STAGE_FILES = 0x020D5E7C
STAGE_BG = 0x020CFA40
NSTAGES = 15


def bgr555(c):
    return ((c & 31) * 255 // 31, ((c >> 5) & 31) * 255 // 31, ((c >> 10) & 31) * 255 // 31)


def read_textures(d):
    out, p = [], 0
    while True:
        w, h, fmt, palsz = struct.unpack_from("<4H", d, p)
        po, to, ts, nx = struct.unpack_from("<4I", d, p + 8)
        fmt >>= 8
        pal = [bgr555(struct.unpack_from("<H", d, po + 2 * i)[0]) for i in range(palsz // 2)]
        t = d[to:to + ts]
        rows = []
        for y in range(h):
            row = bytearray()
            for x in range(w):
                i = y * w + x
                a = 255
                if fmt == 2:
                    v = (t[i // 4] >> (2 * (i & 3))) & 3
                elif fmt == 3:
                    v = (t[i // 2] >> (4 * (i & 1))) & 15
                elif fmt == 4:
                    v = t[i]
                elif fmt == 6:
                    v = t[i] & 7; a = (t[i] >> 3) * 255 // 31
                elif fmt == 1:
                    v = t[i] & 31; a = (t[i] >> 5) * 255 // 7
                else:
                    v = 0
                if fmt in (2, 3, 4) and v == 0:
                    a = 0  # colour 0 transparent (texparam bit 29 set in-game)
                c = pal[v] if v < len(pal) else (255, 0, 255)
                row += bytes(c) + bytes((a,))
            rows.append(bytes(row))
        out.append({"w": w, "h": h, "format": fmt, "rows": rows})
        if nx == 0:
            break
        p = nx
    return out


def read_objects(d):
    objs, p = [], 0
    while True:
        hdr = struct.unpack_from("<22I", d, p)
        start = 0x58 if p == 0 else hdr[0]
        prims, _ = gx.decode(d[start:start + hdr[1]])
        difamb, speemi = hdr[18], hdr[19]
        c5 = lambda v: (v & 31, (v >> 5) & 31, (v >> 10) & 31)
        mat = {"dif": c5(difamb), "amb": c5(difamb >> 16), "spe": c5(speemi), "emi": c5(speemi >> 16)}
        tris = []
        for pr in prims:
            for t in gx.triangles(pr):
                # per-vertex colour baked with the DS lighting equation (light 0 = dir (0,256,512) white,
                # read from the emulator during battle; see DATA_NOTES "Stage lighting")
                tris.append([[round(c, 6) for c in v["pos"]] + list(v["uv"]) +
                             list(gx.ds_light(v["nrm"], dif=mat["dif"], amb=mat["amb"], spe=mat["spe"], emi=mat["emi"]))
                             for v in t])
        objs.append({"texture": hdr[16], "params": [hex(x) for x in hdr[11:21]], "tris": tris})
        nxt = hdr[21]
        if nxt <= p or nxt >= len(d):
            break
        p = nxt
    return objs


def render_bg(tiles, mapd, pal, w_tiles, h_tiles, affine):
    rows = [bytearray(w_tiles * 8 * 4) for _ in range(h_tiles * 8)]
    for ty in range(h_tiles):
        for tx in range(w_tiles):
            if affine:
                idx = ty * w_tiles + tx
                if idx >= len(mapd): continue
                t, hf, vf = mapd[idx], 0, 0
            else:
                blk = (tx // 32) + (ty // 32) * max(1, w_tiles // 32)
                idx = blk * 1024 + (ty % 32) * 32 + (tx % 32)
                if idx * 2 + 2 > len(mapd): continue
                e = struct.unpack_from("<H", mapd, idx * 2)[0]
                t, hf, vf = e & 0x3FF, (e >> 10) & 1, (e >> 11) & 1
            for y in range(8):
                for x in range(8):
                    sx = 7 - x if hf else x
                    sy = 7 - y if vf else y
                    o = t * 64 + sy * 8 + sx
                    v = tiles[o] if o < len(tiles) else 0
                    if v == 0:
                        continue
                    r, g, b = bgr555(struct.unpack_from("<H", pal, v * 2)[0])
                    px = (tx * 8 + x) * 4
                    rows[ty * 8 + y][px:px + 4] = bytes((r, g, b, 255))
    return [bytes(r) for r in rows]


def main():
    ext, out = sys.argv[1], sys.argv[2]
    arm9 = open(os.path.join(ext, "arm9.bin"), "rb").read()
    A = lambda a: a - 0x02000000
    bgarc = garc.read(open(os.path.join(ext, "fs/romdata/game/game_bg.arc"), "rb").read())
    for s in range(NSTAGES):
        paths = []
        for k in range(3):
            ptr = struct.unpack_from("<I", arm9, A(STAGE_FILES) + (3 * s + k) * 4)[0]
            paths.append(arm9[A(ptr):arm9.index(b"\0", A(ptr))].decode().lstrip("/"))
        od = os.path.join(out, "stage", f"stage_{s:02d}")
        os.makedirs(od, exist_ok=True)
        geo = open(os.path.join(ext, "fs", paths[0]), "rb").read()
        texd = open(os.path.join(ext, "fs", paths[1]), "rb").read()
        texs = read_textures(texd)
        for i, t in enumerate(texs):
            png_write(os.path.join(od, f"tex_{i}.png"), t["w"], t["h"], t["rows"], "RGBA")
        objs = read_objects(geo)
        json.dump({"objects": objs, "textures": [[t["w"], t["h"], t["format"]] for t in texs]},
                  open(os.path.join(od, "mesh.json"), "w"))
        row = arm9[A(STAGE_BG) + 9 * s: A(STAGE_BG) + 9 * s + 9]
        t2, m2, p2, t3, m3 = row[0], row[1], row[2], row[3], row[4]
        affine = row[8] != 0
        png_write(os.path.join(od, "bg2.png"), 512, 256, render_bg(bgarc[t2], bgarc[m2], bgarc[p2], 64, 32, False), "RGBA")
        n3 = len(bgarc[m3])
        if affine:
            side = {256: 16, 1024: 32, 4096: 64}.get(n3, 32)
            bg3 = render_bg(bgarc[t3], bgarc[m3], bgarc[t3 + 1], side, side, True)
            w3 = side * 8
        else:
            bg3 = render_bg(bgarc[t3], bgarc[m3], bgarc[t3 + 1], 32, 32, False)
            w3 = 256
        png_write(os.path.join(od, "bg3.png"), w3, len(bg3), bg3, "RGBA")
        meta = {"stage": s, "files": paths, "bg_row": list(row), "bg3_affine": affine,
                "objects": len(objs), "textures": len(texs)}
        json.dump(meta, open(os.path.join(od, "stage.json"), "w"), indent=1)
        print(meta, flush=True)


if __name__ == "__main__":
    main()
