#!/bin/sh
# platform: host-agnostic
#   usage: mach-interface-test.sh
#          scripts/lib/mach-interface.sh: the Rust symbol normaliser without tools, then the interface of
#          Mach-O fixtures built at test time with the pinned clang22 and 10.9 SDK, judged through
#          build-equivalence.sh. Without clang22: SKIP, exit 77.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../scripts/mavergreen-meta.sh"; . "$here/../scripts/lib/name-rules.sh"; . "$here/../scripts/lib/macho-tools.sh"
. "$here/../scripts/lib/mach-interface.sh"
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
a="$(norm __RINvNtCs1a_4core3ptr13drop_in_placeTNtNtCs2b_5alloc3vec3VecNtBA_3RawEE)"
b="$(norm __RINvNtCs1abc_4core3ptr13drop_in_placeTNtNtCs2b_5alloc3vec3VecNtBC_3RawEE)"
[ "$a" = "$b" ] || fail "v0 back-references to one target, shifted by a disambiguator: '$a' vs '$b'"
a="$(norm __RINvNtCs1a_4core3ptr13drop_in_placeNtB4_3FooE)"; b="$(norm __RINvNtCs1a_4core3ptr13drop_in_placeNtB2_3FooE)"
[ "$a" != "$b" ] || fail "v0 back-references to core and core::ptr stay distinct: both '$a'"
n=__RINvNtCs1a_4core3ptr13drop_in_placeNtB7_3FooE
[ "$(norm "$n")" = "$n" ] || fail "a back-reference with no target passes unchanged: '$(norm "$n")'"
[ "$(norm __RNvCs9_4core4B9_x)" = __RNvCs_4core4B9_x ] || fail "v0 identifier bytes are not rewritten"
for n in __ZN3foo3barEv _widgetCs1a_2 __Rfoo __ZN4core3fmt5write17h0123456789abcdeE _RNvCsa_3foo3bar _ZN4core3fmt5write17h0123456789abcdefE; do
  [ "$(norm "$n")" = "$n" ] || fail "non-Rust name $n changed to '$(norm "$n")'"
done
[ "$(norm a b c | wc -l | tr -d ' ')" = 3 ] || fail "one line out per line in"
a="$(norm _rust_metadata_std_1c4a7586348cee47)"; b="$(norm _rust_metadata_std_0123456789abcdef)"
[ "$a" = _rust_metadata_std_H ] || fail "rustc's metadata symbol has its crate hash written H: '$a'"
[ "$a" = "$b" ] || fail "metadata symbols differing only in hash: '$a' vs '$b'"
[ "$(norm _rust_metadata_proc_macro2_fedcba9876543210)" = _rust_metadata_proc_macro2_H ] || fail "a crate name with underscores keeps them"
[ "$(norm _rust_metadata_std_fda44cb9000b3d7)" = _rust_metadata_std_H ] || fail "rustc prints the metadata hash unpadded: 15 hex digits"
[ "$(norm _rust_metadata_std_1c4a)" = _rust_metadata_std_H ] || fail "an unpadded metadata hash of 4 hex digits"
[ "$(norm _rust_metadata_core_7)" = _rust_metadata_core_H ] || fail "an unpadded metadata hash of 1 hex digit"
[ "$(norm _rust_metadata_foo_ab_0123456789abcdef)" = _rust_metadata_foo_ab_H ] || fail "the hash is the segment after the last underscore"
[ "$(norm _rust_metadata_foo_ab)" = _rust_metadata_foo_H ] || fail "a crate name ending _<hex> with no hash reads its last segment as the hash"
for n in _foo_1c4a7586348cee47 _rust_metadata_std_1C4A7586348CEE47 _rust_metadata_std_1c4A __rust_metadata_std_1c4a7586348cee47 \
         _rust_metadata_std_1c4a7586348cee47x _rust_metadata__1c4a7586348cee47x _rust_metadata__1c4a7586348cee47 \
         _rust_metadata_std_01c4a7586348cee47 _rust_metadata_std_ _rust_metadata_1c4a _rust_metadata_st-d_1c4a; do
  [ "$(norm "$n")" = "$n" ] || fail "$n is not rustc's metadata symbol, yet changed to '$(norm "$n")'"
