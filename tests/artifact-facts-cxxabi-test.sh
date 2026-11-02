#!/bin/sh
# platform: macOS-only -- the fixtures are Mach-O, built with cc and merged with lipo
set -eu
unset GITHUB_REPOSITORY
here="$(cd "$(dirname "$0")" && pwd)"
AF="$here/../scripts/artifact-facts.sh"
S="$here/../scripts/check-artifact-conformance.sh"
w="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/af-cxxabi.XXXXXX")" && pwd)"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

S9="$(sh "$here/../scripts/fetch_sdk.sh")"
mkdir -p "$w/src/bin" "$w/src/lib" "$w/stubs" "$w/dist"
cd "$w"
build() { SDKROOT="$S9" cc -arch x86_64 -mmacosx-version-min=10.9 "$@"; }

printf 'void __cxa_throw(void) {}\nint main(void) { return 0; }\n' > throws.c
printf 'void __cxa_call_terminate(void) {}\nvoid __cxa_init_primary_exception(void) {}\nvoid __cxa_throw_bad_array_new_length(void) {}\nvoid __cxa_uncaught_exceptions(void) {}\nint main(void) { return 0; }\n' > backfills.c
printf 'void *_ZTVN10__cxxabiv119__pointer_type_infoE[4] = { 0 };\nint main(void) { return 0; }\n' > vtable.c
printf '__attribute__((visibility("hidden"))) void __cxa_throw(void) {}\nint main(void) { __cxa_throw(); return 0; }\n' > hidden.c
printf 'void __cxa_throw(void) {}\n' > throw-member.c
printf 'void __cxa_uncaught_exceptions(void) {}\n' > back-member.c
printf '__attribute__((visibility("hidden"))) void *_ZTVN10__cxxabiv119__pointer_type_infoE[4] = { 0 };\n' > hidden-member.c
printf '__attribute__((visibility("hidden"))) void __cxa_throw(void) {}\n__attribute__((visibility("hidden"))) void __gxx_personality_v0(void) {}\nint main(void) { __cxa_throw(); __gxx_personality_v0(); return 0; }\n' > codex.c
printf 'extern void *_ZTVN10__cxxabiv119__pointer_type_infoE[];\nint main(void) { return _ZTVN10__cxxabiv119__pointer_type_infoE[0] != 0; }\n' > withrecaulk.c
build throws.c -o src/bin/throws
build backfills.c -o src/bin/backfills
build vtable.c -o src/bin/vtable
build hidden.c -o src/bin/hidden
build codex.c -o src/bin/codex
pin="$(sed -n 1p "$here/../.mavergreen/ingredients/recaulk/VERSION")"
sh "$here/../scripts/fetch_product_pkg.sh" recaulk "$pin" "$w/recaulk" > /dev/null 2>&1 || fail "cannot fetch Recaulk $pin"
build withrecaulk.c "$w/recaulk/lib/librecaulk.a" -lc++abi -o src/bin/withrecaulk
build -c throw-member.c -o throw-member.o
build -c back-member.c -o back-member.o
ar rcs src/lib/libthrow.a throw-member.o 2>/dev/null
ar rcs src/lib/libback.a back-member.o 2>/dev/null
build -c hidden-member.c -o hidden-member.o
ar rcs src/lib/libhidden.a hidden-member.o 2>/dev/null

stub() {  # $1 = stub name, $2 = install name
  printf 'void %s(void) {}\n' "$1" > "stubs/$1.c"
  build -dynamiclib -install_name "$2" "stubs/$1.c" -o "stubs/$1.dylib"
}
stub sys /usr/lib/libc++abi.dylib
stub rpath1 @rpath/libc++abi.1.dylib
stub loader1 @loader_path/libc++abi.1.dylib
stub tree1 /usr/local/mavergreen/libcxx22/lib/libc++abi.1.dylib
stub rpath0 @rpath/libc++abi.dylib
stub vendor1 /opt/vendor/lib/libc++abi.1.dylib
stub rpath2 @rpath/libc++abi.2.dylib
printf 'void sys(void); void rpath1(void); void loader1(void); void tree1(void);\nint main(void) { sys(); rpath1(); loader1(); tree1(); return 0; }\n' > ok.c
build ok.c stubs/sys.dylib stubs/rpath1.dylib stubs/loader1.dylib stubs/tree1.dylib -o src/bin/okloads
printf 'void rpath0(void);\nint main(void) { rpath0(); return 0; }\n' > rpathbad.c
build rpathbad.c stubs/rpath0.dylib -o src/bin/rpathbad
printf 'void vendor1(void);\nint main(void) { vendor1(); return 0; }\n' > second.c
build second.c stubs/vendor1.dylib -o src/bin/second
printf 'void reex(void) {}\n' > reex.c
build -dynamiclib -install_name @rpath/libreex.dylib reex.c -Wl,-reexport_library,stubs/rpath2.dylib -o src/lib/reex.dylib

