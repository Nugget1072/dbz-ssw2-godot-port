#!/bin/bash
# regen.sh [gen|ghidra|all]  -- rebuild scripts/gen/ds_game.gd from the Ghidra output (decomp/tools/transpile/run.sh)
# GHIDRA=<ghidra_11.4.2_PUBLIC> (default tools/ghidra_11.4.2_PUBLIC); TRACE=1 / WATCH=1 / PROFILE=1 debug builds
. "$(dirname "$0")/env.sh"
GODOT="$GODOT" "$REPO/decomp/tools/transpile/run.sh" ${1:-gen}
