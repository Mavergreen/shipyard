#!/bin/sh
# platform: macOS-only -- proves a Mac builds the updater with clang22 rather than the Apple clang it has
#   usage: updater-clang22-darwin-test.sh
#          The x86_64 updater, built the way shipyard's release builds it (tests/lib/build-updater.sh), is
#          compiled and linked by clang22, never /usr/bin/clang, and records minos 10.9 and sdk 10.9. A
#          configure that names only clang22 still gets the flags mavericks_add_updater_app owns.
#          Fetches clang22 (or uses the installed one at the pin), the 10.9 SDK and Sparkle.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
_tmp="${TMPDIR:-/tmp}"
T="$(mktemp -d "${_tmp%/}/updater-darwin.XXXXXX")"; trap 'rm -rf "$T"' EXIT
CL="$(sh "$ROOT/scripts/fetch_clang22.sh" "$ROOT")"
fail() { echo "FAIL: $*"; exit 1; }

sh "$ROOT/tests/lib/build-updater.sh" --arch x86_64 --out "$T/shipyard-updater.app" > "$T/build.log" 2>&1 \
  || { cat "$T/build.log"; fail 'build-updater.sh could not build the x86_64 updater with clang22'; }
grep -E 'Building OBJC|Linking OBJC' "$T/build.log" > /dev/null \
  || fail 'the build log shows no compile or link of the updater, so nothing below could be checked'
grep -E '(^|[ ;])/usr/bin/(clang|cc)( |$)' "$T/build.log" > "$T/other" || :
[ ! -s "$T/other" ] || { cat "$T/other"; fail 'the updater was compiled or linked by /usr/bin/clang, not clang22'; }
grep "^$CL/bin/clang .*-c .*shipyard-updater-main.m" "$T/build.log" > /dev/null \
  || fail "main.m was not compiled by clang22 ($CL/bin/clang)"
grep "^$CL/bin/clang .* -o shipyard-updater " "$T/build.log" > /dev/null \
  || fail "the updater was not linked by clang22 ($CL/bin/clang)"
exe="$T/shipyard-updater.app/Contents/MacOS/shipyard-updater"
[ -f "$exe" ] || fail "no $exe"
"$CL/bin/llvm-otool" -l "$exe" > "$T/lc"
grep -E '(version|minos) 10\.9$' "$T/lc" > /dev/null || fail 'the x86_64 updater must record minos 10.9'
grep -E 'sdk 10\.9$' "$T/lc" > /dev/null || fail 'the x86_64 updater must record the pinned 10.9 SDK'

cmake -S "$ROOT" -B "$T/bare" -DSHIPYARD_BUILD_UPDATER=ON -DMAVERICKS_ALLOW_GENERIC_ICON=ON \
  -DCMAKE_TOOLCHAIN_FILE="$ROOT/MavericksToolchain.cmake" -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DCMAKE_OBJC_COMPILER="$CL/bin/clang" > "$T/bare.log" 2>&1 || { cat "$T/bare.log"; fail 'a configure naming only clang22 failed'; }
cmake --build "$T/bare" -v > "$T/bare.log" 2>&1 || { cat "$T/bare.log"; fail 'a build configured with only clang22 failed'; }
for line in compile link; do
  case $line in compile) pat='-c .*shipyard-updater-main.m' ;; link) pat=' -o shipyard-updater ' ;; esac
  l="$(grep -e "$pat" "$T/bare.log" | head -1)"
  [ -n "$l" ] || fail "no $line line for the updater in the build log"
  case " $l " in *' --no-default-config '*) ;; *) fail "the updater's $line line must carry --no-default-config, or clang22's clang.cfg adds Recaulk and libc++ to it: $l" ;; esac
  case " $l " in *' --target=x86_64-apple-macos10.9 '*) ;; *) fail "the updater's $line line must name its target, or a Linux host compiles it for Linux: $l" ;; esac
done
grep -e ' -o shipyard-updater ' "$T/bare.log" | grep -e ' -fuse-ld=lld ' > /dev/null \
  || fail 'the updater must link with ld64.lld (-fuse-ld=lld) on every host'
if cmake -S "$ROOT" -B "$T/wrong" -DSHIPYARD_BUILD_UPDATER=ON -DMAVERICKS_ALLOW_GENERIC_ICON=ON \
  -DCMAKE_TOOLCHAIN_FILE="$ROOT/MavericksToolchain.cmake" -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DCMAKE_OBJC_COMPILER="$CL/bin/clang" -DCMAKE_OBJC_COMPILER_TARGET=x86_64-apple-macos10.10 > "$T/wrong.log" 2>&1; then
  fail 'a compiler target other than the configure arch and floor (x86_64-apple-macos10.9) must be refused'
fi
grep -q "CMAKE_OBJC_COMPILER_TARGET is" "$T/wrong.log" \
  || { cat "$T/wrong.log"; fail 'the wrong compiler target failed the configure for some other reason'; }
echo 'PASS: the updater builds with clang22 on a Mac, and mavericks_add_updater_app gives it the flags it owns'
