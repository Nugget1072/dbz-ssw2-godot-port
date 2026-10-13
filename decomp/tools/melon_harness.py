#!/usr/bin/env python3
"""melonDS automation harness (Linux/Xvfb).

Drives the melonDS Qt window with XTest key/mouse events and grabs exact
256x192 DS screen captures, so reference screenshots of the original game are
scriptable and reproducible.

Usage as a library:
    from melon_harness import Melon
    m = Melon(rom); m.wait(8); m.tap('Start'); m.shot('reference/title.png')

Usage as CLI with a script file (one command per line):
    wait 6.0            # seconds
    tap A               # press+release a DS button (A B X Y L R Start Select Up Down Left Right)
    hold Right 0.5      # hold a button for N seconds
    touch 128 96        # tap the bottom screen at DS coords
    shot name           # save top/bottom/both PNGs as <outdir>/<name>_{top,bot,both}.png
    savestate 1 / loadstate 1   # Shift+F1 / F1
    ff on|off           # hold/release fast-forward (Tab)

    python3 melon_harness.py ROM SCRIPT OUTDIR

Environment: needs an X display (Xvfb :99), melonDS AppImage extracted, the
libOpenGL shim on LD_LIBRARY_PATH, and ~/.config/melonDS/melonDS.toml with the
keyboard map from tools/melonDS-config/melonDS.toml.
"""
import ctypes, ctypes.util, os, subprocess, sys, time

MELON = os.environ.get("MELON_BIN", "/home/claude/tools/squashfs-root/AppRun")
DISPLAY = os.environ.get("DISPLAY", ":99")

# DS button -> X keysym, matching the keyboard map in melonDS.toml
KEYSYM = {
    "A": 0x78, "B": 0x7A, "X": 0x73, "Y": 0x61, "L": 0x71, "R": 0x77,
    "Start": 0xFF0D, "Select": 0xFF08,
    "Left": 0xFF51, "Up": 0xFF52, "Right": 0xFF53, "Down": 0xFF54,
    "FF": 0xFF09, "Shift": 0xFFE1,
    **{f"F{i}": 0xFFBE + i - 1 for i in range(1, 9)},
}

x11 = ctypes.cdll.LoadLibrary("libX11.so.6")
xtst = ctypes.cdll.LoadLibrary("libXtst.so.6")
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
x11.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
x11.XFlush.argtypes = [ctypes.c_void_p]
xtst.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeButtonEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeMotionEvent.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]

# Screen placement inside the X root (window at 0,0, Qt menubar on top).
# Calibrated by find_screens(); override with MELON_TOP_Y if the layout changes.
SCREEN_X = 0
TOP_Y = int(os.environ.get("MELON_TOP_Y", "20"))


