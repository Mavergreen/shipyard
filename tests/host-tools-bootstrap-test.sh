#!/bin/sh
# platform: macOS-only -- builds and inspects a host-native Mach-O tool with clang22 and the pinned SDK
# usage: sh tests/host-tools-bootstrap-test.sh
#        mavergreen_build_host_tools on this Mac, from a small fixture source: a fresh build is the
#        host's arch, minimum and SDK; the same inputs reuse it; a tampered, unstamped or interrupted
#        entry is never returned; a changed source gets its own entry; two writers build once; an
#        OUTPUT_ROOT inside the source is refused. MAVERGREEN_HOST_TOOLS_CC names the compiler
#        (default: the installed clang22, clang-22 on 10.9 or clang-22-cross on a modern Mac). Without
#        one the test skips, unless SHIPYARD_ON_TARGET=1 (tests/maintainer-tests).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
fx="$here/fixtures/host-tools"
SC="${CMAKE:-$(command -v shipyard-cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)}"
unmet() {
  if [ "${SHIPYARD_ON_TARGET:-}" = 1 ]; then echo "FAIL: $*"; exit 1; fi
  echo "SKIP: $*"; exit 77
}
CC="${MAVERGREEN_HOST_TOOLS_CC:-}"
if [ -z "$CC" ]; then
  for c in /usr/local/mavergreen/bin/clang-22 /usr/local/mavergreen/bin/clang-22-cross; do
    [ -x "$c" ] && { CC="$c"; break; }
  done
fi
[ -x "$SC" ] || unmet "no shipyard-cmake"
[ -n "$CC" ] && [ -x "$CC" ] || unmet "no clang22 (set MAVERGREEN_HOST_TOOLS_CC)"
TOOLBIN="$(dirname "$(cd "$(dirname "$CC")" && pwd -P)/$(basename "$(readlink "$CC" || echo "$CC")")")"
OTOOL="$TOOLBIN/llvm-otool"; LIPO="$TOOLBIN/llvm-lipo"
[ -x "$OTOOL" ] && [ -x "$LIPO" ] || unmet "no llvm-otool/llvm-lipo beside $CC"
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = 1 ]; then
  want_arch=arm64 want_min=11.0 want_sdk=11.3
else
  want_arch=x86_64 want_min=10.9 want_sdk=10.9
fi

_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/host tools bootstrap.XXXXXX")"
trap 'rm -rf "$w"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
cp -R "$fx/fake-mulle" "$w/src"
counter="$w/configures"; : > "$counter"

build() {
  MHT_TEST_COUNTER="$counter" "$SC" -DMODULE_DIR="$root" -DCOMPILER="$CC" -DSOURCE="$1" -DROOT="$2" \
    -DRESULT="$3" -P "$fx/build.cmake" > "$3.log" 2>&1
}
configures() { wc -l < "$counter" | tr -d ' '; }
tool() { printf '%s/mulle-xcode-to-cmake\n' "$(cat "$1")"; }

echo "== fresh_bootstrap"
if ! build "$w/src" "$w/cache" "$w/r1"; then cat "$w/r1.log"; echo "FAIL: fresh bootstrap"; exit 1; fi
t1="$(tool "$w/r1")"
case "$t1" in "$w/cache"/*) ;; *) echo "FAIL: the tool '$t1' is not under OUTPUT_ROOT"; exit 1 ;; esac
[ -x "$t1" ] || { echo "FAIL: no executable at $t1"; exit 1; }
[ "$("$LIPO" -archs "$t1" | xargs)" = "$want_arch" ] || bad "fresh: $t1 is $("$LIPO" -archs "$t1"), want $want_arch"
lc="$("$OTOOL" -l "$t1")"
printf '%s\n' "$lc" | grep -Eq "(version|minos) $want_min\$" || bad "fresh: minimum is not $want_min"
printf '%s\n' "$lc" | grep -Eq "sdk $want_sdk\$" || bad "fresh: SDK is not $want_sdk"
"$t1" | grep -q 'fake mulle-xcode-to-cmake' || bad "fresh: the built tool does not run natively"
[ "$(configures)" = 1 ] || bad "fresh: configured $(configures) times, want 1"

echo "== warm_cache_same_inputs"
build "$w/src" "$w/cache" "$w/r2" || bad "warm: $(cat "$w/r2.log")"
[ "$(cat "$w/r2")" = "$(cat "$w/r1")" ] || bad "warm: another directory for the same inputs"
[ "$(configures)" = 1 ] || bad "warm: the same inputs were rebuilt"

echo "== tampered_binary"
printf 'tampered' >> "$t1"
build "$w/src" "$w/cache" "$w/r3" || bad "tampered: $(cat "$w/r3.log")"
t3="$(tool "$w/r3")"
[ "$(configures)" = 2 ] || bad "tampered: the tampered entry was not rebuilt"
if tail -c 8 "$t3" | grep -q tampered; then bad "tampered: the tampered binary was returned"; fi
"$t3" | grep -q 'fake mulle' || bad "tampered: the rebuilt tool does not run"

echo "== interrupted_cache"
rm -f "$(cat "$w/r3")/../stamp.json" "$(dirname "$(cat "$w/r3")")/stamp.json"
build "$w/src" "$w/cache" "$w/r4" || bad "interrupted: $(cat "$w/r4.log")"
[ "$(configures)" = 3 ] || bad "interrupted: an unstamped entry was used"
[ -f "$(dirname "$(cat "$w/r4")")/stamp.json" ] || bad "interrupted: the rebuilt entry has no stamp"

echo "== changed_sdk_or_pin"
printf '/* changed */\n' >> "$w/src/main.c"
build "$w/src" "$w/cache" "$w/r5" || bad "changed: $(cat "$w/r5.log")"
[ "$(cat "$w/r5")" != "$(cat "$w/r4")" ] || bad "changed: a changed source reused the old entry"
[ -x "$(tool "$w/r4")" ] || bad "changed: the old entry was removed"
[ "$(configures)" = 4 ] || bad "changed: the changed source was not built"

echo "== concurrent_cache_writer"
: > "$counter"
build "$w/src" "$w/cache2" "$w/c1" & p1=$!
build "$w/src" "$w/cache2" "$w/c2" & p2=$!
r1=0; wait $p1 || r1=$?; r2=0; wait $p2 || r2=$?
[ "$r1" = 0 ] && [ "$r2" = 0 ] || bad "concurrent: a writer failed: $(cat "$w/c1.log" "$w/c2.log")"
[ "$(cat "$w/c1")" = "$(cat "$w/c2")" ] || bad "concurrent: two directories for the same inputs"
[ "$(configures)" = 1 ] || bad "concurrent: built $(configures) times, want 1"

echo "== escaping_output_parent"
if build "$w/src" "$w/src/cache" "$w/e1"; then bad "escaping: an OUTPUT_ROOT inside the source was accepted"; fi
grep -q 'mavergreen_build_host_tools' "$w/e1.log" || bad "escaping: refused without naming the function: $(cat "$w/e1.log")"
[ ! -e "$w/src/cache" ] || bad "escaping: something was written inside the source"
ln -s "$w/src" "$w/into-src"
if build "$w/src" "$w/into-src/cache" "$w/e2"; then bad "escaping: an OUTPUT_ROOT reaching the source through a link was accepted"; fi
[ ! -e "$w/src/cache" ] || bad "escaping: something was written inside the source through the link"

[ "$fail" -eq 0 ] && echo "host-tools-bootstrap-test: OK"
exit "$fail"
