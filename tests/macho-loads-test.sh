#!/bin/sh
# platform: host-agnostic
#   usage: macho-loads-test.sh
#          macho-loads.sh prints each slice's install name, dylib loads and rpaths, reading a thin file directly and a
#          fat file per thinned slice. Exits 77 without LLVM's Mach-O readers.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
. "$here/scripts/mavergreen-meta.sh"
. "$here/scripts/lib/name-rules.sh"
. "$here/scripts/lib/macho-tools.sh"
S="$here/scripts/macho-loads.sh"
mx="$here/tests/fixtures/macho"
t="$(mktemp -d "${TMPDIR:-/tmp}/macho-loads-test.XXXXXX")"; trap 'rm -rf "$t"' EXIT
bad=0
fail() { echo "FAIL $1"; bad=1; }

rc=0; sh "$S" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "no argument is a usage error (2), got $rc"

if ! mach_tool LIPO >/dev/null 2>&1 || ! mach_tool OTOOL >/dev/null 2>&1; then
  [ "$bad" -eq 0 ] || exit 1
  echo "SKIP: no LLVM Mach-O readers"; exit 77
fi

out="$(sh "$S" "$mx/loader")" || fail "a thin file is read directly, which llvm-lipo -thin refuses"
[ "$out" = "x86_64 dylib @rpath/libt.dylib
x86_64 rpath @loader_path/../lib" ] || fail "loader prints its one load and its one rpath, got: $out"

out="$(sh "$S" "$mx/libw")" || fail "a dylib is read"
[ "$out" = "x86_64 id @rpath/libw.dylib" ] || fail "libw prints its install name as an id row, got: $out"

out="$(sh "$S" "$mx/fat130")" || fail "a fat file is read per slice"
[ "$out" = "x86_64 dylib /usr/lib/libSystem.B.dylib" ] \
  || fail "fat130 prints its x86_64 slice's load and nothing for a130, which carries only LC_BUILD_VERSION, got: $out"

printf 'not a binary\n' > "$t/text"
rc=0; sh "$S" "$t/text" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "a text file is not Mach-O (1), got $rc"

printf '\312\376\272\276\000\000\000\002' > "$t/fat"; head -c 64 /dev/zero >> "$t/fat"
rc=0; sh "$S" "$t/fat" >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "lipo failing on a fat Mach-O header is a reader that died (4), got $rc"

[ "$bad" -eq 0 ] || exit 1
echo "PASS macho-loads"