class Melon:
    def __init__(self, rom, env_extra=None, log="/tmp/melon_harness.log"):
        env = dict(os.environ, DISPLAY=DISPLAY)
        env.setdefault("LD_LIBRARY_PATH", "/home/claude/tools/shim")
        env.update(env_extra or {})
        self.proc = subprocess.Popen([MELON, rom], env=env, stdout=open(log, "w"), stderr=subprocess.STDOUT)
        self.dpy = x11.XOpenDisplay(DISPLAY.encode())
        if not self.dpy:
            raise RuntimeError("cannot open X display " + DISPLAY)
        time.sleep(2.0)
        self._focus()

    def _focus(self):
        # No window manager under Xvfb: click inside the window so Qt takes focus.
        self.click_root(128, 10, button=0)

    # ---------------- input ----------------
    def key(self, name, down):
        kc = x11.XKeysymToKeycode(self.dpy, KEYSYM[name])
        xtst.XTestFakeKeyEvent(self.dpy, kc, 1 if down else 0, 0)
        x11.XFlush(self.dpy)

    def tap(self, name, secs=0.08):
        self.key(name, True); time.sleep(secs); self.key(name, False); time.sleep(0.05)

    def hold(self, name, secs):
        self.tap(name, secs)

    def click_root(self, x, y, button=1, secs=0.08):
        xtst.XTestFakeMotionEvent(self.dpy, -1, int(x), int(y), 0)
        x11.XFlush(self.dpy)
        if button:
            xtst.XTestFakeButtonEvent(self.dpy, button, 1, 0); x11.XFlush(self.dpy)
            time.sleep(secs)
            xtst.XTestFakeButtonEvent(self.dpy, button, 0, 0); x11.XFlush(self.dpy)
        time.sleep(0.05)

    def touch(self, x, y, secs=0.1):
        self.click_root(SCREEN_X + x, TOP_Y + 192 + y, 1, secs)

    def savestate(self, slot):
        self.key("Shift", True); self.tap(f"F{slot}"); self.key("Shift", False)

    def loadstate(self, slot):
        self.tap(f"F{slot}")

    def wait(self, secs):
        time.sleep(secs)

    # ---------------- capture ----------------
    def grab(self):
        from PIL import Image
        raw = subprocess.run(["import", "-display", DISPLAY, "-window", "root", "png:-"],
                             capture_output=True, check=True).stdout
        import io
        return Image.open(io.BytesIO(raw)).convert("RGB")

    def shot(self, path_base):
        img = self.grab()
        both = img.crop((SCREEN_X, TOP_Y, SCREEN_X + 256, TOP_Y + 384))
        os.makedirs(os.path.dirname(path_base) or ".", exist_ok=True)
        both.save(path_base + "_both.png")
        both.crop((0, 0, 256, 192)).save(path_base + "_top.png")
        both.crop((0, 192, 256, 384)).save(path_base + "_bot.png")
        return both

    def close(self):
        self.proc.terminate()
        try:
            self.proc.wait(5)
        except subprocess.TimeoutExpired:
            self.proc.kill()


def do_line(m, line, outdir):
    line = line.split("#", 1)[0].strip()
    if not line:
        return
    op, *a = line.split()
    if op == "wait": m.wait(float(a[0]))
    elif op == "tap": m.tap(a[0], float(a[1]) if len(a) > 1 else 0.08)
    elif op == "hold": m.hold(a[0], float(a[1]))
    elif op == "touch": m.touch(int(a[0]), int(a[1]))
    elif op == "shot": m.shot(os.path.join(outdir, a[0])); print("shot", a[0], flush=True)
    elif op == "savestate": m.savestate(int(a[0]))
    elif op == "loadstate": m.loadstate(int(a[0]))
    elif op == "ff": m.key("FF", a[0] == "on")
    elif op == "keydown": m.key(a[0], True)
    elif op == "keyup": m.key(a[0], False)
    else: raise ValueError("unknown op " + op)


def run_script(rom, script, outdir):
    m = Melon(rom)
    try:
        for raw in open(script):
            do_line(m, raw, outdir)
    finally:
        m.close()


def serve(rom, sock_path, outdir):
    """Keep melonDS running; accept command lines on a UNIX socket (see melon_client)."""
    import socket
    m = Melon(rom)
    if os.path.exists(sock_path):
        os.unlink(sock_path)
    srv = socket.socket(socket.AF_UNIX); srv.bind(sock_path); srv.listen(1)
    try:
        while True:
            c, _ = srv.accept()
            data = c.recv(65536).decode()
            if data.strip() == "quit":
                c.sendall(b"bye"); c.close(); break
            try:
                for line in data.splitlines():
                    do_line(m, line, outdir)
                c.sendall(b"ok")
            except Exception as e:  # report and keep serving
                c.sendall(("err " + repr(e)).encode())
            c.close()
    finally:
        m.close()


if __name__ == "__main__":
    if sys.argv[1] == "serve":
        serve(sys.argv[2], sys.argv[3], sys.argv[4])
    elif sys.argv[1] == "send":
        import socket
        c = socket.socket(socket.AF_UNIX); c.connect(sys.argv[2])
        c.sendall("\n".join(sys.argv[3:]).encode()); print(c.recv(4096).decode())
    else:
        run_script(sys.argv[1], sys.argv[2], sys.argv[3])
