# melonds-headless

Frame-exact, scriptable melonDS 1.1 core used as ground truth for the port (GPLv3 like melonDS).

**License / source:** `libmelonds_headless.so` is melonDS 1.1 (GPL-3.0, (c) the melonDS team,
https://melonds.kuribo64.net) linked with `melonds_headless.cpp` (also GPL-3.0). It is built by `build.sh` from the
unmodified upstream source, tag `1.1` of https://github.com/melonDS-emu/melonDS. This test tool is separate from the
game: the port itself contains no melonDS code.

- `melonds_headless.cpp` — tiny C API over the melonDS core (init, set input, run frames, read screens/RAM, savestates, audio)
- `build.sh` — builds `libmelonds_headless.so` on Linux
- `mh.py` — Python wrapper (`MH(rom, sav)`, `.run(n)`, `.press([...])`, `.touch(x,y)`, `.screens()`, `.u32(addr)`, `.save_state()`)
- `mhs.py` — command-line runner: `mhs.py ROM SAV IN_STATE OUT_STATE SHOTDIR run:60 press:A:6 touch:212:80 shot:name`

Savestates used for references live in `reference/states/` (title, modeselect, charselect, stageselect, battle_start,
battle_ready). They are melonDS savestates; the Windows melonDS app can load them too (File → Load state from file)
as long as the same ROM is loaded.

`../../decomp/tools/melon_harness.py` is the alternative that drives the real melonDS GUI under Xvfb (XTest keys +
screen grabs); used for the first captures before the headless core existed.
