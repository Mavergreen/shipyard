#!/bin/sh
# platform: host-agnostic
#   usage: toolchain-file-test.sh
#          A project configured through MavericksToolchain.cmake records the pinned SDK in its binary, and
#          include(Mavericks) refuses a cross configure whose sysroot is not the pin. On a native 10.9
#          host, MavericksMode.cmake puts every include(Mavericks) configure in "native" mode, so
#          Mavericks.cmake's cross-mode-only backstop (the runner's-SDK refusal, the empty-arch guidance)
#          cannot fire there; those two cases print a "skip (native 10.9 host)" line instead of asserting.
#          Every other case -- the toolchain file's own pin, the two-arch refusal, the toolchain file
#          accepted, the FORCE override -- is native-valid and still runs and asserts on that host.
#          The binaries are built and read with the pinned clang22 (scripts/fetch_clang22.sh), so no
#          Apple clang is needed and a Linux host runs every case.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning"
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
# platform: shipyard refuses any cmake but shipyard-cmake on a macOS host (MavericksShipyardConfig.cmake),
#           and the CI test job installs one; standalone-include.sh finds it the same way.
#           On Linux shipyard refuses no cmake, so any cmake will do.
real="${SHIPYARD_CMAKE:-$(command -v shipyard-cmake 2>/dev/null || true)}"
[ -n "$real" ] || [ "$(uname -s)" != Linux ] || real="$(command -v cmake 2>/dev/null || true)"
[ -n "$real" ] || { echo "SKIP: no shipyard-cmake (install the shipyard pkg, or set SHIPYARD_CMAKE)"; exit 77; }
# platform: MavericksMode.cmake calls a host "native" when sw_vers reports 10.9.x (Darwin 13); the
#           cross-mode-only backstop in Mavericks.cmake cannot fire there, so this test detects the
#           same way and skips exactly the cases that assert on it.
native=0
# platform: guarded macOS-only call -- sw_vers is absent on Linux, whose empty answer leaves native=0
case "$(sw_vers -productVersion 2>/dev/null)" in
  10.9.*) native=1 ;;
esac
CL="$(sh "$root/scripts/fetch_clang22.sh" "$root")"
LIPO="$CL/bin/llvm-lipo"; OTOOL="$CL/bin/llvm-otool"; export LIPO OTOOL
other_sdk="$(sh "$root/scripts/fetch_sdk.sh" --arch arm64)"
sysname=""; [ "$(uname -s)" != Linux ] || sysname=-DCMAKE_SYSTEM_NAME=Darwin
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/toolchain-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
configure() {  # $1 = source dir  $2 = build dir  then more cmake arguments
  _src="$1"; _bld="$2"; shift 2
  "$real" -S "$_src" -B "$_bld" $sysname -DCMAKE_C_COMPILER="$CL/bin/clang" -DCMAKE_C_COMPILER_TARGET=x86_64-apple-macos10.9 \
    -DCMAKE_C_FLAGS=--no-default-config -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld --ld-path=$CL/bin/ld64.lld" "$@"
}
# platform: cmake wraps a FATAL_ERROR message to the terminal width, so a long sysroot path splits a
#           phrase across lines; the log is read as one line.
says() { tr '\n' ' ' < "$1" | tr -s ' ' | grep -q -e "$2"; }
mkdir -p "$w/p"
printf 'cmake_minimum_required(VERSION 3.16)\nproject(p C)\nadd_executable(p p.c)\n' > "$w/p/CMakeLists.txt"
printf 'int main(void){return 0;}\n' > "$w/p/p.c"
configure "$w/p" "$w/b" -DCMAKE_TOOLCHAIN_FILE="$root/MavericksToolchain.cmake" > "$w/c.log" 2>&1 \
  || { echo "FAIL: configure through the toolchain file failed:"; sed 's/^/    | /' "$w/c.log"; exit 1; }
"$real" --build "$w/b" > "$w/b.log" 2>&1 || { echo "FAIL: build failed:"; sed 's/^/    | /' "$w/b.log"; exit 1; }
got="$(sh "$root/scripts/macho-slices.sh" "$w/b/p")"
[ "$got" = "x86_64 EXECUTE 10.9 10.9" ] || { echo "FAIL: expected the pinned x86_64/10.9 SDK, got: $got"; exit 1; }

rc=0; configure "$w/p" "$w/b2" -DCMAKE_TOOLCHAIN_FILE="$root/MavericksToolchain.cmake" -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" > "$w/c2.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ] && grep -q 'one arch per configure' "$w/c2.log" || { echo "FAIL: two arches in one configure must be refused"; exit 1; }