fatarch=""
printf '#ifndef __x86_64__\nvoid __cxa_throw(void) {}\n#endif\nint main(void) { return 0; }\n' > fat.c
build fat.c -o fat-x86_64
# platform: a modern Mac builds arm64 against the pinned 11.3 SDK; 10.9's toolchain builds i386 instead
if SDKROOT="$(sh "$here/../scripts/fetch_sdk.sh" --arch arm64)" cc -arch arm64 -mmacosx-version-min=11.0 fat.c -o fat-other 2>/dev/null; then
  fatarch=arm64
elif SDKROOT="$S9" cc -arch i386 -mmacosx-version-min=10.9 fat.c -o fat-other 2>/dev/null; then
  fatarch=i386
fi
[ -z "$fatarch" ] || lipo -create fat-x86_64 fat-other -output src/bin/fat

( cd src && tar -czf "$w/dist/t-1.0.0-mavericks.1.tgz" bin lib )

facts="$(sh "$AF" "$w/dist" 1.0.0-mavericks.1 "$w" 2>"$w/err")" || fail "artifact-facts failed: $(cat "$w/err")"
has() { printf '%s\n' "$facts" | grep -qxF "$1" || fail "$2 -- want '$1' in: $facts"; }
lacks() { printf '%s\n' "$facts" | grep -q "$1" && fail "$2 -- got: $(printf '%s\n' "$facts" | grep "$1")"; return 0; }
T=t-1.0.0-mavericks.1.tgz

has "cxxabi-defines $T bin/throws x86_64 ___cxa_throw visible" "a program defining ___cxa_throw fails"
lacks "^cxxabi-defines $T bin/backfills " "Recaulk's back-fills alone pass"
has "cxxabi-defines $T bin/vtable x86_64 __ZTVN10__cxxabiv119__pointer_type_infoE visible" "a program visibly defining a pointer-catch vtable fails: only libcxx22's runtime may, by declaration"
has "cxxabi-defines $T bin/hidden x86_64 ___cxa_throw hidden" "a hidden definition is a second runtime too"
has "cxxabi-defines $T bin/codex x86_64 ___cxa_throw hidden" "codex's shape fails: a whole runtime, hidden"
has "cxxabi-defines $T bin/codex x86_64 ___gxx_personality_v0 hidden" "codex's shape fails: a whole runtime, hidden"
lacks "^cxxabi-defines $T bin/withrecaulk " "a program linked with librecaulk.a (its pointer-catch vtables hidden) passes"
has "cxxabi-defines $T lib/libthrow.a x86_64 ___cxa_throw visible" "a shipped archive is judged by its members' definitions"
lacks "^cxxabi-defines $T lib/libback.a " "a shipped archive of back-fills passes on the allow-list alone"
lacks "^cxxabi-defines $T lib/libhidden.a " "an archive member's hidden pointer-catch vtable, as librecaulk.a's, passes"
lacks "^cxxabi-loads $T bin/okloads " "/usr/lib/libc++abi.dylib and libcxx22's runtime are allowed loads"
has "cxxabi-loads $T bin/rpathbad x86_64 @rpath/libc++abi.dylib" "an @rpath libc++abi other than libcxx22's fails"
has "cxxabi-loads $T bin/second x86_64 /opt/vendor/lib/libc++abi.1.dylib" "loading a second libc++abi fails"
has "cxxabi-loads $T lib/reex.dylib x86_64 @rpath/libc++abi.2.dylib" "a re-exported libc++abi is a load"
lacks "^cxxabi-loads $T lib/reex.dylib .*libreex" "a dylib's own install name is not a load"
if [ -n "$fatarch" ]; then
  has "cxxabi-defines $T bin/fat $fatarch ___cxa_throw visible" "a definition in one slice of a fat binary fails"
  lacks "^cxxabi-defines $T bin/fat x86_64 " "each slice is judged on its own"
