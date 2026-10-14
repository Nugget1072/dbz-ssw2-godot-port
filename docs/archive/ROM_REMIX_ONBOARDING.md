# ROM Remix Onboarding: turning the games you own into a new game with Godot + Claude Code

**Who this is for:** a Claude (Claude Code or any Claude) helping someone start a ROM-remix game project from zero.
They may never have used a model, an engine or a hex editor before. Read all of it once. Then you can answer their questions,
set up their machine, and run the project the way it's described here.

**Where it comes from:** a real project, a first-person, early-GameCube-style remake of *Nintendogs: Lab & Friends* (DS)
in Godot 4. It splices in assets and rules from the owner's own dumps of *Animal Crossing: New Leaf* (3DS), *Endless Ocean*
(Wii), *Cooking Mama: Cook Off* (Wii), *Super Mario 64 DS*, *Rune Factory 3* (DS), *Go Vacation* (Wii) and more.
- It has hundreds of Python converters, a Godot project with 600+ scripted test pilots, and a knowledge base of reverse-engineered formats.
- Up to four Claude Code "coordinator" sessions ran it at once, each with a team of background agents.
- Nothing here is specific to that game. It's the method.

---

## 1. The idea (the mindset)

A game cartridge or disc is two things at once:
1. **An art library.** Every model, texture, animation, sound effect, song, font and line of text was made by a
   professional team, and it's all there in the data.
2. **A rule book.** The game's code and tables hold its logic: how hungry a dog gets, what a fish is worth, how fast a
   recipe's timer runs, which villager says what, when.

**ROM remixing** means taking both out of games you own and building something new with them:
- a remake in a different style (a DS game re-imagined as first-person GameCube);
- a mash-up, with one game's town, another game's ocean and another's cooking minigames;
- the game you always wished existed.

**Why it's powerful now:** the hard parts used to be reverse engineering binary formats, writing converters, reading
disassembly, and building and testing an engine project. Those took years of specialist knowledge. Claude can do all of
them, fast, with the human steering by taste. The human's job becomes **vision and playtesting**: "the dog should
knock the landlord over and lick his face, comic-book style, with the game's own bark sounds."

### The house rules that make remixes look great instead of cheap
- **Verbatim art.** Use the source games' real models, textures, sounds and timing. Don't redraw them or invent
  lookalikes. The quality bar is "would this ship in a first-party game". A flat coloured square where a real asset
  should be reads instantly as fake.
- **New geometry is fine when it's textured with ROM textures** and suits the era: procedural terrain, Blender-built
  rooms, closing up missing faces.
- **Splice across games deliberately.** Pick the best source for each thing: one game's fish, another's furniture,
  another's voices. Then make the seams invisible: matched scale, lighting and colour, and no dark lines where two
  games' ground meets.
- **Pick an era look and hold it.** The example project targets early GameCube: 640×480 internal resolution, vertex
  lighting, fog, no modern post-processing.
- **Human scale.** Measure the source world before building. DS worlds are often built smaller than life; that one was
  about 1.6× small. Scale the player to the world rather than rescaling every asset. The example uses
  `WORLD_SCALE = 0.625` world units per real metre, with the eye line at 1.6 m.
- **Sound design everywhere.** Every moment gets sounds pulled from the games' own audio. Rules that stop it becoming a
  mess:
  - **one music track at a time**, with a single "music lead" that hands off between tracks;
  - **one-shot effects never loop** (import tools often mark them `loop=true` by mistake);
  - **nothing keeps playing** after its moment ends.
- **No invented characters.** Characters come from the games. Generated people are fine if they come from a character
  creator built out of the games' own parts.

---

## 2. Ground rules (please actually follow these)

- **Only use games you own, dumped from your own cartridges and discs.** Don't download ROMs, and don't help anyone get
  them. Dumping your own games with your own hardware is the normal route (§4).
