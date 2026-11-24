#!/bin/sh
# platform: host-agnostic
#   usage: linux-arm64-sdk-libcxx-test.sh
#          Linux arm64 C++ uses the SDK's own libc++, headers and dylib together, as Apple's clang does: a
#          project configured through MavericksToolchain.cmake with no compiler named compiles C++ and
#          Objective-C++ against <SDK>/usr/include/c++/v1, never clang22's, so an API the SDK marks
#          unavailable (std::atomic::wait) or lacks (floating-point std::to_chars) fails at compile time,
#          and links only /usr/lib/libc++.1.dylib and /usr/lib/libSystem.B.dylib at minos 11.0, sdk 11.3.
#          Fetches the pinned clang22 Linux archive and the 11.3 SDK over the network; needs ninja.
set -eu
[ "$(uname -s)" = Linux ] || { echo 'SKIP: Linux arm64 C++ against the SDK libc++'; exit 77; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/linux-arm64-libcxx.XXXXXX")"; trap 'rm -rf "$T"' EXIT
LLVM="$(sh "$ROOT/scripts/fetch_clang22.sh" "$ROOT/components/clang22")"
SDK="$(sh "$ROOT/scripts/fetch_sdk.sh" --arch arm64)"
SDKR="$(cd "$SDK" && pwd -P)"
LLVMR="$(cd "$LLVM" && pwd -P)"
mkdir -p "$T/project"
cat > "$T/project/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.16)
project(arm64_libcxx CXX OBJCXX)
add_executable(hello hello.cpp)
add_executable(objcxx hello.mm)
add_library(atomicwait OBJECT wait.cpp)
set_property(TARGET atomicwait PROPERTY CXX_STANDARD 20)
add_library(tochars OBJECT tochars.cpp)
set_property(TARGET tochars PROPERTY CXX_STANDARD 17)
CMAKE
cat > "$T/project/hello.cpp" <<'CXX'
#include <iostream>
#include <string>
int main() {
  std::string s("arm64");
  std::cout << s << std::endl;
  return 0;
}
CXX
cat > "$T/project/hello.mm" <<'CXX'
#include <string>
int main() { std::string s("objc++"); return (int)s.size() - 6; }
CXX
cat > "$T/project/wait.cpp" <<'CXX'
#include <atomic>
void park(std::atomic<int>& a) { a.wait(1); }
CXX
cat > "$T/project/tochars.cpp" <<'CXX'
#include <charconv>
char* put(char* b, char* e) { return std::to_chars(b, e, 1.5).ptr; }
CXX
cmake -G Ninja -S "$T/project" -B "$T/build" \
  -DCMAKE_TOOLCHAIN_FILE="$ROOT/MavericksToolchain.cmake" -DCMAKE_OSX_ARCHITECTURES=arm64 >/dev/null
cmake --build "$T/build" --target hello objcxx >"$T/build.log" 2>&1 \
  || { cat "$T/build.log"; echo "FAIL: arm64 C++ and Objective-C++ did not build through MavericksToolchain.cmake on Linux"; exit 1; }
headers() { ninja -C "$T/build" -t deps "$1" | sed -n 's/^[[:space:]]*//; /\/c++\/v1\//p'; }
for obj in CMakeFiles/hello.dir/hello.cpp.o CMakeFiles/objcxx.dir/hello.mm.o; do
  h="$(headers "$obj")"
  [ -n "$h" ] || { echo "FAIL: ninja records no libc++ header for $obj"; exit 1; }
  bad="$(printf '%s\n' "$h" | while IFS= read -r p; do
    case "$p" in
      "$LLVM"/*|"$LLVMR"/*) printf '%s\n' "$p" ;;
      "$SDK/usr/include/c++/v1/"*|"$SDKR/usr/include/c++/v1/"*) : ;;
      *) printf '%s\n' "$p" ;;
    esac
  done)"
  [ -z "$bad" ] || { printf '%s\n' "$bad"; echo "FAIL: $obj includes libc++ headers outside $SDK/usr/include/c++/v1 (clang22's LLVM 22 headers over the SDK's libc++.1.dylib)"; exit 1; }
done
if cmake --build "$T/build" --target atomicwait >"$T/wait.log" 2>&1; then
  echo "FAIL: std::atomic::wait compiled for arm64 at an 11.0 floor; the SDK's libc++ marks it unavailable"; exit 1
fi
command grep -q unavailable "$T/wait.log" \
  || { cat "$T/wait.log"; echo "FAIL: std::atomic::wait must fail through the SDK's availability annotations ('unavailable')"; exit 1; }
if cmake --build "$T/build" --target tochars >"$T/tochars.log" 2>&1; then
  echo "FAIL: std::to_chars(double) compiled for arm64; the SDK's libc++ has no floating-point to_chars"; exit 1
fi
dylibs="$("$LLVM/bin/llvm-otool" -L "$T/build/hello" | sed 1d | sed 's/^[[:space:]]*//; s/ (.*//' | sort)"
want="$(printf '%s\n' /usr/lib/libSystem.B.dylib /usr/lib/libc++.1.dylib | sort)"
[ "$dylibs" = "$want" ] || { printf '%s\n' "$dylibs"; echo "FAIL: arm64 C++ must load exactly the SDK's /usr/lib/libc++.1.dylib and /usr/lib/libSystem.B.dylib"; exit 1; }
slices="$(LIPO="$LLVM/bin/llvm-lipo" OTOOL="$LLVM/bin/llvm-otool" sh "$ROOT/scripts/macho-slices.sh" "$T/build/hello")"
[ "$slices" = 'arm64 EXECUTE 11.0 11.3' ] \
  || { echo "FAIL: the arm64 C++ slice must record minos 11.0 and sdk 11.3, got '$slices'"; exit 1; }
echo 'PASS: Linux arm64 C++ and Objective-C++ compile against the SDK libc++ headers and link its dylib, minos 11.0, sdk 11.3'
