#!/bin/sh
# platform: host-agnostic
#   usage: umbrella-langs-portable-test.sh [mavericks-shipyard source dir]
#          include(Mavergreen) is includable for every language set once the AppleClang gate is turned
#          off, and leaves a caller's CMAKE_OSX_* alone. The gate's own cases are umbrella-langs.sh's.
set -eu
SC="${CMAKE:-$(command -v shipyard-cmake || echo cmake)}"
command -v "$SC" >/dev/null 2>&1 || { echo "SKIP: no cmake"; exit 77; }
SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
T=$(mktemp -d "${TMPDIR:-/tmp}/umbrella-portable.XXXXXX"); trap 'rm -rf "$T"' EXIT
CL="$(sh "$SRC/scripts/fetch_clang22.sh" "$SRC")"
CC="$CL/bin/clang"
CCARGS="-DCMAKE_C_COMPILER=$CC -DCMAKE_OBJC_COMPILER=$CC -DCMAKE_C_FLAGS=--no-default-config -DCMAKE_OBJC_FLAGS=--no-default-config -DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld"

cfg() {  # $1=langs
  d="$T/p"; rm -rf "$d"; mkdir -p "$d"
  cat > "$d/CMakeLists.txt" <<CM
cmake_minimum_required(VERSION 3.16)
project(u LANGUAGES $1)
list(APPEND CMAKE_MODULE_PATH "$SRC")
set(MAVERICKS_REQUIRE_APPLECLANG OFF)
include(Mavergreen)
CM
  "$SC" -S "$d" -B "$d/b" $CCARGS -DCMAKE_C_COMPILER_TARGET=x86_64-apple-macos10.9 -DCMAKE_OBJC_COMPILER_TARGET=x86_64-apple-macos10.9 \
    -DCMAKE_TOOLCHAIN_FILE="$SRC/MavergreenToolchain.cmake" >"$T/log" 2>&1 \
    || { echo "FAIL: include(Mavergreen) must configure for LANGUAGES $1:"; tail -20 "$T/log"; exit 1; }
}

cfg NONE
cfg C
cfg OBJC
cfg "C OBJC"

# platform: without a toolchain file a Linux host configures for Linux and ignores CMAKE_OSX_*, so the
#           try_compile links with no sysroot; naming Darwin applies the caller's own CMAKE_OSX_SYSROOT.
sysname=""; [ "$(uname -s)" != Linux ] || sysname=-DCMAKE_SYSTEM_NAME=Darwin
if "$CL/bin/clang" -print-targets | grep -q aarch64; then
  d="$T/marr"; mkdir -p "$d"
  cat > "$d/CMakeLists.txt" <<CM
cmake_minimum_required(VERSION 3.16)
project(u LANGUAGES C)
list(APPEND CMAKE_MODULE_PATH "$SRC")
set(MAVERICKS_REQUIRE_APPLECLANG OFF)
include(Mavergreen)
if(NOT CMAKE_OSX_ARCHITECTURES STREQUAL "arm64" OR NOT CMAKE_OSX_DEPLOYMENT_TARGET STREQUAL "12.0")
  message(FATAL_ERROR "umbrella changed arch/target to [\${CMAKE_OSX_ARCHITECTURES}]/[\${CMAKE_OSX_DEPLOYMENT_TARGET}]")
endif()
CM
  "$SC" -S "$d" -B "$d/b" $sysname $CCARGS -DCMAKE_C_COMPILER_TARGET=arm64-apple-macos12.0 -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
    -DCMAKE_OSX_SYSROOT="$(sh "$SRC/scripts/fetch_sdk.sh" --arch arm64)" >"$T/log" 2>&1 \
    || { echo "FAIL: include(Mavergreen) must not touch a project's CMAKE_OSX_*:"; tail -20 "$T/log"; exit 1; }
fi

echo "PASS: umbrella-langs-portable"
