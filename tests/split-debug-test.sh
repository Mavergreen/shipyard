#!/bin/sh
# platform: host-agnostic
#   usage: split-debug-test.sh
#          split-debug.sh moves each linked Mach-O's DWARF into a deterministic dSYM tarball and strips the
#          debug map, keeping local symbols and an arm64 slice's ad-hoc signature. Exits 77 without
#          LLVM's Mach-O tools.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/scripts/mavergreen-meta.sh"
. "$root/scripts/lib/name-rules.sh"
. "$root/scripts/lib/macho-tools.sh"
S="$root/scripts/split-debug.sh"
mx="$root/tests/fixtures/macho"
t="$(mktemp -d "${TMPDIR:-/tmp}/split-debug-test.XXXXXX")"; trap 'rm -rf "$t"' EXIT
bad=0
fail() { echo "FAIL $1"; bad=1; }

rc=0; sh "$S" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "no argument is a usage error (2), got $rc"

for v in DSYMUTIL STRIP NM OTOOL LIPO OBJDUMP; do
  mach_tool "$v" >/dev/null 2>&1 && continue
  [ "$bad" -eq 0 ] || exit 1
  echo "SKIP: no LLVM Mach-O tools ($v)"; exit 77
done
SOURCE_DATE_EPOCH=1700000000; export SOURCE_DATE_EPOCH

oso() { "$NM" -a -arch all "$1" | awk '$5 == "OSO"' | wc -l | tr -d ' '; }
uuids() { "$OBJDUMP" --macho --arch=all --private-headers "$1" | awk '$1 == "uuid" { print $2 }' | LC_ALL=C sort; }
run() {  # $1 = root, $2 = out, from the fixtures directory, where the debug maps' objects are
  (cd "$mx" && sh "$S" --root "$1" --short w --version 1.0 --out "$2")
}

mkdir -p "$t/r1/bin" "$t/r1/lib" "$t/r1/share"
cp "$mx/dbg" "$t/r1/bin/dbg"
cp "$mx/libm.a" "$t/r1/lib/libm.a"
echo hi > "$t/r1/share/readme"
[ "$(oso "$t/r1/bin/dbg")" -gt 0 ] || fail "the dbg fixture carries a debug map"
run "$t/r1" "$t/o1" > "$t/o1.log" 2>&1 || { fail "split-debug.sh on dbg:"; sed 's/^/    | /' "$t/o1.log"; }
[ "$(oso "$t/r1/bin/dbg")" = 0 ] || fail "the stripped dbg has no debug map"
"$NM" -a "$t/r1/bin/dbg" | grep -q ' t _dbg_helper$' || fail "local symbols survive the strip"
cmp -s "$mx/libm.a" "$t/r1/lib/libm.a" || fail "a static archive is not linked, and is left alone"
tb="$t/o1/w-1.0-dSYM.tar.gz"
dw=w-1.0-dSYM/bin/dbg.dSYM/Contents/Resources/DWARF/dbg
tar -tzf "$tb" > "$t/list" 2>/dev/null || fail "the tarball reads"
grep -qx "$dw" "$t/list" || { fail "the tarball holds $dw"; sed 's/^/    | /' "$t/list"; }
grep -q '/Relocations/' "$t/list" && fail "the tarball holds no Relocations/, which names the staged root"
mkdir -p "$t/x1" && (cd "$t/x1" && tar -xzf "$tb")
[ -n "$(uuids "$t/r1/bin/dbg")" ] && [ "$(uuids "$t/x1/$dw")" = "$(uuids "$t/r1/bin/dbg")" ] \
  || fail "the DWARF file's LC_UUID is the binary's"
grep -Eq 'readme|libm' "$t/list" && fail "only dSYMs go in the tarball"

