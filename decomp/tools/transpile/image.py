# Memory image of the binary being translated (ARM9 by default; TARGET=arm7 for the ARM7 binary).
# Segments are (load address, bytes, is_code). The ARM7 binary is split into its crt0 (0x02380000) and the two
# autoload segments its crt0 copies at boot: 0x037F8000 (WRAM) and 0x027E0000 (main RAM), see run7.sh.
import os, struct

TARGET = os.environ.get("TARGET", "arm9")


def segments():
    if TARGET == "arm7":
        d = os.environ.get("ARM7_DIR", "ext7")
        return [(0x02380000, open(f"{d}/crt0.bin", "rb").read(), True),
                (0x037F8000, open(f"{d}/wram.bin", "rb").read(), True),
                (0x027E0000, open(f"{d}/mram.bin", "rb").read(), True)]
    arm9 = open("ext/arm9.bin", "rb").read()
    return [(0x02000000, arm9[:0xB7000], True), (0x01FF8000, arm9[0xDD4C0:0xDD4C0 + 0x3C0], True)]


SEGS = None


def _segs():
    global SEGS
    if SEGS is None:
        SEGS = segments()
    return SEGS


def word(a):
    for base, data, _ in _segs():
        if base <= a and a + 4 <= base + len(data):
            return struct.unpack_from("<I", data, a - base)[0]
    return None


def in_code(a):
    return any(base <= a < base + len(data) for base, data, code in _segs() if code)
