#!/usr/bin/env python3
"""Nintendo DS BIOS-style decompressors: LZ77 (0x10), LZ11 (0x11), RLE (0x30), Huffman (0x24/0x28).
Stdlib only. decompress(data) dispatches on the type byte."""
import struct


def size_of(d):
    return d[1] | d[2] << 8 | d[3] << 16


def lz10(d):
    size, out, p = size_of(d), bytearray(), 4
    while len(out) < size:
        flags = d[p]; p += 1
        for bit in range(8):
            if len(out) >= size:
                break
            if flags & (0x80 >> bit):
                b1, b2 = d[p], d[p + 1]; p += 2
                n, disp = (b1 >> 4) + 3, ((b1 & 0xF) << 8 | b2) + 1
                for _ in range(n):
                    out.append(out[-disp])
            else:
                out.append(d[p]); p += 1
    return bytes(out)


def lz11(d):
    size, out, p = size_of(d), bytearray(), 4
    while len(out) < size:
        flags = d[p]; p += 1
        for bit in range(8):
            if len(out) >= size:
                break
            if flags & (0x80 >> bit):
                b = d[p]; ind = b >> 4
                if ind == 0:
                    n = ((b & 0xF) << 4 | d[p + 1] >> 4) + 0x11
                    disp = ((d[p + 1] & 0xF) << 8 | d[p + 2]) + 1; p += 3
                elif ind == 1:
                    n = ((b & 0xF) << 12 | d[p + 1] << 4 | d[p + 2] >> 4) + 0x111
                    disp = ((d[p + 2] & 0xF) << 8 | d[p + 3]) + 1; p += 4
                else:
                    n = ind + 1
                    disp = ((b & 0xF) << 8 | d[p + 1]) + 1; p += 2
                for _ in range(n):
                    out.append(out[-disp])
            else:
                out.append(d[p]); p += 1
    return bytes(out)


def rle(d):
    size, out, p = size_of(d), bytearray(), 4
    while len(out) < size:
        f = d[p]; p += 1
        if f & 0x80:
            out += bytes([d[p]]) * ((f & 0x7F) + 3); p += 1
        else:
            n = (f & 0x7F) + 1
            out += d[p:p + n]; p += n
    return bytes(out[:size])


def huffman(d):
    bits = d[0] & 0xF
    size = size_of(d)
    tree_size = (d[4] + 1) * 2
    tree = 4  # tree root at offset 5; node table starts at 4
    p = 4 + tree_size
    out = bytearray(); cur = 0; nbits = 0
    acc = 0
    node = 5; data_bits = []
    while len(out) < size:
        word = struct.unpack_from("<I", d, p)[0]; p += 4
        for i in range(32):
            bit = (word >> (31 - i)) & 1
            v = d[node]
            off = (v & 0x3F)
            nxt = (node & ~1) + off * 2 + 2
            is_leaf = v & (0x40 if bit else 0x80) if False else (v & (0x80 >> bit))
            node = nxt + bit
            if is_leaf:
                acc |= d[node] << nbits; nbits += bits
                node = 5
                if nbits == 8:
                    out.append(acc & 0xFF); acc = 0; nbits = 0
                    if len(out) >= size:
                        break
    return bytes(out)


def decompress(d):
    t = d[0]
    if t == 0x10: return lz10(d)
    if t == 0x11: return lz11(d)
    if t == 0x30: return rle(d)
    if t in (0x24, 0x28): return huffman(d)
    raise ValueError("unknown compression type %02x" % t)


def is_compressed(d):
    return len(d) >= 4 and d[0] in (0x10, 0x11, 0x30, 0x24, 0x28)
