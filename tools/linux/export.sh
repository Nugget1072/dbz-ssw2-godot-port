#!/bin/bash
# export.sh  -- native library for both platforms, then finished/DBZ_SSW2_Port.exe (+ DLL) and finished/linux/
# (needs the Godot 4.7.2 export templates in ~/.local/share/godot/export_templates/4.7.2.stable/)
. "$(dirname "$0")/env.sh"
"$PROJ/native/build.sh" all
mkdir -p "$REPO/finished/linux"
(cd "$PROJ" && "$GODOT" --headless --path . --export-release "Windows Desktop" && "$GODOT" --headless --path . --export-release "Linux")
cp "$REPO/docs/PLAYER_README.txt" "$REPO/finished/README.txt" 2>/dev/null
cp "$REPO/docs/BOSS_CHARACTERS.txt" "$REPO/finished/BOSS_CHARACTERS.txt" 2>/dev/null
cp "$REPO/docs/BUGFIXES.txt" "$REPO/finished/BUGFIXES.txt" 2>/dev/null
ls -la "$REPO/finished" "$REPO/finished/linux"