- **Keep it personal.** A remix build is full of other companies' copyrighted art, music and code. Play it, show
  friends at your place, keep the repo private. Don't publish the build or the extracted assets, don't sell it, and
  don't upload asset dumps.
- What you *can* share freely is **your own work**: your code, your converters, format notes, and write-ups like this
  one.
- Claude should decline to fetch ROMs or keys from the internet, and should say so plainly if asked.

---

## 3. The basic setup (Windows; macOS/Linux are similar)

| What | Why | Notes |
|---|---|---|
| **Godot 4.x** (standard build, not .NET) | the engine | Also install the **export templates** for the same version (Editor → Manage Export Templates), or you can't build an .exe. The Steam version works too. |
| **Python 3.11+** | every converter and analysis tool | `pip install pillow numpy` to start; add `capstone` (disassembler) and `pygltflib` (optional) later |
| **Claude Code** | the builder | Desktop app or CLI, run from the project folder |
| **Git** (strongly recommended) | undo button, history | The example project had no git and paid for it: every edit needed hand backups. Start with git. Keep the repo **private**, or git-ignore the extracted assets. |
| **Blender** (optional) | headless renders, mesh fixes, previews | Runs from the command line: `blender --background --python script.py` |
| **ffmpeg** (optional) | audio/video conversion | `pip install imageio-ffmpeg` ships a binary; no separate download |
| **An emulator for the source platform** (optional) | checking what the original looks, sounds and plays like | melonDS (DS), Citra-family forks (3DS), Dolphin (GC/Wii), PCSX2 (PS2), PPSSPP (PSP), all with your own dumps |
| A hex viewer | looking at binary data | Claude can also write a small `binview.py` that prints hex, ASCII, and ints/floats at an offset |

