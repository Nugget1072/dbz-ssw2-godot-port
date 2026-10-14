# Release notes — draft for the GitHub release

Text to paste into the release page (edit the version / date). Attach the zip from `local/release/` and the four
clips from `local/release/videos/` (both are made by `python tools/test/showcase.py` and the release-zip step in
docs/TESTING.md 35 / HANDOFF part 44; neither is in git).

---

## DBZ Supersonic Warriors 2 — Godot port v1.0

A faithful PC port of *Dragon Ball Z: Supersonic Warriors 2* (Nintendo DS, European cartridge), plus optional
extras. **Bring your own ROM**: the download contains no game data.

### Install
1. Unpack `DBZ_SSW2_Port_v1.0_windows.zip` anywhere (Windows 10/11 x64; Steam Deck / Linux: run the exe with Proton).
2. Put your own dump of the European cartridge (game code ADBP, any file name) next to `DBZ_SSW2_Port.exe`.
3. Run `DBZ_SSW2_Port.exe`. Everything is unlocked. Controls and all options: `README.txt`.

### Highlights
- The whole original game: Story, Z-Battle, Maximum, Free Battle, Practice, Data File — the original program and sound
  driver, checked frame by frame against melonDS.
- Settings in the game's own menu style: window size / full screen, smooth motion up to 240 fps, key and gamepad
  remapping, gamepad mouse cursor, volume, jukebox, camera zoom, detailed shadows, auto skip, damage numbers, input display.
- New gamemodes: ALL-STAR, ENDLESS, BOSS RUSH, TOURNAMENT, with records.
- Local multiplayer (two players on one PC) and LAN play.
- 32 cheats (ULTRA INSTINCT, TIME SKIP, Z-VANISH, RANDOMIZER, BODY CHANGE, HOT POTATO, SMASH KNOCKBACK, DRAGON BALL
  HUNT, …) and three pages of "weird" picture / text effects (Game Boy, CRT TV, mirror mode, EPIC MODE, …).
- Fixes for bugs of the original game (`BUGFIXES.txt`).

### Clips
- `ultra_instinct_kid_gohan_vs_final_boss.mp4` — Kid Gohan parries every blast of Final Boss SSJ Goku's super.
- `time_skip_ssj_goku_vs_frieza.mp4` — SSJ Goku stops Frieza's time and finishes with a Kamehameha.
- `randomizer_krillin_supers.mp4` — Krillin's supers come out as Piccolo's, Broly's and Gotenks'.
- `z_vanish_goku_vs_vegeta.mp4` — Goku and Vegeta trade afterimage dodges mid-combo.

### Known limitations
- The DS wireless VS mode needs a second DS; the port's LAN mode replaces it.
- A few texels differ from a real DS on scaled / rotated 3D quads; screens that load many files can hitch briefly.
- No lag frames while loading (the original drops some).

Not affiliated with or endorsed by the game's developer or publishers or the *Dragon Ball* rights holders.
