#!/bin/sh
# platform: macOS-only -- compiles Objective-C against the pinned 10.9 SDK with clang22
# usage: sh tests/sdk-metadata-consumer-test.sh
#        mavericks_target_sdk_metadata on a real SDK: only the opted-in Objective-C target gets the
#        overlay; generic NSArray code compiles with it and fails without it; a reconfigure reuses
#        the verified generation; a tampered or unowned generation is refused, never overwritten.
#        SDK_METADATA_CC names the compiler (default: the installed clang22, clang-22 on 10.9 or
#        clang-22-cross on a modern Mac). Without it the test
#        skips, unless SHIPYARD_ON_TARGET=1 (tests/maintainer-tests), which makes a missing compiler
#        or SDK a failure.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
fx="$here/fixtures/sdk-metadata-consumer"
recipes="$here/fixtures/sdk-metadata/recipes-v1.json"
SC="${CMAKE:-$(command -v shipyard-cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)}"
CC="${SDK_METADATA_CC:-}"
if [ -z "$CC" ]; then
  for c in /usr/local/mavergreen/bin/clang-22 /usr/local/mavergreen/bin/clang-22-cross; do
    [ -x "$c" ] && { CC="$c"; break; }
  done
  CC="${CC:-/usr/local/mavergreen/bin/clang-22 or clang-22-cross}"
fi
unmet() {
  if [ "${SHIPYARD_ON_TARGET:-}" = 1 ]; then echo "FAIL: $*"; exit 1; fi
  echo "SKIP: $*"; exit 77
}
[ -x "$SC" ] || unmet "no shipyard-cmake"
[ -x "$CC" ] || unmet "no compiler at $CC (set SDK_METADATA_CC)"
SDK="$(sh "$root/scripts/fetch_sdk.sh")" || unmet "the pinned 10.9 SDK could not be fetched"
NSARRAY="$SDK/System/Library/Frameworks/Foundation.framework/Versions/C/Headers/NSArray.h"
sdk_before="$("$SC" -E sha256sum "$NSARRAY" | awk '{print $1}')"

_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/sdk metadata consumer.XXXXXX")"
trap 'rm -rf "$w"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

configure() {
  "$SC" -S "$fx" -B "$1" -DMODULE_DIR="$root" -DRECIPES="$recipes" -DGENERATION_ROOT="$2" \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_OBJC_COMPILER="$CC" -DCMAKE_OSX_SYSROOT="$SDK" \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=10.9 \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON > "$w/configure.log" 2>&1
}
cmd() { "$SC" -DDB="$1/compile_commands.json" -DSOURCE="$2" -P "$fx/command.cmake"; }
overlay_of() { printf '%s\n' "$1" | sed -n 's/.*-ivfsoverlay "\{0,1\}\([^"]*overlay\.json\).*/\1/p'; }
gen_dir() { dirname "$1"; }

echo "== opted_objc, plain_objc, plain_c"
if ! configure "$w/b1" "$w/gen root"; then
  cat "$w/configure.log"; echo "FAIL: configure"; exit 1
fi
"$SC" --build "$w/b1" > "$w/build.log" 2>&1 || { cat "$w/build.log"; bad "the fixture targets did not build"; }
opted="$(cmd "$w/b1" opted.m)"
n="$(printf '%s\n' "$opted" | grep -o -- '-ivfsoverlay' | wc -l | tr -d ' ')"
[ "$n" = 1 ] || bad "opted_objc's compile carries $n -ivfsoverlay, want 1: $opted"
case "$opted" in *"-isysroot $SDK"*) ;; *) bad "opted_objc's compile does not keep the original sysroot: $opted" ;; esac
for s in plain.m plain.c; do
  case "$(cmd "$w/b1" "$s")" in *-ivfsoverlay*) bad "$s got the overlay without opting in" ;; esac
