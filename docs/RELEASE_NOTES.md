# Release notes — draft for the GitHub release

Text of the GitHub release (edit the version / date). Attach the zip from `local/release/` (HANDOFF part 44: exe + dll +
the three texts, written with Python's zipfile; not in git).

---

## DBZ Supersonic Warriors 2 — Godot port v1.0

A faithful PC port of *Dragon Ball Z: Supersonic Warriors 2* (Nintendo DS, European cartridge), plus optional
extras. **Bring your own ROM**: the download contains no game data.

### Install
1. Unpack `DBZ_SSW2_Port_v1.0_windows.zip` anywhere (Windows 10/11 x64; Steam Deck / Linux: run the exe with Proton).
   (The same files are also offered one by one: put the exe, the DLL and the .txt files in one folder.)
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

### Known limitations
- The DS wireless VS mode needs a second DS; the port's LAN mode replaces it.
- A few texels differ from a real DS on scaled / rotated 3D quads; screens that load many files can hitch briefly.
- No lag frames while loading (the original drops some).

Not affiliated with or endorsed by the game's developer or publishers or the *Dragon Ball* rights holders.
