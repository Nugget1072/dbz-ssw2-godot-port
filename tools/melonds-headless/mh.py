#!/usr/bin/env python3
"""Python wrapper for libmelonds_headless (frame-exact melonDS 1.1 core).

    from mh import MH
    e = MH(rom, sav)
    e.run(300)                         # 300 frames, no input
    e.press(["Start"], frames=4); e.run(60)
    e.screens().save("x.png")          # 256x384 both screens
    e.u32(0x02000000)                  # RAM reads
    e.save_state("s.mst"); e.load_state("s.mst")
"""
import ctypes, os
from PIL import Image

LIB = os.environ.get("MH_LIB", os.path.join(os.path.dirname(os.path.abspath(__file__)), "libmelonds_headless.so"))
BTN = {"A": 0, "B": 1, "Select": 2, "Start": 3, "Right": 4, "Left": 5, "Up": 6, "Down": 7,
       "R": 8, "L": 9, "X": 10, "Y": 11}


class MH:
    def __init__(self, rom, sav=None, jit=True, verbose=False):
        self.lib = ctypes.CDLL(LIB)
        L = self.lib
        L.mh_init.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
        L.mh_set_input.argtypes = [ctypes.c_uint32, ctypes.c_int, ctypes.c_int, ctypes.c_int]
        L.mh_run_frames.argtypes = [ctypes.c_int]
        L.mh_get_screens.argtypes = [ctypes.c_void_p]
        L.mh_read.argtypes = [ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p]
        L.mh_read32.argtypes = [ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p]
        L.mh_write8.argtypes = [ctypes.c_uint32, ctypes.c_uint8]
        L.mh_savestate.argtypes = [ctypes.c_char_p]
        L.mh_loadstate.argtypes = [ctypes.c_char_p]
        L.mh_audio.argtypes = [ctypes.c_void_p, ctypes.c_int]
        L.mh_verbose(1 if verbose else 0)
        r = L.mh_init(rom.encode(), (sav or "").encode(), 1 if jit else 0)
        if r:
            raise RuntimeError(f"mh_init failed {r}")
        self.frame = 0
        self.audio = bytearray()
        self.capture_audio = False
        # MH_RTC=YYYY-MM-DDTHH:MM:SS (default 2026-01-01T12:00:00) freezes the RTC; MH_RTC=host keeps melonDS's
        rtc = os.environ.get("MH_RTC", "2026-01-01T12:00:00")
        self.rtc = None if rtc == "host" else [int(x) for x in rtc.replace("T", "-").replace(":", "-").split("-")]

    def input(self, buttons=(), touch=None):
        m = 0
        for b in buttons:
            m |= 1 << BTN[b]
        if touch:
            self.lib.mh_set_input(m, 1, int(touch[0]), int(touch[1]))
        else:
            self.lib.mh_set_input(m, 0, 0, 0)

    def run(self, n=1):
        for _ in range(n):
            if self.rtc:   # frozen clock (deterministic: the game seeds its RNGs from the RTC)
                self.lib.mh_set_rtc(*self.rtc)
            self.lib.mh_run_frames(1)
            self.frame += 1
            if self.capture_audio:
                buf = (ctypes.c_int16 * 4096)()
                got = self.lib.mh_audio(buf, 2048)
                self.audio += bytes(buf)[: got * 4]
            else:
                buf = (ctypes.c_int16 * 4096)()
                self.lib.mh_audio(buf, 2048)  # drain

    def press(self, buttons, frames=4, after=0):
        self.input(buttons); self.run(frames); self.input(); self.run(after)

    def touch(self, x, y, frames=4, after=0):
        self.input(touch=(x, y)); self.run(frames); self.input(); self.run(after)

    def screens(self):
        buf = (ctypes.c_uint32 * (256 * 384))()
        self.lib.mh_get_screens(buf)
        im = Image.frombuffer("RGBA", (256, 384), bytes(buf), "raw", "BGRA", 0, 1).convert("RGB")
        return im

    def read(self, addr, n):
        buf = (ctypes.c_uint8 * n)()
        self.lib.mh_read(addr, n, buf)
        return bytes(buf)

    def u8(self, a): return self.read(a, 1)[0]
    def read32(self, addr, words):
        buf = (ctypes.c_uint32 * words)()
        self.lib.mh_read32(addr, words, buf)
        return bytes(buf)

    def dtcm(self):
        buf = (ctypes.c_uint8 * 0x4000)()
        self.lib.mh_dtcm.restype = ctypes.c_uint32
        base = self.lib.mh_dtcm(buf)
        return bytes(buf), base

    def itcm(self):
        buf = (ctypes.c_uint8 * 0x8000)()
        self.lib.mh_itcm(buf)
        return bytes(buf)

    def u16(self, a): return int.from_bytes(self.read(a, 2), "little")
    def u32(self, a): return int.from_bytes(self.read(a, 4), "little")
    def s16(self, a): return int.from_bytes(self.read(a, 2), "little", signed=True)
    def s32(self, a): return int.from_bytes(self.read(a, 4), "little", signed=True)

    def main_ram(self):
        buf = (ctypes.c_uint8 * 0x400000)()
        n = self.lib.mh_main_ram(buf, 0x400000)
        return bytes(buf)[:n]

    def save_state(self, path):
        r = self.lib.mh_savestate(path.encode())
        if r: raise RuntimeError(f"savestate {r}")

    def load_state(self, path):
        r = self.lib.mh_loadstate(path.encode())
        if r: raise RuntimeError(f"loadstate {r}")


