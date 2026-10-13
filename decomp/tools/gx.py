#!/usr/bin/env python3
"""Nintendo DS GX geometry-command (display list) decoder -> triangles.

Handles the packed command format (one word holding up to 4 command ids, followed by their
parameters). Produces primitives with position (float, 4.12 fixed -> /4096), texcoord
(1.11.4 fixed -> texels), normal, vertex colour, and the TEXIMAGE_PARAM / PLTT_BASE / POLYGON_ATTR
state active when each primitive was begun.
"""
import struct

NPARAMS = {
    0x00: 0, 0x10: 1, 0x11: 0, 0x12: 1, 0x13: 1, 0x14: 1, 0x15: 0, 0x16: 16, 0x17: 12, 0x18: 16,
    0x19: 12, 0x1A: 9, 0x1B: 3, 0x1C: 3, 0x20: 1, 0x21: 1, 0x22: 1, 0x23: 2, 0x24: 1, 0x25: 1,
    0x26: 1, 0x27: 1, 0x28: 1, 0x29: 1, 0x2A: 1, 0x2B: 1, 0x30: 1, 0x31: 1, 0x32: 1, 0x33: 1,
    0x34: 32, 0x40: 1, 0x41: 0, 0x50: 1, 0x60: 1, 0x70: 3, 0x71: 2, 0x72: 1,
}


