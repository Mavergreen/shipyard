#!/bin/sh
# platform: host-agnostic
set -eu
unset GITHUB_REPOSITORY
here="$(cd "$(dirname "$0")" && pwd)"
AF="$here/../scripts/artifact-facts.sh"
S="$here/../scripts/check-artifact-conformance.sh"
w="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/af-cxxabi.XXXXXX")" && pwd)"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

S9="$(sh "$here/../scripts/fetch_sdk.sh")"
CL="$(sh "$here/../scripts/fetch_clang22.sh" "$here/..")"
LIPO="$CL/bin/llvm-lipo"; OTOOL="$CL/bin/llvm-otool"; NM="$CL/bin/llvm-nm"; AR="$CL/bin/llvm-ar"
export LIPO OTOOL NM
mkdir -p "$w/src/bin" "$w/src/lib" "$w/stubs" "$w/dist"
cd "$w"
build() { "$CL/bin/clang" --no-default-config -Wno-unused-command-line-argument -fuse-ld=lld --ld-path="$CL/bin/ld64.lld" -target x86_64-apple-macos10.9 -isysroot "$S9" "$@"; }

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
sh "$here/../scripts/fetch_product_pkg.sh" --repo "$(sed -n 1p "$here/../.mavergreen/ingredients/recaulk/REPO")" recaulk "$pin" "$w/recaulk" > /dev/null 2>&1 || fail "cannot fetch Recaulk $pin"
build withrecaulk.c "$w/recaulk/lib/librecaulk.a" -lc++abi -o src/bin/withrecaulk
build -c throw-member.c -o throw-member.o
build -c back-member.c -o back-member.o
"$AR" rcs src/lib/libthrow.a throw-member.o
"$AR" rcs src/lib/libback.a back-member.o
build -c hidden-member.c -o hidden-member.o
"$AR" rcs src/lib/libhidden.a hidden-member.o

stub() {  # $1 = stub name, $2 = install name
  printf 'void %s(void) {}\n' "$1" > "stubs/$1.c"
  build -dynamiclib -install_name "$2" "stubs/$1.c" -o "stubs/$1.dylib"
}
stub sys /usr/lib/libc++abi.dylib
stub rpath1 @rpath/libc++abi.1.dylib
stub loader1 @loader_path/libc++abi.1.dylib
stub tree1 /opt/mavergreen/libcxx22/lib/libc++abi.1.dylib
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
stub other1 /opt/mavergreen/other/lib/libc++abi.1.dylib
printf 'void other1(void);\nint main(void) { other1(); return 0; }\n' > other.c
build other.c stubs/other1.dylib -o src/bin/other

printf 'extern "C" int puts(const char *);\nint main(void) { int *p = new int(1); try { throw *p; } catch (int) { puts("c"); } delete p; return 0; }\n' > ex.cc
printf '#define H __attribute__((visibility("hidden")))\nH void *__cxa_allocate_exception(unsigned long n) { return 0; }\nH void __cxa_throw(void) {}\nH void *__cxa_begin_catch(void *p) { return p; }\nH void __cxa_end_catch(void) {}\nH int __gxx_personality_v0(void) { return 0; }\nH void *_ZTIi[2] = {0};\n' > rt.c
build -x c++ -c ex.cc -o ex.o
build -c rt.c -o rt.o
build ex.o rt.o -lc++ -o src/bin/stripx
cp src/bin/stripx src/bin/stripS
"$CL/bin/llvm-strip" -x src/bin/stripx
"$CL/bin/llvm-strip" -S src/bin/stripS
build ex.o -lc++abi -lc++ -o src/bin/importsx
"$CL/bin/llvm-strip" -x src/bin/importsx
"$AR" rcs src/lib/libex.a ex.o rt.o
printf 'int main(void) { @try { @throw (id)0; } @catch (id e) { return 1; } return 0; }\n' > trycatch.m
build -x objective-c -fobjc-exceptions trycatch.m -lobjc -o src/bin/objctry
printf 'void done(int *p);\nvoid work(void);\nint main(void) { int x __attribute__((cleanup(done))) = 0; work(); return x; }\nvoid done(int *p) { (void)p; }\nvoid work(void) {}\n' > cleanup.c
build -fexceptions cleanup.c -o src/bin/ccleanup

printf '#ifndef __x86_64__\nvoid __cxa_throw(void) {}\n#endif\nint main(void) { return 0; }\n' > fat.c
build fat.c -o fat-x86_64
# platform: the second slice is an i386 object, the one every host's clang22 builds (10.9's native
#           clang22 targets x86_64 only and links no i386).
build -target i386-apple-macos10.9 -c fat.c -o fat-other
"$LIPO" -create fat-x86_64 fat-other -output src/bin/fat

( cd src && tar -czf "$w/dist/t-1.0.0-mavergreen.1.tgz" bin lib )

