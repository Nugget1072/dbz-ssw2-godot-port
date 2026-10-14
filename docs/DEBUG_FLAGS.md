# Debug / test flags (command line, after `--`)

Parsed by the `Game` autoload (`scripts/core/game.gd`): every `key=value` (or bare `key` = "1") after `--` lands in
`Game.args`; code reads them with `Game.args.has("x")` / `Game.flag("x", default)`. All flags are inert unless given.
Verified against `scripts/` + `tools/` (part 32). Procedures that use them: `docs/TESTING.md`; LAN details
`docs/LAN_DESIGN.md` 8; MP inputs `docs/MULTIPLAYER_DESIGN.md` 5.

## Capture, scripted input, test setup
| Flag | Meaning |
|---|---|
| `capture=DIR cap_every=N cap_to=M [cap_from=A]` | frame-exact screenshots `DIR/p<frame>.png` (relative DIR = next to the exe); RTC frozen, settings.cfg ignored; the save file is loaded but (part 37) written only when `save=` is given (the frozen clock would rewrite its 16 block time stamps); `qolcfg=` never falls back to the player's user:// settings (part 37) |
| `cap_fast` | captures draw only the captured frames (not every emulated frame) |
| `capinterp=A` | captures drawn as in-between frames at A (0..1) — smooth-motion checks |
| `layersweep=F` | capture the lower screen one layer at a time at frame F |
| `snap=DIR snap_every=N` | real-time screenshots (no capture mode) |
| `inputs=F:Key:N,F:T<x>/<y>:N` | scripted pad / touch input; `F:F3` = function keys (F3 / F11); `F:K<name>:N` = a raw key through Godot's Input (CONTROLS mapping applies, e.g. `Kspace`) |
| `nds=PATH` `sav=PATH` `save=PATH` | ROM, save to load, save to write |
| `quit_at=F` | quit at game frame F (release stdout is only flushed on a clean exit: always pass it) |
| `rtc=YYYY-MM-DDTHH:MM:SS` | fixed RTC (repeatable runs) |
| `poke=F:ADDR:VAL16[:N]` · `clamp=ADDR:LO:HI` | write RAM at frame F / keep a value in range (e.g. `clamp=021080FA:-32000:200`) |
| `probe=EXPR;EXPR` `probe_every=N` | print RAM expressions every N frames (default 10) |
| `dumpram=F1,F2` · `dumpvram=F` · `dump3d` | RAM / VRAM / 3D dumps |
| `iohook=ADDR+LEN` (`iohook_all`, `iohook_from`, `iohook_val`) | log IO writes |
| `watch=ADDR+LEN` (`watch_from=F`) | store watch points (WATCH=1 build) |
| `trace=F1-F2` | call trace (TRACE=1 build) |
| `profslow=N` | slow-function report (PROFILE=1 build) |
| `qolcfg=PATH` | settings file to use (captures otherwise ignore settings.cfg) |
| `noqol` | no QoL layer at all (plain `DSGame`) |
| `qoldbg` | Mode Select / sound masks every 20 frames; "QOL se", banner icon |
| `qoldump=F` | sound-driver state at frame F |
| `sndlog` · `sndstat` · `sndcnt=F` | sound logs (sndstat / sndcnt force the GDScript mixer) |
| `nocache` | rebuild every VRAM texture every frame |
| `scene=…` (`scripts/core/boot.gd`, default the game), `single_screen=1` (`Game`), `pilot` `shots` `mute` | start scene / pilot (scripted test input, `scripts/pilot/pilot.gd`) |

