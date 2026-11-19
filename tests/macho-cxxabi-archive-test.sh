#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
MC="$here/../scripts/macho-cxxabi.sh"
CL="$(sh "$here/../scripts/fetch_clang22.sh" "$here/../components/clang22" 2>/dev/null)" || { echo "SKIP: no clang22 to fetch"; exit 77; }
w="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/mc-archive.XXXXXX")" && pwd)"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
export LIPO="$CL/bin/llvm-lipo" OTOOL="$CL/bin/llvm-otool" NM="$CL/bin/llvm-nm"
AR="$CL/bin/llvm-ar"
cd "$w"

printf 'void __cxa_throw(void) {}\n' > throw.c
"$CL/bin/clang" --no-default-config -target x86_64-apple-macos10.9 -c throw.c -o throw.o
printf 'rustc 1.99.1 metadata, not an object\n' > lib.rmeta

"$AR" rcs t.rlib throw.o lib.rmeta
out="$(sh "$MC" t.rlib)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || fail "archive with an rmeta member: exit $rc, want 0"
[ "$out" = "x86_64 defines ___cxa_throw visible" ] || fail "archive with an rmeta member: got '$out'"
echo "ok: archive with an rmeta member is read"

size="$(wc -c < throw.o | tr -d ' ')"
dd if=throw.o bs=1 count=$((size / 2)) of=corrupt.o 2>/dev/null
"$AR" rcS bad.a corrupt.o lib.rmeta
sh "$MC" bad.a > /dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" -eq 4 ] || fail "corrupt Mach-O member: exit $rc, want 4"
echo "ok: corrupt Mach-O member still fails"

printf 'void __cxa_call_terminate(void) {}\n' > term.c
mkdir dup1 dup2
cp throw.o dup1/m.o
"$CL/bin/clang" --no-default-config -target x86_64-apple-macos10.9 -c term.c -o dup2/m.o
"$AR" rcS dup.a dup1/m.o dup2/m.o
out="$(sh "$MC" dup.a)" || fail "two members of one name: exit $?"
want="$(printf 'x86_64 defines ___cxa_call_terminate visible\nx86_64 defines ___cxa_throw visible')"
[ "$out" = "$want" ] || fail "two members of one name: got '$out'"
echo "ok: members sharing a name are all read"

printf '#!/bin/sh\ncase "$1" in *N*) echo "ar: illegal option -- N" >&2; exit 1 ;; esac\nexec "%s" "$@"\n' "$AR" > ar-no-n
chmod +x ar-no-n
out="$(AR="$w/ar-no-n" sh "$MC" dup.a)" || fail "two members of one name, ar without N: exit $?"
[ "$out" = "$want" ] || fail "two members of one name, ar without N: got '$out'"
echo "ok: members sharing a name are read by an ar without N"

"$CL/bin/clang" --no-default-config -target x86_64-apple-macos10.9 -flto -c throw.c -o bc.o
"$AR" rcS bc.a bc.o lib.rmeta
sh "$MC" bc.a > /dev/null 2>"$w/bc.err" && rc=0 || rc=$?
[ "$rc" -eq 4 ] || fail "bitcode member: exit $rc, want 4"
grep -q 'bc.o' "$w/bc.err" || fail "bitcode member: stderr does not name the member"
echo "ok: bitcode member exits 4, named"

: > empty.txt
"$AR" rcS none.a lib.rmeta empty.txt
sh "$MC" none.a > /dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" -eq 1 ] || fail "archive with no Mach-O member: exit $rc, want 1"
"$AR" rcS empty.a
sh "$MC" empty.a > /dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" -eq 1 ] || fail "empty archive: exit $rc, want 1"
echo "ok: archive with no Mach-O member is not Mach-O"

"$CL/bin/clang" --no-default-config -target i386-apple-macos10.9 -c throw.c -o throw-i386.o
"$AR" rcS x86.a throw.o
"$AR" rcS i386.a throw-i386.o
"$LIPO" -create x86.a i386.a -output fat.a
out="$(sh "$MC" fat.a)" || fail "fat archive: exit $?"
want="$(printf 'x86_64 defines ___cxa_throw visible\ni386 defines ___cxa_throw visible')"
[ "$(printf '%s\n' "$out" | LC_ALL=C sort)" = "$(printf '%s\n' "$want" | LC_ALL=C sort)" ] || fail "fat archive: got '$out'"
echo "ok: every slice of a fat archive is read"
