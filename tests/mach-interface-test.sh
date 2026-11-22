#!/bin/sh
# platform: host-agnostic
#   usage: mach-interface-test.sh
#          scripts/lib/mach-interface.sh: the Rust symbol normaliser without tools, then the interface of
#          Mach-O fixtures built at test time with the pinned clang22 and 10.9 SDK, judged through
#          build-equivalence.sh. Without clang22: SKIP, exit 77.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../scripts/lib/mach-nm.sh"; . "$here/../scripts/lib/mach-interface.sh"
BE="$here/../scripts/build-equivalence.sh"
w="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/mach-interface.XXXXXX")" && pwd)"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: mach-interface: $*"; exit 1; }
T="$(printf '\t')"

norm() { printf '%s\n' "$@" | shipyard_rust_sym_normalize; }
a="$(norm __ZN4core3fmt5write17h0123456789abcdefE)"; b="$(norm __ZN4core3fmt5write17hfedcba9876543210E)"
[ "$a" = "$b" ] || fail "legacy Rust names differing only in hash: '$a' vs '$b'"
[ "$a" = __ZN4core3fmt5write17hHE ] || fail "legacy hash is written H: '$a'"
a="$(norm __RNvNtCs1a2B3c_4core3fmt5write)"; b="$(norm __RNvNtCsXyZ_4core3fmt5write)"
[ "$a" = "$b" ] || fail "v0 names differing only in a crate disambiguator: '$a' vs '$b'"
[ "$a" = __RNvNtCs_4core3fmt5write ] || fail "v0 disambiguator becomes Cs_: '$a'"
a="$(norm __RINvNtCs1a_4core3ptr13drop_in_placeNtB4_3FooE)"; b="$(norm __RINvNtCs1abc_4core3ptr13drop_in_placeNtB6_3FooE)"
[ "$a" = "$b" ] || fail "v0 back-references shifted by a disambiguator: '$a' vs '$b'"
[ "$(norm _RNvCs9_4core4B9_x)" = _RNvCs_4core4B9_x ] || fail "v0 identifier bytes are not rewritten"
for n in __ZN3foo3barEv _widgetCs1a_2 __Rfoo __ZN4core3fmt5write17h0123456789abcdeE; do
  [ "$(norm "$n")" = "$n" ] || fail "non-Rust name $n changed to '$(norm "$n")'"
done
[ "$(norm a b c | wc -l | tr -d ' ')" = 3 ] || fail "one line out per line in"
echo "ok: Rust symbol normaliser"

CL="$(sh "$here/../scripts/fetch_clang22.sh" "$here/../components/clang22" 2>/dev/null)" || { echo "SKIP: no clang22"; exit 77; }
SDK="$(sh "$here/../scripts/fetch_sdk.sh" 2>/dev/null)" || fail "no pinned 10.9 SDK"
NM="$CL/bin/llvm-nm"; OTOOL="$CL/bin/llvm-otool"; export NM OTOOL
cc() { "$CL/bin/clang" --no-default-config -target "${TGT:-x86_64-apple-macos10.9}" -isysroot "$SDK" "$@"; }
cd "$w"
src() { printf '%s\n' "$@" > "$w/s.c"; }
F1='int f1(void) { return 1; }'; F2='int f2(void) { return 2; }'
PUTS='#include <stdio.h>
int p(void) { return puts("x"); }'
dy() { _o="$1"; shift; cc -dynamiclib -install_name /opt/a/libx.dylib "$w/s.c" -o "$w/$_o" "$@"; }
pair() {
  rm -rf "$w/A" "$w/B"; mkdir -p "$w/A/lib" "$w/B/lib"; cp "$w/$1" "$w/A/lib/${3:-x.dylib}"; cp "$w/$2" "$w/B/lib/${3:-x.dylib}"
  rc=0; sh "$BE" --repo "$w" "$w/A" "$w/B" > "$w/out" 2> "$w/err" || rc=$?
  out="$(cat "$w/out")"; err="$(cat "$w/err")"
}
level() {
  [ "$(sed -n 1p "$w/out")" = "$2${T}lib/${3:-x.dylib}${T}-" ] || fail "$1: want $2, got: $out (err: $err)"
  [ "$rc" -eq 1 ] || fail "$1: exit $rc, want 1"
}
detail() { grep -qx "  $2" "$w/out" || fail "$1: no detail line '$2' in: $out"; }

src "$F1" "$F2"; dy base.dylib
src "$F2" "$F1"; dy reorder.dylib
mi="$(shipyard_mach_interface "$w/base.dylib")" || fail "interface of a dylib: exit $?"
for f in "x86_64 export _f1" "x86_64 export _f2" "x86_64 import dyld_stub_binder" "x86_64 dylib 1 load /usr/lib/libSystem.B.dylib" \
         "x86_64 id /opt/a/libx.dylib" "x86_64 minos 10.9" "x86_64 sdk 10.9" "x86_64 section __TEXT,__text"; do
  printf '%s\n' "$mi" | grep -qx "$f" || fail "interface of a dylib lacks '$f': $mi"
done
[ "$mi" = "$(printf '%s\n' "$mi" | LC_ALL=C sort -u)" ] || fail "interface lines are sorted and unique"
pair base.dylib reorder.dylib; level "function order" bytes
[ "$out" = "bytes${T}lib/x.dylib${T}-" ] || fail "function order: no detail lines: $out"
echo "ok: function order is bytes"

