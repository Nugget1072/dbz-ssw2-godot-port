#!/bin/bash
# Builds the native helper library for Linux (host g++) and Windows (llvm-mingw cross compiler).
#   GODOT_CPP=<godot-cpp checkout>  API=<extension_api.json from `godot --dump-extension-api`>  MINGW=<llvm-mingw dir>
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
GODOT_CPP=${GODOT_CPP:-/home/claude/toolchain/godot-cpp}
API=${API:-$GODOT_CPP/extension_api.json}
MINGW=${MINGW:-/home/claude/toolchain/llvm-mingw-20260922-ucrt-ubuntu-22.04-x86_64}
COMMON="-DGODOT_CPP_DIR=$GODOT_CPP -DGODOTCPP_CUSTOM_API_FILE=$API -DGODOTCPP_BUILD_PROFILE=$HERE/build_profile.json -DCMAKE_BUILD_TYPE=Release -G Ninja"
mkdir -p "$HERE/../bin"
if [ "${1:-all}" != windows ]; then
  cmake -S "$HERE" -B "$HERE/build-linux" $COMMON -DDS_PLATFORM=linux.x86_64 > /dev/null
  cmake --build "$HERE/build-linux" -j2
  cp "$HERE/build-linux/libdsnative.linux.x86_64.so" "$HERE/../bin/"
fi
if [ "${1:-all}" != linux ]; then
  cat > "$HERE/build-windows.toolchain.cmake" <<TC
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER $MINGW/bin/x86_64-w64-mingw32-clang)
set(CMAKE_CXX_COMPILER $MINGW/bin/x86_64-w64-mingw32-clang++)
set(CMAKE_RC_COMPILER $MINGW/bin/x86_64-w64-mingw32-windres)
TC
  cmake -S "$HERE" -B "$HERE/build-windows" $COMMON -DDS_PLATFORM=windows.x86_64 \
    -DCMAKE_TOOLCHAIN_FILE="$HERE/build-windows.toolchain.cmake" -DCMAKE_SHARED_LINKER_FLAGS="-static" > /dev/null
  cmake --build "$HERE/build-windows" -j2
  cp "$HERE/build-windows/libdsnative.windows.x86_64.dll" "$HERE/../bin/"
fi
ls -la "$HERE/../bin"
