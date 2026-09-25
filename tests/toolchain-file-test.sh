#!/bin/sh
# platform: macOS-only -- builds and inspects a real binary with Apple clang and otool
#   usage: toolchain-file-test.sh
#          A project configured through MavericksToolchain.cmake records the pinned SDK in its binary, and
#          include(Mavericks) refuses a cross configure whose sysroot is not the pin.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning"
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
# platform: shipyard refuses any cmake but shipyard-cmake on a macOS host (MavericksShipyardConfig.cmake),
#           and the CI test job installs one; standalone-include.sh finds it the same way.
real="${SHIPYARD_CMAKE:-$(command -v shipyard-cmake 2>/dev/null || true)}"
[ -n "$real" ] || { echo "SKIP: no shipyard-cmake (install the shipyard pkg, or set SHIPYARD_CMAKE)"; exit 77; }
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/toolchain-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/p"
printf 'cmake_minimum_required(VERSION 3.16)\nproject(p C)\nadd_executable(p p.c)\n' > "$w/p/CMakeLists.txt"
printf 'int main(void){return 0;}\n' > "$w/p/p.c"
"$real" -S "$w/p" -B "$w/b" -DCMAKE_TOOLCHAIN_FILE="$root/MavericksToolchain.cmake" > "$w/c.log" 2>&1 \
  || { echo "FAIL: configure through the toolchain file failed:"; sed 's/^/    | /' "$w/c.log"; exit 1; }
"$real" --build "$w/b" > "$w/b.log" 2>&1 || { echo "FAIL: build failed:"; sed 's/^/    | /' "$w/b.log"; exit 1; }
got="$(sh "$root/scripts/macho-slices.sh" "$w/b/p")"
[ "$got" = "x86_64 EXECUTE 10.9 10.9" ] || { echo "FAIL: expected the pinned x86_64/10.9 SDK, got: $got"; exit 1; }

rc=0; "$real" -S "$w/p" -B "$w/b2" -DCMAKE_TOOLCHAIN_FILE="$root/MavericksToolchain.cmake" -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" > "$w/c2.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ] && grep -q 'one arch per configure' "$w/c2.log" || { echo "FAIL: two arches in one configure must be refused"; exit 1; }

mkdir -p "$w/q"
printf 'cmake_minimum_required(VERSION 3.16)\nproject(q C)\nfind_package(MavericksShipyard REQUIRED)\ninclude(Mavericks)\n' > "$w/q/CMakeLists.txt"
# platform: CMAKE_OSX_ARCHITECTURES comes only from the env var, a preset, the toolchain file or an
#           explicit -D on Darwin (Modules/Platform/Darwin-Initialize.cmake) -- never from AppleClang
#           detection -- so this configure needs one named, or it hits "one arch per cross configure"
#           (empty) before ever reaching the pinned-SDK comparison this case means to exercise.
rc=0; "$real" -S "$w/q" -B "$w/b3" -DMavericksShipyard_DIR="$root" -DMAVERICKS_REQUIRE_APPLECLANG=OFF \
  -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_SYSROOT="$(xcrun --show-sdk-path)" > "$w/c3.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ] && grep -q 'not the pinned SDK' "$w/c3.log" || { echo "FAIL: include(Mavericks) must refuse the runner's SDK:"; sed 's/^/    | /' "$w/c3.log"; exit 1; }
"$real" -S "$w/q" -B "$w/b4" -DMavericksShipyard_DIR="$root" -DMAVERICKS_REQUIRE_APPLECLANG=OFF \
  -DCMAKE_TOOLCHAIN_FILE="$root/MavericksToolchain.cmake" > "$w/c4.log" 2>&1 \
  || { echo "FAIL: include(Mavericks) must accept the toolchain file's pin:"; sed 's/^/    | /' "$w/c4.log"; exit 1; }
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- a plain
#       configure (no arch, no preset, no toolchain file) is the first thing a newly-red consumer runs,
#       so it must get the preset/toolchain-file guidance, not "one arch per cross configure".
rc=0; ( unset CMAKE_OSX_ARCHITECTURES
        "$real" -S "$w/q" -B "$w/b6" -DMavericksShipyard_DIR="$root" -DMAVERICKS_REQUIRE_APPLECLANG=OFF ) \
  > "$w/c6.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ] && grep -q 'CMAKE_OSX_ARCHITECTURES is empty' "$w/c6.log" && grep -q 'MavericksToolchain.cmake' "$w/c6.log" \
  || { echo "FAIL: a configure with no arch must be refused with the preset/toolchain-file guidance:"; sed 's/^/    | /' "$w/c6.log"; exit 1; }

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the toolchain
#       file sets CMAKE_OSX_SYSROOT with FORCE precisely so it overrides whatever a caller already set
#       (a stale cache entry, or -D on the same command line); prove that by pre-setting the runner's
#       own SDK and checking the built binary still records the PINNED one, not the pre-set one.
"$real" -S "$w/p" -B "$w/b5" -DCMAKE_TOOLCHAIN_FILE="$root/MavericksToolchain.cmake" \
  -DCMAKE_OSX_SYSROOT="$(xcrun --show-sdk-path)" > "$w/c5.log" 2>&1 \
  || { echo "FAIL: configure with a pre-set sysroot failed:"; sed 's/^/    | /' "$w/c5.log"; exit 1; }
"$real" --build "$w/b5" > "$w/b5.log" 2>&1 || { echo "FAIL: build (pre-set sysroot case) failed:"; sed 's/^/    | /' "$w/b5.log"; exit 1; }
got5="$(sh "$root/scripts/macho-slices.sh" "$w/b5/p")"
[ "$got5" = "x86_64 EXECUTE 10.9 10.9" ] \
  || { echo "FAIL: toolchain file must override a pre-set CMAKE_OSX_SYSROOT (FORCE), got: $got5"; exit 1; }

echo "PASS: toolchain-file"