def s(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


def bgr555(c):
    return ((c & 31) / 31.0, ((c >> 5) & 31) / 31.0, ((c >> 10) & 31) / 31.0)


def decode(dl):
    """Returns (prims, stats). prim = dict(mode, verts=[{pos,uv,nrm,col}], tex, pltt, polyattr)."""
    words = struct.unpack_from("<%dI" % (len(dl) // 4), dl)
    i = 0
    prims, stats = [], {}
    cur = None
    pos = [0.0, 0.0, 0.0]
    uv = (0.0, 0.0)
    nrm = (0.0, 0.0, 1.0)
    col = (1.0, 1.0, 1.0)
    tex = pltt = 0
    polyattr = 0
    scale = [1.0, 1.0, 1.0]
    trans = [0.0, 0.0, 0.0]

    def emit():
        p = [pos[k] * scale[k] + trans[k] for k in range(3)]
        cur["verts"].append({"pos": p, "uv": uv, "nrm": nrm, "col": col})

    while i < len(words):
        cmds = [(words[i] >> (8 * k)) & 0xFF for k in range(4)]
        i += 1
        for c in cmds:
            n = NPARAMS.get(c)
            if n is None:
                raise ValueError(f"unknown GX command {c:#x} at word {i}")
            p = words[i:i + n]
            i += n
            stats[c] = stats.get(c, 0) + 1
            if c == 0x40:
                cur = {"mode": p[0] & 3, "verts": [], "tex": tex, "pltt": pltt, "polyattr": polyattr}
                prims.append(cur)
            elif c == 0x41:
                cur = None
            elif c == 0x20:
                col = bgr555(p[0])
            elif c == 0x21:
                nrm = (s(p[0], 10) / 512.0, s(p[0] >> 10, 10) / 512.0, s(p[0] >> 20, 10) / 512.0)
            elif c == 0x22:
                uv = (s(p[0], 16) / 16.0, s(p[0] >> 16, 16) / 16.0)
            elif c == 0x23:
                pos = [s(p[0], 16) / 4096.0, s(p[0] >> 16, 16) / 4096.0, s(p[1], 16) / 4096.0]
                emit()
            elif c == 0x24:
                pos = [s(p[0], 10) / 64.0, s(p[0] >> 10, 10) / 64.0, s(p[0] >> 20, 10) / 64.0]
                emit()
            elif c == 0x25:
                pos = [s(p[0], 16) / 4096.0, s(p[0] >> 16, 16) / 4096.0, pos[2]]; emit()
            elif c == 0x26:
                pos = [s(p[0], 16) / 4096.0, pos[1], s(p[0] >> 16, 16) / 4096.0]; emit()
            elif c == 0x27:
                pos = [pos[0], s(p[0], 16) / 4096.0, s(p[0] >> 16, 16) / 4096.0]; emit()
            elif c == 0x28:
                pos = [pos[0] + s(p[0], 10) / 4096.0, pos[1] + s(p[0] >> 10, 10) / 4096.0,
                       pos[2] + s(p[0] >> 20, 10) / 4096.0]  # VTX_DIFF: 1/4096 units (verified vs emulator)
                emit()
            elif c == 0x29:
                polyattr = p[0]
            elif c == 0x2A:
                tex = p[0]
            elif c == 0x2B:
                pltt = p[0]
            elif c == 0x1B:
                scale = [s(v, 32) / 4096.0 for v in p]
            elif c == 0x1C:
                trans = [trans[k] + s(p[k], 32) / 4096.0 * scale[k] for k in range(3)]
            elif c == 0x15:
                scale, trans = [1.0, 1.0, 1.0], [0.0, 0.0, 0.0]
    return prims, stats


def triangles(prim):
    """Expand a primitive to a list of vertex triples (counter-clockwise as the DS sees them)."""
    v, m, out = prim["verts"], prim["mode"], []
    if m == 0:
        out = [(v[k], v[k + 1], v[k + 2]) for k in range(0, len(v) - 2, 3)]
    elif m == 1:
        for k in range(0, len(v) - 3, 4):
            out += [(v[k], v[k + 1], v[k + 2]), (v[k], v[k + 2], v[k + 3])]
    elif m == 2:
        for k in range(len(v) - 2):
            out.append((v[k], v[k + 1], v[k + 2]) if k % 2 == 0 else (v[k + 1], v[k], v[k + 2]))
    elif m == 3:
        for k in range(0, len(v) - 3, 2):
            a, b, c, d = v[k], v[k + 1], v[k + 2], v[k + 3]
            out += [(a, b, d), (a, d, c)]
    return out


def ds_light(nrm, light_dir=(0, 256, 512), light_col=(31, 31, 31), dif=(18, 18, 18), amb=(18, 18, 18),
             spe=(28, 28, 28), emi=(0, 0, 0), spec_recip=256):
    """Bit-exact DS vertex lighting for one light with an identity vector matrix (after melonDS
    GPU3D::CalculateLighting). nrm = floats as decoded (1.0.9 / 512). Returns (r,g,b) 0..31."""
    n = [int(round(c * 512)) for c in nrm]
    nt = [((v * 4096) << 9) >> 21 for v in n]      # VecMatrix identity (4096) -> 1.0.10 normal
    buf = [e << 14 for e in emi]
    dot = sum((light_dir[k] * nt[k]) >> 9 for k in range(3))
    if dot > 0:
        dd = ((dot << 21) & 0xFFFFFFFF)
        dd = (dd - (1 << 32) if dd & (1 << 31) else dd) >> 21
        for k in range(3):
            buf[k] += (dif[k] * light_col[k] * dd) & 0xFFFFF
        d2 = dot + nt[2]
        d2 = ((d2 << 21) & 0xFFFFFFFF)
        d2 = (d2 - (1 << 32) if d2 & (1 << 31) else d2) >> 21
        d2 = ((d2 * d2) >> 10) & 0x3FF
        shine = ((d2 * spec_recip) >> 8) - (1 << 9)
        if shine < 0:
            shine = 0
        else:
            shine = ((shine << 18) & 0xFFFFFFFF)
            shine = (shine - (1 << 32) if shine & (1 << 31) else shine) >> 18
            shine = 0 if shine < 0 else min(shine, 0x1FF)
    else:
        shine = 0
    for k in range(3):
        buf[k] += ((spe[k] * shine) + (amb[k] << 9)) * light_col[k]
    return tuple(min(31, b >> 14) for b in buf)
