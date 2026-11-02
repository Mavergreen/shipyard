#!/bin/sh
# platform: host-agnostic
#   usage: build-updater.sh --arch x86_64|arm64 [--arch x86_64|arm64] --out APP
#          Builds shipyard's own Sparkle updater (CMakeLists.txt, SHIPYARD_BUILD_UPDATER) with the pinned
#          clang22 (scripts/fetch_clang22.sh) and MavericksToolchain.cmake, one configure per arch
#          (x86_64: 10.9 SDK, minos 10.9; arm64: 11.3 SDK, minos 11.0), on Linux and on a Mac alike. Two
#          arches are merged into one app by lipo-merge-tree.sh with LIPO=llvm-lipo; one arch is copied
#          as built, which only the tests ask for. APP must not exist. The build logs go to stderr,
#          verbose. CMAKE names the cmake (default: shipyard-cmake, else cmake).
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
usage() { echo "usage: build-updater.sh --arch x86_64|arm64 [--arch x86_64|arm64] --out APP" >&2; exit 2; }
die() { echo "build-updater: $*" >&2; exit 1; }
archs=""; out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --arch) [ "$#" -ge 2 ] || usage
      case "$2" in x86_64|arm64) ;; *) usage ;; esac
      case " $archs " in *" $2 "*) usage ;; esac
      archs="$archs $2"; shift 2 ;;
    --out) [ "$#" -ge 2 ] || usage; out=$2; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$archs" ] && [ -n "$out" ] || usage
case "$out" in /*) ;; *) out="$(pwd)/$out" ;; esac
[ ! -e "$out" ] && [ ! -L "$out" ] || die "$out already exists"
CMAKE="${CMAKE:-$(command -v shipyard-cmake || echo cmake)}"
CL="$(sh "$ROOT/scripts/fetch_clang22.sh" "$ROOT")"
LIPO="$CL/bin/llvm-lipo"; OTOOL="$CL/bin/llvm-otool"; NM="$CL/bin/llvm-nm"; STRINGS="$CL/bin/llvm-strings"
export LIPO OTOOL NM STRINGS
_tmp="${TMPDIR:-/tmp}"
root="${MAVERICKS_BUILD_ROOT:-${_tmp%/}/mm-build}"
mkdir -p "$root"
work="$(mktemp -d "$root/shipyard-updater.XXXXXX")"
trap 'rm -rf "$work"' EXIT
for a in $archs; do
  case "$a" in x86_64) floor=10.9 ;; arm64) floor=11.0 ;; esac
  "$CMAKE" -S "$ROOT" -B "$work/$a" -DSHIPYARD_BUILD_UPDATER=ON -DMAVERICKS_ALLOW_GENERIC_ICON=ON \
    -DCMAKE_TOOLCHAIN_FILE="$ROOT/MavericksToolchain.cmake" -DCMAKE_OSX_ARCHITECTURES="$a" \
    -DCMAKE_OBJC_COMPILER="$CL/bin/clang" -DCMAKE_OBJC_COMPILER_TARGET="$a-apple-macos$floor" \
    -DCMAKE_OBJC_FLAGS=--no-default-config -DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld >&2 \
    || die "the $a updater did not configure"
  "$CMAKE" --build "$work/$a" -v >&2 || die "the $a updater did not build"
done
app=shipyard-updater.app
mkdir -p "$(dirname "$out")"
case "$archs" in
  " x86_64" | " arm64") cp -R "$work/${archs# }/$app" "$out" ;;
  *) sh "$ROOT/scripts/lipo-merge-tree.sh" --a "$work/x86_64/$app" --b "$work/arm64/$app" \
       --out "$out" --require-archs "x86_64 arm64" >&2 || die "could not merge the two updaters" ;;
esac
echo "build-updater:$archs updater at $out" >&2
