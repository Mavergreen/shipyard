#!/bin/sh
# platform: host-agnostic
#   usage: fat-macho-test.sh
#          A fat Mach-O and a Java class file share the magic cafebabe; the arch count after it tells
#          them apart. A fat Mach-O is a Mach-O to check, and a reader that cannot read one fails the
#          guard closed; a class file is skipped. Exits 77 without LLVM's Mach-O readers.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
. "$here/scripts/lib/pkg-tree.sh"
. "$here/scripts/lib/macho-tools.sh"
t="$(mktemp -d "${TMPDIR:-/tmp}/fat-macho-test.XXXXXX")"; trap 'rm -rf "$t"' EXIT
unset SHIPYARD_CHECK_RUNLOG SHIPYARD_CHECK_FAILLOG SHIPYARD_CHECK_NOTRUNLOG SHIPYARD_CHECK_SELECTED SHIPYARD_CHECK_DIST
bad=0
fail() { echo "FAIL $1"; bad=1; }

printf '\312\376\272\276\000\000\000\002' > "$t/fat"; head -c 64 /dev/zero >> "$t/fat"
printf '\312\376\272\276\000\000\000\064' > "$t/Fake.class"; head -c 64 /dev/zero >> "$t/Fake.class"
printf '!<arch>\n' > "$t/lib.a"
printf '\317\372\355\376' > "$t/thin"
[ "$(af_macho_kind "$t/fat")" = strict ] || fail "M13: a fat Mach-O header is a Mach-O, got '$(af_macho_kind "$t/fat")'"
[ -z "$(af_macho_kind "$t/Fake.class")" ] || fail "M13: a Java class file is not a Mach-O, got '$(af_macho_kind "$t/Fake.class")'"
[ "$(af_macho_kind "$t/lib.a")" = loose ] || fail "M13: an ar archive is Mach-O only if the readers say so"
[ "$(af_macho_kind "$t/thin")" = strict ] || fail "M13: a thin Mach-O magic is a Mach-O"

if ! mach_tool LIPO >/dev/null 2>&1 || ! mach_tool OTOOL >/dev/null 2>&1; then
  [ "$bad" -eq 0 ] || exit 1
  echo "SKIP: no LLVM Mach-O readers"; exit 77
fi
rc=0; sh "$here/scripts/macho-slices.sh" "$t/fat" >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "M13: lipo failing on a fat Mach-O header is a reader that died (4), got $rc"
rc=0; sh "$here/scripts/macho-slices.sh" "$t/Fake.class" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "M13: a class file is not Mach-O (1), got $rc"

for k in fat Fake.class; do
  rm -rf "$t/root" "$t/dist"; mkdir -p "$t/root/lib" "$t/dist"; cp "$t/$k" "$t/root/lib/$k"
  (cd "$t/root" && tar czf "$t/dist/demo-1.0.0-mavericks.1.tar.gz" lib)
  rc=0; (cd "$t" && SHIPYARD_CHECK_DIST="$t/dist" sh "$here/scripts/assert_binary_compatible.sh") > "$t/out" 2>&1 || rc=$?
  if [ "$k" = fat ]; then
    [ "$rc" = 1 ] && grep -q 'CANNOT MEASURE' "$t/out" || fail "M13: the guard fails closed on a fat Mach-O lipo cannot read, got $rc: $(cat "$t/out")"
  else
    [ "$rc" = 0 ] || fail "M13: the guard skips a class file, got $rc: $(cat "$t/out")"
  fi
done

[ "$bad" -eq 0 ] || exit 1
echo "PASS fat-macho"