src "$F1" "$F2" "$PUTS"; dy import.dylib
pair base.dylib import.dylib; level "added import" interface; detail "added import" "only in B: x86_64 import _puts"
src "$F1" "$F2"; dy weak.dylib -Wl,-weak_library,"$SDK/usr/lib/libz.dylib"
pair base.dylib weak.dylib; level "weak dylib" interface
grep -q '^  only in B: x86_64 dylib [0-9]* weak /usr/lib/libz\.1\.dylib$' "$w/out" || fail "weak dylib: no detail: $out"
( TGT=x86_64-apple-macos10.10; dy minos.dylib )
pair base.dylib minos.dylib; level "deployment target" interface
detail "deployment target" "only in A: x86_64 minos 10.9"; detail "deployment target" "only in B: x86_64 minos 10.10"
cc -dynamiclib -install_name /opt/b/libx.dylib "$w/s.c" -o "$w/id.dylib"
pair base.dylib id.dylib; level "install name" interface; detail "install name" "only in B: x86_64 id /opt/b/libx.dylib"
dy rpath.dylib -Wl,-rpath,/opt/r
pair base.dylib rpath.dylib; level "rpath" interface; detail "rpath" "only in B: x86_64 rpath 1 /opt/r"
echo "ok: imports, weak loads, deployment target, install name and rpaths are interface"

src 'int main(void) { return 0; }'; cc "$w/s.c" -o "$w/exe-a"
src 'int main(void) { return 0; }' 'int extra(void) { return 3; }'; cc "$w/s.c" -o "$w/exe-b"
mi="$(shipyard_mach_interface "$w/exe-b")" || fail "interface of an executable: exit $?"
case "$mi" in *" export "*) fail "an executable's exports are not interface: $mi" ;; esac
pair exe-a exe-b bin; level "executable exports" bytes bin
echo "ok: an executable's exports are not interface"

src "$F1" "$F2"; cc -c "$w/s.c" -o "$w/m64.o"
"$CL/bin/clang" --no-default-config -target i386-apple-macos10.9 -isysroot "$SDK" -c "$w/s.c" -o "$w/m32.o"
"$CL/bin/llvm-lipo" -create "$w/m32.o" "$w/m64.o" -output "$w/fat.o"
pair fat.o m64.o m.o; level "fat object vs thin" interface m.o; detail "fat object vs thin" "only in A: i386 export _f1"
if "$CL/bin/clang" --no-default-config -target arm64-apple-macos11.0 -isysroot "$SDK" -dynamiclib -install_name /opt/a/libx.dylib "$w/s.c" -o "$w/arm.dylib" 2>/dev/null \
   || "$CL/bin/clang" --no-default-config -target arm64-apple-macos11.0 -isysroot "$(sh "$here/../scripts/fetch_sdk.sh" --arch arm64)" -dynamiclib -install_name /opt/a/libx.dylib "$w/s.c" -o "$w/arm.dylib" 2>/dev/null; then
  "$CL/bin/llvm-lipo" -create "$w/base.dylib" "$w/arm.dylib" -output "$w/universal.dylib"
  pair universal.dylib base.dylib; level "universal vs thin" interface; detail "universal vs thin" "only in A: arm64 minos 11.0"
  echo "ok: a universal binary's slice set is interface"
else
  echo "skip: this clang22 cannot build arm64; the slice set is covered by the fat object"
fi

src "$F1"; cc -c "$w/s.c" -o "$w/m1.o"; src "$F2"; cc -c "$w/s.c" -o "$w/m2.o"; src "$F2" "$PUTS"; cc -c "$w/s.c" -o "$w/m3.o"
printf 'rustc metadata\n' > "$w/lib.rmeta"
"$CL/bin/llvm-ar" rcs "$w/one.a" "$w/m1.o" "$w/m2.o" "$w/lib.rmeta"
"$CL/bin/llvm-ar" rcs "$w/two.a" "$w/lib.rmeta" "$w/m2.o" "$w/m1.o"
"$CL/bin/llvm-ar" rcs "$w/three.a" "$w/m1.o" "$w/m3.o" "$w/lib.rmeta"
mi="$(shipyard_mach_interface "$w/one.a")" || fail "interface of an archive: exit $?"
[ "$mi" = "x86_64 export _f1
x86_64 export _f2" ] || fail "an archive's interface is its members' exports and imports only: $mi"
pair one.a two.a libx.a; level "archive members reordered" bytes libx.a
pair one.a three.a libx.a; level "archive member import" interface libx.a; detail "archive member import" "only in B: x86_64 import _puts"
printf '\177ELF one\n' > "$w/e1.o"; printf '\177ELF two\n' > "$w/e2.o"
"$CL/bin/llvm-ar" rcs "$w/elf1.a" "$w/e1.o"; "$CL/bin/llvm-ar" rcs "$w/elf2.a" "$w/e2.o"
pair elf1.a elf2.a libe.a; level "archive without Mach-O members" bytes libe.a
echo "ok: archives"

dd if="$w/base.dylib" of="$w/trunc.dylib" bs=64 count=1 2>/dev/null; chmod +x "$w/trunc.dylib"
pair base.dylib trunc.dylib
[ "$rc" -eq 2 ] || fail "truncated Mach-O: exit $rc, want 2 (out: $out; err: $err)"
case "$err" in *lib/x.dylib*) ;; *) fail "truncated Mach-O: stderr must name the path: $err" ;; esac
echo "ok: an unreadable Mach-O exits 2 naming the path"
echo "PASS: mach-interface"