done
a="$(norm _anon.0123456789abcdef0123456789abcdef.12.llvm.1234567890)"; b="$(norm _anon.fedcba9876543210fedcba9876543210.12.llvm.42)"
[ "$a" = _anon.H.12.llvm.N ] || fail "LLVM's _anon hash is H and its .llvm suffix N: '$a'"
[ "$a" = "$b" ] || fail "_anon names differing only in hash and .llvm number: '$a' vs '$b'"
[ "$(norm _anon.0123456789abcdef0123456789abcdef.3)" = _anon.H.3 ] || fail "an _anon name without a .llvm suffix"
[ "$(norm _anon.0123456789abcdef0123456789abcdef.3)" != "$(norm _anon.0123456789abcdef0123456789abcdef.4)" ] || fail "_anon keeps its index"
[ "$(norm _compiler_builtins_helper.llvm.9876543210)" = _compiler_builtins_helper.llvm.N ] || fail "a C name's .llvm suffix is N"
[ "$(norm __ZN4core3fmt5write17h0123456789abcdefE.llvm.17)" = __ZN4core3fmt5write17hHE.llvm.N ] || fail "a legacy name with a .llvm suffix: the suffix is set aside, then the hash is H"
[ "$(norm __RNvNtCs1a2B3c_4core3fmt5write.llvm.5)" = __RNvNtCs_4core3fmt5write.llvm.N ] || fail "a v0 name with a .llvm suffix"
[ "$(norm _rust_metadata_std_fda44cb9000b3d7.llvm.5)" = _rust_metadata_std_H.llvm.N ] || fail "a metadata name with a .llvm suffix"
for n in _anon.0123456789abcdef0123456789abcde.1 _anon.0123456789ABCDEF0123456789abcdef.1 _anon.0123456789abcdef0123456789abcdef0.1 \
         _anon.0123456789abcdef0123456789abcdef. _anon.0123456789abcdef0123456789abcdef.1x __anon.0123456789abcdef0123456789abcdef.1 \
         _foo.llvm. _foo.llvm.12x _foo.llvm.12.x _foo.LLVM.12 _foo_llvm_12 _foo.llvmx.12; do
  [ "$(norm "$n")" = "$n" ] || fail "$n is not an LLVM per-build name, yet changed to '$(norm "$n")'"
done
echo "ok: Rust symbol normaliser"

CL="$(sh "$here/../scripts/fetch_clang22.sh" "$here/.." 2>/dev/null)" || { echo "SKIP: no clang22"; exit 77; }
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
         "x86_64 id /opt/a/libx.dylib" "x86_64 minos version_min_macosx 10.9" "x86_64 sdk version_min_macosx 10.9" "x86_64 section __TEXT,__text"; do
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
detail "deployment target" "only in A: x86_64 minos version_min_macosx 10.9"; detail "deployment target" "only in B: x86_64 minos version_min_macosx 10.10"
cc -dynamiclib -install_name /opt/b/libx.dylib "$w/s.c" -o "$w/id.dylib"
pair base.dylib id.dylib; level "install name" interface; detail "install name" "only in B: x86_64 id /opt/b/libx.dylib"
dy rpath.dylib -Wl,-rpath,/opt/r
pair base.dylib rpath.dylib; level "rpath" interface; detail "rpath" "only in B: x86_64 rpath 1 /opt/r"
dy sdk.dylib -Wl,-platform_version,macos,10.9,10.10
pair base.dylib sdk.dylib; level "SDK version" interface
detail "SDK version" "only in A: x86_64 sdk version_min_macosx 10.9"; detail "SDK version" "only in B: x86_64 sdk version_min_macosx 10.10"
grep -q 'minos' "$w/out" && fail "SDK version: the deployment target did not change: $out"
cp "$w/weak.dylib" "$w/lazy.dylib"
off="$("$OTOOL" -l "$w/lazy.dylib" | awk -v o=32 '$1 == "cmd" { c = $2 } $1 == "cmdsize" { if (c == "LC_LOAD_WEAK_DYLIB") { print o; exit } o += $2 }')"
[ -n "$off" ] || fail "no LC_LOAD_WEAK_DYLIB to turn lazy"
printf '\040\000\000\000' | dd of="$w/lazy.dylib" bs=1 seek="$off" conv=notrunc 2>/dev/null
pair weak.dylib lazy.dylib; level "lazy dylib" interface
grep -q '^  only in B: x86_64 dylib [0-9]* lazy /usr/lib/libz\.1\.dylib$' "$w/out" || fail "lazy dylib: no detail: $out"
echo "ok: imports, weak and lazy loads, deployment target, SDK, install name and rpaths are interface"