mkdir -p "$t/r2/bin" "$t/r2/lib" "$t/r2/share"
cp "$mx/dbg" "$t/r2/bin/dbg"; cp "$mx/libm.a" "$t/r2/lib/libm.a"; echo hi > "$t/r2/share/readme"
run "$t/r2" "$t/o2" >/dev/null 2>&1 || fail "the second run"
cmp -s "$tb" "$t/o2/w-1.0-dSYM.tar.gz" || fail "two runs give byte-identical tarballs"
cmp -s "$t/r1/bin/dbg" "$t/r2/bin/dbg" || fail "two runs strip to identical bytes"

mkdir -p "$t/r3/bin"
cp "$mx/dbgfat" "$t/r3/bin/dbgfat"
rc=0; run "$t/r3" "$t/o3" > "$t/o3.log" 2>&1 || rc=$?
# platform: the native clang22 pkg on 10.9 builds for x86_64 alone, so its dsymutil has no AArch64 target
if [ "$rc" = 4 ] && grep -q 'lacks a target' "$t/o3.log"; then
  echo "skip ($DSYMUTIL has no AArch64 target): dbgfat"
  cmp -s "$mx/dbgfat" "$t/r3/bin/dbgfat" || fail "a dsymutil without the target strips nothing"
else
  [ "$rc" = 0 ] || { fail "split-debug.sh on dbgfat:"; sed 's/^/    | /' "$t/o3.log"; }
  [ "$(oso "$t/r3/bin/dbgfat")" = 0 ] || fail "neither stripped slice has a debug map"
  mkdir -p "$t/x3" && (cd "$t/x3" && tar -xzf "$t/o3/w-1.0-dSYM.tar.gz")
  dwf="$t/x3/w-1.0-dSYM/bin/dbgfat.dSYM/Contents/Resources/DWARF/dbgfat"
  [ "$(uuids "$t/r3/bin/dbgfat" | wc -l | tr -d ' ')" = 2 ] && [ -f "$dwf" ] && [ "$(uuids "$dwf")" = "$(uuids "$t/r3/bin/dbgfat")" ] \
    || fail "the fat DWARF file carries both slices' LC_UUIDs"
  if [ "$(uname -s)" = Darwin ] && [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then
    # platform: guarded macOS-only call -- the if above admits only an arm64 Mac, which has codesign and runs the arm64 slice
    codesign -v -a arm64 "$t/r3/bin/dbgfat" || fail "the stripped arm64 slice keeps a valid ad-hoc signature"
    "$t/r3/bin/dbgfat" || fail "the stripped arm64 slice runs"
  fi
fi

mkdir -p "$t/r4/bin"
cp "$mx/clean" "$t/r4/bin/clean"
rc=0; run "$t/r4" "$t/o4" > "$t/o4.log" 2>&1 || rc=$?
[ "$rc" = 1 ] && grep -q 'bin/clean has no debug map' "$t/o4.log" || { fail "a linked image with no debug map is exit 1, got $rc"; sed 's/^/    | /' "$t/o4.log"; }
[ ! -e "$t/o4/w-1.0-dSYM.tar.gz" ] || fail "a failed run writes no tarball"

mkdir -p "$t/r5/bin"
cp "$mx/dbg" "$t/r5/bin/dbg"
rc=0; (cd "$t" && sh "$S" --root "$t/r5" --short w --version 1.0 --out "$t/o5") > "$t/o5.log" 2>&1 || rc=$?
[ "$rc" = 1 ] && grep -q 'cannot read' "$t/o5.log" || { fail "objects the debug map names but the build root lacks are exit 1, got $rc"; sed 's/^/    | /' "$t/o5.log"; }
cmp -s "$mx/dbg" "$t/r5/bin/dbg" || fail "a failed run strips nothing"

mkdir -p "$t/r6/bin"
cp "$mx/dbg" "$t/r6/bin/dbg"
rc=0; (cd "$mx" && DSYMUTIL="$t/none/dsymutil" sh "$S" --root "$t/r6" --short w --version 1.0 --out "$t/o6") >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "a missing dsymutil is exit 4, got $rc"

[ "$bad" -eq 0 ] || exit 1
echo "PASS: split-debug"