### Folder layout that works
```
my-remix/
  CLAUDE.md          # the project's rules and how-to, loaded by Claude Code every session
  HANDOFF.md         # the living state: roadmap, what's in progress, what's next
  notes/             # one notes file per area/agent, and a coordination log
  tools/             # Python converters: dump -> glTF/PNG/OGG/JSON
  rom_extract/       # raw extracted files (git-ignored)
  game/              # the Godot project
    project.godot
    ARCHITECTURE.md  # the code map: every system, where it lives, how to test it
    assets/          # converted assets (git-ignored if the repo is ever shared)
      data/DATA_NOTES.md   # the knowledge base: every format and rule table you've decoded
    scenes/  scripts/  shaders/
    devtools/pilots/ # scripted play-throughs for testing (§8)
  build/             # exported game, one subfolder per release
```
Keep the dumps outside the project (e.g. `C:\Games\Roms\`) and point the tools at them.

---

## 4. Dumping your own games (high level)

Search for the current guide for your platform; the homebrew community keeps these up to date.
- **DS and 3DS cartridges:** a 3DS with custom firmware can dump both. The usual tool is GodMode9: DS carts come out as
  `.nds`, 3DS carts as decrypted `.3ds`/`.cci`. Dump **decrypted** 3DS images from your own console, so no keys are
  needed later.
- **Wii and GameCube discs:** CleanRip on a Wii dumps to `.iso`. Dolphin can compress to `.rvz` and back
  (`DolphinTool`).
- **PS2 discs:** a PC optical drive makes an `.iso` of most discs.
- **PSP UMDs:** a PSP with custom firmware dumps to `.iso`.

Keep the untouched dump. Extract working copies from it.

---

## 5. The pipeline

```
dump (.nds/.3ds/.iso/.rvz)
  -> unpack the container (file system: NitroFS, RomFS, FST/ISO9660)
  -> decompress (LZ77/LZ11/Yaz0/BLZ...)
  -> decode formats (models, textures, anims, audio, text, tables)
  -> write standard files: .glb (glTF 2.0), .png, .ogg/.wav, .json
  -> Godot imports them (headless: godot --headless --path game --import)
  -> gameplay code in GDScript uses them, plus the rule tables as JSON
```

Principles:
- **One converter per format, in `tools/`**, rerunnable, deterministic, and writing a sidecar JSON with what it found.
  You'll rerun converters many times as you learn more about a format.
- **glTF 2.0 (`.glb`) is the interchange.** It's JSON plus one binary buffer. Claude can write it by hand from Python,
  or use `pygltflib`. Put skinning, animations and materials in it where you can. Godot imports `.glb` natively.
- **Preview everything.** Render contact sheets of converted models and textures (PIL, or Blender headless) and
  actually look at them. Most format bugs are obvious in a picture:
  - flipped V coordinates;
  - wrong palette;
  - swapped RGB/BGR;
  - inside-out faces;
  - a model 4096× too big (fixed-point scale).
- **Extract the rules too.** Tables like breed stats, item prices, fish sizes, recipe timings and spawn chances go into
  JSON, with notes on what each field means.
- **Label your confidence.** In `DATA_NOTES.md`, mark each finding H (verified by render or by the code), M (strong
  guess) or L (hunch). It stops guesses hardening into "facts".

### Format cheat sheet, by platform

Every game also has its **own custom formats**; that's where the real reverse engineering happens (§6). These are the
common, well-documented ones.

**Nintendo DS (`.nds`)**
- **Container:**
  - The header at 0x00 points to the ARM9/ARM7 code, the overlays, and the **NitroFS** file system (FNT at 0x40,
    FAT at 0x48).
  - Overlays are code modules loaded on demand. They're often **BLZ**-compressed, which is LZ run backwards from the end.
- **Archives:** many files are **NARC** (`NARC`: BTAF = the file table, BTNF = the names, GMIF = the data), which is a
  NitroFS in a file. Unpack them the same way.
- **Compression:** type byte `0x10` = LZ77, `0x11` = LZ11, `0x24`/`0x28` = Huffman, `0x30` = RLE.
- **3D (the Nitro formats)** are four-letter magic chunks:
  - `BMD0` = NSBMD (models, and often textures);
  - `BTX0` = NSBTX (textures);
  - `BCA0` = NSBCA (skeletal animation);
  - `BTP0` = NSBTP (texture swap anims, e.g. blinking eyes);
  - `BTA0` = NSBTA (UV anims).
  - **Geometry:**
    - It's a **GX display list**, the hardware's command stream.
    - Vertices are fixed-point, times the model's scale.
    - Texture coordinates are in *texels*: divide by the texture size.
  - **Texture formats:** A3I5, 4-colour, 16-colour, 256-colour, 4×4 compressed, A5I3 and direct 16-bit colour.
    - Palettes are stored separately from the texture.
    - "Colour 0 is transparent" is a per-texture flag.
  - The community Rust tool **apicula** converts Nitro models to glTF/DAE, and is a good reference.
- **2D:** the magic is stored reversed:
  - `RGCN` = NCGR (tiles);
  - `RLCN` = NCLR (palettes);
  - `RCSN` = NSCR (screens);
  - `RECN` = NCER (sprites);
  - `RNAN` = NANR (sprite animation).
- **Audio:** **SDAT** contains:
  - SSEQ (sequenced music, like MIDI);
  - SBNK (instrument banks);
  - SWAR (sample archives);
  - SSAR (sequenced SFX);
  - STRM (streamed audio).

  To get music as audio, render SSEQ + SBNK + SWAR yourself (Claude can write a sequencer), or use VGMTrans to get
  MIDI + SoundFont, then render.
- **Text:** **BMG** (`MESGbmg1`), with inline control codes for colours, pauses and variables.
- **Gotcha:** the DS only built the faces its fixed cameras could see. In first person you'll find missing backs and
  open furniture. Use two-sided materials and close up the geometry.

**Nintendo 3DS (`.3ds`/`.cci`)**
- **Container:** NCSD → NCCH partitions.
  - **ExeFS** holds `code.bin` (ARM11 code, often BLZ-style compressed).
  - **RomFS** is the file system.
  - Retail data is encrypted: dump it decrypted (§4). `ctrtool` and `3dstool` unpack it.
- **Archives and compression:** `SARC`, LZ11/LZ13, Yaz0 in some games.
- **3D:** `CGFX` (`.bcres`) and `BCH`. Materials run through the **PICA200** fixed-function "texture combiners". To
  match the look, rebuild those combiner stages as a Godot shader: the example project's `acnl_pica` shader.
  **Ohana3DS** and **SPICA** are references.
- **Audio:** `CSAR` (`.bcsar`) with CWAV/CSTM/CSEQ/CBNK.
- **Text:** `MSBT` (`MsgStdBn`).
- **Animalese:** ACNL's villager speech is built from per-syllable voice samples. Rebuilt, it gives every speaking
  character a real Animal Crossing voice.

**GameCube / Wii (`.iso`, `.rvz`)**
- **Container:** the disc FST. Dolphin can browse and extract files (right-click → Properties → Filesystem), and
  `DolphinTool` converts RVZ ↔ ISO.
- **Archives:** U8 (`0x55AA382D`), RARC.
- **Compression:** `Yaz0`.
- **3D:**
  - Wii: **BRRES** (`bres`) with MDL0 (models), TEX0 (textures), PLT0 (palettes), CHR0 (skeletal anims), SRT0
    (UV anims), PAT0 (texture swaps), CLR0 and VIS0.
  - GameCube: often J3D **BMD/BDL**.
  - **Textures** are tiled in blocks: I4, I8, IA4, IA8, RGB565, RGB5A3, RGBA8, C4, C8, C14X2 and CMPR (DXT1-like).
    TPL and BTI are the file wrappers.
  - **References:** BrawlCrate, Noesis, Dolphin's texture dump feature.
- **Audio:** BRSAR (`RSAR`) with RSEQ/RBNK/RWAR/RWAV; BRSTM for streams.
- **Code:** `main.dol` plus `.rel` modules, PowerPC (Gekko/Broadway). Ghidra has community processor support.

**PS2 (`.iso`)**
- ISO9660, then almost always a **custom archive** per game.
- **Geometry:** usually VIF packets / GS-ready data.
- **Textures:** PSMT8/PSMT4 with CLUTs, often swizzled.
- **Audio:** Sony ADPCM (VAG, or raw).
- **Code:** a MIPS R5900 ELF (`SLUS_...`).
- Expect more custom reverse engineering here than on Nintendo platforms.

**PSP (`.iso`/`.cso`)**
- Common formats: GIM (textures), GMO (models), AT3 (audio).
- **Code:** EBOOT/PRX, MIPS Allegrex (often encrypted).

### Two tiny starter tools (Claude can extend them)
Both were tested on a real DS dump: the extractor pulled all 1,480 files, and 38 of 38 LZ77 files decompressed to their
stated size.

**Extract NitroFS from a `.nds`:**
```python
import struct, os, sys
rom = open(sys.argv[1], "rb").read(); out = sys.argv[2]
fnt, _, fat, _ = struct.unpack_from("<4I", rom, 0x40)
def data(fid):
    s, e = struct.unpack_from("<2I", rom, fat + fid * 8); return rom[s:e]
def walk(dir_id, path):
    sub, fid, _ = struct.unpack_from("<IHH", rom, fnt + (dir_id & 0xFFF) * 8)
    p = fnt + sub
    while True:
        t = rom[p]; p += 1
        if t == 0: break
        name = rom[p:p + (t & 0x7F)].decode("ascii", "replace"); p += t & 0x7F
        if t & 0x80:                                   # a sub-directory
            (sid,) = struct.unpack_from("<H", rom, p); p += 2
            walk(sid, os.path.join(path, name))
        else:                                          # a file
            os.makedirs(path, exist_ok=True)
            open(os.path.join(path, name), "wb").write(data(fid)); fid += 1
walk(0xF000, out)
```

**Decompress DS LZ77 (type 0x10):**
```python
def lz10(d: bytes) -> bytes:
    assert d[0] == 0x10
    size = d[1] | d[2] << 8 | d[3] << 16
    out, p = bytearray(), 4
    while len(out) < size:
        flags = d[p]; p += 1
        for bit in range(8):
            if len(out) >= size: break
            if flags & (0x80 >> bit):                  # a back-reference
                b1, b2 = d[p], d[p + 1]; p += 2
                n, disp = (b1 >> 4) + 3, ((b1 & 0xF) << 8 | b2) + 1
                for _ in range(n): out.append(out[-disp])
            else:                                      # a literal byte
                out.append(d[p]); p += 1
    return bytes(out)
```

---

## 6. Reverse engineering with Claude (how it actually goes)

1. **Survey.** List every file, its size and its first 16 bytes; group by magic and extension. Most containers
   announce themselves.
2. **Look.** Use a hex view at offsets, and read candidate ints and floats. Look for counts that match sizes, offset
   tables, repeating strides (a vertex is often 12–32 bytes), and strings.
3. **Check what's known.** Many formats have community documentation or open-source readers. Read them; don't copy
   code you can't license. Then write your own converter.
4. **Decode, then render.** A converter isn't done until its output has been *looked at*: contact sheets, turntables,
   side-by-side with the emulator.
5. **Go to the code for the rules.**
   - Disassemble with **Capstone** (`pip install capstone`: ARM/Thumb for DS/3DS, PowerPC for GC/Wii, MIPS for
     PS2/PSP), or use **Ghidra**.
   - Find the functions that touch a table, read the maths, and write it down as a formula with its constants.
   - Examples from the example project, all pulled from code:
     - how fast a dog gets hungry;
     - the petting reactions;
     - how a Cooking Mama minigame is scored;
     - ACNL's fish sizes and rarity.
6. **Write it down.** Every finding goes in `DATA_NOTES.md`, with its offset, format, meaning and confidence (H/M/L).
   That file becomes the project's memory. The next agent reads it instead of rediscovering it.

**Common "why does it look wrong" fixes**
- Texture upside down: flip V (`v = 1 - v`), or the image rows.
- Colours off: the palette is BGR555 rather than RGB, or the wrong palette is bound to the texture.
- Holes or see-through faces: the winding is reversed, or the source relied on one-sided faces the camera never saw.
  Use two-sided materials and close the geometry.
- Giant or tiny models: a fixed-point scale factor (e.g. `/4096`) or a model-level scale was missed.
- Spiky skinned meshes: the bind pose or the inverse bind matrices are wrong, or the joint order is mismatched.
- Flickering surfaces (z-fighting): two coplanar surfaces. Offset or delete one, and fix it where things get placed,
  not prop by prop.
- Muddy textures: filtering or mipmaps. Match the source: DS textures are often best with nearest filtering and no
  mips.

---

## 7. Godot, the way it worked here

- **Version:** Godot 4.x, GDScript with static typing (`var x: float = ...`). Forward+ renderer.
- **The era look:**
  - `display/window/size/viewport_width=640`, `viewport_height=480`, stretch mode `viewport`;
  - vertex lighting (`rendering/shading/overrides/force_vertex_shading=true`, or per material);
  - fog; low shadow resolution; no bloom-heavy post.
  - Recreate the source games' **own shaders** where they matter (e.g. ACNL's PICA combiners); don't reach for a
    generic modern PBR material.
- **Autoloads (global singletons):**
  - `Game`: all game state, and save slots as JSON in `user://`;
  - `Scenes`: scene changes and the loading screen;
  - `Sound`: SFX and the music lead;
  - `Dev`: a dev menu with teleports, money, levels and flags.
- **Scenes per area** (`scenes/home`, `scenes/walk`, `scenes/restaurant`, ...), and **scripts per system**
  (`scripts/dog`, `scripts/cooking`, ...).
- **Feature flags on the command line.** Everything after `--` reaches `OS.get_cmdline_user_args()`, so
  `game.exe -- cooking=1 casino=0 cityscale=1` switches features on and off.
  - The export ships two `.bat` launchers: a PLAYTEST launcher (everything on) and a **safe mode** launcher
    (risky features off).
  - Every new feature gets a flag that turns it off. That's how you ship something half-finished without breaking the
    build.
- **Save sandboxes:** `save_dir=C:/some/dir` redirects saves, so tests never touch the player's real save.
- **Imports:** new images, models and audio must be imported before they load:
  `godot --headless --path game --import`, then grep the `.import` files for `valid=false`. Scripts and scenes need no
  import.
- **Export:** `godot --headless --path game --export-release "Windows Desktop" C:/abs/path/build/R1/game.exe` (the
  preset is in `export_presets.cfg`, and the templates must match the editor version).
  - **Export each release into a new folder** so the player can keep playing the old one.
  - Test the exported exe from a temp copy, never the one the player uses.
- **Parse-check scripts headlessly.** `--check-only` doesn't know your autoloads, so use a tiny SceneTree script that
  loads each `.gd` and prints `PARSE OK`/`PARSE FAIL`.
- **Typed-GDScript gotchas:**
  - `var x := <Variant expression>` can't infer a type: write the type.
  - Multi-line lambdas inside array literals break: use methods or `.bind()`.
  - A lambda that captures a node that gets freed errors later: check `is_instance_valid`, or use a `WeakRef`.

---

## 8. Testing like a machine: pilots

The single biggest multiplier: **the game can play itself, take screenshots, and print PASS/FAIL**, so Claude can test
without a human.

- **A pilot** is a script of steps: load a scene, wait, press keys and actions, aim, take screenshots, check state, and
  print a verdict line. Launch one with `godot --path game -- scene=res://scenes/home/Home.tscn pilot=feed shots=C:/tmp/feed hour=13`.
- **Inject input** only through `Input.parse_input_event()` or `Input.action_press()`, never through real devices.
- **Screenshots:** `get_viewport().get_texture().get_image().save_png(path)`. They need a window, because headless
  mode doesn't render. Claude **looks at the images** (contact sheets under ~1,600 px wide) before calling anything
  done.
- **Headless runs** handle logic checks, parse checks and "0 SCRIPT ERROR" sweeps. They're cheap, so use them first.
- **Scanners are pilots too**, checking the whole scene at once:
  - floating props;
  - z-fighting;
  - props hanging over ledges;
  - UI elements overlapping;
  - see-through gaps.

  "Fix it at the system level" means the scanner reads 0 everywhere, not just in the one spot someone noticed.
- **A `tour` pilot** visits every scene. It's the smoke test before every build.
- **Test windows must not bother the person using the PC**, because they play and work while tests run:
  - the window is unfocusable (`display/window/size/no_focus`) and opens on a second monitor, in a corner;
  - the Master audio bus is muted;
  - the mouse is never captured or warped;
  - real mouse, pad and touch input is dropped.
- **Cap the number of windowed Godot instances.** In the example, more than about 5 at once crashed the GPU driver.
  A tiny launcher script hands out "GPU slots".
- **Windows gotcha:** stopping a background shell task can leave its child processes (bash, timeout, the game)
  running. Kill them by command line (`Get-CimInstance Win32_Process`), and check nothing is left over.

A minimal pilot autoload to start from:
```gdscript
extends Node   # autoload "Pilot"; does nothing unless launched with -- pilot=...
var args := {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if not args.has("pilot"):
		return
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	if args.has("scene"):
		get_tree().change_scene_to_file.call_deferred(String(args["scene"]))
	_run()

func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	_shot("00_start")
	await _hold("move_forward", 1.5)
	_shot("01_walked")
	var ok := true   # check real game state here
	print("PILOT PASS" if ok else "PILOT FAIL")
	get_tree().quit()

func _hold(action: String, secs: float) -> void:
	Input.action_press(action)
	await get_tree().create_timer(secs).timeout
	Input.action_release(action)

func _shot(name: String) -> void:
	var dir := String(args.get("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
```

---

## 9. Working with Claude Code on a big project

Start simple: **one Claude Code session, one project, git.** Add the rest as the project grows.

### The files Claude lives by
- **`CLAUDE.md`**: loaded every session. It holds the project's purpose, the rules of the remix, how to run, test and
  export, and the tool paths. Short and strict. Every rule the human states more than once goes here.
- **`HANDOFF.md`**: the living state (roadmap, what's done, what's in flight, the next step). Any new session can
  resume from it.
- **`game/ARCHITECTURE.md`**: the code map. Every system gets a section: files, how it works, how to test it.
- **`DATA_NOTES.md`**: the format and rules knowledge base (§6).
- **`notes/<area>.md`**: one per area of work. It's updated as the work goes (done / half-done / exact next step /
  files mid-edit), so a usage cutoff never loses work.
