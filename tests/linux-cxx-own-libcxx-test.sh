#!/bin/sh
# platform: host-agnostic
#   usage: linux-cxx-own-libcxx-test.sh
#          Linux x86_64 C++ links the way a 10.9 host's does: a C++ project configured through
#          MavericksToolchain.cmake, with no compiler named, gets clang22's clang++.cfg, as clang22 on
#          10.9 does. Its link runs the cfg's linker with every -Wl argument the cfg names, its
#          over-aligned allocation compiles (--mavergreen-own-libcxx), and it loads the same dylibs as
#          the same source built by clang22's own driver, never 10.9's /usr/lib/libc++.1.dylib.
#          Fetches the pinned clang22 Linux archive and the 10.9 SDK over the network.
set -eu
[ "$(uname -s)" = Linux ] || { echo 'SKIP: Linux C++ link shape'; exit 77; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/linux-cxx.XXXXXX")"; trap 'rm -rf "$T"' EXIT
LLVM="$(sh "$ROOT/scripts/fetch_clang22.sh" "$ROOT/components/clang22")"
SDK="$(sh "$ROOT/scripts/fetch_sdk.sh")"
CFG="$LLVM/bin/clang++.cfg"
[ -f "$CFG" ] || { echo "FAIL: clang22 at $LLVM has no bin/clang++.cfg"; exit 1; }
mkdir -p "$T/project"
cat > "$T/project/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.16)
project(cxx_link CXX)
add_executable(hello hello.cpp)
CMAKE
cat > "$T/project/hello.cpp" <<'CXX'
#include <iostream>
#include <memory>
#include <string>
#include <vector>
struct alignas(64) Line { int x; };
int main() {
  std::vector<std::string> v(1, "a");
  std::unique_ptr<Line> p(new Line());
  std::cout << v[0] << p->x << std::endl;
  return 0;
}
CXX
cmake -S "$T/project" -B "$T/build" -DCMAKE_TOOLCHAIN_FILE="$ROOT/MavericksToolchain.cmake" >/dev/null
cmake --build "$T/build" >"$T/build.log" 2>&1 || { cat "$T/build.log"; echo "FAIL: a C++ program did not build through MavericksToolchain.cmake on Linux"; exit 1; }
dylibs() { "$LLVM/bin/llvm-otool" -L "$1" | sed 1d | sed 's/^[[:space:]]*//; s/ (.*//'; }
got="$(dylibs "$T/build/hello")"
case "$got" in
  */usr/lib/libc++.1.dylib*) printf '%s\n' "$got"; echo "FAIL: Linux-built C++ loads 10.9's /usr/lib/libc++.1.dylib under clang22's LLVM 22 libc++ headers"; exit 1 ;;
esac
"$LLVM/bin/clang++" -isysroot "$SDK" "$T/project/hello.cpp" -o "$T/ref"
want="$(dylibs "$T/ref")"
[ "$got" = "$want" ] || { printf 'toolchain:\n%s\nclang22 driver:\n%s\n' "$got" "$want"; echo "FAIL: Linux-built C++ loads other dylibs than clang22's own driver links"; exit 1; }
link="$(cd "$T/build" && sh -c "$(cat CMakeFiles/hello.dir/link.txt) -###" 2>&1 | sed -n '/^ "/p' | tail -n 1)"
cfgdir="$LLVM/bin"
ld="$(sed -n 's/^--ld-path=//p' "$CFG" | sed "s#<CFGDIR>#$cfgdir#g")"
case "$link" in
  " \"$ld\" "*) : ;;
  *) printf '%s\n' "$link"; echo "FAIL: the link must run clang++.cfg's linker $ld"; exit 1 ;;
esac
sed -n 's/^\$\{0,1\}-Wl,//p' "$CFG" | sed "s#<CFGDIR>#$cfgdir#g" > "$T/wl"
while IFS= read -r w; do
  q="\"$(printf '%s' "$w" | sed 's/,/" "/g')\""
  case "$link" in
    *" $q"*) : ;;
    *) printf '%s\n' "$link"; echo "FAIL: the link lacks clang++.cfg's -Wl,$w"; exit 1 ;;
  esac
done < "$T/wl"
[ -s "$T/wl" ] || { echo "FAIL: clang++.cfg names no -Wl argument to check"; exit 1; }
echo 'PASS: Linux x86_64 C++ links through clang++.cfg, loading what clang22 links on 10.9 and not /usr/lib/libc++.1.dylib'
