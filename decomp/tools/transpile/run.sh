#!/bin/bash
# ARM9 binary -> GDScript (GodotGame/new-game-project/scripts/gen/ds_game.gd), the whole pipeline.
#
#   decomp/tools/transpile/run.sh [ghidra|gen|all]      (default: all)
#
# Needs (Linux): Ghidra 11.4.x + JDK 21, Python 3 with pycparser, capstone Python bindings, Godot 4.7 (for the
# parse check). Paths below can be overridden with environment variables.
#
#   1. ghidra: decompile every function (function starts: decomp/notes/arm9_function_starts.txt) with the
#      fixes in decomp/tools/ghidra_DecompAll.java (ITCM block, bx-lr returns, call overrides for computed
#      tail calls, r0-r3 for indirect calls, bottom-up prototypes, runtime-helper signatures). New function
#      starts discovered in the output (called addresses: closure.py; code pointers used as values, e.g.
#      interrupt handlers and task callbacks: codeptrs.py) are added and Ghidra
#      is re-run until nothing new appears.
#   2. gen: HLE list (hle_list.py) + translation (ghidra2gd.py) + Godot parse check.
#
# Debug builds: TRACE=1 (call/loop tracing, break points), WATCH=1 (write watch points) - see CLAUDE.md.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=${REPO:-$(cd "$HERE/../../.." && pwd)}
export REPO
WORK=${TRANSPILE_WORK:-$REPO/decomp/extract/transpile}
export TRANSPILE_WORK=$WORK
GHIDRA=${GHIDRA:-$REPO/tools/ghidra_11.4.2_PUBLIC}
GODOT=${GODOT:-godot}
PROJ=$REPO/GodotGame/new-game-project
export GD_OUT=$PROJ/scripts/gen/ds_game.gd
mkdir -p "$WORK/ghidra/out" "$WORK/ext"
[ -f "$WORK/ext/arm9.bin" ] || cp "$REPO/decomp/extract/arm9.bin" "$WORK/ext/arm9.bin"
[ -f "$WORK/ghidra/funcs.txt" ] || cp "$REPO/decomp/notes/arm9_function_starts.txt" "$WORK/ghidra/funcs.txt"
STEP=${1:-all}

ghidra_pass() {
    python3 "$HERE/find_icalls.py"
    if [ ! -d "$WORK/ghidra/proj.rep" ]; then
        "$GHIDRA/support/analyzeHeadless" "$WORK/ghidra" proj -import "$WORK/ext/arm9.bin" -loader BinaryLoader \
            -loader-baseAddr 0x02000000 -processor ARM:LE:32:v5t -noanalysis > "$WORK/ghidra_import.log" 2>&1
    fi
    "$GHIDRA/support/analyzeHeadless" "$WORK/ghidra" proj -process arm9.bin -noanalysis -scriptPath "$REPO/decomp/tools" \
        -postScript ghidra_DecompAll.java "$WORK/ghidra/funcs.txt" "$WORK/ghidra/out" 0x1ff8000 0x20b7000 \
        > "$WORK/ghidra.log" 2>&1
    grep -E "created|committed|decompiled|overrides" "$WORK/ghidra.log" | sed 's/^INFO  //'
    python3 "$HERE/split_decomp.py"
}

if [ "$STEP" = ghidra ] || [ "$STEP" = all ]; then
    for i in 1 2 3 4; do
        ghidra_pass
        n1=$(python3 "$HERE/closure.py" | tail -1)
        n2=$(python3 "$HERE/codeptrs.py" | tail -1)
        echo "$n1 / code pointers: $n2"
        case "$n1 $n2" in "added 0 "*"added 0 "*) break ;; esac
    done
fi

if [ "$STEP" = gen ] || [ "$STEP" = all ]; then
    python3 "$HERE/hle_list.py" | cut -c1-60
    python3 -c "
import json, os; d = json.load(open(os.path.join('$WORK', 'ghidra/funcs.json')))
open(os.path.join('$WORK', 'all_functions.txt'), 'w').write('\n'.join(sorted(d)))"
    HLE_LIST=$WORK/hle_functions.txt python3 "$REPO/decomp/tools/ghidra2gd.py" "$WORK/ghidra/funcs.json" "$WORK/ext/arm9.bin" \
        "$GD_OUT" --list "$WORK/all_functions.txt" | head -3
    sed -i '1a class_name DSGame' "$GD_OUT"
    if command -v "$GODOT" > /dev/null; then
        "$GODOT" --headless --import --path "$PROJ" > /dev/null 2>&1 || true
        "$GODOT" --headless --path "$PROJ" --script res://parsecheck.gd -- res://scripts/gen/ds_game.gd 2>&1 \
            | grep -E "PARSE|SCRIPT ERROR|Parse Error" | head -10
    fi
fi