def _polys(self):
    """Polygons rendered last frame: list of dict(attr, texparam, texpal, verts=[(cx,cy,cz,cw,s,t,sx,sy,r,g,b)])."""
    buf = (ctypes.c_int32 * 400000)()
    n = self.lib.mh_polys(buf, 400000)
    out, i = [], 0
    while i < n:
        attr, tp, pal, nv = buf[i], buf[i + 1] & 0xFFFFFFFF, buf[i + 2], buf[i + 3]
        i += 4
        vs = [tuple(buf[i + 11 * k: i + 11 * k + 11]) for k in range(nv)]
        i += 11 * nv
        out.append({"attr": attr & 0xFFFFFFFF, "texparam": tp, "texpal": pal, "verts": vs})
    return out


def _vram(self, bank):
    buf = (ctypes.c_uint8 * 0x20000)()
    n = self.lib.mh_vram(bank, buf)
    return bytes(buf)[:n]


MH.polys = _polys
MH.vram = _vram
MH.vramcnt = lambda self, b: self.lib.mh_vramcnt(b)


def _gpu2d(self, engine=0):
    buf = (ctypes.c_int32 * 32)()
    self.lib.mh_gpu2d(engine, buf)
    b = list(buf)
    return {"dispcnt": b[0] & 0xFFFFFFFF, "bgcnt": b[1:5], "hofs": b[5:9], "vofs": b[9:13],
            "xref": b[13:15], "yref": b[15:17], "pa": b[17:19], "pb": b[19:21], "pc": b[21:23], "pd": b[23:25],
            "bldcnt": b[25], "bldalpha": b[26], "evy": b[27]}


MH.gpu2d = _gpu2d


def _lights(self):
    buf = (ctypes.c_int32 * 256)()
    self.lib.mh_lights(buf)
    b = list(buf)
    return {"dir": [b[i * 3:i * 3 + 3] for i in range(4)], "color": [b[12 + i * 3:15 + i * 3] for i in range(4)],
            "diffuse": b[24:27], "ambient": b[27:30], "specular": b[30:33], "emission": b[33:36],
            "specrecip": b[36:40], "use_shine": b[40], "shine": b[41:169], "vecmatrix": b[169:185]}


MH.lights = _lights


def _regs(self):
    buf = (ctypes.c_uint32 * 18)()
    self.lib.mh_arm9_regs(buf)
    return list(buf)


MH.regs = _regs
