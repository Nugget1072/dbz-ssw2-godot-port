#!/bin/bash
# Build the headless melonDS 1.1 core + C API used for frame-exact reference captures (Linux).
# Done in the cloud sandbox; see WORK_OUTSIDE_FOLDER.txt.
set -e
SRC=${1:-$HOME/melonds-src}
[ -d "$SRC" ] || git clone --depth 1 -b 1.1 https://github.com/melonDS-emu/melonDS.git "$SRC"
cmake -S "$SRC" -B "$SRC/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_QT_SDL=OFF \
      -DENABLE_OGLRENDERER=OFF -DENABLE_GDBSTUB=OFF -DENABLE_JIT=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON
cmake --build "$SRC/build" --target core
g++ -O2 -std=gnu++17 -fPIC -shared -flto=auto -DARCHITECTURE_x86_64=1 -DJIT_ENABLED \
    -I "$SRC/src" -I "$SRC/build/src" -I "$SRC/src/teakra/include" \
    -o libmelonds_headless.so "$(dirname "$0")/melonds_headless.cpp" \
    -Wl,--whole-archive "$SRC/build/src/libcore.a" -Wl,--no-whole-archive \
    "$SRC/build/src/teakra/src/libteakra.a" -lpthread -lrt
echo built libmelonds_headless.so