- **Memory**: Claude Code's persistent memory, for the human's preferences, e.g. "say 'dog', never 'pup'", "no
  downloads without asking".

### Scaling up: background agents
- **The main session becomes a coordinator.** It hands self-contained tasks to background agents: "fix the restaurant
  window shards: here's the screenshot, the likely file, the rules, the tests to run, and what to report."
- **Every agent brief contains:**
  - the rules (link an `AGENT_BRIEF.md`);
  - the exact problem, with the evidence;
  - the files it owns;
  - how to prove it's fixed;
  - what it must never touch (the build, the player's saves, imports).
- **Every agent ends with a report:** what changed, the proof (runs, results, screenshots it viewed), and what's still
  open. The coordinator checks the key screenshots itself before telling the human.
- **Marked code blocks.** Several agents edit the same files, so each one wraps its edits in
  `# >>> A (restaurant) ... # <<< A (restaurant)`. Anyone can see whose code is whose, and nobody overwrites another
  lane's block.
- **Back up before a big edit.** Without git, copy the file to a temp backup first.

### Several coordinators at once (advanced)
- **A shared log**, `notes/COORDINATION.md`, holds:
  - who owns which area (a claim table);
  - Start / READY / FAIL lines, each with proof;
  - FOR <lane> hand-offs.

  Coordinators run a small watcher script that announces new lines.
- **Locks** for anything global: `notes/locks/import.lock` and `export.lock`. The rule is check-then-create, so only
  one import or export runs at a time.
- **Dead-man switches.** Each coordinator's heartbeat file is watched. When a session hits its usage limit, a
  `<X>_DOWN` file appears and another coordinator takes over that session's lanes from their notes.
- **Release discipline:**
  1. Lanes post READY.
  2. QA wave 1 re-runs everything finished so far.
  3. QA wave 2 re-runs the late finishers.
  4. FREEZE: no more edits.
  5. The final core tests run.
  6. Import, then export to a **new** folder.
  7. Smoke-test the exe from a temp copy.
  8. Write the playtest guide: what changed, and how to see each new thing on your own save.
  9. The human plays it.
- **Keep usage lean.** Don't read giant shared files whole. Grep logs for PASS/FAIL lines. Use thumbnails. Give each
  agent one focused milestone.

### How the human steers (tell your human this)
- **Talk about feel and moments**, not code: "the landlord should do an anime blue sigh", "the town should feel
  cozier", "no flowers on the pavement".
- **Playtest, then send notes with screenshots.** The coordinator turns each note into a tracked item with an owner.
- **Standing rules become `CLAUDE.md` lines.**
- **Ask for proof.** "Show me the screenshot" keeps everyone honest.
- **Say which features matter most** for the next build, and anything unfinished ships switched off, with a note in
  the guide.

---

## 10. A starter plan for week one

1. **Set up:** install Godot 4.x + export templates, Python, Claude Code and git. Make the folder layout from §3, and a
   `CLAUDE.md` with the rules of the remix.
2. **Dump one game you own** (§4). Pick one with well-known formats; DS is a great first platform.
3. **First converter:** unpack the file system, survey the magics, then get **one model with its texture** into a
   `.glb`. Render a preview and compare it with the emulator.
4. **First scene:**
   - a Godot project at 640×480 with vertex lighting;
   - that model in a room;
   - a first-person player at human scale (measure a door or a chair in the source and scale the player to match).
5. **First pilot:** walk forward, take a screenshot, print PASS. From now on, every feature gets a pilot.
6. **First rule table:** find one gameplay table (item prices, stats) and pull it into JSON, with notes in
   `DATA_NOTES.md`.
7. **First sound:** convert the game's sound effects and one song. Add the music lead so only one plays at a time.
8. **First splice** (week 2+): bring in a second game you own, and match scale, lighting and colour so the seam
   disappears.
9. **First build:** export into `build/R1/` with a PLAYTEST launcher, then play it and write notes.

---

## 11. Quick answers (FAQ for Claude)

- **"Can you get me the ROM?"** No: dump the games you own (§4). Claude helps with the dumping guide and everything
  after it.
- **"What engine should I use?"** Godot 4: free, scriptable from the command line, headless imports and exports,
  native glTF. Everything here assumes it.
- **"How do I get a model out of X?"** Unpack the container, find the model format's magic (§5), write or adapt a
  converter to `.glb`, then render a preview and fix what's wrong (§6).
- **"Why is my model missing faces or inside out?"** The source only built the faces its camera saw, or the winding
  flipped. Use two-sided materials and close the geometry with a solidify tool.
- **"How do I make it look like the original?"** Match the original's shading (vertex lighting, the platform's
  combiner or TEV stages as a shader), its texture filtering, its resolution and its fog. Don't reach for modern PBR.
