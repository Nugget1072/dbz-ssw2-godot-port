#!/bin/bash
# Shared settings for the Linux test scripts (source it). Override any of these in the environment.
#   REPO   repository root (default: two folders up from this script)
#   GODOT  Godot 4.7.2 Linux editor binary          ROM / SAV  the user's ROM and the 100% save
#   OUT    scratch folder for captures and logs (default /tmp/ssw2)
REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
GODOT=${GODOT:-godot}
ROM=${ROM:-$(ls "$REPO"/baseroms/*.nds "$REPO"/finished/*.nds 2>/dev/null | head -1)}       # part 21: baseroms/ may be gone
SAV=${SAV:-$(ls "$REPO"/100Save/*.sav "$REPO"/GodotGame/new-game-project/data/save100.sav 2>/dev/null | head -1)}
OUT=${OUT:-/tmp/ssw2}
PROJ="$REPO/GodotGame/new-game-project"
export DISPLAY=${DISPLAY:-:99}
mkdir -p "$OUT"
# a virtual X display for windowed (GPU) runs on a headless machine; Mesa llvmpipe renders
if [ "$DISPLAY" = ":99" ] && ! pgrep -x Xvfb > /dev/null; then
  (Xvfb :99 -screen 0 1280x1024x24 > /dev/null 2>&1 &); sleep 2
fi
