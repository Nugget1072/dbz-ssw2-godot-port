#!/usr/bin/env python3
"""One-shot asset build: ROM -> decomp/extract -> GodotGame/new-game-project/assets.

usage (from anywhere):  python decomp/tools/build_all.py [--rom PATH] [--only step,step]
Steps: extract, chara, stage, ui, raw, sound, text   (each is skipped if its converter is missing)
Stdlib only.
"""
import argparse, glob, importlib, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rom", default=None)
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    # the player's ROM: baseroms/ (original layout) or finished/ (part 21: the user keeps it next to the exe)
    rom = a.rom or (glob.glob(os.path.join(ROOT, "baseroms", "*.nds")) + glob.glob(os.path.join(ROOT, "finished", "*.nds")) or [None])[0]
    if not rom:
        sys.exit("No .nds found in baseroms/ or finished/")
    ext = os.path.join(ROOT, "decomp", "extract")
    assets = os.path.join(ROOT, "GodotGame", "new-game-project", "assets")
    only = set(filter(None, a.only.split(",")))

    def want(s):
        return not only or s in only

    t0 = time.time()
    if want("extract"):
        import nds_extract
        nds_extract.extract(rom, ext)
    steps = [("chara", "convert_chara"), ("stage", "convert_stage"), ("ui", "convert_ui"), ("raw", "convert_packs"),
             ("sound", "convert_sound"), ("text", "convert_text")]
    for name, mod in steps:
        if not want(name):
            continue
        if not os.path.exists(os.path.join(HERE, mod + ".py")):
            print(f"[{name}] converter not written yet, skipped")
            continue
        print(f"[{name}] ...", flush=True)
        m = importlib.import_module(mod)
        sys.argv = [mod + ".py", ext, assets]
        m.main()
    # the completed save (100Save/*.sav: player progress, no game content) is built into the exported game as
    # res://data/save100.sav so a fresh copy starts with everything unlocked
    sav = sorted(glob.glob(os.path.join(ROOT, "100Save", "*.sav")))   # (100Save/ removed in part 21: the copy in
    if sav:                                                             #  data/save100.sav is kept as it is)
        data = os.path.join(ROOT, "GodotGame", "new-game-project", "data")
        os.makedirs(data, exist_ok=True)
        with open(sav[0], "rb") as f, open(os.path.join(data, "save100.sav"), "wb") as g:
            g.write(f.read())
    # the ROM is never built into the game: the exported exe looks for the player's ROM in its own folder
    stale = os.path.join(ROOT, "GodotGame", "new-game-project", "data", "game.nds")
    if os.path.exists(stale):
        os.remove(stale)
    os.makedirs(assets, exist_ok=True)
    # keep the Godot editor from importing/compressing ROM assets; the game loads them at runtime
    open(os.path.join(assets, ".gdignore"), "w").close()
    print(f"done in {time.time() - t0:.1f}s -> {assets}")


if __name__ == "__main__":
    main()
