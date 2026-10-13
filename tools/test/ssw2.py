#!/usr/bin/env python3
"""ssw2.py - portable test harness for the DBZ SSW2 Godot port (Windows and Linux, Python 3.8+, stdlib only).

Written in part 35 so Claude Code (or a person) can run every routine check from inside SupersonicMain.
Run from anywhere:  python tools/test/ssw2.py <command> ...
On Windows with the bundled Python:  tools\\Python3.14.8\\python.exe tools\\test\\ssw2.py <command> ...

Commands
  env                         show the detected Godot / ROM / save / output paths
  parse FILE...               parse-check GDScript files (res:// paths or paths under the project)
  import                      re-import the project (needed after adding a class file)
  run NAME [opts] [-- FLAGS]  play the game with scripted inputs and captures -> local/runs/NAME/ (+ NAME.log)
        --every N --from F --to T   capture every N frames from F to T (quits after T)
        --inputs "F:Key:len,..."     input script (see docs/DEBUG_FLAGS.md "inputs=")
        --battle                     prepend the standard Free Battle path (Goku vs Goku, control from ~4540)
        --cfg FILE                   settings file (default: a fresh one per run, so your settings.cfg is not used)
        --headless                   no window / no captures (logic-only runs, fastest)
  offcheck [--battle] [--intro] [--tag TAG]
                              the off-identity check every change must pass (both parts when no option is given):
                              battle = 21 PNGs (frames 4300..5300 step 50) + the `CHT f` lines up to frame 5300,
                              intro = 221 PNGs (frames 10..2210 step 10). The CHT lines are machine-independent;
                              PNGs are compared with the baselines of the same machine/GPU (TAG, default = this OS).
  baseline [--tag TAG]        record the baselines from the CURRENT code (do it once on a known-good state, before
                              changing anything) -> local/baselines/TAG/
  pngdiff DIR_A DIR_B         pixel-compare same-named p<frame>.png captures of two runs
  export                      export the Windows release build into finished/ and copy README / BUGFIXES

Everything this tool writes goes under local/ (git-ignored: captures are ROM-derived pictures).
Environment overrides: GODOT (Godot 4.7.2 binary; on Windows the *_console.exe), ROM, SAV, SSW2_OUT.
"""
import os, sys, subprocess, shutil, glob, zlib, struct, time, platform, argparse

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROJ = os.path.join(REPO, "GodotGame", "new-game-project")
LOCAL = os.environ.get("SSW2_OUT", os.path.join(REPO, "local"))
IS_WIN = os.name == "nt"

# The Free Battle path used by every battle baseline (mode select -> Free Battle -> Goku vs Goku -> fight).
BATTLE_PATH = ("2141:Start:4,2396:T128/120:6,2560:Right:4,2590:Right:4,2620:Down:4,2660:A:4,2810:A:4,2870:Start:4,"
               "2960:A:4,3020:A:4,3080:Start:4,3170:A:4,3330:A:4")
BATTLE_ACTIONS = ("4300:A:4,4400:B:4,4500:B:40,4600:X:4,4700:Y:4,4800:L:40,4900:R:40,5000:Select:4,5100:Start:4,"
                  "5200:Start:4,5300:Right:20,5400:X:30,5500:R+A:4,5600:R+B:4,5700:R+Y:4,5800:Up+Y:4,5900:Down+Y:4")
RTC = "rtc=2026-01-01T12:00:00"


def default_tag():
    return "windows" if IS_WIN else ("linux-llvmpipe" if not os.environ.get("SSW2_GPU") else "linux-gpu")


def find_godot():
    g = os.environ.get("GODOT")
    if g:
        return g
    if IS_WIN:
        d = os.path.join(REPO, "tools", "Godot_v4.7.2-stable_win64.exe")
        for n in ("Godot_v4.7.2-stable_win64_console.exe", "Godot_v4.7.2-stable_win64.exe"):
            if os.path.exists(os.path.join(d, n)):
                return os.path.join(d, n)
    return shutil.which("godot") or shutil.which("godot4") or "godot"


