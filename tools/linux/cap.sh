#!/bin/bash
# cap.sh DIR EVERY TO [FROM] [extra GameDS args]  -- frame-exact port captures: DIR/p<frame>.png
# (the game pauses while each frame is saved; the clock is frozen at 2026-01-01 12:00 like the melonDS reference)
# e.g. mode select:  cap.sh /tmp/ssw2/ms 1 2560 2440 inputs=2141:Start:4,2300:Start:4
. "$(dirname "$0")/env.sh"
rm -rf "$1"; mkdir -p "$1"
timeout ${GDT:-1800} "$GODOT" --path "$PROJ" --rendering-driver opengl3 res://scenes/GameDS.tscn -- \
  nds="$ROM" sav="$SAV" save="$OUT/cap_save.sav" capture="$1" cap_every=$2 cap_to=$3 cap_from=${4:-1} "${@:5}" > "$1.log" 2>&1
rm -f "$OUT/cap_save.sav"
grep -E "SCRIPT ERROR|Parse Error|game stopped" "$1.log" | head
echo "$(ls "$1" | grep -c '^p') frames in $1 (log $1.log)"
