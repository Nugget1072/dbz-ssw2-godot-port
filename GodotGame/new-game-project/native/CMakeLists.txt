# Native DS geometry engine (GDExtension). Same results as scripts/render/ds_gx.gd + DSRender3D._prepare, much
# faster. Build: native/build.sh (Linux .so + Windows .dll through llvm-mingw). Godot falls back to the
# GDScript version when the library is missing.
cmake_minimum_required(VERSION 3.17)
project(dsnative LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(GODOTCPP_TARGET template_release CACHE STRING "")
add_subdirectory(${GODOT_CPP_DIR} godot-cpp)
add_library(dsnative SHARED src/register_types.cpp src/ds_fs_native.cpp src/ds_gx_native.cpp src/ds_mem_native.cpp src/ds_sound_native.cpp)
target_link_libraries(dsnative PRIVATE godot-cpp)
# identical floating point results to the engine's own math (no fused multiply-add contraction)
target_compile_options(dsnative PRIVATE -ffp-contract=off -O2)
set_target_properties(dsnative PROPERTIES PREFIX "lib" OUTPUT_NAME "dsnative.${DS_PLATFORM}")