## Pacing, performance, profiling
| Flag | Meaning |
|---|---|
| `perf` | timings every 600 frames (step, scanlines, sound, 3D, refresh) |
| `perflog` (or env `DBZ_PERFLOG=1`) | `perflog.txt` next to the exe; fields in `scripts/game/ds_perflog.gd`, docs/TOOLING.md parts 26/32 |
| `noprof` | perflog / perf without the scanline timers |
| `perfmark=F1,F2` | process CPU time at those frames |
| `pacelog` | `PACE game <frames/s>` every 5 s |
| `pacedbg` | `PACE d=… steps=… acc=…` per frame (accumulator) |
| `fakehz=N` | pretend display rate |
| `maxfps=N` | Engine.max_fps (0 = uncapped; default 240) |
| `vsync=0` | V-Sync off |
| `smooth=0/1` | smooth motion (in-between frames) off / on |
| `turbo` | one game frame per Godot frame; with `--headless --fixed-fps 60` = CPU benchmark of the game step |
| `pipeline=0\|1\|auto` · `pipedbg` · `fakerender=MS` | frame pipelining (part 26) / print auto switches / simulated driver+present time |
| `perfmode=1` | PERFORMANCE MODE on (part 32) |
| `perfhalf=0\|1\|auto` | 30-fps cadence experiment (off by default) |
| `fakeslow=MS` | every game frame MS longer (slow-CPU simulation) |

