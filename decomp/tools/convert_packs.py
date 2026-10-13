#!/usr/bin/env python3
"""Dump every named .bin pack member and every GARC entry of the UI archives as raw, decompressed files,
so the Godot side can compose screens at runtime exactly like the game does (map entries, tile bases,
palette rows are applied in code, see scripts/ui/*.gd).

usage: convert_packs.py EXTRACT_DIR OUT_ASSETS_DIR
Writes OUT/raw/<romdata path without .bin>/<member name>   e.g. raw/charselect/SubScrNBFC/gkn.nbfc
       OUT/raw/<romdata path without .arc>/<index>.bin     e.g. raw/game/game_bg/102.bin
Language variants: only the EU/EN members are needed by the EU build, but all are kept (small).
"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
import binpack, garc, ndscomp

GARC_DIRS = ("game", "title", "opening", "modeselect", "charselect", "stageselect", "option", "data", "scene", "credit")


def main():
    ext, out = sys.argv[1], sys.argv[2]
    fs = os.path.join(ext, "fs", "romdata")
    n_files = n_members = 0
    for root, _, files in os.walk(fs):
        for f in sorted(files):
            p = os.path.join(root, f)
            rel = os.path.relpath(p, fs)
            d = open(p, "rb").read()
            if f.endswith(".bin") and binpack.is_pack(d):
                od = os.path.join(out, "raw", rel[:-4])
                os.makedirs(od, exist_ok=True)
                for name, data, _ in binpack.read(d):
                    dst = os.path.join(od, name)
                    os.makedirs(os.path.dirname(dst), exist_ok=True)
                    open(dst, "wb").write(data)
                    n_members += 1
                n_files += 1
            elif f.endswith(".arc") and d[:4] == b"GARC" and rel.split(os.sep)[0] in GARC_DIRS:
                od = os.path.join(out, "raw", rel[:-4])
                os.makedirs(od, exist_ok=True)
                for i, data in enumerate(garc.read(d)):   # UI GARC entries are stored uncompressed
                    open(os.path.join(od, f"{i}.bin"), "wb").write(data)
                    n_members += 1
                n_files += 1
    print(f"raw packs: {n_files} files, {n_members} members -> {os.path.join(out, 'raw')}")


if __name__ == "__main__":
    main()
