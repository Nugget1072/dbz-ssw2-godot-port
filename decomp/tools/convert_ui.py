#!/usr/bin/env python3
"""Convert 2D UI resources (BG tiles/maps/palettes and 3D-quad UI textures) for the Godot port.

usage: convert_ui.py EXTRACT_DIR OUT_ASSETS_DIR
Writes OUT/ui/...  Formats:
  *_tiles.png  L8 strip 8 x (n*8): one 8x8 tile per 8 rows, texel = colour index
  *_pal.png    RGBA 16 x 16: row r = 16-colour palette r (for 8bpp: the 256 colours row-major)
  *_map.bin    raw u16 map entries, linear (w x h tiles)
  *.png        RGBA for textures drawn as orthographic 3D quads on the DS
See DATA_NOTES.md "Battle HUD".
"""
import os, struct, sys
sys.path.insert(0, os.path.dirname(__file__))
import garc
from convert_chara import png_write


def bgr555(c):
    return ((c & 31) * 255 // 31, ((c >> 5) & 31) * 255 // 31, ((c >> 10) & 31) * 255 // 31)


def tiles_png(path, data, bpp):
    tb = 8 * bpp
    n = len(data) // tb
    rows = []
    for t in range(n):
        for y in range(8):
            if bpp == 4:
                b = data[t * 32 + y * 4: t * 32 + y * 4 + 4]
                rows.append(bytes(v for x in b for v in (x & 15, x >> 4)))
            else:
                rows.append(bytes(data[t * 64 + y * 8: t * 64 + y * 8 + 8]))
    png_write(path, 8, len(rows), rows, "L")
    return n


def pal_png(path, rows_data):
    """rows_data: dict row -> bytes (32 bytes per 16-colour row; longer data fills following rows)"""
    grid = [[(0, 0, 0, 0)] * 16 for _ in range(16)]
    for r0, data in rows_data.items():
        for i in range(len(data) // 2):
            r, c = r0 + i // 16, i % 16
            if r < 16:
                grid[r][c] = bgr555(struct.unpack_from("<H", data, 2 * i)[0]) + (255,)
    png_write(path, 16, 16, [bytes(v for px in row for v in px) for row in grid], "RGBA")


def tex_png(path, data, pal, w, h, bpp, c0_transparent=True):
    rows = []
    for y in range(h):
        row = bytearray()
        for x in range(w):
            i = y * w + x
            v = (data[i // 2] >> (4 * (i & 1))) & 15 if bpp == 4 else data[i]
            if v == 0 and c0_transparent:
                row += b"\0\0\0\0"
            else:
                row += bytes(bgr555(struct.unpack_from("<H", pal, 2 * v)[0])) + b"\xff"
        rows.append(bytes(row))
    png_write(path, w, h, rows, "RGBA")


def map_bin(path, data, w=32, h=32):
    """Write a linear map. DS maps wider than 32 tiles are stored as 32x32 blocks."""
    out = bytearray()
    for y in range(h):
        for x in range(w):
            blk = (x // 32) + (y // 32) * max(1, w // 32)
            idx = blk * 1024 + (y % 32) * 32 + (x % 32)
            out += data[idx * 2: idx * 2 + 2] if idx * 2 + 2 <= len(data) else b"\0\0"
    open(path, "wb").write(bytes(out))


def battle_hud(ext, out):
    od = os.path.join(out, "ui", "battle")
    os.makedirs(od, exist_ok=True)
    bg = garc.read(open(os.path.join(ext, "fs/romdata/game/game_bg.arc"), "rb").read())
    # BG1 (priority 0, above the 3D layer): HUD frame, timer and ki digits. Map entries use palette 15.
    tiles_png(os.path.join(od, "bg1_tiles.png"), bg[0], 4)
    pal_png(os.path.join(od, "bg1_pal.png"), {15: bg[1]})
    map_bin(os.path.join(od, "bg1_map.bin"), bg[2])
    # 3D quads: health bar (128x16, 256 colours, pal #5) and red damage bar (64x8, 16 colours, pal #3).
    # The life bar is a palette gauge: row 2 holds one colour index per column (16..86); the game recolours
    # those palette entries every frame (yellow = life left, 0x3484 dark blue = lost). Kept indexed.
    png_write(os.path.join(od, "bar_life_idx.png"), 128, 16, [bytes(bg[6][y * 128:(y + 1) * 128]) for y in range(16)], "L")
    pal_png(os.path.join(od, "bar_life_pal.png"), {0: bg[5]})
    tex_png(os.path.join(od, "bar_damage.png"), bg[4], bg[3], 64, 8, 4)
    fi = garc.read(open(os.path.join(ext, "fs/romdata/game/game_faceicon.arc"), "rb").read())
    for cid in range(len(fi) // 2):
        tex_png(os.path.join(od, f"face_{cid:02d}.png"), fi[2 * cid], fi[2 * cid + 1], 32, 32, 4)
    print("battle HUD ->", od)


def main():
    ext, out = sys.argv[1], sys.argv[2]
    battle_hud(ext, out)


if __name__ == "__main__":
    main()
