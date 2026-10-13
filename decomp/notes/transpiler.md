# ARM9 -> GDScript transpiler (decomp/tools/transpile, decomp/tools/ghidra2gd.py)

Goal: run the original game logic unmodified. Every ARM9 function is decompiled by Ghidra and translated to a
GDScript method `f_XXXXXXXX` of `DSGame` (scripts/gen/ds_game.gd, generated). Memory is the emulated 8 MiB ARM9
address space `M` (0x02000000-0x027FFFFF incl. DTCM), so every pointer is the original DS address.

## Pipeline (run.sh)
1. Ghidra headless + `ghidra_DecompAll.java`:
   - function starts from `decomp/notes/arm9_function_starts.txt` (+ ITCM block at 0x01FF8000);
   - every `bx lr` is a return (conditional returns otherwise become "unrecovered jump tables");
   - computed tail calls whose register holds a literal-pool function address (`find_icalls.py`) get a
     CALL_OVERRIDE reference so the callee's signature is used;
   - all other computed calls get the signature `f(r0, r1, r2, r3)` (ARM ABI), plus `sp[0..k-1]` when the
     instructions just before the call store outgoing stack arguments (`str rX,[sp,#0..0xc]`, e.g. the NNS
     sound-stream callback with 6 arguments, 0x020A0B48);
   - BIOS call wrappers (short functions containing `swi`) are declared `f(r0, r1, r2, r3) -> r0`, otherwise
     Ghidra drops their arguments (GetCRC16 was called with no data and every save block looked corrupt);
   - runtime division helpers return 64 bits (quotient r0, remainder r1); OS_Disable/RestoreInterrupts pass the
     saved CPSR value;
   - prototypes are inferred bottom-up (callees first) and committed; tail calls inherit the callee's return
     type and every remaining `void` becomes `undefined4` (callers may use r0 left by a callee);
   - `closure.py` / `codeptrs.py` add called-but-undefined addresses and code pointers used as values, then
     Ghidra runs again. `codeptrs.py` (part of the loop since part 5) also accepts leaf functions that follow a
     literal pool when the value is a call argument and the code reaches a return (interrupt handlers passed to
     OS_SetIrqFunction 0x020A8F70, task callbacks passed to 0x020094F4); addresses the code reads as data are
     excluded. This found 14 functions that were silently no-ops before (e.g. HBlank handler 0x02000FB4).
2. `hle_list.py`: only functions that cannot run as plain code are replaced by HLE: CPU state (mrs/msr,
   mcr/mrc other than cache maintenance), BIOS calls (swi), thread context switches, OS_SleepThread
   (0x020AA100), CARDi_SetTask (0x020B1A2C), the division helpers and OS_Terminate.
3. `ghidra2gd.py`: C -> GDScript. Notable rules:
   - canonical integer widths after every operation; pointer arithmetic scaled by the pointee size
     (`code *` is a byte pointer, as in Ghidra);
   - constant addresses outside main RAM -> `io_read/io_write`; pointers that may hold such addresses
     (assigned a non-RAM constant, copies of those, or any pointer in functions that receive IO pointers from
     callers - fixed point over the call graph) use run-time dispatch `_ld/_st`;
   - stack locals whose address is taken are laid out exactly like Ghidra's frame offsets (`local_18` = SP-0x18),
     incl. `stack0x...` references and incoming stack parameters;
   - `void` returns pass through the value of a call immediately before them (tail calls);
   - goto-heavy functions become a block state machine; switch -> `while true` + `match`.
4. Debug builds: `TRACE=1` (call + loop-head tracing, break points `break=ADDR[:N]`), `WATCH=1` (every store
   goes through `_st`, watch points `watch=ADDR+LEN`), `PROFILE=1` (every function behind a timing wrapper;
   GameDS `perf` then prints the 50 functions with the most own time per 600 frames; scanline events, the
   frame hand-over and blocked threads are separate pseudo entries so they are not charged to the caller).

## Runtime (scripts/core)
- `ds_core_base.gd`: BIOS functions (installed by scanning the ARM9 binary for `swi n; bx lr` wrappers: CpuSet,
  CpuFastSet, GetCRC16, Sqrt, WaitByLoop, IsDebugger), memory helpers, IO registers (8/16/32/64-bit accesses) (DIV/SQRT, IPC FIFO, IRQ, GXSTAT, VCOUNT/DISPSTAT, card, DMA,
  VRAMCNT), CPSR I-flag and IRQ delivery (OS_IrqHandler semantics), HLE functions.