else
  echo "artifact-facts-cxxabi: skip: no second arch to build a fat fixture with"
fi
has end-of-facts "a run that read every Mach-O ends its stream"
out="$(printf '%s\n' "$facts" | sh "$S" 2>&1)" && fail "a release carrying these fails conformance: $out"
printf '%s\n' "$out" | grep -q '^conformance: cxxabi: ' || fail "the failure is cxxabi's: $out"

printf 'void x(void) {}\n' > plain.c
mkdir -p plain/bin plain-dist
build plain.c -dynamiclib -o plain/bin/plain.dylib
( cd plain && tar -czf "$w/plain-dist/p.tgz" bin )
nofacts="$(NM=/nonexistent/nm sh "$AF" "$w/plain-dist" 1.0.0-mavericks.1 "$w" 2>/dev/null)" \
  && fail "a Mach-O with no NM to read it must abort: $nofacts"
printf '%s\n' "$nofacts" | grep -q '^abort .*NM.*/nonexistent/nm' || fail "the abort record names NM: $nofacts"
printf '%s\n' "$nofacts" | grep -qx end-of-facts && fail "an aborted stream carries no end-of-facts"

mkdir -p fakebin
printf '#!/bin/sh\ncase "$*" in *plain.dylib*) echo "nm: broke" >&2; exit 1 ;; esac\nexec nm "$@"\n' > fakebin/nm
chmod +x fakebin/nm
nofacts="$(NM="$w/fakebin/nm" sh "$AF" "$w/plain-dist" 1.0.0-mavericks.1 "$w" 2>/dev/null)" \
  && fail "an NM that fails on a shipped Mach-O must abort: $nofacts"
printf '%s\n' "$nofacts" | grep -q '^abort .*plain.dylib' || fail "the abort record names the file NM could not read: $nofacts"

nomachinery="$(MAVERGREEN_RELEASES="file://$w/no-releases" MAVERGREEN_PKG_CACHE="$w/no-cache" sh "$AF" "$w/plain-dist" 1.0.0-mavericks.1 "$w" 2>&1)" \
  || fail "a Mach-O with no C++ runtime machinery never fetches Recaulk (the fixture release URL fails if touched): $nomachinery"
printf '%s\n' "$nomachinery" | grep -qx end-of-facts || fail "a Mach-O with no machinery ends its stream: $nomachinery"
mkdir -p throws-dist
( cd src && tar -czf "$w/throws-dist/t.tgz" bin/throws )
nofacts="$(MAVERGREEN_RELEASES="file://$w/no-releases" MAVERGREEN_PKG_CACHE="$w/no-cache" sh "$AF" "$w/throws-dist" 1.0.0-mavericks.1 "$w" 2>/dev/null)" \
  && fail "no allow-list, no facts: $nofacts"
printf '%s\n' "$nofacts" | grep -q '^abort cxxabi allow-list unavailable: ' || fail "a failed Recaulk fetch aborts naming the allow-list: $nofacts"
printf '%s\n' "$nofacts" | sh "$S" >/dev/null 2>&1 && fail "an aborted stream never passes conformance"

mkdir -p txt-src txt-dist; echo x > txt-src/f
( cd txt-src && tar -czf "$w/txt-dist/x.tgz" f )
txtfacts="$(NM=/nonexistent/nm MAVERGREEN_RELEASES="file://$w/no-releases" MAVERGREEN_PKG_CACHE="$w/no-cache" sh "$AF" "$w/txt-dist" 1.0.0-mavericks.1 "$w" 2>&1)" \
  || fail "a release with no Mach-O needs neither NM nor the allow-list: $txtfacts"

echo "PASS: artifact-facts-cxxabi"
