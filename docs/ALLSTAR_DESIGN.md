# NEW GAMEMODES / ALL-STAR — design (part 34 research)

Research for the NEW GAMEMODES setting and its first mode, ALL-STAR. Facts with addresses and evidence are in
`decomp/DATA_NOTES.md` "## Session 1 part 34 findings (All-Star research)"; this file is the plan. Evidence runs:
`/tmp/ssw2/as34/` (`run.sh NAME EVERY FROM TO "inputs" [flags]`; sheets `*_sheet.png`, layer sweeps `*_layers.png`).
Confidence: V = seen in a port run (capture / probe), C = code read (Ghidra C / disassembly), M = reasoned, to verify.

## 0. Summary

| Piece | Reuse | Hook |
|---|---|---|
| Setting NEW GAMEMODES | BIG CHANGES page (`mpset`) row, `QoLSettings.new_gamemodes` ([game] or [mp]-like section) | QoLMenu / QoLSettings |
| GAMEMODE tile | Mode Select tile 5 (FREE BATTLE) texture at slot 0 + 0x5000, rewritten like `QoLButton` | new `QoLGamemodeTile` (or a QoLButton variant); `f_02075738` redirect |
| Gamemode menu | MAXIMUM's course select = scene 0xB states 2-6 (3D bar objects) with 4 slots | `f_0204dd8c` (input), `f_0205495c` (draw), texture relabel, QoLTopInfo |
| All-Star select | Z-Battle / Maximum team select = scene 4 (`FUN_02066558`) incl. READY? GO / BACK | `f_02001014` redirects, game mode 5 at its exit |
| Battle | Free Battle rules (mode 5), stage 4 (Time Chamber), P2 = rolling 2-member CPU team | `f_020140c8`, `f_0202954c` tick, `f_02027164`, `f_02026e34` |
| Enemy swap | the game's own KO replacement (state 0xC, `FUN_02017358`) + `_shuffle_load` of the KO'd bench record | `# ---- ALL-STAR (part 34)` |
| Timer / tracker | BG1 HUD map cells (timer at cols 14-17 rows 0-1) with tiles composed from the game's digit glyphs | after `FUN_0201CDCC` / per frame |
| Sky + stars | stage 4's BG3 (sky) replaced by a star field + palette cycling (game-side, BG manager) | after `FUN_0201C150` |
| Music | stream position `[0x020DE33C]+0x158` vs the STRM's sample count → `f_0200fde4(0)` + `f_0200fe48(n)` | per battle frame |
| Hearts | port-drawn buttons under Team Arts (Touch! plate colours), revive = `FUN_020298D4`, heal = `FUN_02029428` | `QoLAllStarPanel` + filter_input |
| Records | port-drawn page with the HI-SCORE RANKING's own ROM art (`game/result.bin`), `allstar_records.cfg` | new `QoLAllStarRecords` |

Everything is inert unless `QoLSettings.new_gamemodes` is on AND (for the battle parts) an All-Star session is active
(`QoLAllStar.active`), so with the setting off every override is `super` only (off-identity tests, section 7).
The Gamemode menu's four slots: ALL-STAR (this design), ENDLESS (section 7, part 38), BOSS RUSH (section 8, part 43),
TOURNAMENT (section 9, part 43).

## 1. Facts per research question (short; details + addresses in DATA_NOTES part 34)

### 1.1 Mode Select FREE BATTLE tile (V/C)
- Tile index 5 (cursor u8 0x020DEC20, row-major 3x3: 0 Z-BATTLE, 1 STORY, 2 VS, 3 MAXIMUM, 4 centre/PORT, 5 FREE
  BATTLE, 6 PRACTICE, 7 DATA FILE, 8 OPTION). `FUN_02075738` maps cursor → scene: 0→4, 1→1, 2→0x11, 3→4, 4→2, 5→**3**,
  6→0xC, 7→8, 8→9, and calls `FUN_0200297C(cursor)` = **game mode u32 0x020DD514 = cursor index** (that is why Z-Battle
  = 0, Maximum = 3, Free = 5) and `FUN_02002738(0)`. Called from `FUN_02073F40` (scene 6) after `FUN_02073AAC` returns 1.
- Drawing (part 22): 3D quad, texture slot 0 + k·0x1000 (128x64 4-bit, visible 80x44, palette 0). Tile 5 = **+0x5000**.
  Label style (max1/p2620, ms_tiles.png): white condensed bold capitals (≈5x9 px) on a black plate, right-aligned,
  bottom 10 rows. Letters available in other labels: A, M, E, O, D (MAXIMUM, STORY MODE, FREE BATTLE) — **no G** in
  any label, so "GAMEMODE" needs one drawn glyph (or the whole label drawn from a small hand-made glyph table in code,
  like `QoLFont.HEAVY_GLYPHS`; nothing ROM-derived stored).