asm() { printf '%s\n' "$@" > "$w/s.s"; }
asm '.macosx_version_min 10, 9 sdk_version 10, 9' '.globl _f' '_f: ret'; cc -c "$w/s.s" -o "$w/vmin.o"
asm '.build_version macos, 10, 9 sdk_version 10, 9' '.globl _f' '_f: ret'; cc -c "$w/s.s" -o "$w/bver.o"
pair vmin.o bver.o v.o; level "LC_VERSION_MIN_MACOSX vs LC_BUILD_VERSION" interface v.o
detail "version load command" "only in A: x86_64 minos version_min_macosx 10.9"; detail "version load command" "only in B: x86_64 minos build_version macos 10.9"
detail "version load command" "only in A: x86_64 sdk version_min_macosx 10.9"; detail "version load command" "only in B: x86_64 sdk build_version macos 10.9"
echo "ok: the deployment target's load command and platform are interface"

BC='.section __LLVM,__bitcode'
asm '.globl _f' '_f: ret' "$BC" '.ascii "BC\300\336junk"'; cc -c "$w/s.s" -o "$w/bc1.o"
asm '.globl _f' '_f: nop' 'ret' "$BC" '.ascii "BC\300\336knuj"'; cc -c "$w/s.s" -o "$w/bc2.o"
asm '.globl _f' '.globl _g' '_f: ret' '_g: ret' "$BC" '.ascii "BC\300\336junk"'; cc -c "$w/s.s" -o "$w/bc3.o"
mi="$(shipyard_mach_interface "$w/bc1.o")" || fail "an object embedding bitcode the pinned llvm cannot parse: exit $?: $mi"
printf '%s\n' "$mi" | grep -qx "x86_64 export _f" || fail "an object embedding bitcode: its exports are read from the Mach-O symbol table: $mi"
pair bc1.o bc2.o b.o; level "embedded bitcode, same symbols" bytes b.o
pair bc1.o bc3.o b.o; level "embedded bitcode, an added export" interface b.o; detail "embedded bitcode" "only in B: x86_64 export _g"
printf 'rustc metadata\n' > "$w/lib.rmeta"; "$CL/bin/llvm-ar" rcs "$w/bc1.a" "$w/bc1.o" "$w/lib.rmeta"
"$CL/bin/llvm-ar" rcs "$w/bc3.a" "$w/bc3.o" "$w/lib.rmeta"
pair bc1.a bc3.a libbc.rlib; level "embedded bitcode in an archive member" interface libbc.rlib; detail "embedded bitcode in an archive" "only in B: x86_64 export _g"
asm '.globl _f' '_f: ret'; "$CL/bin/clang" --no-default-config -target x86_64h-apple-macos10.9 -c "$w/s.s" -o "$w/h.o"
"$CL/bin/clang" --no-default-config -target i386-apple-macos10.9 -c "$w/s.s" -o "$w/i.o"
mi="$(shipyard_mach_interface "$w/h.o")" || fail "an x86_64h object: exit $?"
printf '%s\n' "$mi" | grep -qx "x86_64h export _f" || fail "a thin x86_64h object's arch comes from its header: $mi"
mi="$(shipyard_mach_interface "$w/i.o")" || fail "an i386 object: exit $?"
printf '%s\n' "$mi" | grep -qx "i386 export _f" || fail "a thin i386 object's arch comes from its header: $mi"
echo "ok: embedded LLVM bitcode does not stop the reader, and a thin file's arch is its header's"