done
ov="$(overlay_of "$opted")"
case "$ov" in "$w/gen root"/*) ;; *) echo "FAIL: the overlay '$ov' is not under the generation root"; exit 1 ;; esac
[ -f "$ov" ] || { echo "FAIL: no overlay at '$ov' from: $opted"; exit 1; }

echo "== real SDK compile cases"
I='#import'
generic='NSArray<NSString *> *a; NSMutableArray<NSNumber *> *m; void f(void) { m = [NSMutableArray array]; [m addObject:@1]; a = @[@"x"]; }'
try() {
  name="$1" want="$2"; shift 2
  : > "$w/probe.m"
  while [ "$1" != -- ]; do printf '%s\n' "$1" >> "$w/probe.m"; shift; done
  shift
  if "$CC" --no-default-config -fsyntax-only -fobjc-arc -arch x86_64 -mmacosx-version-min=10.9 \
    -isysroot "$SDK" "$@" "$w/probe.m" > "$w/probe.log" 2>&1; then got=pass; else got=fail; fi
  [ "$got" = "$want" ] || { bad "$name: compile ${got}ed, want ${want}"; sed 's/^/    | /' "$w/probe.log" | head -8; }
}
try unadapted_generics fail "$I <Foundation/Foundation.h>" "$generic" --
try adapted_generics pass "$I <Foundation/Foundation.h>" "$generic" -- -ivfsoverlay "$ov"
try appkit_first pass "$I <AppKit/AppKit.h>" "$I <Foundation/Foundation.h>" "$generic" -- -ivfsoverlay "$ov"
try direct_header pass "$I <Foundation/NSArray.h>" "$I <Foundation/NSString.h>" "$I <Foundation/NSValue.h>" \
  "$generic" -- -ivfsoverlay "$ov"
try canonical_header pass "$I <Foundation/NSObject.h>" "$I \"$NSARRAY\"" 'NSArray<id> *c;' -- -ivfsoverlay "$ov"
try nongeneric pass "$I <Foundation/Foundation.h>" 'NSArray *a; void f(void) { a = [NSArray arrayWithObject:@"x"]; }' \
  -- -ivfsoverlay "$ov"
printf '%s\n' '@class NSArray<__covariant ObjectType>;' '@class NSMutableArray<ObjectType>;' > "$w/prefix.h"
try prefix_only_still_fails fail "$I <Foundation/Foundation.h>" "$generic" -- -include "$w/prefix.h"

echo "== reconfigure_same_inputs"
configure "$w/b1" "$w/gen root" || { cat "$w/configure.log"; bad "reconfigure with the same inputs failed"; }
again="$(cmd "$w/b1" opted.m)"
[ "$again" = "$opted" ] || bad "a reconfigure changed opted_objc's compile: $again"
[ "$("$SC" -E sha256sum "$NSARRAY" | awk '{print $1}')" = "$sdk_before" ] || bad "the SDK's NSArray.h changed"
configure "$w/b2" "$w/gen root 2" || { cat "$w/configure.log"; bad "a second generation root failed"; }
ov2="$(overlay_of "$(cmd "$w/b2" opted.m)")"
case "$ov2" in "$w/gen root 2"/*) ;; *) echo "FAIL: the second overlay '$ov2' is not under its generation root"; exit 1 ;; esac
h1="$(find "$(gen_dir "$ov")" -name NSArray.h)"; h2="$(find "$(gen_dir "$ov2")" -name NSArray.h)"
[ -f "$h1" ] && [ -f "$h2" ] || { echo "FAIL: a generation holds no NSArray.h: '$h1' '$h2'"; exit 1; }
cmp -s "$h1" "$h2" || bad "two generations of the same inputs hold different headers"

echo "== tampered_cached_header_refused"
printf '/* tampered */\n' >> "$h1"
if configure "$w/b1" "$w/gen root"; then bad "a tampered generation was accepted"; fi
grep -q 'mavericks_target_sdk_metadata' "$w/configure.log" || bad "tampered: refused without naming the function"
tail -1 "$h1" | grep -q tampered || bad "tampered: the generation was overwritten instead of refused"

echo "== unowned_generation_refused"
g2="$(gen_dir "$ov2")"
rm -f "$g2/.mavericks-sdk-metadata-stamp.json"
if configure "$w/b2" "$w/gen root 2"; then bad "an unowned generation was accepted"; fi
grep -q 'mavericks_target_sdk_metadata' "$w/configure.log" || bad "unowned: refused without naming the function"
[ -f "$g2/overlay.json" ] || bad "unowned: the generation was removed or replaced"

[ "$("$SC" -E sha256sum "$NSARRAY" | awk '{print $1}')" = "$sdk_before" ] || bad "the SDK's NSArray.h changed"
[ "$fail" -eq 0 ] && echo "sdk-metadata-consumer-test: OK"
exit "$fail"
