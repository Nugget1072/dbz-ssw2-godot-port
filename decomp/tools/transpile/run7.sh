#!/bin/bash
# ARM7 binary (the NitroSDK sound driver part) -> GDScript (scripts/gen/ds_game7.gd, class DSGame7).
#
#   decomp/tools/transpile/run7.sh [ghidra|gen|all]      (default: all)
#
# Same pipeline as run.sh (see there) with TARGET=arm7: the ARM7 binary is split into crt0 (0x02380000) and its
# two autoload segments, WRAM 0x037F8000 and main RAM 0x027E0000 (decomp/notes: ARM7 layout); Ghidra imports
# them as three blocks (ghidra_Arm7Setup.java). Function starts come from one Ghidra auto-analysis pass.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=${REPO:-$(cd "$HERE/../../.." && pwd)}
export REPO
WORK=${TRANSPILE_WORK7:-$REPO/decomp/extract/transpile7}
export TRANSPILE_WORK=$WORK TARGET=arm7 ARM7_DIR=$WORK/ext7
GHIDRA=${GHIDRA:-$REPO/tools/ghidra_11.4.2_PUBLIC}
GODOT=${GODOT:-godot}
PROJ=$REPO/GodotGame/new-game-project
export GD_OUT=$PROJ/scripts/gen/ds_game7.gd
mkdir -p "$WORK/ghidra/out" "$WORK/ext7"
STEP=${1:-all}

if [ ! -f "$WORK/ext7/wram.bin" ]; then   # split the ARM7 binary (autoload table at 0x023A7760, see notes)
    python3 - "$REPO/decomp/extract/arm7.bin" "$WORK/ext7" <<'PY'
import sys
b = open(sys.argv[1], "rb").read()
open(sys.argv[2] + "/crt0.bin", "wb").write(b[0:0x1B0])
open(sys.argv[2] + "/wram.bin", "wb").write(b[0x1B0:0x1B0 + 0xFDD4])
open(sys.argv[2] + "/mram.bin", "wb").write(b[0x1B0 + 0xFDD4:0x1B0 + 0xFDD4 + 0x177DC])
PY
fi
if [ ! -d "$WORK/ghidra/proj7.rep" ]; then
    "$GHIDRA/support/analyzeHeadless" "$WORK/ghidra" proj7 -import "$WORK/ext7/crt0.bin" -loader BinaryLoader \
        -loader-baseAddr 0x02380000 -processor ARM:LE:32:v5t -scriptPath "$REPO/decomp/tools" \
        -preScript ghidra_Arm7Setup.java "$WORK/ext7" -postScript ghidra_Arm7Funcs.java "$WORK/ghidra/funcs.txt" \
        > "$WORK/ghidra_import.log" 2>&1
fi
[ -f "$WORK/ghidra/funcs.json" ] || echo '{}' > "$WORK/ghidra/funcs.json"

ghidra_pass() {
    python3 "$HERE/find_icalls.py"
    "$GHIDRA/support/analyzeHeadless" "$WORK/ghidra" proj7 -process crt0.bin -noanalysis -scriptPath "$REPO/decomp/tools" \
        -postScript ghidra_DecompAll.java "$WORK/ghidra/funcs.txt" "$WORK/ghidra/out" 0x02000000 0x04000000 arm7 \
        > "$WORK/ghidra.log" 2>&1
    grep -E "created|committed|decompiled|overrides|wrappers" "$WORK/ghidra.log" | sed 's/^INFO  //'
    python3 "$HERE/split_decomp.py"
}

if [ "$STEP" = ghidra ] || [ "$STEP" = all ]; then
    for i in 1 2 3 4; do
        ghidra_pass
        n1=$(python3 "$HERE/closure.py" | tail -1)
        echo "$n1"
        case "$n1" in "added 0 "*) break ;; esac
    done
fi

# ARM7 OS services replaced by the port (DSCore7Base): OS_RescheduleThread, OS_SleepThread (no ARM7 threads),
# OS_GetTick, OS_CancelAlarm / OS_SetPeriodicAlarm / OS_SetAlarm (alarms scheduled in emulated time), the
# OS panic loop, the runtime division helpers (computed jumps). CPU-state code and BIOS calls are found by hle_list.py as for the ARM9.
export HLE7=0x037fc0b4,0x037fc264,0x037fd264,0x037fd550,0x037fd5e0,0x037fd65c,0x037fdfec,0x038072ec,0x038074f8,0x03807500,0x038070e4,0x038070f0,0x0380712c,0x0380713c
if [ "$STEP" = gen ] || [ "$STEP" = all ]; then
    python3 "$HERE/hle_list.py" | cut -c1-80
    python3 -c "
import json, os; d = json.load(open(os.path.join('$WORK', 'ghidra/funcs.json')))
open(os.path.join('$WORK', 'all_functions.txt'), 'w').write('\n'.join(sorted(d)))"
    HLE_LIST=$WORK/hle_functions.txt python3 "$REPO/decomp/tools/ghidra2gd.py" "$WORK/ghidra/funcs.json" - \
        "$GD_OUT" --list "$WORK/all_functions.txt" | head -3
    sed -i '1a class_name DSGame7' "$GD_OUT"
    if command -v "$GODOT" > /dev/null; then
        "$GODOT" --headless --import --path "$PROJ" > /dev/null 2>&1 || true
        "$GODOT" --headless --path "$PROJ" --script res://parsecheck.gd -- res://scripts/gen/ds_game7.gd 2>&1 \
            | grep -E "PARSE|SCRIPT ERROR|Parse Error" | head -10
    fi
fi
