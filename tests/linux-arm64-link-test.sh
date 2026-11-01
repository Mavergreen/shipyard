#!/bin/sh
# platform: host-agnostic
#   usage: linux-arm64-link-test.sh
#          Linux arm64 configure links Mach-O arm64: a one-file C project, configured through
#          MavericksToolchain.cmake with clang22's Linux archive and the pinned 11.3 SDK, is an
#          arm64 Mach-O whose minos is 11.0. Fetches both over the network.
set -eu
[ "$(uname -s)" = Linux ] || { echo 'SKIP: Linux arm64 cross-link'; exit 77; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLANG22_VERSION="${CLANG22_VERSION:-22.1.8-mavericks.12}"
CLANG22_SHA256="${CLANG22_SHA256:-82d3fdab2d5868d1bc9452dcc95962d6615d05945731781683a1b9363c3b5ebd}"
T="$(mktemp -d "${TMPDIR:-/tmp}/linux-arm64.XXXXXX")"; trap 'rm -rf "$T"' EXIT
LLVM="$(sh "$ROOT/scripts/fetch_product_tar.sh" clang22 "$CLANG22_VERSION" "$CLANG22_SHA256" "$T/clang22")"
SDK="$(sh "$ROOT/scripts/fetch_sdk.sh" --arch arm64)"
mkdir -p "$T/project"
cat > "$T/project/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.16)
project(arm64_link C)
add_executable(hello hello.c)
CMAKE
printf 'int main(void) { return 0; }\n' > "$T/project/hello.c"
cmake -S "$T/project" -B "$T/build" \
  -DCMAKE_TOOLCHAIN_FILE="$ROOT/MavericksToolchain.cmake" -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_C_COMPILER="$LLVM/bin/clang" -DCMAKE_C_COMPILER_TARGET=arm64-apple-macos11.0 \
  -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld --ld-path=$LLVM/bin/ld64.lld"
cmake --build "$T/build"
archs="$("$LLVM/bin/llvm-lipo" -info "$T/build/hello" | sed -n 's/.*: //p')"
[ "$archs" = arm64 ] || { echo "FAIL: Linux arm64 configure must link a Mach-O of arch arm64 (the toolchain file kept x86_64?), got '$archs'"; exit 1; }
"$LLVM/bin/llvm-otool" -l "$T/build/hello" | grep -q 'minos 11.0' \
  || { echo 'FAIL: the arm64 slice must record minos 11.0 (deployment target not pinned per arch)'; exit 1; }
"$LLVM/bin/llvm-otool" -l "$T/build/hello" | grep -q 'sdk 11.3' \
  || { echo 'FAIL: the arm64 slice must record sdk 11.3 (the pinned SDK, not another)'; exit 1; }
echo 'PASS: Linux arm64 configure links Mach-O arm64, minos 11.0, sdk 11.3'