mkdir -p "$w/noprefix"
rc=0; ( unset NM OTOOL LIPO; SHIPYARD_MACHO_DIRS="$w/noprefix"; export SHIPYARD_MACHO_DIRS; PATH="$CL/bin:$PATH"; shipyard_mach_interface "$w/base.dylib" ) > /dev/null 2> "$w/err" || rc=$?
[ "$rc" -eq 2 ] || fail "no pinned llvm tools: exit $rc, want 2"
grep -q 'no pinned llvm-' "$w/err" || fail "no pinned llvm tools: stderr says so: $(cat "$w/err")"
rc=0; ( unset NM LIPO; OTOOL="$CL/bin/llvm-otool"; SHIPYARD_MACHO_DIRS="$w/noprefix"; export OTOOL SHIPYARD_MACHO_DIRS; shipyard_mach_interface "$w/base.dylib" ) > /dev/null 2> "$w/err" || rc=$?
[ "$rc" -eq 0 ] || fail "OTOOL alone finds llvm-nm, llvm-lipo and llvm-ar beside it: exit $rc: $(cat "$w/err")"
echo "ok: readers are the pinned clang22's, never PATH's"

mkdir -p "$w/sy/scripts/lib" "$w/sy/.mavergreen/ingredients/clang22"
cp "$BE" "$here/../scripts/deviations.sh" "$here/../scripts/mavergreen-meta.sh" "$w/sy/scripts/"
cp "$here/../scripts/lib/name-rules.sh" "$here/../scripts/lib/macho-tools.sh" "$here/../scripts/lib/mach-interface.sh" "$w/sy/scripts/lib/"
printf '#!/bin/sh\nprintf "%%s\\n" "$1" >> "%s/fetched"\nprintf "%%s\\n" "%s"\n' "$w" "$CL" > "$w/sy/scripts/fetch_clang22.sh"
rm -rf "$w/A" "$w/B"; mkdir -p "$w/A/lib" "$w/B/lib"; cp "$w/base.dylib" "$w/A/lib/x.dylib"; cp "$w/import.dylib" "$w/B/lib/x.dylib"
befetch() { rc=0; ( unset NM OTOOL LIPO; SHIPYARD_MACHO_DIRS="$w/noprefix"; export SHIPYARD_MACHO_DIRS; sh "$w/sy/scripts/build-equivalence.sh" --repo "$w" "$w/A" "$w/B" ) > "$w/out" 2> "$w/err" || rc=$?; out="$(cat "$w/out")"; err="$(cat "$w/err")"; }
befetch
[ "$rc" -eq 1 ] || fail "no reader installed: fetches the pinned clang22 beside the script: exit $rc, want 1 (err: $err)"
grep -qx "  only in B: x86_64 import _puts" "$w/out" || fail "fetched readers compare the interface: $out"
[ "$(cat "$w/fetched")" = "$w/sy/scripts/.." ] || fail "fetch_clang22.sh is given the pin beside the script: $(cat "$w/fetched")"
rm -f "$w/fetched"; rm -rf "$w/A/lib/x.dylib" "$w/B/lib/x.dylib"; printf 'a\n' > "$w/A/lib/t"; printf 'b\n' > "$w/B/lib/t"
befetch
[ "$rc" -eq 1 ] && [ ! -f "$w/fetched" ] || fail "no Mach-O to compare: nothing is fetched: exit $rc, fetched: $(cat "$w/fetched" 2>/dev/null)"
cp "$w/base.dylib" "$w/A/lib/x.dylib"; cp "$w/import.dylib" "$w/B/lib/x.dylib"
printf '#!/bin/sh\necho offline >&2\nexit 1\n' > "$w/sy/scripts/fetch_clang22.sh"
befetch
[ "$rc" -eq 2 ] || fail "a failed fetch: exit $rc, want 2 (err: $err)"
case "$err" in *offline*) ;; *) fail "a failed fetch shows fetch_clang22.sh's stderr: $err" ;; esac
rm -rf "$w/sy/.mavergreen"
befetch
[ "$rc" -eq 2 ] || fail "no reader and no pin beside the script: exit $rc, want 2 (err: $err)"
echo "ok: with no reader installed, the pinned clang22 beside the script is fetched"

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
  pair universal.dylib base.dylib; level "universal vs thin" interface; detail "universal vs thin" "only in A: arm64 minos build_version macos 11.0"
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
