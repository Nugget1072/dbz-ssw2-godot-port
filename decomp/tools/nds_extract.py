#!/usr/bin/env python3
"""Extract the NitroFS file system, ARM9/ARM7 binaries and header from an .nds ROM.

usage: python nds_extract.py ROM OUTDIR
Writes OUTDIR/fs/<path>, OUTDIR/arm9.bin, OUTDIR/arm7.bin, OUTDIR/header.bin, OUTDIR/files.json
Stdlib only.
"""
import json, os, struct, sys


def extract(rom_path, out):
    rom = open(rom_path, "rb").read()
    fnt, _, fat, _ = struct.unpack_from("<4I", rom, 0x40)
    a9o, a9e, a9r, a9s = struct.unpack_from("<4I", rom, 0x20)
    a7o, a7e, a7r, a7s = struct.unpack_from("<4I", rom, 0x30)
    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, "header.bin"), "wb").write(rom[:0x200])
    open(os.path.join(out, "arm9.bin"), "wb").write(rom[a9o:a9o + a9s])
    open(os.path.join(out, "arm7.bin"), "wb").write(rom[a7o:a7o + a7s])
    files = []

    def walk(dir_id, path):
        sub, fid, _ = struct.unpack_from("<IHH", rom, fnt + (dir_id & 0xFFF) * 8)
        p = fnt + sub
        while True:
            t = rom[p]; p += 1
            if t == 0:
                break
            name = rom[p:p + (t & 0x7F)].decode("ascii", "replace"); p += t & 0x7F
            if t & 0x80:
                (sid,) = struct.unpack_from("<H", rom, p); p += 2
                walk(sid, path + name + "/")
            else:
                s, e = struct.unpack_from("<2I", rom, fat + fid * 8)
                dst = os.path.join(out, "fs", path + name)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                open(dst, "wb").write(rom[s:e])
                files.append({"id": fid, "path": path + name, "offset": s, "size": e - s,
                              "magic": rom[s:s + 4].hex()})
                fid += 1

    walk(0xF000, "")
    meta = {"title": rom[0:12].decode(), "gamecode": rom[12:16].decode(),
            "arm9": {"rom_offset": a9o, "entry": a9e, "ram": a9r, "size": a9s},
            "arm7": {"rom_offset": a7o, "entry": a7e, "ram": a7r, "size": a7s},
            "files": files}
    json.dump(meta, open(os.path.join(out, "files.json"), "w"), indent=1)
    print(f"{meta['title']} {meta['gamecode']}: {len(files)} files -> {out}")


if __name__ == "__main__":
    extract(sys.argv[1], sys.argv[2])
