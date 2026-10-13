#!/usr/bin/env python3
"""Convert the SDAT sound archive.

usage: convert_sound.py EXTRACT_DIR OUT_ASSETS_DIR
Writes OUT/sound/
  strm/<NAME>.wav       streamed music (IMA-ADPCM -> 16-bit PCM, original rate), loop points in sound.json
  swar/<id>/<n>.wav     every sample of every wave archive (PCM8/PCM16/ADPCM -> 16-bit PCM)
  sbnk/<id>.json        instrument banks (note -> sample, envelope, pan) for the sequencer
  sseq/<id>.bin, ssar/<id>.bin  raw sequence data for the in-game sequencer port
  sound.json            index: names, SEQ/SEQARC/BANK/WAVEARC/STRM info records, loops
Stdlib only.
"""
import json, os, struct, sys, wave
sys.path.insert(0, os.path.dirname(__file__))
import sdat

IMA_STEP = [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88,
            97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658,
            724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660,
            4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818,
            18500, 20350, 22385, 24623, 27086, 29794, 32767]
IMA_IDX = [-1, -1, -1, -1, 2, 4, 6, 8]


def ima_decode(data, nsamples, sample=None, index=None):
    """DS IMA-ADPCM: optional 4-byte header (s16 sample, u8 index); low nibble first."""
    out = []
    p = 0
    if sample is None:
        sample, index = struct.unpack_from("<hB", data, 0)
        p = 4
    step_tab, idx_tab = IMA_STEP, IMA_IDX
    for b in data[p:]:
        for nib in (b & 15, b >> 4):
            if len(out) >= nsamples:
                return out
            step = step_tab[index]
            diff = step >> 3
            if nib & 1: diff += step >> 2
            if nib & 2: diff += step >> 1
            if nib & 4: diff += step
            if nib & 8:
                sample = max(-0x7FFF, sample - diff)
            else:
                sample = min(0x7FFF, sample + diff)
            index = min(88, max(0, index + idx_tab[nib & 7]))
            out.append(sample)
    return out


def write_wav(path, rate, channels):
    n = min(len(c) for c in channels)
    with wave.open(path, "wb") as w:
        w.setnchannels(len(channels))
        w.setsampwidth(2)
        w.setframerate(rate)
        frames = bytearray()
        if len(channels) == 1:
            frames = struct.pack("<%dh" % n, *channels[0][:n])
        else:
            inter = [0] * (n * len(channels))
            for c, ch in enumerate(channels):
                inter[c::len(channels)] = ch[:n]
            frames = struct.pack("<%dh" % len(inter), *inter)
        w.writeframes(frames)


