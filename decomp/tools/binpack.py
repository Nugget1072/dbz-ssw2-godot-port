#!/usr/bin/env python3
"""Named .bin resource packs (title/Title.bin, game/result.bin, scene/...).

Layout (H, verified on all 120+ packs):
  0x00 u8 version (3 or 4), u8 flags (0/2/0x7f), u16 entry count N
  0x04 u32 header size (data starts here)
  0x08 N x 0x4C-byte entries:
        char name[64]   (e.g. "logo\\logo.ntft"; Windows path separators)
        u32  unpacked size
        u32  stored size   (== unpacked when not compressed)
        u32  offset from header end
  Stored data that is smaller than the unpacked size is DS-BIOS compressed (LZ10/LZ11/RLE/Huffman).
"""
import struct, sys, os
sys.path.insert(0, os.path.dirname(__file__))
import ndscomp


def is_pack(d):
    if len(d) < 8 or d[0] not in (3, 4):
        return False
    n = struct.unpack_from("<H", d, 2)[0]
    hs = struct.unpack_from("<I", d, 4)[0]
    return n > 0 and hs == 8 + n * 0x4C and hs <= len(d)


def read(d):
    n = struct.unpack_from("<H", d, 2)[0]
    hs = struct.unpack_from("<I", d, 4)[0]
    out = []
    for i in range(n):
        e = 8 + i * 0x4C
        name = d[e:e + 64].split(b"\0")[0].decode("latin-1").replace("\\", "/")
        usize, ssize, off = struct.unpack_from("<3I", d, e + 64)
        raw = d[hs + off: hs + off + ssize]
        if ssize != usize and ndscomp.is_compressed(raw):
            data = ndscomp.decompress(raw)
        else:
            data = raw
        out.append((name, data, ssize != usize))
    return out


if __name__ == "__main__":
    for name, data, comp in read(open(sys.argv[1], "rb").read()):
        print(f"{name:40s} {len(data):7d} {'C' if comp else ' '} {data[:8].hex()}")