- `ds_hardware.gd`: VRAM banks + VRAMCNT mapping, palette, OAM, DMA (immediate / timed / card / GX FIFO),
  game card interface (KEY2 read 0xB7, chip ID 0xB8).
- `ds_arm7.gd`: the ARM7 services behind the PXI FIFO (touch, RTC, power management, sound command lists,
  save memory).
- `ds_boot.gd`: power-on state (cartridge boot + crt0).
- `ds_machine.gd`: runs NitroMain on a Godot thread; SVC_WaitVBlankIntr is the frame boundary.

## Verification (lockstep)
- `tools/melonds-headless/lockstep_ref.py STATE|boot OUT "cmds"`: reference RAM per emulator frame + whether the
  main thread is parked in its vblank wait, the loop counter and the inputs.
- `tools/lockstep.gd` (Godot, headless): runs the port with the same inputs, writes `sync_XXXX.ram` per vblank.
- `decomp/tools/lockstep_align.py REF OUT`: matches port frames to reference frames (same loop counter, closest
  RAM) and lists differences; `lockstep_cmp.py` for snapshot-started runs; `breakref.py` + `break=` for
  code-point snapshots.

## ARM7 (run7.sh, TARGET=arm7)
- The ARM7 binary is translated the same way into `scripts/gen/ds_game7.gd` (class DSGame7, functions `f7_*`) on
  DSCore7Base. Ghidra imports crt0 + the two autoload segments as blocks (ghidra_Arm7Setup.java); function
  starts come from one auto-analysis pass (ghidra_Arm7Funcs.java). `image.py` describes the binary's segments
  for find_icalls / closure / hle_list / ghidra2gd.
- Every ARM7 memory access is dynamic (`_ld/_st`): DSCore7Base resolves main RAM mirrors, WRAM and its own IO.
- Ghidra thunks (auto-analysis creates them) share their target's signature: they are skipped when prototypes
  are reset/committed (resetting a thunk reset the BIOS wrapper behind it).

## Translator fixes found through the ARM7 work (apply to both CPUs)
- Literal-pool constants typed as signed ints are emitted negative (e.g. -723 was 0xFFFFFD2D and compared as a
  huge positive number).
- Shifts by a non-constant amount are clamped to 0..63 (ARM register shifts reach 255; the host masks counts).
- `CONCATxy` of any sizes; `_param_N` (wider view of a stack parameter) = `param_N`.
- Computed tail jumps to Thumb functions (odd literal-pool addresses) get call overrides too.
- Globals named `PTR_<label>_<addr>` are renamed `DAT_<addr>` in the body; their types (from the `//@globals`
  line) are renamed the same way now. Before, they defaulted to `uint` and indexing them failed ("index
  non-pointer"), which left the game-over screen setup 0x0209E1A4 untranslated. All 3,304 functions translate.

## Session 1 part 6 additions
- **Function discovery**: `codeptrs.py` also scans literal pools (words after a return/branch or after other pool
  words) for code addresses whose bodies look like functions (`_body_ok`); addresses used as data are excluded.
  This found 12 callbacks (e.g. 0x02009840, 0x0200731C, 0x02007744: story/menu task callbacks whose absence left
  the Story select and the "dragon ball" text screens stuck). 3,316 functions.
- **Veneers**: `_fn[va] = target  # veneer` aliases for the ARM/Thumb veneers Ghidra does not make functions
  (0x02007544 / 0x02007550 took the 3D of the Practice/Story/Data screens with them: `_missing` returned 0).
- **FASTPATH** (`ghidra2gd.py`): listed functions start with `if _fast_on: var _fr = _fast_call(addr, p1, p2, p3);
  if _fr != null: return _fr` and keep their translated body as the fallback. Only exact, memory-pure SDK
  functions belong there (DATA_NOTES "SDK functions with native fast paths"); each must leave RAM identical in a
  lockstep run with the fast path off (`fsnative=0` for the path lookup).
- **HLE_INLINE**: OS_DisableInterrupts/OS_RestoreInterrupts bodies call `_set_i` directly instead of `_hle`
  (they no longer appear in the lockstep "hle hits" line).

## Session 1 part 7
- Frames allocated with a literal (`sub sp, sp, #big` from a literal pool) appear in Ghidra as `X = -DAT_x;`
  with `&stack0x.. + X` or as `&local_4 + -DAT_x`. The translator adds the literal (largest one) below the
  lowest named offset when laying out the frame (`big` in ghidra2gd.py), so such buffers no longer overwrite
  the callers' frames. The main thread's synthetic stack now starts at 0x027E0200 (15 KiB below STACK_TOP).
