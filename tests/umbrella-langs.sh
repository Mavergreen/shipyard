#!/bin/sh
# platform: macOS-only -- include(Mavericks) requires AppleClang, which only a Mac has, and its arm64 case needs a cross-capable Apple clang; run by hand on Golden Gate (tests/maintainer-tests)
set -eu
SC="${CMAKE:-$(command -v shipyard-cmake || echo cmake)}"
command -v "$SC" >/dev/null 2>&1 || { echo "SKIP: no cmake"; exit 77; }
SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
T=$(mktemp -d "${TMPDIR:-/tmp}/umbrella-langs.XXXXXX"); trap 'rm -rf "$T"' EXIT
# platform: /usr/bin/clang is present on 10.9 and modern macOS alike.
CC=/usr/bin/clang
[ -x "$CC" ] || { echo "SKIP: no Apple clang at $CC"; exit 77; }

cfg() { # $1=langs  $2...=extra -D
  langs=$1; shift
  d="$T/p"; rm -rf "$d"; mkdir -p "$d"
  cat > "$d/CMakeLists.txt" <<EOF
cmake_minimum_required(VERSION 3.16)
project(u LANGUAGES $langs)
list(APPEND CMAKE_MODULE_PATH "$SRC")
include(Mavericks)
EOF
  # spec: SKILL.md "SDK pinning" -- include(Mavericks)'s backstop now refuses a cross configure with
  #       no pinned sysroot, so every configure here must go through the toolchain file to stay green.
  "$SC" -S "$d" -B "$d/b" -DCMAKE_C_COMPILER=$CC -DCMAKE_OBJC_COMPILER=$CC -DCMAKE_CXX_COMPILER=${CC}++ \
    -DCMAKE_TOOLCHAIN_FILE="$SRC/MavericksToolchain.cmake" "$@" >/dev/null 2>&1 \
    || { echo "FAIL: include(Mavericks) must be universally includable with no MAVERICKS_REQUIRE_LANGS (the gate auto-scopes to the enabled languages) -- failed for LANGUAGES $langs"; exit 1; }
}

cfg NONE
cfg C
cfg OBJC
cfg "C OBJC"

d="$T/marr"; rm -rf "$d"; mkdir -p "$d"
cat > "$d/CMakeLists.txt" <<EOF
cmake_minimum_required(VERSION 3.16)
project(u LANGUAGES C)
list(APPEND CMAKE_MODULE_PATH "$SRC")
include(Mavericks)
if(NOT CMAKE_OSX_ARCHITECTURES STREQUAL "arm64" OR NOT CMAKE_OSX_DEPLOYMENT_TARGET STREQUAL "12.0")
  message(FATAL_ERROR "umbrella changed arch/target to [\${CMAKE_OSX_ARCHITECTURES}]/[\${CMAKE_OSX_DEPLOYMENT_TARGET}]")
endif()
EOF
# spec: SKILL.md "SDK pinning" -- no toolchain file here on purpose: it would FORCE the deployment
#       target to 11.0 for arm64, defeating this case's point (arch/target stay the CALLER's, 12.0).
#       The backstop checks only CMAKE_OSX_SYSROOT, so pin that by hand to arm64's SDK.
"$SC" -S "$d" -B "$d/b" -DCMAKE_C_COMPILER=$CC -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
  -DCMAKE_OSX_SYSROOT="$(sh "$SRC/scripts/fetch_sdk.sh" --arch arm64)" >/dev/null 2>&1 \
  || { echo "FAIL: include(Mavericks) must not touch a project's CMAKE_OSX_* -- umbrella not multi-arch safe (clobbered arm64/12.0)"; exit 1; }

echo "umbrella-langs OK"
