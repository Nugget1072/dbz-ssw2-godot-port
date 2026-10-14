# DATA_NOTES index (decomp/DATA_NOTES.md, ~294 KB — never read it whole)

One line per `## ` section: start line (as of part 32; sections are only appended, so earlier numbers stay valid
unless text is inserted — re-check with the grep below), heading, gist + key addresses. Confidence letters (H/M/L,
V = verified, C = code read) are in the sections themselves. Keep this index current when adding a section.

**Grep tips**
- Section list with line numbers: `grep -n '^## ' decomp/DATA_NOTES.md`; read one with `sed -n 'A,Bp'` (A = its line,
  B = next section's line − 1) or the Read tool with offset / limit.
- An address: `grep -n -i '0x020DD4C4\|FUN_020DD4C4\|f_020dd4c4' decomp/DATA_NOTES.md` (functions appear as
  `FUN_XXXXXXXX` in notes, `f_xxxxxxxx` in code; RAM as `0x0XXXXXXX`, sometimes without `0x` in flag examples).
- A feature: grep its menu name in capitals (`BOMB RAIN`, `CHAOS SHUFFLE`) or a code section marker (`# ---- WEIRD 3`).
- Bold topic lines inside a section: `grep -n '^- \*\*' decomp/DATA_NOTES.md`.

## Containers, formats, ROM
| Line | Section | Gist / key addresses |
|---|---|---|
| 6 | ROM / container | header ADBP, ARM9 @0x4000 → 0x02000000 entry 0x02000800, ARM7 @0xE1A00, no overlays; module params 0x02000B68 |
| 12 | Compression | BIOS types; character frames RLE 0x30; pack members LZ10 |
| 15 | GARC archives (`*.arc`) | the game's own container layout (`garc.py`) |
| 22 | Named resource packs (`*.bin`) | pack header / 0x4C entries (`binpack.py`) |
| 30 | Characters | character table 0x020D62AC (stride 0x43), sprite GARCs, frame info, palettes, 'c' behaviour chunk |
| 68 | Stages | stage id → files via 0x020D5E7C; stg_N.bin 3D objects, textures, camera (least squares), 2D BG layers, battle coords; Ruins = id 10 |
| 107 | Sound | SDAT (TODO stub; real facts in part 11 / ARM7 sections) |

## Battle screens and fighter data
| Line | Section | Gist / key addresses |
|---|---|---|
| 110 | Battle HUD (top screen) | BG1 glyph library rows 24-30, life bars; 0x02101B3C |
| 126 | Battle sub screen (bottom) | engine B layers, palettes, panels (pixel-exact) |
| 134 | Fighter object (0x2D8 bytes) | record offsets; 3 per team block 0x8E8, P1 team 0x021075C8, pointer 0x020DE3D0 (see part 13 correction) |
| 297 | Game state used by the debug flags | fighter slots 0x021075C8 + i·0x8E8, HP s16 +0x24A (`clamp=` example) |

## Runtime, CPU, hardware (translator / emulation)
| Line | Section | Gist / key addresses |
|---|---|---|
| 158 | ARM9 runtime environment | boot crt0 0x02000800, autoloads (ITCM 0x01FF8000, DTCM 0x027E0000), NitroMain 0x02000B88, vblank wait, IRQ table, threads, PXI, card, save/EEPROM, FS, BIOS wrappers, 64-bit IO |
| 206 | Display output rules | 6-bit LCD colour, master brightness / BLDY formulas (vs melonDS) |
| 222 | ARM7 binary and its sound driver | load 0x02380000, autoloads 0x023A7760, WRAM / main-RAM segments, driver |
| 244 | ARM9 threads, timers | OSThreadInfo 0x020E31BC, OSThread layout, OS_SleepThread 0x020AA100 … |
| 263 | SDK functions with native fast paths | memory-pure SDK functions (0x020ABB30.., 0x020AEE38), FS path lookup — DSCoreBase._fast_call / native/src |
| 301 | DMA / card DMA details | MI_StopDma 0x020AB738, card DMA 0x020B20F4 / 0x020B24F0 / 0x020B2724 |
| 310 | Session 1 part 7 findings | large literal stack frames (12 functions), Story progress, texture palette memory, translucent polygons |
| 328 | Session 1 part 8 findings | quads clipped as one polygon |
| 336 | Session 1 part 9 findings | GPU attribute planes from snapped corners; ROM identification (CRC16 0x53C2, MD5) |

## QoL menu, sound, controls, display
| Line | Section | Gist / key addresses |
|---|---|---|
| 348 | part 11 (QoL menu, jukebox, sound switches) | Mode Select scene: VBlank slot 0x020DE374 = 0x020738E0, cursor u8 0x020DEC20 (4 = centre tile); BGM manager; SDAT; ARM7 SND driver state |
| 371 | part 12 (menu restyle) | font `romdata/scene/font_eu.bin` (9x15 cells), Mode Select lower layers, header bar, OPTION MODE screen |
| 555 | part 16 (buttons, banner icon, presenter) | battle buttons → actions (A 0x24, B 0x18, X 0x20, Y 0x1C, R 0x0C/0x0D, L 0x29) via FUN_0202AEB4; banner icon; presenter margins |
| 571 | part 17 | smooth-motion edge gap, fighter shadows (not a bug), boss + shuffle |
| 1147 | part 22 (mode select tile) | lower screen = engine A, tiles are 3D quads, tile textures (PORT tile), load timing |
| 1183 | part 22 (QA: menu options) | tile 4 → scene 2 (boot) via FUN_02073AAC / 0x020DEC20; watchdog vs frozen PC; settings.cfg typing; input map while a key is held |
| 1293 | part 23 (leaderboard) | save copy 0x020DD5B4 (FUN_02004CD8), HI-SCORE RANKING 0x020DD5C4 (5 × 0x14, insert FUN_02002560, defaults 0x020B6888), story progress 0x020DD628 |
| 1327 | part 24 (gamepad cursor) | touch input path (filter_input → arm7.set_touch), input map, QoLCursor, scripted K-key timing |
| 1415 | part 24 (auto skip) | story scene FUN_0203E87C / FUN_0203E944, state 0x020DE4EC, SKIP / EXIT buttons, progress kept, Z-Battle VS screen (0x020DD514 mode) |
| 1466 | part 24 (QA / runtime) | card DMA vs VBlank freeze is not a port bug (FUN_020B24F0, DMA3 0xAF000001), which reads, repro; menu QA; mirror vs pause |
| 1508 | part 25 (input display, CRT TV) | pad block 0x020DD4DC (FUN_0200124C; bits), fighter copy ≠ raw pad; INPUT DISPLAY; CRT TV |
| 2651 | part 32 (performance mode) | Deck perflog analysis, where a game frame goes, line registers, exact speed-ups, PERFORMANCE MODE, expected Deck effect |

## Cheats and character / stage systems
| Line | Section | Gist / key addresses |
|---|---|---|
| 388 | part 13 (cheats) | team blocks correction (0x021075C8 / 0x02107EB0, +0x8C8.., ki +0x8D0), damage FUN_020293A4, ki FUN_02027950, input, action dispatcher, effect objects, character select |
| 428 | part 14 (bosses, battle start, portraits) | boss level u8 0x020DD510 (FUN_02001EA4 / FUN_02001EB4), FUN_0202117C parameter blocks, battle start, portraits |
| 451 | part 15 (assists, music) | assists FUN_02026C00 / FUN_020277AC / FUN_0202CC70, Team Arts FUN_02026E34; BGM functions |
| 474 | part 16 (character shuffle) | fighter load FUN_0202A40C / FUN_0202A094, file table, file manager, heap, OBJ VRAM / palettes FUN_02010B6C, lower panels, tag, CHARACTER SHUFFLE |
| 579 | part 18 (stage shuffle) | stage loader FUN_0201C150 (record 0x020CFAC8), 3D stage FUN_0201AC48, texture / palette manager, fighter bounds, stage ids, STAGE SHUFFLE, card DMA during swap |
| 660 | part 18 (dash, attack spam) | R dash FUN_020272F0 / FUN_0202C1D4, parameter block, boss dash overflow, melee hits, ATTACK SPAM FUN_0202B630 |
| 712 | part 18 (chaos shuffle, triple ki) | action dispatch FUN_0202954C (table 0x020D7958), effect life FUN_0202104C, camera, freeze, CHAOS SHUFFLE, TRIPLE KI FUN_020225C8 |
| 815 | part 19 (chaos fixes) | throws (table 0x020D76BC), grab supers (FUN_02028DDC, 0x020D7724), summons, visibility, chaos waits |
| 897 | part 20 (graphics) | effect life flags FUN_0202104C (pool 0x020DE3CC), step dash, NO COOLDOWN dash-line bug, regression scan |
| 2122 | part 29 (SAME CHARACTERS team rules) | select tests, START / auto confirm, why two supports were wrong in single player, rule now (FUN_0206CC94 / FUN_0206ABB0) |

## Picture / text effects (weird stuff, zoom, shadows)
| Line | Section | Gist / key addresses |
|---|---|---|
| 770 | part 19 (shadows) | battle sprites = 3D quads, list [0x020DE384] drawn by FUN_02011384; ground shadow FUN_0202A254; DETAILED SHADOWS |
| 850 | part 20 (camera zoom) | camera struct 0x020DE3A4 → 0x021003CC (+6 zoom 8.8), readers of +6, stage projection FUN_020A7710, CAMERA ZOOM |
| 930 | part 21 (zoom: stage object culling) | stage script op 0x11 (FUN_0201A794), repeating props / panorama pairs (FUN_02019C74), culling fix |
| 975 | part 21 (2nd fiddle) | mirror palettes in FUN_0202A094 (P2 record, id < 0x1A, same id in P1 team) |
| 993 | part 21 (text) | only story / tutorial script text is strings (script.bin, drawer FUN_0200B954, 128 glyphs); encoding; boxes; everything else images; EPIC MODE |
| 1036 | part 21 (BEVEL EMBOSS, TOUCH FUZZY) | scene byte 0x020DD4C4, battle state 0x020DD4C5 (states 1-9), sprite projection, effects |
| 1083 | part 22 (battle signal, GAME BOY, MIRROR) | scene table 0x020B6278 (0 battle FUN_02013064 … 6 Mode Select), battle-on-screen = VBlank handler 0x027E0004 == 0x02013030 |
| 1125 | part 22 (blood, afterimages) | hit damage entry FUN_020293A4, feet line, world → screen, BLOOD / AFTERIMAGES |
| 1205 | part 23 (text: Data File, credits) | resource pack loader FUN_02009B28 (table *0x020DE214), Data File, staff credits, EPIC pictures |
| 1247 | part 23 (blood scaling, flashy ki, confetti) | effect handlers per kind (0x020209E0, 0x02020A84 …), slow motion, BLOOD scaling, FLASHY / CONFETTI |
| 1274 | part 23 (SCREEN SHAKE) | hit damage values (198 / 297 / 1080 / 2000 / 120 per frame), SCREEN SHAKE |
| 1360 | part 24 (weird 3) | sprite drawer per sprite FUN_020A71C8, hit damage stream, hit-stop, DAMAGE NUMBERS, RAINBOW KI, JELLY FIGHTERS (removed part 25) |
| 1548 | part 25 (bomb rain) | ki-blast hit path FUN_0201E9EC, HP scale, explosion FUN_0202247C / FUN_0202216C, SE, hurt box FUN_0201DF20, battle states, BOMB RAIN |
| 1617 | part 26 (bomb sprite) | smooth-motion pairing by polygon number; texture VRAM reservation (0x020DE380); one textured quad per bomb; other port effects |

## Local multiplayer (design: docs/MULTIPLAYER_DESIGN.md)
| Line | Section | Gist / key addresses |
|---|---|---|
| 1695 | part 27 (multiplayer research) | scene table 0x020B6278, game mode u32 0x020DD514, VS menu scene 0x11 FUN_0207BA08, select scene 3 FUN_0206DCE8, outline, stage scene 5, battle input FUN_02012DA8, touch per side, pause / end, wireless "human P2" |
| 1823 | part 27 (MP input / menu) | FUN_0207B778 early return, VS menu boxes, scene 0x11 exit, scene 3 B → FUN_02001014, fades, port input |
| 1869 | part 27 (MP battle) | P2 input via FUN_0202DCE0, touch per side, Team Arts conditions, panel lighting, MP panel, cheats in MP |
| 1915 | part 27 (MP select / stage / loop) | select key repeat / touch rects / READY? / sounds, FUN_0206ED18, cursor objects, stage icons, loop stability |
| 1978 | part 27 (MP QA) | WIN / LOSE banner, Touch! plate, grey-outs, pad cursors, VS BATTLE tile |
| 2026 | part 28 (MP select / panel) | per-side DP bytes (0x020DE7C8 / 0x020DE7E4 / 0x020DE800), supports per team, two supports (FUN_02026C00 / FUN_020277AC) |
| 2071 | part 28 (MP cheats / weird QA) | face icon upload queue, shuffle icon per side, STAGE SHUFFLE garbled-frame fix |
| 2157 | part 29 (MP battle: touch light, dual assists) | Team Arts partner bit (FUN_02026548), one assist slot → per-side slots (FUN_0202B580 / FUN_0202759C / FUN_0202B4A0) |

## LAN multiplayer (design: docs/LAN_DESIGN.md)
| Line | Section | Gist / key addresses |
|---|---|---|
| 2217 | part 30 (LAN research) | battle RNG (FUN_020019FC(1), 0x020DD7B4), other RNGs, instance ids, frame counter, save copy, determinism, drawing-only fields, wireless host path, ENet |
| 2287 | part 30 (LAN core) | lockstep result, exit frame, sync at FUN_020140C8, pause abort, disconnect / desync detection, snapshot, BOMB RAIN in LAN, pacing, rejects |
| 2348 | part 30 (LAN menus) | VS menu LAN → port pages (FUN_0207B778), ":" key, connect timeout, two instances |
| 2386 | part 30 (LAN select / stage / battle) | HOST path on both, scene 4 loop FUN_02066558, scene 5 loop FUN_0207197C, stage icon → id, guest panel, stalls, cheats |
| 2451 | part 30 (LAN QA) | PING = frame rate bug, rejoin deadlock, false DESYNC, window close, dead peer, matrix, `lanbattle=1` needs `lanbstage` |
| 2532 | part 31 (LAN menu exit) | layers lost after the LAN pages: cause / fix / verified |
| 2564 | part 31 (LAN rejoin / disconnects) | root cause + 5 fixes (ids on every message, resets, fresh STAGE_RESULT, host battle ids, watchdog), notices, matrix, debug flags |
| 2684 | part 32 (LAN pause) | battle pause menu is on the UPPER screen (state 0x020DD4C5 = 9), guest panel fix, pause lag not found |
| 2734 | part 32 (combined verification) | "L277 desync" = harness artefact; lockstep on the combined tree; off-identity |
| 2762 | part 34 (All-Star research) | Mode Select tile → scene/mode (`FUN_02075738`), Maximum course select scene 0xB (state 0x020DE554, exit 0x020DE560, objects q+0x14.., draw `FUN_0205495C`), team select exit, character names 0-25, KO replacement state 0xC, revive `FUN_020298D4`, timer / HUD cells, Time Chamber = stage 4 (BG3 sky palette 32-191), stream position [0x020DE33C]+0x158, HI-SCORE RANKING art (result.bin), battle lower layout |
| 2835 | part 34 (All-Star menus) | Mode Select label rows / letter columns, course-select object palettes / textures (header +0x1000, cursor +0x0), bar font, scene 0xB exit codes, scene 4 in mode 5 (teardown asks scene 2 first), Free pause items, course-select upper-screen colours |
| 2867 | part 34 (All-Star battle) | per-frame hook `FUN_020010F4`, battle states (7 = FIGHT, 0xC KO replacement, 9 pause, 0x11 end), KO'd CPU record reload (HP = u16 *(rec+0x50)), mirror rule of `FUN_0202A094` (any P1 record), max HP per character, 24-swap heap / file-cache check, CPU tag / Team Arts taps, revive `FUN_020298D4` + heal `FUN_02029428`, HUD BG1 tiles (0x100-0x1FF free) / glyph layout, pause window |
| 2908 | part 34 (All-Star records) | result.bin formats (4-bit linear ntft; rank rows, title plate, digits, Character Select plate; e_res_bg = upper results screen), ranking layout (rows y 28+32i, digits x≤122, faces x 128/152/176), faceicon.arc entries 2·id / 2·id+1 (24x24 icons, supports 26-36), COURSE SELECT header texture +0x1000 (palette 0 greys, rows 8-22), win → scene 10 timing, P1 support 0x020DD53C at the end, records file rules |
| 2950 | part 34 (All-Star stage) | BG manager 0x020DD7BC (queue +0x180, map buffers +0x1AC, palette shadow +0x1D8), Time Chamber sky = BG3 + 3D light-ray objects 5/6 (texture 3; visible flag S+0x44+i·0x3C+0xA), translucent hourglass glass, stream counter blocks / offset start, battle BGM keeps playing in pause (+0xA2 bit 0 already set), rotation timings |
| 2984 | part 35 (All-Star records redesign) | scene 10 upper screen = engine B (BG0 portraits 256-col ext palette, BG1 e_res_bg, BG2 hexagons), portraits CharFace256.bin <abbr>_face (80x40, one palette gkn_face.nbfp, nul1 = empty), hexagons common_bg.bin cstat_bg (64x64 tile, scroll 35/477 +0.5/+1.1 px/f), e_res_bg layout + digit strips (yellow 8x16 y 192, orange 8x12 y 208), lettering of the table / tab / title plates / difficulty words (glyph sources, missing letters), cursol = 256x32 cursor frame + triangle |
| 3034 | part 35 (All-Star sky) | stage 4 BG3 never scrolled (HOFS / VOFS 0; parallax = BG2), horizon y ≈ 100-145, engine A BG VRAM = bank D layout (BG3 chars 0x14000-0x1B800 = 480 tiles, 0x1C000 another map), port sky budgets (386 tiles, palette 32-188: ramp / nebula / 36 twinkle slots / 6 glints), pause grey-out applies to BG3, off-identity |
| 3069 | part 35 (All-Star life bars) | life-bar colour buffers per member (B = *(0x020DE3BC)+side·0x258: +0xF3C buffers, +0xF4D slot→buffer, +0xF4A/B shown/target, colours per member yellow / lavender / green), who repaints (per-frame active only, FUN_0201CBBC swap, FUN_0201C5C0 revive), bench-heal bug + port fix |
| 3099 | part 36 (green demon) | battle SE ids by caller (FUN_02029E3C; 0x1E ki-blast explosion, 0x2B big explosion), fighter speeds, FUN_02021DD4 effect mover (24.8), base Goku size, GREEN DEMON rules (spawn / chase / catch-up / kill / warp / MP targeting), shared port texture block, LAN check |
| 3144 | part 37 (editor vs exe) | exe = editor frame-exact; the divergence was the user:// settings fallback for a fresh qolcfg (fixed); texture-manager block list in battle RAM |
| 3156 | part 38 (Endless) | Free Battle loss -> scene 0x14 (P1 / P2 record HP addresses of the btnrun battle), gameover_dat.arc GARC layout (Continue? plates, Game Over emblems; English title box), WINNER band rows 139/184 + one typeface in five words (letter sets, touching letters), digit-strip cells ("1" at the right), e_charasele inner frame x 250, cursol = frame only, Gamemode menu third bar (+0x6000), 47-swap heap check |
| 3186 | part 39 (parry etc.) | +0x10 bit 0 = on the ground (correction), FUN_020214C4 floor / landing (pool +0x4DEA / +0x4DEE), FUN_020213A8 / FUN_02021264 motion, held vs pressed input tests + dispatcher branches, collision list 0x020DE3C0 + box test + hit handlers, dash-attack reflect, guard spark 0xB, hit stop, palette slot for silhouettes, battle SE analysis (0x21), randomizer / flightless / knockback notes |
| 3232 | part 40 (ultimates etc.) | FUN_02026A8C ultimate test conditions (red HP = shown bar < 0x17, +0x24E once, direction rule blk+0x23) and that it spends the 150 % itself, camera tether FUN_02019594 (504 / 378 px, +0x250 & 0x20000), ground takeoff speeds / jump, plain-shot handler outside the fight |
