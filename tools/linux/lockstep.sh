#!/bin/bash
# lockstep.sh REFDIR [frames] [extra args]  -- run the translated game against melonDS RAM dumps and compare
# (references: tools/melonds-headless/lockstep_ref.py; "t1" = battle snapshot, "boot" = power-on, see
# decomp/notes/transpiler.md "Verification"). Known diffs: t1 0x020E18A9 + the sound-stream buffer.
. "$(dirname "$0")/env.sh"
REF=$1; N=${2:-18}; shift 2
rm -rf "$OUT/ls_out"
(cd "$PROJ" && timeout -s SEGV ${LSTIMEOUT:-600} "$GODOT" --headless --path . --script res://tools/lockstep.gd -- \
  ref="$REF" out="$OUT/ls_out" frames=$N rom="$ROM" sav="${LSSAV:-$(ls "$REPO"/baseroms/*.sav "$REPO"/GodotGame/new-game-project/data/save100.sav 2>/dev/null | head -1)}" "$@" > "$OUT/ls.log" 2>&1)
grep -E "SCRIPT|ERROR" "$OUT/ls.log" | grep -v "ObjectDB\|resources still" | sort | uniq -c | sort -rn | head
grep "LOCKSTEP" "$OUT/ls.log" | tail -3
python3 "$REPO/decomp/tools/lockstep_cmp.py" "$REF" "$OUT/ls_out" 2>&1 | head -${LSC:-40}