## Renderer / native
| Flag | Meaning |
|---|---|
| `gxdump=FROM:N` | capture/gx.bin for `tools/dump_gx.gd`, `cmp_gx.gd`, `bench_gx.gd` |
| `gxthread=0` · `gxdbg` | geometry engine not on its worker thread / print what GPU textures were built from |
| `gxnative=0` `sndnative=0` `fsnative=0` | GDScript versions of the geometry engine / mixer / FS path lookup |
| `present=0` | no SubViewport / DSPresenter (old root-stretch path) |
| `presentfit` | full-screen fit scaling in a window (start with `--resolution WxH`; Xvfb has no window manager) |
| `fxdump` · `fxdbg` | picture effects (dump / debug, SHAKE lines) |
| `shadows=1/0` · `shadowdbg` `shadowk=` `shadowc=` `shadowflip=0` | DETAILED SHADOWS; silhouette debug / squash / shear / direction |
| `zoom=0..4` · `zoomcycle` · `zoomk=F` · `zoomdbg` · `zoomcull=0` | CAMERA ZOOM (2 = the game's own); culling fix off |

## QoL / menu / controls
| Flag | Meaning |
|---|---|
| `autoskip=1` · `skipdbg` | AUTO SKIP |
| `fakepad` · `vcursor=X,Y` · `vcurmove=F:SX:SY:N,…` · `vcurclick=F:N,…` · `curspeed=1..5` · `curdbg` | gamepad mouse cursor (QoLCursor) |
| `btndbg` · `nobutton` | PORT tile art (QoLButton) |
| `lbdbg` · `lbreset=F` | HI-SCORE ranking / reset at frame F |
| `inpdbg` | INPUT DISPLAY |
| `noloadskip` · `dmaread` | shuffle card-DMA freeze repro (`cheats=chaos_shuffle shufseed=49 noloadskip dmaread`) |

## Cheats
| Flag | Meaning |
|---|---|
| `cheats=a,b` | turn cheats on (names in `QoLSettings.CHEATS`) |
| `cheatdbg` | party ids, HP / ki / action / live projectiles every 10 frames; boss setup |
| `shufseed=N` | CHARACTER / CHAOS SHUFFLE picks |
| `stgseed=N` · `stglist=a,b,…` | STAGE SHUFFLE picks |
| `chaosat=F1,F2` | chaos swaps only at these frames |
| `dashdbg` · `nodashfix` | motion / stun trace ("SPAM", "DSH fix"); boss dash fix off (A/B) |
| `p2keys=F:MASK:N` | scripted P2 fighter input |
| `uidbg` | ULTRA INSTINCT (part 39): "UI f… window opens / PARRY … stun / reflect / ignore / MISS / B pressed" lines |
| `uiauto` | ULTRA INSTINCT: every collision pass is a parry window for player 1 (parries every hit: captures of the effects) |
| `uise=N` | ULTRA INSTINCT parry sound (FUN_02029E3C id, default 0x21; -1 = none) |
| `rzseed=N` · `rzto=ID` | RANDOMIZER picks (seed) / always this fighter id (0-25) |
| `rzult` | (part 40) player 1's once-a-battle ultimate flag (+0x24E) cleared every frame: many ultimates in one run |
| `p1hp=F:HP` · `p2hp=F:HP` | (part 40) set player 1's / 2's active fighter's HP at port frame F (red-HP ultimates: `p1hp=4300:1500` + `infinite_health`) |
| `fldbg` | FLIGHTLESS: per-frame height / fall speed / the game's vertical speed of every airborne active fighter |
| `kbdbg` | SMASH KNOCKBACK: launched fighters + camera centre per frame (tether undone), off-camera damage ticks |
| `hpdbg` · `hpseed=N` · `hpfuse=N` · `hpwait=N` | HOT POTATO: light / pass / BOOM lines; its RNG; fuse frames; frames to the first fuse |
| `rcdbg` | RICOCHET KI: every bounce (shot, count, screen position, axis, new direction) |
| `vpdbg` | VAMPIRE (part 41): every heal (victim, attacker, HP lost, healed, new HP) |
| `tsdbg` · `tscpu=N` · `tsauto=F` · `tsseed=N` | TIME SKIP (part 41): start / end lines (reason); CPU chance 1 / N per frame (0 = never, default 300); player 1 skips once at the first battle frame >= F where it may; the CPU RNG seed |
| `dbdbg` · `dbseed=N` · `dbwait=N` · `dbgive=N` · `dbhere=DX` | DRAGON BALL HUNT (part 41): palette / spawn / grab / drop / wish lines; its RNG; frames to the first ball; player 1's team starts with N balls; balls appear DX px right of player 1 |
| `nddbg` | NONDIRECTIONAL (part 42): every substitution (real angle -> chosen angle, the action that started) |
| `zvdbg` · `zvcpu=N` · `zvauto` · `zvseed=N` | Z-VANISH (part 42): vanish / refused / touchable-again lines; CPU vanish chance % per hit stun (default 30, 0 = never); player 1 vanishes whenever it may; the CPU RNG seed |
| `bcdbg` · `bct=N` | BODY CHANGE (part 42): swap lines (HP before / after per side); frames between swaps (default 1200) |
| `texgap` | (part 41) the port texture block's check prints the game's last texture block and the free gap below the port block every battle frame |
| `setest[=A,B,…]` | sound test (part 39): from port frame 4150 the fight is held in hit stop (silent), from 4200 battle sound k plays every 60 frames (all 0-0x31, or the listed ids); "SETEST f… se …" lines; pair with a capture + `--cfg` with `[sound] music=false` (absolute path) |

## Weird stuff
| Flag | Meaning |
|---|---|
| `weird=bevel,fuzzy,epic,fiddle,blood,after,gameboy,mirror,flashy,shake,confetti,dmgnum,rainbow,bombs,inputs,crt` | turn these on (`dmgnum` / `inputs` = DAMAGE NUMBERS / INPUT DISPLAY, settings page 3; `bombs` = BOMB RAIN, a cheat since part 38, also `cheats=bomb_rain`) |
| `epicdbg` · `blooddbg` · `flashydbg` | EPIC MODE / BLOOD / FLASHY KI + CONFETTI debug |
| `w3dbg` · `w3merge=0` | damage numbers / rainbow debug; no merging (stacking test) |
| `bombdbg` `bombseed=N` `bombrate=F` `bombfx=V` `bombfxcycle` `bombkind=K` `bombpos` `bombvram` | BOMB RAIN |
| `gddbg` · `gdpos` · `gdspeed=F` · `gdseed=N` · `gdse=N` · `gdwait=N` | GREEN DEMON (part 36, `cheats=green_demon`): `GD f…` spawn / switch / lock / lock lost / KILL / warp / rest / shift lines + a status line every 60 running frames (position, target, distance, the target's top speed) · `GDPOS` every frame · speed in world px / frame (default 0.9) · RNG seed · kill sound id (`-1` = none, for sound tests) · frames to the first spawn (default 90). `gddbg` / `bombdbg` also print the shared texture block's `TEXBLOCK` lines |

## Local multiplayer (part 27)
| Flag | Meaning |
|---|---|
| `mp=1` | MULTIPLAYER on |
| `mpseed=N` | stage 50/50 pick |
| `mpdbg` | "MP f… stage scene state cur …" every 10 frames (+ heap / archives with `landbg`) |
| `mpbattle=1` | Free Battle as an MP battle (shortcut) |
| `fakepads=N` · `mpdev=k,0` · `mppad=F:DEV:b<n>\|a<n>±:N` | fake gamepads / devices per player / scripted pad input |
| `p2inputs=` | P2 input (same syntax as `inputs=`) |
| `vcursor2` · `vcur2move` · `vcur2click` | P2 pad cursor |

## LAN (parts 30-32; semantics: docs/LAN_DESIGN.md 8)
| Flag | Meaning |
|---|---|
| `lan=host\|join:IP[:PORT]` · `lanport=N` · `lanname=S` · `lanauto` | start hosting / joining at scene 0x11 without menu pages; auto propose / accept |
| `lanbattle=1` (+ **always** `lanteams=a.b.c/d.e.f lanbstage=HEX`) | lockstep test from the btnrun Free Battle (without them each side keeps its own stage → correct DESYNC at L277) |
| `laninputs=L:Btn[+Btn\|T<x>/<y>]:N` · `lanpicks=a.b.c[@D]` · `lanstage=ICON[@D]` · `lanrounds=N` · `lanleave=K` | scripted LAN input / picks / stage / rounds / leave |
| `landelay=N` · `lanlag=MS` · `lanjitter=MS` · `lanloss=PCT` · `lanimpseed=N` | input delay / network impairment |
| `landbg` · `lanmenudbg` · `pingdbg` · `lanpace` | protocol + lockstep log (`POINT <name>`) / menu debug / one line per pong / `LANP` pace line per 60 lockstep frames |
| `lanhash=FILE` | per-lockstep-frame hashes for `tools/linux/lan_cmp.py` |
| `lanquit=L` · `landesync=L` | quit / corrupt one HP at lockstep frame L |
| `lanbuild=S` · `lanrom=S` | fake build id / ROM MD5 (reject tests) |
| `lanpanel=0` · `lanthread=0` | no guest panel / no network thread |
| `lanrejoin=N[@C]` · `lanquitat=WHAT[@N]` · `lanoos=room\|noresult\|silent[@L]` | part 31 rejoin / window-close / forced divergence |
| `lanwd=K` | watchdog limits × K (default 4 in capture runs) |

## NEW GAMEMODES / ALL-STAR (part 34; docs/ALLSTAR_DESIGN.md)
| Flag | Meaning |
|---|---|
| `newmodes=1` / `0` | NEW GAMEMODES on / off for the run (FREE BATTLE tile -> GAMEMODE -> Gamemode menu -> ALL-STAR) |
| `allstar=1` | the btnrun Free Battle becomes an All-Star battle (session starts when the Free Battle path asks for scene 0x13 / 0 in mode 5; no menus needed, NEW GAMEMODES not needed); afterwards the battle exits lead to the All-Star select (scene 4, mode 5) |
| `asstart=N` · `asorder=a,b,c` | first enemy = roster index N / custom enemy order (ids 0-25) |
| `asdbg` | `AS …` lines: tile / bar relabels, Gamemode menu choices, session start / end, scene routing (`AS scene cur -> new (asked x) mode stage active result`), battle events (phase 2) |
| `asp1=a,b,c` | All-Star battle: P1's party for the battle (e.g. 3 members for heart tests; phase 2) |
| `asheart=F[:i],…` · `ashp=F:k:HP,…` | use heart i (default: the first lit one) at port frame F · set P1 record k's HP at frame F (heart / lose tests) |
| `asclock=S` | the All-Star clock starts at S seconds (cap test: `asclock=5990` → 99:59 after 9 s) |
| `asrec=PATH` | ALL-STAR records file for the run (default `allstar_records.cfg` next to the exe / user://; capture runs without it read / write none) |
| `asfakewin=M:SS[:hearts]` | the next All-Star win (or `asrecdemo`) counts as a cheat-free run of the whole roster with that clear time / hearts used (records tests with `cheats=one_hit_ko asstart=25`) |
| `asrecdemo=F` | open the ALL-STAR RECORDS page at port frame F without a battle (team from `asp1=`, else 0,5,6; time 12:34 unless `asfakewin=`; cheats rule kept unless `asfakewin=`); `asdbg` logs `AS f… records open: … rank … saved … table …` / `OK by …` / `closed` |
| `asmusic=F,…` · `asmseek=F:S,…` · `asmseed=N` · `asmlog` | All-Star music (phase 3): force a switch to a random other stage BGM at port frame F · restart the playing track S seconds before its end at F (natural-end tests) · rotation picks seed · `AS f… music: id … pos … / [samples, loop, rate] step … since … A2 … state …` every 30 frames (with `asdbg`; switches log `AS f… music switch #n: a -> b (why) state …`) |
| `endless=1` (with `allstar=1`) | part 38: that btnrun Free Battle is an ENDLESS battle (random enemies with no end; dying -> ENDLESS RECORDS -> All-Star select) |
| `esseed=N` | ENDLESS enemy list seed (N + the session's battle number; default random) |
| `esrec=PATH` | ENDLESS records file for the run (default `endless_records.cfg` next to the exe / user://; capture runs without it read / write none) |
| `esfake=N[:M:SS[:hearts]]` | the next ENDLESS records page counts as a cheat-free run with N enemies beaten (and that time / hearts) |
| `esrecdemo=F` | open the ENDLESS RECORDS page at port frame F without a battle (12 enemies, 08:21 unless `esfake=`; cheats rule kept unless `esfake=`) |
| `bossrush=1` (with `allstar=1`) | part 43: that btnrun Free Battle is a BOSS RUSH battle (18 bosses at their boss levels, one heart; `asdbg` logs `AS f… boss: record … id … level … hp …`) |
| `brstart=N` · `brorder=a,b,c` | BOSS RUSH: first enemy = index N of the boss order / a custom order (ids with a boss version); the run is then "Practice / Not Recorded" |
| `brrec=PATH` · `brrecdemo=F` | BOSS RUSH records file for the run (default `bossrush_records.cfg` next to the exe / user://; capture runs without it: none) · open the BOSS RUSH RECORDS page at port frame F without a battle (with `asfakewin=` as ALL-STAR's) |
| `tournament=1` (with `allstar=1`) | part 43: the btnrun Free Battle's P1 team enters a TOURNAMENT (bracket page first; FIGHT = A) |
| `tnseed=N` · `tndbg` | TOURNAMENT draw / roll seed (N + the draw number; default random) · `TN …` lines: draw, round results and rolls, bracket page open / FIGHT / QUIT / OK |
| `tnrec=PATH` | TOURNAMENT titles file for the run (default `tournament_records.cfg` next to the exe / user://; capture runs without it: none) |
| `assky=0` · `asrays=1` | All-Star battle without the space sky (comparisons) · keep the Time Chamber's light-ray curtain (3D objects 5 / 6) |
| `asskypng=FILE` · `asskylog` | All-Star sky (part 35): write the built 256x256 BG3 sky (twinkle at t = 0) as a PNG when it is built · with `asdbg`, `AS f… skylog: st … BG3CNT … ofs … BG2 ofs … DISPCNT … BLDCNT … BLDALPHA … BLDY … MB …` every 10 frames (`asdbg` alone logs `sky: built N tiles (… dropped), ramp …, palette 32..188, … stars + … glints, … us`) |

## Godot tool scripts (`tools/*.gd`, args after `--`)
`cmp_gx.gd gx=DIR/gx.bin` · `dump_gx.gd gx=… frame=K` · `bench_gx.gd gx=… [native] [reps]` · `dbg_gx.gd` (`dump`, `show`,
`tris`, `texdump`, `hookval`, `frames`) · `dbg_snd.gd` / `dsstats.gd` (`frames`, `every`) · `lockstep.gd` (`ref`, `out`,
`rom`, `frames`, `break=ADDR[:N]`, `cardlog`, `pxilog`, `hang_ms`, `trace`) · `check_rom.gd file=PATH` ·
`qol_preview.tscn -- rom=ROM bg=CAPTURE.png out=DIR [mp fakepads=2 | lan | asrec [asdbg] | tour tnseed=N tnrec=FILE]` (`asrec`: the ALL-STAR RECORDS page in 11 table states, part 35, + the ENDLESS RECORDS page `es_*`, part 38; `tour`: the TOURNAMENT bracket page through a tournament, `tn_*`, part 43 — give `tnrec=` a scratch file: the champion state writes a title) · `assets=DIR` (converted-asset folder of the legacy scenes, `scripts/core/assets.gd`).