def find_rom():
    r = os.environ.get("ROM")
    if r:
        return r
    c = sorted(glob.glob(os.path.join(REPO, "finished", "*.nds")))
    return c[0] if c else ""


def find_sav():
    s = os.environ.get("SAV")
    if s:
        return s
    p = os.path.join(PROJ, "data", "save100.sav")
    return p if os.path.exists(p) else ""


def godot_cmd(windowed=True):
    cmd = [find_godot(), "--path", PROJ]
    if not windowed:
        cmd.insert(1, "--headless")
    elif not IS_WIN:
        cmd += ["--rendering-driver", "opengl3"]
        if not os.environ.get("DISPLAY") and shutil.which("xvfb-run"):
            cmd = ["xvfb-run", "-a"] + cmd
    return cmd


def run_game(name, every=0, frm=1, to=0, inputs="", flags=(), cfg=None, headless=False, quit_at=None, timeout=3600):
    if not os.path.isdir(os.path.join(PROJ, ".godot")):      # first run on this machine: import the project once
        subprocess.run(godot_cmd(False) + ["--import"], cwd=PROJ)
    os.makedirs(os.path.join(LOCAL, "runs"), exist_ok=True)
    d = os.path.join(LOCAL, "runs", name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    rom, sav = find_rom(), find_sav()
    if not rom:
        sys.exit("no ROM found: put the user's dump in finished/ (any .nds name) or set ROM=")
    tmp_sav = d + ".sav"
    if sav:
        shutil.copy(sav, tmp_sav)
        os.chmod(tmp_sav, 0o644)
    args = ["nds=" + rom, "sav=" + tmp_sav, "save=" + tmp_sav, RTC, "qolcfg=" + (cfg or d + ".cfg")]
    if every and to and not headless:
        args += ["capture=" + d, "cap_every=%d" % every, "cap_from=%d" % frm, "cap_to=%d" % to]
    if quit_at or (headless and to):
        args.append("quit_at=%d" % (quit_at or to))
    if inputs:
        args.append("inputs=" + inputs)
    args += list(flags)
    cmd = godot_cmd(not headless) + ["res://scenes/GameDS.tscn", "--"] + args
    t0 = time.time()
    with open(d + ".log", "w", encoding="utf-8", errors="replace") as log:
        try:
            subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, timeout=timeout, cwd=PROJ)
        except subprocess.TimeoutExpired:
            log.write("\nssw2.py: TIMEOUT after %d s\n" % timeout)
    if os.path.exists(tmp_sav):
        os.remove(tmp_sav)
    n = len(glob.glob(os.path.join(d, "p*.png")))
    errs = [l.rstrip() for l in open(d + ".log", encoding="utf-8", errors="replace")
            if "SCRIPT ERROR" in l or "Parse Error" in l or "game stopped" in l][:10]
    print("%s: %d captures, %.0f s, log %s.log" % (name, n, time.time() - t0, d))
    for e in errs:
        print("  " + e)
    return d