- Intercept: override `f_02075738`: `r = super()`; if NEW GAMEMODES and cursor == 5 → mode stays 5 (harmless) and return
  0xB (scene 0xB = MAXIMUM's scene) after clearing u8 0x020DE554 (scene-0xB state) and u8 0x020DE560 (exit code)
  to 0 (see 1.2 risk). Upper-screen box for tile 5: QoLTopInfo text (as the VS tile, QoLController ~line 289).

### 1.2 MAXIMUM course select (V/C)
- Flow (V max1/max2/max3): Mode Select tile 3 → **scene 4 mode 3 = team select first** (VBlank slot 0x02065E60, DP ∞/∞
  with the 100% save) → GO → **scene 0xB (`FUN_0204D0FC`) = course select** ("COURSE SELECT", Novice / Hard / Mania
  Rank) → map → battles. B in the course select → back to scene 4.
- Scene 0xB is a state machine, state u8 **0x020DE554** (`FUN_0204DB0C` / `FUN_0204DB1C`), loop `FUN_0204D1C4`:
  0 first entry (`FUN_0204DC98` setup, `FUN_020028C8(0)`), 1 = re-entry after a Maximum battle (map path!), 2-4 load
  the course select (`FUN_0204E118` engine setup, `FUN_020550D0`, `FUN_020550F0` + `FUN_020544E4(chosen)`,
  `FUN_0204DFCC` sound heap + BGM 1), 5 fade-in + `FUN_0200FE48(1)`, **6 = input `FUN_0204DD8C`** (returns 0 = leave
  → state 8 fade → 9 teardown `FUN_0204E0B8` → state 10 map or **0x20 = leave scene `FUN_0204DB60`**).
- Exit code u8 **0x020DE560** read by `FUN_0204DB60`: 3 → scene 4 (team select), **4 → scene 6 (Mode Select)**,
  5 → 0x10, `FUN_0204D9C0` true → scene 0 (battle, sets state 1). B in the course select = `FUN_0204DAD0` (exit 3).
  `FUN_0204DB60` also calls `FUN_02004D8C` (save write of the RAM copy — the game does this when leaving Maximum).
- Chosen course u8 0x020DE558 (`FUN_0204D9AC`).
- Graphics (V max3 layer sweep + RAM dump): lower screen = engine A, DISPCNT_A 0x40210D18: **BG0 = 3D** (header, the
  three bars and the cursor are 3D objects), BG3 = hexagon background, BG1 / BG2 off/empty. Upper screen = engine B
  (rank title + description, per-course maps uploaded by `FUN_020544E4` via `FUN_0200E570(0x4B / 0x33 / 0x41)`).
- Module state: `q = *(*(0x020DE5A0) + 0x30)`: +0/+4/+8 texture handles of the three bars (256x64 4-bit, texture
  VRAM offsets 0x2000 / 0x4000 / 0x6000; Novice / Hard / Mania incl. their labels), +0xC cursor frame texture
  (+0x1000), +0x10 header texture "COURSE SELECT" (+0x0, 256x32); **objects** (0x48 bytes, same object type as the
  select screens, drawn by `FUN_0200AEBC`, xyz s32 20.12 at +0x3C/+0x40/+0x44): +0x14/+0x18/+0x1C bars at
  (175,46) (160,100) (146,154) z 20, +0x20 header (111,19), +0x24 cursor (moved by `FUN_020544E4` to (204,46) /
  (175,100) / (146,154), z 30); +0x3080 u8 cursor 0..2, +0x3081..+0x3083 course open (0xFF; course 0 always,
  others by save via `FUN_02002498`); +0x28/+0x34 + 4c upper-screen data / sizes, +0x80 + c·0x1000 upper maps.
- Draw task **`FUN_0205495C(task)`** (task+0x30 = q): `FUN_0200AEBC` for the 3 bars, header, cursor. Touch rects
  (`FUN_02009844(1, x0, x1, y0, y1)`): course 0 x 103-247 y 30-62 (`FUN_02054484`), 1 x 78-242 y 84-116
  (`FUN_02054454`), 2 x 43-249 y 138-170 (`FUN_02054424`). Up `FUN_02054248` / Down `FUN_020540B8` (skip closed
  courses), SE 8 move, SE 2 decide, SE 4 back, SE 0xD buzzer. Scene 0xB never reads the game mode.
- **4 slots** = override `f_0205495c` (All-Star menu only): move the 3 bar objects to slot positions 0-2 (e.g. y 40 / 82
  / 124, x stepping like the game's diagonal −14 px per row) and draw a 4th bar = a copy of the bar object in port RAM
  (e.g. 0x02720000, 0x48 bytes, texture handle = the EMPTY texture) at y 166; then header + cursor. Labels: rewrite the
  bar textures in texture VRAM like QoLButton (compare-and-rewrite when the bank changes): texture +0x2000 → "ALL-STAR",
  +0x4000 → "EMPTY" (slots 1-3 all use it; +0x6000 unused); optionally the header +0x0 → "GAMEMODE SELECT". Text in
  the bars' heavy italic style (QoLFont HEAVY, bar palette indices sampled once from the texture).
- Input: override `f_0204dd8c` (All-Star menu only): own cursor 0..3 (Up/Down wrap, SE 8; key repeat like the game's
  `FUN_020011DC`), 4 touch rects (y centres 40/82/124/166, h 32), cursor object +0x24 moved to the slot's position;
  A / tap on ALL-STAR → SE 2, exit code 3 (0x020DE560 = 3 → scene 4) + `QoLAllStar.go_select = true`, return 0; A on
  EMPTY → SE 0xD (buzzer) and the top box says "Coming later"; B → SE 4, exit code **4** (→ scene 6 natively), return 0.
  Upper screen: QoLTopInfo (ALL-STAR + description / EMPTY + "coming later") over the game's upper screen; call
  `FUN_020544E4(0)` once at entry so the game's own upper frame is consistent.
- Risk: state 0x020DE554 = 1 is left behind when a real Maximum battle was quit from its pause; entering 0xB from the
  GAMEMODE tile would then take the "back from a battle" path → clear 0x020DE554 / 0x020DE560 before entering.

### 1.3 All-Star select = scene 4 (V/C)
- `FUN_02066558` is the Z-Battle / Maximum / LAN single-team select (3 picks incl. at most one support, READY? GO red /
  BACK blue hexagons, state u32 0x020DE8AC+0x10; GO → `FUN_0206CC94` returns 0x8000). Picks s32[3] **0x020DE64C**.
  It does not use the game mode except at its exit. Exit (after a 30-frame fade and `FUN_02066230` teardown):
  B with no picks → mode 2 ? 0x11 : **6**; GO → mode 0: `FUN_0209D244` + 0x12, mode 2: host ? 5 : 0x11, mode 3: 0xB,
  **else 0 (battle)**; afterwards (after its `FUN_02001014`!) it clears BOTH parties (`FUN_020028E0(0/1)`), moves a
  support back, applies the Babidi rule (SSJ Vegeta 7 + Babidi 0x1E → Majin Vegeta 0x15) and commits P1 with
  `FUN_02002838(0, id)` (party block P1 0x020DD524, count 0x020DD548).
- All-Star: enter scene 4 from the Gamemode menu (exit code 3) with the game mode set to **5** (`FUN_0200297C(5)` in the
  `f_02001014` redirect 0xB → 4): GO then goes straight to scene 0; B with no picks asks for scene 6 → redirect to 0xB
  (Gamemode menu). Because the select clears P2 after calling `FUN_02001014`, **P2 / stage / counts must be written at
  battle start (`f_020140c8` pre-hook)**, as RANDOM CHARACTERS and LAN already do.
- Battle setup in `f_020140c8` (All-Star only, before `super`): P2 ids s32[3] 0x020DD530 = [roster[i], roster[i+1],
  38], P2 support 0x020DD540 = 38, P2 count u8 0x020DD549 = 2 (1 for the last character), stage u8 0x020DD54A = **4**,
  boss level u8 0x020DD510 = 0, mode 5. After `super`: timer u16 G+0x1BCA6 = 0xFFFF (∞: no time-up; Free Battle uses
  1800 when the Option bit `FUN_020022B8()` is 0). CPU level: the loader `FUN_0202A40C` sets it from the
  Option difficulty (options bits 1-2 → `FUN_0200231C(1 / 3 / 6)`, DATA_NOTES part 30) — keep (or a fixed level).
- Routing in `f_02001014` while a session is active (cur → asked ⇒ new): 6 → 3 from the GAMEMODE tile ⇒ 0xB (done in
  `f_02075738`); 0xB → 4 (ALL-STAR) ⇒ 4 + mode 5; 0xB → 6 (B) ⇒ 6, session ends; 4 → 6 (B, no picks) ⇒ 0xB; 4 → 0 ⇒ 0
  (battle); battle 0 → **0x14** (Game Over / Continue = P1 lost) ⇒ 4 (All-Star select); 0 → **10** (results = P1
  won) ⇒ 4 + records page (section 1.10); pause exits (`FUN_02013064` state 9, Free mode: G+0x1BCAE = 3 / 0xD / 6 by item; which item is which: M, check the menu) 3 and 0xD ⇒ 4;
  pause "Return to Menu" 0 → 6 ⇒ 6 (session ends; or 0xB — user's choice). Scene teardown order: scene 4 calls
  `FUN_02001014(2)` first (LAN note `_lan_from`), handle like `_lan_sel_redirect`.

### 1.4 Roster (V: names = `charselect/SubScrNameDataEU.bin` USNAME map rendered, portraits / sprites / face icons rendered)
Playable fighters = ids 0-25 (supports 26-36 excluded). Names as the EU select screen shows them:
0 Goku · 1 Goku (Super) · 2 Gohan (Super 2) · 3 Gohan (Teen) · 4 Krillin · 5 Piccolo · 6 Vegeta · 7 Vegeta (Super) ·
8 Trunks (Super) · 9 Gotenks (Super 3) · 10 Frieza (final form) · 11 Mecha Frieza · 12 Ginyu · 13 Dr. Gero ·
14 Android #18 · 15 Cell (perfect) · 16 Buu (Good) = Majin Buu · 17 Buu (Evil) = Kid Buu (sprite: small, no cape) ·
18 Cooler · 19 Metal Cooler · 20 Broly · 21 Vegeta (Evil) = Majin Vegeta (not on the grid: SSJ Vegeta + Babidi
support, `FUN_02066558` exit rule) · 22 Trunks (Teen) = Future Trunks base · 23 Gotenks (base) · 24 Gohan (Kid) ·
25 Cell (2nd) = semi-perfect (bulky portrait; BOSS_CHARACTERS.txt calls it "Imperfect Cell" — M).
Boss versions are not separate ids (boss level on the same id) → nothing to exclude beyond keeping boss level 0.

**Proposed chronological order** (first appearance in the main story, manga/TV order; the three movie villains placed
where their films sit in the timeline; transformations at their first appearance):

| # | id | Character | Reason |
|---|---|---|---|
| 1 | 0 | Goku | DB ch. 1 |
| 2 | 4 | Krillin | DB (21st Tournament training) |
| 3 | 5 | Piccolo | Piccolo Jr., 23rd Tournament (end of DB) |
| 4 | 24 | Gohan (Kid) | DBZ start (Raditz arc) |
| 5 | 6 | Vegeta | Saiyan arc (after Gohan) |
| 6 | 12 | Ginyu | Namek, Ginyu Force |
| 7 | 10 | Frieza (final form) | after the Ginyu Force (the brief's example) |
| 8 | 1 | Goku (Super) | first SSJ vs Frieza |
| 9 | 18 | Cooler | movie 5 (set after Namek) — M |
| 10 | 11 | Mecha Frieza | Trunks arc opening |
| 11 | 22 | Trunks (Teen) | appears in base form, then turns SSJ |
| 12 | 8 | Trunks (Super) | same chapter, right after |
| 13 | 19 | Metal Cooler | movie 6 (during the 3-year wait) — M |
| 14 | 13 | Dr. Gero | Android arc (Android 20) |
| 15 | 7 | Vegeta (Super) | reveals SSJ vs Android 19 (after Gero) |
| 16 | 14 | Android #18 | activated after 19/20 |
| 17 | 25 | Cell (2nd) | after absorbing 17 (Cell's first form is not in the game) |
| 18 | 15 | Cell (perfect) | after absorbing 18 |
| 19 | 20 | Broly | movie 8 (during the 10 days before the Cell Games) — M |
| 20 | 2 | Gohan (Super 2) | Cell Games climax |
| 21 | 3 | Gohan (Teen) | Buu arc (sprite: dark blue gi, red sash) — M (could be read as Cell-arc base Gohan) |
| 22 | 21 | Vegeta (Evil) | Majin Vegeta, Babidi's ship |
| 23 | 16 | Buu (Good) | Majin Buu released |
| 24 | 23 | Gotenks | first successful fusion |
| 25 | 9 | Gotenks (Super 3) | vs Super Buu |
| 26 | 17 | Buu (Evil) | Kid Buu, the final form |

`ROSTER := [0, 4, 5, 24, 6, 12, 10, 1, 18, 11, 22, 8, 19, 13, 7, 14, 25, 15, 20, 2, 3, 21, 16, 23, 9, 17]` (26).
Open points for the user: include Majin Vegeta (only reachable with Babidi normally)? Movie villains by release date
instead (Cooler Jul 1991, Metal Cooler Mar 1992, Broly Jul 1993 — same slots except Metal Cooler could move after
Gero/SSJ Vegeta)? `asorder=` lets them try.

### 1.5 Enemy replacement (V rp2, C)
- KO handler `FUN_0202759C(rec)` (HP 0): action 0x33, then **`FUN_02027164(rec, 0, 0)`** = forced tag to the next alive
  member (HP > 0, id < 0x1A): if found → event 7 → battle state **0xC** = `FUN_02017358` = the game's KO-replacement
  sequence (the KO'd fighter falls off screen, the camera follows, the next member flies in, its face icon / life bar /
  voices are loaded, back to state 7). Else Shenron check (`FUN_0203483C`), else winner / loser (teams +0x11D0 /
  +0x11D4) and event 0xB → state 0x11 (battle end).
- **V (rp2):** Free Battle, P2 party poked to Goku + Piccolo (count 2), one-hit KO: KO at f4620 → state 0xC sub-states
  0-6, P2 active index (team +0x8C8) 0 → 1 at f4750, state 7 at f4790 (≈170 frames); Piccolo enters from the top with
  his face icon and a full life bar (/tmp/ssw2/as34/rp2_sheet.png). The P2 HUD shows no member markers for 2 members.
  The same sequence runs between Z-Battle enemies (rank2_ko.png: Gohan falls, Krillin enters).
- **Design: rolling 2-member CPU team.** P2 = [roster[i], roster[i+1]]. When the active enemy is KO'd the game brings
  the bench in (exact entrance, voices, icon, bar). Once the state is back to 7, the KO'd (now inactive, hidden)
  record is reloaded with roster[i+2] with the CHARACTER SHUFFLE machinery: `_shuffle_load(rec, n)` (archives /
  cache entries released and reloaded, per-character init, palettes into the record's own slots — mirror palette
  when the id is in P1's TEAM, not only P1's active), `_shuffle_icon(rec, n)` (face icon into rec+0x290), `_shuf_loading`
  around it (card-DMA freeze workaround, keep!), then HP = max HP = u16 *(rec+0x50) (the new character's own),
  +0x250 = 0, +0x254 &= ~0x800, `FUN_02021B4C(rec, 0)` (as the game's revive `FUN_020298D4` does). Voices are not
  needed for a bench record (the replacement sequence loads them). For the last character the KO'd bench is left at
  HP 0, so its KO ends the battle normally (event 0xB → state 0x11 → WIN banner → scene 10).
  Counter: beaten = number of side-1 KOs (state 0xC entries for side 1 + the final one).
- No tag / no Team Arts for side 1: the CPU's tag is a touch on a bench panel through the neutral handler
  `FUN_0202CC70` → `FUN_02027164(f, 1, 0x14)` (AI tap: `FUN_0202D820`); override **`f_02027164`**: refuse when All-Star,
  f+0x1A side 1 and param_2 != 0 (the KO path uses param_2 = 0 and must keep working). Team Arts: override
  **`f_02026e34`** → 0 for side 1. P1 unchanged.
- Alternative (fallback): 1-member P2 and an in-place reload at the KO (intercept `FUN_0202759C` before event 0xB):
  needs a home-made entrance — not recommended.

### 1.6 HUD timer (C, V hudbg.png / hud_top.png)
- Top-screen BG1 (4-bit, char base 0, map 0x1C800 in engine A BG VRAM = bank D) is built in the BG manager's map
  buffer **S = *(0x020DE3BC) + 0x1774** (32x32 entries) and queued with `FUN_02006B68(1, 0x800)`. Glyph library
  (game_bg.arc #2): rows 24/25 cols 21-30 = timer digits 0-9 (8x16, black on the plate's yellow), col 31 = blank;
  rows 24/25 cols 0-9 = ki digits. The plate with ∞ is part of the base map (rows 0-2, cols 13-18, x 102-155).
- `FUN_0201CDCC(G+0x1BC8C)` (called from `FUN_0201272C`, value u16 G+0x1BC90 = timer G+0x1BCA6) rewrites cols 14-17
  rows 0-1 only when the value changes; 0xFFFF (Free Battle without time limit) never changes → the ∞ stays.
- MM:SS in 32 px (cols 14-17): compose 8 new BG1 tiles (4 cells x 2 rows) from the game's own digit tiles read from
  VRAM (digit ink ≈6 px; layout 6+1+6+1+2(colon)+1+6+1+6 ≤ 32) plus a 2-dot colon in the digits' black, written into
  free BG1 char slots (the HUD uses 93 tiles at 0x0000; BG2 chars start at 0x4000 → tiles 0x100-0x1FF free; verify)
  through `FUN_02006E50(1, …)` (BG manager queue, uploaded at VBlank) or a direct bank write + `bank_gen++` like
  QoLButton; then point map cells cols 14-17 rows 0-1 at them and queue `FUN_02006B68(1, 0x800)`. Rewrite only when
  the second changes; re-check every frame that the cells still point at our tiles (pause / cut-ins may rebuild).
- "beaten/total" (e.g. "12/26") centred under the plate at rows 3-4 (y 24-39), composed the same way on a small plate
  (yellow fill, black outline like the ki boxes); or fallback: a port Control on the top screen (QoLInputDisplay-like).
- Clock: count frames while battle state u8 0x020DD4C5 ∈ {7, 8, 0xA-0xE} (fight + in-fight events incl. the KO
  replacement; not 9 = pause), from the first state-7 frame to the final KO (state 0x11); show frames / 59.8261 s,
  cap 99:59.

### 1.7 Time Chamber (V tc1 / stages.png / stex.png)
- **Stage id 4** (stg_5.bin; select icon 4 → id 4 via table 0x020D0758): the white floor and the building with two
  hourglasses (tc1_sheet.png). BGM: `FUN_02013064` case 4 → STRM stage+1 = **5** (probe 0x020DE348 = 5).
- Picture (V tc1 io / VRAM dump f4600): DISPCNT_A 0x08010F08 (mode 0, BG0 = 3D, BG1-3 on, map base +0x10000), BG1CNT
  0x1900 (HUD), BG2CNT 0x5A86 (256-colour, chars 0x4000, map 0x1D000, 512x256), **BG3CNT 0x1C97 (256-colour, chars
  0x14000, map 0x1E000) = the sky**: a pale blue-grey gradient with light streaks, palette indices **32..191 used only
  by BG3**; BG2 uses only index 17 (white single-pixel dots over transparency = already "stars"). Clear colour 0, fog
  on (DISP3DCNT 0x3A99, FOG_COLOR 0x000F7E10 light blue) — the far floor fades to light blue; stage 4 table flag 0 → no
  affine sky / no HBlank sky handler.
- Recommended (game-side, every renderer feature keeps working): after `FUN_0201C150(4)` in All-Star, give BG3 a
  port-made star field: a few 8x8 star tiles (1-2 px dots in indices 33..40) + a map (random stars, the rest a black
  tile) queued through the BG manager (`FUN_02006E50(3, …)` chars, `FUN_02006DCC(3, …)` map, palette via the BG
  palette path) and palette 32 = black, 33..40 = star colours cycled every few frames with different phases →
  individually twinkling stars that scroll with the sky's parallax. Floor / buildings / fog unchanged (optional: fog
  colour black if the light-blue horizon band looks wrong). Normal Time Chamber elsewhere untouched (only in a session).
- Fallback (renderer-only): a DSDisplay flag making engine A BG3 output black + procedural stars keyed to BG3's scrolled
  texel position (ds_engine2d variant like FX_FUZZY).

### 1.8 Music (V tc2 / tc3, C)
- Stage BGMs = STRM 1..15 (stage s → s+1, except 2 → 4, 3 → 3); 0 = opening, 16/17 boss, 18 VS, 19 CHARA.
  Time Chamber = **STRM 5** (691967 samples at 11141 Hz = 62.1 s, loops from 0).
- Play position: stream handle **u32 0x020DE33C** → player P: **u32 P+0x158 = samples played**, u16 P+0xC0 = rate
  (`FUN_020A4438` = position in ms, used by the BGM pause `FUN_0200FD68`). V tc3: +0x158 rises ≈179 samples/frame,
  0xA8C00 (691200) at f7440 → **0x1301 at f7470: it wraps to loop start + overflow at the loop**.
- Rotation (All-Star battle only, game thread): each battle frame (not while the BGM is paused, +0xA2 bit 0, nor after
  the final KO) read pos; when `total − pos < 2 frames' worth` or pos < last pos → pick a random other stage BGM
  (1..15 minus the current) and play it the jukebox way: `f_0200fde4(0)` then `f_0200fe48(n)` (stream mode is already
  set in battle). Totals from the SDAT (QoLSound: STRM INFO → file → HEAD +0x14 sample count, +0x10 loop start).
  RANDOM MUSIC's stream map applies inside `f_0200fe48` (fine). Pause resume (`FUN_0200FCF8`) restarts at the saved
  offset of the CURRENT id (+0xA8) — consistent.

### 1.9 Hearts (V lower_crop.png, C)
- Lower screen (battle): "Team Arts" bar x 5-135 y 145-174, Touch! plate x 128-247 y 145-186; free strip **x 8-122,
  y 175-191** under the Team Arts bar. Three hearts ≈16x14 at x 16 / 48 / 80, y 176 (port-drawn Node2D over the lower
  screen like QoLMarkers / QoLMpPanel; follow MASTER_BRIGHT fades). Colours like Touch!: lit = plate 0x027F + red
  0x001F, used = dim 0x014F + 0x0010 (palette game_bg.arc #0x66 rows 5 / 6).
- Taps: the game's Team Arts rect is x 8-248 **y 144-184** → a tap on a heart (y ≥ 176) would also reach the game:
  `QoLController.filter_input` must swallow touches that start on a heart (like CENTER_RECT). Keyboard / pad: Select
  (no battle action, part 16) = use the next heart.
- Effect (only in state 7, no cut-in `FUN_02012FD4() == 0`, no Team Arts running teams+0x11E4 == 0, P1 active HP > 0):
  for each P1 member with HP 0 → `FUN_020298D4(0)` (the game's revive, Shenron's: first KO'd member, HP 10000, flags
  cleared, action 0, `FUN_0201C5C0` = life bar + lower panel palette); then every member `FUN_02029428(rec, max)` (heal,
  clamped to +0x24C; the HUD bar drains up by itself). SE e.g. 0x12. Supports untouched.

### 1.10 Records screen (V rank2 / rank3, C)
- The HI-SCORE RANKING is the LOWER screen of the results scene 10 (`FUN_0208B578` state 2 `FUN_0208B428`, Z-Battle
  only): engine A DISPCNT 0x08010508, BG0 = 3D (title plate, 5 rows, digits, faces, difficulty), BG2 = hexagon BG.
  Art (`romdata/game/result.bin`): `base1st..base5st` (256x32 rank rows with "1st".."5th"), `e_hi_score` (256x32 title
  plate), `no0..no9` (8x16 digits), `e_easy / e_noaml / e_hard` (64x16), `e_res_bg` (BG); faces `game/game_faceicon.arc`.
- Recommended: a port page `QoLAllStarRecords` drawn with that art read from the ROM at runtime (QoLFont.nitro_file +
  the pack / GARC decoders QoLMpPanel uses; nothing stored): title plate re-texted "ALL-STAR RECORDS" (QoLFont HEAVY
  over the plate), 5 rows: rank art, time MM:SS in `no` digits (+ drawn colon), the team's 3 face icons, hearts used
  where the difficulty label sits; the new entry's row blinks like the game's. Upper screen: QoLTopInfo "ALL-STAR" +
  "Clear time 12:34 — 2nd place!" (or "Cheats on: not recorded").
- When: the win asks for scene 10 → redirect to scene 4 and show the page as an opaque modal over both screens while
  the select loads; A / B / tap closes it (input blocked meanwhile).
- File: `allstar_records.cfg` next to the exe (same folder logic as settings.cfg; editor user://; captures ignore it
  unless `asrec=PATH`), ConfigFile `[records] r1..r5 = {"frames": int, "ids": [a,b,c], "hearts": int, "date": "YYYY-MM-DD"}`,
  sorted by frames, then hearts, then date; never the game save. Cheats on (`QoLSettings.cheats_on() > 0`) → nothing
  written (as `f_02002560`).

## 2a. Implementation status / shared API (part 34 implementation)
**`QoLAllStar`** (`scripts/qol/qol_allstar.gd`, phase 1, created first): one instance `QoLController.allstar`, shared as
`QoLGame.allstar` (declared in qol_game.gd `# ---- ALLSTAR MENU (part 34)`, set in `QoLController.setup` like `mp`).
- enum `NONE, MENU, SELECT, BATTLE, RECORDS`; consts `ROSTER` (26 ids, design 1.4), `STAGE_ID` 4, `GAME_MODE` 5, `EMPTY_ID` 38.
- `active` (session running), `stage`, `order` (enemy ids; `asorder=`), `start_index` (`asstart=N`), `index` (order index
  of the enemy active now — phase 2 advances it), `beaten`, `hearts_used`, `elapsed_frames` (phase 2 counts),
  `result` ("" / "win" / "lose" / "quit", set by the phase-1 routing when the battle is left; phase 2 may set it earlier),
  `p1_ids` (P1 team at battle start, written by phase 1), `battles`, `debug_battle` (`allstar=1`), `dbg` (`asdbg`),
  `menu_cursor`, `menu_note`.
- `start()`, `end()`, `battle_reset()` (called by phase 2's `_asb_battle_setup` at the `f_020140c8` pre-hook BEFORE the
  party is written: index = start_index, counters 0, stage = BATTLE), `enemy(k := 0)` → `order[index + k]` or 38,
  `total()`. Phase 2 added `hearts`, `heart_req`, `done`, `done_frame`.
- Battle setup: **phase 2** (`# ---- ALLSTAR BATTLE`, `_asb_battle_setup` / `_asb_battle_started`): P2 = [enemy(0),
  enemy(1), 38], count 2 (1 for the last), support 38, stage 4, boss level 0, `p1_ids`; after super timer 0xFFFF.
- **Phase 1 status: DONE** (QoLGame `# ---- ALLSTAR MENU (part 34)`, `qol_allstar_menu.gd`, QoLController `# ---- ALLSTAR
  (part 34)`, QoLTopInfo `full`; facts DATA_NOTES "part 34 findings (All-Star menus)"; evidence /tmp/ssw2/as1):
  - GAMEMODE label on tile 5 (texture rewrite) + upper box text; `f_02075738`: tile 5 → scene 0xB, stage MENU, scene
    state / exit cleared.
  - Gamemode menu: 4 bars (ALL-STAR + 3× EMPTY) at (160,44) (149,85) (138,126) (127,167), cursor frame +15 px; Up / Down
    (wrap, key repeat), tap = move / tap again = choose, A, B; EMPTY = buzzer; upper screen `as_top` (title +
    description per slot, faded with the game). B → Mode Select (exit 4).
  - Routing `_gm_route` (top of `f_02001014`, only while `active` / stage MENU / `allstar=1`): 6 → 0xB (tile); 0xB → 4
    ⇒ 4 + mode 5 + `start()`; 0xB → 6 ⇒ `end()`; 4 → 6 (B, no picks) ⇒ 0xB (menu again); 4 → 0 battle; battle 0 →
    0x14 / 10 / 3 / 0xD ⇒ 4 + mode 5, `result` lose / win / quit if still ""; 0 → 6 ⇒ `end()`. The select's teardown
    asks scene 2 first (`_gm_from`, like LAN). A stale MENU stage is dropped when any other scene changes.
  - Win: straight back to the select for now (phase 4 records page hooks the 0 → 10 case / `result == "win"`).
  - Open: header still says COURSE SELECT (the game's texture); the lose path (0 → 0x14) is the same branch as the
    verified pause path but was not played to the end in phase 1.
- **Phase 2 status: DONE** (QoLGame `# ---- ALLSTAR BATTLE (part 34)` (prefix `_asb_` / `ASB_`: AUTO SKIP owns `_as_`),
  `qol_allstar_hearts.gd` = `QoLAllStarHearts`, QoLController hook lines `as_hearts`; facts DATA_NOTES "part 34
  findings (All-Star battle)"; evidence /tmp/ssw2/as2):
  - Setup at `f_020140c8` (after RANDOM CHARACTERS / RANDOM STAGE, so the stage is always 4); STAGE SHUFFLE inert in an
    All-Star battle. Per-frame tick = override of `f_020010f4` (NitroMain's scene update; `_asb_on` only).
  - Rolling CPU pair: the KO'd hidden record is reloaded on the first state-7 frame after the game's state 0xC as
    `order[next]` (`_shuffle_load` inside `_shuf_loading`, loader mirror rule over P1's whole team, HP = the new
    character's max, icon into the side-1 buffer); safety net in `f_02027164(rec, 0, 0)` (a KO before the reload →
    reload at once). Last enemy: the bench stays KO'd → the game's own battle end (state 0x11) → `result` "win".
  - CPU tag (`f_02027164` side 1, touched) and Team Arts (`f_02026e34` side 1) refused; P2 support 38.
  - Clock: frames in states 7, 8, 0xA-0xE from FIGHT to the last KO, `elapsed_frames` (shown floor(frames / 59.8261 s),
    cap 99:59); `beaten` counts side-1 KOs (tracker shows `start_index + beaten` / `total()`); `result` "win" / "lose"
    when the battle state reaches 0xF-0x11 (lose = P1's team out).
  - HUD: BG1 tiles 0x180-0x18B (timer plate cols 13-18 rows 0-1, ∞ replaced by MM:SS) and 0x18C-0x197 (new plate cols
    13-18 rows 3-4 with "n/26"), pixels from the game's own timer digit tiles; given back to the game while paused.
  - Hearts: 17x15 at x 37 / 61 / 85, y 176 of the lower screen (lit / used looks = the Touch! plate's lit / dim
    colours); tap (mouse / pad cursor) or SELECT (first lit heart) → `heart_req` → in state 7 with no cut-in / Team Arts
    / tag: `FUN_020298D4(0)` per KO'd P1 fighter + `FUN_02029428(rec, max)` for all, SE 2; nobody hurt → nothing. Taps
    starting on a heart are kept from the game; while paused taps / SELECT go to the game.
  - Debug flags: `asp1=a,b,c` (P1 party), `asheart=F[:i]`, `ashp=F:k:HP`, `asclock=S`; `asdbg` lines `AS f… battle
    start / state / enemy KO / swap #n … heap … archives … cache / heart … / CPU … refused / battle end`.
  - Life bars (part 35): the game repaints only the ACTIVE member's bar colours when its HP changes, so a member
    healed / revived while benched (hearts) or the reloaded CPU record came back with "lost" (navy) columns.
    `_asb_bar_paint` / `_asb_bars` + an override of `f_0201cbbc` repaint a member's colour buffer from its HP (each
    member keeps its own bar colour: yellow / lavender / green); DATA_NOTES "part 35 findings (All-Star life bars)".
  - Open: (music rotation and the star sky = phase 3, records = phase 4: done). The CPU's refused taps are rare (t1: one in 50 s).
- **Phase 3 status: DONE** (stage look + music; `QoLAllStarStage` = `scripts/qol/qol_allstar_stage.gd`, QoLGame
  `# ---- ALLSTAR STAGE (part 34)` (`_ass_reset` from `_asb_battle_setup`, `_ass_tick` from `f_020010f4` while `_asb_on`),
  track lengths `QoLGame.as_strm_info` filled by QoLSound (STRM HEAD); facts DATA_NOTES "part 34 findings (All-Star
  stage)"; evidence /tmp/ssw2/as3):
  - Sky (part 35 redesign; facts DATA_NOTES "part 35 findings (All-Star sky)", evidence /tmp/ssw2/as35sky): BG3
    (never scrolled: a screen-fixed backdrop) becomes a DS-style night sky built once at runtime from fixed seeds (no
    ROM data; `_build` on a WorkerThreadPool task started at the battle setup): a vertical gradient (near-black at
    the top → indigo → navy at the bottom; 19 five-bit ramp entries, 4x4 ordered dithering between neighbours), a
    faint milky-way band with a dark dust lane plus a smaller cloud (periodic value noise; rose / violet / teal x 4
    levels x 7 sky bands, dithered), 230 one-pixel stars (white, blue-white, yellow, orange, pale red; dim .. bright;
    denser in the band, fewer near the horizon) in 36 twinkle slots (4 height zones x 9 classes, each its own period
    / phase, blending between the sky under it and the star colour) and 6 plus-shaped glints (centre / arms / outer
    arms twinkling). 386 distinct tiles over BG3's own 480-tile char data (0x06014000-0x0601B800), map in VRAM + the
    BG manager's BG3 map buffer, palette 32-188 (shadow +0x1D8 and palette RAM, written when different; nothing in
    the pause, the twinkle stops there); the sky's 3D light-ray curtain (stage objects 5 / 6, texture 3) hidden via
    their visible flag. Re-applied whenever the game's data comes back. Floor / building / fog / BG2 dots unchanged;
    intro fade, pause grey-out, KO swap, KO / WIN, zoom 0 / 4, mirror verified (s1 / zm / z4); the hourglasses' glass
    shows the navy sky. Normal Time Chamber (Free Battle) identical to the part-34 code (nA / nB).
  - Music: track 5 (or RANDOM MUSIC's pick) first; when ≤ largest counter step + 2 frames of samples are left (or the
    counter wrapped) → FUN_0200FDE4(0) + FUN_0200FE48(random stage BGM 1-15 ≠ current, RANDOM MUSIC map bypassed),
    +0xA2 put back. Only in battle states 7, 8, 0xA-0xE until the last KO; a track ending in the pause (the game keeps
    playing music there) switches at resume. Leaving the battle = the game's own music handling.
  - Flags `asmusic=F`, `asmseek=F:S`, `asmseed=N`, `asmlog`, `assky=0`, `asrays=1`, `asskypng=FILE`, `asskylog`.
  - Open: the hourglasses' glass is see-through (3D alpha) → shows the sky behind it (physically consistent). ≤ 1-frame
    silence at a switch (stream restart).
- **Phase 4 status: DONE** (records; QoLGame `# ---- ALLSTAR RECORDS (part 34)` = `_asr_win` (hook line in `_gm_route`'s
  battle branch), `qol_allstar_records.gd` = `QoLAllStarRecords`, QoLController hook lines `as_records`, header relabel in
  `QoLAllStarMenu.bars_frame`; facts DATA_NOTES "part 34 findings (All-Star records)"; evidence /tmp/ssw2/as4):
  - QoLAllStar: `records_req` (set on the game thread by `_asr_win` when the won battle asks for scene 10, cleared by the
    page), `p1_support` (u32 0x020DD53C at that moment); stage `RECORDS` while the page is up (back to `SELECT` after).
  - Page (both screens, opaque, z 900, main thread; **redesigned in part 35** to look like the game's own Z-Battle
    results scene 10, DATA_NOTES "part 35 findings"; evidence /tmp/ssw2/as35):
    - UPPER = the results' score panel: e_res_bg (three portrait frames, yellow table, black tab, Total bar, WINNER
      banner) over the game's hexagons (common_bg.bin cstat_bg, 64 x 64 tile, scrolling +0.5 / +1.1 px per frame from
      35 / 477 like scene 10); the team's portraits (CharFace256.bin, 80 x 40 at y 14 + 40 k; empty slot = nul1; a
      support is shown like a fighter, as on the Z-Battle select); tab "ALL-STAR" (white letters of the tab / Total
      labels); rows "Enemies 26/26", "Hearts Used n", "Rank 1st..5th / -", "Best MM:SS / --:--" and a status row
      ("New Record!", "Not Ranked", "Cheats On | Not Recorded", "Practice | Not Recorded", "File Error | Not
      Recorded"); Total bar = "TIME" + this run's time in the bar's orange digit cells. Letters = glyphs cut at runtime
      from the five languages' pre-lettered labels (QoLAllStarRecords.harvest; d / H / w / ! / - put together from the
      font's own strokes), numbers = the table's own digit strip (8 x 16 yellow / 8 x 12 orange cells at e_res_bg
      y 192 / 208), colon / slash / dash drawn in their shades.
    - LOWER = the HI-SCORE RANKING: e_hi_score re-lettered "ALL-STAR RECORDS" with the plate's own italic capitals
      (harvest_plate over e/f/s/g/i plates: A, L, -, S, T, R, E, C, O, D) at y -2; rows base1st..base5st at
      y 22 + 28 i (2-px borders overlapping; the game: 28 + 32 i) with MM:SS in no0..no9 (ink only, + drawn colon,
      "--:--" for an empty row) right-aligned to x 122, face icons at x 128 / 152 / 176, the hearts used in the
      difficulty word's slot ("NO HEARTS" / "1 HEART" / "2 HEARTS" / "3 HEARTS" in the e_easy/e_noaml/e_hard
      lettering, x 202-251, underline row + 27); the new row flashes lighter (8 frames on / 8 off).
    - OK = the results' "Character Select" plate (e_charasele rows 0-1 + 8-31 = 26 rows at y 166) with the results'
      cursor (cursol 256 x 32: white frame + triangle) blinking on it. A / START / B / a tap or pad-cursor click on it
      (touch rect 0,164 256 x 28) -> SE 0 (decide) -> fade out 16 f -> the select (loaded behind the page meanwhile)
      revealed from black in 16 f. All input is kept from the game while the page is up; held keys stay blocked
      until released.
    - Art missing (unknown ROM): a plain text page (QoLFont) with the time; A closes it as before.
  - File: `allstar_records.cfg` next to the exe (editor user://, `asrec=PATH`, captures without `asrec=`: none),
    `[records] r1..r5 = {"date", "frames", "hearts", "ids"}`; load skips invalid entries (wrong types, ids > 38, frames
    out of 1..99:59, hearts > 3; strings of digits accepted), an unparseable file is copied to `.bak` before the next
    write; read-only exe folder -> user://. Not written while cheats are on or after an `asstart=` / `asorder=` run.
  - Gamemode menu header: COURSE SELECT -> "GAMEMODE SELECT" (texture +0x1000, `QoLAllStarRecords.retitle`: the game's
    title erased row by row after the square block, the port's heavy capitals 10 -> 15 rows, slant 1 px / 4 rows,
    coverage -> 5 greys of palette 0); only while the Gamemode menu runs (MAXIMUM's own header untouched).
  - Debug flags: `asrec=PATH`, `asfakewin=M:SS[:hearts]` (the win counts as a cheat-free full run with that time),
    `asrecdemo=F` (open the page at port frame F without a battle; cheats rule kept unless `asfakewin=`).
  - Open: no "reset records" item (delete the file). Part 35 found the hexagon file (cstat_bg) and dropped the
    generated one and the character-name list (the page shows portraits / icons, no names).

## 2. Classes, files, hook points
- `scripts/qol/qol_allstar.gd` — `QoLAllStar` (RefCounted, shared by QoLController / QoLGame like QoLMp): `active`,
  `stage` (MENU / SELECT / BATTLE / RECORDS), roster + index, beaten, frames, hearts_used, music state, records I/O.
- `scripts/qol/qol_allstar_panel.gd` — hearts on the lower screen (draw + hit test + Select key).
- `scripts/qol/qol_allstar_records.gd` — records page (both screens).
- Tile label: `QoLButton` generalised (offset + picture provider) or a sibling `QoLGamemodeTile`.
- QoLGame section `# ---- ALL-STAR (part 34)` with one-line hooks: `f_02075738` (new), `f_02001014` (redirect, before
  the MP/LAN branches only when `allstar.active`), `f_0204dd8c` / `f_0205495c` (new), `f_020140c8` (party / stage /
  timer), `f_0202954c` (tick: swap, clock, music, hearts request), `f_02027164` / `f_02026e34` (side 1), `f_0201c150`
  (sky), records at the 0 → 10 redirect.
- QoLController: setting apply, top-info texts (tile 5, gamemode menu), hearts input in `filter_input`, records modal.
- QoLSettings: `new_gamemodes` (saved, default false); QoLMenu `mpset`: row "NEW GAMEMODES" ON / OFF (+ description).
- Docs: QOL_ARCHITECTURE section, DEBUG_FLAGS rows, PLAYER_README text, TESTING section.

## 3. Phases
1. **Menus** — setting row; tile 5 label (texture rewrite + top info); `f_02075738` → 0xB; 4-slot course screen
   (draw + input + labels + top info); exit codes 3 / 4; 0xB → 4 with mode 5; 4 → 6 ⇒ 0xB; session start / end.
   Test: captures of Mode Select (label), gamemode menu (cursor on each slot, tap each slot, B), select, B chain.
2. **Battle rules** — `f_020140c8` setup (P2 pair, stage 4, ∞ timer), rolling reload after state 0xC, side-1 tag /
   Team Arts refusals, end routing (0x14 ⇒ 4, 10 ⇒ 4 + records, pause exits), clock + beaten counter (log first),
   HUD cells, hearts. Test with `allstar=1 asstart=` + one-hit KO: every swap logs ids / heap / archives / cache
   (constant per round like part 16), mirror palettes, last KO → WIN → records.
3. **Stage look + music** — star field + twinkle; music rotation (force a switch with `asmusic=F` to test, then a
   real 62 s wrap).
4. **Records** — page + file; cheats → not saved; blinking new row; reset from the menu (optional).
5. **QA** — full flow by keys and taps, all 26 swaps in one battle (heap / file manager constant, no SCRIPT ERROR, no
   freeze with `noloadskip dmaread` style repro off), pause paths, cheats combos (CHARACTER / CHAOS SHUFFLE on P1,
   BOMB RAIN, RANDOM MUSIC; RANDOM CHARACTERS randomises P1 only; RANDOM STAGE / STAGE SHUFFLE off in a session),
   MULTIPLAYER on at the same time (VS tile unaffected), off-identity.

## 4. Debug flags (proposed)
| Flag | Meaning |
|---|---|
| `newmodes=1` | NEW GAMEMODES on for the run (captures ignore settings.cfg) |
| `allstar=1` | the btnrun Free Battle becomes an All-Star battle (like `mpbattle=1`): session active, setup at `f_020140c8` |
| `asstart=N` | start at roster index N (e.g. 24 → two fights to the end) |
| `asorder=a,b,c` | custom roster (ids) |
| `asdbg` | `AS f… state … active … beaten … clock … pos … heap … archives … cache` lines, swap / music / heart events |
| `asmusic=F` | force the music switch at battle frame F |
| `asheart=F` | use a heart at frame F |
| `asrec=PATH` | records file to use |

## 5. Tests
- Off-identity (setting off): off23 copy → 21/21 PNGs + 1382 `^CHT f` lines = /tmp/ssw2/btn; intro 221/221.
- Setting on, other modes: Free Battle tile is GAMEMODE, but Z-Battle / Maximum / VS / Practice runs = off runs
  (compare the btn-style Z-Battle path frames).
- Swap stability: one `allstar=1` battle through all 26 (one-hit KO + infinite health), `asdbg` heap free / archives /
  cache at each state-7 return identical per character class; card-DMA: `_shuf_loading` gating active.
- Visual: gamemode menu (4 bars, cursor on each), HUD MM:SS + n/26, sky black + stars, hearts lit / used, records page,
  compared side by side with the game's course select / ranking captures (as34/max3_sheet.png, rank3_layers.png).

## 6. Risks / fallbacks
- Scene 0xB state 1 left over from Maximum (clear 0x020DE554 / 0x020DE560 on entry).
- `FUN_0204DB60` writes the save copy on leaving 0xB (same data; the game does it too) — acceptable, note it.
- KO replacement while a P1 assist / Team Arts is active: same as the game's Z-Battle (fine); the reload waits for
  state 7 and `_shuffle_blocked`-like conditions (no effect objects of the bench record alive).
- Heap: two enemy characters loaded at once (Ginyu / Cooler effect archives ~200 KB): log heap per swap; worst pair.
- The P2 HUD/AI with count 2 behaves like Z-Battle teams (V); the AI's refused tag taps are harmless (same as low ki).
- Timer cells: if the game redraws the HUD map (pause, Team Arts cut-in), the per-frame check rewrites them.
- Star field via the BG manager queue: queue limit 32 entries (part 18) — one-off at load, far below.
- Music: a STRM switch costs a stream restart (brief gap like the jukebox); never during pause / KO end.

## 7. ENDLESS (part 38) — status: DONE
Second NEW GAMEMODES mode: ALL-STAR's machinery with random enemies and no end. Facts: DATA_NOTES "part 38 findings
(Endless)". Code: `QoLAllStar.endless` + `at()` (qol_allstar.gd), QoLGame `# ---- ALLSTAR MENU / BATTLE / RECORDS`,
QoLAllStarMenu (ENDLESS bar), QoLAllStarRecords (`endless`), QoLController `AS_TEXTS`.
- **Menu**: Gamemode menu slot 1 (was EMPTY) = the third bar object (MAXIMUM's Mania bar, texture +0x6000), its texture
  rewritten as the Hard bar labelled ENDLESS (port-drawn N / D in the bar font; the Mania M / R are read before the
  texture is relabelled). Slots 2-3 stay EMPTY (buzzer). Keys / taps as before; upper box = ENDLESS description.
  `_gm_decide`: slots 0-1 -> exit 3; `_gm_route` 0xB -> 4: `start(menu_cursor == 1)`; B on the select with nothing
  picked -> Gamemode menu with the cursor back on the mode left.
- **Session**: `start(true)` = `endless`, `start_index` 0; ALL-STAR's own order / `asstart=` are kept apart
  (`_as_order`, `_as_start`) and put back by `start(false)`. `battle_reset()` reseeds the RNG (`esseed=N` + battle
  number) and empties `order`; `at(i)` appends random ROSTER ids until index i exists, each never one of the two ids
  before it (so the active enemy and the bench differ, no repeat of the one just beaten). `total()` = 1<<30, so the
  "last enemy" / `done` logic never fires and `_asb_swap` always reloads.
- **Battle** (unchanged code paths): P2 = [at(0), at(1)], count 2, stage 4 (space sky + music rotation), hearts,
  CPU tag / Team Arts refused, clock (cap 99:59, keeps the cap), swaps through `_asb_load(at(next))`. HUD tracker plate
  shows the enemies beaten ("n", no "/26"). V es1 (headless, one-hit KO + infinite health + ki homing, A spam): 47
  random swaps in 11800 frames, heap free 0.98-1.23 MB without a trend, cache 24, archives 7-9, mirror palette when the
  enemy is P1's character ("mirror true" at 18 -> 0 with P1 Goku).
- **End**: P1's team out -> state 0x11 -> result "lose" -> the game asks scene 0x14 (Game Over / Continue; V es2 f5038)
  -> `_gm_route` sends it to the select (4) and `_asr_win` raises `records_req` (ENDLESS: only on 0x14 + "lose";
  pause exits 3 / 0xD = no page). Pause "Return to Menu" ends the session as in ALL-STAR.
- **ENDLESS RECORDS page** (QoLAllStarRecords with `endless`): the ALL-STAR page's layout and art with: tab "ENDLESS"
  (white tab font; D = L's stem + O's right half, `_make_d`), the WINNER band's letters erased and GAME OVER set in
  the band's own typeface (`_bfont`: letters cut with `harvest_cc` from WINNER / GANADOR / SIEGER and VAINQUEUR's V,
  M = N's stem + V + mirrored stem `_make_m`; outline spacing gap 3; the word, wider than the band at full size, is
  scaled down as a whole by area averaging into the band's shades, `_shrink`) centred in the band (rows 140-183); table Enemies n / Hearts Used / Rank / Best (most enemies) /
  status; Total bar = TIME. Ranking plate "ENDLESS RECORDS" (the plate's own capitals, outline spacing); rows: enemies
  beaten + "KO" in the `no` digits' drawing (K = `KO_K`, O = digit 0) ending at x 122 like the game's score digits,
  faces, the time in the difficulty word's slot (same digits, underline); empty rows "--" / "--:--". Both pages: every
  number set from the digits' ink 1 px apart (`_packed`; the game's 8-px cells put a "1" in a gap), "Character Select"
  label 3 px off the plate's inner frame (`_label_room`).
- **File** `endless_records.cfg` (next to the exe; editor user://; `esrec=PATH`; capture runs without it: none):
  `[records] r1..r5 = {"beaten", "date", "frames", "hearts", "ids"}`; load needs beaten 1..99999 + the ALL-STAR
  checks; order `before_e` = more beaten, then shorter time, fewer hearts, older. beaten 0 -> "Not Ranked"; cheats on
  -> "Cheats On | Not Recorded"; write failure -> "File Error". Settings HI-SCORES RESET removes both records files
  (`reset_files`).
- **Isolation**: NEW GAMEMODES off -> no tile, no menu, no session (off-identity PASS). ALL-STAR with the part-38
  code = the part-37 code (V asnew / asold: identical AS lines for an `allstar=1 asstart=22` one-hit-KO battle incl.
  the records page; only the art log's new white "D"). MP / LAN never start a session (`_asb_session` / tile checks).
- Flags: `endless=1` (+ `allstar=1`), `esseed=N`, `esrec=PATH`, `esfake=N[:M:SS[:h]]`, `esrecdemo=F`.

## 8. BOSS RUSH (part 43) — status: DONE
Third NEW GAMEMODES mode (Gamemode menu slot 2): ALL-STAR's battle with the game's bosses. Facts: DATA_NOTES "part 43
findings (Boss Rush, Tournament)". Code: `QoLAllStar.mode` / `BOSS_ORDER` (qol_allstar.gd), QoLGame `# ---- BOSS RUSH
(part 43)` (`_br_loaded`, `_br_boss`), QoLAllStarStage (`BOSS_POOL`), QoLAllStarHearts (`_count`), QoLAllStarRecords
(`bossrush`), QoLAllStarMenu (BOSS RUSH bar), QoLController `AS_TEXTS[2]`.
- **Session**: `QoLAllStar.mode` (ALLSTAR / ENDLESS / BOSSRUSH / TOURNAMENT = the Gamemode menu slot; `endless` kept as
  the ENDLESS flag), `start(mode)`; `_gm_route` 0xB -> 4 starts the cursor's mode, B on the select returns the cursor
  to it. Enemies = `BOSS_ORDER` = every id with a boss version (docs/BOSS_CHARACTERS.txt), level 1 first, each level in
  story order, the Final Boss SSJ Goku last: 0 6 12 11 13 25 | 10 18 8 7 2 21 16 9 17 | 15 20 1 (18).
- **Battle** = an All-Star battle (`_asb_on`: Time Chamber, rolling 2-member P2 team, P1's HP carried, CPU tag / Team
  Arts refused, clock, HUD "n/18"). Every enemy record becomes the game's own boss version at `BOSS_LEVELS[id]` with
  `_make_boss` (the BOSS CHARACTERS cheat's: the level's parameter block -> boss HP 21000 / 26000 / 32000, stats, ki
  costs; opcode 0x92 boss branches -> gotos): the two loaded by the battle loader in its post-hook (`_br_loaded`), every
  reloaded one in `_asb_load` before its max HP is read (`_br_boss`). All are in `battle_bosses`, so the level-3 dash
  fix (`f_0202c1d4`) covers Cell / Broly / SSJ Goku. The global boss level stays 0 (the game's FUN_0202117C would give
  every CPU fighter one level). One heart (hearts = [true, false, false]; QoLAllStarHearts draws only the first).
  Music: the first FIGHT switches the stage BGM to a boss theme; the rotation then picks from BOSS_POOL (16 / 17).
- **End**: as ALL-STAR (won: results -> select + BOSS RUSH RECORDS page; lost: Game Over -> select).
- **Records**: QoLAllStarRecords with `bossrush`: ALL-STAR's page (time + hearts, Enemies n/18, WINNER banner), tab
  "BOSS RUSH" (the white tab font has no B / H: B = P over D's lower half `_make_b`, H = N's stems + a bar `_make_h`),
  plate "BOSS RUSH RECORDS" in the plate's own italic capitals (B = R's top half over D's lower half `_stack`, U = O
  with its straight middle row carried up the slant `_make_u`). File `bossrush_records.cfg` (`brrec=PATH`), the
  ALL-STAR entry format; "Practice / Not Recorded" after `brstart=` / `brorder=`; HI-SCORES RESET removes it too.
- **V**: br1 (headless, one-hit KO + infinite health / ki + ki homing, A spam): all 18 bosses at their levels (HP 21000
  x15, Cell 32000, Broly 26000, SSJ Goku 32000), 16 swaps, clock 02:00, win -> records page; music 5 -> 16 at the first
  FIGHT, 16 -> 17 at the track's end. br2 captures: HUD "16/18" + one heart. br3 (`brrecdemo`): the records page.
- Flags: `bossrush=1` (+ `allstar=1`), `brstart=N`, `brorder=a,b,c` (ids with a boss version), `brrec=PATH`,
  `brrecdemo=F`.

## 9. TOURNAMENT (part 43) — status: DONE (1 player; 2 players = a later part)
Fourth NEW GAMEMODES mode (Gamemode menu slot 3). Code: QoLTournament (qol_tournament.gd: the bracket), QoLTournamentPage
(qol_tournament_page.gd: the bracket page), QoLGame `# ---- TOURNAMENT (part 43)`, QoLAllStarMenu (4th bar).
- **Menu**: the Gamemode menu draws slot 3 with the second bar object whose texture handle (+8 = texture offset,
  0x4000) is pointed at +0x8000 for that draw only (`f_0205495c`); QoLAllStarMenu writes the Hard bar labelled
  TOURNAMENT there (free in scene 0xB: checked once, `tour_free`; else slot 3 is refused with the buzzer). Port bar
  letters B / O / U / H / space added; a label wider than the field (TOURNAMENT) uses the game's 1-column letter gap.
- **Bracket** (QoLTournament): 8 teams: player 1's (the select's picks + support) at a random slot, 7 CPU teams of 3
  different fighters (21 of the 26, none of player 1's); a stage per round (0-14); seeded (`tnseed=N`). Player 1's
  matches are fought; the other matches of a round are rolled when player 1's ends, weighted by the teams' total max
  HP (DATA_NOTES part 34 table) -- the game has no CPU-vs-CPU battle. Player 1 out -> the rest is rolled too.
- **Flow**: select GO (4 -> 0) -> `tour.hold`: the battle scene's function `f_02013064` returns 1 without running while
  the scene state is 0 (nothing loaded; 0 would end NitroMain's loop = soft reset) and draws the bracket there (P1's
  party is committed by then) -> the page opens; FIGHT (after the page's fade-out) clears `hold`. Battle start
  (`f_020140c8`, first step): P1 = its team / support, P2 = the opponent (3, no support), the round's stage, boss level
  0; after the loader the CPU level = the Option level + 0 / 2 / 4 (max 10; FUN_02013D60 hands it to the AI init after
  the loader). A normal Free Battle: the game's timer, tags, Team Arts, supports, no hearts, no All-Star rules
  (`_asb_session` excludes the mode). Won (results, 10) -> rerouted to a new battle (0) held for the page (next round);
  the final won / a match lost (0x14) -> the team select (4) with the page over it (CHAMPION! / KNOCKED OUT, OK).
  QUIT (pressed twice: QUIT -> CONFIRM) -> the held scene asks scene 4. Pause exits as ALL-STAR.
- **Page** (QoLTournamentPage, both screens, z 900, the records page's ROM art: hexagons, face icons, CharFace256
  portraits; port heavy capitals): upper = round name, P1's portraits | VS + "ROUND n/3" | the opponent's (mirrored),
  footer TITLES WON / BEST; lower = "TOURNAMENT" band, the bracket (two columns of 4 entries of 3 face icons, the whole
  bracket's lines grey, won paths yellow, P1's entry yellow + "1P", the match about to be fought blinking, beaten teams
  dimmed, the champion's leader face in the centre), buttons FIGHT! / QUIT or OK. Keys: Left / Right, A / START, B
  (= QUIT, again = quit; over: OK); taps on the buttons. Takes every key / tap while shown.
- **Titles**: `tournament_records.cfg` (`tnrec=PATH`): titles = n, best = {"frames", "ids", "date"} (the fastest
  tournament won, its battles' fight time); nothing while cheats are on; HI-SCORES RESET removes it.
- **V**: tn1 (debug start, one-hit KO, A spam): QF / SF / F won, CPU level 3 -> 3 / 5 / 7, 10 -> 0 reroutes, champion ->
  select; tn3: QF lost -> the rest rolled -> KNOCKED OUT page (0x14 -> 4) -> OK; gm1 / tn2 (menu path): bars, TOURNAMENT
  -> select -> GO -> page; QUIT -> CONFIRM -> select; GO again -> FIGHT -> battle. Preview `tour` states (tn_*).
- **Not yet**: 2 human players (local MP / LAN): the MP routing puts the second human on side 1 only; a later part.
- Flags: `tournament=1` (+ `allstar=1`: the btnrun Free Battle's P1 team enters a bracket), `tnseed=N`, `tndbg`,
  `tnrec=PATH`.
