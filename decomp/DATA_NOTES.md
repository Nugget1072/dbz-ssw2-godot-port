# DATA_NOTES — DBZ Supersonic Warriors 2 (EU, ADBP) format & rules knowledge base

Confidence: **H** = verified by render, emulator RAM or code; **M** = strong guess; **L** = hunch.
Addresses are ARM9 RAM addresses (ARM9 binary loads at 0x02000000, file offset = addr − 0x02000000).

## ROM / container
| What | Notes | Conf |
|---|---|---|
| Header | title `DRAGONBALLZ2`, code `ADBP`, maker `B2`. ARM9 @0x4000 size 0xDD8F8 → 0x02000000, entry 0x02000800. ARM7 @0xE1A00 size 0x27778. No overlays. ARM9 is **not** compressed (module params at 0x02000B68: compressed-end = 0). | H |
| NitroFS | 304 files, all under `romdata/`. Extract: `decomp/tools/nds_extract.py`. | H |

## Compression (`decomp/tools/ndscomp.py`)
Standard DS BIOS types. Character frames use **RLE (0x30)**; `.bin` pack members use LZ10 when stored size < unpacked size. | H |

## GARC archives (`*.arc`, `decomp/tools/garc.py`) — the game's own container (not 3DS GARC)
```
0x00 'GARC'  0x04 u32 file size  0x08 u32 count N  0x0C u32 data start
0x10 N × {u32 offset (from data start), u32 size}
```
Nested GARCs occur inside `charadata.arc`. | H |

## Named resource packs (`*.bin`, `decomp/tools/binpack.py`)
```
0x00 u8 version(3/4) u8 flags u16 N   0x04 u32 header size (= 8 + N*0x4C)
entries: char name[64] ("dir\\file.ext"), u32 unpacked size, u32 stored size, u32 offset (from header end)
```
Member types seen: `ntft` (3D texture data, raw, no header), `ntfp` (3D texture palette), `nbfc` (BG tiles), `nbfs` (BG screen map), `nbfp` (BG palette), `bin`, `tbl`, `dmy`, `pltt`. Texture size/format is NOT stored with `ntft`; it comes from code or companion tables (TODO). | H (layout) |
Not packs: `game/stg_*.bin` (stage 3D, see below), `charselect/list3.bin` (version 1, TODO).

## Characters
### Character table @ 0x020D62AC (ARM9), stride 0x43, indexed by character id
```
+0 u8  charadata.arc index of the 'c' (behaviour) chunk
+1 u8  charadata.arc index of the frame-info GARC
+2 u8  charadata.arc index of the palette (512 bytes = 16 sub-palettes × 16 colours, BGR555)
+3 char path[64]  e.g. "/romdata/chara/gkn_img.arc"
```
Loader: function 0x02020D4C (r1 = id). Same table continues with `*_eff_img.arc` (effect sprites), `cmneffect_img.arc`, `win_img.arc`. | H |

Character ids (table order): 0 gkn Goku, 1 gks SSJ Goku, 2 ghk Kid Gohan, 3 gho Gohan(teen?), 4 crr Krillin, 5 pic Piccolo, 6 vgn Vegeta, 7 vgs SSJ Vegeta, 8 trk, 9 gtk Gotenks, 10 frz Frieza, 11 frm (Frieza final/Mecha?), 12 gnu Ginyu, 13 drg, 14 egh, 15 cel Cell, 16 bmr, 17 bmj, 18 col Cooler, 19 com Metal Cooler, 20 brl Broly, 21 vga, 22 trn Trunks, 23 gtn, 24 ghn, 25 cey, 26 tsh, 27 dnd Dende, 28 stn Hercule, 29 sxsv, 30 bvd Babidi, 31 cej Cell Jr, 32 zbdd, 33 bdk Bardock, 34 dbr Dabura, 35 srn Shenron, 36 nmz. (names beyond the 3-letter codes are M/L until checked against the select screen.)

### Sprite images `chara/<id>_img.arc` (GARC)
Each entry = one frame image: RLE-compressed, 8192 bytes = **128×128, 4 bpp, linear (not tiled)** — a DS 3D texture (format 3, 16-colour). Pixel 0 = transparent. Low nibble = left pixel. | H (rendered) |

### Frame info (nested GARC in charadata.arc, index = table byte +1)
One entry per frame (frame count may exceed image count):
```
u16 image index, u16 origin x (64 = image centre), u16 origin y, u16 box count
box × count: s16 x, s16 y, s16 w, s16 h (relative to origin), u32 kind (2 = hurt box, 1 = ? attack)
```
| H (layout) / M (box semantics) |

### Palettes (charadata.arc 0..75)
Body palette for Goku = entry 41 (from table). Sub-palette 0 = normal, 1 = red (Kaioken/damage?), 6 = white flash, others = effects/alt costumes. Colour 0 of each 16 = transparent. | H (index) / M (meanings) |

### Behaviour data 'c' chunk (e.g. charadata 117 = `cgkn`)
```
0x00 char[4] 'c'+id   0x04 u32 offset → action offset table (u32 each, relative to script base)
0x08 u32 ?(0x60)       0x0C u32 offset → script base           0x10 u32[4] offsets → 4 param blocks of 0x28 bytes
```
Scripts are bytecode run by the **character VM at 0x02022A60** (opcode = first byte, 0x00–0x92, jump table at 0x02022ADC). Opcode lengths extracted from handlers → `decomp/tools/charscript.py`.
Known ops (H unless marked):
- `00` (10 bytes) action header; sets loop point.
- `01` loop/end: arg byte 0 → jump back to action start+10.
- `03` (8 bytes) **show frame**: `03 xx u32 dirtable_off u16 duration`. `dirtable_off` (from 'c' base) → 16 × u16 frame ids indexed by the fighter's facing/travel angle ((angle+0x40)>>3, ≥16 = mirrored). Duration (frames) stored at fighter+0x10C.
Fighter object: 0x8E8 bytes (P1 at 0x021075C8 in a Free Battle; P2 at +0x8E8). +0x38 s32 x, +0x3C s32 y (fixed point), +0x44 ptr to 'c' chunk, +0x104 loop pointer, +0x10C frame timer, +0x118 script ptr. | H (RAM-verified) / M (fixed-point scale) |

## Stages
Stage id s (0..14) → files `stg_{s+1}.bin/_tex.bin/_scr.bin` via pointer table 0x020D5E7C (3 ptrs per stage). Loader 0x0201C1xx. | H |
Stage-select order ≠ file order: the "Ruins" stage (first stage-select icon) is stage id 10 = `stg_11`. | H (RAM/VRAM) |

### `stg_N.bin` — 3D background objects (H, decoded by `decomp/tools/gx.py`, matched to emulator polygons)
Chain of objects, each with a 0x58-byte header:
```
+0x00 u32 display-list start (absolute; first object: 0 → list starts at 0x58)   +0x04 u32 display-list size
+0x08 s32[3] scale (20.12, always 1.0)   +0x14..0x2B zeros (rot/trans)
+0x2C..0x3F material/texture params (TODO)   +0x40 u32 texture index into stg_N_tex.bin
+0x48 u32 DIF_AMB 0x4A524A52, +0x4C SPE_EMI 0x739C, +0x50 0x0022FF1F (poly attr?)   +0x54 u32 next object offset
```
Display lists use the **packed GX command format** (VTX_16/VTX_DIFF/VTX_XY/XZ/YZ/VTX_10, TEXCOORD, NORMAL, BEGIN/END). No TEXIMAGE_PARAM inside: the texture is per object.
Objects 0 and 1 are the two halves of a horizontally looping panorama (period 8.0 model units); small objects are props.

### `stg_N_tex.bin` — texture chain (H)
`u16 w, u16 h, u16 format<<8 (3=16c, 4=256c, 6=A5I3), u16 palette bytes, u32 palette off, u32 texel off, u32 texel bytes, u32 next record (0 = last)`.
Texture params seen in the emulator: repeat S+T, colour 0 transparent, texcoord transform mode 1.

### Stage camera (H — solved by least squares from melonDS clip-space vertices, residual 0.001)
`clip = P · V · model`, with **P = perspective, fovy 60°, aspect 4:3**, and
`V(model) = 128·(model + (tx, ty, 0)) + (0, 0, −1)`
`tx = (9216 − camX) / 256` (mod 8, object 1 drawn at tx − 8), `ty = (camY − 8216) / 1024`
camX/camY = camera centre in battle pixels (s32 at 0x021003D8 / 0x021003DC). The 3D stage therefore scrolls at
parallax 1/2 (x) and 1/8 (y) in view units. Render runs one frame behind the RAM value (±1–2 px). Zoom (u16 at
0x021003D2, 256 = 1.0) shrinks when fighters are far apart; effect on the stage TODO.

### 2D background layers (engine A, behind the 3D layer) — `game/game_bg.arc`
Per-stage table at 0x020CFA40, stride 9: `u8 BG2 tiles, BG2 map, BG2 palette, BG3 tiles, BG3 map, flag, ?, flag, BG3-affine` (GARC indices; BG3 palette = BG3 tiles + 1).
BG2 = 512×256 text BG, 256 colours (distant horizon panorama, priority 2). BG3 = sky (priority 3): 256×256 affine
(1-byte map) when the last flag is set, otherwise 256×256 text. BG1 (priority 0, above 3D) = HUD/overlay (TODO).
Engine A DISPCNT in battle 0x08010F09 (mode 1, BG0 = 3D). Ruins: tiles 17/map 19/pal 18, sky tiles 20/map 22/pal 21. | H |
Scroll parameters per stage: u16 tables at 0x020CFAC8.. (TODO).

### Battle coordinates
Fighter x/y are s32 **24.8 fixed-point pixels** (fighter+0x38/+0x3C). Free Battle start: P1 (8127, 8128), P2 (8161, 8128), camera (8143/8144, 8128).
Fighters (and the whole HUD) are drawn as **orthographic 3D quads** (W = 1.0): 128×128 4bpp textures placed 1:1 on
screen, P2 mirrored with flipped texcoords. Screen centre (128, 96) = camera centre. | H |

## Sound
`sound/sound_data.sdat` (29.7 MB) standard Nitro SDAT. TODO.

## Battle HUD (top screen) — H unless marked
- **BG1** (priority 0, above the 3D layer), 4bpp text 256×256: tiles `game_bg.arc#0`, palette `#1` loaded into
  BG palette row 15, base map `#2`. Map rows 24–30 (off-screen) are a **glyph library**: rows 24/25 cols 0–9 =
  small digits (top/bottom halves), cols 21–30 = timer digits; rows 28–30 = ki-gauge icon variants. The game
  copies glyph entries into the visible rows: timer at cols 14–17 rows 0–1, P1 ki % at cols 1–3 rows 21–22,
  P2 at cols 28–30. Engine A DISPCNT bits 27–29 = 1 → BG map base +0x10000.
- **Life bars** = orthographic 3D quads using `game_bg.arc#6` (128×16, 256 colours, palette `#5`). Row 2 of the
  texture holds one palette index per column (16..86, 71 columns): the game shows life by recolouring those
  palette entries every frame — 0x033F yellow = remaining, 0x3484 dark blue = lost, 0x19F2 flash at the edge,
  0x001F/0x1852 red when low. Visible columns = floor(hp × 71 / 12480) fits 8 samples exactly (M); the shown
  value drains toward the target over several frames. P2 = same quad mirrored (x 127..255) with its own palette.
- Red damage bars `#4` (64×8, palette `#3`) at x 119 / 137, width 0 when idle (TODO semantics).
- Face icons `game/game_faceicon.arc` entries 2·charid (32×32 4bpp) + 2·charid+1 (palette), at (0,0) and (232,0).
- Top-centre counter: RAM u16 0x02101B3C, starts 1800, decrements irregularly every 5–9 frames (TODO: code).
- Fighter HP: fighter+0x24A (13000 at start for Goku and Vegeta).

## Battle sub screen (bottom) — H (pixel-exact vs melonDS)
Engine B, DISPCNT 0x11700, palette = `game/game_bg.arc#102` (all 16 rows; colour 0 = backdrop).
- BG0 (0x1500): tiles `charselect/SubScrNBFC.bin:<p1>.nbfc` at tile 0 + `game/game_subbg.bin:e_pairatk.nbfc` at
  tile 0x7E. Map: fill 0x0007; `SubScrNBFS.bin:<p1>.nbfs` cols 0–9 rows 0–15 at col 1 with palette 1 (col 0 =
  0x1007); `e_pairatk.nbfs` rows 0–6 → rows 16–22 plus 0x7E. Scroll (0, −8).
- BG1 (0x1605) / BG2 (0x170A): empty team-member slot `nul1.nbfc/.nbfs` over a 0x0004 fill, scroll x 424 / 344, y −8.
- `e_` = English pack member (f/g/i/s = other EU languages).

## Fighter object (0x2D8 bytes; 3 per team block of 0x8E8 — see part 13 correction; P1 team at 0x021075C8, pointer at 0x020DE3D0) — M unless marked
| off | meaning |
|---|---|
| +0x04 | u8 VM status (2 = action finished) (H) |
| +0x05 | u8 C-state index → handler table 0x020D785C (H) |
| +0x06 | u8 current action id (H) |
| +0x07 | u8 facing angle (0 = right, 128 = left) (H) |
| +0x0E | u16 flags (bit 8: use +0x07 for sprite direction) |
| +0x1A | u8 player index (H) |
| +0x20 | u16 movement angle |
| +0x22/+0x24 | speed / max speed (664 while flying) |
| +0x28..+0x2E | velocity components (decay 21/frame after release) |
| +0x38/+0x3C | s32 x/y, 24.8 fixed pixels (H) |
| +0x44 | ptr to 'c' behaviour chunk (H) |
| +0x100/+0x104 | VM animation start / resume pointer (H) |
| +0x10C | u16 VM frame timer (H) |
| +0x118 | VM action-header pointer (H) |
| +0x140/+0x142 | s16 screen x/y of the sprite origin (H) |
| +0x24A | s16 HP (H) |
| +0x26C..+0x270 | input bits (16 = right, 64 = up, 2 = A …) |
| +0x288/+0x28C | previous-frame x/y |
Fighter update: 0x0202954C; VM: 0x02022930; effects/objects: 48 × 0x164 + 8 at globals+0x42C0 (0x02021F54).
Battle globals pointer: 0x020DE3CC. Camera: 0x021003D0 (+2 zoom, +8 camX, +0xC camY).

## ARM9 runtime environment (for the translated code) — H unless marked
- **Boot** (crt0 0x02000800): IME=0, CP15 setup, stacks in DTCM (0x027E0000), clears DTCM, palette (1 KiB), OAM
  (filled with 0x200), autoloads from module params at 0x02000B4C {list 0x020DD8E0..0x020DD8F8, src 0x020DD4C0,
  bss 0x020DD4C0..0x020E6680}: ITCM 0x3C0 bytes -> 0x01FF8000 (OS_IrqHandler, DMA/GX-FIFO helpers), DTCM 0x60
  bytes -> 0x027E0000. Then *0x027FFF9C=0, *0x027E3FFC=0x01FF8000 (BIOS IRQ vector), 0x020B6220 (empty),
  0x02000B48 (empty), 0x020B6234 (static ctors, list 0x020D53C4) and NitroMain = 0x02000B88.
- **NitroMain 0x02000B88**: SDK init, then `do { 0x02002C18; 0x02001014(0xF); vblank wait; 0x020A5298; inner loop }`;
  inner loop: `++u16[0x020DD4C0]; keys 0x0200124C; touch 0x020105C0; if (!scene_update 0x020010F4) break; wait;
  0x0209FE54 (SND reply housekeeping); soft-reset combo check; 0x02003360 (card pull-out check + sound)`.
- **Vblank wait** = 0x0200077E (Thumb: `svc 5`, SVC_WaitVBlankIntr). Called from main and ~110 scene loops.
- **IRQ table** OS_IRQTable at DTCM 0x027E0004 (one handler per IE bit). Battle: VBlank 0x02013030,
  HBlank 0x0201B254 (per-line BG3 affine for the sky; counters 0x020DE3AC/B0/B4/B8). Boot: VBlank 0x02000FD0.
- **Threads** (OSThreadInfo 0x020E31BC: +8 current thread): NitroMain = launcher thread 0x020E32A4; idle 0x020A9E44;
  CARD worker 0x020B29F0 (CARDi_SetTask 0x020B1A2C posts a job; common block 0x020E5240: +0x3C job, +0xE0 flags,
  +0xDC wait queue); sound stream 0x020A2DB4 (NNS stream decoder, woken by an alarm). OSThread context: +0 cpsr,
  +4 r0-r12, +0x38 sp, +0x3C lr, +0x40 pc+4.
- **Runtime library**: 0x020B5E30 _s32_div_f, 0x020B603C/6044 _u32_div_f (quotient r0, remainder r1),
  0x020B5C28/5C34/5C70/5C80 64-bit udiv/umod/smod/sdiv. 0x020AB358/36C/380/398/3AC/3C4 = OS_Enable/Disable/
  RestoreInterrupts(+Fiq variants)/GetProcMode. 0x020AB3E8 = OS_Terminate (assertion failure). 0x020AB3DC = OS_SpinWait.
- **PXI** (IPC FIFO): callbacks table 0x020E5028 (32 tags); ARM7 "callback ready" bits at 0x027FFF8C (0x7FF0);
  send 0x020AD668(tag, data, err) -> word = tag | err<<5 | data<<6; receive IRQ handler 0x020AD544.
  Services seen: 5 RTC (cmd bits 8-14; date at 0x027FFDE8, time 0x027FFDEC, BCD), 6 touch (reply 0x01000000|cmd<<8;
  raw ADC at 0x027FFFAA: x 12 bits, y 12 bits, bit 24 touch, 25-26 validity), 7 sound (data = SNDCommand list
  address; command = {next, id, arg[4]}; 0x1D = shared work (0x020E3540); ARM7 increments SharedWork+0 per list),
  8 PM (0x65 read register -> reply cmd 0x70+reg | value), 11 CARD backup (request number with error bit set;
  request 0 is followed by the command block address 0x020E5200 {+0 result, +4 type (0x0D01 = EEPROM 8 KiB),
  +0xC src, +0x10 dst, +0x14 len, +0x18 total size, +0x20 page size, +0x24 address width, +0x28 caps};
  2 identify, 6 read, 7 write, 8 program, 9 verify; answer = error-bit word), 12 OS, 14 CARD (pull-out).
- **Game card**: ROM reads by the CPU (0x020B23F0, command 0xB7 + address, 0x200-byte blocks via ROMCTRL
  0x040001A4 / data 0x04100010) or by DMA (start timing 5) + card IRQ (bit 19, handler 0x020B264C). The SDK polls
  the chip ID (command 0xB8) every frame (0x02003360 -> 0x020B2B00) and treats a mismatch as a pulled-out card.
- **Save**: 8 KiB EEPROM; the save starts with "DBZ2" and stores the console MAC at offset 0xA (checked at boot).
  16 blocks of 0x200 bytes: +0 "DBZ2", +8 u16 CRC = BIOS GetCRC16(initial 0x325A4244 masked to 16 bits = 0x4244,
  data = block +0x10, 0x1E4 bytes) (check 0x0208F648 -> 0x02004CD8; result 5 = "save data corrupted" screen
  0x0208F22C). CRC-16 is the reflected 0xA001 polynomial (= the cartridge header CRC). H (all valid blocks of the
  user's save match).
- **BIOS wrappers** (Thumb `swi n; bx lr`, arguments in r0-r3): 0x02000080 CpuSet (0x0B), 0x020000DC WaitByLoop
  (0x03), 0x0200021C GetCRC16 (0x0E), 0x0200077E VBlankIntrWait; the table at 0x02000000-0x02000800 has the rest.
- **EEPROM addressing** wraps at the chip size (8 KiB) like the hardware. M.
- **FS**: ROM archive 0x020E50D4 (read proc 0x020AF764 -> CARD read, async: completion 0x020AF7B0 ->
  FS_NotifyArchiveAsyncEnd 0x020AE478). FS_InitFile 0x020AF444, FS_OpenFile 0x020AF0F4, FS_SeekFile 0x020AEF14,
  FS_ReadFile 0x020AEF80, FS_CloseFile 0x020AF0AC. Character frames are read from the ROM on demand.
- **64-bit IO accesses**: VEC_Normalize (0x020A4F38) and friends store 64-bit operands to DIV_NUMER/DENOM
  (0x04000290/0x04000298) and SQRT_PARAM (0x040002B8) with `strd`; truncating them to 32 bits zeroes every
  look-at/rotation matrix (MTX_LookAt 0x020A727C). H.
- **2D/3D register helpers** (NitroSDK G2/GX): 0x020A69CC G2_GetBG1ScrPtr, 0x020A5224 GX_SetGraphicsMode,
  0x020A6ADC per-line BG affine DMA source, 0x01FF8308 (ITCM) MI_SendGXCommand by DMA (display lists).

## Display output rules (checked frame-by-frame against melonDS 1.1 captures) — H unless marked
- LCD colour = 6 bits per channel; 2D colours are 5-bit << 1, the 3D layer keeps its own 6 bits; 8-bit output
  = c6 << 2 | c6 >> 4.
- Master brightness (0x0400006C) and BLDY in 6-bit integers: up `c + ((63 - c) * f >> 4)`, down
  `c - ceil(c * f / 16)` (f <= 16). 2D alpha blend `(c1*eva + c2*evb + 8) >> 4` (M: no frame has proven the +8
  yet). 3D-over-2D blend `(c3*(a+1) + c2*(31-a) + 16) >> 5`.
- 3D: geometry submitted in frame N is displayed in frame N+1. Vertex screen positions are integers:
  `x = (X + W) * width / 2W + x1`, `y = (-Y + W) * height / 2W + (191 - y2)` (truncated) after clipping against
  the view volume (attributes interpolated linearly in clip space). Texels are sampled at the pixel's top-left
  corner (not the centre). Translucent pixels are not drawn over a pixel already drawn by a translucent polygon
  with the same polygon ID. Texture modulate: `((t6+1)*(v6+1)-1) >> 6`, with 5-bit colours widened to
  `c*2 + (c != 0)`; alpha `((ta+1)*(va+1)-1) >> 5`.
- CLEAR_COLOR (0x04000350) alpha 0 = transparent rear plane: a translucent polygon over it is written with its
  own colour and alpha, and the 2D compositor blends it with the 2nd target. M: translucent-over-translucent
  blending (`dst alpha != 0`) is not reproduced exactly by the GPU path (see HANDOFF).

## ARM7 binary and its sound driver — H unless marked
- Loaded at 0x02380000 (header 0x30..0x3C), entry 0x02380000 (crt0). Autoload table 0x023A7760..0x023A7778:
  0x037F8000 (WRAM) 0xFDD4 bytes + 0x3758 bss, 0x027E0000 (main RAM, physical 0x023E0000) 0x177DC + 0x18B8 bss,
  sources consecutive from 0x023801B0. Then 0x037FB6C0 (ARM7 main).
- NitroSDK SND driver: SND_Init 0x037FF384 creates the thread 0x037FF17C: init 0x037FF304 (interval queue
  0x038080DC + alarm), 0x038002D0 ExChannelInit, 0x03801F08 SeqInit, 0x03802518 AlarmInit, 0x037FEA30 enable,
  0x037FE8D8 output selector, 0x037FE910 master volume, 0x037FF2AC interval timer (periodic alarm every 0xAA8
  ticks = 5.2 ms, handler 0x037FF1FC sends message 1); loop: receive (1 periodic / 2 wakeup), 0x038000E4,
  0x038028BC SND_CommandProc (command ids as listed in scripts/core/ds_sound.gd history; switch at 0x038028BC),
  0x03801E68 SeqMain, 0x037FFDD8 ExChannelMain, 0x038022A8 UpdateSharedWork, 0x037FEF24 random.
  SND_CommandInit 0x03802D34 (command queue 0x0380975C, PXI tag 7 callback 0x03802868: data >= 0x02000000 =
  command list, 0 = wakeup). SND_CalcChannelVolume 0x037FEFC4, SND_CalcTimer 0x037FF048.
- ARM7 OS: ticks 0x037FD264 (64 bus cycles), alarms: SetAlarm 0x037FD65C, SetPeriodicAlarm 0x037FD5E0,
  CancelAlarm 0x037FD550; messages: Receive 0x037FC78C, Send 0x037FC82C, Init 0x037FC8C0. Division helpers
  0x038070E4..0x03807500 (same set as the ARM9's). BIOS: 0x03804188 GetPitchTable (SWI 1Bh), 0x0380418C
  GetVolumeTable (SWI 1Ch).
- Sound alarms: SND_SetupAlarm keeps {tick, period, id} per alarm (0x40-byte records); each firing sends PXI tag 7
  data alarmNo | id << 8 to the ARM9 (handler table 0x020E4FC0, 12 bytes per alarm). Streamed music: two PCM16
  channels (6/7) looping over a ring buffer the ARM9 stream thread refills one quarter per alarm.
- BIOS tables: pitch(i) = round((2^(i/768) - 1) * 65536) (all 768 match FreeBIOS); volume table copied from
  melonDS FreeBIOS (BSD), see scripts/core/ds_bios7.gd. M (only FreeBIOS checked, not a real BIOS).

## ARM9 threads, timers (for the thread model in DSMachine) — H
- OSThreadInfo 0x020E31BC: +0 u16 reschedule request, +4 u16 (non-zero = no switch), +8 current thread, +0xC
  thread list (priority order), +0x10 switch callback; 0x020E31B8 reschedule-disable count, 0x020E31AC callback.
- OSThread: context at +0 (cpsr, r0-r12, sp +0x38, lr +0x3C, pc+4 +0x40), state +0x64 (0 waiting, 1 ready,
  2 terminated), next +0x68, id +0x6C, priority +0x70, stack bottom +0x84, top +0x88. OS_CreateThread 0x020AA1DC,
  OS_InitContext 0x020AA544, OS_SleepThread 0x020AA100, OS_WakeupThread 0x020AA08C, OS_RescheduleThread
  0x020A9F40, OS_SelectThread 0x020AA02C, OS_ExitThread 0x020AA168, idle thread 0x020A9E44 (OS_Halt 0x020AB3D0).
- Threads seen: launcher (main) 0x020E32A4, CARD worker 0x020E5280, sound stream 0x020E2680, idle 0x020E3210.
- Interrupt handlers (OS_SetIrqFunction 0x020A8F70): HBlank 0x02000FB4 and VBlank 0x02000FD0 / 0x0204D0B0 /
  0x02056794 only set the IRQ check flag (0x027E3FF8 bit 1 / bit 0). In battle the HBlank callback 0x0201B254
  rewrites the BG3 affine registers (0x04000030) every line through 0x020A6ADC (scrolling/scaled background).
- Hot SDK paths in battle (PROFILE build, per frame): DMA set-up 0x01FF82B8 (~120 calls), card reads for the
  streamed music 0x020B23F0 (2 calls, ~1 ms), IRQ enable/disable pairs 0x020AB36C/0x020AB380 (~280 calls).
- Lockstep t1 also differs (from frame 13) in two bytes 0x020E18A9 / 0x020E1931 (ref 1, port 0): field +0x81 of
  0x88-byte entries of the table at 0x020E1828 (initialised by 0x0209F2C4 with 4 entries). Probably the sound
  stream request flags, in step with the stream-buffer difference (ARM7 timing). M.
- The game seeds its random number generators from the RTC date/time (0x0200846C -> 0x02008264/0x0200820C/
  0x02008424, MT19937-style 0x020DD80C).

## SDK functions with native fast paths (DSCoreBase._fast_call; native/src) — H unless marked
All are pure functions of memory; the fast path writes exactly what the original writes (lockstep RAM + DTCM
snapshots identical with the fast path on and off) and falls back to the translated body when its preconditions
do not hold (address outside main RAM/DTCM, no native library).
- MI (memory) functions, arguments as in NitroSDK: 0x020ABB30 MIi_CpuClear16(data, dest, size), 0x020ABB48
  MIi_CpuCopy16(src, dest, size), 0x020ABB64 MIi_CpuClear32, 0x020ABB78 MIi_CpuCopy32, 0x020ABB90 MIi_CpuClearFast,
  0x020ABBDC MIi_CpuCopyFast, 0x020ABC4C MI_CpuFill8(dest, data, size), 0x020ABCE0 MI_CpuCopy8(src, dest, size),
  0x020ABE18 MI_UncompressLZ8(src, dest), 0x020ABF84 MI_UncompressRL8(src, dest). The two decompressors return
  the source end pointer in r0 (callers use it). Sizes are compared signed (a size with bit 31 set copies nothing).
- 0x020B23F0 = CARD ROM read loop (common block 0x020E5240): per 0x200-byte transfer it calls 0x020B277C (set up
  command), writes ROMCTRL 0x040001A4, pulls the words from 0x04100010, then 0x020B281C. The fast path moves each
  transfer's words in one go (DSHardware.card_take_all).
- 0x020AB3DC = OS_SpinWait(cycles): the SDK busy-waits with it for the ARM7 (e.g. SND command buffers,
  0x020A2xxx); the port lets cycles/2 bus cycles of emulated time pass (DSMachine._spin_wait) instead of counting
  down with no time passing (that spun 1.5 M times, ~20 s).
- 0x020AB36C / 0x020AB380 OS_DisableInterrupts / OS_RestoreInterrupts (CPSR I bit) are emitted in place by the
  translator (no _hle dispatch): a file load calls them ~24,000 times.
- **FS path lookup** (session 1 part 6): 0x020AD8BC = FSi command dispatcher(file, cmd): archive = file+8;
  archive+0x10 flags (0x100 busy async / 0x200 busy sync), +0x44 read callback, +0x48 user proc, +0x4C proc mask
  (bit = command; a proc result 8 clears the bit for good); default handlers table 0x020D53A0 (pointer literal
  0x020ADA34): 0 0x020AE304, 1 0x020AE2CC, 2 SEEKDIR 0x020AE234, 3 READDIR 0x020AE124, 4 FINDPATH 0x020ADF08,
  5 0x020ADB48, 6 0x020ADACC, 7 0x020ADAA4, 8 0x020ADA9C. Read helper 0x020AE370({arc, pos}, dst, len) calls the
  archive read callback; 0x020AEE38 = read from the tables loaded in memory (MI_CpuCopy8). Name compare 0x020AE414
  (A-Z folded to lower case). FSFile fields: +0x0C stat (bit 2 = synchronous command), +0x14 result, +0x1C..+0x28
  current dir position {arc, own id u16, index u16, pos, parent id & 0xFFF at +0x28}, argument block from +0x2C
  (find path: +0x2C start dir position, +0x38 path, +0x3C find directory flag, +0x40 result pointer; read dir:
  +0x2C entry pointer, +0x30 skip name). FSDirEntry: {arc, id/own id+index, pos, +0x0C is dir, +0x10 name length,
  +0x14 name}. File name table entry (8 bytes at fnt + id*8): u32 sub-table offset, u16 first file id, u16 parent.
  The native walk (native/src/ds_fs_native.cpp) runs when stat bit 2 is set, the archive mask has no seek/read-dir
  bits, the read callback is 0x020AEE38 and the default table is unchanged; it uses the translated function's
  stack frame (DSCoreBase._sp) for the directory entry like the original. Boot: 182 lookups, all native.
- Callers of FS commands per file (FS_OpenFile/ReadFile/CloseFile through FSi_SendCommand 0x020AE998, about 7 per
  file) remain translated: a screen change that loads ~200 files still costs ~100 ms on the cloud VM. M.

## Game state used by the debug flags — M
- Fighter slots: 0x021075C8 + i * 0x8E8 (slot 0 = P1, slot 1 = P2's current fighter in Z-Battle); HP s16 at +0x24A
  (`clamp=021080FA:-32000:200` keeps the opponent at ≤ 200 HP so any hit knocks out).

## DMA / card DMA details — H
- MI_StopDma 0x020AB738(ch): two halfword writes to DMAxCNT's top half: `&= 0xC5FF` (clears repeat + timing,
  enable stays set) then `&= 0x7FFF`. A DMA starts only when its enable bit goes 0 → 1 (rewriting an enabled
  channel does not restart it).
- Card reads by DMA (FS read path 0x020AF764 -> 0x020B20F4 -> 0x020B24F0 -> 0x020B2724): DMA3 CNT 0xAF000001
  (enable, start timing 5 = card, repeat, 32-bit, fixed source 0x04100010, 1 word per card word); per 0x200-byte
  block the card IRQ handler 0x020B264C stops the DMA, then 0x020AC0B8 waits for DMA3 enable = 0 and sets up the
  next block. Used by Maximum mode's battle load.

## Session 1 part 7 findings — H
- **Large stack frames**: 12 functions allocate their frame with `sub sp, sp, <literal>` (0x414..0x1044 bytes:
  0x02042118, 0x02042EC0, 0x02042FA0, 0x020430C0, 0x02043DA0, 0x02044638, 0x02047AFC, 0x02048D70, 0x020550F0,
  0x02055FE4, 0x02058AB4, 0x0205DE6C). Ghidra shows them as `iVar = -DAT_x; &stack0x.. + iVar` or
  `&local_4 + -DAT_x`. The translator now sizes those frames; before, their buffers overlapped the callers'
  frames. Visible effect: story character select "Map Clear 3/14" instead of 14/14 (0x02047AFC counts the
  cleared maps from a 20 x 52-byte map table filled by 0x020084E0, then calls 0x020430C0 whose own table
  overwrote it).
- **Story progress** in the save copy: 15 characters x 0x18 bytes at 0x020DD628 (getter 0x02002410(dst, char),
  setter 0x020023A0(char, src)); +0 u16 cleared-map bits, +4.. 20 map status bytes (4/5 = cleared).
- **Texture palette memory** is 96 KiB; the 3D shader masked palette addresses with 0x17FFF, dropping bit 15:
  every palette at 0x8000-0xFFFF read the wrong bytes (Maximum rank bars drew black).
- **Translucent polygons** at the same depth as what is already drawn fail the DS depth test (less, unless
  attribute bit 14 = equal): e.g. the shine overlays (alpha 10, IDs 1/2) on the menu bars.
- **Quads are one polygon** on the DS: the diagonal between their two triangles (and the fan edges of a clipped
  polygon) is not a polygon edge, so the port no longer dilates it (overlapping triangles of one quad sampled
  slightly different texels: flickering seams in the scrolling MODE SELECT bar).

## Session 1 part 8 findings — H
- **Quads are clipped as one polygon** on the DS (the geometry engine clips the 4-vertex polygon against the view
  volume, then rasterises the result). Clipping the quad's two triangles separately gives different new vertices
  along the screen edge; after integer vertex snapping the two halves' edges differ by 1 px and the difference
  changes as the polygon scrolls (the MODE / CHARACTER SELECT bars, which are long quads running off the screen
  edges, "shook"). DSGX `_quad4` / DSGXNative `quad4` clip the whole quad (facing from vertices 0,1,2, or 0,2,3 if
  degenerate) and fan-split it afterwards. Verified against melonDS: bar border rows identical in every column.

## Session 1 part 9 findings — H
- **GPU attribute planes from snapped corners**: GPUs snap triangle corners to their sub-pixel grid (1/256 px on
  the user's NVIDIA RTX 4070) and rebuild the UV plane from the snapped corners. Long thin triangles amplify that
  error (error × length / height): the old fan over the dilated outline produced slivers along a quad's diagonal
  and on that GPU some pixels there sampled texel row n-1 (texture coordinate exactly on a texel boundary at the
  DS sampling point). Drawing each triangle as itself (integer corners) plus a ring of dilation pieces, with the
  dilation a multiple of 1/256 px, removes it: the RTX 4070 and Mesa llvmpipe captures are now identical.
- **ROM identification** (`scripts/core/assets.gd`): title `DRAGONBALLZ2`, game code `ADBP`, header CRC16 0x53C2
  (CRC-16/MODBUS over 0x000-0x15D), ARM9 binary (ROM 0x4000, 0xDD8F8 bytes) MD5 after its first 0x800 bytes
  (secure area differs between dump tools) c859f91b…, ARM7 (ROM 0xE1A00, 0x27778 bytes) MD5 9f883c56….
  Trimmed dumps (60,017,540 bytes) are accepted.

## Session 1 part 11 findings (QoL settings menu, jukebox, sound switches)
- **Mode Select scene** — H. While Mode Select runs, the scene VBlank callback slot u32 0x020DE374 = 0x020738E0
  (sub-scenes: 0, 0x02065E60, 0x0206D61C; stage select 0x02071138). Cursor u8 0x020DEC20 (0..8 row-major 3x3,
  4 = the unused Dragon Ball tile; u8 0x020DEBB8 mirrors it). u8 0x020DEBD8 (and 0x020DEBDA) = 3 while the player
  chooses, 4 from the A press until the next scene (the callback slot stays 0x020738E0 for ~60 frames after A);
  back at 3 when the scene returns (melonDS: A f0 → slot 0 at f63 → sub-scene f95 → B → slot back f254).
  Writing 4 to the cursor makes the game highlight the centre tile and navigate away from it normally (Up→1,
  Down→7, Left→3, Right→5); A or a touch on it does nothing in the original. Centre tile: touch x 88..168,
  y 64..108. No idle timeout at Mode Select. (melonDS scripts; port `QoLController`.)
- **BGM manager** — H. Struct 0x020DE2A0: +0xA0 u16 mode (bit0: 1 = sequence/MIDI, 0 = stream), +0xA2 bit0
  paused, +0xA4 stream position, +0xA8 current BGM id; handle 0x020DE33C. f_0200FE48(id) play BGM ·
  f_0200FEE0(mode) set mode + stop · f_0200FDE4(fade) stop · f_0200FD68(0,0,0,0) pause · f_0200FCF8() resume ·
  f_0200FE98(id) load a sequence into the sound heap · f_02010044() NNS_SndHeapSaveState (returns level) ·
  f_02010028(level) NNS_SndHeapLoadState · f_020AC5B8 SND_StartSeq · f_0200FF9C play SE.
- **Sound archive** — H. SDAT (found by its magic in the ROM): 20 STRM (BGM_OP, BGM_01..15, BOSS1/2, VS, CHARA)
  and 18 BGM sequences on player 0 (PLAYER_BGM); sound effects are SEQARC entries on other players. SEQ INFO
  player byte at +9, STRM INFO player byte at +6; SSEQ data offset at file +0x18.
- **ARM7 SND driver state** — H. ExChannels 0x038085DC stride 0x54 (+0 hw channel, +3 flags bit0 active, +0x48
  callback, +0x4C callback data = track address). Players 0x03808B1C stride 0x24 (+0 flags bit0 active, +8 u8
  tracks[16]). Tracks 0x03808D5C stride 0x40 (+0x24 sequence base, +0x28 current pointer). Stream channels are
  hardware-active channels that no active ExChannel owns (channels 6/7 for BGM streams). A player plays BGM when
  the 16 bytes at its track 0's base equal a BGM sequence's data start.

## Session 1 part 12 findings (QoL menu restyle)
- **Text font** — H. `romdata/scene/font_eu.bin`: small archive (u32 at +4 = data offset 0xA0; names
  "font_eu.ntft", "font.pltt"), texture RLE-compressed (BIOS type 0x30, 16,384 bytes) = 256x256 2bpp; glyphs in
  9x15 cells, 28 per row, starting at '!' (0x21) in ASCII order (Latin-1 after '~'); capitals 5 px wide, 10 px
  tall at cell rows 3-12, descenders to row 14. The Option screen's descriptions use this look (6 px per char).
  Read at runtime by `QoLFont` (NitroFS lookup), never stored.
- **Mode Select lower screen layers** — H. Engine A (lower screen while Mode Select runs, POWCNT1 swap): BG0 = 3D
  (the nine tiles and the scrolling MODE SELECT bars are polygons), BG1 = the hexagon background (scrolled by the
  game), backdrop green (0x03E0-ish, never visible). Found with the `layersweep=F` capture flag.
- **Header bar on the upper screen** — H (pixels). Orange (235,150,0) bar y 23..42: black line y 24 and y 41,
  text area y 25..40; title text black bold, capitals y 28..37 from x 31/32; the bar's slant starts at x ≈ 195.
  Description box text from x 26, lines every 14 px from y 77 (Option screen).
- **OPTION MODE lower screen** (melonDS colours) — H. Title plate: orange line y 1, black y 2..25 with slanted end
  (x 166 → 153), orange line y 26, white block + white underline; rows: black bands with orange (186,121,24)
  trim lines, bold italic white labels ~13 px; hexagon buttons ~36x30: rim (255,166,0) 3 px, black line, face
  (134,101,0); value text red (255,24,0) when selected; cursor = white rim.

## Session 1 part 13 findings (cheats) — H unless marked (melonDS RAM experiments + port runs)
- **Correction: team blocks.** `*(u32*)0x020DE3D0` = 0x021075C8 = per-player TEAM blocks, stride 0x8E8 (P1
  0x021075C8, P2 0x02107EB0). Each holds 3 fighter records of 0x2D8 (+0, +0x2D8, +0x5B0), then +0x8C8 u8 active
  member, +0x8C9 member count, +0x8CA assists left, +0x8D0 u16 team ki (0x100 = 1 %, start 0x6400, max 0xC800 =
  200 %, HUD shows ki>>8), +0x8E2..+0x8E6 beam-struggle mashing. Fighter +0x05 = character id (indexes the
  per-character handler table 0x020D785C), not a C-state. FUN_02027C00(p) = player p's active fighter,
  FUN_02027BD0(p) = the opponent's active fighter, FUN_02027BB4(p) = team block. Inactive members sit at 0,0.
- **Damage**: FUN_020293A4(fighter, dmg, type) is the only HP loss from hits (dmg scaled by globals+0x1676); sets
  +0x254 |= 0x200 (|= 0x800 if lethal and type 5). +0x24C = max HP. FUN_02029428 heals (clamped to max). Guard
  chip damage (FUN_0201E9EC path when `u32[f+0x250] & 1`) floors HP at 1. KO action 0x33.
- **Ki**: spend FUN_02027950(f, amount, mode 0 = scaled by u16 c[+0x12]/256), gain FUN_02027A40 (clamp 0xC800);
  FUN_02027924 = ki %; FUN_020278D0 = "enough for a super". Costs: ki blast 10 % (needs > 9 %), R+B 30 %, super
  50 % (VM opcode 0x48 in FUN_02022930), ultimate 0x9600, team change 200 %.
- **Input**: fighter +0x26C u16 pressed this frame, +0x270 held: 0x001 A (ki blast), 0x002 B (guard), 0x400 X
  (dash / super modifier), 0x800 Y (melee), 0x100 R, 0x200 L, 0x10/20/40/80 directions.
- **Action dispatcher** FUN_0202AEB4(f) (called only from neutral/move handlers: actions 0/5 FUN_0202CC70, 1-4
  FUN_0202C9B8, 6 FUN_0202C74C) starts actions via FUN_02021B4C(f, act): Y+B 0x2A; R+B 0x19; R+A 0x23; R 0x0C;
  X+A clash FUN_02026994 / ultimate 0x2E FUN_02026A8C / super 0x2C (charge) → 0x2D (fire); A ki blast 0x24
  (Goku: 47 frames, shots on frames 9/17/25); Y melee 0x1C+n; X dash 0x20; B guard 0x18. No cooldown timer:
  an attack ends when the action script sets `u16[f+0xE] & 1` (FUN_0202124C), then FUN_0202B630 returns to 0 / 5.
  Gates: `u32[f+0x250] & 0x800` freezes the fighter, `& 0x400` skips the character handler; byte
  [globals+0x1675] disables supers; FUN_02012FD4 = pause / cut-in.
- **Effect objects**: pool `*(u32*)0x020DE3CC` (0x02108C44), 48 × 0x164 (+8 at +0x42C0), per-frame loop
  FUN_02021F54, allocation FUN_020227D4 (first free; no per-fighter projectile limit). Layout: +0 owner (fighter
  for ki blasts, another object for beam parts), +4 u8 1 alive / 2 dying, +6 kind (8-byte table at +0x40:
  {per-frame handler, hit handler}), +8 u16 sub-state, +0x10 life flags (2 countdown at +0x18, 4 die with
  owner, 8 die when owner's action != +0x1B: FUN_0202104C), +0x1A player, +0x1B owner's action at spawn, +0x21
  u8 direction (0 right, 0x40 up), +0x22 speed, +0x24 max, +0x26 accel, +0x28/+0x2A velocity (24.8, y down),
  +0x2C/+0x2E target velocity, +0x30/+0x32 accel vector, +0x34 hit handler, +0x38/+0x3C x/y. Handlers: plain
  projectile (ki blasts) 0x020209E0; beam head 0x02020330, body 0x020203CC, origin 0x02020560; hit handler
  0x0201F74C = no damage. FUN_020213A8(obj, speed, accel, max, dir) sets the motion; sine table 0x020B64D4.
  FUN_0201EE60(obj, target) = direction to the target's hurtbox centre; FUN_020210C8(cur, step, want) turns.
- **Character select**: FUN_0206CC94 turns input into a pick (-1 = refused); it refuses ids already in the side's
  team s32[3] 0x020DE64C (three inline loops), the same family (FUN_0206A688, family bytes 0x020D04C8) and a
  second support (FUN_02066088, ids >= 0x1A). FUN_0206ABB0 greys portraits by the same tests (called every
  frame). Free Battle working picks s32[6] 0x020DE658 (FUN_0206ED18), committed to the party block 0x020DD51C
  (P1 s32[3] 0x020DD524, P2 0x020DD530, 38 = empty) by FUN_02071374; Z-Battle team select FUN_02066558
  (FUN_02067E34 writes 0x020DE64C). The battle loader FUN_0202A40C copes with duplicates (verified: three Gokus,
  two Bardocks; mirror-match palettes as usual). Cursor character u8 0x020DEA0F, confirm state FUN_0206A76C.

## Session 1 part 14 findings (bosses, battle start, portraits) — V = melonDS/port verified, C = code
- **Boss level** (C, V): u8 0x020DD510 (0-3; get FUN_02001EA4, set FUN_02001EB4). Fighter init FUN_0202117C: if
  level != 0 and fighter+0x1A != 0 (CPU side): f+0x50 = c + u32[c+0x10+4*L] (c = u32[f+0x44] 'c' chunk; 4 parameter
  blocks of 0x28 bytes; block 0 normal); the loader sets HP/max HP from u16[f+0x50]. Level 1: 21000 HP; level 2:
  21000 HP, +4 0x404, +0x10/+0x14 0x1CC, super costs (+0x1F..+0x22) 25 %; level 3: 26000 HP (SSJ Goku, Cell 32000),
  +0x10 0x280, ki-cost scale +0x12 0x80, super cost 0. Supports (26-36) have no blocks. VM opcode 0x92 `92 L off32`
  (inside FUN_02022930) jumps if CPU and L == level: boss-only scripts, only in SSJ Goku (1), Cell (15), Broly (20),
  all level 3 (actions 0x13, 0x23, 0x24, 0x2C, 0x2D). Opcode 0x05 (goto) has the same layout. Each fighter has its
  own copy of its 'c' chunk (V: Goku vs Goku chunks at 0x0217CAA4 / 0x0218B790). Boss battles play BGM 0x10/0x11
  (FUN_02013064 case 4). Z-Battle round 8 (state 0x020E174C, +0x67 round): FUN_0209CBF4 one boss at level 2 from
  0x020D0E80 (hero leader: Frieza, Cell, Kid Buu, Broly, Cooler, Majin Vegeta) or 0x020D0E88 (villain leader: SSJ
  Goku, Gohan, SSJ Vegeta, Gotenks, Majin Buu). Maximum: scene/maptables.bin max_maptable_a/b/c.tbl, 20 × 0x28
  (+0xC..+0x14 enemies, +0x18 stage, +0x1C boss level, +0x20 CPU level); level-3 solos: Cell, Broly, SSJ Goku.
- **Battle start** (C, V): FUN_0202A40C (loader) is called only from FUN_02013D60 (battle init); every mode reads
  the party block 0x020DD51C: mode u32 0x020DD514 (0 Z-Battle, 1 Story, 2 VS, 3 Maximum, 5 Free), P1 ids s32[3]
  0x020DD524, P2 0x020DD530, support ids 0x020DD53C / 0x020DD540 (38 = none), counts u8 0x020DD548/549, stage
  0x020DD54A, CPU level 0x020DD552. The VS screen (FUN_02018714) and the lower-screen panels (FUN_0201B78C) read the
  party before the loader: FUN_020140C8 is the first step of both battle-start paths. Count must equal the valid
  entries; at most one support, at least one fighter; the loader moves the support last. Valid ids 0-36.
- **Portraits** (V): Free Battle select upper screen P1 slot k portrait x 3-77, y 43+40k; enemy x 178-253,
  y 35+40k. Z-Battle team select upper screen: panels x 8+80k, y 8-138. Battle lower screen: panel per fighter
  record at s16 rec+0x2D0 (x0), y 8-135 (party order).

## Session 1 part 15 findings (assists, music) — V = melonDS / port verified, C = code
- **Assists** (C, V): called by touch only: in the neutral handler FUN_0202CC70, touch flag fighter+0x263 bit 0 →
  FUN_02026E34 (Team Arts, touch rect *0x02027000 x 8..248 y 144..184, 200 % ki, >= 2 members), FUN_02026C00(f,
  touched) (assist: action 0x28 call pose, f+0x250 |= 0x100), FUN_02027164 (tag). FUN_02026C00 refuses while a
  call is in progress (+0x250 & 0x100 on either active fighter), while the GLOBAL slot u32 [teams+0x11E0]
  (0x021087A8) is non-zero (the record of the assist on screen, either player's), with +0x8CA == 0, or when the
  touch is not inside every support record's panel (two supports in one team: never callable). Arrival
  FUN_020277AC(caller) at the end of the pose: slot = the team's last support record, FUN_02029E3C voice,
  FUN_02021B4C(sup, 0), FUN_02011D54(sup+0x124, 1) visible, +0x8CA-- (Shenron 0x23: 0). Each battle frame
  FUN_020294B8(*slot) runs the assist (action table rec+0x284, VM, drawing via FUN_02019328); its end
  (FUN_0202B580) hides *slot+0x124 and clears the slot. Copies of the record in unused RAM (0x02700000) work as
  extra assists when updated with the slot pointing at them (port: 13000 → 0 HP vs 13000 → 10600 without).
  Correction: support id 26 shows Tien's portrait in the port's battle panel (the RE agent read it as Yamcha;
  M — check the in-battle sprite).
- **BGM** (C, V): f_0200FE48(id) is the only "play": stream mode → STRM index, sequence mode → SEQ index; +0xA8
  = id (read only by resume f_0200FCF8). f_0200FE98(id) loads seq + bank + wave archives (callers panic on 0).
  +0xA2 bit 0 is not a pause flag (stop sets it, play never clears it). Title: STRM 0 (one-shot); Mode Select:
  fe98(1) + bank 0x45 + fe48(1) (SEQ 1 MODEMENU); character / team / stage select: STRM 19 CHARA; VS screen STRM 18;
  battle (FUN_02013064 case 4): stage 2 → STRM 4, 3 → 3, else stage+1; boss battles STRM 16/17; story scenes:
  sequences via script FUN_0203B178. Sound heap per scene FUN_02010124: battle 1 MiB stream mode; menus / story
  0xC0000 sequence mode. A sequence scene cannot start a stream (buffers only from stream-mode init) and a battle
  cannot load a big sequence: remap stream → stream, sequence → sequence of similar size.

## Session 1 part 16 findings (character shuffle) — H/M/L confidence; V = port verified, C = code read
- **Fighter load** (H, C+V): the loader FUN_0202A40C builds each record with FUN_0202A094(rec, id, side): rec+0x274 =
  0x1F; per-character init handler u32[0x020D78C4 + 4*id](rec) (sets +0x284 action table, +0x244 character
  handler table, +0x274 |= move unlock bits from FUN_02002410); +0x280 = 0x020D7958; +0x1A = side; body sprite
  object rec+0x124 (FUN_02012084, 128x128, owns one OBJ VRAM block); FUN_0202117C(rec, id) = +4 = 1, +5 id, +6/+7/+8/
  +0xA = 0 (+7 = facing!), FUN_02020D4C(rec+0x44, id) + FUN_02020D0C(rec+0x44, id, 1), boss block for CPU;
  P2 only: +0xFC += 0x100 when the id is also in P1's team (mirror palette); palette slot FUN_02010B6C(*(rec+0xFC),
  0x100) → u16 rec+0x10A and sprite+8; effects FUN_02020D4C(rec+0x164, id+0x26) + FUN_02020D0C(rec+0x164, id+0x26,
  0); effect palette slot FUN_02010B6C(*(rec+0x21C), u16 rec+0x228) → u16 rec+0x22A; visible; max HP = HP =
  u16 *(rec+0x50); +0x24F = u8 0x020CFCA8[id], +0x27E = u8 0x020CFC8C[id] (ids < 0x1A, else 0). Then FUN_0202A40C:
  face icon sprite rec+0x290 (32x32) from /romdata/game/game_faceicon.arc entries 2*id (tiles) / 2*id+1 (palette
  0x20, own slot), key (2*id & 0xFFFFF) | 0x40000000, FUN_0201CB44(member, id) for the local side; after both teams
  the sound-heap level (FUN_02010044 → kept at globals+0x1BCB0, read by FUN_02013004), then FUN_02029024(active,
  0..6) loads both active fighters' voices ABOVE that level; FUN_02026548(local active) = team-art partners.
- **Character file table** (H, C+V): 0x020D62AC, 0x43 bytes per entry (0-36 fighters / supports, 37 cmneffect,
  38-74 = id+0x26 effect sets, 75 win): bytes 0/1/2 = entries of /romdata/chara/charadata.arc for the 'c' chunk,
  the frame-table archive and the palette (512 bytes = normal + mirror palette of 0x100), +3 = path of the image
  archive (<abbr>_img.arc / <abbr>_eff_img.arc). Struct filled by FUN_02020D4C(s, id): s+0 'c' chunk, +4 action
  table, +8 script base, +0xC param block 0 (rec+0x50), +0x10 in-memory archive over the frame table (its data
  pointer at +0x2C = rec+0x70 / rec+0x190), +0xB8 palette (rec+0xFC / rec+0x21C), +0xC4 u16 palette size, +0xCA id,
  +0xDC last frame descriptor (rec+0x120). FUN_02020D0C(s, id, hdr_only) opens the image archive into s+0x64
  (rec+0xA8 / rec+0x1C8, path at +0x24): fighters header only — frame tiles are read from the card when the frame
  changes (FUN_02020C08) and queued with FUN_02010FB4(rec+0x124, frame | (id | side<<7)<<20 | 0x50000000, buf);
  effect archives are loaded whole (16 KB Goku … 207 KB Ginyu, 185 KB Cooler).
- **File manager** (H, C+V): u32 0x020DD7B8 → +0 open archives {struct pointer, refs} × 64, u32 count +0x380;
  +0x200 file cache {u16 archive handle, u16 entry, u32 data} × 48. FUN_0200626C opens (a path already open only
  gets refs+1 + a copy of the header pointer; the table keeps the FIRST opener's struct), every open gets a new
  handle (u16 counter 0x020DD7B4), so a cached entry can only be found through the handle that loaded it.
  FUN_02006074 = load entry (cached), FUN_02005FC4 = free entry, FUN_02005F18 = close (refs-1; at 0 frees the
  header and copies table[count] — one PAST the last entry — into the slot, so the last open archive drops out of
  lookups: game bug, M), FUN_02005E4C (scene end) frees every cache entry and every open struct. The battle never
  frees fighter data before the scene ends.
- **Heap** (H, C+V): main NNS expanded heap u32 0x020DE1E4 ('EXPH'; free list +0x24, block header 0x10: 'FR'/'UD',
  size +4, next +0xC): FUN_02009120 alloc (head), FUN_020090E4 alloc (tail), FUN_020090B0 free. Free Battle
  Goku vs Goku battle: 1.34 MB free; Goku + Vegeta + support vs Goku: 1.22 MB (V).
- **OBJ VRAM / palettes** (H, C): manager u32 0x020DE380: FUN_02010FB4(sprite, key, src) queues tiles into the
  sprite's VRAM block (a block with the same key is shared, ref-counted; +0x600 block list, +0x7AE count < 0x30);
  FUN_02010B6C(src, size) allocates a palette slot (+0x7B4 list, +0x8B8 count ≤ 64, only reset with the scene) and
  queues the upload; FUN_02010AE0(slot, src, size) queues an upload into an existing slot; queues (+0x7AC tiles /
  +0x7AD palettes ≤ 32) run at VBlank. Loaders wait with FUN_0200077E (SWI 5, VBlankIntrWait, after clearing bit 0
  of 0x027E3FF8) before freeing the sources. Face icon on the life bar = rec+0x290 of the ACTIVE member (FUN_0202A254).
- **Lower-screen panels** (H, C+V): FUN_0201B78C draws the three portrait panels from the party ids of the local
  side (FUN_020028C8): /romdata/charselect/SubScrNBFC.bin (tiles, entry = id), SubScrNBFS.bin (maps), and
  /romdata/game/game_subbg.bin (overlays: slot 0 "Team Arts" bar 2n/2n+1, slot 1 "Touch!" 10/11) through the packed-
  file system (FUN_0200A85C init / FUN_0200A648 open / FUN_02009B28 decompress / FUN_02009E08 close / FUN_0200A788
  teardown, state u8 0x020DE210, 0 = idle in battle); BG layers 4-6, chars FUN_02006E50 (queued from ONE heap buffer,
  with a VBlank wait per panel), maps = the BG manager's map buffers (u32 0x020DD7BC + 0x1AC + 4*layer =
  *(0x020DE3BC) + 0x4774 / 0x4F74 / 0x5774), uploaded by FUN_02006B68; palette game_bg.arc entry 0x66. +0xCE0[slot] =
  id, +0xCD8[slot] = id + member<<8 (FUN_0201CB44). Panel state = palette nibble of the portrait rect (FUN_020067CC(
  layer, pal, rect x 0..0x58, y 0..0x80)): member+1 = active, 0 = inactive, 7 = greyed (FUN_0201C7A8), 4
  (FUN_0201C9C4); Team Arts bar 5/6 (FUN_0201C8F4).
- **Tag** (H, C): FUN_02027164 only requests it (team+0x8CB = next member, globals+0x11DC = requester); FUN_020281D8
  performs it: FUN_020297DC(old, 2) (per-character handler table 0x020D778C, mode 2 = power-up off, Goku: kills
  his effect 7, +0x261 = 0), team+0x8C8 = +0x8CB, FUN_0201CBBC (lower life bar), FUN_0201CA60 (panel highlight),
  FUN_02026548; the tag sequences FUN_02017358 / FUN_02017D68 then FUN_02010028(FUN_02013004()) (sound heap back
  to the level before the voices) and reload both active fighters' voices with FUN_02029024(rec, 0..6), P1 first.
  FUN_02029024(rec, 0) loads sound group u16 0x020CFCE0[id] (FUN_0200FFEC, M), every step n the archive item
  u16 0x020CFD2C[id] + n (FUN_0200FFBC, M); voices play as seqarc 1 on player 4 + 3*side + team+0x8CD (FUN_02029E3C).
- **Effect objects** (H, C): FUN_020225C8(owner, kind, chunk struct, handler table) copies the 0xE0-byte chunk
  struct to obj+0x44, so an object made from a fighter's chunk points into that chunk's heap data (pool 0x020DE3CC,
  alive = (+4 & 3) != 0).
- **CHARACTER SHUFFLE** (port cheat, V): QoLGame `_shuffle_*` (qol_game.gd part 16). Every 600 battle frames
  (counted at P1's active record in FUN_0202954C, from the first update of each battle) once P1 is in action 0-5,
  HP > 0, no +0x250 & 0x900, no tag (globals+0x11DC), no pause / cut-in (FUN_02012FD4), opponent alive, power-up
  ended (FUN_020297DC mode 2) and no effect object made from its chunks alive: free the record's six cache entries
  (by data pointer) and close its two image archives (refs-aware, table entry handed to another opener's struct),
  per-character init, FUN_02020D4C / FUN_02020D0C ×2 into the same record, palettes into the existing slots
  (FUN_02010AE0; mirror palette when the opponent shows the same character in normal colours), +0x24F/+0x27E, HP
  and max HP kept, FUN_02021B4C(rec, same action), FUN_02026548, voices as after a tag, face icon tiles into the
  rec+0x290 VRAM block from a scratch copy (port-only RAM 0x02710000) + palette into its slot, lower screen via
  FUN_0201B78C with the party block showing every member's current character (chars copied to scratch, VBlank
  waits skipped), then the old palette nibbles and +0xCD8 restored. Archives / cache entries stay constant over
  swaps (V: 10 / 30), heap free returns to the same range. V: a swapped-in Metal Cooler's face icon (24x24) and
  lower-screen portrait (80x128) are pixel-identical to melonDS with Metal Cooler loaded normally (party block
  written at stage select); with the cheat off a Free Battle capture run (17 frames, 1147 cheatdbg lines) is
  byte-identical to the run before the change. Metal Cooler's own max HP is > 13000 (melonDS 16102 left at f914):
  the shuffle keeps the old max on purpose. Also V: swaps with the global assist slot busy and 8 ASSIST SPAM copies
  on screen, swaps of a tagged-out member's record that is later tagged in again (icon / panel / voices follow),
  battle end with a swapped record (scene teardown FUN_02005E4C) and RANDOM CHARACTERS + shuffle. Cost of one swap
  in the slow cloud sandbox: ~110 ms (load 37, voices 24, icon 7, panel 38).

## Session 1 part 16 findings (buttons, banner icon, presenter) — V = port verified
- **Battle buttons** (V, Free Battle Goku vs Goku, each button alone, fighter action u8 rec+6 from `cheatdbg`;
  matches the dispatcher FUN_0202AEB4 in part 13): A → 0x24 ki blast; B → 0x18 guard; X → 0x20 dash attack (hits,
  1080 damage up close); Y → 0x1C+ melee combo; R held → 0x0C → 0x0D ki charge (ki +150 per frame, aura); L → 0x29
  power-up (Goku: red Kaioken aura afterwards, ki drains 15/frame until FUN_020297DC mode 2 ends it); Start pauses
  (ki frozen 5110-5200); Select: no action in battle. Combos: X+A 0x2C → 0x2D super (−12800 = 50 %), R+A 0x23,
  R+B 0x19 → 0x1B / 0x12 (−7800 ki, projectiles), Y+B 0x2A → 0x2B. Labels in QoLControls.BUTTONS / QoLMenu.BUTTON_HELP.
  (Corrects PLAYER_README before part 16: A is the ki blast, B guards, C/Y is the melee button.)
- **Banner icon** (H, NDS format): header u32 +0x68 = banner offset (ADBP: 0x10B000, version 1); 32x32 icon = 4x4
  tiles of 8x8 at banner +0x20 (4 bpp, low nibble left), palette 16 × BGR555 at +0x220, colour 0 transparent. It is
  the Goku face (same picture as the user's Icon.png; that file differs only by BGR555→RGB rounding).
  QoLController.banner_icon() reads it from the player's ROM at startup (DisplayServer.set_icon, scaled ×4 nearest).
- **Presenter margins** (V): DSPresenter drew its black full-window rect through the picture's sharp-bilinear
  ShaderMaterial; draw_rect has a white default texture, so the shader turned the margins white (full screen).
  Fixed by drawing the picture in a child node with the material; clear colour black (project + RenderingServer).

## Session 1 part 17 findings — V = port verified
- **Smooth-motion edge gap** (V): in-between frames move each 3D vertex back by its screen motion (CUSTOM1.yz);
  vertices the DS clipper put on the screen edge (x/w = ±1 → x 0 / 256, y 0 / 192) moved inward too, so fast camera
  moves showed a 1-6 px strip of clear colour / far BG at the edge (dash attack on the ice stage, frames 4807-4815).
  ds_poly.gdshader now never moves an edge vertex inward (outward or along the edge is kept). 60 fps untouched.
- **Fighter shadows** (V, melonDS battle_ready state): solid black ellipses on the ground are the original's look.
- **Boss + shuffle** (V): `battle_bosses` keyed by record; after a shuffle the record holds another character.

## Session 1 part 18 findings (stage shuffle) — V = port verified, C = code read
- **Stage loader** (H, C+V): FUN_0201C150(stage) is the first step of the battle init FUN_02013D60 and does the whole
  stage: globals (u32 0x020DE3BC = u32 0x020DE3A8, the battle stage block S) +0xCBE stage id, +0xCC0..+0xCCE = the
  first 8 u16 of the per-stage 0x1E-byte record at 0x020CFAC8 (+0 width 0x4000 / 0x1000, +2 height = camera y max,
  +4 / +0xC scroll divisors of BG2 / the 3D stage in FUN_0201B5C0, every frame), +0xCBF flags (table 0x020CFA45 / 0x020CFA47
  bits 0 / 1); BG3: table byte 0x020CFA48 = 0 → BG mode 0, BG3CNT (BG3CNT & 0x43) | 0x1C94, HBlank IRQ off
  (FUN_020A535C(0) clears DISPSTAT bit 4); else mode 1, BG3CNT | 0x7C14, HBlank handler FUN_0201B254 (FUN_020A8F70(2,
  …), affine perspective sky whose phase counter advances every 4 frames while it runs) and DISPSTAT bit 4 on. Then
  game_bg.arc entries of table 0x020CFA40 (stride 9): BG2 chars FUN_02006E50(2) (queued from the source pointer),
  BG2 map FUN_02006DCC(2) (copied into the BG manager map buffer at once), BG2 palette FUN_02006C6C(2, p, 0, 0xF0)
  (copied at once), VBlank wait, BG3 chars / map, VBlank wait, frees the 5 entries, closes the archive, then
  FUN_0201AC48(stg_N.bin, stg_N_tex.bin, stg_N_scr.bin) (pointer table 0x020D5E7C), a VBlank wait, FUN_0201ABA4(1)
  (S+0x554 = draw the stage) and BG0-3 offsets 0 (FUN_020069F8). No sound / BGM call anywhere in it. | H |
- **3D stage FUN_0201AC48** (H, C+V): texture file into a TAIL heap buffer (FUN_020090E4); per record (chain, see
  "stg_N_tex.bin"): FUN_02011128(slot S+0x404+i*0x14, w, h, fmt, 3) allocates a texture VRAM block (key -1),
  FUN_02010E54(slot, 0x20000000|i, texels, size) queues the texels, FUN_02010B6C(palette, size) allocates a
  texture-palette slot + queues it (slot start u16 S+0x40C+i*0x14, size S+0x40E); VBlank wait; frees the buffer.
  Then IF S+0 != 0 it frees S+0 AND every object pointer S+4.. (interior pointers of that block: would corrupt the
  heap; never reached because FUN_0201B0A4, the scene init of S, zeroes it — a second load must clear S+0 first).
  stg_N.bin → head heap S+0, object pointers S+4+4i (≤ 16, count S+0x550, chain via obj+0x54); if obj0 +0x3A != 0:
  fog on (FUN_020A6E00(1, 0, 10, obj0+0x3C & mask): DISP3DCNT bit 7 + shift 10, FOG_OFFSET) and FOG_COLOR =
  u32 obj0+0x36 (stages 2, 3, 4, 12, 13); the loader never turns fog off (scene init state). stg_N_scr.bin → head heap
  S+0x4B4; opcode 1 entries set the object's script start/current (S+0x44/+0x48 + obj*0x3C). Per-object script state
  S+0x44+i*0x3C (0x3C bytes, scene init: zero except u16 +0xA = 1 visible) run by FUN_0201A794 (ops 0..0x25, op 0x11
  tests the camera y), drawn by FUN_02019C74 (texture slot = S+0x404 + obj u16 +0x40 * 0x14). | H |
- **Texture VRAM / palette manager** u32 0x020DE380 (H, C+V; DATA_NOTES part 16 called it "OBJ VRAM": fighters are 3D
  quads, it is the TEXTURE manager): blocks {+0 VRAM offset, +4 size, +8 key, +0xC refs} listed at +0x600 sorted by
  offset between a head sentinel (+0x788, its size mirrors the first block's) and a tail sentinel at 0x60000 (VRAM
  A|B|C = texture slots 0-2), count u8 +0x7AE < 0x30, free structs stacked at +0x6C8; FUN_02010D28 = first-fit
  allocation, FUN_02010C2C(&slot) = release (refs-1, unlinked at 0), FUN_02010900(key) = lookup. Palette slots
  {u16 start, u16 size} at +0x7B4 sorted, count u8 +0x8B8 ≤ 64, unused entries 0xFFFF / 0 (the first-fit test reads
  entry [count] as the end marker), texture palette VRAM = bank G (slot 0); no free function (only the scene reset).
  Upload queues (texels +0x7AC, palettes +0x7AD, ≤ 32 each) and the BG manager queue (u32 0x020DD7BC +0x180) are run
  by the battle VBlank handler FUN_02013030 (FUN_0201098C, FUN_02006518). | H |
- **Fighter bounds** (H, C+V): per-stage record +0x10 flag, +0x12 x0, +0x14 x1, +0x16 y0 (top), +0x18 y1 (ground
  line) → FUN_0201B3DC → FUN_02021C68 → effect-pool block (u32 0x020DE3CC) +0x4DE7 flag, +0x4DE8 x0, +0x4DEA y0,
  +0x4DEC x1, +0x4DEE y1 (s16 px). Stages 0, 2, 7, 12: flag 1 (bounded: FUN_020218FC clamps both fighters into
  x0..x1), x 0x480..0xB80 / 0x300..0xD00 / 0x280..0xD80 / 0x360..0xCA0, y1 0x1000 (y0 0 / 0 / 0xAF0 / 0xAF0); the
  others: flag 0, 0..0x4000 x 0..0x2000 (y0 0xED8 on stage 8) and the battle wraps around: when the fighters'
  midpoint leaves x0..x1 both move by 3/4 of the width and FUN_02021DD4(dx, dy) moves every live effect object. The
  camera (u32 0x020DE3A4 → 0x021003CC: u16 +0 mode, +6 zoom, +0xC/+0x10 x/y) is the fighters' midpoint every frame in
  mode 0 (FUN_02019594); modes 2 / 4 = super / team-art sequences. Ground: fighter y ≥ y1 + u8 rec+0x24F. | H |
- **Stage ids** (H, C): stage select icon → id table 0x020D0758 = 10 12 11 9 4 7 5 8 3 0 1 2 14 13 6 (icon 15 =
  random 0-14); FUN_02071374 stores it with FUN_0200294C (party block 0x020DD54A). Read back only by the battle init
  (FUN_0201C150 argument) and the BGM choice in FUN_02013064 case 4 (and the story wrapper FUN_02079B48 copy);
  during the battle only globals +0xCBE is used. Battle scene state u8 0x020DD4C5 (FUN_020010E4): 7 = fight running
  (all modes: Z-Battle / Story wrap FUN_02013064). | H |
- **STAGE SHUFFLE** (port cheat, V): QoLGame `_stage_*` (qol_game.gd part 18). Every 600 battle frames (counted at
  P1's active record in FUN_0202954C) once the fight runs (state 7) with both fighters alive, no pause / cut-in, tag,
  assist slot, frozen fighter, camera mode != 0 or hidden stage: release the old stage (FUN_02010C2C per texture slot,
  palette slot entries removed from the list, model / script freed, S+0 / object pointers / count / object states
  reset as FUN_0201B0A4 leaves them, fog off), FUN_0201C150(new) with its VBlank waits skipped, the tail-heap texture
  buffer placed in port-only RAM 0x02740000 and BG2 / BG3 chars queued from copies at 0x02760000 (everything is
  uploaded at the next VBlank, from data still there), S+0x554 and BG0 / BG1 offsets restored, FUN_0201B3DC /
  FUN_02021C68 (new bounds), then fighters + effects (FUN_02021DD4) + camera moved by (centre x, ground y1) difference,
  clamped into bounded stages. Music untouched; party block stage kept. Evidence: Goku vs Goku from the ice stage
  (14), `stglist=10,0,13,10,14,10`: VRAM / RAM of the swapped-in stage 10 vs stage 10 loaded normally (party block
  poked; both runs with the fighters poked to the same spot for 100 frames) — model + script bytes (= ROM files),
  object table, bounds, texture params, texels and palettes, DISPCNT 0x08010F09, DISPSTAT, BG2CNT, BG3CNT, DISP3DCNT
  0x3019, fog registers, BG palette, BG2 / BG3 chars and maps all identical; only BG3's affine reference point
  differs (the sky's time phase); top screen differs only in the sky band. Same for 14 → 13 → 2 (fog, bounded):
  DISP3DCNT 0x3A99 identical, 1 differing pixel outside the sky. Heap free per stage constant over swaps (stage 10
  1346700, 14 1336272 = the battle-start value, largest block back to 1335456), palette slot count = base + the
  stage's textures, BGM id 15 through every swap, ~30-90 ms per swap in the cloud sandbox. Combined with CHARACTER
  SHUFFLE (team + support, taps) 5 + 5 swaps without errors. KO on a swapped-in stage → Game Over / Continue →
  VS screen → rematch on the picked stage (14) with its BGM 15, heap free at its start 1336272 = the first battle's,
  and the shuffle goes on. Cheat off: 21 captures + 422 cheatdbg lines byte-identical to the run before the change.
  The vertical-strip look of both fighters during P2's Y+B throw (actions 0x2A / 0x85 / 0x34) is the game's own (also
  seen with no swap in that battle).
- **Card DMA vs VBlank uploads during the swap** (V): the character-swap freeze (VBlank handler FUN_02013030 uploading
  with DMA 3 while the card DMA 3 is armed, busy-wait on 0x040000DC) could also hit FUN_0201C150's card reads, so
  f_0201098C / f_02006518 also skip while `_stg_busy` (queues kept, uploaded at the next VBlank). Queue limits (C):
  FUN_02010E54 / FUN_02010B6C refuse when +0x7AC / +0x7AD ≥ 32 (FUN_0201AC48 then aborts the load), FUN_02006E50 /
  FUN_02006B68 / FUN_02006C6C refuse at BG queue +0x180 ≥ 32 (FUN_02006DCC then does not even copy the map). A stage
  queues ≤ 4 textures + 4 palettes (records per stg_N_tex.bin: 3 3 3 3 4 3 2 4 2 3 2 2 3 3 3 for ids 0-14) and 5 BG
  entries; measured right after the load (nothing drained): peak 4 / 4 / 5 alone, 5 / 6 / 15 with CHAOS SHUFFLE
  swapping in the same frame — far below 32. Mid-load VBlanks observed: 0 in 38 swaps (27 alone through all 15
  stages + 12 random; 11 with CHAOS SHUFFLE, 108 character swaps): the stage files are read before the frame's line
  192. Long run (20500 frames): heap free per stage identical on every revisit (e.g. 13: 1351992 ×3, 2: 1328604 ×3),
  no freeze / script error; cheats off: 35 captures + 680 cheatdbg lines identical to the earlier baseline.

## Session 1 part 18 findings (dash, attack spam) — V = port / melonDS verified, C = code read
- **R dash** (H, C+V): FUN_020272F0 (from the neutral / move handlers): R held + a direction held + ki > 9 % → ki
  0xA00 mode 0 (FUN_02027950, scaled by u16 blk+0x12 / 256: level-3 boss 5 %), action 0x0B (FUN_0202C3E8; at its end
  action 0x0A + effect 4). Action 0x0A FUN_0202C1D4: R released → FUN_020213A8(f, s16 +0x22, -(u16 blk+0xE), 0,
  +0x21) and FUN_0202B630 (neutral); every 4th frame (u16 +8 & 3 == 0) it re-aims: direction held → speed = s16
  blk+0xC, velocity = half-sum of the unit vectors to the held direction (FUN_02029448) and the facing; NO direction
  held → speed = (s16 blk+0xC * u16 blk+2 * 0x100) >> 16 computed in int32, FUN_020213A8(f, v, 0, v, +7 & 0xE0).
- **Parameter block** (u16 fields of fighter +0x50, C): +0 HP, +2 speed scale (0x14C = 1.3 normal, 0x500 level 3),
  +4 walk speed, +6 walk brake, +8 / +0xA step-dash speed / accel (double tap FUN_020273AC, FUN_0202C4A0), +0xC R-dash
  speed, +0xE R-dash brake, +0x10 melee damage scale (FUN_02027C2C), +0x12 ki-cost scale, +0x14 ki-attack damage
  scale (FUN_0201E9EC), +0x18 guard-crush scale (FUN_020292E8), u8 +0x1C combo length, +0x1D, u8 +0x1F..+0x22 super
  costs. Character handlers (power-ups) write +0x10 in place (e.g. 0x140 Kaioken, back to 0x100) (M).
- **Boss dash bug** (H, V melonDS + port): level-3 blocks (+2 0x500, +0xC 0x1E00 in every fighter's chunk, ids
  0-25; BOSS CHARACTERS uses level 3 for SSJ Goku 1, Cell 15, Broly 20) make the no-direction product 0x1E00*0x500*0x100 =
  0x96000000 → int32 negative → speed -27136 (0x9600 as s16) = 106 px/frame BACKWARDS; releasing R brakes with accel
  -0x200 in the same direction, so the velocity grows to -32768, wraps to +32256 and flies back. Level 2 (0x1000 *
  0x14C → 0x14C0) and every normal block fit. melonDS, battle_ready, P1 Goku +0x50 := block 3, R+Right 20 frames
  then R only: speed 7680 → -27136 at f183, x 8299 → 6694 in 26 frames, vx -32256 → +32256 at f223 (P2 dragged along:
  the fighters' maximum distance); block 0: 3328 → 4316 forward. Ki 25600 → 24320 (−5 %), as in the user's video.
  The game only gives these blocks to CPU fighters (FUN_0202117C); a CPU boss would hit it too if its AI dashed
  without a direction (not observed, L). Port fix (QoLGame `f_0202c1d4`, BOSS DASH part 18): for fighters the BOSS
  CHARACTERS cheat made bosses whose product overflows, the handler's no-direction speed is set again with the
  normal block's scale (+2 of block 0): boss Broly 7680 held → 9960 forward (normal Broly 3072 → 3984, same 1.3
  ratio), brake −512/frame to 0 (V port trace `dashdbg`: bug run speed −27136 / camera across the stage; fixed run
  continues forward and stops). Everything else of the boss block (HP, 5× walk speed, dash 0x1E00, damage, ki costs)
  is kept.
- **Melee hits** (H, C+V): FUN_0201E5BC tests every registered object pair of different sides: frame descriptor
  (+0x120) boxes {s16 x, y, w, h, u32 type} (type 1 attack, 2 / 4 hurt; scaled by u16 +0x154 / +0x156, mirrored by
  the facing) → attacker's hit handler u32 [obj+0x34](attacker, victim). Melee / dash-attack handlers (0x1C-0x1F
  FUN_0202BE94, 0x20 FUN_0202BE44, 0x22 FUN_0202BD34) set +0x34 = FUN_02027C2C each frame. FUN_02027C2C: victim
  u16 +0x10E < 0x25 = a fighter; attacker +0x250 & 4 = already hit in this animation frame (set with 0x2000 on a
  hit; the VM's show-frame ops clear 4, op 0x8C clears 0x2000 / plays the hit voice); victim guarding (+0x250 & 9) →
  push / guard crush; else damage u32 header[0] * u16 blk+0x10 >> 8 (FUN_020293A4), hit-stop FUN_02012F9C(8 dash
  attack / 2) (globals +0x1BCAC), victim pushed FUN_020213A8(victim, s16 header+4, -0x40, 0, attacker facing) (victim
  at a wall / on the ground, u16 +0xC & 6: the attacker is pushed back too); dash attacks 0x20 / 0x22: victim action
  0x11, stun u16 +0x25E 10 / 20, attacker ki +0x1400; other hits: victim 0xF, stun 0, ki +0xA00; combo window u8
  +0x257 = 12 + team RUSH counter +0x8E0 (FUN_02029804); victim +0x250 |= 2. Hit-stun handlers 0xF / 0x11
  FUN_0202BCD0 and 0x10 / 0x12 FUN_0202BC08 leave when the animation ends and +0x25E == 0 (KO check FUN_0202759C).
  Melee combo: Y → FUN_0202AEB4 steps forward (0x200) and starts 0x1C, or 0x1C + ++u16 +0x258 while +0x257 != 0 and
  the count < u8 blk+0x1C; 0x1D-0x1F pick their script by the held direction (VM op 0x04). No attack cooldown: the
  limits are the long recovery (X dash attack ~33 frames), the dispatcher only running in neutral / move, and the
  push that carries the victim out of reach (heavy finisher 0x1F: speed 2048, dash attack 3072).
- **ATTACK SPAM** (port cheat `attack_spam`, QoLGame part 18, V): an attack button (Y / X / A) during P1's melee
  (0x1C-0x1F), dash attack (0x20-0x22) or ki blast (0x24, not before its first shot) ends it with FUN_0202B630 so the
  dispatcher starts the new attack the same frame (Y during melee sets +0x257: the combo goes on and cycles); supers,
  ultimates, beams, R+A / R+B, Y+B throws, team arts are never cut; not during KO / tag / pause / cut-in / assist call.
  P1's FUN_02027C2C hits push victim (and the wall-pushed attacker) at 64/256 speed. Free Battle Goku vs Goku (CPU),
  300 frames: X every 8 frames: off 3 hits 13000 → 9760; restart only 5 hits → 7600; ATTACK SPAM 13 hits → 0, KO
  action 0x33 at f4807 (RUSH counter 13), then KnockOut / WIN, win pose and the results screen as usual. Y every 6 frames: off 9 hits (2 finishers 0x1F) → 11119; on 37 hits (9
  finishers) → 4783, RUSH 34. X+A pressed during the Y spam: the super 0x2C → 0x2D (Goku's Spirit Bomb) runs as usual.
  Cheats off: a Free Battle capture run (345 captures, 1674 cheatdbg lines) is byte-identical to the run before part 18.

## Session 1 part 18 findings (chaos shuffle, triple ki) — V = port verified, C = code read
- **Fighter action dispatch** (H, C+V): FUN_0202954C runs action u8 rec+6 through u32 rec+0x280 (= 0x020D7958, the
  same generic table for every character, ids 0-0x84) or, for ids >= 0x85, u32 rec+0x284 [id-0x85] (per character,
  set by the init handler 0x020D78C4[id]; correction to part 16: +0x284 is that table, +0x244 is the character's
  EFFECT KIND table {per-frame handler, hit handler} × kinds). Generic table: 0/5 FUN_0202CC70, 1-4 FUN_0202C9B8, 6
  FUN_0202C74C, 7/8 FUN_0202C4A0, 9 FUN_0202C620, 0xA FUN_0202C1D4, 0xB FUN_0202C3E8, 0xC FUN_0202C13C, 0xD
  FUN_0202C02C, 0xE / 0x18 FUN_0202BFF8, 0xF / 0x11 FUN_0202BCD0, 0x10 / 0x12 FUN_0202BC08, 0x13-0x15 FUN_0202D170
  (intro / win poses), 0x16 FUN_0202BBAC, 0x17 / 0x1B / 0x31 FUN_0202D100, 0x19 FUN_0202BF70, 0x1A FUN_0202BEEC,
  0x1C-0x1F FUN_0202BE94, 0x20 FUN_0202BE44, 0x21 FUN_0202BD84, 0x22 FUN_0202BD34, 0x23 FUN_0202BB84, 0x24 FUN_0202BB5C,
  0x26 FUN_0202B9F0, 0x27 FUN_0202B9C8, 0x28 FUN_0202B998, 0x29 FUN_0202B8D0, 0x2A FUN_0202B698, 0x2C FUN_0202BB08,
  0x2D FUN_0202BAD8, 0x2E FUN_0202BA78, 0x2F FUN_0202BA10, 0x30 FUN_0202B85C, 0x32 FUN_0202B904, 0x33 FUN_0202B4A0 (KO),
  0x52 FUN_0202B80C, 0x2B / 0x34-0x66 FUN_0202D128 (move; at the script's end flag: FUN_020297DC(f,1) + FUN_0202B630),
  0x25 / 0x67-0x84 FUN_0202D164. FUN_0202B630 = the game's attack end (KO check FUN_0202759C, +0x250 = 0, action 0 or
  5 when +0x10 & 1 = in the air). Action 0x34 (seen as the victim of Y+B throws / clashes, P2 0x85) lasts ~240
  frames. Script count u16 rec+0x110 (= chunk struct +0xCC): FUN_02020BD4 ignores ids beyond it.
- **Effect object life** (H, C+V): allocation FUN_020227D4 = first of 48 slots with +4 == 0 (+4 = 1, pool +0x4DE0
  count + 1); 8 more slots at pool+0x42C0 run by the same loop. Per frame FUN_02021F54: for +4 != 0: if (+4 & 6) ==
  0: kind handler u32[obj+0x40 + 8*kind](obj), VM FUN_02022930, attach FUN_02020F80 (flags 0x30), life FUN_0202104C
  (flags 0xE); then +4 & 2 → FUN_02021D90 (sprite release FUN_0201205C → FUN_02010C2C, 0x164 bytes zeroed, +0xC |=
  1) else draw FUN_02019328. Killing = +4 = 2 (what FUN_0202104C does). Spawn FUN_020225C8(owner, kind, chunk struct,
  kind table, slot or 0): copies the chunk struct to +0x44, FUN_02021B4C(obj, kind), +0x40 table, +0x34 hit handler
  = table[kind].hit, sprite +0x124 (FUN_02012084 dims from the script header, no VRAM yet), position = owner's. VM op
  7 (fighter script) = spawn (chunk rec+0x164 or the object's own copy, table rec+0x244) + FUN_0202216C(obj, script
  offset, position offset). Plain projectile handler FUN_020209E0: sub-state +8 == 0: +7 = owner's facing, sprite
  rotation FUN_02011F74(sprite, 0, 0, 0x100 - facing) unless +0xE & 0x80, sub-state 1; then FUN_02021264 (move) +
  FUN_0201DEE0. The shot's own script sets its motion with VM op 0xE FUN_020213A8(obj, speed, accel, max, +7).
- **Camera** u32 0x020DE3A4: u16 +0 mode — 2 during supers, 4 during team arts / intro sequences (V: chaos waits).
- **Port freeze, card DMA vs VBlank uploads** (H, V): a long card read mid-battle (shuffle loads) waits block by block;
  the port delivers the VBlank IRQ meanwhile with the card DMA (channel 3, mode 5, repeat: DMA3CNT 0xAF000001, source
  0x04100010) armed; the battle VBlank handler FUN_02013030 → FUN_0201098C (texture / texture-palette queues) →
  FUN_020A8B0C → FUN_020AB82C waits for DMA3 to be free (GX DMA = 3) → endless loop, "busy-wait on 040000dc", game
  stopped (chaos run, 16th swap, deterministic). FUN_02006518 (BG queue) uses DMA the same way. QoLGame skips both
  runners while a character swap loads (queues kept, uploaded at the next VBlank). The game's own frame streaming
  (FUN_02020C08) and STAGE SHUFFLE's loads could in principle hit the same window (not observed). M
- **CHAOS SHUFFLE** (port cheat, V): `_shuffle_swap(f, true)` every 60 battle frames counted from battle state u8
  0x020DD4C5 == 7 (no intro swaps: swapping restarted the intro action 0x13 forever). Waits only for KO (either
  side), P1 super 0x2C/0x2D/0x2E, pause / cut-in FUN_02012FD4, tag (globals+0x11DC), P1 frozen (+0x250 & 0x800),
  camera mode != 0. Before the release: FUN_020297DC(f, 2) and +4 = 2 for every object whose +0x44 is the old 'c' or
  effect chunk. After: generic action (< 0x19 or 0x34-0x66 except 0x52, below the new script count) restarted with
  FUN_02021B4C, but a reaction already restarted at the previous swap ends (FUN_0202B630); attacks / call pose /
  power-up / throws / >= 0x85 end with FUN_0202B630. Lower-screen panels cached per party-id triple (uploads + maps +
  globals +0xCE0..+0xCE3): a repeat costs 0 ms instead of ~26. V: 33 swaps in 1560 frames (Goku + Vegeta + support
  26, busy inputs): mid ki blast (0x24 → 0), R+A (0x23 → 0), melee (0x1C / 0x1D → 0), dash attack (0x20), call pose
  (0x28 → 0), hit stun (0xF → 0xF), throw victim (0x34 → 0x34 → 0), guard (0x18), moves; up to 6 objects killed per
  swap; open archives 8 / 10, cache entries 30 throughout; heap free back to the same value per character (Goku
  1223380 every time); 50-117 ms per swap here (load 28-52, voices 12-40, icon 7-12, panel 0 cached / 25-38).
- **TRIPLE KI BLASTS** (port cheat, V): QoLGame `f_020225c8` notes every object player 1's fighters (record +0x10E < 0x1A,
  +0x1A == 0; supports / assists not) spawn whose kind handler u32[table + 8*kind] is FUN_020209E0 (plain projectile:
  ki blasts and plain-projectile specials; beams FUN_02020330 / FUN_020203CC / FUN_02020560 never). At the shot's
  first handler call (sub-state 0, its script start and position already set by FUN_0202216C, its motion not yet)
  two more objects come from FUN_020225C8 with the same arguments (game allocation / count / sprite set-up; a full
  48-slot pool returns 0 → no copy) and get bytes +8..+0x123 of the shot (each keeps its own sprite struct +0x124,
  no VRAM block yet); after their own first handler call has set +7 from the owner, +7 turns by ±9/256 (12.7°) and
  the sprite rotation is set again, so the script's op 0xE FUN_020213A8(…, +7) fans them. KI HOMING turns copies
  too (same owner), NO COOLDOWN unaffected, CHAOS kills copies with the shot (same chunk). V (Goku vs Goku, A every
  14 frames from port frame 4560, infinite health): live P1 blasts peak 23 vs 6 without; P2 HP 13000 → 580 at
  f5190 vs → 6628 without (same ki spent); captures show three blasts per shot in a fan.

## Session 1 part 19 findings (shadows) — V = port verified, C = code read
- **Battle sprites** (H, C+V): every battle sprite (fighters, effects, face icons, HUD pieces, the ground shadow) is a
  0x40-byte sprite object drawn as an orthographic textured 3D quad, not an OBJ. FUN_02011F98(spr, x, y, flags)
  appends it to the draw list (u32 [0x020DE384] → u32[64] pointers, u8 count +0x183, s32 global scale +0x184 =
  camera zoom, 256 = 1.0); FUN_02011384 draws the list once per frame (end of the battle draw FUN_02012D70) and
  clears it. Per sprite: drawn only if +0x3D != 0, alpha +0x3B > 7 and *(+0) != 0; MTX_PUSH, MTX_TRANS(+0x1C x,
  +0x1E y, byte +0x3C z), rotation FUN_020A71C8(sin, cos) from s16 pairs 0x020D0F5C[+0x38 >> 4] (G3_RotZ rows
  (c, s), (-s, c)), MTX_SCALE(+0x14, +0x18 (20.12 px) × the global scale unless +0x3E bit 3), texture matrix
  identity (+0x3E & 0x30: S scale), TEXIMAGE_PARAM = (*(u32*)*(+0) >> 3) | (+0xC format) << 26 | 0x40000000 |
  (+0x10) << 20 | (+0x11) << 23 | 0x20030000 (0x20070000 when +0x3E bit 5), PLTT_BASE = u16 +8 >> (4, 3 for
  format 2), POLYGON_ATTR 0x8080 | a << 16 | (0x20 - a) << 24 (a = +0x3B >> 3; front faces only, modulation),
  BEGIN quads, 4 × TEXCOORD (+0x20/+0x24/+0x28/+0x2C = u0, v0, u1, v1) + VTX_16 (±0.5), order flipped by +0x3E bits
  0-1 (1 = mirror x, 2 = mirror y), bit 2 = vertices from list +0x100 + 16 × byte +0x3A; END, MTX_POP. Vertex colour
  = white from DIF_AMB 0x4210FFFF (bit 15) set once at the start. Higher +0x3C z = nearer (fighters 3 / 5, dust 7,
  face icons 0x1A, ground shadow 1). Fighter body = record +0x124 (128x128 4bpp texture in its own VRAM block,
  frames streamed into it), registered by FUN_02019328 at screen (zoomed) coordinates of +0x38/+0x3C.
- **Ground shadow** (H, C+V): one per TEAM, sprite object at team block +0x888 (FUN_0202A40C: FUN_02012084 64x32
  4bpp, z 1, tiles / palette = /romdata/game file entries 0x4A / 0x4B of the archive opened there; no other code
  references +0x888, so it never scales or fades). FUN_0202A254 (battle draw, after the fighters registered,
  only when globals +0x1678 != 0) registers it for the ACTIVE member of each team (team +0x8C8) when
  ground − (y >> 8) < 256 (ground = u16 *(*(0x0201B49C)) + 0xCC2 = 8192 on the ice stage; fighters stand at
  y 8224 for Goku) and record +0x161 != 0: x = fighter screen x (FUN_02019180) + s8 0x020CFCC4[id] (negated when
  record +0x12 bit 0; only id 21 has one: −12), y = screen y + (ground − y) + f + (zoom × (64 − f) >> 8) with
  f = u8 0x020CFCA8[id] (= record +0x24F; 32 for Goku: the feet are f px below the sprite centre at zoom 1). So the
  ellipse stays on the ground line while the fighter jumps, and supports / assist copies never get one. V (port,
  RAM at Free Battle frame 4639): P1 airborne y 8146 → shadow (142, 167) under sprite (142, 57); P2 standing y 8224
  → shadow (113, 167) under sprite (113, 135).
- **DETAILED SHADOWS** (port setting, V): QoLGame `# ---- DETAILED SHADOWS (part 19)` overrides FUN_02011384. With the
  setting on, the two ellipse pointers are swapped for an empty sprite object (port RAM 0x02720000) while the
  drawer runs (restored after), then each is replaced by a black copy of its fighter's quad: same TEXIMAGE / PLTT
  (= the current animation frame), texcoord flip, rotation and scale, COLOR 0 (modulation: texel × black = black,
  colour 0 stays clear), one MTX_MULT_4x3 = T(ellipse centre, z 1) · Q · T(−feet) · R · S with the feet at
  (ellipse x − sprite x, f × quad height / 128) and Q = mirror downward (cast toward the viewer), squash 0.35,
  shear 0.3 (flags `shadowk` / `shadowc` / `shadowflip=0` to try others); POLYGON_ATTR bit 6 added because the
  mirrored quad faces away. Emitted after the list, so earlier polygon numbers are unchanged (smooth-motion matching
  by polygon number), then COLOR 0x7FFF. Supports and ASSIST SPAM copies drawn this frame get one by the same rule
  (record +0x161, height < 256, not +0x12 bit 3 screen-space). Setting off: the override only calls super —
  captures byte-identical to captures made before the change (22/22 frames, Free Battle 4600-4700). On vs off
  (151 frames 4600-5050, ground fights): every differing pixel is black in one of the two images except where a
  translucent aura is drawn over the shadow (17 frames, R charge). Silhouettes follow pose / flip / dash-lying pose /
  ki blast pose, shuffled characters (Metal Cooler with tail) and stage shuffle; with smooth motion an in-between
  frame moves the silhouette exactly when it moves its fighter (both are matched or neither: same frames).
- **Tool note** (V): tools/dump_gx.gd prints out_attr/out_tex/out_pal[i / 3] although those arrays are per vertex
  (index i): its attribute columns are wrong for every triangle after the first third.

## Session 1 part 19 findings (chaos fixes) — V = port verified, C = code read
- **Throws** (H, C+V): FUN_0202B698 (action 0x2A, Y+B) on contact (+0x250 & 0x10000, range FUN_02026D40) calls the
  thrower's throw function u32[0x020D76BC + 4*id](thrower, victim): thrower action 0x85 (its first character
  action), victim a generic victim state by THROWER id: 0/1 0x34, 2/24 0x35, 3 0x36, 4 0x38, 5 0x3A, 6/7/21 0x3C,
  8/22 0x3E, 9/23 0x40, 10/11 0x4E, 12 0x42, 13 0x48, 14 0x47, 15/25 0x44, 16 0x49, 17 0x4B, 18/19 0x4D, 20 0x50;
  then both get +0x250 |= 0x20 | 0x400 (0x400 = no character handler, 0x20 = in a sequence), globals +0x1674 = 1,
  FUN_02028FB0(side, 1000). A miss: action 0x2B. (V: P2 Goku throws P1 at port ~4290: P1 0x34 / P2 0x85 for ~240
  frames.)
- **Grab supers** (H, C+V): FUN_02028DDC(attacker, victim, range) → u32[0x020D7724 + 4*id](attacker, victim) (0 =
  none) sets the victim's state, the same +0x250 |= 0x20 | 0x400 on both, FUN_02028FB0 with a longer time when the
  state is 0x5A-0x66. Characters with one and the victim state: 0 Goku 0x5A, 2 0x5B, 5 Piccolo 0x5C, 6 Vegeta 0x5D,
  7 SSJ Vegeta 0x54, 9 0x57, 11 0x5F, 12 Ginyu 0x5E, 13 0x60, 14 0x65, 15 Cell 0x61, 16 Fat Buu 0x63, 17 Kid Buu
  0x55 (attacker in 0x2D, the side super "ball") / 0x64 (otherwise), 20 Broly 0x59, 22 0x66, 23 0x56, 24 0x53, 25
  0x62; none for 1, 3, 4, 8, 10, 18, 19, 21. All victim states (0x34-0x66) use the generic handler FUN_0202D128;
  the attacker's script moves / hides the victim (V: Kid Buu's ball keeps P1 in 0x55 for ~180 frames, hidden).
- **Summons** (H, V): Ginyu's and Cooler's X+A supers spawn (in action 0x2D) an effect object (kind 9) that spawns
  the summoned fighters as further effect objects (Ginyu: kinds 0x0F / 0x11 / 0x12 / 0x14 / 0x15 / 0x17 / 0x18,
  Recoome's beam; Cooler: kinds 0x17 / 0x18 / 0x19 / 0x1C, the armoured squadron); they keep attacking ~100-150
  frames after the summoner is back in action 0, and they are made from the summoner's chunks (killed by a swap).
  Metal Cooler (19) and Majin Vegeta (21) supers also leave such objects for a while.
- **Visibility**: sprite +0x3D (FUN_02011D54) — a fighter's at rec+0x161 (FUN_0202A254 tests it for the life-bar).
- **CHAOS SHUFFLE part 19 waits** (port, V): besides KO / P1 super / pause / tag / frozen / camera: P1 action 0x2A /
  0x2B or >= 0x85; P1 victim state 0x34-0x66 (not 0x52); +0x250 & 0x420 on P1 or the opponent; opponent action
  0x2A-0x2E or >= 0x85; P1 hidden (+0x161 == 0); effect objects made by a fighter in 0x2A-0x2E / >= 0x85 / +0x250 &
  0x20 (or by such objects), tracked at FUN_020225C8, waited for at most 600 frames. Debug flags `chaosat=F,…`
  (forced due frames) and `p2keys=F:MASK:N,…` (P2 input). Checked (V): Kid Buu ball super on P1 (waits "held
  (victim state 55)" ~180 frames, swap the frame P1 is released, P1 visible), P2 Goku throw on P1 (waits 0x34,
  swap at port 4539 when it ends), P1 throw attempts (0x2A / 0x2B), Ginyu and Cooler summon supers as P1 (waits
  0x2C → 0x2D → "super / summon objects", swap after the last summoned fighter left: port 4814 / 4757), and a
  14-super hunt with random P1 characters (Ginyu, Metal Cooler, Krillin, 22, Gotenks, Teen Gohan, Majin Vegeta,
  Piccolo, Cell, SSJ Goku): every swap after the super / its objects, P1 visible, no error. Also V: P1 Frieza
  (final) throw on Cell (P1 0x85 / P2 0x4E ~250 frames, 1600 damage, swap at port 5049 right after), Broly's grab
  super on P1 (P1 0x59 port ~5150-5315, then "opponent super 2d" until Broly's action ends, swap at 5330), P2 throw
  attempts / misses (0x2A / 0x2B). Cheats off: /tmp/ssw2/btn (345 captures + 1674 cheatdbg lines) byte-identical.

## Session 1 part 20 findings (camera zoom) — V = port verified, C = code read
- **Battle camera zoom** (H, C+V): camera struct u32 0x020DE3A4 → 0x021003CC (= battle globals FUN_0201301C + 900):
  u16 +0 mode (0 follow FUN_02019594, 1 pan FUN_02018DA4, 2 super / follow one fighter, 3 fixed, 4 team art), u16 +2
  flags (bit 0 shake: +4 frames, +0x38/+0x3A amplitudes; bit 1 zoom transition), u16 +6 zoom (8.8, 256 = 1.0), +8
  fighters' distance, s32 +0xC/+0x10 centre x/y (px), +0x14..+0x28 pan from/to/frames/target fighter, s32 +0x30/+0x34
  screen centre (FUN_0201930C(0x80, 0x60), every frame from FUN_0201B5C0), +0x3C/+0x3D/+0x3E/+0x40 zoom transition
  step / steps / from / to (FUN_020193FC(to, steps), effect script op; steps 0 = at once). Camera update FUN_02019980
  (once per battle frame, after fighters + effects, before the stage FUN_0201DDC4 and the draw FUN_02012D70). Mode 0:
  centre = fighters' midpoint, d = sqrt(dx² + (4·dy/3)²) (hardware sqrt), zoom = 0x100 if d < 0xC0, else 0x14000 /
  (d + 0x80) clamped to 0x80..0x100; when it would go below 0x80 the fighters are pulled together along their line
  (tether: max on-screen spread = 256 px, both at the screen edges). Modes 2 / 4: FUN_0201945C, the same formula on
  the camera-to-target distance. Every mode ends with FUN_02012154(+6) = sprite list global scale ([0x020DE384] +0x184).
- **Readers of +6** (H, C): drawing — FUN_02019328 (fighters, effects FUN_02021F54, supports FUN_020287E8: screen =
  centre + zoom·(pos − cam) / 256), FUN_02019180 (screen position: ground shadows FUN_0202A254, and gameplay
  FUN_02031EC8 = an effect that bounces at the screen edges), FUN_0201B5C0 (3D stage: S+0x54C = (0x100 − zoom) / 2,
  subtracted × object z scale from every stage object's z: the game zooms the stage by moving it back, a dolly, not a
  scale), FUN_0202A254 (shadow y). Gameplay — FUN_0201921C (fighter on screen, ±128 / ±96, used by FUN_02017358 case
  4), effect script op 0x39 (FUN_02022930: spawn offset (zoom − 0x80) · 0.75 px from the midpoint), FUN_020193FC
  (start value of a zoom transition). Effect script op 0x43 places objects at camera + offset (no zoom). | H |
- **3D stage projection** (H, C): FUN_02019C74 is the only caller of the perspective FUN_020A7710(fovySin 0x800,
  fovyCos 0xDDB, aspect 0x1555, near 0x1000, far 0x1900000, scaleW 0x1000) (60° fovy); FUN_020A7710 builds the y entry
  as cos / sin (FUN_020A4F1C) and x = that / aspect, so scaling fovyCos scales the whole 3D stage around the screen
  centre. Stage objects: horizontally repeating objects (+0x34 = 1) are drawn twice (at cd0 mod width and the
  neighbouring copy); camera y is clamped to ≤ the stage height (+0xCC2) in FUN_0201B5C0. | H |
- **Ground shadow drop** (H, C+V): FUN_0202A254 y = screen y + (ground − y) + f + zoom · (64 − f) / 256: the
  (ground − y + f) part is not scaled by the zoom, so in the original an airborne fighter's ellipse is too low whenever
  the game zooms out (zoom < 1.0). | H |
- **CAMERA ZOOM** (port setting, V): QoLGame `# ---- CAMERA ZOOM (part 20)`, QoLSettings.camera_zoom 0..4 (flag
  `zoom=N`), factors k = 0.7, 0.85, 1.0, 1.15, 1.3 (2 = the game's camera; every override then only calls super).
  RAM +6 keeps the game's value for all logic; the scaled value (game zoom × k; zoomed in: never more than keeps both
  active fighters' centres 40 px inside the screen, never less than the game's own) is written into +6 only while the
  drawing functions run (f_02019328, f_02012D70 = shadows + stage model + sprite list; restored after), and passed to
  FUN_02012154 (sprite scale). The 3D stage keeps the game's own dolly (FUN_0201DDC4 runs with the game's zoom) and
  the projection is scaled by (scaled / game zoom) (f_020A7710: fovyCos × ratio), so fighters, effects, beams,
  shadows and stage are the level-2 picture magnified about the screen centre (fighters stay on the same spot of the
  ground); the ground shadow drop (ground − y + f) is scaled by the zoom at levels != 2 (f_0202A254 post-fix, and the
  DETAILED SHADOWS support silhouettes via `_zm_drop`). Not scaled (fine): BG2 panorama / BG3 sky (2D, behind, scroll
  only), HUD (screen-space sprites, +0x3E bit 3 / flags 8, 9), bottom screen. Gameplay readers (on-screen tests,
  bouncing effect, op 0x39 / 0x43 placement) stay at the game's zoom: game state is identical at every level (debug
  `zoomcycle`: level = frame % 5 in one run; `zoomk=F` factor override; `zoomdbg` per-frame log). Evidence (Free
  Battle Goku vs Goku, cap_every=4 + zoomcycle, sheets /tmp/ssw2/zoom_<run>_a/b.png, columns = levels 0..4):
  ice 14 (zoom_c2), Tenkaichi 0 bounded (zoom_s0: both fighters at the walls, beam across the screen), ruins 10
  (zoom_s10), stage 12 bounded (zoom_s12), stage 8 (zoom_s8); no void / missing stage at 0.7 × 0.5 = 0.35, beams and
  ki blasts scale and stay attached, shadows under standing fighters; team art / assists / tag with zoom=0 +
  capinterp=0.5 (zoom_tB); DETAILED SHADOWS silhouettes scale with the level (zoom_sh); STAGE SHUFFLE ice → ruins swap at
  port 4492 with zoom=0 (zoom_stg). Level 2 (setting default): 145 captures + 1269 cheatdbg lines byte-identical to /tmp/ssw2/btn.

## Session 1 part 20 findings (graphics) — V = port / melonDS verified, C = code read
- **Effect life flags** (H, C+V): FUN_0202104C (once per effect object per frame): s16 +0x18 counts down, 0 with
  +0x10 & 2 → status +4 = 2 (dying); +0x10 & 8 and owner u32 +0 != 0 and owner's action byte +6 != byte +0x1B
  (the owner's action at spawn) → dying; +0x10 & 4 and owner +0xC & 1 → dying. Pool u32 [0x020DE3CC] → 48 × 0x164
  (+0x1A side, +6 kind, +0x40 kind table: u32 handler at +kind*8, script at +4; +0x34 hit handler).
- **Step dash** (H, C+V): FUN_020273AC (neutral / move handlers): a direction tap stored (+0x254 |= 2, +0x25A = dir
  bits, +0x14 = 15-frame window); the same direction again → speeds from blk +8 / +0xA × blk +2, action 9
  (FUN_02021B4C(f, 9)); +0x254 bit 2 = forward, bit 3 = backward. Action 9 FUN_0202C620: when its animation ends →
  action 7 (forward) / 8 (backward), +0xE |= 8, FUN_02029E3C(f, 0xC), effect kind 6 (burst, flags 0, alpha fades
  255 → 0 in ~10 frames) and kind 5 (speed lines, flags 0x18, +0x1B = 7 / 8, rotated 0x100 − dir by FUN_02011F74).
  Actions 7 / 8 FUN_0202C4A0: 16 frames (u16 +8), then speed set back, FUN_0202B630 (neutral) and, when +0x10 & 1,
  effect kind 4 (dust, at y + 0x18); Y or X during it → action 0x21 (dash attack). So the lines live exactly as
  long as the dash: melonDS battle_ready (P2 pushed 200 px away every frame), Left, Left: action 9 F146-149,
  8 F150-166, kind 5 alive F150-F167 (17 frames), gone F168; port Free Battle 4611-4627 the same on screen.
- **Other flag-8 effects** (V melonDS): R charge (action 0x0D) auras kinds 5 / 6 flags 8 (+0x1B 0x0D); R + direction
  dash (0x0A) lines kind 4 flags 0x18 (+0x1B 0x0A); port debug: Goku's super 0x2D shot kind 8 (handler 0x020209E0,
  hit 0x0201F474) flags 8 (+0x1B 0x2D).
- **NO COOLDOWN bug** (V, fixed): QoLGame's FUN_0202104C override (part 13) turned EVERY player-1 object with flag 8
  into a 60-frame countdown whenever P1's action changed for any reason, so with the cheat on the step-dash lines,
  R-dash lines and charge auras hung on the fighter ~1 s after the move ended (port, cheats=no_cooldown: lines on the
  standing fighter 4629-4686; 718,686 px differ from the cheat-off run over 257 frames). Fix: no FUN_0202104C
  override any more; `_cancel_attack` calls `_nc_keep(f, act)` before it ends the attack, which converts only the
  objects of that attack (owner = P1 fighter, flag 8, +0x1B = the action cut short). Checks: cheats=no_cooldown
  without any cut attack → byte-identical to the cheat-off run (257 frames); Spirit Bomb (0x2D) cut by A at 4749 →
  "nc cut … kind 8 … keep true", bomb flies on, byte-identical to the part-17 code (257 frames).
- **Regression scan, cheats off** (V): current tree vs part-17 tree, same scripted Free Battle (ki blast, guard,
  X dash attack, Y combo, L power up, R charge, R+A, R+B, Y+B, double-tap dash, R dash, X+A super), cap_every 2,
  4550-5500: 477 / 477 captures byte-identical at 60 fps and with capinterp=0.5; double-tap dash 4595-4680 every frame
  identical (60 fps and capinterp=0.5). capinterp=0.05 / 0.5 in-between frames of the dash: lines only while the dash
  runs. DETAILED SHADOWS during ground dashes (60 fps and capinterp=0.5): silhouettes follow the fighter, nothing
  lingers (the streaks under a dashing Goku are his squashed hair spikes). No renderer / shader file changed since
  part 17 (diff of the trees: only qol_*.gd).

## Session 1 part 21 findings (camera zoom: stage object culling) — V = port verified, C = code read
- **Stage script op 0x11** (H, C+V; FUN_0201A794 case 0x11, correction to part 18 "tests the camera y"): `0x11 a b`
  sets the object's visible flag (state +0xA) = camera x (u32 0x020DE3A4 → +0xC) in [a, b], else 0. The interpreter
  runs ONE op per object per frame (state +4 = op pointer, +8 s16 wait counter, op 0x0B wait, 0x0C jump to the start
  (state +0), 0x0D / 0x0E hide / show, 0x12-0x14 x/y/z offsets (state +0x18/+0x1C/+0x20, 20.12) with velocities
  +0x24/+0x28/+0x2C (ops 2-4)). Stage scripts (stg_{id+1}_scr.bin): ids 1 (island: object 2 = Kame house, window
  4536..6584), 3 (6244..8292), 5 (5756..7904), 8 (5336..8084) use `1 2 | 0x11 a b | 0x0C` (window = one stage period
  0x800 cam px), id 11 a 0..16000 window (always), ids 0 / 12 / 14 / 7 animation scripts (ops 3 / 0xB / 0xF / 0xD /
  0xE), the rest none. | H |
- **Repeating props** (H, C): FUN_02019C74, object +0x34 == 0 (else panorama pair, drawn as 3 half pieces): +0x32 == 2
  → x = obj x + state x − S+0x558·0x1000 (absolute, S+0x558 = w·(cam x − width/2) / period); else the copy is chosen
  by iv7 = S+0x548 (= w·(cam x mod period) / period, w = object 0 +0x2C, period = stage record +0xC = 0x800 on the
  wrapping stages): T = w/2 − iv7 if obj x < 1 or (obj x >> 12) ≤ iv7, else −(iv7 + w/2) (units, ×0x1000), so a prop
  is drawn only within half a period of the view and jumps to the other side there; +0x32 == 0 draws a second copy
  (T + w if obj x < 1, else −(iv7 + w/2)). At the game's own views the jump is just off screen (island: at 70 % it
  is exactly at the screen edge). | H |
- **Panorama pairs** (H, C+V): objects with +0x34 != 0 are the two halves (i, i+1, each w/2 = half a period wide) of
  a looping strip; FUN_02019C74 draws 3 half pieces with u = w/2 − iv7: u ≥ 0 → (i+1 at u − w), (i at u), (i+1 at u),
  else (i at u), (i+1 at u), (i at u + w) (object x ignores the state x/y/z and rotations), i.e. the strip
  [L, L + 1.5 w) with L = u − w/2 (u ≥ 0) or u: only ≥ half a period on each side of the view. Stage 10 (ruins):
  objects 0/1 (city skyline); stage 6 (destroyed city): 0/1 (leaning towers) and 2/3 (rubble strip, z 5.2); stage
  14: 0/1. At 70 % the strip ends inside the view (ruins: buildings missing at the screen edges until they pop in;
  destroyed city: the rubble strip ends, water / sky showing below the towers). | H |
- **CAMERA ZOOM culling fix** (port, V; QoLGame `# ---- CAMERA ZOOM`, only while drawing with zoom ratio < 1, flag
  `zoomcull=0` turns it off): f_0201a794 re-evaluates op 0x11 with the window widened by the extra view half-width at
  the object's depth (0.7698·depth·(1/ratio − 1)·period/w ·1.25 + 16 cam px); windowed objects are drawn at the copy
  that continues the one seen at the window centre (state +0x18 moved by whole periods for the draw, `_zm_win_place`)
  and get no extra copies; f_02019c74 runs the stage draw twice more with only the repeating props visible, each
  moved by whole periods onto the two copies the game skipped, plus two more half pieces of each panorama pair on
  each side (drawn through the prop path: +0x34 = 0, +0x32 = 1, state x = slot − T, state y/z/rotation 0; all
  restored after). Level 2 draws nothing extra. Logic state untouched except
  the visible flag of windowed objects (drawing only). Evidence: island, level 0, camera swept 7400 → 3800 by poked
  fighters (/tmp/ssw2/zoom_sweep3.sh): before (zoomcull=0) the house pops in at screen x 26 (port 4650) and its
  wrapped copy pops out at x 25 (5064); after it enters at the left edge (4593) and leaves at the right edge (4998),
  /tmp/ssw2/zoom_house_before_after.png. Ruins / destroyed city, fighters 450 px apart (/tmp/ssw2/zoom_ruins_edges.png,
  zoom_city_edges.png, zoom_ruins_before_after.png): before, buildings / rubble missing at the screen edges; after,
  continuous. Survey (camera swept over > 2 periods by poked fighters, /tmp/ssw2/zoom_survey2.sh, sheets
  /tmp/ssw2/zoom_<run>_<stage>_s.png): all 15 stages at level 1 with the fighters close (sv1) and at level 0 with
  them 400 px apart (sf0, game zoom ~0.55 → 0.39): windowed objects (island house, stage 3 rock, 5 tree, 8 pillar)
  enter / leave at the screen edges, repeating props and panoramas continuous, nothing pops inside the view; the
  stage 7 room vanishing ~1200 frames into the battle is its own script (ops 0x0E / 0x0B 1200 / 0x0D). Window margin:
  max(extra view at the object depth, half the window × (1/ratio − 1) × 1.1) (the window is the object's on-screen
  camera range at 100 %; the depth formula alone was too small for the stage 5 tree). Level 2: 146 captures + 1269
  cheatdbg lines byte-identical to /tmp/ssw2/btn.

## Session 1 part 21 findings (2nd fiddle) — V = port verified, C = code read
- **Mirror palettes** (H, C+V): the battle loader's FUN_0202A094 gives a fighter the second palette of its palette
  file (charadata.arc entry byte 2 of table 0x020D62AC: 512 bytes = normal 0x100 + mirror 0x100) only when it is a
  PLAYER 2 record (+0x1A != 0), its id < 0x1A, and the same id is in player 1's team block at that moment (P1 is
  loaded first): rec+0xFC += 0x100, then FUN_02010B6C(+0xFC, 0x100) → slot u16 rec+0x10A. Player 1 is never
  mirrored. Only the loader reads +0xFC (VM op 8 only picks a 0x20 sub-palette inside the slot). Effect palettes
  (+0x21C, 0x200 bytes) are never mirrored: the second 0x100 of a fighter's effect palette file is zero (Goku).
  Supports (26-36) have no mirror: palette files of 32 bytes (27, 28, 30, 31, 33-36) or 512 bytes with a zero
  second half (26, 29, 32). Face icons (game_faceicon.arc, 0x20 palette) and portraits have one palette.
- **2ND FIDDLE** (WEIRD SETTING, port, V): QoLGame `_fiddle_*` (section `# ---- 2ND FIDDLE (part 21)`): after
  FUN_0202A40C every P1 fighter record gets its mirror palette and every P2 fighter its normal one, uploaded into
  the records' own slots with FUN_02010AE0 (supports skipped); CHARACTER / CHAOS SHUFFLE's `_shuffle_load` gives a
  swapped-in P1 character the mirror palette. V: Goku vs Goku (ice stage, port frame 4600): the two fighters'
  colours swap (P1 red / P2 orange); SSJ Trunks vs SSJ Trunks: P1 red jacket, P2 blue; SSJ Trunks vs Goku: only P1
  changes (red jacket); team Goku + Vegeta + support 26 vs Goku with CHAOS SHUFFLE: members 0 / 1 mirror, support
  normal, every swapped-in character (SSJ Trunks, Majin Vegeta, Vegeta, Metal Cooler …) in its mirror colours;
  setting off: /tmp/ssw2/btn (345 captures, 1674 cheatdbg lines) byte-identical.

## Session 1 part 21 findings (text) — V = port verified, C = code read
- **Only the story / tutorial script text is drawn from strings** (H, C+V). `romdata/scene/script.bin` = named pack
  of `script_<lang>_<char>.bin` (en/fr/ge/it/jp × gok goh crr pic veg trk gtk gnu frz drg egh cel bmr col brl tut;
  LZ-compressed members, header u8 4, u8 8, u16 count…). Text sits inside script opcodes (e.g. op 0x17: u8 op,
  u16 size, u8 flags (bits select register operands via FUN_0203797C), u8 palette, u8, u8, u16 scale (100 = 1x),
  u16, s16 x, s16 y, u16 length, then `length` bytes of text, no terminator); handlers FUN_0203BE7C-family /
  FUN_0203C070 / FUN_0203C150 / FUN_0203C380 copy the text to a heap buffer + NUL and call FUN_0203B708 /
  FUN_0203B7CC / FUN_0203BC70 / FUN_0203BD34, all of which call **FUN_0200B954(out, str, x, y, z=0x78, scale_x,
  scale_y, palette)**. No other code calls FUN_0200B954; `font_eu.bin` is only loaded for story scenes. (H)
- **Encoding** (H, C): ASCII; escapes `\n` (new line: y += scale*12/100 + 1, x back to start), `\'`, `\"`, `\\`,
  `\t` (x += scale*24/100); a byte with (b & 0xE0) == 0xC0 starts a 2-byte glyph code. Raw `'` / `"` bytes draw the
  same glyphs as the escapes. The first pass counts glyphs (spaces included, `\n` not) and stops at 128; an escape
  or 2-byte lead at byte index >= 0x7F calls FUN_020AB3E8 (fatal) → strings must stay < 127 bytes. Space advance =
  scale*6/100; glyph advance = scale*(x1 - x0 - 2)/100 from the **glyph table 0x020CEAEC** (0x13D entries of 12
  bytes {u16 texture slot (index into 0x020DE22C), u16 code, s16 x0, y0, x1, y1}, sorted by code, binary search;
  unknown codes draw '?'). ASCII glyphs are all 6 px except `'` (3 px). One sprite per glyph (FUN_0200B4F4). (H)
- **Text boxes** (V): story dialogue = speaker line + 3 lines at x 10, y 125 (body lines ≤ 234 px in the ROM); the
  A-button icon sits at the box's bottom right; narration on black at x 23..53, y 77. EN strings: 3040, ≤ 128 bytes,
  ≤ 5 lines. (V, from the en scripts)
- **Everything else is images** (H): Mode Select descriptions `modeselect/ModeSelectSubScrExplanationEU.bin`
  (9 × nbfc/nbfp/nbfs per language, 30 members each: z, story, vs, maximum, hatena, free, practice, data, option;
  title + description pre-rendered with the same font, description pixels = colour 7, palette 1), loaded by
  FUN_02075CC4 into a 9 × 0x20 table at *0x020DECEC {+0 palette, +4 chars, +8 map, +0x14 chars size, +0x18 map
  size} (map entries += 0x1000), copied to the top screen's BG1 (engine B, char base 0x8000, map 0x1000) by
  FUN_02075BE8 for the tile under the cursor (FUN_0207401C). Option descriptions `option/OptSubTxtEU.bin` (7
  entries per language, 21 members: timelimit, gamerank, damage, regulation (BACK LIGHT), credit, optmode × 2):
  FUN_020864E0 → table 0x020E14D8 (stride 0x14 {+0 palette, +4 chars, +8 map 0x800, +0xC chars size}); copy
  FUN_020863B4 (entry 6 at start). Language index FUN_02070F28(): 0 English, 1 FR, 2 GE, 3 IT, 4 SP (u8
  0x020DEAB0: 0/1 → 0, 2..5 → 1..4). Character select names, Data File, help, results, VS,
  pause / tutorial menus, map titles and the opening (opening/SCN*.bin) are images too. (H, C)
- **EPIC MODE** (WEIRD SETTING, port, V): QoLGame `# ---- EPIC MODE (part 21)` overrides FUN_0200B954 (rewrites the
  string with QoLEpic (scripts/qol/qol_epic.gd; deterministic, seeded by FNV-1a of the original bytes, cached),
  copies it to port-only RAM 0x027B0000, passes that pointer), FUN_02075CC4 and FUN_020864E0 (after the loaders:
  tile rows 0-6 of each description image kept, the rest redrawn with the ROM font in colour 7 from QoLEpic's own
  MODE_DESC / OPTION_DESC, de-duplicated tiles; chars buffer rewritten in place or replaced by a new heap block).
  English only. Rewriter: speaker line, quoted names, numbers and button words kept; phrase / word swaps (u, ur,
  pwned, n00b, epic, Dragon Ballz…), s→z at word ends (40 %), laughter → Trololo / LOL, emoticons by sentence mood
  (:D B) :'( :O >:( …), ≤ 1 meme line by context (over 9000, waffles, tacos, SPAAACE, Challenge accepted, Like a
  boss, FFFFUUUU-, Y U NO, barrel roll, IMMA FIRIN MAH LAZER, epic win/fail…), templates for "Learned …" / "New
  Character … unlocked"; re-wrapped to max(original width, min(228, 246 - x)) px and the original line count
  (dialogue ≥ 3 body lines, narration +1 below 3), ≤ 126 bytes, falling back level by level (no meme → no extras →
  words only → original). All 3040 EN strings fit (142 unchanged: "...", screams).

## Session 1 part 21 findings (picture effects: BEVEL EMBOSS, TOUCH FUZZY) — V = port verified, C = code read
- **Battle scene detection** (H, V): u8 0x020DD4C4 = scene id (FUN_020010F4 dispatches on it; 0 = the battle scene,
  menus non-zero), u8 0x020DD4C5 = battle state (FUN_020010E4 reads it, FUN_020010D4 writes it). Free Battle run:
  state 1 / 2 = VS screen, 3 = load (white), 4 / 5 = fighters enter, 6 = "READY", 7 = fight, 9 = pause (Start).
  The port treats scene 0 + state 4..9 as "a battle is on screen". Battle input reaches the fighters from ~port frame
  4540 of the btn script (P1 action 0x34 before). (V, port probe `probe=020DD4C4`.)
- **Battle sprite projection** (H, C+V): FUN_02011384 sets G3_OrthoW(top 192, bottom 0, left 0, right 255, near -1024,
  far 1024, scaleW 1.0) (FUN_020A7414(0, 0xC0000, 0, 0xFF000, -0x400000, 0x400000, 0x1000, 1)): every battle sprite
  vertex reaches DSGX with clip w = 1 and clip z = -(sprite +0x3C z) / 1024 (measured: -2..-25 / 1024; fighters 3 / 5,
  face icons 24 / 25). Stage vertices (perspective, near 1.0): w = 40..800 (log2(w)·3 = 16..29) on the ice stage;
  a stage vertex clipped at the near plane has w = 1 but z = -w. So "w == 1 and |z| < 0.5" = sprite / effect / HUD.
- **TOUCH FUZZY** (port WEIRD SETTING, V): DSDisplay `# ---- WEIRD SETTINGS (part 21)` reads QoLGame.cheats
  (QoLSettings) each refresh; strength fades 0 → 1 over 45 frames when the battle is on screen (above), back to 0
  otherwise. Global shader uniform `ds_fx` (registered at runtime) = (time = (game frames − 1 + smooth fraction) /
  59.83 s, strength). Engine A (battle screen) uses ds_engine2d with FX_FUZZY: BG2 / BG3 are sampled at
  centre + (p − centre) / zoom + wave(line) (zoom 1..1.06 pulsing, period 7.6 s; x wave 4.5·sin(0.105 y + 1.9 t) +
  2.5·sin(0.031 y − 1.13 t), y wave 4.5·sin(0.057 y + 1.37 t), whole DS px; the affine sky's x clamped to the screen,
  its map ends just off screen) and the final colour gets a pastel hue (period 6.5 s, drifting diagonally across the
  screen; c·mix(1, hue, 0.24) + 0.11·mix(1, hue, 0.75)). DSRender3D uses ds_poly with FX_FUZZY: perspective vertices
  zoom with the same factor about the screen centre, perspective fragments sample their texture at the warped screen
  position (UV + dFdx(UV)·dx + dFdy(UV)·dy; FRAGCOORD.y = DS line + 0.5 in the 3D viewport). Orthographic quads
  (fighters, effects, HUD, shadows) are untouched. RAM / logic untouched (only shaders): positions, physics, bounds.
- **BEVEL EMBOSS** (port WEIRD SETTING, V): both engine quads (and the 3D renderer, so it draws first) move into a
  256x384 RGBA SubViewport and use ds_engine2d with FX_BEVEL (blend off; alpha = top layer code: 1 + (3 − prio)·5 +
  (3 − bg) for BGs, + 4 for OBJ, +32 when it is the 3D layer, 0 backdrop); DSRender3D adds a 256x192 object-id render
  of the same mesh (material_override = ds_poly with FX_ID: r = depth rank (sprites 32 + z, stage 31 − log2(w)·3),
  g/b = 12-bit hash of TEXIMAGE address / size / palette; rear plane (UV2.y = 1) and pixels with alpha < 0.6 skipped).
  shaders/ds_fx_bevel.gdshader (a rect in DSDisplay) lights every shape: a pixel within 3 DS px of a different shape
  that is behind it (or level) gets highlight (screen-white 0.75) / shadow (multiply-black 0.62) by the direction to
  that outline against a light from 120° (top left), smoothstep fall-off; thin strokes (outline on both sides) stay
  flat → small text stays legible; plus a luminance emboss (diagonal difference × 0.44). The stage's depth rank varies
  per pixel, so it only orders shapes (using it to separate them drew a line at every rank step across the floor).
  The port's own QoL menu / top info / FPS counter / markers are drawn after DSDisplay and stay flat (the game's
  menus, including the Mode Select background behind the QoL menu, are bevelled). Captures show the effect (the pass
  is in DSDisplay, not the presenter). Debug: `fxdump` writes fxa<F>.png (picture + codes) / fxi<F>.png (3D ids) next
  to the captures, `fxdbg` prints sprite z / stage w classes.
- **Off = unchanged** (V): with both settings off no variant shader, viewport or uniform update exists (the `#ifdef`
  blocks compile away; the only data change is UV2.y = 1 on the rear-plane quad, unread by the plain shader): intro
  capture vs /tmp/ssw2/intro 221/221 frames 0 px, Mode Select barcheck 0 of 122, btn battle 345/345 captures 0 px +
  1674 CHT lines identical to /tmp/ssw2/btn. TOUCH FUZZY on outside battles: intro + Mode Select (frames 10-2560)
  0 px vs the off captures.
- **Evidence (on)** (V, Free Battle Goku vs Goku, ice stage, scripts /tmp/ssw2/fx_run.sh with FXIN inputs): sheets
  /tmp/ssw2/fx_sheet_bevel.png (Mode Select off/on, character select, battle off/on), fx_sheet_fuzzy.png (ki blasts,
  dash, combo; lower row zoom=0 + capinterp=0.5), fx_sheet_both_super.png (both on, R charge + X+A super 0x2C/0x2D).
  Fighters / effects / HUD keep their shape and position under the wave; no void at the screen edges at zoom 0
  and 2; the stage ground waves under the fighters (accepted, as in Yoshi's Island).

## Session 1 part 22 findings (picture effects: battle signal, GAME BOY, MIRROR MODE) — V = port verified, C = code read
- **Scene table** (H, C): FUN_020010F4 calls table 0x020B6278[scene byte 0x020DD4C4] (0x17 entries): 0 = FUN_02013064
  (the battle), 1 FUN_0203E87C (story dialogue), 3 FUN_0206DCE8 (character select), 5 FUN_02071B68 (stage select),
  6 FUN_02073F40 (Mode Select), 7 FUN_02079430 (calls FUN_02013064), 0xC FUN_020567E0 (Practice course select), 0x13
  FUN_0202FDB8 (Practice: wraps FUN_02013064), 0x14 FUN_0209DED8 (Game Over / Continue). FUN_02001014(scene) = scene
  change: sets the scene byte, zeroes state byte +1 / u16 +2 and VBlank IRQ handler 1 = default 0x02000FD0.
- **Battle on screen, every mode** (H, C+V): FUN_02013064 installs the VBlank handler FUN_02013030 (OS_SetIrqFunction
  FUN_020A8F70(1, …) → OS IRQ table DTCM 0x027E0004) during its load; battle states (u8 0x020DD4C5, FUN_020010D4 /
  FUN_020010E4): 1-2 VS screen, 3 load, 4-6 fighters enter / READY, 7 fight, 8 and 0xA-0xE events inside the fight (from
  [globals +0x1BCAA] 1-3 / 5-9; they return to 7), 9 pause, 0xF time up (FUN_020163F0), 0x10 / 0x11 end sequences
  (FUN_02015DA8 / FUN_0201825C, KO / win), 0x12 fade out → 0x13 / 0x14 (quit) wait → scene change. Port signal
  (DSDisplay.battle_on_screen()): handler == 0x02013030 and state >= 4. Probes (u32 0x027E0004, u32 0x020DD4C4):
  Free Battle scene 0, Practice scene 0x13 (states 4-7 with handler 0x02013030; the part-21 test "scene 0" missed it),
  Story scene 1 dialogue (handler 0x0203E84C) → scene 0 battle, Z-Battle scene 0 incl. state 0xB (event) and 0x11
  (KO) → 0x13 → scene 0x14 Game Over (handler 0x02000FD0, 0x0209DC48), Maximum scene 0 (states 2-7).
- **Captures** (V; /tmp/ssw2/fx22_mode.sh = menu navigation + A presses): TOUCH FUZZY + MIRROR in Practice
  (/tmp/ssw2/fx22_sheet_prac.png), Story (fx22_sheet_story.png: dialogue and VS screen untouched, battle on), Z-Battle
  (fx22_sheet_zb2.png: on through the KO sequence, off at Game Over), BEVEL + MIRROR in Maximum (fx22_sheet_max.png),
  GAME BOY + MIRROR in Z-Battle (fx22_sheet_zb.png), bevel + fuzzy + mirror with zoom=0 and capinterp=0.5 in Free
  Battle (fx22_sheet_combo.png: bevel ids follow the flip, light stays top left), GAME BOY on Mode Select / QoL menu
  (fx22_sheet_gbmenu.png).
- **GAME BOY** (port WEIRD SETTING, V): DSDisplay adds a CanvasLayer (layer 64, above the QoL menu, top info, FPS
  counter, markers) with a 256x384 rect running shaders/ds_fx_gameboy.gdshader on the screen texture: luminance →
  #0F380F / #306230 / #8BAC0F / #9BBC0F with a 4x4 Bayer dither (0.35 step); a pixel whose 8-neighbour has a clearly
  different colour (distance > 0.42) but the same shade drops one shade if it is the darker one (rises at shade 0):
  the QoL menu's selected values (red on olive chips) and the battle "Touch!" button stay readable. Off: no layer.
- **MIRROR MODE** (port WEIRD SETTING, V): while battle_on_screen(), the top screen's engine quad gets scale x = -1
  (position x 256): the battle picture incl. HUD is flipped, the bottom (touch) screen never. `DSDisplay.mirror_active()`
  (setting on and battle on screen; reads RAM, callable any time) is for the input swap in GameDS. The bevel pass reads
  3D ids at 255 − x when engine A is flipped (`a_flip`).
- **BEVEL EMBOSS + fades** (V, fix): the bevel used to be added to the already faded picture, so on a black (or
  white) screen the outlines stayed visible (QA: /tmp/ssw2/qa_opt p2700 / p3060, qa_vs p2640 / p3120). With FX_BEVEL
  the engine shader now leaves out MASTER_BRIGHT (0x6C) and the BLDCNT mode 2 / 3 brightness effect (it marks those
  pixels with alpha bit 6); ds_fx_bevel.gdshader applies both per line (registers of the engine on each screen,
  `regs_top` / `regs_bot`) after the bevel, so the bevel fades with the picture. Free Battle menu path with bevel
  (/tmp/ssw2/fx_22fade, every 4 frames 2400-3800): black frames 0/0 (before: max 191), fade to white reaches 255
  everywhere at 3688, fade-in from black (3704-3736) scales the bevel; before / after sheet
  /tmp/ssw2/fx22_fade_before_after.png (top = before, bottom = after: half to black 2460, black 2700, to white 3660,
  from black 3720). Bevel + fuzzy + mirror battle with capinterp 0.5 unchanged (fx22_sheet_combo2.png).
- **Off = unchanged** (V): intro 221/221 0 px vs /tmp/ssw2/intro, barcheck 0 of 122, btn 345/345 0 px + CHT lines
  identical to /tmp/ssw2/btn (rechecked after the fade fix: the plain shader's brightness code was only regrouped).

## Session 1 part 22 findings (blood, afterimages) — V = port verified, C = code read
- **Hit damage entry** (H, C+V): FUN_020293A4(record, damage, type) runs once per damaging hit on any fighter
  record (active fighters, supports, ASSIST SPAM copies); `blooddbg` lines show dash attack 1080, ki blast 432,
  melee 198, CPU combo finisher 2000. The guard bit is record +0x250 bit 0 (as used by ONE HIT KO).
- **Feet line** (M, V): a standing fighter's world y + f (u8 0x020CFCA8[id]) = ground (u16 *(*(0x0201B49C)) + 0xCC2)
  + 64, i.e. the floor is ground + 64 world px for every character (Goku: 8224 + 32 = 8192 + 64).
- **World → screen** (H, C): sprites are placed by FUN_02019328 at camera +0x30 + zoom × (x − camera +0xC) / 256
  (y: +0x34, +0x10; camera = *(0x020DE3A4), zoom u16 +6); inside FUN_02012D70 CAMERA ZOOM's scaled zoom is in +6.
- **BLOOD / AFTERIMAGES** (port WEIRD settings, V): QoLGame `# ---- BLOOD / AFTERIMAGES (part 22)`; hooks: one line in
  f_020293a4 (`_blood_hit`, only when blood is on), `_fx_upd = true` in f_0202954c (a battle frame ran: the
  simulation steps once per battle frame, so pauses freeze it), and the f_02011384 override (drawing after the
  sprite list, like DETAILED SHADOWS; `_spr_emit` = the shared textured-quad emitter). Blood: 4-12 droplets by damage
  (guarded hits a quarter), 1-3 px untextured quads in #6b0000 / #c00000 / #ff4040, thrown from the victim's upper
  body away from the other team's active fighter, gravity 0.22 px/frame², land on the floor plane at a random depth
  (−2..+12 px, so most land in front of the ground shadow), splat 1 px high and fade; pool of 64 sent whole while any
  droplet lives (dead slots at −4000 px) so slots keep their polygon numbers for smooth motion. Afterimages: speed
  >= 5 world px / frame (dash, knockback, teleport; < 200 px) keeps 3 copies of the current sprite quad at the
  positions 2 / 4 / 6 frames back for 12 frames, translucent (alpha 16 / 11 / 6 of 31, fading), modulated light
  blue (24, 28, 31), z 2 (behind both fighters), one polygon ID per fighter (copies never overdraw each other).
  Off: byte-identical to the pre-change Free Battle captures (21/21 frames 4600-4700). Images: blood_g2.png,
  blood_z3.png, blood_z6.png (zoom level 0), blood_z1.png (afterimages), blood_z5.png (capinterp 0.5) in /tmp/ssw2.

## Session 1 part 22 findings (mode select tile) — V = port verified, C = code read
- **Mode Select's lower screen is engine A** (V): POWCNT1 0x020F (bit 15 = 0: engine A on the lower screen).
  DISPCNT_A 0x00010308: BG0 = 3D, BG1 = the scrolling hexagon background (char base 1, map 0, prio 1), BLDCNT 0x0241.
  The nine tiles and the bottom "MODE SELECT" bar are 3D quads on BG0 (not BG character data). VRAMCNT at Mode
  Select: A 0x83 (texture slot 0), B 0x8B (texture slot 1), D 0x81 (A BG), G 0x83 (texture palette slot 0),
  C 0x84 / H 0x82 (engine B, top screen).
- **Tile textures** (V): texture slot 0 (bank A) holds one 128x64 4-bit texture per tile, tile k (row-major,
  same numbering as the cursor u8 0x020DEC20) at offset k * 0x1000; the picture is the top-left 80x44 texels
  (quad uv 0..80 x 0..44, TEXIMAGE_PARAM 0x6DCF0000 + offset/8: 128x64, format 3 = 16 colours, colour 0
  transparent, repeat/flip set, texcoord mode 1). Slot 9/10 = the "MODE SELECT" bar (drawn twice, the second
  copy alpha 10/31), slot 11 = the cursor frame drawn over the selected tile (the highlight; it blinks white /
  yellow, the tile's own texture and palette never change), slots 12+ = other screens' data. The centre
  (Dragon Ball) tile = offset 0x4000, used only by that quad. All tiles use texture palette 0 (bank G +0):
  1 0x318C grey, 2 0x0000 black, 3 0x7FFF white, 4 0x00A7, 5 0x1CE7 grey, 6 0x010A, 7 0x016E, 8 0x018F,
  9 0x39CE grey, 10 0x01F3, 11 0x0257, 12 0x029A, 13 0x02FD, 14 0x5EF7 grey, 15 0x033F (gold ramp + label greys).
  Palette 0 is constant while Mode Select runs (no palette animation).
- **Load timing** (V, btndbg trace): the scene slot u32 0x020DE374 becomes 0x020738E0 in the same frame the
  textures are (re)loaded (texture slot 0 unmapped the frame before: f2457 → f2458 first entry, f2861 → f2862
  re-entry from the title, f3180 → f3183 back from the Z-BATTLE sub-scene 0x02065E60). The screen fades in with
  MASTER_BRIGHT_A 0x8010 → 0x8001 over 15 frames and stays at 0x8001 (1/16 darker) while the player chooses;
  fade-out 0x8001 → 0x8010 after B (slot back to 0 ~60 frames later) or after A (sub-scene loads new textures).
- **Port: QoLButton** (`scripts/qol/qol_button.gd`, hook `button.frame(core, game.frames)` in
  `QoLController.after_step`): while 0x020DE374 == 0x020738E0 and texture slot 0 / palette slot 0 are each mapped to
  one bank, whenever that bank was written or VRAM remapped it compares texels 0x4000 (44 rows x 40 bytes, row
  stride 64) with `assets_qol/port_button.png` (the user's own art, lossless import) quantized to palette 0
  (nearest CIELAB colour against the palette as shown at 15/16 brightness; alpha < 0.5 → 0) and rewrites them if
  they differ (bank_gen++ so the renderer re-uploads). Colour mapping (all exact on screen except white):
  (239,190,0)→15, (199,154,0)→12, (146,117,0)→10, (117,93,0)→8, (77,60,0)→6, (56,40,0)→4, black→2,
  (56,56,56)→5, (109,109,109)→9, (178,178,178)→14, white (255,255,255)→3 (0x7FFF, shown as 239 like every other
  tile's label text). Indices 1, 7, 11, 13 unused. Debug: `btndbg` (trace + mapping), `nobutton` (original tile).
- **Verification** (V): captures every 2 frames 2300-3400 (entry fade-in, cursor elsewhere, cursor on the centre
  with the blinking frame, QoL menu open/close, cursor moved away, B to the title + fade-out, re-entry, A →
  Z-BATTLE sub-scene, B back): pixel diff vs a `nobutton` run = 0 outside x 87..168 / y 63..108 of the lower
  screen in all 554 frames; inside, only Mode Select frames differ; title and sub-scene frames identical.
  Images in /tmp/ssw2/btn22_work (crops_0.png, crops_1.png, full_on.png).

## Session 1 part 22 findings (QA: menu options bug hunt) — V = port verified, C = code read
- **Mode Select tile 4 = scene 2 (the boot sequence)** (C + V): FUN_02073AAC (Mode Select loop) leaves with result 1
  on a new A press (FUN_02001230(1)) unless the selection is 3 (MAXIMUM) and MAXIMUM is locked (FUN_020735B8 == 0:
  SE 0xD buzzer). The selection is the s16 at 0x020DEC10 + 0x10 = 0x020DEC20 (literal pools 0x02074028 and
  0x020757D4 both = 0x020DEC10), i.e. the cursor. FUN_02075738 maps it to the next scene: 0→4, 1→1, 2→0x11, 3→4,
  4→2, 5→3, 6→0xC, 7→8, 8→9. Tile 4 (the Dragon Ball tile the port uses for its menu) goes to scene 2 = the
  Bandai / Cavia logos and the opening (port: the QoL layer wrote cursor 4 and the game saw A in the same frame →
  logos at f2660, captures /tmp/ssw2/qa_lr). The part-11 note "A on it does nothing" was a later-frame test (M:
  that case was not re-checked in melonDS; in the port the QoL layer always takes A on tile 4 for its menu).
  Port fix: QoLController.filter_input keeps every key pressed in the frame the cursor is moved onto the tile /
  the menu is opened from the game (the A that came with Right / a tap no longer reaches the game).
- **Watchdog vs a frozen PC** (V): DSMachine.step() stopped the game ("game thread busy for 10000 ms") when the
  wall clock jumped while the whole process was frozen (SIGSTOP 12 s = PC asleep / suspended; also two capture runs
  stopped at the same second when a third Godot instance started on this 2-CPU machine). It now counts the time
  between polls capped at 100 ms per poll, so only time the game thread really had counts.
- **settings.cfg typing** (V): ConfigFile values of the wrong type (a quoted "true", a list) made `bool()` fail with
  "Nonexistent 'bool' constructor" and stopped QoLSettings.load_file half way (later settings at defaults, then saved
  over). QoLSettings._val converts / falls back to the default per key. Garbage, truncated, empty and part-11
  (old, display + sound only) files load cleanly (defaults for the rest).
- **Godot input map changes while a key is held** (V): remapping Y's key to X while X (then A's key) is held, then
  releasing it, leaves no action stuck (the menu reacts to the next press; A's new key C works at once).

## Session 1 part 23 findings (text: Data File, credits) — V = port verified, C = code read
- **Resource pack loader FUN_02009B28(buf, member, pack)** (H, C+V): pack handles 0..31 in a table at *0x020DE214,
  0x88 bytes each (+0 ROM path string as opened by FUN_0200A648(path, mode), +0x7C mode, +0x7D flags, +0x7E member
  count, +0x80 data offset, +0x84 -> directory of 0x10-byte entries {+0 unpacked size, +4 stored size, +8 offset,
  +0xC cached copy}); FUN_02009DB8(member, pack) = unpacked size. Reads the member, decompresses it (BIOS RLE /
  LZ10 ...) into buf. Every Data File / help / credits picture goes through it. (H)
- **Data File** (H, C+V): FUN_02081160 (mode start) opens ModeSelectMainScrBG.bin, TeamIcon.bin, HelpEU.bin and keeps
  DataModeDataImage_<lang>.bin open (handle u8 0x020E1154); help textures (HelpEU, 8 members per language: arts /
  sp / teamarts / sup, palette + texture) into 0x020E11B0 +8/+0xC, +0x18/+0x1C, +0x28/+0x2C and 0x020E1188 +8/+0xC.
  Help textures: 256x256 **A3I5** (low 5 bits colour, high 3 bits alpha; text = alpha 7, colour 1 (5 in arts_help),
  background alpha 5 (4 in teamarts) colour 0), text = the game's font_eu glyphs, 6 px per letter, lines 14 px.
  Character pages: FUN_02080200 loads per character (first member index table u16 0x020D0B1C) name (+1, 0x1000),
  ability (+2, 0x8000 buffer), second ability, team attacks into 0x020E11EC; the move strips (ex1..4) the same way.
  Pack members (EN): data_<chr>_ex1..4 (256x64 4bpp: name white 15 on black 1 at x 38, y 12; input line black 1 on
  yellow 13 / orange 11 at y 27 followed by the button icons), _sp1/_sp2 (256x128: name + description lines x 41,
  15 px apart; support pages hold two entries), _team1..5 (256x32, black on yellow, x 27), _name (256x32, bold
  anti-aliased grey ramp 2..15 on 1), _face. Section tabs (ARTS, ULTIMATE ATTACKS, SPECIAL ABILITIES, TEAMARTS,
  SUPPORT, SPECIAL) = tiny capitals colour 9. The page font is proportional (not font_eu: 'w', 'a', 'r' differ),
  1-2 px letter gaps, 4-7 px word gaps. Touch-screen items DataSubScrEU.bin (df00US / df01US / df02US / df03US:
  nbfc/nbfp/nbfs, LZ10) = small font line "Select an item to display info." + big-font item labels. (H)
- **Staff credits** (H, C+V): FUN_02087678 loads CreditRollEU.bin roll_1..10, 13 (nbfc + nbfp + nbfs, LZ10, 256x512
  maps) into the table *0x020E1570 (11 x 0x14: +0 palette, +4 chars, +8 map, +0xC chars size, +0x10 map size; odd
  entries' maps += 0x1000), FUN_020871E4 uploads entry i to BG1 (even: chars VRAM 0xC000, map 0x1000) or BG2 (odd:
  chars 0x14000, map 0x2000), both 256x512 (BG1CNT 0xA20C, BG2CNT 0x8414, FUN_02088118) -> up to 1024 tiles each.
  Text: font_eu-style monospace (6 px) but its own 'r', 'C', '#' shapes; white 15 = names / team titles, yellow
  13 = roles and cast characters (right-aligned at x 122, actors left-aligned at x 133), red = companies. (H)
- **EPIC MODE pictures** (port, V): QoLGame overrides FUN_02009B28; after the load QoLEpicImg (scripts/qol/
  qol_epic_img.gd) reads the text in the picture (connected glyph pieces of one colour whose frame is one other
  colour, grouped in lines and glyphs; each glyph matched exactly against reference glyphs cut at run time out of
  the ROM at the coordinates in QoLEpicRefs - DF_REFS 112, CR_REFS 123, SUB_* 33, TINY_REFS 32 shapes), rewrites it
  (QoLEpic.picture_text / credit_text / SUB_TEXT / TAB_TEXT, hand-written HELP_TEXT for the 4 help panels) and
  draws it back with the same glyphs (font_eu glyphs for missing letters) in the original colours / baselines /
  letter gaps, within the free space of its box (move names up to the cost box, input lines push the button icons
  left, descriptions re-wrapped to the box with one more line when the slot below is empty). BG pictures (credits,
  touch-screen items) are re-encoded (tiles de-duplicated with flips, palette bits kept); credits pictures that
  grow get a new heap block (pointer / size in the credits table). Offline check of all 278 EN Data File members:
  367 texts rewritten, 0 kept; credits: 229 lines in 10 rolls (515-589 tiles of 1024). English only.
  V in game (weird=epic): Data File Goku / Piccolo pages, help panels, touch-screen items; Option -> Credit roll
  (frames 3100-7000); setting off: /tmp/ssw2/btn (345 captures, 1674 CHT lines) byte-identical. Not changed: the
  bold CANCEL / EXIT buttons, character portraits, the BANDAI logo; a credits line whose glyphs are not all known
  ("MAM Project manager") stays as it is.

## Session 1 part 23 findings (blood scaling, flashy ki, KO confetti) — V = port verified, C = code read
- **Effect handlers seen per kind** (V, `flashydbg`, Free Battle Goku vs Goku): R charge (action 0x0D) = kind 5 (54x27
  quad, alpha 12, z 9, centred 23 px above the fighter) + kind 6 (142x146 → 108x112, alpha 22 → 18, z 7), both
  handler 0x02020A84 (generic animated effect), flag 8, +0x1B 0x0D; ki blasts kind 2 / 24 / 27 handler 0x020209E0
  (z 7; kind 24 is a 288x16 quad); beam origin kind 9 0x02020560 (+0x1B 0x2D), head kind 16 0x02020330; kind 25
  handler 0x0201F750 (80x16) and kind 15 0x02020674 (56x56) also appear during supers; dust kind 4 (16x16, 24 px
  below the owner). Beam parts are owned by other objects, not by the fighter. Goku's beam super hits as a stream
  of 120-damage ticks (one FUN_020293A4 call every 1-4 frames); ki blast 432 (108 guarded), dash attack 1080,
  melee 198.
- **Effect object +4 during slow motion** (V): in the KO slow motion the battle updates every 4th frame; on the
  frames in between the effect objects' u8 +4 reads 5 (1 | 4) instead of 1, so "alive" must be tested as
  (+4 & 3) != 0 (as FUN_02021F54 does), not == 1.
- **BLOOD scaling** (V): droplets = clamp(2 + d / 100, 2, 30) with d = damage clamped to 3000 (so ONE HIT KO /
  HARD MODE / boss damage can never exceed 30 per hit); guarded 1-3; more 2-3 px drops and up to 2.6x speed /
  spread as d grows; pool 160 (oldest reused when full), only the slots used since the pool was last empty are
  sent. Seen: 198 → 3, 432 → 6, 1080 → 12, 2000 → 22.
- **FLASHY KI / KO CONFETTI** (port WEIRD settings, V): QoLGame `# ---- FLASHY KI / KO CONFETTI (part 23)`, drawn by
  the part-22 `_fx_draw` path (no new hooks; drawing only). Flashy: blasts (handler 0x020209E0) get a x1.8 halo
  copy (alpha 14/31) + a 3-copy shrinking trail; beam parts (0x02020330 / 0x020203CC / 0x02020560) a pulsing
  x1.6 glow copy (body: thicker only); auras (object owned by a fighter, within 16 / 40 px of its centre, quad >= 48
  px, made in or owner in action 0x0C / 0x0D / 0x29 or owner +0x261 powered up) two pulsing copies x1.4 / x1.2
  behind the fighters; charging fighters (0x0D) throw rising white / yellow / blue sparkles (twinkle crosses).
  Confetti: a fighter record's HP (+0x24A) reaching 0 → 64 pieces (2-3 px, 7 colours, turning 3x2 / 2x3 / 2x2 / 2x1),
  upward burst, drag + sway, slow fall, lie on the floor plane, fade at ~2 s. Off: byte-identical to the btn
  baseline (21/21). Images in /tmp/ssw2: fx23_onoff.png (off vs on), fx23_z1.png (aura + sparkles), fx23_g3.png /
  fx23_g4.png / fx23_z2.png (ONE HIT KO confetti, default zoom and zoom level 0), fx23_g2.png (blast halo, beam).

## Session 1 part 23 findings (SCREEN SHAKE) — V = port verified, C = code read
- **Hit damage values** (V, Free Battle Goku vs Goku, FUN_020293A4 argument 2, `fxdbg` SHAKE lines): ki blast /
  single punch 198, combo finisher 297, X+A super (Kamehameha) one hit of 1080, a P2 heavy hit 2000, a beam that
  touches every frame 120 per frame.
- **SCREEN SHAKE** (port WEIRD SETTING, V): QoLGame f_020293A4 records the biggest damage (`shake_dmg`, section
  `# ---- SCREEN SHAKE (part 23)`, before the cheats change it); DSDisplay reads and clears it each refresh. While the
  setting is on and battle_on_screen() with engine A on top, engine A uses the FX_SHAKE shader variant: the picture
  (stage, fighters, HUD) is sampled moved by `fx_shake` whole DS px, edge rows / columns repeated (nothing spills
  onto the bottom screen, no black gap). Amplitude 6·(damage / 2000)^0.75 px clamped 1..6 (198 → 1.1, 297 → 1.4,
  1080 → 3.8, 2000 → 6), length 8 + amplitude game frames, envelope (1 − t/len)², x = A·e·cos(2.83 t) (flips side
  almost every frame), y = 0.6·A·e·sin(2.2 t + 1); a new hit replaces a running shake only when at least as strong as
  what is left; time = game frames + the smooth-motion fraction. The bevel pass shifts its 3D id lookup by the same
  offset (`a_shift`, also under MIRROR). Measured HUD offsets (/tmp/ssw2/fx_tools/shakemeas.py on /tmp/ssw2/fx_23shake,
  every frame): 198-damage hits (1, 1) (−1, 0) (1, 0) then still; the 1080 super hit (4, 2) (−3, 0) (2, −1) (−1, 1)
  (1, 0) (0, 1) then still. Sheet /tmp/ssw2/fx23_sheet_shake.png (top row a punch, bottom row the super).
  With bevel + mirror + capinterp 0.5 (/tmp/ssw2/fx_23shakeB, sheet fx23_sheet_shake_combo.png): offsets mirrored and
  in between ((−1, 2) (1, −2) (−2, 0) (2, 1) …), bevel outlines stay on their shapes. Off: intro 221/221 0 px, btn
  345/345 0 px + 1674 CHT lines identical.

## Session 1 part 23 findings (leaderboard) — V = port verified, C = code read
- **Save copy in RAM** (H, C+V): FUN_02004CD8 loads the chosen 0x1F4-byte save block into 0x020DD5B4 (FUN_020024B0):
  +0 "DBZ2", +4 u32 time stamp (FUN_02002CA4 = RTC seconds since 2000), +8 u16 CRC of +0x10..+0x1F4, +0xA MAC; data
  from +0x10 (0x020DD5C4): +0x10 **HI-SCORE RANKING** (below), +0x74 Story progress (15 x 0x18, 0x020DD628), +0x1DC..
  (FUN_0203FC40 defaults), +0x1E4 u8[3] Maximum progress per course table a/b/c (stages cleared, max 0x14; setter
  FUN_02002484 from FUN_020507AC, which also ORs unlock bits FUN_0200222C and saves), +0x1E7, +0x1E8 u16 (default 0x22),
  +0x1EC/+0x1F0 unlock bits (0x020DD7A0 / 0x020DD7A4).
- **HI-SCORE RANKING** (H, C+V): 5 entries x 0x14 at 0x020DD5C4 (save block +0x10..+0x74), best first: s32 ids[3]
  (38 = empty), u32 score, u32 difficulty (0 Easy, 1 Normal). The only leaderboard in the game (Maximum / Story are
  progress with unlocks, not rankings; the Data File has no records). Insert = **FUN_02002560(score, ids, difficulty)**
  -> rank 1..5 or 0 (shifts the lower entries down; `entry.score < score` unsigned). Only caller FUN_0208B9B8 (Z-Battle
  results, state 1 of FUN_0208B578, after every won Z-Battle fight): score = [0x020DD564+0x44] + u16 +0x48..+0x4E,
  ids = 0x020DD564 (P1 party), difficulty FUN_0200228C; the rank goes to work +0x25BE (> 5 -> 0) and makes that row of
  the ranking screen blink. V: a 30000 win against a table whose 5th is 1000 -> rank 5, 5th row "30000 Goku" blinking.
- **Defaults** (H, C+V): the save formatters FUN_02004EFC(block) / FUN_02005378 (all blocks) / FUN_0200580C (RAM image)
  copy the default ranking from **0x020B6888** (ARM9 data): (Goku 0, 6, 24) 100000 Normal, (24, 5, 4) 90000, (6, 22)
  80000, (0, 5) 70000, (23) 60000, all Normal. No separate "reset ranking" routine exists.
- **Saving** (H, C+V): the game's sequence (e.g. FUN_0208690C) is FUN_02005D24(0xD01) open (allocates, sets s8
  0x020DD7A8 = -1), FUN_02004D8C write (checks, header + CRC, writes the RAM copy to the next block in rotation via
  FUN_02004B08; returns 1 when the save is not open), FUN_02005914 close. Loader FUN_020046A4: the block with the
  largest +4 stamp (first one on ties) is loaded; if the clock is behind that stamp, every block is rewritten with
  the loaded one (frozen-clock test runs: all 16 blocks get stamp 800280000 at boot, and two saves in the same second
  tie). Mode Select runs with the save closed (FUN_02004D8C alone returned 1 there).
- **Port (QoLGame `# ---- LEADERBOARD (part 23)`)** (V): f_02002560 returns 0 without touching the table while
  QoLSettings.cheats_on() > 0 (cheats only), so the game takes the "not ranked" path (old table shown, no blinking
  row). `reset_leaderboards()` copies 0x020B6888 over 0x020DD5C4 (0x64 bytes) and saves with the game's own open /
  FUN_02004D8C / close (only write if the save is already open). Evidence (seed = 100% save with 5th place = 1000,
  CRC fixed; inputs /tmp/ssw2/qa_s/zb3.in + P2 HP clamped to 1; scripts /tmp/ssw2/score_run.sh,
  score_tools/sav.py): no cheats -> "score 30000 -> rank 5" (/tmp/ssw2/score_off4/p5240-5420); cheats=infinite_assists
  -> "not entered: 1 cheat(s) on", table unchanged (score_on4/p5400, side by side /tmp/ssw2/score_t/offon4.png).
  Reset at Mode Select (lbreset=2350, clock running): save result 0, DBZ_SSW2_Port.sav changed only in block 1
  (+4 stamp, +8 CRC, +0x10..+0x74 ranking = defaults); the next boot loads it and the Z-Battle ranking screen shows
  the default table (/tmp/ssw2/score_rst5/p5400.png). Off: /tmp/ssw2/btn 345/345 PNGs + 1674 CHT lines identical.

## Session 1 part 24 findings (gamepad cursor) — V = port verified, C = code read
- **Touch input path** (port, V): GameDS._tick builds one touch per emulated frame (mouse over the lower screen or a
  scripted `T<x>/<y>`) → QoLController.filter_input (Mode Select PORT tile / settings menu taps: only the first
  frame of a touch counts as a tap, `new_touch`) → `arm7.set_touch(pressed, x, y)` (TSC emulation). The gamepad
  cursor feeds the same Vector2i in front of filter_input (`qol.cursor_touch()`, used only when the mouse does not
  touch; scripted taps still win), so everything the touch screen does works with it, including the QoL menu.
- **Input map** (port, V): project.godot has no ds_* action on the right stick (axes 2 / 3) or R3 (button 8), so the
  cursor defaults (QoLControls.CURSOR_DEFAULTS: qol_cur_up/down/left/right = "a:3:-1" / "a:3:1" / "a:2:-1" / "a:2:1",
  qol_cur_click = "b:8", key slots empty) clash with nothing. They are ordinary QoLControls actions: saved in
  settings.cfg [controls] (`qol_cur_*_key/_pad`, plus `cursor_enabled`, `cursor_speed` 1..5), applied to the InputMap
  by QoLControls.apply, part of the swap in `assign` (a key taken from a DS button for an empty cursor key slot leaves
  that button without a key: the menu notice says "(A: no key now)"), reset by DEFAULT (also ON + speed 3).
- **QoLCursor** (scripts/qol/qol_cursor.gd, V): child of `screen_root` (the 256x384 SubViewport, or the root in
  captures), z_index 1000, drawn last; an 11x15 hand-drawn arrow (cream-white body, orange shade, dark outline,
  soft shadow; pressed: orange body, 1 px "in", three white tap rays). Shown while the cursor is ON, the touch screen
  is in use and `Input.get_connected_joypads()` is not empty (captures: only with `fakepad` / `vcursor`). Movement:
  radial deadzone 0.2 on the action raw strengths, speed 60/100/150/220/300 DS px/s at full deflection (SPEED 1-5)
  × (0.35m + 0.65m²) × ramp 60 %→100 % over 0.5 s of continuous movement; position clamped to 0..255 × 0..191, kept
  sub-pixel, drawn at whole pixels. Real time: moved in `_process(delta)`; captures: one game frame (1/59.83 s) per
  tick, so scripted runs are frame-exact. Hidden after 4 s without movement / click and on real mouse motion / click
  (the next stick move shows it; after mouse use the first click only shows it). Click presses are latched from
  `_input` so taps shorter than a game frame count. While CONTROLS waits for a new input the cursor neither moves
  nor touches (mapping the right stick does not move it, R3 does not cancel the capture).
- **Scripted K-key timing** (port, V): `inputs=F:Kkey:N` key events go through Input.parse_input_event, which is
  buffered until the next main-loop iteration; in captures several physics ticks can run per iteration, so a short
  scripted key press/release may be seen by `Input.is_action_pressed` for fewer frames than N (the cursor's event
  latch still catches the press). The frame-exact cursor test path is `vcurmove` / `vcurclick`.
- **Tests** (V): Mode Select → stick right/back → click on the PORT tile opens the settings menu → clicks on the
  page arrow, CONTROLS SET, CONTROLS page arrow (page 3), CURSOR OFF (cursor gone) (/tmp/ssw2/cur_click); key slots
  from a qolcfg + `inputs=F:Kl:N` move it (/tmp/ssw2/cur_keys); real-time run through the presenter: drawn, OPTION
  tile selected by a click, hidden 4 s later (/tmp/ssw2/cur_rt); no gamepad: intro 221/221 and the off23 battle
  (21 PNGs + CHT lines to 5300) identical.

## Session 1 part 24 findings (weird 3: damage numbers, rainbow ki, jelly fighters) — V = port verified, C = code read
- **Sprite drawer per sprite** (H, C+V): FUN_02011384 sets DIF_AMB 0x4210FFFF once (bit 15: vertex colour = white for
  the whole list; it never writes COLOR), then for each list entry that is drawn (+0x3D != 0, +0x3B > 7, +0 != 0):
  MTX_PUSH, MTX_TRANS(+0x1C, +0x1E, z = u8 +0x3C), FUN_020A71C8(sin, cos) (= MTX_MULT_3x3 rotation about z; angle
  table 0x020D0F5C[+0x38 >> 4]), MTX_SCALE(w, h × list +0x184 >> 8 unless +0x3E bit 3), texture matrix, TEXIMAGE_PARAM,
  PLTT_BASE, POLYGON_ATTR 0x8080 | (0x20 − a) << 24 | a << 16 with a = +0x3B >> 3 (game sprite polygon IDs 1-31),
  BEGIN quads, 4 × (TEXCOORD, VTX_16), END, MTX_POP. Its loop index lives in its stack frame (112 bytes) at +4, so
  inside FUN_020A71C8 the current sprite is list[u32 (_sp − 112 + 4)] (V: tint lands on the right sprites).
  Ortho projection FUN_020A7414(0, 192, 0, 255, …): screen px, y down; a larger z is in front (V: fill at z 41 over
  outline at z 40).
- **Hit damage stream** (V, `w3dbg`, Goku vs Goku): Goku's beam super (R charge, X+A at a distance) deals 120 per
  FUN_020293A4 call, first 3 ticks one frame apart, then every 4 frames (23 ticks = 2760 here); ki blasts 432 hit 8
  frames apart; dash attack 1080; CPU heavy 2000; melee 198 / 297. Guarded: see DAMAGE NUMBERS below (action 0x0E at the call).
- **Hit-stop** (V): on a strong hit the battle freezes for a few frames (p4636 = p4638); f_0202954C does not run, so
  effects stepped on `_fx_upd` freeze with it.
- **DAMAGE NUMBERS** (port WEIRD setting, V): QoLGame `# ---- WEIRD 3 (part 24)`; hook line in f_020293a4 (`_w3_hit`,
  damage before cheats change it); hits on one victim within 10 battle frames (debug `w3merge=N`) add up into one number (a beam = one
  growing number following the victim; it lives 60 battle frames after the last tick, rising 22 px, fading over the
  last 16). Tiers: < 300 white 1x, < 800 yellow 1x, < 1500 orange 2x, >= 1500 red 2x, guarded grey 1x; a new number
  / higher tier draws one size up for 3 frames. Hand-drawn 5x7 digits (advance 6), 1 px dark outline (dilated glyph),
  lower 3 rows darker; glyphs pre-split into rectangles (≈ 4-6 per digit per pass) and sent as untextured quads with
  VTX_XY in two BEGIN batches (outline ID 0x26 z 40, fill ID 0x27 z 41) after all other effects in `_fx_draw`.
  Screen position = the part-22 world → screen mapping (zoom-aware), clamped to x 2..254, y 30..186; glyph size does
  not follow the zoom. Never overlapping (part 24 follow-up): each frame the boxes (outline included) are laid out in
  screen space, newest at its own spot; older numbers that would touch it (same victim or any number nearby) get
  a lift target that clears it by 2 px, and their lift grows toward it smoothly (45 % of the rest per frame, at least
  1.5 px; it never shrinks); until they are clear, newer numbers are drawn just below them, so no two boxes ever
  overlap. Numbers pushed above y 4 are dropped. V: /tmp/ssw2/w3/s_stack.png (w3merge=0, mirror, zoom 0: up to 4
  guarded 108s stacked in a column under the HUD, one of them popping at 2x). Guarded (M, V): a blocked ki blast
  (432 → 108) lands while the victim is in action 0x0E (0x18 guard the frame before; +0x250 & 9 was 0), so guarded =
  +0x250 & 9 or action 0x0E / 0x18. MIRROR MODE: drawn with x scale −1 so the flipped picture reads normally.
- **RAINBOW KI** (port WEIRD setting, V): objects whose handler is 0x020209E0 or 0x02020330 / 0x020203CC / 0x02020560
  (as FLASHY KI) get GX COLOR hsv(t / 36 + slot × 0.085, 0.72, 1) (modulation) written from an override of FUN_020A71C8
  while the drawer runs (white again for the next untinted sprite and after the list); FLASHY KI copies use the same
  colour. Battle frames only (`_w3_t`), so pauses freeze the cycle.
- **JELLY FIGHTERS** (port WEIRD setting, V): spring per fighter record s'' = −0.18 (s − rest) − 0.16 s' + kicks, s
  clamped ±0.2, drawn as height × (1 + s), width / (1 + s) via an extra MTX_MULT_4x3 before FUN_020A71C8's rotation,
  anchored at the feet (u8 0x020CFCA8[id] × quad height / 128 below the centre) when standing, the centre in the air
  (blend 0.25 / frame). Kicks: hit −dmg/10000 (0.012..0.12), sudden horizontal speed change ≥ 2 px/frame wider, vertical
  speed change taller (speeds averaged over 2 frames, so the hit vibration ±x every frame cancels; at most one speed
  kick per 3 frames), landing / take-off (rare: fighters fly); rest point stretched by fast vertical motion in the air
  (|vy| × 0.03 ≤ 0.15); idle wobble ±0.012 on the ground. No speed kicks while the fighter is in a scripted victim
  action 0x34-0x66 (V: Y+B throw swings the victim in a circle, act 0x34, ±11-32 px per 2 frames) or its sprite is
  rotated (+0x38 >> 4 != 0).
- **Tests** (V, /tmp/ssw2/w3, run.sh = Free Battle Goku vs Goku, inputs in2.txt): a = dmgnum + jelly + rainbow + flashy
  (sheets s_a1.png punches / dash 1080 / ki blasts 432, s_a2.png beam merged 120 → 2760 next to the game's RUSH counter,
  rainbow beam); c = dmgnum + jelly vs base = none (s_j1.png / s_j2.png: base / jelly pairs, squash at the feet after
  the dash attack, stretch flying up); b = all + flashy + mirror + zoom=0 (s_b1.png: numbers read normally in the
  flipped picture, 864 = two ki blasts merged, rainbow beam gradient); g / g2 = throw before / after the calm rule
  (s_g1.png, s_g2.png). Step cost (headless `turbo perf`, 2 CPUs under load 4): fight windows 12-18 ms per frame
  on and off, the difference (≤ 1 ms) inside the run-to-run noise.
- **Off = unchanged** (V): with the three off, off23 copy (21 PNGs 4300-5300 + 1382 CHT lines to 5300) identical to
  /tmp/ssw2/btn; intro (cap.sh 10 2210 10) 221/221 identical to /tmp/ssw2/intro. When off nothing new runs except a bool test in the f_020A71C8 override and one
  condition in f_020293a4 (no allocations).

## Session 1 part 24 findings (auto skip) — V = port verified, C = code read
- **Story scene (scene 1, FUN_0203E87C → FUN_0203E944)** (H, C+V): state u8 0x020DE4EC (setter FUN_0203FE78, getter
  FUN_0203FCE4), exit code u8 0x020DE4F0 (0 none, 1 L+R+Select+Start reset (FUN_0203FE30, tested in FUN_0203E87C),
  2 / 3 back (FUN_0203FE1C / FUN_0203FE08), 4 FUN_0203FDF4, 5 = go to the battle (FUN_0203FDE0)), u8 0x020DE4E4 = 0xFF
  after EXIT (FUN_0203FD18, back to the map), u32 0x020DE4F4 = character (FUN_0203FCC4). States seen (port probe, Goku
  "The Emperor Stirs"): 4-5 character select (FUN_02047464), 7, 0xD-0xE chapter map (FUN_020403AC; Start = menu 0xF),
  0x10, 0x12-0x14 load + fade, **0x15 pre-battle script** (FUN_0204C85C; Start opens menu 0x16 FUN_0204C3E8), 0x18-0x19
  end (progress written with FUN_02002410 / FUN_020023A0; exit 5 → 0x33 → battle scene 0), after the battle 0x1A-0x1C,
  **0x1D post-battle script** (FUN_0204C6E8; menu 0x1E), 0x20-0x21, 0x22-0x25 map reload, 0x26-0x28 new-chapter
  animation (FUN_020420F0), 0x29-0x2D character ending pictures (FUN_02040DC0: FUN_02062B90(table 0x020CFF68[char]),
  seen bit 0x020CFFA4[char] = 1 << char ORed into u32 0x020DD7A4 (save block +0x1F0)), 0x2E-0x32 final ending (all 15
  bits set and 0x8000 clear; FUN_02040D50 sets 0x8000), 0x33 leave. Ending condition FUN_02040C9C: all 20 chapter
  bytes == 5 and the bit not set. (V: probes, ston3 run with pokes)
- **Story progress entry** (M, V): save copy 0x020DD628 + char * 0x18: u16 0xFFFF, u16 0, then u8[20] chapter states
  (5 = cleared; clearing chapter 0 with chapter 0/1 poked to 1/0 gave 5 / 3 = next chapter opened).
- **Script player and its SKIP / EXIT buttons** (H, C+V): FUN_0204C85C / FUN_0204C6E8 (story) and FUN_0205AB94 /
  FUN_0205AD04 (another scene's scripts, state setter FUN_020598C8) each frame: FUN_0203E1E4 = touch in x 149-201, y
  110-191 (EXIT: SE 4, button highlight FUN_0203E0E4, script freed FUN_02037CEC, 0x020DE4E4 = 0xFF, back to the map;
  in the post-battle script only SE 0xD), FUN_0203E214 = touch in x 203-255, y 110-191 (**SKIP**: SE 2, highlight
  FUN_0203E164, FUN_02037A7C: script context (s32 0x020DE424, loaded flag u8 0x020DE420 == 0xFF) +0x84D = 0xFF, +0x84C
  = 0); B held → +0x84D = 0xF0 (fast, FUN_02037AB4), released → 0 (FUN_02037B24). The interpreter FUN_020369B4 runs
  no opcode handler while +0x84D == 0xFF (each op only advances +0x808) and returns 3 at the end → the state goes on.
  Pad block u16 0x020DD4DC: +0 pressed (FUN_02001230), +2 FUN_02001214, +4 held (FUN_020011F8), +6 FUN_020011DC.
- **Skipping keeps progress** (H, V): Goku chapter 0 (chapter bytes poked to 01 00 at frame 2700, cheats
  one_hit_ko + infinite_health, same inputs): watched (A every 90 frames: pre-battle script frames 2960-4170,
  post-battle 5480-6660) vs AUTO SKIP (scripts skipped at f2959 and f4219, 0 frames shown): save copy
  0x020DD5B4..0x020DD7A8 byte-identical after the chapter (incl. CRC, Goku 05 03 …), the written .sav files identical,
  party block 0x020DD514.. identical at battle start (only fade bytes 0x020DD500-0x50B differ), same next chapter /
  "Map Clear 11/14" and new-chapter animation. 100 % save run: identical too (nothing changes).
- **Ending pictures** (H, C+V): FUN_02040BD0 (states 0x2B / 0x30) calls FUN_02065704 on A / B / touch, which only sets
  the advance request u8 0x020DE620 while u8 0x020DE624 != 0 (set by FUN_0206573C, cleared by FUN_02065728); in the
  ston3 run that was only the final ending's message box (one A at f5763): the game allows no skip of the pictures,
  so AUTO SKIP leaves them alone.
- **VS screen** (H, C+V): battle state 2 (FUN_02013064) runs FUN_02018714, sub-state u16 0x020DD4C6 (FUN_020010C4):
  0 setup (STRM 0x12), 1 panels slide in (0x46 frames, counter globals +0x1BCA4), 2 "VS DRAGON BALL Z" emblem (0x78
  frames), 3 fade out → battle state 3 (load). **A pressed in sub-state 1 or 2 skips to 3** unless u8 0x020DD54E
  (party block +0x32, FUN_02002728) is set (all modes). Z-Battle (mode u32 0x020DD514 == 0) VS screen measured: 2970 →
  3230 (260 frames) watched, 2970 → 3020 with A at sub-state 1 (fade only; the opponent panels are not drawn, as in
  the original when A is pressed). Z-Battle flow (zb run): scene 4 team select → 0x12 → scene 0 states 1-2 (VS) …
  KO 0x11 → 0x13 → scene 0x14 (results / score) → scene 0 VS again for the next team.
- **AUTO SKIP** (port setting, V): QoLGame `# ---- AUTO SKIP (part 24)`: f_0203e214 override returns 1 (SKIP touched)
  once per script while scene == 1 and the script context's +0x84D != 0xFF; f_02018714 override adds A (bit 0) to the
  pressed word 0x020DD4DC around the call (restored after) while mode == 0 (Z-Battle), u8 0x020DD54E == 0 and sub-state
  1 / 2. Story VS screens, Free / VS / Maximum VS screens, endings, menus, battles, results, tutorials and the attract
  mode are not touched. `skipdbg` prints "SKIP f<frame> <what> (scene S state X)". Evidence (/tmp/ssw2/askip):
  zb_sheet.png (row 1 watched VS, row 2 skipped 1st fight f2985, row 3 skipped 2nd fight f6440), story_sheet.png
  (rows 1/3 watched pre / post-battle scripts, rows 2/4 skipped: map → black → VS screen; results → map).
- **Off = unchanged** (V): off23 copy (21 PNGs 4300-5300 + 1382 CHT lines to 5300) identical to /tmp/ssw2/btn with
  AUTO SKIP off and with autoskip=1 (Free Battle: 0 SKIP lines); intro (cap.sh 10 2210 10) 221/221 identical to
  /tmp/ssw2/intro off and with autoskip=1 (attract mode untouched).

## Session 1 part 24 findings (QA / runtime) — V = port verified, C = code read
- **Card DMA vs VBlank freeze is not a port timing bug** (H, C + V): FS reads use the card DMA only when the ROM
  offset, the length and the destination are aligned (FUN_020B24F0: dst & 3 == 0, (rom | len) & 0x1FF == 0, dst not
  in ITCM / DTCM; FS default DMA u32 0x020E50C0 = 3). DMA3CNT 0xAF000001 = repeat + card timing: the enable bit
  stays set after every 0x200-byte block (also in melonDS, DMA.cpp: `if (!(Cnt & (1<<25))) Cnt &= ~(1<<31)`); only
  the card IRQ handler FUN_020B264C clears it (MI_StopDma 0x020AB738) and chains the next block (FUN_020B2724). A
  VBlank handler that waits for DMA 3 (FUN_0201098C / FUN_02006518 → FUN_020A8B0C / FUN_020A89E0 → FUN_020AB82C →
  MIi_WaitDma FUN_020AB7BC: IRQs off, spin on DMA3CNT bit 31) blocks that IRQ, so a DS hangs exactly like the port.
  The port's block timing (whole block at once, card IRQ at the next scanline) is the same window as the hardware,
  not a wider one; "completing the card read before the IRQ" would have to run the game's own card IRQs early
  (a different order of events than the DS for every DMA read that spans line 192). No runtime change; the QoLGame
  skip (`_shuf_loading` / `_stg_busy`) is the correct fix and stays.
- **Which reads** (V, port instrumentation, removed again): Free Battle boot→battle and 36 CHAOS SHUFFLE swaps (+ STAGE
  SHUFFLE): 0 card reads by DMA; the ROM has one aligned file (FAT 40 romdata/chara/ghn_img.arc 0x640800, 0x26600
  bytes), read by member. Part 18's freeze needed a DMA read in a swap, which the current swap path no longer does.
- **Reproduction** (V): debug flags `noloadskip` (skip off) + `dmaread` (an aligned 0x26600-byte DMA read of
  ghn_img.arc into 0x02780000 with f_020B20F4(3, 0x640800, dst, len, 0, 0, 0) in every character swap): chaos run
  (shufrunB setup, chaos_C inputs, shufseed=49) → first swap: VBlank handler 0x02013030 entered with DMA3CNT
  af000001, card IRQ pending, block 0x200/0x200 → "busy-wait on 040000dc" f_020ab7bc ← f_020ab82c ← f_020a89e0 ←
  f_0201098c, "game stopped" (/tmp/ssw2/qa24/dma_noskip.log). `dmaread` alone (skip on): 2 swaps, "dmaread result 1
  vblanks during it 1 / 2", no freeze (dma_skip.log). Lockstep t1 18 frames: only the known 0x020E18A9 / 0x020E1931 /
  0x022E6400 diffs; intro 221/221; off23 copy 21/21 PNGs + 1382 CHT lines identical.
- **Menu QA** (V): offline checker over all 10 pages + CONTROLS 1-3 + confirm / lbconfirm / jukebox (every row /
  button: top title ≤ 159 px, description ≤ 5 lines inside x 26..243, CONTROLS waiting texts, button texts, labels,
  wrapping Up/Down, L/R through all pages both ways, B from every page, taps on every button → value red); in-game
  walks: R ×10 / L / header taps / DAMAGE NUMBERS ON → cfg, HI-SCORES RESET → B, qoltest.sh (window confirm / undo /
  timeout, jukebox) and qoltest3.sh + CONTROLS 3 (cursor OFF, SPEED by tap and keys) → cfg as expected; settings.cfg
  round trip of every QoLSettings field incl. auto_skip, damage_numbers, rainbow_ki, jelly_fighters, cursor_enabled,
  cursor_speed and the qol_cur_* mappings: identical. Bugs fixed: page counter "n/10" (27-34 px) over the header
  arrow hexagons (arrows now 24 px at x 126 / 186, counter box 36 px); tile text "Cheats on: N (pages 3-6 of the
  menu)." ran past the description box and named the wrong pages (now "menu pages 4-7", also shown before the menu
  was first opened); 7-letter pad names (R-STICK, D-RIGHT, PADDLE1) drawn over the box rims (now the narrower
  REGULAR font); B on the HI-SCORES "ARE YOU SURE?" page played the back and the decide sound in the same frame.
- **Combos** (V): Z-Battle with autoskip=1 + infinite_health, one_hit_ko, chaos_shuffle, stage_shuffle, triple_ki,
  random_music + every weird option, 7400 frames headless: several opponents KO'd, 22 swaps, no script error; Free
  Battle with every weird option + shadows=1 + zoom=0: no error, damage numbers readable under MIRROR MODE; gamepad
  cursor (`vcursor` / `vcurclick` / `vcurmove`) presses the menu's page arrow.
- **MIRROR MODE vs pause** (port, V): the battle pause menu is drawn while battle state u8 0x020DD4C5 == 9;
  `DSDisplay.mirror_active()` (and the damage-number mirror test in QoLGame) now exclude state 9, so the pause menu
  reads normally and LEFT/RIGHT are not swapped in it (/tmp/ssw2/mirpause_sheet.png: f5150/5200 paused unmirrored,
  f5250 mirrored again).

## Session 1 part 25 findings (input display, CRT TV) — V = port verified, C = code read
- **Game pad words** (H, C + V): FUN_0200124C builds the pad block (pointer DAT_020013C4 = 0x020DD4DC): u16 +0 newly
  pressed, +2 released, +4 held (KEYINPUT | the X/Y bits, active-high); bits 0x001 A, 0x002 B, 0x004 Select, 0x008
  Start, 0x010 RIGHT, 0x020 LEFT, 0x040 UP, 0x080 DOWN, 0x100 R, 0x200 L, 0x400 X, 0x800 Y. Each fighter keeps a copy
  with the same layout at +0x26C pressed / +0x26E released / +0x270 held (FUN_020011C8(mask, f+0x26C) tests pressed,
  FUN_020011B4 tests +4 = held). V (`inpdbg`, Free Battle script): every scripted press shows the same word in
  0x020DD4E0 and in P1's +0x270 on the same frame (A 001, B 002, X 400, Y 800, L 200, R 100, Right 010, Left 020,
  Up+Right 050, Down+Left 0A0, Down+Left+A 0A1, R+A 101, Up+Y 840, Down+Y 880; Select 004 reaches the fighter copy).
- **The fighter copy is not the raw pad** (M, C): FUN_02028FE4 clears +0x26C/+0x26E/+0x270 and FUN_02029FF4 clears
  them for both fighters pointed to by globals +0x11D0 / +0x11D4; FUN_020273AC drops DOWN
  (& 0xFF7F) from all three words when u16 [f+0x10] & 1. So INPUT DISPLAY reads the pad block (0x020DD4E0), which
  already has the CONTROLS remapping and MIRROR MODE's swap (GameDS swaps LEFT/RIGHT before the game reads KEYINPUT);
  the display undoes the mirror swap so the arrows match the direction pressed / moved on the flipped screen.
- **INPUT DISPLAY** (port, V): scripts/qol/qol_input_display.gd (`QoLInputDisplay`, child of screen_root, z 95, made
  by QoLController.setup, `frame()` from after_step; off = one test). Shown while DSDisplay.battle_on_screen() and
  engine A is on top; history frozen while paused (state 9); cleared when the battle ends. Strip x 67..188, y
  171..189 (between the ki gauges, which span x 0..63 / 194..255, y 169..189; the pause menu is y ~30..130): D-pad
  (15 px cross, held arms orange), L Y X / R B A 7-px chips (held = orange, black letter), then the last input states
  newest first (arrow + button letters, neutral = dot) with the frames each was held (cap 99), as many as fit (up to
  8). 3x5 / 7x7 pixel glyphs from one small atlas; dark translucent backing; black outlines keep it readable under
  GAME BOY (unlit fill one DMG shade above the outline). Debug `inpdbg`: "INPD f… pad … shown … fighter pressed/held".
- **CRT TV** (port, V): shaders/ds_fx_crt.gdshader + scripts/qol/qol_crt.gd (`QoLCrt`, child of QoLController,
  `_process`; off = one test, no material / layer). With DSPresenter the picture is drawn through the shader at the
  window's resolution (DSPresenter.set_crt; `scale` = window px per DS px, sharp-bilinear sampling as before):
  scanline darkness = the exact fraction of each window pixel inside the lower 42 % of a DS row (box-filtered, so
  one line per DS row at 2X/3X/4X/8X and anti-aliased at full-screen fit scales; faded out below 1.5X), bright pixels
  darken less; glow = 8 bilinear taps (~5x5 DS px) of the parts above 0.5, + 0.24; per-screen vignette and 9-px
  rounded dark corners (each DS screen its own tube); RGB stripe mask ±7 % at scale ≥ 3. Without the presenter
  (captures, `snap=`, `present=0`) a ColorRect on CanvasLayer 65 (above GAME BOY's 64) runs the CRT_SCREEN variant at
  1X (glow, vignette, corners; no scanlines possible at one pixel per row). While the QoL menu is open the lower
  screen and QoLTopInfo's area (y 24..147) are left untouched except the corners (`sharp0/1` uniforms).
- **Tests** (V): Free Battle (/tmp/ssw2/inpd_run.sh) weird=inputs (inpd_on1), inputs+crt+mirror+zoom=0 (inpd_mir:
  display unflipped, Right pressed under mirror shown as →), inputs+crt+gameboy (inpd_gb), inputs+crt+zoom=0 final
  style (inpd_fin; /tmp/ssw2/inpd_work/fin_sheet.png, fin_z.png); Mode Select + QoL menu WEIRD STUFF 3 with crt
  (/tmp/ssw2/inpd_menu, menu_sheet.png: menu + description box sharp); real-time presenter screenshots on Xvfb
  (/tmp/ssw2/inpd_rt.sh): 2X (w2: rows alternate FFFF00 / FFE500 on the yellow logo band), 3X `presentfit` 768x1152
  (f3: period-3 rows, 1 dim of 3), 2.344X fit (f23: anti-aliased lines), 4X battle (x4: one line per 4 px, RGB mask).
  Off: /tmp/ssw2/inpd_off.sh (copy of off23.sh) 21/21 PNGs identical to /tmp/ssw2/btn and 1382 `CHT f` lines identical;
  intro (cap.sh 10 2210 10, xvfb-run) 221/221 identical to /tmp/ssw2/intro.

## Session 1 part 25 findings (bomb rain) — V = port verified, C = code read
- **Ki-blast hit path** (H, C): FUN_0201E9EC(obj, victim, reaction) is the common damage routine of projectile hit
  handlers (obj +0x118 = hit header: u32 [0] damage, s16 +4 push speed, u8 +6 class 0-5, u8 +7 guard-crush value).
  Fighter victim, not guarding (u32 +0x250 & 1 == 0): FUN_020213A8(victim, push, -0x18, 0, obj +7) (push along the
  shot's direction), FUN_020293A4(victim, damage * u16 [attacker +0x50]+0x14 >> 8, class), RUSH FUN_02029804(attacker);
  unless KO action 0x33: +0x250 = 0, u8 +0x25D = victim's own side +0x1A, FUN_02021B4C(victim, reaction) (0xF light,
  0x11 heavy: FUN_0201EEE0 passes 0xF, FUN_0201F474 / FUN_0201F594 0x11); stun u16 +0x25E = 10 (class < 4) else 60;
  +0x250 |= 2 (and 0x4000 class 0-1 / 0x8000 class 2); score FUN_02028FB0(side, 100/500/800/1000). Guarding: guard
  spark = common effect kind 0xB at the box overlap (globals +4 via FUN_0201E210), guard crush FUN_020292E8; only a
  crushed guard takes damage (header[0] >> 2, action 0xE, HP floored at 1). Dash-attacking victims (0x20 / 0x22,
  class < 3) deflect the shot (kind 0x3A); victim +0x254 & 0x400 absorbs it (ki +0xA00 / +0x1400).
- **HP scale** (H, C+V): FUN_020293A4 multiplies the damage by u16 [*0x020DE3D0 + 0x1676] / 256 (set by the battle loader
  FUN_0202A40C: 0x100, or 0x140 / 0x180 in some modes by a level value (M, not traced further)); Free Battle / Z-Battle /
  Story runs read 0x100.
- **Common effects** (H, C+V): FUN_0202247C(owner, kind) spawns a COMMON effect (not a character's): chunk struct
  copied from [0x020DE3CC] + 0x4DF0 (0xE0 bytes), kind table u32 [[0x020DE3CC] + 0x4F10] ({per-frame, hit handler} x
  8 bytes), side +0x1A and position from the owner (owner +0x1A, +0x38 / +0x3C). Then FUN_0202216C(obj, arg, attach):
  arg bit 3 → u8 +0x1D = (arg >> 16) & 0x1F (0xFF0008 = random via FUN_02001998); attach 0 = free-standing (bits
  1 / 8 of the 3rd argument attach to the owner, 2 / 4 = die with the owner / its action). Kinds seen: 1 = ki-blast
  explosion (hit handlers FUN_0201EEE0 0x20008, FUN_0201F474 0x30008, FUN_0201F4D4 0x20008, FUN_0201F534 0x10008,
  FUN_0201F594 none, FUN_02016A5C / FUN_020302C0 0x40008); +0x1D = SIZE: 0 ~40 px, 1 ~70, 2 ~110, 3-4 fill most of the
  battle picture (V, /tmp/ssw2/bomb_work/ex_*.png); its hit handler 0x02020EC4 does nothing (no damage, V). 0xB guard
  spark, 9 melee hit spark, 0x3A deflect, 4/5/6 dash dust (FUN_0202C4A0 / FUN_0202C620), 0xD-0xF / 0x11 / 0x12 from the
  dispatcher / neutral handlers (L: not looked at).
- **Explosion sound** (H, C): FUN_02029E3C(obj, se) = FUN_0200FF68(1, se, channel side*3 + 4 + rotating u8 counter in
  the side's team block), counter += 1 & 3. Every blast hit handler above plays SE 0x1E with it (V: heard as the game's
  ki-blast explosion; port log shows the call, no error).
- **Hurt box** (H, C): FUN_0201DF20(out s16[4], obj, type, index) = world-px box {x0, y0, x1, y1} of the frame
  descriptor (+0x120) entry of `type` (2 = hurt, as FUN_0201EE60 uses it), mirrored by the facing; default ±0x20
  around the position.
- **Battle states** (H, V): 8 / 0xA-0xE are events inside the fight that return to 7 (part 22 note); BOMB RAIN freezes
  in them, in pause 9, in cut-ins (FUN_02012FD4 != 0), tag changes (globals +0x11DC), camera mode != 0 (supers / team
  arts) and while an active fighter is in action 0x34 (throw / clash sequence, its camera hides the fighters).
- **BOMB RAIN** (port setting, WEIRD STUFF 3; scripts/qol/qol_bombs.gd + `# ---- BOMB RAIN (part 25)` hooks in
  QoLGame: f_0202954C tick, f_0202A40C reset, _fx_any / _fx_draw). Own RNG (seed `bombseed`, default 0xB0B0B, reset at
  every battle load), never the game's. Spawn every 72-150 battle frames (`bombrate=F` divides), max 5 alive, first one
  70 frames into the fight, x = a random active fighter ±80 world px clamped into the drawn view, y just above the
  picture (the view as DRAWN: with CAMERA ZOOM the camera +6 zoom is only scaled while drawing, so the tick uses the
  camera values recorded in _fx_draw). Fall 0.9 → 2.1 world px / frame (+0.035), ±3 px sway: ~1.5-2 s from the top to
  the floor at zoom 1. Floor = FUN_0201B488 ground (+0xCC2) + 64 (+0..8 depth). Direct hit = 11x12 box (fuse row
  excluded) overlaps an active fighter's hurt box (fighters in intro / win 0x13-0x15, KO 0x33, frozen +0x250 & 0x800,
  HP <= 0, drawn in screen space +0x12 & 8, or hurt by a bomb in the last 45 frames are skipped): explosion (kind 1
  size 1 + SE 0x1E at the bomb), victim loses 25 % of max HP +0x24C (argument / scale so that exactly 25 % is lost),
  push 0x500 / -0x40 away from the bomb 22° upward (direction 0x10 / 0x70), reaction 0x11, stun 10, +0x250 = 2; a
  guarding victim (+0x250 & 1): 1/4 of it with HP kept >= 1, guard spark kind 0xB, push / 3, no reaction. Other active
  fighters within 40 world px of the blast (to the hurt box): 12 % → 3 % linearly, reaction 0xF, push 0x380. Floor
  reached: the same blast at floor - 6. Left the drawn picture by 24 px (or 1200 frames): removed silently. KO /
  battle end: all bombs removed. Damage goes through QoLGame.f_020293A4 (INFINITE HEALTH, HARD MODE, ONE HIT KO,
  BLOOD, DAMAGE NUMBERS, SCREEN SHAKE apply; bombs hurt both teams; no score / RUSH credit).
- **Drawing without VRAM** (H, V): the user's art assets_qol/bomb.png (edited from bomb_src.png: 6 frames 11x12 = feet
  A/B x 3 fuse sparks, DS 15-bit colours, dark navy outline) is turned into untextured GX quads at load: colour layers,
  each covering its own pixels or all pixels not yet drawn (fewer rectangles wins, greedy order), one z unit apart
  (VTX_16 z 0x400 per layer, matrix z scale 4): 35-38 quads per frame, padded to 38 for a stable polygon numbering
  (smooth motion). Shadows: 16x6 black ellipse of 3 quads (like the game's own opaque black fighter ellipses), x0.4-1
  by the height above the floor, z 1. Bombs z 10, polygon IDs 0x22 / 0x23. The prebuilt command lists are appended to
  DSCoreBase.gx_cmds directly (what io_write logs for 0x04000400-0x040005FF; the GX ports are write-only): 30-60 µs
  per drawn frame vs 400-500 µs per bomb through io_write (bombdbg timing). The Image is loaded on the main thread when
  QoLGame is created (loading a texture on the game thread deadlocks against the main thread: "game thread busy").
- **Tests** (V): /tmp/ssw2/bomb_run.sh NAME FROM TO EVERY QUIT flags (btnrun copy; BOMB_IN = own inputs). Free Battle
  `weird=bombs bombdbg`: full-HP P2 direct hit 13000 → 9750 (f4235, reaction 0x11, life bar drops a quarter), P1
  guarded blast 1/4 (f4832), ground blast 4.9 % on P1 standing nearby (f4375), dodged bombs (ground blast with nobody in
  range f4514, "left the picture" lines); sheets /tmp/ssw2/bomb_work/ev_direct.png, ev_dodge.png, g3b.png (shadows),
  ex_*.png (explosion sizes 1-4), zm1.png (`zoom=0` + MIRROR), zb.png (Z-Battle, mirror + zoom 0), Story
  (`autoskip=1`, 11 explosions): no SCRIPT ERROR anywhere. Cost (bombdbg averages): tick 40-160 µs, draw 30-60 µs per
  battle frame. Off: /tmp/ssw2/bomb_off.sh (off23 copy) 21/21 PNGs identical to /tmp/ssw2/btn, 1382 `CHT f` lines
  identical; intro (cap.sh 10 2210 10) 221/221 identical to /tmp/ssw2/intro.
- Debug flags: `bombdbg`, `bombseed=N`, `bombrate=F`, `bombfx=V` / `bombfxcycle` (explosion size), `bombkind=K`
  (spawn another common effect kind instead of 1).

## Session 1 part 26 findings (bomb sprite) — V = port verified, C = code read
- **Smooth-motion pairing** (H, C: scripts/render/ds_gx.gd `_poly_begin` / `_prev_of`, native/src/ds_gx_native.cpp
  `poly_begin`): an in-between frame (FPS > 60, `capinterp=A`) moves every vertex back by the screen motion of "the same
  point" in the previous polygon list. The previous polygon is found BY NUMBER: polygon k of this list is paired with
  polygon k of the last list when POLYGON_ATTR, TEXIMAGE_PARAM, PLTT_BASE and the 4 texture coordinates are equal (no
  search). Polygons with identical keys whose number shifts are therefore paired with a neighbour: its vertices get
  the neighbour's positions as their "previous" ones (motion ≤ 32 px is applied, per vertex, rounded to whole pixels).
- **BOMB RAIN pixels separating / grey boxes** (H, V): part 25 drew each bomb as 35-38 untextured quads (colour-layer
  rectangles, padded to 38) + 3 shadow quads, ALL with one key (TEXIMAGE_PARAM 0, TEXCOORD 0, same attributes). Every
  time the picture frame changed (fuse spark every 3 game frames, feet every 8: another rectangle set), the polygon
  count before the bombs changed (the game's sprite list: hit sparks, ki blasts, explosions...) or a bomb / shadow was
  added, quad j was paired with another rectangle: in in-between frames each rectangle slid / stretched part of the way
  toward a different one. Seen as pixels coming apart, single-colour layers stretched into boxes (body grey (7,7,9) or
  outline navy (2,2,4): the layers that cover "every pixel not yet drawn"), parts of the bomb gone. At 60 FPS (interp
  1) the sprite was always correct (per-frame captures). Evidence (track sheets, bomb crop per game frame, the 3D list is
  shown one frame late): before /tmp/ssw2/bs_work/a5_track.png (CAMERA ZOOM 2, interp 0.5: 12 of 20 frames below the
  HUD not the exact sprite, bs_work/verify.py), Az0c25.png (zoom 0, 0.25), Az4c5.png (zoom 4, 0.5); interp 1 a0_track.png fine. Not the cause: the port
  has no polygon / vertex RAM limit (2048 / 6144 are not modelled, nothing is dropped); no stale command list.
- **Fix: one textured quad per bomb and per shadow** (H, V): assets_qol/bomb.png → direct-colour texture (format 7, bit
  15 = opaque; no texture palette): frame f = 16x16 at texture offset 0x5F000 + f * 0x200 (the 11x12 picture top-left),
  shadow = 16x8 at 0x5FC00 (16x6 ellipse). TEXIMAGE_PARAM = (offset >> 3) | 1 << 20 | th << 23 | 7 << 26, texture
  coordinates = the pixel rectangle (12.4), COLOR 0x7FFF (modulation keeps the texels: the game's own sprite colour
  path; the 6-bit levels differ by ≤ 4/255 from the old untextured colours), PLTT_BASE = slot (bomb) / 8 + slot
  (shadow): unused by direct colour, it makes every bomb's key unique, so a bomb is never paired with another bomb; a new
  picture frame has another TEXIMAGE_PARAM, so it is just not blended for that one game frame (the whole quad moves
  together). Free slots up to the highest one in use are still emitted off screen (stable numbering).
- **Texture VRAM reservation** (H, C+V): battles map VRAMCNT A 0x83 / B 0x8B / C 0x93 = texture slots 0-2, D 0x81, G 0x83
  = texture palette slot 0, E / F off (`bombvram` lines). The game's texture manager (u32 0x020DE380, part 18 notes)
  spans 0..0x60000 (tail sentinel) and allocates first-fit from the bottom: observed top ≤ 0x1CF00 (≤ 21 of 48 blocks)
  in Free Battle with supers + FLASHY KI + 5x bombs. Keys seen: 0, 0x2000000x (stage), 0x125000xx, 0x364000xx, 0x365000xx,
  0x400000xx, 0x500000xx, 0x5800000x. BOMB RAIN inserts its own block {0x5F000, 0x1000, key 0x7B0B0B26, refs 1} the
  way FUN_02010D28 inserts (free struct from +0x6C8 + (0x2F - n) * 4, list +0x600 shifted, count +0x7AE + 1) but in the
  LAST gap, against the tail sentinel: the game's own allocations land exactly where they would without it (captures
  before / after the fix identical outside the bomb pixels), nothing can be allocated over it, nobody releases it; the
  manager is rebuilt by every scene reset, then it is reserved again (checked every fight frame: count byte + last list
  entry, O(1)). Texels written straight into bank C + 0x1F000 (the bank behind texture slot 2, like QoLButton), bank
  write counter + 1 (renderer re-upload), compared again whenever that bank is written / remapped. No block (layout not
  the battle's) → no bombs spawn.
- **Tests** (V, Free Battle Goku vs Goku, ice stage, `weird=bombs`; /tmp/ssw2/bs_run.sh NAME PROJECT FROM TO EVERY QUIT
  flags, the before runs use a copy of the project with the part-25 qol_bombs.gd; sheets in /tmp/ssw2/bs_work, made by
  track.py (crop around the drawn position, flag `bombpos` = BOMBD lines) and checked by verify.py (exact sprite pixels,
  any frame, flipped too)): CAMERA ZOOM 2 interp 1 a0_track / B0 (identical PNGs outside the bomb pixels: the block
  changes nothing else), interp 0.5 a5_track → b5_track (0 of 20 frames below the HUD not exact), interp 0.25
  Bz2c25 (0 not exact); zoom 0 interp 0.25 Az0c25 → Bz0c25, zoom 0 interp 1 Bz0c0; zoom 4 interp 0.5 Az4c5 → Bz4c5,
  interp 1 Bz4c0: no broken frame after the fix (scaled bombs are nearest-sampled like the game's sprites). Stress:
  bombrate 6-8 (5 bombs alive), FLASHY KI + SCREEN SHAKE + MIRROR MODE + interp 0.5 + TRIPLE KI / ASSIST SPAM + a
  super (0x2C/0x2D) (bs_S, bs_S2: S_sheet.png, S2_sheet.png, S2_track.png): every bomb below the HUD intact (exact
  where the camera zoom is 1); manager peak 21 blocks / 0x1CF00 + ours. STAGE SHUFFLE (stglist=10,..., swap at f4340):
  block kept, 131/131 bombs below the HUD exact. Story (autoskip, 2 battles): reserved again at the 2nd battle (scene
  rebuilt), bombs intact (story_track2.png; fogged stage colours, camera zoom). No SCRIPT ERROR anywhere. Off: bs_off.sh
  (off23 copy) 21/21 PNGs identical to /tmp/ssw2/btn, `CHT f` lines up to 5300 identical (1382); intro (cap.sh 10 2210
  10) 221/221 identical. Cost (bombdbg, 5 bombs, container CPU): draw 65-80 µs, tick 135-280 µs per battle frame.
- **Limits** (M): a bomb whose picture frame changes, or whose polygon number moves (the game's sprite count before it
  changed), is drawn unblended for that one game frame (all of it at its current position) — the same rule the game's
  own sprites follow. Other port effects drawn as several untextured quads with one key (DAMAGE NUMBERS glyph runs,
  BLOOD / CONFETTI / FLASHY KI pieces) can be paired with the wrong neighbour the same way in in-between frames (not
  looked at here). Debug: `bombpos` (BOMBD lines), `bombvram` (VRAMCNT, texture slots, manager blocks + keys every 20
  battle frames).
- **Other port effects (part 26 follow-up)** (H, V): measured with a scratch-copy instrumentation (never in the repo:
  /tmp/ssw2/bs_work/mkdiag.py; each effect polygon carries its true identity in SPE_EMI, inert without NORMAL; the
  GDScript geometry engine (`gxnative=0`) counts pairs whose previous polygon was a different object; run
  bs_dg0 = old behaviour (`pairkeys0`), bs_dg1 = fix; Free Battle 4100-4700 with DAMAGE NUMBERS, BLOOD, FLASHY KI,
  AFTERIMAGES, KO CONFETTI, DETAILED SHADOWS, BOMB RAIN (KO at f4396), ~4590 swaps). Wrong pairs (of paired, "visible" =
  within the 32 px blend limit): DAMAGE NUMBERS 2107 / 29022 (2008 visible), BLOOD 2327 / 55318 (1779), KO CONFETTI
  437 / 17589 (193); FLASHY KI sparkles (charging, run bs_dgsk0 / bs_dgsk1: R held, FLASHY KI + DAMAGE NUMBERS +
  BLOOD) 2029 / 5629 (1786); FLASHY KI glow / halo / trail copies 0 / 2698 (bs_dgsk0: 4 / 2988, all jumps > 32 px, not
  blended), AFTERIMAGES 0 / 526, DETAILED SHADOWS silhouettes 0 / 1702 (single textured quads of the game's own
  sprites, alpha / polygon ID differ per copy: different objects practically never share a key) - left as they are. Seen in captures: numbers
  scrambled into red / black blocks for a frame (/tmp/ssw2/bs_work/fxA5_dn.png f4316 / f4352, interp 0.5;
  fxAz0_a.png f4340 / f4352 / f4356, zoom 0 interp 0.25), a blood droplet stretched into a 25 px streak
  (fxAz0_bl.png f4356). Fix (qol_game.gd, sections BLOOD / FLASHY KI + KO CONFETTI / WEIRD 3): every untextured
  effect quad gets its own PLTT_BASE (`_fx_box(..., key)`, `_dn_key()`), which untextured polygons ignore: blood 0x400
  + slot * 4 + spawn generation & 3, FLASHY KI sparkles 0x700 + (slot * 2 + quad) * 4 + gen & 3, confetti 0x900 +
  slot * 4 + gen & 3 (generation counters `_fxk_bl / _fxk_sk / _fxk_cf`, +1 per spawn), damage numbers 0x1000 |
  (serial * 977 + total * 131 + size * 17 + quad index) & 0xFFF (a merged / popped number gets new keys). After: 0
  wrong pairs for all four (bs_dg1, bs_dgsk1); captures fxB5_dn.png, fxBz0_a.png, fxBz0_bl.png clean; 60 fps captures
  (bs_fxA1 vs bs_fxB1, 202 PNGs) byte-identical. A quad whose number moved is simply not blended for that frame.

## Session 1 part 27 findings (multiplayer research) — V = port verified, C = code read
Research for LOCAL MULTIPLAYER (design: docs/MULTIPLAYER_DESIGN.md). Evidence runs (port, 100% save): /tmp/ssw2/mp_research
(`run.sh NAME INPUTS CAP_FROM CAP_TO CAP_EVERY QUIT [flags]`; vs1/vs2 = VS menu, prac1/prac2 = Practice select + stage
select, zb2 = Z-Battle READY?, fb1 = Free Battle probes; sheets *_sheet.png, vs2_layers.png, prac2_layers.png,
portraits3.png).
- **Scene table 0x020B6278** (H, ROM dump of the table): 0 FUN_02013064 battle, 1 0x0203E87C story, 2 0x0208C1C8 boot,
  3 0x0206DCE8 character select (Free / Practice), 4 0x02066558 Z-Battle team select, 5 0x02071B68 stage select, 6
  0x02073F40 Mode Select, 7 0x02079430 wireless battle wrapper, 8 0x0207C860 Data, 9 0x02083DBC Option, 10 0x0208B578
  (results), 0xB 0x0204D0FC, 0xC 0x020567E0 Practice course select, 0xD 0x02058BC4, 0xE 0x02086DD8, 0xF 0x0208C1C8
  title, 0x10 0x0209BBC4, **0x11 0x0207BA08 VS BATTLE (wireless) menu**, 0x12 0x0209D524 (Z-Battle, before the VS
  screen), 0x13 0x0202FDB8 Practice battle, 0x14 0x0209DED8 Game Over / Continue, 0x15 0x0209EB44, 0x16 0x02000FEC.
- **Game mode u32 0x020DD514** (H, C+V): 0 Z-Battle, 1 Story, 2 VS (wireless), 3 Maximum, 5 Free, 0xB Practice
  (FUN_02056C30 sets 0xB before scene 3; FUN_0205990C sets 10 before scene 0x13), 6 while Mode Select is up (V: probe).
  Party block 0x020DD51C: +0x32 u8 "wireless link" flag (FUN_02002738(1) / getter FUN_02002728), +0x33 u8 1 = host,
  2 = client (FUN_020026E4(1/0), FUN_02002708 = host?, FUN_020026C4 = client?). u32 0x020DD518 = 1 set by FUN_020029C4,
  0 by FUN_020029B0 (battle init FUN_020140C8). V (fb1, Free Battle Goku vs Goku): mode 5, P1 0x020DD524 = 0, P2
  0x020DD530 = 0, counts u8 0x020DD548/549 = 1/1, stage u8 0x020DD54A = 0x0E.
- **VS BATTLE menu = scene 0x11 FUN_0207BA08** (H, C+V): Mode Select tile 2 (FUN_02075738: 2 → 0x11). Work block u32
  0x020E1148 → heap 0x164F4 bytes. States u8 0x020DD4C5: 0 fade, 1 load (FUN_0207BF70: VRAM / BG setup, then
  FUN_0207AB08 + FUN_0207A3CC; if party +0x33 == 2 it goes to state 3 = client wait), **2 = HOST / CLIENT choice
  FUN_0207B778** (V: probe 0x0211 from f2780 with the vs1 inputs), 3-6 wireless (connect), 7 fade-out, 8 / 9 leave:
  FUN_02001014(work +0x18CB) after FUN_02002738(1) (state 9: FUN_02002738(0) and scene 0xF). FUN_0207B778 returns 0
  (nothing), 1 = A / tap on the left button with cursor 0 (HOST), 2 = right (CLIENT), 3 = B; cursor u16 work +0x1066
  (0 left, 1 right; Left / Right toggle, SE 4; A / tap = SE 5); touch rects x 0..0x78 / 0x88..0x100, y 0x30..0x90
  (FUN_02009844). Results 1 / 2: +0x33 = 1 / 2, +0x18CB = 4 (scene 4, team select in wireless mode), teardown
  (FUN_020029C4, FUN_020033A4, FUN_02005914, FUN_020102F4, FUN_020102A8, FUN_020103BC, FUN_02010578), state 7. Result 3:
  +0x18CB = 6, FUN_02002738(0). Wireless itself only starts in scene 4 / scene 7 (FUN_020033C0 is the card pull-out
  callback set-up, not wireless), so states 1-2 of scene 0x11 are an ordinary menu.
- **VS menu graphics** (H, C + layersweep / dumpvram V, vs2 f2880): POWCNT1 0x020F (engine A = lower screen). Lower:
  DISPCNT_A 0x08010708 — BG0 = 3D (the yellow selection frame: object at work +0x1068, 128x128 texture from
  /romdata/game/vsmode.bin `tex_cursol1`, drawn by FUN_02011F98(obj, 0x37 / 200, 0x6E, flip)), BG1 0x1903 = hexagon
  background (`bg.nbfc/nbfs/nbfp`, layer 1), BG2 0x1A86 = the two picture buttons with the 親 / 子 kanji, the HOST /
  CLIENT label plates and the DBZ footer (`bg_tenka.nbfc/nbfs/nbfp`, 256 colours, layer 2). Upper (engine B, DISPCNT
  0x00010300): BG0 = /romdata/scene/common/common_bg.bin frame (VS BATTLE title, message box; layer 4), BG1 =
  `msg_<lang>` message text (layer 5): FUN_0207A31C(n) copies a 32x10 map region from work +0x15CF4 (n 0, HOST text),
  +0x15F74 (1, CLIENT), +0x161F4 (2) to the layer-5 map and queues it (FUN_02006B68(5, 0x800)). Layer numbers of the BG
  manager: 0-3 = engine A BG0-3, 4-7 = engine B BG0-3. Language index FUN_0200264C (1 = English).
- **Character select scene 3 FUN_0206DCE8** (H, C + V prac1/prac2): one blocking loop per frame: keys FUN_0200124C,
  touch FUN_020098EC, FUN_0206D6F0 (fades), **FUN_0206CC94 = input → result** (0x800 nothing, id = pick, -1 refused,
  -2 / -10 cancel, 0x8000 GO), B (FUN_02001230(2)) → FUN_0206EABC removes the LAST pick of slots 5..0 (a stack over both
  sides), Start + a pick → READY? (FUN_0206A748(1)), Select → FUN_0206E9B0; then FUN_0206F948, FUN_0206E818, FUN_0200B244
  (3D frame set-up), FUN_02069990 (positions + draws all objects), FUN_0200AB18, VBlank wait. Exits: no picks + B →
  mode 0xB: scene 0xC (and mode 6), else scene 6; GO with side byte 1 → scene 5; soft reset → 6. Side being picked u8
  0x020DEA2C (FUN_0206D56C / FUN_0206D55C; 0 PLAYER, 1 ENEMY; GO with side 0 switches to 1 and clears 0x020DE64C).
  Picks: s32[6] 0x020DE658 (0-2 P1, 3-5 P2; FUN_02065E90 / FUN_02065EA0), current side's team s32[3] 0x020DE64C
  (FUN_02065E70; duplicate / family / support tests). FUN_0206ED18(id) commits a pick for the side byte (DP check
  FUN_020671F4 used vs FUN_02066074 max u32 0x020DE638 & 0xFF; per-slot DP FUN_02066CA4/94/84; redraw FUN_0206EF54 +
  FUN_0206FA64). Practice (mode 0xB) shows D·P ∞/∞ and both PLAYER and ENEMY lists (V prac2: Goku → slot 0, Piccolo
  (id 5) → slot 3, then scene 5). READY? overlay (GO red / BACK blue circles, "READY?") = confirm state u32
  0x020DE8AC+0x10 (FUN_0206A76C / FUN_0206A748), drawn by FUN_0206A4B8 / FUN_02068B18; GO rect x 131..171 y 43..87
  (0x020D05CC), BACK x 75..117 y 98..142 (0x020D05C8); A = GO. The same overlay in Z-Battle (scene 4, zb2 f2820) — this
  is the "red / blue hexagon confirmation".
- **Select grid** (H, C + ROM tables + V): lower screen = engine A, BG0 = 3D (faces, DP tabs, CANCEL, outline — all
  objects), BG1 = hexagon background (prac2 layersweep f3060). 16 hexes, hex index → position u16 x/y 0x020D04F0 /
  0x020D04F2 (stride 4; e.g. hex 4 = (43, 40)), touch rects 0x020D0668 (8 bytes per hex); character id → hex u8
  0x020D04A0[id] (several ids share a hex: the DP tab decides which one is lit). Tab u32 0x020DB534 (0-6 = DP1..DP7,
  7 = SP); tab members 0x020D060C (4 per tab: DP1 24,12,13 · DP2 4,10,22,14 · DP3 0,5,6,11 · DP4 3,8,25,18 · DP5
  1,7,23,19 · DP6 2,15,16,20 · DP7 9,17); first id of a tab 0x020D0400; SP: supports 26..35 at hexes 0x020D05D8
  (ids 0x020D05E4); tab rects 0x020D0628. Neighbours u8[4] per id at 0x020D0530: [0] Left, [1] Right, [2] Up (previous
  tab), [3] Down (next tab) (FUN_0206A980(2/1/3/4)); e.g. Goku 0 = (11, 5, 4, 3). Up / Down in the game = tab ±1 +
  move to that neighbour (only from a fighter); FUN_0206ADB8 re-lights the tab, FUN_0206ABB0 greys picked / refused.
- **Selection outline** (H, C): cursor block 0x020DE9B8: +0x57 u8 character under the cursor (= the old "u8
  0x020DEA0F"), +0x58..+0x5B neighbours, +4 / +8 object pointers (outline, DP label), +0x28 DP-number object. Objects:
  +4 u8 frame / palette variant, +5 u8 alpha (0 = not drawn), +0x3C / +0x40 / +0x44 s32 x / y / z (20.12; FUN_0206A980:
  x = hex x + 0x16, y = hex y + 0x10 (0xF from hex y 0x60), z 0x5F / 0x61). Drawn as one GX quad each by FUN_0200AB48 /
  FUN_0200AEBC(obj) (TEXIMAGE_PARAM, PLTT_BASE, POLYGON_ATTR alpha = +5, MTX from FUN_020A6B90(obj+0x18, obj+0x3C),
  quad; no COLOR command: the frame set-up's DIF_AMB 0x4210FFFF leaves vertex colour white, so a GX COLOR written before
  the call tints the object, as RAINBOW KI does). FUN_0206A3D8 draws the cursor objects (+4, +8, +0x28) once per frame.
- **Stage select scene 5** (H, C + V prac2): loop FUN_0207197C; per frame FUN_02071608 (keys + touch), FUN_0207215C
  (bar scroll + input; returns 0x81 = confirm), B → back (FUN_020717E8(2): mode 2 → scene 4, else scene 3), A →
  confirm, FUN_02071E64 draws (FUN_0200B244, 16 icons, bars, cursor object, FUN_0200AB18). Cursor icon s16 0x020DEB2C
  (= 0x020DEB0C + 0x20; FUN_02071CB4), 4 x 4: Up / Down ±4, Left / Right ±1 within the row (FUN_02071F18), touch rects
  0x020D07E8 / 0x020D0868; cursor objects [0x020DEB0C+0xC] / [+0x10] (variant by column parity, +0x22 from FUN_020724B4)
  at icon x / y u16 0x020D0768 / 0x020D076A (stride 8). Icon → stage id 0x020D0758 = 10 12 11 9 4 7 5 8 3 0 1 2 14 13
  6, icon 15 = random. Exit FUN_020717E8(1): FUN_02071374 commits stage (FUN_0200294C) + both parties (support moved
  last; FUN_02002838(side, id)), then mode 2 → scene 7, mode 0xB → scene 0x13, else scene 0.
- **Battle input** (H, C + V fb1): battle globals G = u32 0x020DE3A0 (0x02100048 in Free Battle), teams = G + 0x7580
  (= u32 0x020DE3D0 = 0x021075C8), active index P1 G + 0x7E48, P2 G + 0x8730. FUN_020140C8(work, vblank, input_fn)
  stores **input_fn at G + 0x1BCB4** (V: 0x02012DA8 in Free Battle); FUN_02013C34 (battle states 5-7, and the event
  states) calls it every frame, then FUN_020129C0 (states < 7: both active records' pressed / released / held keep only
  the direction bits, +0x263 = 0; state >= 7: while u16 rec +0x27C != 0 the held word is replaced by itself & 0x2F0F
  with LEFT/RIGHT and UP/DOWN swapped (reversed-controls countdown, prev word +0x27A), M). **FUN_02012DA8** (every mode but wireless): P1 active record +0x26C /
  +0x26E / +0x270 = pad block 0x020DD4DC +0 / +2 / +4; when P1's action (+6) is 0 or 5: FUN_020098EC, record +0x264..
  +0x26A = TPData u16 {x, y, touch, validity} 0x020DE208, +0x263 = touch flags u8 0x020DE1F4 (bit 0 new touch, bit 1
  held, bit 2 released, bit 3 repeat). **P2 = the AI: p = FUN_0202DCE0(P2 active, P1 active)** returns a u16 struct:
  [0] → +0x26C, [1] → +0x26E, [2] → +0x270, [3] → +0x272, [4..7] → +0x264..+0x26A, u8 at +0x10 → +0x263 (AI state block
  u32 0x020DE3D4, struct at its +0x3C; per-character AI tables u32 0x020D801C[id]; called only from FUN_02012DA8). Wireless battles use FUN_020789A8 instead:
  both records from the link buffer u32 0x020E1144 (P1 +0x1D1FC/FE/200, touch +0x1D1F4..FA, flags +0x1D1F1, +0x1D20C →
  rec +0x274; P2 +0x1D21C/1E/20, +0x1D214..1A, +0x1D211, +0x1D22C) — needs scene 7's 0x1D260-byte link block. Directions
  are absolute (0x10 = right) for both sides.
- **Touch actions per side** (H, C): neutral handler FUN_0202CC70 with record +0x263 bit 0: FUN_02026E34(f) Team Arts
  (rect u16[4] 0x020D76B4 = 8, 144, 248, 184; team ki >= 200 % (mode 4: 20 %), >= 2 members), FUN_02026C00(f, 1) assist
  (call pose 0x28), FUN_02027164(f, 1, 0x14) tag request (ki >= 20 %, next alive fighter whose panel contains the
  touch; FUN_020281D8 performs it). All take the fighter and test the touch with FUN_02029084(side, rect) on THAT side's
  active record (+0x263 / +0x264 / +0x266). Panel rects for EVERY record of both sides (loader FUN_0202A40C, outer loop
  over both sides): +0x2D0 x0 = 8 + 80·k, +0x2D4 x1 = 88 + 80·k, +0x2D2 y0 = 0x10, +0x2D6 y1 = 0x88 (k = party slot).
  The AI taps rect + 0x20 (FUN_0202D66C support, FUN_0202D820 tag). So side 2 is driven by writing P2's touch fields.
  Lower-screen panels / highlight only for the local side u8 G + 0x1BCA9 (FUN_02012FEC; 0 in Free Battle, V): FUN_0201B78C
  (draw), FUN_0201CA60 (highlight, called by FUN_020281D8 only for that side).
- **Battle panel art** (H, ROM + render V portraits3.png): portraits 80x128 = /romdata/charselect/SubScrNBFC.bin
  (member i = character id i, 39 members: gkn gks ghk gho crr pic vgn vgs trk gtk frz frm gnu drg egh cel bmr bmj col
  com brl vga trn gtn ghn cey tsh dnd stn 1617 bvd cej zbdd bdk dbr srn neko nul1 nul2) + SubScrNBFS.bin (map, 16
  entries per row, cols 0-9, rows 0-15); battle palettes game/game_bg.arc #0x66 (16 rows: 0 plain, 1-3 white frame =
  active highlight, 4 / 7 dark, 5 / 6 other UI); the COLOUR look of the mockup's active Gohan = the same tiles with the
  palette /romdata/scene/common/CharFace.bin `<abbr>_face.nbfp` (V: gho renders exactly like the mockup). Team Arts /
  Touch! overlay = game/game_subbg.bin `e_pairatk.nbfc/.nbfs` (+ f/g/i/s languages). Support 26 (tsh) is the diagonal
  two-face portrait the mockup uses as the bench idea. P2's portraits are not loaded by the game (only the local side's).
- **Pause / battle end** (H, C): state 7: Start (pad block, any mode but 4, G+0x1BCAB != 0) → state 9 FUN_0201546C
  (A / B / Start only from the pad block; item codes 0xB/0xC → 2, 0xD/0xF → 3, 0xE → 4, 0x10 = command list); result 2
  in Free → next scene G+0x1BCAE = 3 (character select), 3 → 0xD, 4 → 6 (Mode Select) (Practice: 3). KO → states
  0x11 → 0x12 → 0x13: next scene by mode; Free: loser record u32 [teams + 0x11D4] (FUN_0202921C) side 0 → 0x14 (Game
  Over / Continue), else 10 (results). All leave through FUN_02001014(scene) after the teardown.
- **Wireless "human P2"** (H, C): exists only as the link input function FUN_020789A8 + scene 7's lockstep (FUN_02078BD8 /
  FUN_02079060 exchange, the battle frame runs only when both pads arrived: work +0x1D250). Not reusable without the
  link block; FUN_02012DA8 / FUN_0202DCE0 are the clean hook points.
- **Experiments in a scratch copy of the project** (V; /tmp/ssw2/mp_research/proj, debug code only there, section
  `# ---- MP RESEARCH (debug)` at the end of its qol_game.gd; runner runp.sh): (1) `mptint`: an f_0200aebc override
  draws the cursor block's outline object [0x020DE9B8+4] twice — GX COLOR 0x001F before the game's own draw, then at
  hex 5 ((85+0x16) << 12, (58+0x10) << 12) with COLOR 0x7C00, then COLOR 0x7FFF: Practice select shows a red outline on
  Goku and a blue one on Piccolo, pulse animation intact; both on one hex = the later colour on top
  (tint1_sheet.png, f3020 / f3080). (2) `mpai`: an f_0202dce0 override returning port RAM 0x027C1000 {pressed,
  released, held, 0, x, y, touch, 0, flags} with P2 held LEFT 4600-4700 and A every 40 frames: Free Battle P2 Goku
  stands still (action 0) without input (no AI), walks left (action 3, x 8256 → 8088) and fires ki blasts (0x24, ki
  100 % → 90 %, "3 RUSH") (ai1.log MPR / CHT lines, ai1_sheet.png).
- **Mockup layout** (docs/mp_mockup.png (local only, not in git: cut from the game's art) = 256x192 × 2.8, measured): P1 column A x 0-59, blue-grey bar 60-67, column B
  68-126, black divider 127-129, P2 column A 130-188, bar 189-196, column B 197-255; row line y 95; bench diagonal from
  (0, 158) to (59, 129).

## Session 1 part 27 findings (MP input / menu) — V = port verified, C = code read
Phases 3-4 of docs/MULTIPLAYER_DESIGN.md (device input, VS menu LOCAL / LAN, controller setup page). Evidence runs:
/tmp/ssw2/mpin (`run.sh NAME INPUTS CAP_FROM CAP_TO CAP_EVERY QUIT [flags]`; m1 = keys flow to scene 3, m2 = taps /
cursor clicks / device separation / mapping capture / B from scene 3 back to setup, m3 = two pad cursors + BACK; preview
states /tmp/ssw2/mpin/prev, `tools/qol_preview.tscn -- mp`).
- **FUN_0207B778 returns early** (H, C): results 1 / 2 / 3 return before its drawing tail (FUN_02011F98(work + 0x1068,
  0x37 / 200, 0x6E, flip) = the yellow selection frame, then FUN_0207A1F4(0) = message blink), so a swallowed choice
  must draw the tail itself (QoLGame `_mp_vs_tail`). Tap on the unselected picture only moves the cursor (iVar3 = 0);
  a tap on the selected one or A confirms (SE 5); Left / Right SE 4. V (m2: first tap → cursor LAN, second → LAN).
- **VS menu lower-screen boxes** (H, measured on vs1/p2820.png): HOST plate x 12-52 y 144-157, CLIENT plate x 203-243
  y 32-45 (white, rounded corners, black 8-px text); kanji outlines 親 x 30-90 y 66-126, 子 x 166-225 y 67-126; yellow
  picture rims left x 0-118 y 48-143, right x 139-253 y 50-141. Upper screen: title bar orange (251,162,0) y 25-40 up
  to x ≈ 205 (text "VS BATTLE" from x 43), message box interior x 11-244 y 59-148, stripes by y % 3: 0 → (130,97,56),
  1 → (113,89,40), 2 → (121,89,48); the game's text x 49.., y 74-131, 16-px lines.
- **Scene 0x11 exit with result 2** (H, C + V m1): state 2 → FUN_020026E4(0) (+0x33 = 2 = client), +0x18CB = 4, teardown,
  state 7 (fade FUN_02001D30), state 8 → FUN_02002738(1) (+0x32 = 1) → FUN_02001014(4). Redirected (port, session
  only) to scene 3 after FUN_02002738(0) (+0x32 = +0x33 = 0, party +0x40 = 0) and FUN_0200297C(0xB) (mode u32
  0x020DD514): V m1 probe `020DD4C4;020DD514` = 0x0211 / 2 at f3560 → 0x0003 / 0xB at f3620, Practice character
  select (both lists, D·P ∞) on screen. Leaving +0x33 = 2 would send the next scene-0x11 load to state 3 (client wait,
  wireless) — FUN_0207BA08 state 1 tests FUN_020026C4 — so both redirects into / out of 0x11 clear it.
- **Scene 3 (mode 0xB) B with no picks → FUN_02001014(0xC)** (H, V m2): redirected to 0x11; the loop then writes mode
  6 (FUN_0200297C(6), harmless); 0x11 loads (states 0, 1) and reaches state 2 ≈ 50 frames later (m2: B f3800 → state 2
  f3880), where the setup page reopens.
- **Fades** (M, C + V m1 f3600): scene fades use FUN_02001D30 / FUN_02001DA4 (per-engine fade records, layer mask 0x3F);
  the port overlay follows MASTER_BRIGHT (IO +0x6C, mode 2) and BLDCNT mode 3 / BLDY (IO +0x50 / +0x54) of the engine
  on each screen (POWCNT1 bit 15 set = engine A on top).
- **Port input facts** (H, V m2 `mpdbg` lines): keyboard events never carry a joypad device, joypad events carry their
  pad id: P1 keyboard + P2 fake pad 0 → raw key Down = `p1 080 p2 000` (f2993), pad 0 D-down = `p1 000 p2 080`
  (f3030), key N (KEYBOARD 2 A) with P2 on a pad = nothing; P2 switched to KEYBOARD → N = `p2 001`, M = `p2 002`; the
  capture on P2's mapping page took key Q as P2's A (then `p2 001` from Q). Input.parse_input_event key events (scripted
  `K<key>`) update Input.is_physical_key_pressed and reach GameDS._input (latched).
- Implementation (port, part 27): scripts/qol/qol_mp_input.gd (QoLMpInput: per-player device + key set + pad set,
  poll / latch / capture, [mp] keys in settings.cfg: devices_set, p1_device, p2_device, p<n>_<ds_action>_key / _pad —
  mappings are saved only once a player changed them; P1's follows CONTROLS until then), scripts/qol/qol_mp_menu.gd
  (QoLMpMenu: VS overlay, pages setup / map / drop / ready), QoLController `# ---- MULTIPLAYER MENU (part 27)`
  (mp_poll_p1, mp_latch, mp_frame, _mp_after: stage from scene 3 / 5 / 0, session end at scene 6), QoLCursor
  `player` 0 / 1 (red / blue, own pad), GameDS two hooks in _tick_begin + mp_latch in _input, QoLGame
  `# ---- MULTIPLAYER MENU (part 27)` (f_0207b778, f_02001014 redirect table of design section 2, session only, not for
  `mpbattle=1` debug sessions). DS input per stage: SETUP blank (both players → the page), stages in
  QoLMp.port_stages blank (+ mp.inject), else P1's word (+ inject); BATTLE also P2's START, both players ORed in scene
  state 9 and 0x0F-0x14, touch = QoLMpPanel.route(mp).
- Flags: `mp=1`, `fakepads=N`, `mpdev=a,b` (k / pad id), `mppad=F:DEV:b<n>|a<n>±:N`, `p2inputs=` (inputs= syntax, P2),
  `vcursor2` / `vcur2move` / `vcur2click` (P2's cursor; P1's takes vcursor / vcurmove / vcurclick), `mpdbg`.
- Off-identity (V): /tmp/ssw2/mpin/off.sh (copy of off23.sh) 21/21 PNGs + CHT lines to 5300 identical to /tmp/ssw2/btn,
  also with `mp=1` (offmp.sh: Mode Select + Free Battle path unchanged); intro cap.sh 10 2210 10: 221/221 identical.

## Session 1 part 27 findings (MP battle) — V = port verified, C = code read
Phases 1-2 of docs/MULTIPLAYER_DESIGN.md: P2 human input, MP battle lower screen, cheats for both players. Code:
QoLGame `# ---- MULTIPLAYER BATTLE (part 27)` (+ `_helped()` hooks in the cheat functions), scripts/qol/qol_mp_panel.gd
(QoLMpPanel), QoLController `mp_panel` (setup + after_step), QoLMp `latch` / `tap` / `debug_battle`. Evidence:
/tmp/ssw2/mpb (`run.sh NAME CAP_FROM CAP_TO CAP_EVERY QUIT EXTRA_INPUTS [flags]` = btnrun menu inputs; logs `MPB` lines
= both active fighters every 10 frames with `cheatdbg` / `mpdbg`).
- **P2 input through FUN_0202DCE0** (H, V t2): override returns port RAM 0x027C1000 {u16 pressed, released, held, 0,
  x, y, touching, 0; flags at +0x10}; edges per CALL (hit-stop frames do not call FUN_02012DA8's AI), presses latched
  (QoLMp.latch) so none are lost. `mpbattle=1 p2inputs=4600:A:4,4700:Y:4,4800:R:40,4900:B:40`: P2 action 0x24 at
  f4600 (ki 25600 → 23040), 0x1C at 4700, 0x0C → 0x0D at 4800/4820 (ki rising), 0x18 at 4900; P2 action 0 with no
  input from battle start (f3720) to 4600 (no AI). The CPU AI state / RNG simply do not advance.
- **Touch per side** (H, V t3/t4/t6): P2's touch fields with flags 3 (first call of a new touch) / 2 (held) / 4
  (call after release) act exactly like single player's: tag (P2 bench → action 0x26/0x27, active index 0 → 1,
  ki −20 %), support call (0x28, assists 7 → 6), Team Arts (0x30, ki 0xC800 → 0). P1's mapped point through the DS
  touch screen: tag, support (0x28), Team Arts (0x30). A tap during a non-neutral action is lost (the neutral
  handler only reads +0x263 in actions 0 / 5, also in single player); one assist on screen for BOTH sides (global
  slot teams+0x11E0: P1's call while P2's assist is out is refused, game rule).
- **Team Arts conditions** (H, C FUN_02026E34): opponent +0x250 & 0x400 clear, teams+0x1675 == 0, teams+0x11E4 == 0,
  team ki >= 200 % (mode 4: 20 %), member count (incl. the support) > 1, touch in 8,144-248,184, and FUN_02026548(f)
  finds a partner (sets rec +0x274 |= 0x100 and teams +0x11E4..+0x11F0). Goku + Vegeta (+ support 26) has none (V t3:
  no 0x30), Goku + Piccolo has (V t4).
- **Panel lighting rules of the game** (H, C): FUN_02027950 (spend) / FUN_02027A40 (gain), local side only:
  ki >= 0x1400 → FUN_0201C7A8(1) = bench fighter panels (ids < 0x1A, globals +0xCE0[3]) palette row 0, below →
  row 7 (dark: no tag possible); ki >= 0xC800 and active rec +0x274 & 0x100 → FUN_0201C8F4(1) = Team Arts bar
  (layer 4 region 0x88.., 0x100 x 0xC0) palette row 5 (lit), else row 6. FUN_020067CC(layer, row, …) = set the
  palette nibble of a map region. The MP panel applies the same rules to both sides.
- **Portrait art** (H, ROM V): CharFace.bin `<abbr>_face.nbfp` = game_bg.arc #0x66 row 0 except index 0 (7C1F) —
  the "colour" look of the mockup is simply the normal battle palette (the panels are drawn in the yellow manga
  style; CharFace256.bin holds small 256-colour faces only, ~72x32). Portrait tiles carry a 1-px frame of index 1
  (412 px: black in rows 0 / 4-7, white in rows 1-3 = the game's active highlight). Palette rows (#0x66): 0 plain,
  1-3 active (white frame), 4 / 7 dark, 5 Touch! lit (plate 0x027F, diamond 0x001F), 6 Touch! dim (0x014F, 0x0010).
  e_pairatk (game_subbg.bin, map palette nibble 6): diamond centre (144, 29) radius ~16 incl. the black rim, letters
  "Touch !" x 166-223 (runs 166-184 "To", 186-194, 196-203, 205-213, 218-223 "!"), rows 20-38.
- **MP panel** (V t2-t9): opaque Node2D over the lower screen (z 80; boss skulls 90 and pad cursors 1000 stay above),
  mockup layout (P1 A 0-59, bar 60-67, B 68-126, divider 127-129, P2 A 130-188, bar 189-196, B 197-255, line y 95,
  bench split (0, 62)-(w-1, 33) local, 2 px). Fades follow the lower engine's MASTER_BRIGHT (t9: KO fade-out dims the
  panel with the top screen; the panel goes when battle_on_screen() ends). Tap map: bench part → that record's
  panel-rect centre (48 + 80·slot, 76), support box → the support's rect centre, Touch! plate → (128, 164).
- **Cheats in MP** (V t5, t7, t8): see the table in the final report / MULTIPLAYER_DESIGN 3.8. infinite_ki +
  infinite_health + infinite_assists: P2 ki 51200, HP 13000 and assists 7 unchanged through ki blasts, X dash, P1's
  hits and a support call; chaos_shuffle: both sides swap independently (P2 own timer, same frame as P1's, CHT
  shuffle #1/#2); triple_ki: P2's blasts tripled; hard_mode: both players take double damage; random_characters:
  both parties random (12 vs 17), real parties back after the loader; one_hit_ko: P2's ki blast KOs P1.
- Off-identity (V): /tmp/ssw2/mpb/off.sh 21/21 PNGs + 1382 `^CHT f` lines to 5300 identical to /tmp/ssw2/btn;
  intro cap.sh 10 2210 10: 221/221 identical.

## Session 1 part 27 findings (MP select / stage / loop) — V = port verified, C = code read
Phases 5-7 of docs/MULTIPLAYER_DESIGN.md (two-player character select, stage select, battle loop, polish). Code: QoLGame
`# ---- MULTIPLAYER SELECT (part 27)` (overrides f_0206cc94 → _mp_select, f_0206ed18, f_0206a3d8, f_02069990, f_0207215c,
f_02071e64, f_02070718; hook lines in f_0206cc94 / f_0206abb0 / f_02001014), scripts/qol/qol_mp_select.gd (QoLMpSelect:
1P / 2P tags, READY plates, stage states, winner band), QoLController `_mp_sel_taps` (per-player new taps), QoLMpPanel
`mark_at` (boss skulls) + VS-intro panel. Evidence: /tmp/ssw2/mpsel (`run.sh NAME P1INPUTS P2INPUTS CAP_FROM CAP_TO
CAP_EVERY QUIT [flags]`, logs with `mpdbg`: `MPS` select / stage lines, `MP scene a -> b ... heap free [total, largest]
archives n cache n`; sheets *_sheet.png / a_sel*.png / a_bat.png / b1_*.png / b2_sheet.png / c_*.png / d_sheet2.png).
- **Select key repeat** (H, C FUN_0206CA2C): held Up/Down / Left/Right counters u32 0x020DEA18 / 0x020DEA1C, "repeating"
  flags u32 0x020DEA20 / 0x020DEA28; a press repeats after 0x13 frames, then every 12 (written into the pressed word
  with FUN_020013F4, which REPLACES u16 0x020DD4DC). Pad block 0x020DD4DC: u16 pressed, released (+2), held (+4)
  (FUN_02001230 / FUN_02001214 / FUN_020011F8). Swapping these (and the cursor bytes 0x020DE9B8 +0x57..+0x5B, side byte
  0x020DEA2C, team 0x020DE64C, TPData 0x020DE208 / flags u8 0x020DE1F4) around one FUN_0206CC94 call per player runs
  the game's own select logic per player (V a: moves, tab changes, SP tab, taps, refusals, picks).
- **Select touch rects** (H, ROM + V b1): hex rects u16 {x0, y0, x1, y1} at 0x020D0668 (8 bytes per hex; Goku hex 4 =
  45,40-82,72, Piccolo 5 = 89,58-122,90, Broly 20 → hex 11 = 171,94-209,126); DP tab rects 0x020D0628 (DP1 0,2-40,34,
  DP2 216,20-256,54, … SP 216,128-256,162); READY? rects are u8 {x0, y0, x1, y1}: GO 0x020D05CC = 131,43-171,87, BACK
  0x020D05C8 = 75,98-117,142. One tap on a hex = move there + pick (FUN_0206CC94 returns the id).
- **The select draw opens READY? itself** (H, C FUN_02069990 + V f): with READY? closed it scans the current side's team
  s32[3] 0x020DE64C: any -1 → FUN_0206A748(0) and the overlay's animation counter reset; all three filled →
  FUN_0206A748(1). So a full team shows READY? one frame after the third pick even when FUN_0206ED18 returned 0; the port
  hides the team while it draws in an MP select (the first try showed P1's full team opening READY? alone).
- **Select sounds** (H, C FUN_0206D57C): 0 → SE 0x12 (pick), 1 / 2 → 4 (cancel / GO), 3 → 10 (READY?), 4 → 0xD (refused).
- **FUN_0206ED18 result** (H, C): 0 accepted; 1 = accepted and the side's DP total (FUN_020671F4) equals the maximum
  (FUN_02066074) → the loop shows READY? (FUN_0206A748(1), SE 3); -1 = DP exceeded or the side's 3 slots full (buzzer).
  The CANCEL plate (FUN_0206CC94 → -2 / -10) makes the loop pop the last pick of BOTH sides (FUN_0206EABC) — the port
  turns it into the tapping player's own B.
- **Cursor objects** (H, C FUN_0206A3D8 + V): +4 = outline, **+8 = its pulse ring** (a larger hex drawn right after it;
  the two alternate visibly — not a "DP label" as noted in the research), +0x28 = DP digit plate: frame word = u32
  [0x020DE9C4 + (u8 0x020D0478[id] − 1)·4], drawn only if s8 0x020DB608[id] != 0, at (hex x + 0x16, hex y + 0x23), z
  0x69000. All three are drawn once per player (GX COLOR before +4 / +8: P1 0x10DF, P2 0x7D86, same fighter 0x7CD8).
- **Scene 3 re-entry clears all picks** (V a / b2: after a battle and after pause "Return to Character Select" both
  lists are empty and the cursor is on Goku).
- **Stage cursor colour** (H, C FUN_02071B90 + V): level s32 0x020DC094 ping-pongs 0..31 (direction s32 0x020DEAD0);
  all 15 colours of the cursor palette = FUN_02070718(level) (yellow ↔ white), uploaded every frame to texture palette
  +0x420 (0x20 bytes, FUN_0200C3C4(1, buf, 0x420, 0x20)). A yellow texture × blue vertex colour is nearly black, so in
  an MP stage select the port returns white from FUN_02070718 and draws the pulse as the tint's brightness.
- **Stage icon table** (H, ROM): u16 {x, y} at 0x020D0768 stride 8 = top-left of the 72 x 32 icon: (2,10) (58,27)
  (129,27) (185,10) / (2,44) (58,61) (129,61) (185,44) / (2,78) (58,95) (129,95) (185,78) / (2,112) (58,129) (129,129)
  (185,112); touch rects u16 {x0, x1, y0, y1}: 0x020D07E8 (icon bodies, e.g. icon 3 = 200-252, 12-30) and 0x020D0868
  (the pointed ends). Cursor object size +0x10 / +0x12 = 0x48 / 0x20 (0x47 / 0x1F for icons 12 and 15, FUN_02071F18).
- **Stage top screen** (H, C FUN_02072FBC): the name / description of icon s16 0x020DEB2C is reloaded only when the
  "moved" byte (FUN_02071C8C(1) writes it, FUN_02071CA4 reads it) is set — writing the icon alone does not update it.
- **Stage exit** (H, C FUN_020718C8(1) + V): after the confirm the loop runs 60 more frames of FUN_0207215C /
  FUN_02072FBC / FUN_02071E64 (fade), results ignored. FUN_02071E64 draws icons [u32 [0x020DEAE8 + 8] + i·0xC] × 16, the
  bars [0x020DEB30 + 0xC / + 0x10], the cursor [0x020DEB0C + 0xC] (columns 0 / 2) or [+0x10] (1 / 3), the confirm
  objects when FUN_02071C70() == 1, then FUN_0200AB18.
- **Battle states in the MP (Free, mode 5) battle** (V a, u8 0x020DD4C5): 1 load (~3 frames), 2 VS intro (~260 frames,
  the game draws PLAYER 1's single-player panel; the team pointer u32 0x020DE3D0 is still 0 there, V e, and with RANDOM
  CHARACTERS the party block holds the random teams — the MP panel shows both teams from the party block then), 3, 4, 5, 6, 7 fight, 9 pause, 0x11 after the KO (loser u32 [teams +
  0x11D4] valid: the winner band reads it), 0x13 → exit (FUN_02001014(0x14) → redirected to scene 3).
- **Loop stability** (V b2: 4 rounds setup → select → stage → battle (KO) → select, the 4th left through pause "Return
  to Character Select"): every round exactly 2123 frames; at every scene change the same numbers each round: 0x11 → 3
  heap free 2490280, 3 → 5 2946192 (largest 2760224), 5 → 0 2971000 / 2789932, 0 → 3 1546344 / 1327848; open archives
  0, file-cache entries 0 (5 → 0: 6 from round 2 on, every round).
- **Scene 0x11 while loading** (V d): during states 0-1 the screens are swapped / VRAM not set up; opening the setup page
  then (DSDisplay.set_layer_keep) hid the wrong screen's layers (green backdrop on the upper screen until the page
  closed). Reopened from the select, the page now opens with the first frame of state 2 and fades in with the scene.
- **Cheats in the MP select / battle** (V c / e): BOSS CHARACTERS: the picking player's L (QoLMp.held) — P2's Broly
  picked with L → skull on the ENEMY list, `CHT boss fighter 2107eb0 id 20 level 3 hp 26000` (P2's team block), skull
  on P2's active box of the MP panel (QoLMpPanel.mark_at); SAME CHARACTERS: P1 Broly + Broly; RANDOM STAGE: `CHT random
  stage 9 -> 6`; pause "Return to Menu" → scene 6 → session ended (Mode Select with the normal controls).

## Session 1 part 27 findings (MP QA) — V = port verified, C = code read
QA of the whole LOCAL MULTIPLAYER flow. Evidence: /tmp/ssw2/qa (`run.sh NAME P1IN P2IN FROM TO EVERY QUIT [flags]`, mp=1
mpseed=7; q1.sh / q2.sh / q3.sh / s2.sh full-flow runs, s1 = settings toggle, a1 = run a's inputs + one_hit_ko; sheets
*_s*.png / a1_sheet.png; plate_before.png / plate_after2.png). Code: QoLGame `# ---- MP QA (part 27)` (end of the file),
hook lines in f_020225c8 / f_0206abb0; QoLMpPanel `_plate` letters; QoLCursor `half`; QoLController `_top_vs`.
- **Battle-end banner WIN / LOSE** (H, C FUN_0201825C / FUN_020163F0 + V a1, q1, q2): the KnockOut!! / TIME UP!! banner
  names the result for the LOCAL side u8 G+0x1BCA9 (FUN_02012FEC; 0 in Free Battle = PLAYER 1). KO (battle state 0x11)
  sub-state 1 counts u16 G+0x1BCA4 from 60; at 0 it spawns FUN_020225C8(P1 active record, kind, G+0x1BCB8, [G+0x1BD98],
  0): kind 0 WIN / 5 PERFECT (FUN_02029764(side) low word != 0: the side's HP is 100 % (FUN_02029F4C) and no member
  has +0x254 & 0x200) when the winner (FUN_02029260 = teams+0x11D0; loser FUN_0202921C = +0x11D4) is the local side,
  else 2 LOSE. Time over (state 0x0F, from state 7 when u16 timer G+0x1BCA6 reaches 0, decremented every 6th frame
  via G+0x1BCA8, DAT_02013C30 = no limit) sub-state 1: kinds 1 WIN / 3 LOSE / 4 draw (HP % equal; G+0x1BE60 = 4); its
  sub-state 6 adds kind 0x1C (PERFECT) for a local winner only. Sub-state 3 of both: camera pan FUN_02019104(fighter,
  0x1E) to the winner when local, else to the loser (FUN_02019104 copies the camera's current +0xC/+0x10 to +0x14/+0x18
  and sets target +0x1C/+0x20 = fighter x/y >> 8, mode 2). G+0x1BE60 = result code (0 local win / 1 loss by KO, 2 / 3
  by time, 4 draw; read by the score code FUN_020125xx). Fix (MP battle only): the banner kind is changed at the spawn
  frame (2 → 0 or 5 as the game gives a local winner, 3 → 1) and the sub-state-3 pan goes to the winner. V: a1 (P2 wins
  by KO untouched) "MP f5345 battle end banner kind 5" → PERFECT + Piccolo's victory pose (was LOSE + Goku lying,
  /tmp/ssw2/mpsel/a_bat.png f5400); q2 (time over poked: `poke=4600:0211BCEE:1`, Broly ahead) kind 1 = TIME UP!! WIN,
  camera on Broly; q1 (P1 wins) kind 5 unchanged path.
- **Touch ! plate** (V plate_before.png → plate_after2.png): the e_pairatk letters are 51 px of ink (T+o 19, u 9, c 8,
  h 9, ! 6) + 4 gaps; on the 59-px plate they filled x 2..56 over the inner frame lines (the "!" on the line). Now each
  glyph run is condensed by dropping columns equal to their left neighbour (stems 4 → 3 px) to at most 47 px incl. 1-px gaps and
  a 3-px space before "!" ("Touch !" as on the game's bar): ink x 5..52, 2-3 px clear of the inner frame lines (x 2 / 56).
- **MP select grey-outs** (H, C FUN_0206ABB0 + V q1 f5260 / f5300): entries u32 [0x020DE870] + id·0x28 (ids 0..0x25):
  +4 object (its +4 = frame variant), +0x20 tab + 1, +0x21 normal variant, +0x22 grey; greyed for the current team
  0x020DE64C: picked, family (FUN_0206A688 + FUN_02068E4C), second support (FUN_02066088), DP over (FUN_02070740). MP:
  run once per player still picking (not READY; both if both are) with that player's side / team, a face stays grey
  only when all of them are refused it (V: Piccolo picked by both → grey; after P1's START only P2's own greys).
- **Pad cursors in an MP battle** (V q1 f4780: P2's cursor left at (105, 74) from the select stood on P1's half, and the
  panel routes taps by half, so its click would act for PLAYER 1): while the MP panel is shown each player's cursor is
  kept on its own half (q2 `vcursor2=60,100 vcur2click=4500:4` → "tap p2 at (128, 100)").
- **Debug-log errors** (V q1.log: 392 `p_offset` errors with `cheatdbg` / `mpdbg` in every VS intro): the MPB debug line
  read team blocks at u32 0x020DE3D0 = 0 before FUN_02013D60 loads them; skipped in the intro now (q2 / q3: 0).
- **Mode Select VS BATTLE tile** (V s1 f2910 → s2 f2600): with MULTIPLAYER on its top box now says what the tile opens
  (LOCAL / LAN) instead of the game's "Battle via wireless communication…" (QoLTopInfo, as for the PORT tile).
- Checked without findings (V): settings toggle MULTIPLAYER OFF in the menu → VS BATTLE = the game's HOST / CLIENT screen
  (s1); settings.cfg [mp] round trip (enabled, devices_set, p<n>_device, p2_* mappings kept); setup page: device
  cycling (swap of a pad), dropdown by tap, mapping capture (raw key) + DEFAULT, READY → NO (B) → READY by P2's pad →
  YES by tap (s2); select by taps / pad cursor / SP tab / READY? GO by tap; stage roulette; P2 support tap + ASSIST
  SPAM, P1 tag tap, P1 Team Arts tap (INFINITE KI lights both plates); pause by P2's / P1's Start, Continue by Start,
  Return to Character Select, Return to Menu → Mode Select with the session ended and normal controls (q1, q3); B
  chains select → setup → LOCAL / LAN (q1); BOSS CHARACTERS (P2 L + tap Broly → boss level 3), RANDOM CHARACTERS,
  MIRROR MODE (P2's Right moves right on screen), BOMB RAIN, CRT, DAMAGE NUMBERS, FLASHY KI, BLOOD, AFTERIMAGES: no
  SCRIPT ERROR. INPUT DISPLAY shows PLAYER 1's pad only (it reads the DS pad word) over the panel's top strip.
- Off-identity (V): qa/off.sh and qa/offmp.sh (mp=1) 21/21 PNGs + 1382 `^CHT f` lines to 5300 identical to
  /tmp/ssw2/btn; intro cap.sh 10 2210 10: 221/221 identical to /tmp/ssw2/intro.

## Session 1 part 28 findings (MP select / panel) — V = port verified, C = code read
Evidence: /tmp/ssw2/mp28 (`run.sh NAME P1IN P2IN FROM TO EVERY QUIT [flags]`, mp=1 mpseed=7; r1 = bug before the fix, A =
same inputs after, B2-B4 = SAME CHARACTERS + two supports + battle taps, C = SAME / BOSS CHARACTERS + per-player DP;
sheets r1_sheet.png, A_sheet.png, B_sheet.png, B2_sheet.png, B4_sheet.png, C_sheet.png, plates_before_after.png).
Code: QoLGame `# ---- MULTIPLAYER SELECT (part 27)` (_ms_side, _ms_fighters, _ms_order, _mp_select), `# ---- MP QA` (_mp_grey),
`# ---- MP SUPPORTS (part 28)` (+ hook lines in f_02026c00 / f_020277ac / f_0206abb0), QoLMpPanel (supports, _plate).
- **Per-side DP slot bytes** (H, C FUN_020671F4 / FUN_02066CA4/94/84 / FUN_0206DCE8 + V r1 → A): the select keeps the
  DP of the CURRENT side's three slots in u8 0x020DE7C8 / 0x020DE7E4 / 0x020DE800 (FUN_02066CA4 / 94 / 84 write them,
  FUN_020671F4 = their sum); FUN_0206ED18 writes slot k's byte for side 0 AND side 1 and refuses when max DP (u32
  0x020DE638 & 0xFF; Practice 0x14 = 20, drawn as ∞ by FUN_0206F67C / FUN_0206F404) < DP(id) + sum; FUN_0206ABB0 greys
  every fighter with max < DP(id) + sum (and FUN_02070740(id)). DP of id = u8 0x020DBC34 + id·0x1C (ED18's table; e.g.
  9 / 17 = 7, 15 / 2 / 20 = 6, supports 1-4). The game reloads the bytes from the picks whenever its side changes
  (scene loop FUN_0206DCE8: GO with side 0, B / CANCEL paths). **Cause of the "all boxes black" bug** (V r1 f3360 /
  f3429): the MP select swapped the side byte and team 0x020DE64C per player but not these bytes, so after P1's
  9 + 17 + 15 (= 20) P2 saw a 20-DP team: every face grey (P1 being READY, only P2's greys counted) and every P2 pick
  refused (`pick 2 for p2 -> 4294967295`); a tab change re-lit the row (FUN_0206ADB8) until the next grey pass. Fix:
  _ms_side(p) loads player p's bytes (V A: P2's Gohan accepted at f3429, the DP6 row lit after P1's 20-DP team; C: P1
  at 14 DP refused a DP7 pick while P2 picked one; per-player greys of the DP7 row).
- **Supports per team** (H, C FUN_0206CC94 / FUN_02066088 / FUN_02071374): the game allows ONE support (FUN_02066088 =
  any team entry >= 0x1A refuses the next support; the grey pass too); SAME CHARACTERS hides the team from these tests,
  so a team can get 2-3 supports (single player too). FUN_02071374 (stage exit) only swaps a support out of slot 0 and
  out of slot 1 when slot 2 is a fighter: [S, S, F] → [S, F, S] = a support as the first active fighter. MP rules now:
  a support pick is refused (buzzer) when the player has no fighter and two entries (V B f3509), START needs a fighter
  (V B f3540), GO puts fighters first (_ms_order, V B2 `p2 team order [32, 33, 17] -> [17, 32, 33]`), so an MP team
  is 1-3 fighters + 0-2 supports. Greys follow (V B f3480: supports grey for P2 after two supports).
- **Two supports in battle** (H, C FUN_02026C00 / FUN_020277AC + V B4): FUN_02026C00(f, touched) returns 0 unless the
  touch (FUN_02029084(side, rect): side's active record +0x263 bit 0, +0x264 / +0x266) is inside EVERY support
  record's rect (+0x2D0 x0, +0x2D2 y0, +0x2D4 x1, +0x2D6 y1) → two supports are never callable by touch (also in single
  player); FUN_020277AC puts the LAST support record (k < count u8 team+0x8C9) in the assist slot teams+0x11E0. The
  loader's panel rects of two supports are not in party order (B2: record 2 = id 32 has the slot-1 rect 88-168,
  record 1 = id 33 the slot-2 rect). Port (MP battle only): the call is tested against the touched support's rect
  (the other supports' rects temporarily = it), the arrival with team+0x8C9 cut to k + 1 (V B4: right half → `p2
  calls support slot 2 (id 32)` → `support arrives: slot 2, assist record id 32`; left half → slot 1 / id 33, Vegeta
  on screen f5380; a call while the other assist is out is refused as in the game, f5099).
- **MP panel** (V B2 / B4 / A / C): two supports → the support box split in half (29 px | black line | 29 px, each the
  portrait's middle columns around x 40), each half mapped to its own record's rect centre; 1 / 0 supports drawn as
  before (A f4680, B2 P1 side). Touch! plate redesigned from e_pairatk (game_bg.arc #0x66 row 5 lit / 6 dim: 3 plate,
  2 black, 8 / 9 letter anti-alias, 10 darker plate, B diamond): outer line + bevel (0x033F / 0x01B2 light, row index 8
  dark), the button's inner groove line with its steps, chevrons, diamond (player colour core with light / dark facets
  + white glint, 3-px black ring, plate halo, 2-px black contour), "Touch !" condensed to 45 px (ink-equal columns
  dropped) 2 px clear of the groove, accent bar in the player colour; pressed (a touch held on it): content 1 px
  down-right, bevel inverted, body row index 10 (V B4 f5420 P1 lit pressed + Team Arts cut-in, f5480 P2 dim pressed).
- Off-identity (V): mp28/off.sh and mp28/offmp.sh (mp=1) 21/21 PNGs + 1382 `^CHT f` lines to 5300 identical to
  /tmp/ssw2/btn; intro cap.sh 10 2210 10: 221/221 identical to /tmp/ssw2/intro.

## Session 1 part 28 findings (MP cheats / weird QA) — V = port verified, C = code read
QA of the cheats and WEIRD settings in LOCAL MULTIPLAYER battles with player 2 acting. Evidence: /tmp/ssw2/q28 (`run.sh NAME
FROM TO EVERY QUIT P1_EXTRA_INPUTS [flags]` = btnrun Free Battle Goku vs Goku; `runt.sh` the same with poked teams P1 Goku +
Vegeta + support 26, P2 Goku + Piccolo + support 26; `sheet.py` / `grid.py` contact sheets). Code: QoLGame `_shuffle_icon`
(CHARACTER SHUFFLE section), `_stage_regs_defer` / `_stage_regs_apply` + hook lines in `_stage_swap` / f_02006518.
- **Face icon upload queue** (H, C FUN_02010FB4 / FUN_02010AE0 + V): both only queue {source, VRAM destination, size} (texture
  queue mgr +0x7AC, palette queue +0x7AD, ≤ 32 each, mgr = u32 0x020DE380); the data is read from the source at the next VBlank
  (FUN_0201098C). FUN_02010FB4(sprite, key, src) first looks the key up (FUN_02010900): a VRAM block already holding that key
  is SHARED (refs + 1, the sprite's old block released) and nothing is uploaded; else the sprite's own block (refs 1) is
  re-keyed, or a new one allocated when it is shared, and the tiles are queued. The life-bar face icon (rec+0x290, key
  (2·id & 0xFFFFF) | 0x40000000, palette slot u16 rec+0x298) is therefore shared by both sides when they show the same face.
- **Bug: MP shuffle swaps showed the other player's face icon / palette** (V; user report "P2 Frieza → Cell: the top-right
  icon used Frieza's palette for a moment"). In an MP battle both sides' shuffle timers start together, so P1 and P2 usually
  swap in the SAME frame (fighter update order: P2's record first, then P1's: CHT shuffle #1 = P2). `_shuffle_icon` copied the
  new face's tiles / palette to one shared scratch buffer (0x02710100 / 0x02711100) and queued them; the second swap of the
  frame overwrote it before the VBlank, so both icons got the second swapper's face (c1: P2 Fat Buu shown for P1 Broly; c5:
  P1 Frieza → Cell, P2's icon Frieza / Cell too), and when the key lookup made a side reuse the other side's block (tiles
  right, no upload) only its PALETTE came from the overwritten buffer: c6 (shufseed=38 port f4218) P2 22 → 14 shows
  Android 18's face in Metal Cooler's (P1 14 → 19 the same frame) colours = the user's symptom. Wrong until the next swap of
  that side (≤ 1 s in CHAOS SHUFFLE). Single player never swaps two records in one frame. Fix: one buffer per side (P2 at
  +0xE100 / +0xF100). After: c4 (seed 605: P1 Frieza → Cell, P2 Kid Buu → Fat Buu), c7 (seed 38), k1 (CHARACTER SHUFFLE,
  same-frame swaps), m6 (14 chaos swaps + a stage swap): every frame's icons match the fighters, tiles and palette change
  in the same frame. SP chaos s1 (f4160): already clean, unchanged.
- **Bug: one garbled frame at every STAGE SHUFFLE swap** (V, SP and MP). FUN_0201C150 writes the display registers at once
  (FUN_020A5224 → DISPCNT BG mode, BG3CNT 0x0400000E, FUN_020A535C → DISPSTAT bit 4 HBlank IRQ, fog / DISP3DCNT via the 3D
  loader, FUN_020A6E00) while its BG chars / maps / palettes (FUN_02006E50 / FUN_02006B68 / FUN_02006C6C queues, BG manager
  +0x180) and textures reach VRAM only at the next VBlank. The port draws a frame's scanlines after the frame's logic and
  before the next VBlank handler (DSMachine: lines 193-262, 0-191, then park + VBlank IRQ), as the DS scans out while the
  logic runs; so the picture after the swap frame had the new BG mode over the old stage's VRAM (g2 p4333, 14 → 12: purple
  checkers in the sky; m6 p4335, 3 → 12: rays). Fix (`_stage_regs_defer`): the swap's changed register bits in IO 0x000-0x003,
  DISPSTAT bit 4, 0x008-0x00F, 0x060-0x063, 0x330-0x37F are put back and applied by f_02006518 (inside the battle VBlank
  handler FUN_02013030) right after its BG uploads (once the BG queue count is 0). V g3 (14 → 12: "CHT stage registers
  deferred: 0:1/1 4:10/10 e:0/80 f:60/60 60:80/80 61:a/3a 358.. 35c.."): p4333 = the old stage complete, p4334 = the new one
  complete; g4 (12 → 14, mode 1 → 0, fog off): same. A normally loaded stage 12 (g5, party stage poked) has the same white
  foreground rock seen after the swap.
- Checked in MP battles without findings (V, logs `MPB` / `CHT`, no SCRIPT ERROR in any run): hard_mode (both take ×2: ki
  blast 864 each way, m5), no_cooldown + attack_spam (P2's and P1's Y chains `SPAM restart`, `SPAM hit` pushes, m5),
  infinite_ki (both 51200), infinite_assists + assist_spam (P2 support call act 0x28, assists stay 7, P2's copies on
  screen), triple_ki (P2's blasts tripled), ki_homing (P2's blasts hit), P2 tag (act 0x26/0x27 → Piccolo) (m1), one_hit_ko
  (P2's ki blast KOs P1 for 432, P1's next member tags in) + KO CONFETTI + DAMAGE NUMBERS (m7), chaos / character / stage
  shuffle + random_music + random_stage together (m6), FLASHY KI (P2's charge aura and blast trails), RAINBOW KI, BLOOD,
  DAMAGE NUMBERS on P2's hits (m1), GAME BOY (covers the MP panel too), 2ND FIDDLE (P1 mirror, P2 normal palettes: `CHT
  fiddle side 0 … mirror`, `side 1 … normal`), INPUT DISPLAY (P1's pad only, known), DETAILED SHADOWS, zoom 4 (m3), BEVEL,
  TOUCH FUZZY, MIRROR (P2 drawn on the left, HUD flipped as in single player), CRT, EPIC (m4), AUTO SKIP (m7). Afterimages
  (both sides' records are in `_ai_frame`): none on the R + direction dash of either side in m7 (same for P1: not MP-specific).
- Notes (not fixed): `chaosat=` (debug) keeps one list for both sides, so in an MP battle P1's tick pops the due frame and
  P2 never swaps with it. In an MP battle `_shuffle_panel` still redraws the game's own (hidden) lower-screen panels for P1's
  swaps.
- Off-identity (V): q28/off.sh and q28/offmp.sh (mp=1) 21/21 PNGs + 1382 `^CHT f` lines to 5300 identical to /tmp/ssw2/btn;
  intro cap.sh 10 2210 10: 221/221 identical to /tmp/ssw2/intro.

## Session 1 part 29 findings (SAME CHARACTERS team rules) — V = port verified, C = code read
Single-player team rules with SAME CHARACTERS (Free Battle / Practice select scene 3 FUN_0206DCE8, Z-Battle team select
scene 4 FUN_02066558; both call FUN_0206CC94 + FUN_0206ABB0). Evidence: /tmp/ssw2/sct (`run.sh NAME INPUTS FROM TO EVERY
QUIT CHEATS`; inputs in *.in; before = old code, A = keys, B = taps + BOSS CHARACTERS, C = Z-Battle, G3new / G3old = three
Gokus new vs old code; sheets before_b.png, A_sel.png, B_sel.png, C_sel.png). Code: QoLGame `# ---- same characters`
(`_hide_fighters`, SP paths of f_0206cc94 / f_0206abb0; the MP select keeps `_hide_team` and its own rules).
- **Select tests** (H, C FUN_0206CC94 / FUN_0206ABB0 / FUN_02066088 / FUN_0206A688): key A path: duplicate (team s32[3]
  0x020DE64C), then for id >= 0x1A FUN_02066088 (any team entry >= 0x1A = refuse), then family FUN_0206A688 (u8
  0x020D04C8[id] == family of a team entry); SP-tab tap path (10 rects, hex indices u8 0x020D05D8, ids u8 0x020D05E4,
  hex rects u16 {x0,y0,x1,y1} 0x020D0668): duplicate, family, FUN_02066088; DP-tab hex taps (tab hexes u8 0x020D05F0,
  ids 0x020D060C, 4 per tab, 0x10 = end) carry fighters only and have no support test. Refusal = -1 → scene 3 loop
  FUN_0206D57C(4) / scene 4 loop SE 0xD. The grey pass greys every support on the SP tab while FUN_02066088 is true.
  Family bytes: fighters 0-15, supports 26-37 = 17-31 (all distinct), so a support in the team never blocks a fighter.
- **START / auto confirm** (H, C FUN_0206A6FC + V): START opens READY? only when the current team holds an id 0-25
  (both loops); scene 3 also opens it when the 3 slots are full (FUN_02069990) or FUN_0206ED18 returns 1 (DP total ==
  max, FUN_02066074); scene 4 when the DP total == max and FUN_0206A6FC. With one support at most, every way to confirm
  needs a fighter (V A f2940 / B f3260 / C f2820: START with only a support → no READY?).
- **Why two supports were wrong in single player** (V before: `select 32 33 12` → party `p1 33 12 32` = support in party
  slot 0; FUN_02071374 only moves one support; the loader then made Ginyu active, but the lower-screen panels were
  Bardock (support) | Ginyu | Zarbon & Dodoria). C: the game's SP panel draws every member record as its own portrait at
  its rect (+0x2D0..+0x2D6), so two supports are shown, but FUN_02026C00 calls only with the touch inside EVERY support
  rect (never for two) and FUN_020277AC sends the last one. The part-28 `_ms2_call` / `_ms2_arrive` hooks would work for
  side 0 without any split (separate rects), but are gated to the MP battle in the ASSIST SPAM hook lines (another
  section); the simpler game rule was chosen.
- **Rule now** (V A / B / C): with SAME CHARACTERS the single-player select hides only the FIGHTERS of the team from the
  game's tests (`_hide_fighters`): fighters may repeat, a support stays visible, so the game's own one-support test refuses
  a second support (`CHT f2919 same characters: pick refused (cursor 33, team [32, -1, -1])`, buzzer) and greys the SP tab
  (A f2860, B f3200, C f2760). Teams are 1-3 fighters + 0-1 support, and the game's commit puts the fighter first: A
  `select 32 12 12` → party `p1 12 12 32`, P2 `33 12` → `p2 12 33`; B (taps, L-held bosses) `34 20 20` → `20 20 34`,
  `CHT boss fighter 21075c8 id 20 level 3 hp 26000` ×2, P2 `35 12` → `12 35` + boss Ginyu level 1 (skull on the ENEMY
  list); C (Z-Battle) `34 0 0` → party `0 0 34` (VS screen Goku, Goku, Dabura).
- Unchanged (V): three Gokus with SAME CHARACTERS: 41 PNGs + 402 CHT lines identical between the old and the new code
  (G3old / G3new); cheat off: sct/off.sh 21/21 PNGs + 1382 `^CHT f` lines to 5300 identical to /tmp/ssw2/btn; intro
  cap.sh 10 2210 10: 221/221 identical to /tmp/ssw2/intro. MP select unchanged (still 1-3 fighters + 0-2 supports).

## Session 1 part 29 findings (MP battle: touch light, dual assists) — V = port verified, C = code read
Evidence: /tmp/ssw2/mp29 (`run.sh NAME FROM TO EVERY QUIT P1_EXTRA_INPUTS POKES [flags]` = btnrun Free Battle as an MP battle
(`mpbattle=1`) with the party block poked at 3520; taps on P2's half of the panel go to P2; `rr.sh` = the qa/q1 full MP flow with
two battles and poked parties; it lost sync in the 2nd select, so `rr2.sh` = two debug Free Battles: pause → Return to
Character Select with both assists out, picks again, battle 2). Sheets: r1_sheet.png (bug), t2_sheet.png / t1_sheet.png (fix), d1_sheet.png / d1_zoom.png,
s1_sheet.png, s2_sheet.png, k1_sheet.png / k1_sheet2.png, k2_sheet.png, rr2_a.png / rr2_b.png. Code: QoLGame `# ---- MP TEAM ARTS LIGHT
(part 29)` / `# ---- MP DUAL ASSISTS (part 29)` (end of qol_game.gd) + hook lines in f_0202954c, f_02026c00, f_020277ac,
f_020294b8, f_0202a40c and the ASSIST SPAM copy limit / pool.
- **Team Arts partner bit** (H, C FUN_02026548 / FUN_0202A40C / FUN_020281D8 / FUN_020298D4 / FUN_02026E34 / FUN_0202700C):
  FUN_02026548(rec) walks the Team Arts entries of the active character (u16 at DAT_02026984 + id·4 = first entry, u16
  at +2 = count; entries of 0x14 bytes at teams + DAT_0202698C: member ids +0..+2, members needed +3 (2 = the active one + one
  partner, else every listed member must be on the team), unlock mask +8 tested against u32 team+0x8DC; M for the field
  names) over the members that are alive or supports (id != 0x26), sets rec+0x274 |= 0x100 and the
  participants teams+0x11E4/+0x11E8/+0x11EC (+0x11F0 = FUN_02027BD0(side), the opponent's active) and returns the entry; none:
  clears the bit and the four words. Callers: the loader FUN_0202A40C for ONE record only -- the active fighter of the local
  side (FUN_02012FEC; side 0 in Free Battle) --, the tag FUN_020281D8 and KO replacement FUN_020298D4 for the side that
  changed, FUN_02026E34 (Team Arts touch test, recomputes before deciding) and FUN_0202700C (from FUN_0202B85C, M: a
  follow-up of action 0x34). Readers of the bit: only FUN_02027950 / FUN_02027A40 (ki spend / gain → the local side's Team Arts bar palette) and
  the port's MP panel. **Cause of the user's report** (V r1: both teams Goku + Piccolo + Vegeta, INFINITE KI): P2's bit stays 0
  from the battle start until P2's first tag / KO / Team Arts, so P2's plate showed dim at 200 % although a tap on it started
  Team Arts (r1: P2 tap f4650 → action 0x30, plate lit only afterwards, f4680). Fix (MP battle only): after each active
  fighter's update (f_0202954c) FUN_02026548 is called for it with teams+0x11E4..+0x11F0 put back (they may hold a Team Arts
  in progress). V t2 (the user's teams): both plates lit from the battle start (`p2 Team Arts partner yes` f3737), P2 tap →
  0x30; t1: P2 Goku + Vegeta + support (no pair) dim, tap → nothing (action stays 0); P1 Goku + Piccolo + Vegeta lit, tap f4620
  → 0x30.
- **One assist slot** (H, C FUN_02026C00 / FUN_020277AC / FUN_02029AB0 / FUN_0201825C / FUN_02015328 / FUN_0202B580 /
  FUN_0202759C / FUN_0202B4A0 / FUN_0203483C / FUN_02022930): FUN_02026C00 refuses while side 0's active (teams+0x8C8) OR side
  1's active (teams+0x11B0 → record +0xB38 = +0x8E8 + 0x250) has +0x250 & 0x100 (call pose), while u32 teams+0x11E0 != 0, with
  team+0x8CA == 0, or when the touch is outside a support's rect. The battle frame (FUN_02029AB0), the KO state FUN_0201825C and
  the assist-wait state FUN_02015328 (sub-state 1 waits until FUN_02027B1C() == 0; support 0x24 is ended there by force) run
  FUN_020294B8(*slot) (returns at once for 0, skips records with +0x250 & 0x800). Ends: FUN_0202B580 (hide +0x124, slot = 0)
  from the assist's own action handlers FUN_0202B5D8 / FUN_0202B604 and FORCED by the Team Arts end FUN_020287E8, the grab /
  ultimate starts FUN_02028DDC and FUN_0202B698. FUN_0203483C(f) = the team has Shenron (0x23) with assists left; a KO'd
  fighter's FUN_0202759C (HP 0) and the knock-back handler FUN_0202B4A0 then call FUN_020277AC only while the slot is free
  (Shenron's revive). FUN_02022930 script ops 0x52 / 0x51 set / clear +0x250 & 0x800 (frozen) on the opponent's active and
  the slot's assist. Team Arts members that are supports run through FUN_020294B8(member) from FUN_020287E8 (not the slot).
- **MP dual assists** (V): each side has its own slot `_mda[side]` (the team's real support record, no copy: the same
  character on both sides works). The global slot keeps one of them (so FUN_02015328 / the KO state still wait for / run
  "an assist"), the other runs once per frame right after it with the slot pointing at it (as ASSIST SPAM's copies; its own
  end clears the slot → that side's slot is free). FUN_02026C00 / FUN_020277AC / FUN_0202759C / FUN_0202B4A0 run with the slot
  = the caller's own slot (and the opponent's call pose bit hidden for the call test); a forced FUN_0202B580 sends both
  sides' assists away. ASSIST SPAM in MP: copies per side while that side's own slot is busy, 8 per side (pool 16 x 0x2E0 at
  0x02700000). d1 (P1 Goku + Vegeta + support 26, P2 Goku + Piccolo + support 26 = the same Krillin): P1 call f4600 → arrives
  f4624, P2 call f4640 while P1's is out → arrives f4664 (`own 2108460 ... other 2107b78`), both on screen f4680-f4760
  (d1_zoom f4700: P1's Krillin dashing at P2, P2's waiting top-right), P1's hits P2 (13000 → 11800), P2's hits P1 (13000 →
  11800), leave f4766 / f4806, both re-called f5200 / f5230 (both out again). s1 (ASSIST SPAM + INFINITE ASSISTS): P1 3 calls,
  P2 2 calls → 2 real + 3 copies out together, all attacking the other side. s2 (two supports per team, the part-28 split
  box): P1 left half → Dende (slot 1) + P2 right half → Dende (slot 2) together; P1's right half while its Dende is out:
  refused (one at a time per player); round 2 P1 right half / P2 left half → both Krillins. k1 (ONE HIT KO, P2 support
  Shenron): P1's Krillin KOs P2 f4697 while out → P2's Shenron arrives in P2's own slot, revives P2 (10000 HP f5200, the dark
  sky returns to normal) while P1's Krillin finishes (in the game: no revive while any assist is out). k2 (ONE HIT KO, both
  supports out when P2 is KO'd): KO banner (PERFECT for P1), both assists frozen during the KO countdown (as the game's), then
  run out (f4943 / f4973), victory pose, result screen. rr2: battle 1 both called (f4874 / f4904), pause f5000 with both out
  → Return to Character Select → new picks → battle 2 (loader resets `_mda` / the copies): both called again f7124 / f7154,
  both on screen f7200 (rr2_b), each hits the other side (13000 → 11800 both).
- Off-identity (V): mp29/off.sh and mp29/offmp.sh (mp=1) 21/21 PNGs + 1382 `^CHT f` lines to 5300 identical to
  /tmp/ssw2/btn; intro cap.sh 10 2210 10: 221/221 identical to /tmp/ssw2/intro.
- Not changed: FUN_02022930 op 0x52 freezes only the assist in the global slot (the other side's keeps moving during such a
  move); the INPUT / AI paths are untouched (a support tap during a non-neutral action is still lost, as in the game).

## Session 1 part 30 findings (LAN research) — V = port verified, C = code read
Research for LAN MULTIPLAYER (design: docs/LAN_DESIGN.md). Evidence: /tmp/ssw2/lan_research (scratch project `proj/` with
`# ---- LAN RESEARCH (debug)` sections in qol_game.gd / game_ds.gd: `lanr`, `lansync=stage:XX,rng,anim,party:a.b.c/d.e.f,
qolseed:N`, `lanbattle=N`, `lanin=` / `lanin2=` relative to the battle init, `lanhash=FILE` per-frame hashes, `landump=`;
runners run.sh / runc.sh, inputs.sh, tools/cmp.py / bdiff.py; runs/A1..EC, vs4; enet/ ENet tests).
- **Battle RNG** (H, C + V): byte-table generator, state u32 0x020DD4E4 {u32 mode, u8 index +4, u8 countdown +5}, table
  0x020B63D4 (256 bytes). FUN_02001998 returns table[index++] (FUN_020018FC: 4 bytes as a u32); when the countdown wraps
  and mode == 0 the index is reseeded by FUN_02001A50 = (RTC hour · minute · second products via FUN_020B1510) & 0xFF.
  FUN_020019FC(m): m 0 = index from the RTC, 1 = index 0; countdown = table[index]. Callers: FUN_02002C18 (boot / soft
  reset) 0, FUN_02071374 (stage select, random icon 15) 0, **FUN_02079430 (wireless battle wrapper) state 4: 1** — the
  original makes its two-DS battle deterministic this way. Users of FUN_02001998 in battle: FUN_02017A78, camera
  FUN_02019980, FUN_0201DF20, effects FUN_0202216C, script VM FUN_02022930, AI FUN_0202D1D4 / D438 / D66C / D820 / DA14 /
  DBC4 / DCE0, FUN_0202EF9C / F020. V: 0 calls in a plain MP battle (A5), 65 with bombs + chaos (EA), 281 with the CPU AI (A3).
- **Other RNGs** (H, C): LCG u32 0x020DD7E8 (x · 0x5D588B65 + 0x269EC3, seeded flag u8 0x020DD7C0; FUN_0200819C(n), seed
  FUN_02008264), state 0x020DD7F4 (FUN_0200820C, flag u8 0x020DD7C4), MT19937 state u32[624] 0x020DD80C + index u32
  0x020D53F4 (FUN_020082AC(n), seed FUN_02008424); seeds from FUN_0200846C (RTC date / time) in FUN_0203FFE0, FUN_0204DC98,
  FUN_02056D50, FUN_02059A48, FUN_0209DB34. Users: FUN_0203AA9C (LCG), FUN_0203E728 / FUN_02062968 (MT) — not the battle.
- **Instance-id counter** (H, C FUN_020061E0 + V): u16 0x020DD7B4, copied to object +0x22 and incremented per created
  object; it keeps growing through a battle and the select / stage screens after it (V C3: 0x19 after a previous battle,
  0 after a fresh boot), so the ids in the battle globals differ by history. Writing 0 at FUN_020140C8 made a battle after a
  previous battle byte-identical to a fresh one (V C4, 2600 frames).
- **Frame counter** u16 0x020DD4C0 (H, C): incremented by the NitroMain loop only; the literal 0x020DD4C0 appears 3 times,
  all in NitroMain (FUN_02000B88). The port's CHARACTER / STAGE SHUFFLE tick dedupe compares it with the last value seen.
  NitroMain's loop also soft-resets on L+R+Start+Select (FUN_020011F8 0x200 / 0x100 / 4 / 8); scene 4's loop too (only
  with A, B, X, Y released).
- **Save copy in the battle** (H, C FUN_0202A40C / FUN_0202856C / FUN_020022E0 / FUN_02002260 / FUN_0200228C): options
  word u16 [0x020DD71C] + 0x80 = 0x020DD79C (save copy +0x1E8): bits 1-2 (FUN_0200228C) → FUN_0200231C(1 / 3 / 6) (CPU level
  u8 0x020DD552), bits 3-4 (FUN_02002260) → teams +0x1676 = 0x100 / 0x140 / 0x180 (modes 0, 1, 4, 5, 0xB), bit 0
  FUN_020022B8. Team Arts unlock mask FUN_0202856C → teams +0x8DC and +0x11C4: modes 0, 1, 2, 3, 5, 0xB from the story
  progress (FUN_02002410(buf, character) per character, save copy 0x020DD628 + 0x18 · c), base 0x3E000000 (+ bits); modes
  4 / 10 = -1 (all), 6-9 = 0x3E000000; read by FUN_02026548 (which Team Arts exist). Two machines with different saves /
  options therefore load different battles.
- **Determinism of the translated battle** (V; Free Battle, inputs relative to FUN_020140C8, 2600 frames incl. pause, KO,
  Game Over, back to the select): different rtc + 97 frames of extra menu history, or a previous battle with other
  characters / stage / rtc: the battle globals (G = u32 0x020DE3A0, 0x1C000 bytes), the RNG and the input / RNG call counts
  are identical every frame once the stage, the parties, the RNG (FUN_020019FC(1)) and the id counter (0x020DD7B4 = 0) are
  set at FUN_020140C8 (A3/B3, A3/C4, A5/C5 MP battle with P2 human input + P1 taps + ONE HIT KO, EA/EC with RANDOM
  CHARACTERS / STAGE, CHAOS + STAGE SHUFFLE (46-48 swaps with file loads), BOMB RAIN, RANDOM MUSIC playing different BGMs,
  port RNGs seeded). Without the RNG sync the battle diverges at the first RNG call (EA2/EB2 r1832, A1/B1 r262 with the AI).
  Remaining RAM differences are harmless: save copy time stamp u32 0x020DD5B8, sound work bytes 0x020E35A4 / 0x020E35C8 /
  0x020E3730 / 0x020E3754 (±1), 9 bytes 0x020E5268, SND player lists 0x020E18xx after a previous battle, the music stream
  buffer (0x022Exxxx, every ~11 frames), select / stage leftovers (0x020DC094, 0x020DE88x..0x020DEADx, 0x020DD564..0x020DD5A1).
  Heap at the battle init identical in every history (G 0x02100048, heap free 2895384); first battle input call 311-314
  frames after the init.
- **Drawing-only fields in battle RAM** (V A3/D3, A6/D6: CAMERA ZOOM 0 or 4, DETAILED SHADOWS, DAMAGE NUMBERS, INPUT DISPLAY):
  fighter record and effect object +0x140 / +0x142 (s16 sprite screen x / y, written by the sprite registration
  FUN_02019328 with the zoom of the moment), team block +0x8A4 / +0x8A6 (shadow sprite), G+0xE08 (sprite list scale, = list
  +0x184), stage-object visibility halfwords (stage block, `_zm_win`). Everything else identical for 2600 frames; a checksum
  over the team blocks (teams .. +0x167C) and the effect pool (u32 0x020DE3CC .. +0x4DF0) with +0x140..+0x143 of each record /
  object and team +0x8A4..+0x8A7 zeroed, plus RNG, battle state u8 0x020DD4C5, timer u16 G+0x1BCA6 and camera x / y, is equal
  between them and changes on almost every frame (1861 values in 2600 frames).
- **Port gameplay code that depends on local state** (H, C): QoLBombs `_spawn` clamps to the view `_cv_draw`, the camera as
  drawn by QoLGame `_fx_draw` (zoom +6 while CAMERA ZOOM's drawing swap is active) → bomb positions depend on the local zoom;
  the sway uses GDScript `sin` (C runtime). QoLGame `rng` / `_shuf_rng` / `_stg_rng` are seeded per process (random) unless
  shufseed / stgseed; `_shuf_frame` / `_stg_frame` keep the last frame-counter value across battles.
- **Wireless VS host path = a single-team select** (H, C FUN_02066558 / FUN_020717E8 + V vs4, MULTIPLAYER off): scene 0x11 →
  HOST (+0x33 = 1) → FUN_02002738(1) (+0x32 = 1) → scene 4 in mode 2 at f2840 (the Z-Battle team select: three portraits,
  DRAGONPOWER ∞/∞ with the 100 % save, READY? GO / BACK) → GO → scene 5 at f3180 → stage A → FUN_020717E8(1): FUN_02071374,
  then mode 2: +0x32 set and host → scene 7 (f3460, wireless battle: "Connection Failed" f3600); +0x32 set and client, or
  +0x32 clear → returns 0 (no scene change). Scene 4 exits: B with no picks → mode 2: FUN_02002738(0) + scene 0x11, else 6;
  soft reset → 0xF; GO → mode 0: FUN_0209D244 + 0x12, mode 2: host → 5 / else 0x11, mode 3 → 0xB, else 0; then party P1 via
  FUN_02002838(0, id) with a support moved out of slots 0 / 1, 0x26 for empty, and id 7 → 0x15 when the team also holds
  0x1E (M). DP max FUN_020021F0 (save) clamped to 0x14. Neither scene 4 nor scene 5 reaches any wireless function (call
  graph to depth 4; their only mode / host tests are the exits and FUN_0206B85C's drawing). Scene 5 B in mode 2 → scene 4.
- **ENet in this Godot build** (V, enet/enet_test.gd + enet_2p.gd): ENetConnection bind on UDP 8082 OK, a second bind on the
  same port fails (`Couldn't create an ENet host`, ERR_CANT_CREATE); connect 2 ms (one process) / 168-465 ms (two processes
  incl. start-up); RTT 1 ms (tight loop) / 7 ms (two processes polling once per 60 Hz frame); 900 / 900 frames of 8-record
  redundant 61-byte packets on an unsequenced channel, 0 % loss; reliable channel alongside. IP.get_local_addresses() here:
  ["192.0.2.2", "127.0.0.1"].

## Session 1 part 30 findings (LAN core) — V = port verified, C = code read
Phase 1 of docs/LAN_DESIGN.md (network core, session protocol, lockstep, battle-start sync, checksum, abort). Code:
scripts/qol/qol_lan_net.gd (QoLLanNet: ENet transport, impairment), scripts/qol/qol_lan.gd (QoLLan: session state machine,
handshake, snapshot, lockstep buffers / apply, delay, time sync, checksum, debug flags; public API = LAN_DESIGN 7.1),
QoLGame `# ---- LAN CORE (part 30)` (end of qol_game.gd: `_lan_battle_start` from f_020140c8, `_lan_battle_exit` from
f_02001014, f_0201546c override for the abort), QoLSettings `# ---- LAN SNAPSHOT (part 30)` + the save_file rule, QoLMp.lan,
GameDS gate / LAN input path / poll / `_acc` clamp / turbo sleep, QoLController `# ---- LAN CORE (part 30)` + after_step /
open_menu / AUTO PAUSE hooks, QoLBombs `_sin` + game camera, QoLMpPanel `not mp.lan`. Evidence: /tmp/ssw2/lancore_runs
(run2.sh = two headless turbo instances on 127.0.0.1 with `lanbattle=1`, kill.sh = the guest killed -9 at a lockstep frame,
run2rt.sh = real-time pacing, mpreg.sh = LOCAL MP flow log; runs s1, full1, imp1, kill1..3, des1, rej, mp_base / mp_cur;
compare tool tools/linux/lan_cmp.py).
- **Lockstep result** (V): host P1 (inputs = btnrun menus, `laninputs` = research BAT5 + a pause, cheats one_hit_ko +
  infinite_ki, parties 0.5.26 / 0.5.26 and stage 0x0E from STAGE_RESULT) vs guest P2 (rtc 2026-07-15, a Mode Select detour
  and 97 frames later, zoom=4 shadows=1, own settings.cfg with infinite_health; `laninputs` = research P2B): gameplay hash
  identical every lockstep frame L1..L1961 (full1: VS intro, fight, P1 pause L750-801, events 0x0B / 0x0C, KO L1558, states
  0x11-0x13) and the battle left at the same frame L1962 on both (FUN_02001014(0x14)); G block differs from L279 only
  (drawing fields, as the research found). `lanlag=80 lanjitter=20 lanloss=10` on both (imp1): identical L1..L2599 (P1
  pause, P2 pauses L1600 / L1640), 624 + 515 input packets dropped, 190 / 160 stalls logged (`LAN f… L… stall N ms`).
- **Exit frame** (H, V full1): the frame in which the battle calls FUN_02001014 also runs the port's `f_020019fc(0)` (RNG
  mode 0 = index reseeded from the RTC) → that frame's checksum differs by design: it is neither checksummed nor compared.
- **Battle RNG / ids / flags written at FUN_020140C8** (V): FUN_020019FC(1), u16 0x020DD7B4 = 0, u16 0x020DD4C0 = 0, boss
  level u8 0x020DD510 = 0, wireless flags u8 0x020DD54E (+0x32) / 0x020DD54F (+0x33) of the party block base 0x020DD51C
  cleared with FUN_02002738(0) when set (C: FUN_02002738(0) also writes u32 0x020DD55C = 0 through FUN_02002674;
  **FUN_020026E4(0) writes +0x33 = 2 (client), FUN_020026E4(1) = 1 (host)**, H). The guest's save copy 0x020DD5B4..+0x1F4
  is swapped for the host's (STAGE_RESULT "save") and put back at the exit (V full1 log "save copy host's").
- **Pause menu as the abort path** (H, C FUN_0201546C + V kill2 / kill3 / des1): sub-state u16 0x020DD4C6 (FUN_020010C4):
  0 init, 1 = the menu takes input (A on item code 0xE returns 4 → next scene 6 → FUN_02001014(6) after the teardown), 2 / 3
  closing / command list. START only pauses in battle state 7 (u8 0x020DD4C5). Override: while aborting, a call that
  entered in sub-state 1 and got 0 from super returns 4. V: abort in the VS intro (L333) → waits for state 7 (L676) → exit
  L711; abort mid-fight (L1073) → exit L1126 (53 frames); desync abort L400-407 → exit L711-713 (intro); every time
  FUN_02001014(6) → redirected to 0x11, which then runs its state 2 (VS menu) normally.
- **Disconnect detection** (V): kill -9 of the guest → the host gets ENet EVENT_DISCONNECT within one frame on localhost
  (kill1..3, the closed socket answers); a frozen / OOM-killed peer without a socket close → 10 s TIMEOUT (rt1). Host →
  state HOSTING (room open), guest → IDLE.
- **Desync detection** (V des1, `landesync=400` on the host = P1 HP −7 on that side only): the guest saw its checksum differ
  at exactly L400, sent DESYNC, both aborted (L400 / L407) to 0x11, session kept (host LOBBY).
- **Snapshot / settings.cfg** (V full1, kill1 / kill3): guest's own file infinite_health=true, blood=true; host cheats
  one_hit_ko / infinite_ki, weird bomb_rain active on the guest during the session (identical gameplay hashes prove it; the
  guest saved its settings at WELCOME during the override), and after kill -9 mid-battle the guest's settings.cfg still
  holds infinite_health=true, one_hit_ko=false, infinite_ki=false, blood=true, bomb_rain=false ([lan] name / last_ip added).
- **BOMB RAIN in LAN** (V kill1 / kill3 with weird=bombs on the host, zoom 4 on the guest): spawns at the same world
  positions on both (BOMB f… spawn slot 0 at 8103,8024 view 8064..8320 on both machines, the drawn sprite-list scale g 256
  vs 333 differs) and identical gameplay hashes: `_cam()` (the game's own camera) instead of the drawn view, the game's sine
  table instead of `sin` while QoLGame.lan_battle().
- **ENet sending** (V s1): resending the unacked records on every poll of a stalled turbo loop (~30 000 packets/s per
  side) choked the localhost link until ENet timed out the peer; resends at most every 15 ms + one packet per new record
  fixed it (≈ 2 packets per game frame). Input packet = 24 + 7·n bytes (header u8 type, u16 battle, u32 first, u8 n; trailer
  u32 ack, u32 current frame, u32 checksum frame, u32 checksum).
- **Input delay in these runs** (V): the host's choice from the last 5 s of pings gave 2-8 in turbo runs (RTT 50-300 ms: both
  processes polled once per turbo frame under CPU contention), 7 with lanlag 80; `landelay=N` fixes it.
- **Real-time pacing** (V rt2: no turbo, `pacelog`, both build ids computed from the sources): delay 2 (ping 22-60 ms),
  gameplay hash identical L1..L1500, 26-30 stalls of 20-48 ms per side in 25 s (2 CPUs shared with other Godot runs), time
  sync advantage within ±1 frame; a P2 panel tap by the guest (48,76) reached f_0202dce0 as flags 3 on both machines. (rt1:
  the guest was OOM-killed by the 8 GB memory cgroup with four Godot processes running; the host reported "lost" TIMEOUT.)
- **Handshake rejects** (V rej): `lanbuild=other` → REJECT "VERSION host 1/lancoretest guest 1/other" at the guest's f4;
  `lanrom=0123` → REJECT "ROM".
- **Off-identity / regressions** (V): btn 21/21 PNGs + 1382 CHT lines identical (/tmp/ssw2/lancore_off, and with mp=1
  lancore_offmp); intro 221/221 identical (lancore_intro); LOCAL MP flow (mpsel "a" inputs, mp=1 mpseed=7, headless turbo
  with mpdbg cheatdbg, quit 6000): 2525 MP / MPS / MPB / CHT lines identical between the pre-LAN scripts
  (/tmp/ssw2/lancore_base) and the current tree.

## Session 1 part 30 findings (LAN menus) — V = port verified, C = code read
Port pages for docs/LAN_DESIGN.md 6 (phase 2): `scripts/qol/qol_lan_menu.gd` (QoLLanMenu), `scripts/qol/qol_keyboard.gd`
(QoLKeyboard), hooks in QoLController `# ---- LAN MENU (part 30)`, QoLSettings [lan] name / last_ip. Evidence in
/tmp/ssw2/lanmenu/ (preview pages `prev/`, sheet `prev_all.png`; game runs `t2/` (+ t2.inputs), `two/c/` (two instances)).
- **VS menu LAN choice → port pages** (H, V t2): FUN_0207B778 (scene 0x11 state 2) returns 2 for the right picture button
  (CLIENT, relabelled LAN); QoLGame.f_0207b778 keeps it as `mp.menu_req = 2` and returns 0, QoLController._mp_after opens
  QoLLanMenu (was the part-27 "not available yet" notice). While a page is open the scene stays in state 2 with blank DS
  input (filter_input returns 0x3FF / 0x2C00 / no touch): FUN_0207B778 returns 0 every frame, the game's own cursor and
  drawing tail keep running underneath; only BG1 (hexagons) is kept on the lower screen (set_layer_keep(true, 0x200)) and the
  QoLMpMenu LOCAL / LAN relabel overlay is off. The upper screen's title bar (x 0-198, y 25-40) and message box (x 11-244,
  y 59-148, stripes by y % 3) are redrawn by the port as for QoLMpMenu; page fades follow both engines' MASTER_BRIGHT / BLDY
  (QoLController._mp_bright).
- **Real keyboard typing vs the ds_* map** (H, V t2 / two): a key event consumed in GameDS._input (raw_input returns true)
  is still seen by Godot's Input singleton, so `Input.is_action_pressed("ds_a")` stays true while the X key is held → the DS
  word would also press A on the on-screen key under the cursor. QoLLanMenu.key_event masks the DS bits of the actions of
  every consumed key until its release (`_kb_mask`); consumed presses never set GameDS `_tapped`. Scripted `inputs=F:K<key>`
  events carry no unicode → keycode fallback (A-Z, 0-9, KP digits, period, colon, minus, underscore, space).
- **The ":" key** (H, V two/b → two/c): ids are "key:<char>", so ":" is "key::" — split(":") loses it (typed nothing,
  "127.0.0.18095" → WRONG IP ADDRESS in two/b); the char is taken with substr(4).
- **Connect timeout** (V t2): QoLLan's 15 s timer is real time (CONNECT_TIMEOUT_MS) and emits connect_failed "TIMEOUT"; the
  pages show its seconds (connect_left). In a frame-exact capture run (~12 game frames per real second) that is ~180 game
  frames (join f3489 → UNABLE TO CONNECT f3668, 127.0.0.1:8082 with no room).
- **Two instances through the pages** (V two/c, headless, host 8095 via `lanport=`): host HOST → name HOSTY → lobby f3039;
  guest JOIN → name GUESTY + IP typed with keys + the ":" key tapped (T190/158) → CONNECT? YES f3179 → connected f3189 (lobby,
  host got peer_joined f3243) → host START → guest popup f3884 → DENY → host "GUESTY SAID NO" f4178 → START again → guest
  ACCEPT → host proposal_accepted f5075 (QoLLan state SELECT on both: the phase-3 hook).
- This VM's addresses: QoLLanNet.local_addresses() = ["192.0.2.2"] (TEST-NET-1, shown on the HOST page and in the lobby).
- **Gamepad cursor / D-pad** (V t3, `vcursor=68,83 vcurclick=2870:4`): the QoLCursor click reaches the pages through the
  normal touch path (QoLController.cursor_touch → filter_input → tap): HOST pressed f2870; D-pad + A typed "BV", START = OK,
  A = YES (lobby f3109), B → LEAVE THE ROOM?, B = NO (back in the room).
- **Off-identity** (V): /tmp/ssw2/lanmenu/off.sh (copy of off23.sh) 21/21 PNGs + 1382 `CHT f` lines up to 5300 identical to
  /tmp/ssw2/btn; offmp.sh (the same with mp=1) identical too.
- **Guest captures against a real host** (V two/cap: host headless pressing START every 5 s, guest frame-exact captures,
  sheet two_cap_sheet.png): CONNECT? → lobby with HOSTY / GUESTY plates (f3200), proposal popup (f3250), DENY → DECLINED,
  second proposal → ACCEPT → "GOING TO THE CHARACTER SELECT" / STARTING (f3520), B → LEAVE THE ROOM? → YES → LAN page.
  The guest's ping reads 420-450 ms there only because the capture run polls ~12 times per real second.


## Session 1 part 30 findings (LAN select / stage / battle) — V = port verified, C = code read
Phase 3 of docs/LAN_DESIGN.md (9): the LAN flow from ACCEPT to the battle and back. Code: QoLLan `# ---- LAN SELECT (part 30,
phase 3)` (end of scripts/qol/qol_lan.gd: messages, rounds, sel_filter, scene tracking, notices, debug flags), QoLGame
`# ---- LAN SELECT (part 30, phase 3)` (end of qol_game.gd: f_0206cc94 / f_0207215c / f_02001014 / f_0207b778 LAN branches,
`_st_start` / `_st_roulette` shared with LOCAL), scripts/qol/qol_lan_panel.gd (QoLLanPanel), QoLLanNet.close_graceful,
QoLController (filter_input → lan.sel_filter, after_step → lan_panel, _lan_after notices, lan_poll → bands, INPUT DISPLAY),
QoLLanMenu.show_notice / open_lobby keeps a pending proposal, QoLMpSelect LAN stage mode, QoLInputDisplay.held_override.
Evidence: /tmp/ssw2/lansel (run2.sh two headless turbo instances; runcap.sh one of them captured; kill2.sh kill -9 tests;
cap1.sh single-player panel pixel check; cmpb.py per-battle lanhash compare; sheets s_sel.png, s_bat3.png, s_host.png).
- **VS menu HOST path on both machines** (H, C FUN_0207BA08 + V t1 / full2): FUN_0207B778 result 1 → FUN_020026E4(1) (+0x33 = 1),
  next scene byte 4 at work +0x18CB, states 7 (fade) / 8 → FUN_02002738(1) + FUN_02001014(4) → scene 4 in mode 2 (both
  machines, ~30 frames after the guest's ACCEPT on the host).
- **Team select teardown** (H, C FUN_02066230 + V full1): the scene-4 exit calls FUN_02001014(2) (scene byte = 2) before
  its real FUN_02001014(next): an override sees scene 2 at the real exit (the port remembers the scene before the 2).
- **Scene 4 loop FUN_02066558** (H, C): FUN_0206CC94 returns exactly 0x8000 only from the READY? overlay (A or the GO rect);
  0xFFFFFFFF / 0xFFFFFFFE / 0xFFFFFFF6 (refused / CANCEL / BACK) also have bit 15 set. B is tested by the loop after it
  (FUN_02001230(2)): no picks (FUN_02065EEC over u32[3] 0x020DE64C) → exit 1 (mode 2: FUN_02002738(0) + scene 0x11), else
  FUN_0206648C (pops a pick, closes the overlay). START with a fighter opens the overlay (FUN_0206A748(1)). V lanpicks: a
  character id returned by FUN_0206CC94 is committed by the loop (FUN_02067E34); writing -1 to the three team slots + one
  B press leaves to 0x11 (forced leave).
- **Scene 5 loop FUN_0207197C** (H, C): B pressed with FUN_02071C70() == 0 → exit 2 → FUN_020717E8(2) → mode 2 → scene 4; A
  pressed → exit 1 (the loop's own confirm, also with the port's two-outline code: the DS input stays blank in a LAN stage
  select); the confirm FUN_020717E8(1) → FUN_02071374 → mode 2, +0x32 and host → FUN_02001014(7).
- **Stage icon → stage id** (H, C FUN_02071374 + V): byte table at u32 [0x020715FC] indexed by the icon; 15 (random) = a
  battle-RNG byte % 15. V: icon 3 → stage 9 (Western Capital), icon 9 → stage 0 (World Tournament), as named on the upper
  screen and loaded in the battle (s_sel.png / s_bat3.png).
- **The battle's lower-screen panel** (H, C FUN_020067CC / FUN_0201C7A8 / FUN_0201C8F4 / FUN_0201C9C4 / FUN_0201CA60 /
  FUN_0201CDCC + V palette dump c1/pal.bin): FUN_020067CC(layer, row, …, x, w, h) rewrites the palette bits of a tilemap
  region; the slots are BG "layers" 4..6 (0x58 x 0x80), rows: 0 normal, k + 1 = slot k active (rows 1-3 equal: index 1 white
  = the frame), 4 KO'd (FUN_0201C9C4) / support greyed, 7 bench while ki < 0x1400 (FUN_0201C7A8(0), fighters only), Team Arts
  strip = layer 4 tile rows 17-23 (y 136..191) with row 5 (lit, FUN_0201C8F4(1)) / 6; e_pairatk's map rows 0..55 are that
  strip. FUN_0201CDCC (per frame, state G+0x1BC8C: per side ki >> 8 at +0, assists at +2): the local side's support slot
  (+0xCE3) gets row 4 when its assists value becomes 0 (a change; a support with 0 assists from the start stays row 0). Engine
  B BG palette rows 0-7 = game_bg.arc #0x66 (row 5 index 11 = the red diamond ff0000, row 6 index 11 830000).
- **The port's 2D colour expansion** (H, shaders/ds_engine2d.gdshader + V): c6 = c5 << 1, 8-bit = c6 << 2 | c6 >> 4 (31 → 251).
- **QoLLanPanel pixel check** (V c1 vs c2, `lanpanel=0`: side 0 drawn by the port over the game's own panel in a
  single-player Free Battle, 3 members incl. a support, tags at 4700 / 4800): 0 differing pixels in 5 frames.
- **ENet BYE before a disconnect** (H, V full2 / pms): peer_disconnect_now() right after the reliable BYE made the other side
  report EVENT_DISCONNECT and drop the queued BYE ("lost (DISCONNECTED)"); peer_disconnect_later() + servicing the old
  connection until its EVENT_DISCONNECT (≤ 1.5 s, QoLLanNet.close_graceful / service_closing) → the other side gets the BYE
  ("peer_left (LEFT)").
- **Flow results** (V): full2 (host lanpicks 0.5.26 / lanstage 3 / cheats one_hit_ko,infinite_ki / BAT5; guest picks 5.0.27
  after 300 frames (the host waits: "<NAME> IS READY" / "WAITING FOR <NAME>"), lanstage 9, zoom 4 + shadows): select →
  stage (host 50/50, STAGE_RESULT, both roulettes) → battle 1 (L1..L1945 gameplay hash + RNG identical) → KO → both scene 4 →
  battle 2 (identical) → host B with no picks → LEAVE_SELECT → both in the room. pcs: pause → Character Select (asked 3) → both
  scene 4, two battles identical (G block identical too), guest taps on its own panel: tag (128,76: P2 Piccolo → Goku, act
  0x26 / 0x27), support (208,76: act 0x28, assist slot set), Team Arts (128,164); then B → room, guest leaves → host
  peer_left. pms: pause → Mode Select (asked 6) → both in the room. Kill -9 tests: guest killed in the team select (ksel),
  the stage select (kstg), the battle (kbat) → host back in its open room with "CONNECTION LOST"; host killed in the select
  (khsel) → guest (waiting, READY) leaves to the LAN page with "CONNECTION LOST". ENet reports the dead peer 3-6 s later in
  the select / stage (no packets but pings), within frames in a battle.
- **Lockstep stalls and the band** (V caph: guest lanlag=1500 → host delay 8, stalls 200-850 ms): WAITING FOR PLAYER shown
  during stalls (kept 0.4 s after a long stall), host PING 1746 ms in red under Team Arts; guest `lanquit` → host "GUESTY
  LEFT" band while the battle is left through the pause menu.
- **Cheats in LAN battles** (V): cboss (host BOSS CHARACTERS + SAME CHARACTERS, picks "0b.0.26" / guest "1b.1", guest zoom 4):
  both machines made the same bosses at the loader (P1 Goku level 1 HP 21000, P2 Gohan level 3 HP 32000, 11 boss branches)
  from STAGE_RESULT "boss", gameplay identical L1..L1905. crand (RANDOM CHARACTERS, RANDOM STAGE, CHAOS + STAGE SHUFFLE,
  BOMB RAIN, random icon 15 → host stage 12, RANDOM STAGE → 6; guest zoom 4 + shadows): identical L1..L2624.
- **Guest captures** (V cap3 / capw): the guest's lower screen = its own team (Piccolo active with the white frame, Goku,
  Dende; KO'd dark; Touch! lit / dim with a blue diamond), PING under Team Arts; "WAITING FOR HOSTY..." while the guest was
  ready first, "GUESTY IS READY" on the host when the guest was first (caph).
- **Unchanged without a session** (V): /tmp/ssw2/lansel/off (+ off2 after the last edit) and offmp (mp=1): 21/21 PNGs + 1382
  `CHT f` lines up to 5300 identical to /tmp/ssw2/btn; intro 221/221 identical; LOCAL MP flow (mpreg.sh, mpsel "a" inputs):
  2525 MP / MPS / MPB / CHT lines identical to the pre-LAN /tmp/ssw2/lancore_runs/mp_base.log.

## Session 1 part 30 findings (LAN QA) — V = port verified, C = code read
Phase 4 of docs/LAN_DESIGN.md 9 (QA + polish). Evidence: /tmp/ssw2/lanqa (scripts rt.sh = two real-time instances (headless /
xvfb / mixed: host headless + guest windowed, `lanbattle=1`), run.sh (the same, turbo), run2.sh + mx.sh (full LAN flow, turbo,
summary in NAME.sum), runcap.sh (one instance captured), disc.sh (signal / quit / leave in any stage, guest with its own
settings.cfg g.cfg.in), rejoin.sh (host keeps its room, guest A plays + leaves, guest B joins), caprest.sh, wrun.sh (exported exe
under GE-Proton wine / Linux export / editor), cmpb.py / cmpsess.py (lanhash compare per battle / per session), off.sh +
offcmp.py, mpreg.sh).
- **PING was the frame rate, not the network** (H, V rt_before / rt_after, capA): ENet only sends what `send()` queued and only
  reads what arrived when `ENetConnection.service()` runs, and QoLLan serviced once per Godot frame on the main thread (which
  also waits for the game step) → a ping took 4 frame-quantised legs: real-time localhost 25-42 ms (rt_before), capture runs
  ~12 polls/s → 515-563 ms (lansel/s_bat3.png), turbo 50-300 ms (which also made the host pick input delays 2-8). Fix
  (QoLLanNet): a network thread services the connection every ~1 ms with every ENet call of both threads under one (reentrant)
  Mutex, received events are queued for the main thread's `service()`, every send is flushed at once, PING / PONG (channel 2,
  9 bytes: type + s64 µs) are answered and timed inside that thread → event {"type": "rtt", "us"}. After: real-time localhost
  rtt median 1.3 ms, p90 2.3-2.9 ms, max 10-14 ms with both instances on 2 shared CPUs (149 samples per side, `pingdbg`); capture
  run 1-3 ms; `lanlag=80 lanjitter=20` both ways → 128-210 ms (expected 160 ± 40); lockstep identical in all. `lanthread=0` = the
  old single-thread servicing (A/B). Stalls per 900 real-time frames dropped from 22-28 to 15-16 (sends no longer wait a frame).
- **PING label / select band** (V qa_before_after.png, capA, capW, capV): "PING n ms" in the game font (BOLD), "PING" in the
  game's yellow, the value white, black 1-px outline, at x 8 / cap top y 179 in the free strip under the Team Arts plate (y
  177-191); a 3-bar signal icon in front is the only colour hint (3 green < 30 ms, 2 yellow < 80 ms, 1 red). Team select band
  "WAITING FOR <NAME>..." (white) / "<NAME> IS READY" (yellow) moved from a band across the portraits (y 84) into the top
  screen's own black name strip (H: x 8..247, y 138..160, read from captures: the strip under the three portraits that shows
  the picked names) — the portraits stay visible.
- **Rejoin deadlock** (H, V rj_before → rj_after2): the battle id in the input packets (QoLLan.battle_no) counted battles per
  PROCESS; a host that had played with guest A (its battle 2) and a new guest B (its battle 1) dropped each other's records
  (`bid < _rem_bid` / `bid != battle_no + 1`) → both stalled on WAITING FOR PLAYER forever (pings kept the session "alive").
  Fix: `_reset_battle_ids()` at the session start on both machines (host: HELLO accepted, guest: WELCOME).
- **False DESYNC with different histories** (H, V rj_after → rj_after2): until the battle loader FUN_0202A40C runs (L279 in the
  flow, all runs) the pointers the checksum reads (team blocks u32 0x020DE3D0, effect pool u32 0x020DE3CC, G u32 0x020DE3A0,
  camera u32 0x020DE3A4) still point at the previous battle's freed blocks (fresh process: 0 → hash "000…"). A machine that
  had played any battle before (previous session, local play) hashed stale memory → DESYNC at L1-L4 against a fresh one.
  Fix: QoLGame.f_0202a40c → `lan.on_battle_loaded()`; no checksum before it (both machines run the loader in the same lockstep
  frame). Detection after it unchanged (V des: `landesync=400` → both abort at L400 / L401).
- **Leaving by closing the window** (V d_bat_gquit, d_sel_gquit, d_lob_h9): before, the process ended with the session open (the
  other machine saw "lost"); now QoLController._exit_tree → QoLLan.on_exit(): BYE "QUIT" + disconnect LATER + up to 300 ms for
  it to be delivered → the other machine shows "<NAME> LEFT" (battle aborted through the pause menu, room open again). SIGTERM
  ends Godot without _exit_tree (V d_lob_g15: like a crash). The notices read `last_peer` (QoLLan clears peer_name before the
  menu reads the event: it said "THE GUEST LEFT").
- **Dead-peer detection** (V d_lob_g9 / h9 / g15, d_sel_h9, d_stg_h9, d_bat_h9 / g9): kill -9 → the survivor reports "lost
  (DISCONNECTED)" after ENet's timeout (set_timeout(32, 5000, 10000): 5-10 s; pings and input packets are unreliable, so only
  ENet's own keep-alive notices), in a battle meanwhile WAITING FOR PLAYER. A battle aborted in the VS intro waits for battle
  state 7 to pause (up to ~12 s, d_stg_h9: L3 → L725).
- **Matrix** (V, all gameplay hash + RNG identical, 0 SCRIPT ERRORs, guest with OTHER local cheats / weird options that must
  not act): m1 (host no_cooldown, infinite_health, infinite_ki, ki_homing, infinite_assists, triple_ki + weird blood, after,
  flashy, shake, confetti, dmgnum, rainbow, inputs; guest one_hit_ko, hard_mode, attack_spam, gameboy, crt, mirror, zoom 4,
  shadows) L1..L2795; m2 (host one_hit_ko, hard_mode, attack_spam, assist_spam, same_characters, random_music + mirror, epic,
  fiddle, fuzzy, bevel; guest infinite_health, chaos_shuffle, random_stage, triple_ki, bombs, flashy, crt, zoom 0) L1..L2223
  KO; m3 (host boss_characters "0b", random_characters, random_stage (14 → stage shuffle → 7), character_shuffle,
  stage_shuffle, random icon 15 + bombs, gameboy, crt; guest boss pick "1b", no_cooldown, ki_homing, one_hit_ko,
  same_characters, blood, mirror, epic, zoom 4) L1..L2842; m4long (chaos_shuffle 246 swaps + infinite health / ki + bombs vs
  guest gameboy, zoom 4) **10 000 lockstep frames identical**; loops (6 × select → stage → battle → select, KO each time):
  6 battles identical, heap free [3014584] at every stage select and [2971000, 2789932] at every battle start, file cache 0 / 6
  (`mpdbg` adds heap / archives / cache to the LANS scene lines); imp (`lanlag=80 lanjitter=20 lanloss=10` both, through select,
  stage, 2 battles): identical, delay 7-8. capV (guest captured, host weird blood, after, flashy, confetti, rainbow, bombs,
  mirror; guest local dmgnum, inputs, crt, gameboy, zoom 4): the guest's picture mirrored (host's MIRROR), no CRT / Game Boy
  (its own, overridden), its own damage numbers / input strip / zoom, KO confetti, PING 1-3 ms; identical L1..L1945.
- **MIRROR MODE** (C game_ds.gd + V m1 / m2 / capV): the swap of LEFT / RIGHT happens on the sender's DS word before
  `lan_frame` (the record is already swapped); received records are never swapped; the snapshot carries the HOST's mirror, so
  both pictures are flipped or neither.
- **Settings restore** (V disc runs, caprest rest1): the guest's own settings.cfg (infinite_health, random_stage, blood,
  crt_tv) unchanged after kill -9 in lobby / select / stage / battle and after SIGTERM; after a normal leave the settings
  menu shows its own values again (rest1_cheats.png: INFINITE HEALTH ON, the host's HARD MODE / ONE-HIT KO OFF); log lines
  "settings: host's snapshot on: […]" / "own values back: […]" (landbg).
- **Real time, windows, pipelining** (V rt_sync, xv_pipe1, mx_auto, mx_p1, mx_pauto): headless real time 2400 lockstep frames
  identical, time-sync advantage within ±1.1 frames, lockstep 53-59 game frames/s on this 2-CPU VM (CPU bound: the display rate
  drops at the same time; stalls 0.4 s per 40 s). Windowed (llvmpipe) both instances: 7 game frames/s, guest windowed + host
  headless: 12 / s — this VM cannot show real-time pacing in windows; still identical with `pipeline=1` on the windowed host
  (xv_pipe1, fps 120 smooth motion) and guest (mx_p1), and with `pipeline=auto` switching on during the battle (mx_pauto
  "PIPE f3523 on"), no deadlock. Note: `snap=` makes a run frame-exact (pipelining off).
- **Exported builds** (V w2, w_ed, w_lin; export to /tmp/ssw2/lanqa/exp, the ROM copied next to the exe): two copies of the
  Windows exe under GE-Proton 10-34 wine (headless) — accepted, select → stage → battle, identical L1..L1945 (one_hit_ko, bombs,
  zoom 4 on one side); Windows exe ↔ Linux editor → REJECT "VERSION host 1/5ed55b4accfcd9d1 guest 1/adbb8d095acae93e" (source
  text vs .gdc); Windows exe ↔ Linux export of the same tree → accepted (the same .gdc tokens) and identical L1..L1945 incl.
  BOMB RAIN. ROM check: both found rom.nds next to the exe, rom MD5 equal.
- **`lanbattle=1` debug runs need `lanbstage=HEX`** (V t_des / t_des2): without it each machine keeps the stage its own menus
  chose; with the random icon the RNG picks 0x0E vs 0x0A (party u8 0x020DD54A) → DESYNC at the loader. The real flow always
  uses the host's stage (STAGE_RESULT).
- **Unchanged without a session** (V): /tmp/ssw2/lanqa/off and offmp (mp=1): 21/21 PNGs + 1382 `CHT f` lines up to 5300
  identical to /tmp/ssw2/btn; intro 221/221 identical; LOCAL MP flow (mpreg.sh) 2525 MP / MPS / MPB / CHT lines identical to
  /tmp/ssw2/lancore_runs/mp_base.log.

## Session 1 part 31 findings (LAN menu exit) — V = port verified, C = code read
User bug: after visiting the LAN pages (HOST / JOIN) and going back, the LOCAL / LAN screen (scene 0x11) and then Mode Select
(scene 6) showed only their hexagon background: the game's pictures, menu tiles and most sprites were gone. Evidence:
/tmp/ssw2/lanexit (run.sh NAME INPUTS FROM TO QUIT [flags], mp=1, own cfg base.cfg; sheet before_after.png).
- **Cause** (H, C + V r1): the port's lower-screen layer keep (DSDisplay.set_layer_keep(true, 0x200) = only BG1 of the engine
  on the lower screen, DISPCNT bits 8-12 masked in ds_engine2d.gdshader) is switched on by QoLController._lan_after while a
  LAN page is open and switched off by the same function when `lan_menu.is_open()` turns false. But after_step called
  `_lan_after` only while `lan_menu.visible or lan.state != IDLE or lan.notice` — BACK / B on the LAN page
  (lan_menu_back → QoLLanMenu.close → visible false) with no session left `_lan_after` uncalled from that frame on, so the
  keep stayed at 0x200 for every later scene (r1: p2920 LOCAL / LAN screen = hexagons + the port's LOCAL / LAN labels only,
  p3050-p3100 Mode Select = hexagons only; the top screen was not affected). Every way out of the pages to the LOCAL / LAN
  screen goes through that one call (B / BACK on the "lan" page; NO on the warnings, the name page, CANCEL on connecting,
  UNABLE TO CONNECT / rejected notices and LEAVE THE ROOM? YES all return to the "lan" page first), so every exit path
  had the bug. Not involved: fades (QoLLanMenu.set_brightness only modulates the port's own nodes), the QoLMpMenu overlay
  (set_vs every frame, back on as soon as no LAN page is open), the game's own VS-screen state (FUN_0207B778 kept running
  under the pages; its objects were drawn, only hidden by the mask).
- **Fix** (port, QoLController): one owner rule for the keep — `_keep_mask()` = 0x200 while the settings menu
  (`_layers_hidden`), the LOCAL setup page (`_mp_layers`) or a LAN page (`_lan_layers`) is open, else 0x1F00; `_mp_after` /
  `_lan_after` apply it when their page opens / closes (one page closing no longer clears another's keep); `lan_menu_back`
  clears `_lan_layers` and re-applies at once; after_step also calls `_lan_after` while `_lan_layers` is still set; safety net
  `_layers_guard()` every frame: no port page open and DSDisplay._layer_keep not [0x1F00, 0x1F00] → all layers again (one test
  when all is well).
- **Verified after** (V): p1 (B on the LAN page, BACK tap T230/14, NO on HOST A ROOM?, name page B ×5 → LAN page → B, host
  lobby → LEAVE THE ROOM? YES → LAN page → B, then B to Mode Select): LOCAL / LAN screen and Mode Select complete every time,
  pages look right on each re-entry; j1 (JOIN → CONNECTING → CANCEL → name → BACK → B; JOIN → UNABLE TO CONNECT (TIMEOUT f3445)
  → OK → BACK → B → Mode Select) complete; lo (LOCAL setup → B, LAN page → B, LOCAL setup again → B → Mode Select) unchanged.
  The rejected notice (two instances, host `lanbuild=FAKE`): the guest's first run logged rejected → DIFFERENT GAME VERSION
  (f2985) → OK → name page (f3059) → BACK → LAN page (f3089), then the busy machine stopped it (game-thread watchdog; the
  retry hit the 8 GB memory limit), so no capture of it — it uses the same notice → name → lan → lan_menu_back path as j1 (C).
- Off-identity (V): /tmp/ssw2/lanexit/off.sh and offmp.sh (mp=1) 21/21 PNGs + 1382 `CHT f` lines up to 5300 identical to
  /tmp/ssw2/btn; intro cap.sh 10 2210 10: 221/221 identical to /tmp/ssw2/intro.

## Session 1 part 31 findings (LAN rejoin / disconnects) — V = port verified, C = code read
User bug: "after a joining player leaves and rejoins a lobby, the joining player auto-picks a stage and loads into a broken
battle while the host is soft-locked in the stage select". Code: QoLLan `# ---- LAN SESSION RESET / WATCHDOG (part 31)` (end of
scripts/qol/qol_lan.gd) + part-31 lines in its handshake / message / lockstep code; QoLGame `# ---- LAN SELECT` (5 → 7
redirect: `battle_fresh()` / `battle_redirect()` / `request_room()`, `_lan_sel_seen` token, `mp.cand` reset) and
`_lan_battle_start` (`lan.start_info`). Evidence: /tmp/ssw2/lanrj (two.sh = two headless turbo instances on 127.0.0.1:8131;
chain.sh = one side stays, the other is a sequence of fresh processes each killed -9 / -15 or closed (window-close path) at a
POINT; chainsum.py → NAME.sum; full.sh / busy.sh third process; hconn.sh; capx.sh captures (also of oldproj/ = a copy with the
part-31 fix disabled, for the pictures of the bug); off.sh / offcmp.py / mpreg.sh).
- **Root cause** (H, C + V rj0, rjold, rjoldh): QoLLan's select / stage state lived for the PROCESS, not the session —
  `stage_res` (the host's STAGE_RESULT), `go_round` (SELECT_GO), `rem_ready_round` / `rem_team` / `rem_boss` (the other's
  READY), `rem_round` / `rem_icon` / `rem_chosen` (its stage cursor) were never reset (`_sel_reset_session` reset only this
  machine's half) — while `sel_round` counts from 1 again in every session and every room visit. rj0 (guest: one battle, B
  back to the room, LEAVE, the same process joins again 60 frames later): the rejoined guest (1) left the new team select the
  moment it was READY (the old session's SELECT_GO of round 1), (2) found the old round-1 STAGE_RESULT in the stage select and
  ran the roulette at once (the "auto pick", f6378, 3 frames after entering), (3) at FUN_02001014(7) the redirect asked for a
  LAN battle but `battle_info` had been cleared at the session end → `wants_battle` false → a plain Free Battle on the scene-4
  mode-2 party block (P2 never written): "DSCore: function 00000000 not translated" from f_0202954c and 3723 SCRIPT ERRORs (the
  broken battle). The host left its select on the guest's real READY and waited in the stage select for a cursor that never
  came (rjoldh captures). The host had the mirror problem: its copies of the OLD guest's READY / cursor let it GO and decide
  the 50/50 alone, with the old guest's team (rjold: "HOSTY IS READY" at once on the rejoined guest). A fresh guest process
  only hit the host half; same-process rejoins (LAN page → JOIN again) hit both.
- **Fix 1 — ids on every message** (V): `session_id` (host: random at HELLO → WELCOME "session"), `flow` (host: one per
  proposal: PROPOSE_SELECT {flow} → ACCEPT {flow}; the host takes only an ACCEPT of its last proposal while `_proposed`),
  `round` as before. `_send_msg` adds "sid" / "flow" to every message; `_on_msg` drops ("STALE … dropped") a message of another
  session and a select / stage / battle message (FLOW_MSGS) of another flow; DESYNC / BATTLE_ABORT carry the battle id.
- **Fix 2 — full resets** (V): `_reset_flow()` (rounds, ready / GO, remote team + cursor, stage_res, battle_info, WHERE) at the
  session start (HELLO / WELCOME), the session end (`_end_session`, the host's `_peer_gone`), ACCEPT (both machines) and the
  room's return (scene 0x11 from 4 / 5 / 0); QoLGame's per-round state keys on "session/flow/round".
- **Fix 3 — no battle without a fresh STAGE_RESULT** (V): `battle_fresh(info)` = this session, flow and round; the guest's
  `stage_result()` uses it; the 5 → 7 redirect starts a battle only when it holds (else both back to the room, OUT OF STEP);
  the battle init runs on a copy taken at the redirect (`start_info`), so a session that ends during the scene load starts a
  LAN battle that is left at once through the pause menu (`_start_abort`), never an unsynced plain Free Battle.
- **Fix 4 — battle ids from the host** (H, V oos_nores → oos_nores2): `battle_no` was a per-machine count; after a battle that
  only one machine started (here: the STAGE_RESULT lost on purpose, the host aborted at L3) every later battle of the session
  sent its input records under different ids on the two machines (dropped as "another battle") → both stalled for ever (the
  part-30 rejoin deadlock again, inside one session). STAGE_RESULT now carries "battle" (host: results sent in this session)
  and both use it; records of a later battle are kept (ids may skip). oos_nores2: the next battle identical L1..L1945.
- **Fix 5 — the two machines cannot drift apart unnoticed** (V): WHERE {flow, p} on change and every 1 s, p = 3r team select,
  3r + 1 stage select, 3r + 2 battle (r = round), −1 = no flow (room). The other machine in another flow / in the room / two
  steps away for 5 s, one step away for 30 s (×4 in capture runs), or a lockstep stall of 20 s while its pings still arrive →
  BACK_TO_ROOM to it + this machine to the room (select / stage: the screens' own B exits via `force_leave`; battle: the
  pause-menu abort) with a notice "OUT OF STEP" / "BATTLE STOPPED". Transitions differ by one step for < 1 s (logged "steps
  differ", landbg). V: oos_room (`lanoos=room`: the guest drops to its room without LEAVE_SELECT) → host OUT OF STEP after
  5008 ms, both in the room, next flow 2 battles identical; oos_nores2 (STAGE_RESULT ignored) → host stalled at L3, BATTLE
  STOPPED after 20 s, the guest left the stage select on BACK_TO_ROOM; oos_sil (`lanoos=silent@500`) → both stalled at
  L502-504, both back in the room.
- **Host not in its room** (V busy2): a HELLO while the host is on its way back (aborting a battle, select / stage force-leave)
  → REJECT "HOST NOT IN ITS ROOM - TRY AGAIN" (QoLLanMenu: CONNECTION REFUSED + the reason); while a guest is in → "FULL"
  (full1 / busy2: a third process every 200 / 30 frames: FULL ×9 during the battle / its end, HOST NOT IN ITS ROOM ×18 during the
  abort, then it joined and played; 3 processes = 5.5 GB, run while the other agent was idle).
- **Notices**: a peer-gone notice replaces one not shown yet (rehost: the host's BYE arrived while the guest's room page was
  still loading → it said "BACK TO THE ROOM" on the LAN page; now "<HOST> LEFT").
- **Disconnect matrix** (V; all 0 SCRIPT ERRORs; every survivor back in its room / on the LAN page with a notice; every guest
  settings.cfg before = after (`blood, crt_tv, infinite_health, random_stage`, the host's one_hit_ko never in it); every battle
  that ran on both identical in gameplay hash + RNG, chainsum "hash" lines):
  | run | stays | the other side | result |
  |---|---|---|---|
  | cA | host | guests killed -9 at proposal (guest deciding / host waiting), select, ready, stage, chosen, roulette, intro, battle, pause, end | host "CONNECTION LOST" within frames (localhost), battles left through the pause (intro: L3 → L725), next guest joins clean |
  | cC | guest (same process, lanrejoin) | hosts killed -9 at lobby, select, ready, stage, chosen, roulette, intro, battle, pause, end, then a full run | guest "CONNECTION LOST" → LAN page → rejoins the next host; final battle identical L1..L1945 |
  | cB | host | guests closed (window-close path) at proposal … end, SIGTERM at select / battle, final run | "GUESTY LEFT" (SIGTERM: "CONNECTION LOST"), final battle identical |
  | cD | guest | hosts closed at lobby … end, SIGTERM at stage, final run | "HOSTY LEFT" / "CONNECTION LOST", final battle identical |
  | cP | guest without lanauto | host killed / closed while the guest's proposal popup is open | popup replaced by the notice |
  | cE | host | one guest process: leaves 10 frames into the room, rejoins 10 frames later, ×3, then plays | 3 × "GUESTY LEFT", then identical L1..L1945 |
  | rehost | — | host leaves its room after a battle and hosts again (same process), the same guest process rejoins | both sessions' battles identical |
  | cF | host, lanlag 80 / jitter 20 / loss 10 on both | guests killed / closed at select, ready, stage, roulette, intro, battle, final run | delay 7, all clean, final identical |
  | hconn | — | host closes right after the HELLO, its WELCOME delayed 3 s (lanlag) | guest: connected → "HOSTY LEFT", own settings back |
  | rj2 / final | — | the user's repro on the final code / a 2-round flow (host one_hit_ko + infinite_ki + bombs, guest zoom 4 + shadows) | rejoined guest waits for GO and the fresh result; battles identical (final: B1, B2 L1..L1793, B3 L1..L1047; G differs only by zoom) |
- **SIGTERM** (H, V cB g11 / g12, cD h11): Godot dies without `_exit_tree` (no BYE): the other side reports "lost
  (DISCONNECTED)" at once on localhost (the OS closes the socket), like a crash. Window close (`lanquitat`, the
  get_tree().quit() path) sends the BYE.
- **Test environment** (V): two headless instances use ~1.8 GB each; with the other agent's two xvfb instances (~3.7 GB) the page
  cache fell to ~400 MB and both of mine stopped on the 10 s game-thread watchdog in loading frames (cA first try) — chain.sh
  waits for 2.6 GB free before starting a process.
- **Debug flags (part 31)**: `lanrejoin=N[@C]`, `lanquitat=WHAT[@N]`, `lanoos=room|noresult|silent[@L]`, `landbg` POINT lines
  (docs/LAN_DESIGN.md 8).
- **Pictures of the bug** (V, /tmp/ssw2/lanrj/oldproj = this tree with fixes 1-3 + 5 disabled): rjoldh_sheet.png (host
  captured): the rejoined guest is shown "GUESTY IS READY" in the host's team select while it has already left alone for
  the stage select and its broken battle (guest log: stage result 3 frames after entering, then "function 00000000 not
  translated"); rjold_sheet.png (guest captured, watchdog on): "HOSTY IS READY" at once (the host GOes alone on the old
  READY), then the OUT OF STEP notice in the room page (text fits the popup).
- **Unchanged without a session** (V): /tmp/ssw2/lanrj/off and offmp (mp=1): 21/21 PNGs + 1382 `CHT f` lines up to 5300
  identical to /tmp/ssw2/btn; intro (cap.sh 10 2210 10) 221/221 identical to /tmp/ssw2/intro; LOCAL MP flow (mpreg2.sh: mpsel
  "a", mp=1 mpseed=7, fixed qolcfg) 2525 MP / MPS / MPB / CHT lines identical between the part-30 Linux export
  (/tmp/ssw2/lanqa/expl) and this tree (mpe.flt / mpc.flt; unconfigured runs read the shared user settings.cfg, which other
  runs have changed since the part-30 baseline: devices / zoom / weird lines differ there for that reason only).

## Session 1 part 32 findings (performance mode) — V = port verified, M = measured on the cloud VM, C = code read
- **Deck perflog** (V, the user's perflog.txt, Proton / radeonsi / V-Sync 60): battles `run` 13-15 ms per game frame,
  1.4-2.3 game frames per picture, 24-45 fps, game 55-60 / s; `main` = mostly `wait` for the catch-up game frames that run
  synchronously in `GameDS._process` (only one game frame per picture overlaps the drawing). Spikes 250-690 ms = single
  game-thread frames at scene changes (file loading in the translated code).
- **Where a game frame goes** (M, editor build, heavy Free Battle): translated ARM9 code ~65-75 % (all DS threads; the
  scanline-event callers are separate); ARM7 driver 1.0-2.3 ms; per-line 2D register capture 1.0-1.9 ms (before part 32);
  timers 0.2-0.4; IRQ handlers < 0.3; native mixer 0.2-0.6; scanline loop + clock reads ~1 ms. ~2,000 IO writes per battle
  frame, 1,350 of them geometry command words (0x04000400-0x040005FF). Main thread per picture 3-9 ms in battle, mostly
  VRAM views (whole 512 / 256 KiB regions re-copied whenever a bank's write counter moved: every battle frame) and the
  3D mesh. Details + tables: docs/TOOLING.md part 32.
- **Line registers** (V, H): the per-line registers only matter for the picture; the affine reference points restart
  from BGxX/BGxY at line 0 of every frame, so a frame's 192 lines can be rebuilt afterwards from the register blocks of the
  lines where they changed (`DSMachine._runs`; PB / PD advance them per line exactly as before). Identical buffers over
  6,000 frames (interleaved check), captures identical.
- **Exact speed-ups** (V, M): game thread -10..-20 % (menus 7.0 → 5.7 ms, battle 10.2-12.9 → 9.2-10.9 ms per game frame,
  interleaved A/B); VRAM views 0.68 → 0.12 ms each (native page copies); translucent 3D materials reused. Pictures, RAM
  (CHT lines) and intro audio samples unchanged.
- **PERFORMANCE MODE** (V; `GameDS.set_perf_mode`, settings BIG CHANGES): pipelining always, picture upload after the
  next game frame started (`DSDisplay.refresh_read` / `refresh_apply`), no in-between frames; a 30 fps half rate exists
  behind `perfhalf=auto|1` but is off by default (M: fewer fps at the same game speed with Deck-like frames).
  It never touches the emulated machine: the Free Battle script played in real time with it (pipelined, half rate
  switching) gives all 1382 `CHT f` lines up to 5300 identical to the capture reference; a LAN guest with it on / off
  produces byte-identical lockstep hashes. Not in captures / turbo / pilots (frame-exact paths), not in LAN battles (half
  rate: the LAN time sync owns the pacing there).
- **Expected on the Deck** (M, estimate): game frame ~14 → ~12-12.5 ms (always-on part, both modes); per picture ~1-2 ms
  less on the main thread (VRAM views) and, with PERFORMANCE MODE, the upload half no longer between two game frames
  (`gap` ~2.5 → ~1 ms): one game frame + gap ≈ 13 ms fits a 16.7 ms refresh far more often, so battles should sit much
  closer to 60 fps at full game speed (from 24-45 fps at 55-58 game frames / s); menus already were 60. To be confirmed
  with the next perflog (`PERFLOG ... split` line: `run`, `gap`, `performance on`).
- **Test pitfall** (V): real-time runs without `qolcfg=` read the shared user settings.cfg (here BOMB RAIN was on: the
  battle diverged at f4230); use `qolcfg=<new file>` for defaults. `pkill -f` must not be used (it kills the caller).

## Session 1 part 32 findings (LAN pause) — V = port verified, C = code read
User bugs: (1) pausing a LAN battle showed the HOST's lower screen on the guest (host's team, red Touch!); (2) pausing
"lags the game / raises the ping" until unpaused. Code: scripts/qol/qol_lan_panel.gd (`frame`, `_draw_low`), QoLLan
`battle_side`, QoLController INPUT DISPLAY line, debug flags `lanpace` / `lanwd` (QoLLan, QoLLanNet.loops). Evidence:
/tmp/ssw2/lanpause (capb.sh = `lanbattle=1` pair, one side captured, the other turbo with `lanwd=60`; rt.sh = two
real-time headless instances with `lanpace pingdbg`; lanp.py = pause / fight summary of the LANP lines; two.sh = full flow;
oldproj/ newproj/ = snapshots with the part-31 / part-32 panel for A/B; sheets b1_sheet*.png (before), b2_sheet1.png,
c3_sheet.png, ba_pause.png, fade.png).
- **The battle pause menu is on the UPPER screen** (V b1 p4330-p4750, btn p5150): "Pause Menu / Continue / Return to Character
  Select / Return to Menu" drawn over the dimmed battle picture during battle state u8 0x020DD4C5 == 9; the lower screen
  keeps the game's side-0 panel (G+0x1BCA9 = 0 on both machines) unchanged.
- **Cause of bug 1** (H, C + V b1): QoLLanPanel covered the game's panel only while `(on_battle and st != 9) or st 2-3`, and
  the PING only while `st != 9` — in the pause state the guest saw the game's own side-0 panel = the host's team with the red
  diamond, and no PING. Second case found (V b1 p5820): when the session ends while the battle is still being left (abort
  path: the host left / lost / desync, battle in states 9 / 0x0F+ until FUN_02001014), QoLLan clears `role` and the panel
  (`side := 1 if role == "guest"`) switched to the host's panel too. Every other battle state was already right (V b1: VS
  intro 2-3 from the party block, READY / FIGHT 4-6, fight 7, tag / KO change 0x0C, supers / cut-ins, Team Arts, KO
  0x11, 0x12 / 0x13 end, all with the guest's Piccolo / Goku / Dende and the blue diamond).
- **Fix 1** (V b2 / c3, ba_pause.png): the panel is drawn in every battle state incl. 9, the PING also while paused, the side
  comes from QoLLan.`battle_side` (0 host / 1 guest, set at `_start_lockstep`, kept until the next battle) so the abort path
  keeps the guest's panel (c3 p4820-p4850: own panel, fading with the game); INPUT DISPLAY's guest override uses it too.
  The panel no longer hides / recomposes at every pause / unpause (it also lost the "support greyed after its assists ran
  out" state then: `_sup_seen` was reset on hide). Small extra: the PING is drawn under the panel's fade-to-white (before: it
  stayed on the white screen at the VS-intro → battle flash, fade.png).
- **Pause menu for either player** (V c3): guest Start pauses (L800), guest Down / Down / Up / Up moves the cursor (Return to
  Character Select / Return to Menu / back), guest A on Continue resumes (L951); host Start pauses (L1000), guest A resumes
  (L1101). (The menu reads the DS word = P1 | P2 in state 9 — QoLLan._apply, design 1.3.) Pause → Character Select / Mode
  Select by either player were verified in part 30 (pcs / pms).
- **Bug 2: no pause-specific cost found** (V, numbers below; real time, both instances headless on this 2-CPU VM, 14 pause
  windows vs 11 fight windows of 60 lockstep frames, lanpace): before (oldproj) host fight 56.2 f/s, stalls 12 ms/s, rtt avg
  2.65 ms, CPU 905 ms / 60 frames, frame 13.5 ms; pause 58.3 f/s, stalls 9 ms/s, rtt 3.03 ms, CPU 869 ms, 12.5 ms (guest alike:
  56.0 / 58.5 f/s, rtt 3.16 / 2.91 ms). After (newproj): host fight 55.6 f/s / 15 ms/s / rtt 2.49 / 895 ms / 13.7 ms; pause
  58.2 / 8 ms/s / 2.96 / 847 / 12.9 (guest fight 55.8 f/s rtt 2.09, pause 58.1 f/s rtt 2.14). Input packets 95-98 sent / 90-93
  received per 60 frames in both phases (no message churn, no resend flood); network-thread passes the same; the pause is
  CHEAPER than the fight (single player too: step 8-10 ms paused vs 13-17 fighting, sp3.log; windowed captures 293 vs 553 ms
  per frame incl. llvmpipe drawing, spc/). The LAN layer runs the same code in pause and fight except the panel (fixed
  above; its recompose cost 1.5-2.7 ms per unpause, tbold). WHERE (once a second) and the watchdog do not change with the
  pause. Exported Windows exe under GE-Proton (part-30 export): the network thread uses 5.8 % of a core (Linux 3.4 %) — it
  sleeps, no busy wait. The ping / lag rise the user saw could not be reproduced in this VM (no GPU, no Windows, 2 CPUs
  shared with another agent): open; `lanpace pingdbg` on the user's PCs (exported exe, command line) prints per-60-frame
  real time, stalls, rtt min / avg / max, CPU, frame time, net-thread passes and polls for both phases.
- **Lockstep** (V): b1 / b2 lanhash identical L1..L2300 (two pauses, supers, Team Arts tap, KO, end states); rt_old / rt_new
  identical 2200 frames; full2 (full flow, 2 rounds, host pause + guest unpause and guest pause + host unpause in each
  battle, KO, back to the select, lanrounds 2 → room): both battles identical L1..L2337 incl. the G block, 0 SCRIPT ERRORs.
- **Test notes**: a captured guest is far slower than a turbo host: the part-31 watchdog (20 s lockstep stall, 5 s out of
  step) then sends both back to the room; `lanwd=K` multiplies those limits (default 4 in capture runs). Runs with 4 Godot
  processes on this VM get OOM-killed (8 GB) or hit the 10-s game-thread watchdog.
- Off-identity (V): /tmp/ssw2/lanpause/off and offmp (mp=1) 21/21 PNGs + 1382 `CHT f` lines up to 5300 identical to
  /tmp/ssw2/btn; intro cap.sh 10 2210 10: 221/221 identical to /tmp/ssw2/intro.

## Session 1 part 32 findings (combined verification) — V = port verified, C = code read
Tree = LAN pause fixes + PERFORMANCE MODE / exact runtime speed-ups together. Evidence: /tmp/ssw2/cv32 (lb.sh = `lanbattle=1`
pair, both headless turbo; fl.sh = full flow; rt.sh = real-time `lanbattle=1` pair, MODE hx / gx = host / guest windowed;
capb.sh = guest captured; off.sh / mpreg2.sh = copies of the regression scripts).
- **The perf agent's "desync at L277" is a harness artefact, not a regression** (V): /tmp/ssw2/pm/lan32.sh ran `lanbattle=1`
  without `lanteams=` / `lanbstage=`. Then STAGE_RESULT carries stage -1 / no teams and each machine keeps its own menu's
  battle: the btnrun Free Battle's random stage is resolved by each machine's RTC-seeded RNG (logs: host "stage 1" / "stage 14"
  vs guest "stage 10", parties 0 38 38 on both) → the first checksummed frame after the loader (L277, gp is 0 before
  FUN_0202A40C) differs and the game aborts with DESYNC (correct detection). The host's hash changed between runs while its
  clock was free (stage from the real time). Same flags on the part-31 snapshot /tmp/ssw2/lanpause/oldproj (cv32/old_nostage)
  and on this tree (cur_nostage): the same L277 DESYNC with the same hashes (host 24bcdd65ce15, guest 590719a931e1).
  Fixes: lan32.sh now passes `lanteams=0.5.26/5.0.27 lanbstage=0e` (original kept as lan32.sh.orig; rerun pm/cv_fixed: host
  headless, guest headless `perfmode=1`, real time: identical L1..L1500 incl. the G block); QoLLan `_debug_info` prints
  "LAN WARNING: lanbattle=1 without lanbstage=HEX ..." when the flag is missing.
- **Lockstep on the combined tree** (V): lb a1 (turbo, guest zoom 4 / shadows 1 / own cfg, rtc differ): gp identical L1..L800;
  full flow f3 (lanauto, lanpicks 0.5.26@600 / 5.0.27@200, lanstage 3@400 / 9, lanrounds 2, one_hit_ko host, host pause L720
  resumed by the guest's A L780, guest pause L792 resumed by the host's A L850, in both battles, KO, back to
  select, 2 rounds → room): both battles identical L1..L1917, 0 SCRIPT ERRORs, guest settings kept (infinite_health /
  random_stage / blood). PERFORMANCE MODE on one side only, real time: r1 guest `perfmode=1` headless (L1..L1500, two 0x0B
  events), r2 guest windowed (xvfb) `perfmode=1` (L1..L900), r3 host windowed `perfmode=1` (L1..L698): gameplay hash identical
  in all (G block differs only by the guest's zoom, as designed).
- **Guest panel during the pause** (V, cv32/gp, guest captured, gp_sheet.png): guest Start at L760 → pause f4280; the lower
  screen keeps the guest's panel (Piccolo / Goku / Dende, blue diamond) and the PING through the pause; lockstep identical.
- **Off-identity** (V): cv32/off, offmp (mp=1), offpm (`perfmode=1`: frame-exact run, pipelining off, "performance mode on"
  logged): each 21/21 PNGs + 1382 `CHT f` lines up to 5300 identical to /tmp/ssw2/btn; intro cap.sh 10 2210 10: 221/221 PNGs
  + audio.wav identical to /tmp/ssw2/intro; LOCAL MP flow (mpreg2.sh, fixed qolcfg): 2525 MP / MPS / MPB / CHT lines
  byte-identical to the part-31 tree's /tmp/ssw2/lanrj/mpc.flt.

## Session 1 part 34 findings (All-Star research) — V = port verified, C = code read, M = reasoned
Research for NEW GAMEMODES / ALL-STAR (plan: docs/ALLSTAR_DESIGN.md). Evidence: /tmp/ssw2/as34 (`run.sh NAME EVERY FROM TO
"inputs" [flags]`; max1-3 = Maximum path + course select layer sweep / VRAM+RAM dump, tc1-3 = Free Battle on stage 4 (party
poke) incl. a 62-s stream wrap, rank2-3 = Z-Battle win → HI-SCORE RANKING + layer sweep, rp2 = P2 2-member KO replacement).
- **Mode Select → scene** (C): `FUN_02075738` maps cursor u8 0x020DEC20 → scene (0→4, 1→1, 2→0x11, 3→4, 4→2, 5→3, 6→0xC,
  7→8, 8→9) and calls `FUN_0200297C(cursor)`: the game mode u32 0x020DD514 IS the tile index (0 Z-Battle, 3 Maximum, 5
  Free) + `FUN_02002738(0)`. FREE BATTLE = tile 5 = texture slot 0 + 0x5000 (part 22 layout). Tile labels: white
  condensed capitals ≈5x9 on a black plate, right-aligned; no label contains a "G" (V ms_tiles.png).
- **Maximum flow** (V max1/max2): tile 3 → scene 4 mode 3 (team select, VBlank slot 0x02065E60, DP ∞/∞ with the 100% save)
  → GO → scene 0xB `FUN_0204D0FC` = COURSE SELECT (Novice / Hard / Mania Rank); B there → scene 4 (V max3 f3480 → f3520).
- **Scene 0xB** (C + V): state u8 0x020DE554 (`FUN_0204DB0C` / `FUN_0204DB1C`), loop `FUN_0204D1C4`: 0 first entry
  (`FUN_0204DC98`), 1 back from a Maximum battle (map path), 2-4 load (`FUN_0204E118`, `FUN_020550D0`, `FUN_020550F0` +
  `FUN_020544E4(chosen)`, `FUN_0204DFCC` sound heap 0xC0000 + seq 1), 5 fade-in + `FUN_0200FE48(1)`, 6 input
  `FUN_0204DD8C` (0 = leave), 8 fade, 9 teardown `FUN_0204E0B8` → 10.. map or 0x20 leave `FUN_0204DB60`. Chosen course u8
  0x020DE558 (`FUN_0204D9AC`), exit code u8 0x020DE560: 3 → scene 4, 4 → scene 6, 5 → 0x10, `FUN_0204D9C0` → scene 0
  (sets state 1); B = `FUN_0204DAD0` (3). `FUN_0204DB60` also writes the save copy (`FUN_02004D8C`) unless going to battle.
  The scene never reads the game mode (no `FUN_0200296C` caller in 0x0204D000-0x02055500).
- **Course select graphics** (V max3 layersweep f3300 + RAM): lower = engine A, DISPCNT_A 0x40210D18, BG0 = 3D (header,
  bars, cursor are objects), BG3 = hexagons, BG1/BG2 empty; upper = engine B. q = *(*(0x020DE5A0) + 0x30): +0/+4/+8 bar
  texture handles (256x64 4-bit, texture offsets 0x2000/0x4000/0x6000, labels inside), +0xC cursor frame (+0x1000),
  +0x10 header "COURSE SELECT" (+0x0, 256x32); objects (0x48 bytes, xyz s32 20.12 at +0x3C/+0x40/+0x44, drawn by
  `FUN_0200AEBC`): +0x14/+0x18/+0x1C bars (175,46) (160,100) (146,154) z 20, +0x20 header (111,19), +0x24 cursor
  ((204,46) / (175,100) / (146,154) z 30 by `FUN_020544E4`); +0x3080 u8 cursor, +0x3081..+0x3083 open flags (0xFF; course 0
  always, 1/2 by `FUN_02002498`), +0x28/+0x34 upper data / sizes, +0x40 palette, +0x80 + c·0x1000 upper maps (uploaded with
  `FUN_0200E570(0x4B / 0x33 / 0x41)`). Draw task `FUN_0205495C(task)` (bars ×3, header, cursor). Touch rects
  `FUN_02009844(1, x0, x1, y0, y1)`: 103-247 × 30-62, 78-242 × 84-116, 43-249 × 138-170. Up `FUN_02054248`, Down
  `FUN_020540B8` (skip closed), SE 8 move / 2 decide / 4 back / 0xD buzzer.
- **Team select scene 4 exit** (C `FUN_02066558`): B with no picks → mode 2 ? 0x11 : 6; GO → mode 0 `FUN_0209D244` + 0x12,
  2 host ? 5 : 0x11, 3 → 0xB, else **0**. AFTER its `FUN_02001014` it clears both parties (`FUN_020028E0(0/1)`), moves a
  support back, maps 7 → 0x15 when 0x1E is picked, commits P1 with `FUN_02002838(0, id)` (ids > 0x24 ignored; ids > 0x19
  also set the support word). The mode is not read anywhere else in the select (`FUN_0206B85C` discards it).
- **Character names** (V, `charselect/SubScrNameDataEU.bin` USNAME rendered, portraits / sprites / face icons): 0 Goku, 1
  Goku (Super), 2 Gohan (Super 2), 3 Gohan (Teen) (Buu-arc dark blue gi, red sash), 4 Krillin, 5 Piccolo, 6 Vegeta, 7 Vegeta
  (Super), 8 Trunks (Super), 9 Gotenks (Super 3), 10 Frieza (final form), 11 Mecha Frieza, 12 Ginyu, 13 Dr. Gero, 14
  Android #18, 15 Cell (perfect), 16 Buu (Good) = Majin Buu, 17 Buu (Evil) = Kid Buu, 18 Cooler, 19 Metal Cooler, 20 Broly,
  21 Vegeta (Evil) = Majin Vegeta, 22 Trunks (Teen) (Future Trunks, base), 23 Gotenks, 24 Gohan (Kid), 25 Cell (2nd)
  (semi-perfect, M). Corrects the part-1 guesses at line 40.
- **KO → next member** (C `FUN_0202759C`, V rp2): HP 0 → action 0x33, `FUN_02027164(rec, 0, 0)` forced tag (next member
  with id < 0x1A and HP > 0) → event 7 → battle state 0xC `FUN_02017358` (KO'd fighter falls off, next flies in with icon,
  bar, voices; ≈170 frames, P2 active index team+0x8C8 0 → 1 at sub-state 4) → 7; else Shenron (`FUN_0203483C`), else
  winner / loser teams+0x11D0 / +0x11D4 and event 0xB → state 0x11 (or 10 → 0x10). Events via `FUN_02012FB4` into
  G+0x1BCAA; state-7 dispatch 1-3 → 8, 5 → 0xA, 6 → 0xB, 7 → 0xC, 8 → 0xD, 9 → 0xE, 10 → 0x10, 0xB → 0x11. V: P2 party
  poked to Goku + Piccolo (count 2) in a Free Battle, one-hit KO at f4620 → Piccolo enters, state 7 at f4790; no P2 HUD
  member markers. `FUN_02027164(f, touched, ki%)`: param_2 = 0 → no touch / ki test (KO path); the neutral handler
  `FUN_0202CC70` calls it with (f, 1, 0x14) (tag tap; AI taps via `FUN_0202D820`).
- **Revive / heal** (C): `FUN_020298D4(side)` = Shenron's revive (from `FUN_020348B0`): active HP 0 → the active, else the
  first member with id < 0x1A and HP 0: HP = 10000, +0x254 &= ~0x800, `FUN_020213A8`, +0x250 = 0, `FUN_02021B4C(rec, 0)`,
  `FUN_0201C5C0(side, slot, id, local, hp·0x4A/max, 0/1/2)` (life-bar fill + lower panel palette), `FUN_02026548`, clears
  teams+0x11E4..+0x11F0. `FUN_02029428(rec, n)` heals (clamped to +0x24C; Practice and VM ops use it).
- **Battle timer** (C): G+0x1BCA6 set in `FUN_020140C8` by mode: 1 Story save value or 1800, 2/3 1800, 0/4/5: `FUN_020022B8()` (an
  Option bit) == 0 → 1800 else 0xFFFF (V: ∞ in the port's Free Battles with the 100% save), 10/0xB 0xFFFF; state 7 decrements every 6th frame unless 0xFFFF
  (`DAT_02013C30`), 0 → `FUN_02012FB4(0xC)` + state 0xF. HUD: `FUN_0201272C` copies it to G+0x1BC90, `FUN_0201CDCC(G+0x1BC8C)`
  writes 4 digit cells (thousands..ones) only on change into the BG1 map buffer *(0x020DE3BC) + 0x1774 (entry r,c at
  + (r·32 + c)·2; timer cols 14-17 rows 0-1 = +0x1790 / +0x17D0) from glyph entries +0x1D9E + 2d (row 24 col 21+d, row
  25 = +0x40), blank +0x1DB2, then `FUN_02006B68(1, 0x800)`. 0xFFFF never changes → the base map's ∞ plate stays.
- **Time Chamber = stage id 4** (V tc1): stg_5 (white floor, building with two hourglasses), BGM STRM 5. Top screen
  DISPCNT_A 0x08010F08 (mode 0, map base +0x10000), BG1CNT 0x1900 (HUD, chars 0x0000, map 0x1C800), BG2CNT 0x5A86
  (256 c, chars 0x4000, map 0x1D000, 512x256), BG3CNT 0x1C97 (256 c, chars 0x14000, map 0x1E000 = sky: grey-blue gradient
  + streaks); BG palette indices 32..191 used only by BG3, BG2 only index 17 (single white dots), BG1 row 15; clear colour
  0; fog on DISP3DCNT 0x3A99, FOG_COLOR 0x000F7E10, FOG_OFFSET 0x7FBA. Engine A BG VRAM = bank D (VRAMCNT_D 0x81).
- **Stream position** (C `FUN_020A4438` disassembly, V tc2/tc3): handle u32 0x020DE33C → player P; u32 P+0x158 = samples
  played, u16 P+0xC0 = rate (11141); position ms = P+0x158·1000 / P+0xC0 (used by the BGM pause `FUN_0200FD68`, resume
  `FUN_0200FCF8` restarts `FUN_020A4568(handle, id, offset)`). V: +0x158 ≈ +179 per frame; STRM 5 (691967 samples) at
  0xA8C00 f7440 → 0x1301 f7470 = wrapped to loop start + overflow. STRM HEAD (block at file +0x10): +0x10 loop start, +0x14
  samples, rate +0xC. Lengths: BGM_01..15 62-109 s (05 = 62.1 s, loop 0), BOSS1 93 s, BOSS2 111 s, VS 7 s, CHARA 14 s.
- **HI-SCORE RANKING screen** (V rank2/rank3): results scene 10 (`FUN_0208B578`, Z-Battle only) lower screen: DISPCNT_A
  0x08010508, BG0 = 3D (title plate, 5 rank rows, digits, faces, difficulty), BG2 = hexagons; upper = score breakdown +
  WINNER. Art in `romdata/game/result.bin`: base1st..base5st (256x32 rows with the rank label), e_hi_score (256x32 title
  plate), no0..no9 (8x16 digits), e_easy / e_noaml / e_hard (64x16), e_res_bg (BG), cursol, e_continue / e_charasele /
  e_gameend; faces from game_faceicon.arc.
- **Battle lower screen layout** (V tc1 p4600): portraits y 8-135, "Team Arts" bar x 5-135 y 145-174, Touch! plate x
  128-247 y 145-186, free strip x 8-122 y 175-191; the game's Team Arts touch rect is 8,144-248,184 (part 15).

## Session 1 part 34 findings (All-Star menus) — V = port verified, C = code read, M = reasoned
Phase 1 of NEW GAMEMODES (docs/ALLSTAR_DESIGN.md 2a; code QoLGame `# ---- ALLSTAR MENU`, `qol_allstar_menu.gd`,
QoLController `# ---- ALLSTAR`). Evidence /tmp/ssw2/as1 (`run.sh NAME EVERY FROM TO "inputs" [flags]`): ms (Mode Select VRAM
dump f2600), m1 (GAMEMODE tile, Gamemode menu cursor / taps / ALL-STAR, select, B), m2 (select -> GO -> battle), m3 (pause
-> Return to Character Select -> select -> B chain), max_on / max_off (Maximum from its own tile, NEW GAMEMODES on / off).
- **Mode Select tile labels** (V ms dump, texture slot 0 = bank A, tile k at +k·0x1000, 64 bytes per row): label rows
  32-41, plate index 2 (black), letters index 3 (white) with edge shades 5 / 9 / e (4 / 8 on the plate corners), letter gap
  1 column, right-aligned (last text column 73-74). Letter columns: MAXIMUM (tile 3) M 29-35, A 37-41; STORY MODE (tile 1)
  M 49-55, O 57-62, D 64-69, E 71-74. No label has a G (H). FUN_02073F40 calls `FUN_02001014(FUN_02075738())` (C).
- **Course select objects** (V max3 RAM, corrects the research note): bar objects +0x14/+0x18/+0x1C use texture handles at
  VRAM +0x2000/+0x4000/+0x6000 (handle +0x10 / +0x14 = size codes 5 / 3 = 256x64, +0x18 = 1, the port's 4-bit format code), **palette byte
  obj+4 = 1** (texture palette bank E +0x8020: 1 = 0x033F yellow, 5 = 0x0000 black, 3 = 0x018F, 0xC = 0x00E9 shades),
  obj+5 = alpha 0x1F; header object +0x20 = texture **+0x1000** (palette 0), cursor frame +0x24 = texture **+0x0**
  (palette 3). Object = *obj -> texture handle (+8 VRAM offset). FUN_0200AEBC writes TEXIMAGE / PLTT / vertices
  directly (C): one object can be drawn twice per frame at two positions (V m1: 4 bars from 2 objects) (H).
- **Bar label font** (V max3 bank0): capitals 15 rows (texture rows 27-41), lowercase x-height rows 30-41, ascenders from row
  26; upright (the black triangle left of the text grows 1 px per row); stems 4 px, counters 1 px, letter gap 1 px. Hard bar
  label field: after the triangle + 2 yellow columns, to column 173 (then the barcode plate). M (12 wide) and R (9 wide)
  of "Mania Rank" are the only bar capitals the port needs from the ROM (copied from VRAM at run time).
- **Scene 0xB exits** (C FUN_0204D1C4 / FUN_0204DB60): FUN_0204DA20 = exit == 3, FUN_0204DA00 == 4, FUN_0204D9E0 == 5,
  FUN_0204DA60 == 1 (state 5/6 leave at once); state 0 clears the exit code (FUN_0204DA80). Exit 4 -> FUN_02001014(6)
  (V m3: "scene b -> 6"). Writing exit 3 / 4 and returning 0 from FUN_0204DD8C leaves through the game's own fade.
- **Team select scene 4 in game mode 5** (V m1/m2): DRAGONPOWER shows ∞/∞; GO asks FUN_02001014(0) directly ("scene 4 -> 0
  (asked 0) mode 5"); the teardown asks FUN_02001014(**2**) first, and the real exit is asked while the scene byte
  0x020DD4C4 is already 2 (V m1 "scene 4 -> 2", as LAN's `_lan_from`). Entering scene 4 from a battle (0 -> 4) shows an empty
  team (V m3 p4460).
- **Free Battle pause menu** (V m2 p4820): Continue / Return to Character Select (asks scene 3) / Return to Menu (6).
- **Upper screen of COURSE SELECT** = Mode Select's layout at full brightness (V max2 vs max1): header bar text area y 25-40
  orange (251,162,0) vs (235,150,0); box stripes y % 3 from y 60: (130,97,56) (113,89,40) (121,89,48) vs Mode Select
  (121,89,52) (105,81,36) (113,81,44); text white (251,251,251). (QoLTopInfo.STRIPES lists Mode Select's in the order
  y60, y62, y61 — its rows 61/62 are swapped vs the game (M, cosmetic, untouched).)

## Session 1 part 34 findings (All-Star battle) — V = port verified, C = code read, M = reasoned
ALL-STAR phase 2 (code: QoLGame `# ---- ALLSTAR BATTLE (part 34)`, `qol_allstar_hearts.gd`; plan docs/ALLSTAR_DESIGN.md).
Evidence /tmp/ssw2/as2 (`run.sh NAME EVERY FROM TO "extra inputs" [flags]` = btnrun Free Battle path; `full.sh` = headless
turbo log run): b1 (asstart=22: 3 swaps + win), full (all 26 + win), h1 (hearts), l1 (lose), t1 (CPU tag refused), c1 / c2
(clock cap, pause), v1 (VRAM dump f4600 of a plain Free Battle).
- **Per-frame hook** (C, V): NitroMain's scene update `FUN_020010F4` (`++u16 0x020DD4C0; keys; touch; FUN_020010F4;
  vblank wait`) runs once per game frame in every scene, battle states included (pause 9 too) → the port's All-Star tick
  (after super). Battle states seen (V b1): 4 at f3703 (load done), 5, 6 at the "READY" intro, **7 = FIGHT** (f4185 in
  the btnrun path; f4097-4099 with P1 = Goku only), 0xC = KO replacement (≈169 frames: f4745 → f4914), 9 = pause, 0x11
  the frame after the final KO (battle end), then 0x12, 0x13, scene request 10 (win) / 0x14 (lose).
- **KO replacement of the CPU team** (V b1 / full): P2 = 2 members; the KO'd record stays in its team slot with HP 0 and
  hidden after state 0xC; reloading it on the FIRST state-7 frame after 0xC with `_shuffle_load` (CHARACTER SHUFFLE
  loader) + HP = max HP = u16 *(rec+0x50) (C `FUN_0202A094` writes +0x24C from it, +0x24A = +0x24C) + `+0x254 &= ~0x800`,
  `+0x250 = 0`, `FUN_02021B4C(rec, 0)` (as the revive) works: the next KO's forced tag `FUN_02027164(rec, 0, 0)` finds it
  and the game's own entrance (fly-in, icon, voices, life bar) runs for it. No effect object of the KO'd record was alive
  at that frame in 24 swaps (no wait needed; the check stays). The record's face icon sprite (+0x290) is per record: the
  bench reload's icon upload (`_shuffle_icon`, side-1 buffer) did not change the shown icon (V b1 f4920).
- **Max HP per character** (V full, u16 *(rec+0x50)): 0 13000 (P1 record, h1), 1 16300, 2 18500, 3 14500, 5 13000, 6 13000,
  7 16300, 8 14500, 9 21000, 10 11500, 11 13000, 12 10000, 13 10000, 14 11500, 15 18500, 16 18500, 17 21000, 18 14500,
  19 16300, 20 18500, 21 21000, 22 11500, 23 16300, 24 10000, 25 14500 (reloaded CPU records, boss level 0, Free Battle rules; 4 not reloaded in these runs).
- **Mirror palette rule** (C `FUN_0202A094`): a side-1 record takes the palette at +0x100 (rec +0xFC += 0x100) when ANY of
  side 0's three records has its id (not only P1's active); the reload applies it (V full: swaps 0 → 5 and 5 → 6 with
  P1 = Goku / Piccolo / Vegeta: "mirror true").
- **Heap / file manager over 24 swaps** (V full, `asdbg`): file-cache entries 36 at every swap, open archives 13 from
  swap 5 on (10-13 before, depends on the pair), main heap free 0.92-1.17 MB with no downward trend (pair 9 + 17: 1.04 MB
  in b1 after 2 swaps, 1.07 MB in full after 24) → no leak. 26 enemies in 1:37 of battle clock (one-hit KO).
- **CPU tag / Team Arts** (V t1): the AI's touch taps reach `FUN_02027164(f, 1, 0x14)` and `FUN_02026E34(f)` from the
  neutral handler with f = P2's active (side byte +0x1A = 1); refusing them (return 0) leaves the AI in neutral (t1
  f7094: one tap at 98 % ki, P2 kept its fighter). The KO path calls `FUN_02027164(rec, 0, 0)` (kept).
- **Revive / heal from the port** (V h1): `FUN_020298D4(0)` with P1's active alive revives the first KO'd member (bench,
  hidden): HP 10000, lower panel back to colour (`FUN_0201C5C0`), the record stays hidden until tagged in; then
  `FUN_02029428(rec, max)` clamps to +0x24C. h1 f4800: "0:0/13000, 5:1920/13000" → all 13000.
- **HUD cells** (V v1 dump f4600 + b1): BG1 (4-bit, palette row 15: 1 white 0x7FFF, 4 yellow 0x033F, 0xE black, 5 / 6
  shades) uses tiles 0x00-0x5C; tiles 0x100-0x1FF (VRAM 0x2000-0x3FFF) are all zero in battle; 0x200+ = BG2's 256-colour
  chars (0x4000). Timer plate = cols 12-19 rows 0-2 (entries f001-f005/f403-f401, f006-f00a/f408-f406, f00d-f010/
  f410-f40e); the ∞ ink lies only in cols 14-17 rows 0-1 (y 3-14); rows 3-4 under it are blank (f000). Digit glyphs
  (S = *(0x020DE3BC), S+0x1D9E + 2d / +0x40): 8x16, row 0 white, row 1 black (the plate's top lines), rows 4-12 ink
  7 px wide (x 0-6), blank glyph S+0x1DB2. The BG manager map buffer S+0x1774 equals the VRAM map 0x1C800 (V).
- **Pause** (V c1): state 9, the pause window (upper screen) opens at y ≈ 33 under the HUD — the port gives the tracker
  rows (3-4) back to the game while paused; the battle clock does not run in state 9 (c1: 99:56 from f4499 to f4700).

## Session 1 part 34 findings (All-Star records) — V = port verified, C = code read, M = reasoned
Phase 4 of ALL-STAR (docs/ALLSTAR_DESIGN.md 2a "Phase 4 status"; code `qol_allstar_records.gd`, QoLGame `# ---- ALLSTAR
RECORDS`, header relabel in `QoLAllStarMenu.bars_frame`). Evidence /tmp/ssw2/as4 (`run.sh NAME EVERY FROM TO "inputs"
[flags]`, `win.sh` = btnrun Free Battle as an All-Star battle vs the last enemy): w1 (real win -> page -> tap OK -> select),
d1-d4 (`asrecdemo=2300`: mixed / damaged / full / cheats files; A / START / pad cursor / B), gm0 (VRAM dump of the Gamemode
menu f2800), gm1 (header relabel), max2 (MAXIMUM with NEW GAMEMODES on).
- **`romdata/game/result.bin` art** (H, decoded + V): 0x4C-entry pack; `.ntft` = 4-bit **linear** textures (row-major,
  low nibble first, colour 0 transparent), `.ntfp` = 16 colours. base1st..base5st 256x32 (rank rows; plate yellow 8,
  black 1), e_hi_score 256x32 (title plate: black 1, title rows 5-19 white 0xF with greys 0xB / 0xC / 0xD / 0xE / 2,
  slanted ≈1 px per 4-7 rows, hand-pixelled; square block x 1-14 rows 6-22; underline row 22; plate black up to x 161
  (row 5) .. 154 (row 19)), no0..no9 8x16 (cell yellow 8, ink 1 with greys, ink rows 4-11), e_easy / e_noaml / e_hard
  64x16, e_charasele / e_continue / e_gameend 256x32 ("Character Select" / "Continue?" / "End" plates, black part x 0-43,
  plate x 44-255; their only palette is e_continue.ntfp), cursol 64x64 (results cursor frame), wmlv_0..3; prefixes
  f_ / g_ / i_ / s_ = the other languages. **e_res_bg = the results' UPPER screen** (score breakdown + WINNER, palette
  bank 1), not the ranking's hexagons; the hexagon BG2 file was not found in result.bin / modeselect / scene/common (M:
  elsewhere; ModeSelectMainScrBG is the stripe pattern). Hexagons on the ranking screen (V rank3): period 64 x 32, flat
  top, double walls; colours fill (65,65,130), wall (97,97,186), wall edge (81,81,154).
- **Ranking screen layout** (V as34/rank3 lower screen): title plate at y 1, rank rows at y 28 + 32·i (i = 0..4), score
  digits 8x16 right-aligned to x 122 at row + 8, face icons 24x24 at x 128 / 152 / 176, row + 4, difficulty label in the
  row's lower right part (the row art has a black underline at row + 27, x ≥ 205).
- **`game/game_faceicon.arc`** (H, decoded + V): GARC; entry 2·id = 32x32 4-bit linear (512 bytes; the icon incl. its
  white frame is 24x24 at 0,0), entry 2·id+1 = palette; ids 0-36 (supports 26-36 included; 37 = empty / bar pattern).
  Support icons (V render): 26 two faces (Tien / Yamcha, M), 27 Dende, 28 Hercule, 29 two faces (`sxsv`, Great Saiyaman
  M), 30 Babidi, 31 Cell Jr. (M), 32 Zarbon / Dodoria, 33 Bardock, 34 Dabura, 35 Shenron, 36 Neko Majin (`nmz`).
- **COURSE SELECT header** (V gm0 VRAM dump, slot 0 = bank 0): texture +0x1000 = 256x32 4-bit, palette 0 (bank E
  +0x8000) = black 3, greys 4..0xE, white 0xF (0..2 = border browns / transparent); title rows 8-22 (15 rows), square
  block rows 8-24 from x 16-31, underline row 24 x 30-165, title from x 34 (bottom row) / 37 (top row); plate black to
  x ≈ 177 (row 8) .. 174 (row 22). The port's "GAMEMODE SELECT" (131 px + slant) fits; MAXIMUM's own course select
  is never rewritten (V max2 p3000 / p3050 = as1/max_on = as1/max_off).
- **Win -> results timing** (V w1, one enemy, one-hit KO): last KO f4398, state 0x11 f4399, `FUN_02001014(10)` at f4799
  (≈400 frames of WIN sequence); the battle is still at full brightness the frame before (no fade to black before scene
  10's request) -> the port page cuts to black and fades in (16 frames).
- **P1 support at the end of a battle** (C/M, V w1 = 38 for the btnrun one-member team): u32 0x020DD53C still holds the
  support when the battle asks for scene 10 (the select clears the party only after its own FUN_02001014).
- **Port records rules** (V): file `allstar_records.cfg` (ConfigFile, `[records] r1..r5` dictionaries date / frames /
  hearts / ids); sort frames, hearts, date; equal entries keep the older first; frames shown floor(frames / 59.8261 s).
  d1: r3 = "garbage", r4 with string numbers / int date, r5 with id 99 -> r3 / r5 dropped, r4 kept (strings of digits
  accepted), new 12:34 entry rank 3 of [08:21, 12:32, 12:34, 13:55, 16:42], file rewritten with 5 entries. d2: an
  unparseable file -> engine "ConfigFile parse error" message (no script error), table empty, the file copied to `.bak`,
  new file written. d3: a slower run than all 5 -> "CLEARED! Not in the top 5", file unchanged. d4: cheats on -> "NOT
  SAVED / Cheats are on", file unchanged. w1: no file -> created with the run (10:05, hearts 2, ids [0]).

## Session 1 part 34 findings (All-Star stage) — V = port verified, C = code read, M = reasoned
Phase 3 (space sky + music rotation; code `scripts/qol/qol_allstar_stage.gd` = QoLAllStarStage, QoLGame `# ---- ALLSTAR
STAGE (part 34)`). Evidence `/tmp/ssw2/as3/` (`run.sh NAME EVERY FROM TO "inputs" [flags]`; s1/s4/s5 All-Star captures,
s4b = s4 with the original sky, s2 VRAM dump + layer sweep, s3 object-hide sweep, n2 normal Time Chamber, m1 music
run with audio, rm1 / pz1 headless music logs).
- **BG manager** (C `FUN_02006C6C` / `FUN_02006DCC` / `FUN_02006E50`, V): struct u32 0x020DD7BC: +0x180 u8 queue count
  (≤ 0x20 entries of 12 bytes {src, dst, size} at +0, uploaded at VBlank), +0x181 enabled, +0x1AC + 4·bg = per-BG map
  buffer (FUN_02006DCC copies the map there, then FUN_02006B68 queues buffer → VRAM; stage 4 BG3: 0x021045C8),
  +0x1D8 engine A BG palette shadow (512 bytes; FUN_02006C6C(bg < 4, src, first, count) copies into it and queues
  shadow → 0x05000000 + 2·first), +0x3D8 engine B. FUN_02006E50(bg, data, size) queues characters through a per-BG
  handler table 0x020CEA8C. Stage loader FUN_0201C150: BG2 chars / map / palette (`FUN_02006C6C(2, pal, 0, 0xF0)` =
  240 colours), BG3 chars / map (palette shared). | H |
- **Time Chamber sky = BG3 + a 3D light-ray curtain** (V s2 / s3): BG3 (256-colour text, chars 0x14000, map 0x1E000)
  holds the blue gradient + streaks; on top the 3D stage draws objects 5 / 6 (stg_5.bin, texture index 3 at obj+0x40,
  horizontally repeating flag obj+0x34 = 1) = translucent light rays (blended over BG3: BLDCNT 0x0E41 = BG0 3D first
  target, BG1-3 second, BLDALPHA 0x040C). Objects 0 / 1 = floor (texture 0), 2 = building, 3 / 4 hourglasses / props,
  7 objects (S+0x550). Object visible flag = u16 S+0x44 + i·0x3C + 0xA (scene init 1, never rewritten by the scripts:
  V s3, a poke to 0 stays). | H |
- **Hourglass glass** (V s4 vs s4b): the hourglasses' glass is translucent 3D (alpha) → it shows whatever BG3 has
  behind it; with the black sky the glass looks dark (the sand / frame pixels are identical). Fog (far floor) does not
  blend with BG3: the floor and horizon are pixel-identical (s4 vs s4b: every differing pixel is in the sky or the
  glass, lower screen identical in all 113 frames). | H |
- **Stream position** (V m1 / pz1): P+0x158 advances in blocks of 256 samples (≈187.7 samples / frame at 11141 Hz);
  after a start at an offset (FUN_020A4568(handle, id, ms)) it counts from the offset in samples; after the loop it
  wraps to loop start + overflow. **In battle the BGM manager's +0xA2 bit 0 is already 1** (left set by the last
  FUN_0200FDE4 stop before FUN_0200FE48; only FUN_0200FCF8 clears it): the battle pause's FUN_0200FD68 then does
  nothing → **the battle music keeps playing during the pause** (V s5: +22272 samples over 120 frames of pause). | H |
- **Rotation** (V): `ending` = samples left ≤ largest step + 2 frames (m1: f7442 track 5 at 691456 / 691967, 511 left →
  14; f7933 track 14 at 1151246 / 1151790 → 5 after `asmseek`), forced (`asmusic`), wrap fallback (pos < last). A track
  that ends while paused switches when the fight resumes (pz1: ending at f4474 in state 9 → switch at f4630 on
  resume). RANDOM MUSIC (rm1): first track = the cheat's map (15 for 5), rotation picks played unmapped (15 → 6 → 4).
  Switch = FUN_0200FDE4(0) + FUN_0200FE48(n) with +0xA2 put back: one stream handle → no overlap; a ≤ 1-frame silent
  gap at the switch (m1 audio f8150). | H |

## Session 1 part 35 findings (All-Star records redesign) — V = port verified, C = code read, M = reasoned
The records page (docs/ALLSTAR_DESIGN.md 2a "Phase 4") redrawn as the game's own Z-Battle results scene 10; code
`qol_allstar_records.gd`. Evidence /tmp/ssw2/as35 (`prev.sh NAME` = tools/qol_preview `asrec` states, `run.sh` /
`chain.sh` real-game runs r1-r5, `cmp_ref_full1st.png` = game scene 10 vs the port page). Reference dumps as34/rank3
(f5320 VRAM / palette / IO).
- **Scene 10 upper screen = engine B** (V rank3 io/bank dumps): DISPCNT_B 0x40010700 (BG0-2, BG extended palettes),
  BG0 0x0085 (256 colours, chars 0x4000, ext palette slot 0, VOFS 498 = map row 0 at y 14) = the team portraits,
  BG1 0x020C (16 colours, chars 0xC000, map 0x1000, prio 0) = e_res_bg, BG2 0x041E (16 colours, chars 0x1C000,
  map 0x2000, 512 x 256, prio 2) = hexagons. | H |
- **Portraits** = `romdata/scene/common/CharFace256.bin` members `<abbr>_face.nbfc` (8-bit tiles) / `_face.nbfs`
  (32-wide map, the portrait = top-left 10 x 5 tiles = 80 x 40) in character-id order gkn .. neko (ids 0-36, supports
  included), `nul1_face` / `nul2_face` = the empty slot panel (dark blue), ONE palette `gkn_face.nbfp` (256 colours,
  = VRAM ext palette slot 0 byte for byte). Slot k at x 0, y 14 + 40 k behind the e_res_bg frames. | H (V rank3 BG0
  tiles found in gkn_face.nbfc / nul1_face.nbfc; port render) |
- **Hexagons** (results + ranking BG2 of both engines) = `romdata/scene/common/common_bg.bin` `cstat_bg.nbfc/.nbfs/.nbfp`
  (7 tiles, the map's top-left 8 x 8 tiles = a 64 x 64 tile, rest of the map unused; palette 1 fill (65,65,131),
  2 / 3 walls). Scroll: HOFS 35 / VOFS 477 at f5320, +10 / +22 every 20 frames (f5300 / f5320 / f5340 all pixels
  match), same offsets on both screens. | H (V exact match) |
- **e_res_bg** (result.bin, 4-bit tiles, palette bank 1): table yellow interior x 85-251 y 24-109 (border x 84,
  252-253), labels at text bands y 26 + 16 k (k 0-4, caps rows +2..+9, descender to +12), tab black y 8-23 ("SCORE"
  white x 209-250 y 12-20), Total bar y 110-125 ("Total" x 142-174, orange box x 176-251 y 112-123); below the screen
  the digit strips "0 123456789" the game copies into the table: map rows 24-25 = yellow cells 8 x 16 (digit d at
  x 8 d, y 192; ink rows +4..+11), rows 26-27 = orange cells 8 x 12 (y 208; ink +2..+9) — cell 1 has its '1' at the
  right. The f / g / i / s versions letter the same table in capitals (POINTS COMBAT .., KAMPFPUNKTE .., PUNTI BATT. ..,
  PTOS. BATALLA ..; tab SCORE / PUNKTE / PUNTEGGIO / PUNTUACIÓN; Total / TOTAL / GESAMT / TOTALE). | H (V renders) |
- **Table lettering** (V): black letters = 1-px strokes of index 1 with anti-aliasing 2-7 / 9 on yellow 8; white letters
  = 0xF strokes with greys 0xE / 0xC / 0xD / 0xB / 2 on black 1 (caps 9 rows, the black ones 8). Letters split into
  columns of stroke pixels {1,2,3} for e / g / i / s lines and {1,2} for f lines (the f strokes use more index 3);
  median box gap 0, word gap 5. Letters NOT in any label: lowercase b d j p q v w x y z, capitals H J Q W X Y, digits
  (the strip has them), ! : / -. The port builds d = o + l's stem, H = two l stems + bar, w = two u, ! = top of l + .,
  - / : / slash from the stroke shades.
- **Ranking title plate letters** (V): e/f/g/s/i_hi_score titles are 8-connected white (0xE/0xF) pieces, one per letter
  (the É accent = a 2-px piece); baseline = the letters' last white row (e plate 18-19); capitals available A C D E G H I K
  L M N O R S T and '-'. Spacing measured on the white strokes of rows base-10..base-3 (italic boxes overlap). "ALL-STAR
  RECORDS" in these letters fits the e plate (its end x 163..153, slanted).
- **Difficulty words** (V): e/f/g/i/s _easy/_noaml/_hard (64 x 16, word rows 0-14, underline row 15) = a bolder font
  (2-px strokes); capitals A C D E F H I L M N O R S T W (+ Easy / Normal / Hard lowercase). "NO HEARTS" = 51 px,
  "1 HEART" 36, "2 HEARTS" 46, "3 HEARTS" 45 (gap 1, space 4); the slot after the 3rd face is x 202-251 (row right
  border x 254).
- **Results cursor** `cursol.ntft` (V) is 256 x 32 (not 64 wide): white (0xF) frame rows 0-1 / 30-31, cols 0-1 / 254-255,
  and a white triangle x 4-21 rows 9-26 (left black part of a 256 x 32 plate) = the cursor of the e_continue /
  e_charasele / e_gameend plates (plate: black x 0-43, yellow x 44-253 with an inner line at row 27 / col 250, text
  rows 10-25). | H (render), M (how the game blinks it) |
- **Port page checks** (V, /tmp/ssw2/as35): r1 empty file -> 1st, A; r2 full file -> 1st, START; r3 full -> 5th, tap
  128/178; r4 59:00 not in the top 5 (file unchanged), pad-cursor click 150/178; r5 cheats on (file unchanged), B — each
  `OK by …` at f2369, `closed` f2401. w1 = real All-Star win (`win.sh`, asstart=25 + one_hit_ko): art built in a worker
  thread at session start (1.1 s, f3397), page at f4799 (page build 48 ms), "Cheats On / Not Recorded", Enemies 26/26,
  tap -> the All-Star select revealed (f4931). Preview states (tools/qol_preview `asrec`) draw the same page as the
  game (hexagon scroll aside).

## Session 1 part 35 findings (All-Star sky) — V = port verified, C = code read, M = reasoned
Space sky redesign of the All-Star battle (code `scripts/qol/qol_allstar_stage.gd` = QoLAllStarStage `_build` /
`_sky_tick` / `_palette`; design docs/ALLSTAR_DESIGN.md 2a phase 3). Evidence `/tmp/ssw2/as35sky/` (`run.sh NAME EVERY FROM
TO "inputs" [flags]`; m0 = `asskylog` register log of the part-34 sky, s1 / zm / z4 = new sky (default zoom: intro fade,
KO swap, pause, WIN; zoom 0 + mirror; zoom 4), `sky_built.png` = the built BG3 picture, `before_after_p4300.png`, nA / nB
= normal Free Battle on the Time Chamber with the new / part-34 code).
- **BG3 of stage 4 is never scrolled** (V m0 `asskylog`, f3710-f4880: intro, fight, flight up, pause, KO swap): BG3HOFS /
  BG3VOFS stay 0 (BG3CNT 0x1C97); the parallax is BG2's (HOFS 384 → 305, VOFS 156 → 133 while the camera rises). So the
  sky is a screen-fixed backdrop: map rows 0-23 show, rows 24-31 never; no wrap is ever visible. The horizon (3D floor
  edge) sits at top-screen y ≈ 100 with fighters on the ground (zoom 2) and moves down to y ≈ 145 when the camera rises
  (zoom 0: y ≈ 105). BLDCNT 0x0E41 / BLDALPHA 0x040C / BLDY 0 / MASTER_BRIGHT 0 during the fight and the pause; the intro
  fade is MASTER_BRIGHT (0x800B → 0x8001). | H |
- **Engine A BG VRAM = bank D only** (V part-34 dump s2: VRAMCNT_D 0x81 → 0x06000000; A / B / C = textures): BG1 chars
  0x0000-0x3300 (16-colour, 408 tiles), BG2 chars 0x4000 (its map uses only tiles 0 / 1), **BG3 chars 0x14000-0x1B800 =
  480 tiles of the stage's sky data** (0x1B800-0x1C000 zero), 0x1C000-0x1C800 another 32x32 map (u16 entries 0..0x41,
  not referenced by BG1-3CNT: left alone), BG1 map 0x1C800, BG2 map 0x1D000 (512x256), BG3 map 0x1E000, 0x1E800-0x1F000
  other data. Budget used by the port: BG3 tiles 0..479 only (SKY_TILES = 480). | H |
- **Port sky budgets** (V `asdbg`: `sky: built 386 tiles (0 dropped), ramp 19, palette 32..188, 230 stars + 6 glints`):
  386 distinct tiles (one plain gradient tile per tile row, the rest nebula / star cells; a tile over the budget would
  fall back to its row's plain tile); palette 32-50 = 19-entry 5-bit gradient ramp (y 0 (2,3,9) → y 191 (38,46,90), 8-bit
  anchors), 51-134 = nebula 3 hues (rose / violet / teal) x 4 levels x 7 sky bands, 135-170 = 36 star twinkle slots (4
  height zones x 9 star classes; each slot blends between the mean sky under its stars and the star colour, own period
  80-220 frames / phase), 171-188 = 6 glints x (centre, arms, outer arms); 189-191 free. Dithering: 4x4 Bayer between
  neighbouring ramp entries / nebula levels / hues (dither period 4 → plain cells of one tile row are identical). The
  build is GDScript, ≈ 0.2-0.4 s, run once per QoLAllStarStage on a WorkerThreadPool task started at the battle setup
  (f3422; ready long before the stage's BG3 is up at f3701); per frame: ≤ 157 palette compares + the changed entries
  written (shadow +0x1D8 and palette RAM), spot checks of 8 map entries + 8 tile words. | H |
- **Pause / fades over the new sky** (V s1): the pause's grey-out applies to BG3 as to the other layers (sky
  (8,8,24) → (40,40,48) at p4660, back after the resume; the port writes nothing in state 9 and the twinkle stops);
  the intro's MASTER_BRIGHT fade, KO swap (state 0xC), WIN / KnockOut banner, zoom 0 / 4 and the mirror look right
  (s1 / zm / z4 sheets). The hourglasses' translucent glass now shows the navy sky. | H |
- **Off-identity** (V): btn battle 21/21 PNGs + 1382 `CHT f` lines identical (/tmp/ssw2/off35sky); normal Free Battle on
  the Time Chamber (touch 32/60 on the stage select) with the new code vs the part-34 code: 9/9 PNGs + audio identical
  (nA / nB). | H |

## Session 1 part 35 findings (All-Star life bars) — V = port verified, C = code read (translated ds_game.gd)
- **Life-bar colour buffers** (C + V dump): per side a block B = *(0x020DE3BC) + side·0x258. B+0xF3C = 3 pointers to
  colour buffers of 0xA0 bytes (u16[80]): [0..0x49] the colours of the bar's 74 columns, [0x4A] 0x0800, [0x4B] lost
  colour, [0x4C] full colour, [0x4D] damage flash, [0x4E] low colour, [0x4F] low flash. **Each team member has its own
  buffer and its own colours**: member 1 yellow 0x033F / flash 0x19F2, member 2 lavender 0x7E2E / 0x5969, member 3
  green 0x3EE9 / 0x39C7; lost 0x3484 (navy), low 0x001F / 0x1852 (red) for all (V AS f4357 side 1: buffers at
  0x02101E08 / 0x02101EA8 / 0x02101F48). B+0xF4D[slot] (u8[3]) = buffer index of team member `slot`; the active
  member's is 0 (buffer 0 = the big bar; the two thin bars under it show the bench members' buffers). B+0xF4A /
  +0xF4B shown / target columns (0..0x4A), +0xF4C drain timer, u16 B+0xF48 palette handle, B+0xD3C the 256-colour
  palette uploaded with `FUN_02010AE0(handle, B+0xD3C, 0x200)`. | H |
- **Who paints** (C): the per-frame HUD update (inside the function containing ds_game.gd line ~19190) repaints only
  the ACTIVE member's buffer 0 when that member's HP changes: up → columns 0..v = [0x4C] (or [0x4E] below 0x17
  columns), down → flash then drain to [0x4B] every 4 frames. `FUN_0201CBBC(side, out slot, in slot, HP, max)` (tag
  swap, called by `FUN_020281D8`, also several times during the KO replacement state 0xC) exchanges the two members'
  buffers (0xA0 bytes incl. their colours) and the F4D entries and sets F4A / F4B from HP — it never repaints columns.
  `FUN_0201C5C0(side, slot, id, local, frac·256, panel)` (from the revive `FUN_020298D4`) fills the revived member's
  buffer columns 0..frac·74 with its full colour and, when `local`, writes that member's columns into B+0xF4A / +0xF4B
  even if another member is active. | H |
- **Consequence** (V, the user's report "invisible" bars): a member whose HP rose while benched (heal / revive by
  the All-Star hearts, or All-Star's reloaded CPU record whose buffer was drained to 0x3484 at its KO) came back with
  "lost" navy columns = an empty-looking bar (only the part it had lost). The base game never heals a bench member
  except Shenron's revive (which repaints). | H |
- **Port fix** (V as35bar ko1 / hb2, All-Star only): `QoLGame._asb_bar_paint` repaints a member's buffer from its HP
  with that buffer's own colours (columns < v full / low, the rest lost) and, for the active member, F4A = F4B = v,
  F4C = 0, then uploads the palette; called from an override of `f_0201cbbc` (the incoming member, before super),
  after each heart for every P1 member (`_asb_bars(0)`), and after a CPU record reload (`_asb_load`). V: hb2 (P1 Goku
  KO'd, Piccolo damaged to 3000 then benched, heart, tags): thin bars and the big bar full in each member's colour
  after the heart and after tagging Piccolo / Goku in (hb2_bars.png); ko1 (one-hit KO, 6 enemies): every incoming
  enemy's bar full. | H |

## Session 2, part 36 findings (green demon) — V = port verified, C = code read
- **Battle sound effects** (H, C: every constant-id call of FUN_02029E3C(obj, se) in ds_game.gd, with its caller):
  0 hit (FUN_0201F61C / FUN_0201F6D8 / FUN_02027C2C melee / FUN_02032E24), 1 / 0xA melee (FUN_02027C2C), 0xC step-dash
  burst (FUN_0202C620), 0xE action 0xB (FUN_0202C3E8), 0xF / 0x10 FUN_020214C4, 0x11 KO / tag sequences
  (FUN_02017358 / FUN_02017774, battle states 0xE / 0xD), 0x12 action 0xC FUN_0202C13C (with reaction 0xD), 0x1C
  FUN_0201F5D8 (hit + effect 2), **0x1E** ki-blast explosion (every blast hit handler), 0x1F throw FUN_0202B698, 0x20
  dispatcher FUN_0202AEB4, 0x21 tag sequence FUN_02017D68, 0x29 support call FUN_020277AC, **0x2B big explosion**
  (always with common effect kind 1 size 4 = arg 0x40008: FUN_02016A5C = battle event state 0xF, FUN_020302C0), 0x30
  hit handler FUN_0201F7E0, 0x31 pause FUN_0201546C. M for the names of 0xE-0x12 / 0x1C / 0x20 / 0x30 (context only).
- **0x2B is loaded in every battle** (V gd5a / gd5b: two otherwise identical Free Battle runs, music off, kill with
  SE 0x2B vs none: audio sample-identical up to the kill, then the SE adds RMS ~2500-3200 for ~1.2 s, as loud as the
  rest of the mix together). | H |
- **Fighter speeds** (V, gddbg, fighter +0x38/+0x3C per frame): flying / walking ~2.0-2.6 world px / frame, step
  dash and knock-backs 7-14 px / frame; CPU combos throw fighters 800-1200 px across unbounded stages. | H |
- **FUN_02021DD4(dx, dy)** (H, C): adds (dx, dy) (24.8 fixed, signed) to +0x38 / +0x3C of every live effect object
  (pool [0x020DE3CC], 48 x 0x164, status +4 != 0). Called by the battle wrap-around and the port's STAGE SHUFFLE
  (V gd9 / gd9b: (0, 0) between stages with the same centre). | H |
- **Base Goku's size** (V captures): ~64 world px tall, ~34 wide in his stance; 16 px = 1/4 of his height.
- **GREEN DEMON** (port cheat, page 9 CHALLENGES; scripts/qol/qol_green_demon.gd + QoLGame `# ---- GREEN DEMON (part
  36)`): own RNG (seed `gdseed`, default 0x1F00D, reset at every battle load). Spawn 90 running frames into the fight,
  off the picture (view edge + 24 + 16 px) and >= 320 px from every hunted fighter (hurt-box centres), side with room
  (bounded stages: effect pool +0x4DE7 flag, x0 +0x4DE8, x1 +0x4DEC; both: random), y = their mean +-48 clamped to
  stage top (+0x4DEA) + 24 .. floor (FUN_0201B488 ground +0xCC2 + 64) - 24. Moves straight at the target's hurt-box
  centre at 0.9 px / frame; farther than 300 px: 0.9 + (d - 300) x 0.01, at most 3.0 (catch-up after knock-backs; V
  gd2: 834 -> 75 px; gd7: fleeing players at 2.6 px / frame keep it ~470 px behind). Touch = its 12x12 box (16x16
  picture minus 2 px) overlaps an active hunted fighter's hurt box FUN_0201DF20 type 2 (skipped: HP <= 0, +0x12 & 8,
  frozen +0x250 & 0x800, actions 0x13-0x15 / 0x33). Kill (`QoLGame._gd_kill`): common effect kind 1 arg 0x10008 at
  the 1-UP + SE 0x2B, push FUN_020213A8(0x500, -0x40, dir away), FUN_020293A4 with HP x 256 / scale (+0x1676) and the
  damage cheats skipped (`_gd_killing`), HP forced 0, +0x250 = 0, +0x25D = side, reaction 0x11 FUN_02021B4C, stun 10,
  +0x250 |= 2. The game's own KO follows (V gd1: "KnockOut!! LOSE"; gd4 All-Star team: state 7 -> 0xC, next member
  tags in, All-Star bar repaint, through INFINITE HEALTH). Then warp (same rule as spawn) + rest 120 running frames.
  Frozen in states != 7, KO, pause / cut-in (FUN_02012FD4), tag (globals +0x11DC), camera mode != 0; hidden in action
  0x34. MP (`_mp_on`, local and LAN): random first target, switch every 600 running frames, locked within 24 px of the
  target's hurt box (no switching), lock lost beyond 40 px -> random target, timer 600 (V gd7 / gd8: switches at
  f4786 / f5386, lock f5902, lost f5918 at 40 px). Either player dies on touch. Drawing: one textured quad (16x16
  direct colour at block +0xD00) + floor shadow (16x8 at +0xF00), POLYGON_ATTR 0x1F00C0 = no fog (with the sprites'
  fog bit the ice stage's fog bleached it), polygon ids 0x24 / 0x25, PLTT_BASE keys 16 / 17, z 12 / 1, 1-px bob. | H |
- **Shared port texture block** (V): BOMB RAIN's reserved 0x1000 bytes at texture offset 0x5F000 (key 0x7B0B0B26,
  part 26) moved into scripts/qol/qol_texblock.gd: bombs at +0..0xD00, green demon at +0xD00..0x1000; the block is
  compared / written whole. V: BOMB RAIN run 61/61 captures + 21 bomb event lines identical before / after; both
  cheats on together: one reservation, both drawn.
- **LAN** (V lan1: host GREEN DEMON, guest no cheats, other RTC, CAMERA ZOOM 4): gameplay hash identical all 1538
  lockstep frames (G block differs from L277: drawing-only zoom fields, expected); both logs show the same spawn,
  lock and kill frames. Logic uses the game's unzoomed camera in LAN battles (`lan_battle()`).

## Session 2, part 37 findings (editor vs exe) — V = port verified
- **Editor and exported exe are frame-identical** (V: same flags as ssw2.py, standard battle 21/21 PNGs vs the editor
  baseline; RAM dumps f10..f4090 identical). The apparent divergence (exe vs editor from f3950 pictures / f4100 RAM)
  was the exe loading the player's `user://settings.cfg` (%APPDATA%\DBZSSW2Port\) when a test's fresh `qolcfg=` file
  did not exist (QoLSettings.load_file's read-only-folder fallback, exported builds only): its AFTERIMAGES changed the
  pictures, its BOMB RAIN reserved the port's texture block. Fixed: the fallback only without `qolcfg=`. | H |
- **Texture manager block list in battle** (V ram_exe2/ram_4100.bin, Free Battle Goku vs Goku, ice stage): manager
  [0x020DE380] = 0x02100410, 11 blocks (+0x7AE), pointers +0x600: head sentinel 0x02100B98, block structs 0x02100960 +
  0x10·i (offset, size, key, refs; keys 0x2000000x / 0x364000xx / 0x5000000x / 0x4000004a / 0x5800000a), the port's
  block 11 at 0x02100A00 {0x5F000, 0x1000, 0x7B0B0B26, 1} (BOMB RAIN / GREEN DEMON, parts 26 / 36), tail sentinel
  0x02100BA8 {0x60000, 0}. | H for this battle; M that the addresses are the same in every battle |

## Session 2, part 38 findings (Endless) — V = port verified, C = code read
- **Free Battle loss -> scene 0x14** (V gover, btnrun Goku vs Goku, P1 record HP u16 0x02107812 poked to 0 at f4700):
  battle state 0x11 then 0x12 / 0x13, scene byte 0x020DD4C4 = 0x14 (Game Over / Continue, FUN_0209DED8) from ≈f5200;
  the same poke on P2's record (u16 0x021080FA = 0x02107812 + 0x8E8) gives the WINNER results scene 10. The two
  record addresses are this battle's (HP = record + 0x24A: P1 record 0 at 0x021075C8, P2 record 0 at + 0x8E8, the
  team stride). | H (V) for the btnrun battle; M that the records sit there in other battles |
- **Game Over screen art** `romdata/game/gameover_dat.arc` (V, GARC: u32 count +8 = 27, data base +12, entries
  {offset, size} at +0x10 + 8·i): 0 = 192 bytes chars + 1 palette + 2 map (2048), then 8 groups (chars, palette 32
  bytes, map) at entries 3+3g / 4+3g / 5+3g; groups 0-4 = "Continue? / Yes / No" plates (32x32 maps, one per language),
  groups 5-7 = the Game Over emblem (32x24 maps): 5 = "Game Over" (English), 6 = "PARTIE TERMINEE", 7 = another
  language. Emblem 5: round logo + black plate; title white letters (palette brightness > 0.5) at x 102-229, y 119-144
  (128 x 26), underline at y 147, small print y 150-166, plate borders as white columns / the top edge above y 118. | H |
- **Results panel banner** (V e_res_bg index dump, all five languages; corrects an earlier note here): the WINNER band
  = black rows 138-185 with full-width white (index 15) lines at rows 139 and 184; the word's letters fill rows 144-178
  (35 rows), core index 15 with edge shades 11-14 and 2, on black 1. The word is per language (WINNER / VAINQUEUR /
  SIEGER / VINCITORE / GANADOR) but **one typeface**: the English word is only letter-spaced wider. Letters touch in
  VAINQUEUR (A-I; its V stands alone) and everywhere in VINCITORE; WINNER, SIEGER and GANADOR split into separate
  4-connected shapes of index 15. So the set W I N E R + G A D O + S + V exists; M does not (the port builds it from
  N's 10-px stem + V). GAME OVER at full size is ≈ 270 px wide (band 256). | H |
- **Digit strips** (V result.bin no0..no9, e_res_bg y 192 / 208): 8-px cells, ink rows 4-11; the "1" sits at the cell's
  right (yellow strip: columns 5-6), so fixed cells show "13 1". e_charasele: plate index 0xA, outer frame x 254-255,
  an inner frame line at x 250 (rows 5-27) + row 27; the label's last "t" ends at x 248. cursol is the frame only (no
  letters). | H |
- **Bar textures of scene 0xB in the Gamemode menu** (V esm): rewriting texture +0x6000 (the Mania bar) while the
  Gamemode menu runs and drawing the third bar object (q+0x1C) at slot 1 with bar 0's palette byte shows the relabelled
  bar with the game's cursor frame; MAXIMUM's own course select reloads its textures on entry (unchanged). | H |
- **ENDLESS swaps** (V es1, 47 swaps of random pairs incl. Kid Buu / Broly / Gotenks SSJ3 pairs): heap free 0.98-1.23 MB,
  file cache 24 entries, open archives 7-9, no trend; mirror palette applied when the incoming enemy is P1's
  character. | H |

## Session 2, part 39 findings (parry, randomizer, flightless, knockback) — V = port verified, C = code read
- **Ground / air** (H, C + asm, research agent): fighter u16 +0x10 bit 0 = ON THE GROUND (correction: earlier comments
  said "in the air"); action 5 = ground neutral, 0 = air neutral (FUN_0202B630 picks 0 / 5 by that bit).
  FUN_020214C4 (called for the two ACTIVE fighters by the camera update FUN_02019980, after both FUN_0202954C calls and
  the effect loop): ceiling y0 = s16 effect pool +0x4DEA, floor line y1 = s16 pool +0x4DEE (0x1000 on stages 0/2/7/12,
  else 0x2000; y0 0xAF0 on 7/12, 0xED8 on 8); grounded when (y >> 8) - u8 +0x24F >= y1: y clamped to (y1 + +0x24F) << 8,
  +0xC |= 4; on the first landing frame vertical motion cleared, SE 0xF + action 5 when (+0x250 & 0x1402) == 0, then
  bit 0 set; feet above the floor in action 5 / 6 → action 0 and bit 0 cleared; actions 0xA / 0x26-0x30 are clamped but
  never marked landed; bounce mode +0xE & 0x20 (KO 0x33). Air neutral has no gravity (hovers). | H |
- **Motion** (H, C + asm): FUN_020213A8(o, speed, accel, max, dir) writes +0x22 speed, +0x24 max, +0x26 accel, +0x21
  dir, velocity +0x28/+0x2A = speed·(cos, -sin) >> 8, target +0x2C/+0x2E = max·…, accel +0x30/+0x32 = accel·… (sine
  table 0x020B64D4, 256 steps, ×256). FUN_02021264: position += velocity (24.8 px, y down), velocity += accel, per axis
  when |target - v| <= |accel|: v = target, accel = 0, target += 1 (asm 0x020212E0). Flying: air neutral Up / Down /
  Left / Right → actions 1-4 with constant v = blk+4 · blk+2 >> 8 (~2.3 px/f); ground Up = takeoff FUN_020213A8(0x400,
  -0x40, 0, 0x40) (~32 px over 16 f). A hit push FUN_020213A8(victim, hdr+4, -0x40, 0, attacker +7) lasts s/64 frames,
  ~s²/32768 px; scaling velocity AND accel by k = k × the distance, same duration. | H |
- **Input bits** (H, C): FUN_020011B4(mask, p) tests u16 [p + 4] (p = rec+0x26C → +0x270 HELD), FUN_020011C8(mask, p)
  tests u16 [p] (PRESSED). The dispatcher FUN_0202AEB4: Y+B held → throw 0x2A; R held → R branches; X+A held → clash
  FUN_02026994 / ultimate 0x2E FUN_02026A8C (ki > 0x95 % ·… , +0x274 & 0x40) / super 0x2C (cost blk+0x1F+i, bit i of
  +0x274, i = direction quadrant) with common effect 0xD (ultimate: 0xF + voice 0x20); A pressed → ki blast; Y pressed →
  melee; X pressed → dash; B held → guard 0x18 (+0x250 |= 1). | H |
- **Collision pass** (H, C+V): FUN_0201E5BC uses the list u32 [0x020DE3C0]: u8 +0 count, u8 +1 skip flag, u32 +0x24[]
  objects (fighters and effect objects). Boxes from the frame descriptor +0x120 (u16 +6 count, 12-byte boxes from +8:
  s16 x, y, w, h, s32 type 1 attack / 2, 4 hurt), x scaled by u16 +0x154, y by +0x156 (>> 8), mirrored when 0x40 <= +7
  <= 0xC0; overlap tests with <=; then the attacker's hit handler u32 [+0x34](attacker, victim) for every overlapping box
  pair of different sides (+0x1A) with both +4 != 0. Fighters get +0x34 = 0x02020EC4 (no-op) every frame, melee sets
  FUN_02027C2C. FUN_02027C2C's non-fighter branch (victim +0x10E >= 0x25): a dash attack (0x20 / 0x22, ki >= 10 %) hit
  on a shot whose header [+0x118]+6 <= 2 REFLECTS it: effect 0x3A, velocities +0x28..+0x32 negated, +0x1A = attacker's
  side, +7 / +0x21 += 0x80, sprite rotation FUN_02011F74. Guard branch: hit stop 2 / 3, push, effect 0xB (guard spark,
  at the overlap centre from FUN_0201E210) + SE 0xA, reaction 0xE. FUN_02012F9C(n) = hit stop (globals +0x1BCAC). | H |
- **ULTRA INSTINCT** (port cheat, V): a fighter left out of one pass (+4 = 0 during FUN_0201E5BC) gets no hit, no push,
  no chip; the parried melee attacker in reaction 0x11 with stun 30 + push 0x300 staggers ~40 frames; a reflected blast
  flies back and explodes on its shooter (ui7). The fighters' 4-bit textures drawn through other 16-colour palettes
  (FUN_02010B6C(src, 0x40) once per battle: a slot of the scene's list, e.g. offset 0x11C0) give solid silhouettes
  (modulation tints can only darken). B windows open in actions 0-6 / 0xE / 0x18 only. | H |
- **Battle sounds** (V se2: each id 0-0x31 played every 60 frames in a fight held in hit stop, music off, 32768 Hz):
  loudest / shortest / brightest: 0x21 (tag sequence) 0.33 s, attack < 0.05 s, centroid ~5.9 kHz, the most tonal with
  0x0A (guard) and 0x31; 0x0C step-dash burst 0.6 s whoosh; 0x11 0.37 s; 0x05 bright but slow attack; 0x12-0x2F mostly
  ~1 s long. All are fairly noisy (spectral flatness 0.5-0.64). ULTRA INSTINCT uses 0x21. | M (sound names by context) |
- **RANDOMIZER** (port cheat, V): CHARACTER SHUFFLE's loader inside the dispatcher (after putting the record's 0x2D8
  bytes back) lets another fighter start its own super the same frame; ~50-110 ms per swap. Seen: random ultimates when
  ki allows, Ginyu / Cooler summons keep the fighter transformed until they leave (<= 240 frames), the win pose holds
  the winner frozen (+0x800, camera mode != 0) until action 0x14 (swap back there), hits 0xF / 0x11 mid-super. | H |
- **FLIGHTLESS / SMASH KNOCKBACK** (port cheats, V): +0x60 / frame (max 0x700) added to y of airborne active fighters;
  push × (1 + 2 · HP lost / max). | H |
