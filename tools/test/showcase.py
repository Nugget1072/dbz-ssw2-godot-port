#!/usr/bin/env python3
"""showcase.py - record the cheat showcase clips (part 44) with the test harness.

Each clip is a scripted, deterministic battle (BOSS RUSH with one enemy: `bossrush=1 brorder=<enemy> asp1=<player 1>`),
captured every frame with its sound (`ssw2.py run --every 1`) and encoded by `ssw2.py clip` (needs ffmpeg with libx264
+ aac on PATH or FFMPEG=). Output: local/release/videos/*.mp4 (git-ignored: game footage).
  python tools/test/showcase.py [NAME ...]        (default: all; names below)
Player 1's inputs are real button presses (no auto-parry / auto-vanish flags). Where noted, player 2's input is
scripted with `p2keys` (the boss's super) or held still (a training dummy for RANDOMIZER); RNG seeds pick the
cheat's random outcomes. The frame numbers depend on the battle path in ssw2.py (BATTLE_PATH); docs/TESTING.md 35.
"""
import os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SSW2 = [sys.executable, os.path.join(HERE, "ssw2.py")]
OUT = os.path.join(os.environ.get("SSW2_OUT", os.path.join(HERE, "..", "..", "local")), "release", "videos")


def keys(*groups):
    return ",".join(e for g in groups for e in g)


def every(start, step, n, key, hold):
    return ["%d:%s:%d" % (start + i * step, key, hold) for i in range(n)]


CLIPS = {
    # Kid Gohan (24) vs Final Boss SSJ Goku (1, boss level 3). The boss flies up (p2 Up) and does his X+A super from
    # above: ten huge blasts; Gohan taps B 2 frames before each (and before the boss's melee hits), then counters
    # with his own super (a 16-hit rush). Log: 12 "UI f... PARRY", 0 MISS, Gohan 10000/10000 HP throughout.
    "ultra_instinct": dict(
        out="ultra_instinct_kid_gohan_vs_final_boss.mp4", frm=4090, to=5260, clip=(4100, 5150),
        inputs=keys(["%d:B:3" % f for f in (4262, 4360, 4377, 4394, 4411, 4427, 4444, 4461, 4479, 4516, 4533, 4689)],
                    ["4706:X+A:8"]),
        flags=["brorder=1", "asp1=24", "cheats=ultra_instinct", "uidbg", "p2keys=4300:40:30,4334:401:10"]),
    # SSJ Goku (1) vs Boss Frieza (10): SELECT stops Frieza's time as he closes in, a 6-hit rush on the frozen enemy,
    # then X+A (a super ends the skip early): the Kamehameha lands as time runs again (22 hits).
    "time_skip": dict(
        out="time_skip_ssj_goku_vs_frieza.mp4", frm=4050, to=4440, clip=(4056, 4430),
        inputs=keys(["4128:Select:4"], every(4136, 9, 12, "Y", 4), ["4246:X+A:8"]),
        flags=["brorder=10", "asp1=1", "cheats=time_skip", "tsdbg"]),
    # Krillin (4) vs Boss Ginyu (12) held still (p2 holds Down): three supers with ki charges in between;
    # rzseed=1 picks Piccolo, Broly, Gotenks.
    "randomizer": dict(
        out="randomizer_krillin_supers.mp4", frm=4080, to=5000, clip=(4120, 4990),
        inputs="4140:X+A:8,4330:R:90,4430:X+A:8,4650:R:90,4750:X+A:8",
        flags=["brorder=12", "asp1=4", "cheats=randomizer", "p2keys=4000:80:1500", "rzseed=1"]),
    # Goku (0) vs Boss Vegeta (6): Goku vanishes out of Vegeta's first hit and combos him; the CPU vanishes back
    # twice (its 30 % chance, zvseed=3), Goku keeps attacking (Y / B taps).
    "z_vanish": dict(
        out="z_vanish_goku_vs_vegeta.mp4", frm=4050, to=4440, clip=(4060, 4320),
        inputs=keys(["4112:B:2"], every(4116, 9, 7, "Y", 4), every(4180, 6, 3, "B", 2),
                    [e for i in range(25) for e in ("%d:Y:3" % (4200 + i * 9), "%d:B:2" % (4204 + i * 9))]),
        flags=["brorder=6", "asp1=0", "cheats=z_vanish", "zvdbg", "zvseed=3"]),
}


def main():
    names = sys.argv[1:] or list(CLIPS)
    for n in names:
        c = CLIPS[n]
        run = "show_" + n
        subprocess.run(SSW2 + ["run", run, "--battle", "--every", "1", "--from", str(c["frm"]), "--to", str(c["to"]),
                               "--inputs", c["inputs"], "allstar=1", "bossrush=1", "cheatdbg"] + c["flags"], check=True)
        subprocess.run(SSW2 + ["clip", run, "--from", str(c["clip"][0]), "--to", str(c["clip"][1]),
                               "--out", os.path.join(OUT, c["out"])], check=True)


if __name__ == "__main__":
    main()