facts="$(sh "$AF" "$w/dist" 1.0.0-mavergreen.1 "$w" 2>"$w/err")" || fail "artifact-facts failed: $(cat "$w/err")"
has() { printf '%s\n' "$facts" | grep -qxF "$1" || fail "$2 -- want '$1' in: $facts"; }
lacks() { printf '%s\n' "$facts" | grep -q "$1" && fail "$2 -- got: $(printf '%s\n' "$facts" | grep "$1")"; return 0; }
T=t-1.0.0-mavergreen.1.tgz

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
has "cxxabi-defines $T bin/fat i386 ___cxa_throw visible" "a definition in one slice of a fat binary fails"
lacks "^cxxabi-defines $T bin/fat x86_64 " "each slice is judged on its own"
has "cxxabi-unjudgeable $T bin/stripx x86_64" "a C++ image stripped -x of its hidden personality routine cannot be judged"
lacks "^cxxabi-unjudgeable $T bin/stripS " "a C++ image stripped -S keeps its local symbols and is judged"
has "cxxabi-defines $T bin/stripS x86_64 ___gxx_personality_v0 hidden" "stripping -S leaves the hidden runtime to be seen"
lacks "^cxxabi-unjudgeable $T bin/importsx " "an image importing ___gxx_personality_v0 names it, stripped or not"
lacks "^cxxabi-defines $T bin/importsx " "an image importing the runtime defines none of it"
lacks "^cxxabi-unjudgeable $T bin/objctry " "an ObjC @try image has exception tables but no C++ personality, so it is no C++ ABI consumer"
lacks "^cxxabi-unjudgeable $T bin/ccleanup " "a C -fexceptions cleanup image is no C++ ABI consumer"
lacks "^cxxabi-unjudgeable $T lib/" "objects in archives are not linked images, so their exception tables are not judged"
has "cxxabi-loads $T bin/other x86_64 /opt/mavergreen/other/lib/libc++abi.1.dylib" "a family libc++abi other than libcxx22's fails"
has end-of-facts "a run that read every Mach-O ends its stream"
out="$(printf '%s\n' "$facts" | sh "$S" 2>&1)" && fail "a release carrying these fails conformance: $out"
printf '%s\n' "$out" | grep -q '^conformance: cxxabi: ' || fail "the failure is cxxabi's: $out"
printf '%s\n' "$out" | grep -qF 'bin/stripx (x86_64) has C++ exception tables but names no personality routine, so its C++ runtime cannot be judged; strip it with -S, never -x' \
  || fail "the unjudgeable image is named: $out"
printf '%s\n' "$out" | grep -q 'bin/stripS (x86_64) has C++ exception' && fail "a -S image is judged, not unjudgeable: $out"

printf 'void x(void) {}\n' > plain.c
mkdir -p plain/bin plain-dist
build plain.c -dynamiclib -o plain/bin/plain.dylib
( cd plain && tar -czf "$w/plain-dist/p.tgz" bin )
nofacts="$(NM=/nonexistent/nm sh "$AF" "$w/plain-dist" 1.0.0-mavergreen.1 "$w" 2>/dev/null)" \
  && fail "a Mach-O with no NM to read it must abort: $nofacts"
printf '%s\n' "$nofacts" | grep -q '^abort .*NM.*/nonexistent/nm' || fail "the abort record names NM: $nofacts"
printf '%s\n' "$nofacts" | grep -qx end-of-facts && fail "an aborted stream carries no end-of-facts"

mkdir -p fakebin
printf '#!/bin/sh\ncase "$*" in *plain.dylib*) echo "nm: broke" >&2; exit 1 ;; esac\nexec nm "$@"\n' > fakebin/nm
chmod +x fakebin/nm
nofacts="$(NM="$w/fakebin/nm" sh "$AF" "$w/plain-dist" 1.0.0-mavergreen.1 "$w" 2>/dev/null)" \
  && fail "an NM that fails on a shipped Mach-O must abort: $nofacts"
printf '%s\n' "$nofacts" | grep -q '^abort .*plain.dylib' || fail "the abort record names the file NM could not read: $nofacts"

nomachinery="$(MAVERGREEN_ROOT="$w/no-prefix" MAVERGREEN_RELEASES="file://$w/no-releases" MAVERGREEN_PKG_CACHE="$w/no-cache" sh "$AF" "$w/plain-dist" 1.0.0-mavergreen.1 "$w" 2>&1)" \
  || fail "a Mach-O with no C++ runtime machinery never fetches Recaulk (the fixture release URL fails if touched): $nomachinery"
printf '%s\n' "$nomachinery" | grep -qx end-of-facts || fail "a Mach-O with no machinery ends its stream: $nomachinery"
mkdir -p throws-dist
( cd src && tar -czf "$w/throws-dist/t.tgz" bin/throws )
nofacts="$(MAVERGREEN_ROOT="$w/no-prefix" MAVERGREEN_RELEASES="file://$w/no-releases" MAVERGREEN_PKG_CACHE="$w/no-cache" sh "$AF" "$w/throws-dist" 1.0.0-mavergreen.1 "$w" 2>/dev/null)" \
  && fail "no allow-list, no facts: $nofacts"
printf '%s\n' "$nofacts" | grep -q '^abort cxxabi allow-list unavailable: ' || fail "a failed Recaulk fetch aborts naming the allow-list: $nofacts"
printf '%s\n' "$nofacts" | sh "$S" >/dev/null 2>&1 && fail "an aborted stream never passes conformance"

mkdir -p txt-src txt-dist; echo x > txt-src/f
( cd txt-src && tar -czf "$w/txt-dist/x.tgz" f )
txtfacts="$(NM=/nonexistent/nm MAVERGREEN_ROOT="$w/no-prefix" MAVERGREEN_RELEASES="file://$w/no-releases" MAVERGREEN_PKG_CACHE="$w/no-cache" sh "$AF" "$w/txt-dist" 1.0.0-mavergreen.1 "$w" 2>&1)" \
  || fail "a release with no Mach-O needs neither NM nor the allow-list: $txtfacts"

echo "PASS: artifact-facts-cxxabi"