- **"How do I get the music?"** Streams (STRM/BRSTM/CSTM) decode to PCM directly. Sequenced music (SSEQ/RSEQ/CSEQ)
  needs its instrument bank and samples rendered through a small sequencer, or converted to MIDI + SoundFont and then
  rendered.
- **"How do I make characters talk like Animal Crossing?"** Rebuild animalese from ACNL's syllable samples: pitch per
  character, one blip per letter.
- **"How do I test without watching it?"** Pilots (§8): scripted input, screenshots, PASS/FAIL, headless where
  possible.
- **"Can I share it?"** Share your code and notes. Keep builds and extracted assets private (§2).
- **"How do I run lots of Claude agents?"** Start with one session. When it's big, use background agents with briefs,
  marked blocks, per-area notes and a coordination log (§9).

---

## 12. Glossary

- **ROM / dump:** the data copied from a cartridge or disc you own.
- **Container / file system:** how files are packed in the dump (NitroFS, RomFS, FST, ISO9660).
- **Magic:** the first bytes of a file that name its format (`BMD0`, `bres`, `Yaz0`).
- **glTF / .glb:** the open 3D interchange format Godot imports.
- **Fixed-point:** integers standing in for fractions (e.g. value/4096). Handhelds use them everywhere.
- **Display list / GX / TEV / PICA:** the graphics hardware's command streams and colour-combiner stages, which a
  shader has to recreate to match the look.
- **Pilot:** a scripted play-through that tests the game and takes screenshots.
- **Lane:** one area of work owned by one agent (e.g. "restaurant", "fishing").
- **READY line:** an agent's "done, with proof" post in the coordination log.
- **Freeze:** the point where edits stop so the final tests and the build run on stable code.
- **Safe mode:** a launcher with the risky features switched off.

---

*Written by Claude (Coordinator A on the Nintendogs GC remix), for a friend starting their own. Have fun, keep it
personal, and make it look like it shipped.*