# ---- PNG decoding (stdlib only) -------------------------------------------------------------------------------------
def png_pixels(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG: " + path)
    pos, idat, w = 8, [], 0
    while pos < len(data):
        ln, typ = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
            if depth != 8 or ctype not in (2, 6):
                raise ValueError("unsupported PNG format in " + path)
            bpp = 3 if ctype == 2 else 4
        elif typ == b"IDAT":
            idat.append(body)
        pos += 12 + ln
    raw = zlib.decompress(b"".join(idat))
    stride = w * bpp
    out, prev, i = bytearray(), bytearray(stride), 0
    for _ in range(h):
        f = raw[i]; line = bytearray(raw[i + 1:i + 1 + stride]); i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        out += line; prev = line
    if bpp == 4:   # compare RGB only
        out = bytearray(v for k, v in enumerate(out) if k % 4 != 3)
    return w, h, bytes(out)


def same_png(a, b):
    if open(a, "rb").read() == open(b, "rb").read():
        return 0
    wa, ha, pa = png_pixels(a)
    wb, hb, pb = png_pixels(b)
    if (wa, ha) != (wb, hb):
        return -1
    return sum(1 for k in range(0, len(pa), 3) if pa[k:k + 3] != pb[k:k + 3])


def cmp_dirs(a, b, frames=None):
    names = sorted(os.path.basename(p) for p in glob.glob(os.path.join(b, "p*.png")))
    if frames is not None:
        names = ["p%d.png" % f for f in frames]
    same, diff, missing = 0, [], []
    for n in names:
        pa, pb = os.path.join(a, n), os.path.join(b, n)
        if not (os.path.exists(pa) and os.path.exists(pb)):
            missing.append(n); continue
        d = same_png(pa, pb)
        if d == 0: same += 1
        else: diff.append((n, d))
    return same, diff, missing


def cht_lines(log, upto=5300):
    out = []
    for l in open(log, encoding="utf-8", errors="replace"):
        if l.startswith("CHT f"):
            try:
                f = int(l.split()[1][1:])
            except ValueError:
                continue
            if f <= upto:
                out.append(l.rstrip("\n"))
    return out


# ---- the standard runs ------------------------------------------------------------------------------------------------
BATTLE_FRAMES = list(range(4300, 5301, 50))
INTRO_FRAMES = list(range(10, 2211, 10))


def battle_run(name):
    return run_game(name, every=50, frm=4300, to=5300, quit_at=5301, inputs=BATTLE_PATH + "," + BATTLE_ACTIONS,
                    flags=["cheatdbg", "cheats=infinite_health"])


def intro_run(name):
    return run_game(name, every=10, frm=10, to=2210)


def cmd_baseline(a):
    dst = os.path.join(LOCAL, "baselines", a.tag)
    os.makedirs(dst, exist_ok=True)
    d = battle_run("baseline_battle")
    shutil.rmtree(os.path.join(dst, "battle"), ignore_errors=True)
    shutil.copytree(d, os.path.join(dst, "battle"))
    open(os.path.join(dst, "battle_cht.txt"), "w").write("\n".join(cht_lines(d + ".log")) + "\n")
    d = intro_run("baseline_intro")
    shutil.rmtree(os.path.join(dst, "intro"), ignore_errors=True)
    shutil.copytree(d, os.path.join(dst, "intro"))
    print("baselines recorded in", dst)


def cmd_offcheck(a):
    both = not a.battle and not a.intro
    base = os.path.join(LOCAL, "baselines", a.tag)
    ok = True
    if a.battle or both:
        d = battle_run("off_battle")
        same, diff, miss = cmp_dirs(d, os.path.join(base, "battle"), BATTLE_FRAMES)
        print("battle PNGs: %d/%d identical%s" % (same, len(BATTLE_FRAMES), "" if not diff else "  DIFF " + str(diff[:8])))
        if miss:
            print("  missing:", miss[:5], "(no baseline for tag %s? run `baseline --tag %s` on a known-good state)" % (a.tag, a.tag))
        ok &= same == len(BATTLE_FRAMES)
        mine = cht_lines(d + ".log")
        ref_file = None
        for t in [a.tag] + [os.path.basename(p) for p in glob.glob(os.path.join(LOCAL, "baselines", "*"))]:
            f = os.path.join(LOCAL, "baselines", t, "battle_cht.txt")
            if os.path.exists(f):
                ref_file = f; break
        if ref_file:
            ref = [l for l in open(ref_file).read().splitlines() if l]
            first = next((i for i, (x, y) in enumerate(zip(mine, ref)) if x != y), None)
            if mine == ref:
                print("CHT lines: %d identical (%s)" % (len(ref), ref_file))
            else:
                ok = False
                print("CHT lines DIFFER (%d vs %d), first difference at line %s" % (len(mine), len(ref), first))
                if first is not None:
                    print("  mine:", mine[first]); print("  ref: ", ref[first])
        else:
            ok = False; print("no battle_cht.txt baseline found")
    if a.intro or both:
        d = intro_run("off_intro")
        same, diff, miss = cmp_dirs(d, os.path.join(base, "intro"), INTRO_FRAMES)
        print("intro PNGs: %d/%d identical%s" % (same, len(INTRO_FRAMES), "" if not diff else "  DIFF " + str(diff[:8])))
        ok &= same == len(INTRO_FRAMES)
    print("OFF-IDENTITY:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


def cmd_parse(a):
    files = [f if f.startswith("res://") else "res://" + os.path.relpath(os.path.abspath(f), PROJ).replace("\\", "/")
             for f in a.files]
    return subprocess.run(godot_cmd(False) + ["--script", "res://parsecheck.gd", "--"] + files, cwd=PROJ).returncode


def cmd_export(a):
    r = subprocess.run(godot_cmd(False) + ["--import"], cwd=PROJ).returncode
    r = subprocess.run(godot_cmd(False) + ["--export-release", "Windows Desktop"], cwd=PROJ).returncode or r
    for s, t in (("PLAYER_README.txt", "README.txt"), ("BUGFIXES.txt", "BUGFIXES.txt")):
        shutil.copy(os.path.join(REPO, "docs", s), os.path.join(REPO, "finished", t))
    print("export finished with code", r, "->", os.path.join(REPO, "finished"))
    return r


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = p.add_subparsers(dest="cmd")
    sp.add_parser("env")
    q = sp.add_parser("parse"); q.add_argument("files", nargs="+")
    sp.add_parser("import")
    q = sp.add_parser("run"); q.add_argument("name")
    q.add_argument("--every", type=int, default=0); q.add_argument("--from", dest="frm", type=int, default=1)
    q.add_argument("--to", type=int, default=0); q.add_argument("--inputs", default="")
    q.add_argument("--battle", action="store_true"); q.add_argument("--cfg"); q.add_argument("--headless", action="store_true")
    q.add_argument("flags", nargs="*")
    q = sp.add_parser("offcheck"); q.add_argument("--battle", action="store_true"); q.add_argument("--intro", action="store_true")
    q.add_argument("--tag", default=default_tag())
    q = sp.add_parser("baseline"); q.add_argument("--tag", default=default_tag())
    q = sp.add_parser("pngdiff"); q.add_argument("a"); q.add_argument("b")
    sp.add_parser("export")
    a = p.parse_args()
    if a.cmd == "env":
        print("REPO ", REPO); print("PROJ ", PROJ); print("GODOT", find_godot()); print("ROM  ", find_rom() or "(none)")
        print("SAV  ", find_sav() or "(none)"); print("OUT  ", LOCAL); print("TAG  ", default_tag())
        print("baselines:", ", ".join(os.listdir(os.path.join(LOCAL, "baselines"))) if os.path.isdir(os.path.join(LOCAL, "baselines")) else "(none)")
    elif a.cmd == "parse":
        return cmd_parse(a)
    elif a.cmd == "import":
        return subprocess.run(godot_cmd(False) + ["--import"], cwd=PROJ).returncode
    elif a.cmd == "run":
        inp = a.inputs
        if a.battle:
            inp = BATTLE_PATH + ("," + inp if inp else "")
        run_game(a.name, a.every, a.frm, a.to, inp, a.flags, a.cfg, a.headless)
    elif a.cmd == "offcheck":
        return cmd_offcheck(a)
    elif a.cmd == "baseline":
        cmd_baseline(a)
    elif a.cmd == "pngdiff":
        same, diff, miss = cmp_dirs(a.a, a.b)
        print("identical %d, different %d %s, missing %d" % (same, len(diff), diff[:10], len(miss)))
    elif a.cmd == "export":
        return cmd_export(a)
    else:
        p.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main() or 0)