def strm_to_wav(f, path):
    h = 0x10
    enc, loop, ch, _, rate, _, loop_start, nsamp, data_off, nblk, blklen, spb, lastlen, lastspb = \
        struct.unpack_from("<BBBBHHIIIIIIII", f, h + 8)
    data = f[data_off:]
    chans = [[] for _ in range(ch)]
    p = 0
    for b in range(nblk):
        L = lastlen if b == nblk - 1 else blklen
        S = lastspb if b == nblk - 1 else spb
        for c in range(ch):
            blk = data[p:p + L]; p += L
            if enc == 2:
                chans[c] += ima_decode(blk, S)
            elif enc == 1:
                chans[c] += list(struct.unpack_from("<%dh" % (L // 2), blk))
            else:
                chans[c] += [((v ^ 0x80) - 128) << 8 if False else (v - 256 if v > 127 else v) << 8 for v in blk]
    write_wav(path, rate, chans)
    return {"rate": rate, "channels": ch, "samples": nsamp, "loop": bool(loop), "loop_start": loop_start}


def swar_samples(d):
    """SWAV entries of a SWAR file -> list of (rate, loop flag, loop start, samples)"""
    n = struct.unpack_from("<I", d, 0x38)[0]
    out = []
    for i in range(n):
        off = struct.unpack_from("<I", d, 0x3C + 4 * i)[0]
        enc, loop, rate, time, loop_off, nonloop_len = struct.unpack_from("<BBHHHI", d, off)
        body = d[off + 12: off + 12 + (loop_off + nonloop_len) * 4]
        if enc == 0:      # PCM8
            s = [(v - 256 if v > 127 else v) << 8 for v in body]
            ls = loop_off * 4
        elif enc == 1:    # PCM16
            s = list(struct.unpack_from("<%dh" % (len(body) // 2), body)); ls = loop_off * 2
        else:             # IMA-ADPCM with 4-byte header (counted in loop_off words)
            s = ima_decode(body, (len(body) - 4) * 2); ls = max(0, (loop_off - 1) * 8)
        out.append({"rate": rate, "loop": bool(loop), "loop_start": ls, "enc": enc, "samples": s})
    return out


def sbnk_json(d):
    """Instrument bank: records (type, offset) -> instruments with note ranges, sample refs, ADSR, pan."""
    n = struct.unpack_from("<I", d, 0x38)[0]
    insts = []

    def note_def(p):
        swav, swar, base, a, dcy, s, r, pan = struct.unpack_from("<HHBBBBBB", d, p)
        return {"swav": swav, "swar": swar, "note": base, "attack": a, "decay": dcy, "sustain": s, "release": r, "pan": pan}

    for i in range(n):
        rec = struct.unpack_from("<I", d, 0x3C + 4 * i)[0]
        kind, off = rec & 0xFF, rec >> 8
        if kind == 0:
            insts.append(None)
        elif kind in (1, 2, 3, 4, 5):   # single (PCM / PSG / noise)
            insts.append({"type": kind, "regions": [dict(lo=0, hi=127, **note_def(off))]})
        elif kind == 16:                # drum set: lo, hi, then (u16 type, def) per note
            lo, hi = d[off], d[off + 1]
            regs = []
            for k in range(hi - lo + 1):
                p = off + 2 + k * 12
                regs.append(dict(lo=lo + k, hi=lo + k, **note_def(p + 2)))
            insts.append({"type": 16, "regions": regs})
        elif kind == 17:                # key split: 8 upper bounds then defs
            bounds = list(d[off:off + 8])
            regs = []
            lo = 0
            p = off + 8
            for hb in bounds:
                if hb == 0: break
                regs.append(dict(lo=lo, hi=hb, **note_def(p + 2)))
                lo = hb + 1
                p += 12
            insts.append({"type": 17, "regions": regs})
        else:
            insts.append({"type": kind, "regions": []})
    return insts


def main():
    ext, out = sys.argv[1], sys.argv[2]
    s = sdat.SDAT(open(os.path.join(ext, "fs/romdata/sound/sound_data.sdat"), "rb").read())
    od = os.path.join(out, "sound")
    for sub in ("strm", "swar", "sbnk", "sseq", "ssar"):
        os.makedirs(os.path.join(od, sub), exist_ok=True)
    ip = os.path.join(od, "sound.json")
    old = json.load(open(ip)) if os.path.exists(ip) else {}
    index = {"info": s.info, "symbols": s.symbols, "strm": old.get("strm", {}), "swar": old.get("swar", {})}
    only = set(a for a in sys.argv[3:])
    for i, r in enumerate(s.info["STRM"]):
        if r is None: continue
        name = s.symbols["STRM"][i] or f"STRM_{i}"
        if only and "strm" not in only and name not in only: continue
        meta = strm_to_wav(s.file(r["file"]), os.path.join(od, "strm", name + ".wav"))
        index["strm"][name] = meta
        print("STRM", name, meta, flush=True)
    if not only or "swar" in only:
        for i, r in enumerate(s.info["WAVEARC"]):
            if r is None: continue
            wd = os.path.join(od, "swar", str(i))
            os.makedirs(wd, exist_ok=True)
            metas = []
            for k, smp in enumerate(swar_samples(s.file(r["file"]))):
                write_wav(os.path.join(wd, f"{k}.wav"), smp["rate"], [smp["samples"]])
                metas.append({kk: v for kk, v in smp.items() if kk != "samples"} | {"length": len(smp["samples"])})
            index["swar"][str(i)] = metas
        print("SWAR", len(index["swar"]), flush=True)
    if not only or "seq" in only:
        for i, r in enumerate(s.info["BANK"]):
            if r is None: continue
            json.dump({"wavearcs": r["wavearcs"], "instruments": sbnk_json(s.file(r["file"]))},
                      open(os.path.join(od, "sbnk", f"{i}.json"), "w"))
        for i, r in enumerate(s.info["SEQ"]):
            if r is None: continue
            open(os.path.join(od, "sseq", f"{i}.bin"), "wb").write(s.file(r["file"]))
        for i, r in enumerate(s.info["SEQARC"]):
            if r is None: continue
            open(os.path.join(od, "ssar", f"{i}.bin"), "wb").write(s.file(r["file"]))
    json.dump(index, open(os.path.join(od, "sound.json"), "w"))
    print("sound ->", od)


if __name__ == "__main__":
    main()
