#!/usr/bin/env python3
"""Nintendo SDAT (sound archive) reader: symbols, INFO records, FAT, files.
Formats per the public Nitro sound documentation (kiwi.ds / VGMTrans / 'sdattool' notes)."""
import struct, sys

INFO_KINDS = ["SEQ", "SEQARC", "BANK", "WAVEARC", "PLAYER", "GROUP", "PLAYER2", "STRM"]


class SDAT:
    def __init__(self, d):
        assert d[:4] == b"SDAT"
        self.d = d
        symb_off, symb_size, info_off, info_size, fat_off, fat_size, file_off, file_size = struct.unpack_from("<8I", d, 0x10)
        self.fat = []
        n = struct.unpack_from("<I", d, fat_off + 8)[0]
        for i in range(n):
            o, s = struct.unpack_from("<2I", d, fat_off + 12 + 16 * i)
            self.fat.append((o, s))
        self.symbols = {k: [] for k in INFO_KINDS}
        if symb_off:
            for k, kind in enumerate(INFO_KINDS):
                rec = struct.unpack_from("<I", d, symb_off + 8 + 4 * k)[0]
                if not rec: continue
                if kind in ("SEQARC",):
                    cnt = struct.unpack_from("<I", d, symb_off + rec)[0]
                    for i in range(cnt):
                        no, so = struct.unpack_from("<2I", d, symb_off + rec + 4 + 8 * i)
                        self.symbols[kind].append(self._str(symb_off + no) if no else None)
                else:
                    cnt = struct.unpack_from("<I", d, symb_off + rec)[0]
                    for i in range(cnt):
                        no = struct.unpack_from("<I", d, symb_off + rec + 4 + 4 * i)[0]
                        self.symbols[kind].append(self._str(symb_off + no) if no else None)
        self.info = {k: [] for k in INFO_KINDS}
        for k, kind in enumerate(INFO_KINDS):
            rec = struct.unpack_from("<I", d, info_off + 8 + 4 * k)[0]
            cnt = struct.unpack_from("<I", d, info_off + rec)[0]
            for i in range(cnt):
                eo = struct.unpack_from("<I", d, info_off + rec + 4 + 4 * i)[0]
                if not eo:
                    self.info[kind].append(None); continue
                p = info_off + eo
                if kind == "SEQ":
                    fid, unk, bank, vol, cpr, ppr, ply = struct.unpack_from("<HHHBBBB", d, p)
                    self.info[kind].append(dict(file=fid, bank=bank, vol=vol, cpr=cpr, ppr=ppr, player=ply))
                elif kind == "SEQARC":
                    fid, = struct.unpack_from("<H", d, p); self.info[kind].append(dict(file=fid))
                elif kind == "BANK":
                    fid, unk, w0, w1, w2, w3 = struct.unpack_from("<HH4H", d, p)
                    self.info[kind].append(dict(file=fid, wavearcs=[w0, w1, w2, w3]))
                elif kind == "WAVEARC":
                    fid, = struct.unpack_from("<H", d, p); self.info[kind].append(dict(file=fid))
                elif kind == "STRM":
                    fid, unk, vol, pri, ply = struct.unpack_from("<HHBBB", d, p)
                    self.info[kind].append(dict(file=fid, vol=vol, pri=pri, player=ply))
                else:
                    self.info[kind].append(dict(raw=d[p:p + 8].hex()))

    def _str(self, o):
        return self.d[o:self.d.index(b"\0", o)].decode("latin-1")

    def file(self, fid):
        o, s = self.fat[fid]
        return self.d[o:o + s]


if __name__ == "__main__":
    s = SDAT(open(sys.argv[1], "rb").read())
    for k in INFO_KINDS:
        print(k, len(s.info[k]), "named" if any(s.symbols[k]) else "")
    for k in ("SEQ", "STRM", "SEQARC", "BANK", "WAVEARC"):
        for i, r in enumerate(s.info[k][:400]):
            if r is None: continue
            nm = s.symbols[k][i] if i < len(s.symbols[k]) else None
            print(k, i, nm, r, s.file(r["file"])[:4] if "file" in r else "")
