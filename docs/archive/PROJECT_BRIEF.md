# Project Brief: Dragon Ball Z Supersonic Warriors 2 → Godot 4 port

*This is the improved, detailed version of the original task prompt. Work from this file. The original prompt is quoted at the bottom.*

## Role
You are a senior game developer and reverse engineer. Your job is to decompile/decode **Dragon Ball Z: Supersonic Warriors 2** (Nintendo DS) and rebuild it as a faithful, native **Godot 4.7** game. After the faithful port works, add quality-of-life features (first one: single-screen layout instead of DS dual screens).

## Source material (the user's own dump)
| Item | Value |
|---|---|
| ROM | `baseroms/Dragon Ball Z - Supersonic Warriors 2.nds` — **European release**, game code `ADBP`, maker `B2` (Bandai), 64 MiB |
| SHA-1 | `a85a5fb193b4ff293a99248e7dc986b62f71a332` |
| Save | `baseroms/Dragon Ball Z - Supersonic Warriors 2.sav` (8 KiB EEPROM) — useful for unlocked-character reference shots |
| Code | ARM9 0xDD8F8 bytes @ 0x02000000 (entry 0x02000800), ARM7 0x27778 bytes, **no overlays** |
| Files | 304 NitroFS files under `romdata/` (chara, charselect, game, scene, sound, title, opening, option, …) |

The baseroms folder is **read-only input**. Never modify it; never download ROMs or keys from anywhere.

## Folder layout (everything lives in `SupersonicMain`)
```
SupersonicMain/
  docs/PROJECT_BRIEF.md   this file (the improved prompt)
  CLAUDE.md               short, strict rules + how to run/test (read every session)
  HANDOFF.md              living state: done / in progress / next step
  WORK_OUTSIDE_FOLDER.txt anything that had to happen outside this folder
  docs/ROM_REMIX_ONBOARDING.md methodology reference (follow where it applies; this is NOT a mash-up)
  baseroms/               the dump (read-only, git-ignored)
  tools/                  Godot 4.7.2, Python 3.14.8, melonDS 1.1 (Windows) + any added tools/configs
  decomp/
    tools/                Python converters, one per format, stdlib-only so they run on any Python ≥3.10
    DATA_NOTES.md         knowledge base: every format/table decoded, with offsets + confidence H/M/L
    notes/                per-area working notes
    extract/              raw NitroFS dump + decoded intermediates (git-ignored, regenerable)
  reference/              melonDS reference screenshots (ground truth for accuracy checks)
  GodotGame/new-game-project/   the Godot project (assets/ inside is generated + git-ignored)
```

## Deliverables, in order
1. **Scaffolding**: this brief, `CLAUDE.md`, `HANDOFF.md`, git repo with a `.gitignore` that excludes ROMs, extracted and converted assets.
2. **Toolchain**: melonDS configured with keyboard controls; scripted (headless) emulator runs that produce reference screenshots; Godot runnable headless for imports, parse checks and screenshot "pilots".
3. **Decoding pipeline** (`decomp/tools`): NitroFS extraction → container formats (`GARC` archives, the named `.bin` packs holding NITRO raw `nbfc/nbfp/nbfs/ntft/ntfp` data, NCER-style cell data) → PNG sprite sheets/atlases + JSON frame/cell data → stage backgrounds → SDAT audio (SSEQ/SBNK/SWAR/STRM) to WAV/OGG → text/fonts. Each converter is rerunnable and writes a sidecar JSON. Every converter's output is rendered and *looked at* before it's called done.
4. **Rules extraction**: character stats, move data (damage, ki cost, hitboxes, frame timings) from `charadata.arc` and the ARM9 code (disassembled with Capstone), into JSON with notes.
5. **Godot vertical slice** (first milestone): title screen → mode/character select → stage → one playable 1v1 battle using the real sprites, stage, HUD, sounds and music, at the DS's 256×192-per-screen native resolution with nearest-neighbour scaling.
6. **Accuracy verification**: side-by-side melonDS vs Godot screenshots for each screen built, diffed and inspected; differences logged and fixed.
7. **Later milestones** (documented, not this session): all characters/stages, Story/Z-Battle/Challenge modes, save data, AI, then QoL: single-screen layout, rebindable controls, widescreen, resolution scaling.

## Accuracy standard
- **Verbatim assets.** Use the ROM's own pixels, palettes, animations, timings, sounds and music. No redrawn or invented substitutes; if something isn't decoded yet, show an obvious debug placeholder and log it.
- **Native timing.** The DS runs at ~59.83 Hz; game logic runs at a fixed 60 ticks/s in Godot (`physics_ticks_per_second=60`) so frame data maps 1:1.
- **Native resolution.** Each DS screen is 256×192. The faithful mode renders both screens (256×384 stacked); the QoL single-screen mode is a feature flag.
- **Proof, not claims.** A screen counts as "accurate" only after a side-by-side comparison with a melonDS capture of the same moment. Confidence for every decoded fact is labelled H/M/L in `DATA_NOTES.md`.

## Testing
- Godot "pilots" (see onboarding §8): `-- pilot=<name> shots=<dir>` runs scripted input, saves screenshots, prints `PILOT PASS/FAIL`.
- Headless parse checks of every `.gd` file before reporting work done.
- melonDS reference captures are scripted and reproducible (input script + frame number → PNG).

## Constraints
- All work and outputs stay inside `SupersonicMain` and its subfolders. Anything that must happen elsewhere (e.g. cloud sandbox used for Linux builds of Godot/melonDS) is recorded in `WORK_OUTSIDE_FOLDER.txt`.
- Extra tools go in `tools/` when possible.
- Keep it personal: no publishing of the ROM, extracted assets or builds. Code, converters and notes are the user's own work.
- Python converters use only the standard library so they run on the bundled Python 3.14 (Windows) and on Linux.

---
### Original prompt (for reference)
> You are a senior game developer and you have been tasked with porting Dragon Ball Z Supersonic Warriors 2 from the Nintendo DS to Godot. You have been given a folder at "SupersonicMain"… "tools" has Godot v4.7.2, Python v3.14.8, and melonDS v1.1, all unconfigured… "baseroms" holds the game… "GodotGame" is an empty Godot project… "ROM_REMIX_ONBOARDING.md" has valuable information to follow when applicable (this is a single-game port, not a mash-up)… If you need other tools, keep them in tools… Check your work against the original, preferably via melonDS screenshots… All work must be in SupersonicMain; anything outside must be documented in a standalone text file. Before you start, improve this prompt to be more detailed, then work from that.
