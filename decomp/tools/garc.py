#!/usr/bin/env python3
"""GARC archive reader (DBZ SSW2's own container, not the 3DS GARC).

Layout (H = verified on all 77 chara/*.arc + game/*.arc):
  0x00 'GARC'
  0x04 u32 total file size
  0x08 u32 entry count N
  0x0C u32 data start (= 0x10 + 8*N, padded)
  0x10 N x {u32 offset (relative to data start), u32 size}
"""
import struct, sys


def read(data):
    assert data[:4] == b"GARC", "not a GARC"
    total, n, base = struct.unpack_from("<3I", data, 4)
    out = []
    for i in range(n):
        o, s = struct.unpack_from("<2I", data, 0x10 + 8 * i)
        out.append(data[base + o: base + o + s])
    return out


if __name__ == "__main__":
    d = open(sys.argv[1], "rb").read()
    for i, e in enumerate(read(d)):
        print(i, len(e), e[:16].hex())