mkdir -p "$w/q"
printf 'cmake_minimum_required(VERSION 3.16)\nproject(q C)\nfind_package(MavericksShipyard REQUIRED)\ninclude(Mavericks)\n' > "$w/q/CMakeLists.txt"
# platform: CMAKE_OSX_ARCHITECTURES comes only from the env var, a preset, the toolchain file or an
#           explicit -D on Darwin (Modules/Platform/Darwin-Initialize.cmake) -- never from AppleClang
#           detection -- so this configure needs one named, or it hits "one arch per cross configure"
#           (empty) before ever reaching the pinned-SDK comparison this case means to exercise.
# platform: Mavericks.cmake only compares CMAKE_OSX_SYSROOT against the pin when MAVERICKS_MODE is
#           "cross" (the check is deliberately cross-mode-only -- a native build takes the same pin
#           from the toolchain file); on a native 10.9 host this configure just succeeds, so skip
#           the assertion rather than fail it.
if [ "$native" -eq 1 ]; then
  echo "skip (native 10.9 host): the backstop is cross-mode only"
else
  rc=0; configure "$w/q" "$w/b3" -DMavericksShipyard_DIR="$root" -DMAVERICKS_REQUIRE_APPLECLANG=OFF \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_SYSROOT="$other_sdk" > "$w/c3.log" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && says "$w/c3.log" 'not the pinned SDK' || { echo "FAIL: include(Mavericks) must refuse the runner's SDK:"; sed 's/^/    | /' "$w/c3.log"; exit 1; }
fi
configure "$w/q" "$w/b4" -DMavericksShipyard_DIR="$root" -DMAVERICKS_REQUIRE_APPLECLANG=OFF \
  -DCMAKE_TOOLCHAIN_FILE="$root/MavericksToolchain.cmake" > "$w/c4.log" 2>&1 \
  || { echo "FAIL: include(Mavericks) must accept the toolchain file's pin:"; sed 's/^/    | /' "$w/c4.log"; exit 1; }
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- a plain
#       configure (no arch, no preset, no toolchain file) is the first thing a newly-red consumer runs,
#       so it must get the preset/toolchain-file guidance, not "one arch per cross configure".
# platform: this guidance is raised from inside Mavericks.cmake's cross-mode-only backstop too (the
#           empty-arch branch), so on a native 10.9 host the configure just succeeds instead -- skip
#           the assertion rather than fail it.
#           Darwin-Initialize.cmake runs xcrun when no sysroot is set, and Linux has none; naming a sysroot keeps
#           the configure off xcrun and the empty-arch refusal does not read it.
if [ "$native" -eq 1 ]; then
  echo "skip (native 10.9 host): the backstop is cross-mode only"
else
  rc=0; ( unset CMAKE_OSX_ARCHITECTURES
          configure "$w/q" "$w/b6" -DMavericksShipyard_DIR="$root" -DMAVERICKS_REQUIRE_APPLECLANG=OFF -DCMAKE_OSX_SYSROOT="$other_sdk" ) \
    > "$w/c6.log" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && says "$w/c6.log" 'CMAKE_OSX_ARCHITECTURES is empty' && says "$w/c6.log" 'MavericksToolchain.cmake' \
    || { echo "FAIL: a configure with no arch must be refused with the preset/toolchain-file guidance:"; sed 's/^/    | /' "$w/c6.log"; exit 1; }
fi

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the toolchain
#       file sets CMAKE_OSX_SYSROOT with FORCE precisely so it overrides whatever a caller already set
#       (a stale cache entry, or -D on the same command line); prove that by pre-setting the runner's
#       own SDK and checking the built binary still records the PINNED one, not the pre-set one.
configure "$w/p" "$w/b5" -DCMAKE_TOOLCHAIN_FILE="$root/MavericksToolchain.cmake" \
  -DCMAKE_OSX_SYSROOT="$other_sdk" > "$w/c5.log" 2>&1 \
  || { echo "FAIL: configure with a pre-set sysroot failed:"; sed 's/^/    | /' "$w/c5.log"; exit 1; }
"$real" --build "$w/b5" > "$w/b5.log" 2>&1 || { echo "FAIL: build (pre-set sysroot case) failed:"; sed 's/^/    | /' "$w/b5.log"; exit 1; }
got5="$(sh "$root/scripts/macho-slices.sh" "$w/b5/p")"
[ "$got5" = "x86_64 EXECUTE 10.9 10.9" ] \
  || { echo "FAIL: toolchain file must override a pre-set CMAKE_OSX_SYSROOT (FORCE), got: $got5"; exit 1; }

echo "PASS: toolchain-file"
