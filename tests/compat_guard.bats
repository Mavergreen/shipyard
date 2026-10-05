#!/usr/bin/env bats
# platform: macOS-only -- every case needs Apple clang, and all of them skip without it
# Unit tests for scripts/assert_binary_compatible.sh. Builds tiny x86_64/10.9 fixture Mach-Os
# with controlled symbols. If the host clang cannot emit an x86_64/10.9 slice, the
# arch/min-OS-dependent cases skip, but the symbol logic still runs.

setup() {
  GUARD="$BATS_TEST_DIRNAME/../scripts/assert_binary_compatible.sh"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/compat_guard_test.XXXXXX")"
  CC=$(command -v clang || command -v cc)
  # platform: no vtool (pre-Xcode 11, e.g. the 10.9 box) to restamp fixtures, and that box's
  #           default SDK may be 10.10 (Xcode 6.1+; MavericksToolchain.cmake pins native mode for
  #           the same reason) -- so build them against the pinned 10.9 SDK instead; clang honours
  #           SDKROOT.
  if ! xcrun --find vtool >/dev/null 2>&1; then
    SDKROOT="$(sh "$BATS_TEST_DIRNAME/../scripts/fetch_sdk.sh")" && export SDKROOT
  fi
  printf 'int main(void){return 0;}\n' > "$WORK/clean.c"
  if ! "$CC" -arch x86_64 -mmacosx-version-min=10.9 "$WORK/clean.c" -o "$WORK/clean" 2>/dev/null; then
    HAVE_X8609=0
  else
    HAVE_X8609=1
  fi
  printf 'int mav_test_shim(void){return 0;}\nint main(void){return mav_test_shim();}\n' > "$WORK/shim.c"
  "$CC" -arch x86_64 -mmacosx-version-min=10.9 "$WORK/shim.c" -o "$WORK/shim" 2>/dev/null || true
  printf 'extern int mav_test_post109(void);\nint main(void){return mav_test_post109();}\n' > "$WORK/leak.c"
  "$CC" -arch x86_64 -mmacosx-version-min=10.9 -Wl,-undefined,dynamic_lookup "$WORK/leak.c" -o "$WORK/leak" 2>/dev/null || true
  # ObjC fixtures: a post-10.9 selector (labelColor, 10.10+) vs a 10.9-safe one (blackColor). These
  # dispatch via objc_msgSend, so nm can't see them -- the selector scan must catch labelColor.
  printf '#import <AppKit/AppKit.h>\nint main(void){(void)[NSColor labelColor];return 0;}\n' > "$WORK/sel_bad.m"
  "$CC" -arch x86_64 -mmacosx-version-min=10.9 -framework AppKit "$WORK/sel_bad.m" -o "$WORK/sel_bad" 2>/dev/null || true
  printf '#import <AppKit/AppKit.h>\nint main(void){(void)[NSColor blackColor];return 0;}\n' > "$WORK/sel_ok.m"
  "$CC" -arch x86_64 -mmacosx-version-min=10.9 -framework AppKit "$WORK/sel_ok.m" -o "$WORK/sel_ok" 2>/dev/null || true
  # platform: vtool rewrites the recorded SDK without needing that SDK; it cannot write in place.
  # platform: on the 10.9 box there is no vtool -- SDKROOT above already pinned the build to 10.9,
  #           so no restamping is needed there either.
  if xcrun --find vtool >/dev/null 2>&1; then
    for fx in clean shim leak sel_bad sel_ok; do
      [ -f "$WORK/$fx" ] || continue
      xcrun vtool -set-version-min macos 10.9 10.9 -replace -output "$WORK/$fx.stamped" "$WORK/$fx" \
        && mv "$WORK/$fx.stamped" "$WORK/$fx"
    done
  fi
}
teardown() { rm -rf "$WORK"; }

@test "clean binary passes" {
  [ "$HAVE_X8609" = 1 ] || skip "host cannot emit x86_64/10.9"
  run sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 0 ]
}

@test "post-10.9 undefined import is caught via MAVERICKS_POST_10_9_SYMBOLS" {
  [ -f "$WORK/leak" ] || skip "leak fixture did not build"
  run env MAVERICKS_POST_10_9_SYMBOLS='_mav_test_post109' sh "$GUARD" "$WORK/leak"
  [ "$status" -ne 0 ]
  [[ "$output" == *_mav_test_post109* ]] || false
}

@test "MAVERICKS_REQUIRE_DEFINED_SYMBOLS passes when the symbol is defined" {
  [ -f "$WORK/shim" ] || skip "shim fixture did not build"
  run env MAVERICKS_REQUIRE_DEFINED_SYMBOLS='_mav_test_shim' sh "$GUARD" "$WORK/shim"
  [ "$status" -eq 0 ]
}

@test "MAVERICKS_REQUIRE_DEFINED_SYMBOLS fails when the symbol is absent" {
  [ "$HAVE_X8609" = 1 ] || skip "host cannot emit x86_64/10.9"
  run env MAVERICKS_REQUIRE_DEFINED_SYMBOLS='_mav_test_shim' sh "$GUARD" "$WORK/clean"
  [ "$status" -ne 0 ]
}

@test "post-10.9 ObjC selector (labelColor) is caught -- nm can't see it" {
  [ -f "$WORK/sel_bad" ] || skip "sel_bad fixture did not build (no AppKit?)"
  run sh "$GUARD" "$WORK/sel_bad"
  [ "$status" -ne 0 ]
  [[ "$output" == *labelColor* ]] || false
}

@test "a 10.9-safe selector (blackColor) passes the selector scan" {
  [ -f "$WORK/sel_ok" ] || skip "sel_ok fixture did not build"
  run sh "$GUARD" "$WORK/sel_ok"
  [ "$status" -eq 0 ]
}

@test "MAVERICKS_ALLOW_SELECTORS allowlists a respondsToSelector-guarded selector" {
  [ -f "$WORK/sel_bad" ] || skip "sel_bad fixture did not build"
  run env MAVERICKS_ALLOW_SELECTORS=labelColor sh "$GUARD" "$WORK/sel_bad"
  [ "$status" -eq 0 ]
}

mk_stamped() {  # $1 out, $2 arch, $3 minos, $4 sdk
  # platform: vtool arrived with Xcode 11; the 10.9 box (Xcode 6) runs this suite too and has none.
  xcrun --find vtool >/dev/null 2>&1 || skip "no vtool (pre-Xcode 11) to stamp fixtures"
  printf 'int main(void){return 0;}\n' > "$WORK/s.c"
  "$CC" -arch "$2" -mmacosx-version-min="$3" "$WORK/s.c" -o "$WORK/s.$2"
  case "$2" in
    x86_64) xcrun vtool -set-version-min macos "$3" "$4" -replace -output "$1" "$WORK/s.$2" ;;
    *)      xcrun vtool -set-build-version macos "$3" "$4" -tool ld 1000.0 -replace -output "$1" "$WORK/s.$2" ;;
  esac
}

@test "x86_64 recording the runner's SDK fails -- the audit's blind spot" {
  mk_stamped "$WORK/r265" x86_64 10.9 26.5
  run sh "$GUARD" "$WORK/r265"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sdk 26.5"* ]] || false
}

@test "x86_64 recording the pinned 10.9 SDK passes" {
  mk_stamped "$WORK/p109" x86_64 10.9 10.9
  run sh "$GUARD" "$WORK/p109"
  [ "$status" -eq 0 ]
}

@test "an arch named twice in MAVERICKS_ALLOW_ARCHS is still the same arch set" {
  mk_stamped "$WORK/p109" x86_64 10.9 10.9
  run env MAVERICKS_ALLOW_ARCHS="x86_64 x86_64" sh "$GUARD" "$WORK/p109"
  [ "$status" -eq 0 ]
}

@test "an arm64 slice needs MAVERICKS_ALLOW_ARCHS, and then the 11.3 pin" {
  mk_stamped "$WORK/a113" arm64 11.0 11.3
  run sh "$GUARD" "$WORK/a113"
  [ "$status" -ne 0 ]
  run env MAVERICKS_ALLOW_ARCHS=arm64 sh "$GUARD" "$WORK/a113"
  [ "$status" -eq 0 ]
  mk_stamped "$WORK/a265" arm64 11.0 26.5
  run env MAVERICKS_ALLOW_ARCHS=arm64 sh "$GUARD" "$WORK/a265"
  [ "$status" -ne 0 ]
}

@test "a universal binary with one bad slice fails and names that slice" {
  mk_stamped "$WORK/p109" x86_64 10.9 10.9
  mk_stamped "$WORK/a265" arm64 11.0 26.5
  lipo -create "$WORK/p109" "$WORK/a265" -output "$WORK/fatbad"
  run env MAVERICKS_ALLOW_ARCHS="x86_64 arm64" sh "$GUARD" "$WORK/fatbad"
  [ "$status" -ne 0 ]
  [[ "$output" == *"arm64 records minos 11.0 sdk 26.5"* ]] || false
  mk_stamped "$WORK/a113" arm64 11.0 11.3
  lipo -create "$WORK/p109" "$WORK/a113" -output "$WORK/fatok"
  run env MAVERICKS_ALLOW_ARCHS="arm64 x86_64" sh "$GUARD" "$WORK/fatok"
  [ "$status" -eq 0 ]
}

@test "post-10.9 imports are still caught in a fat binary's x86_64 slice" {
  [ -f "$WORK/leak" ] || skip "leak fixture did not build"
  xcrun --find vtool >/dev/null 2>&1 || skip "no vtool (pre-Xcode 11) to stamp fixtures"
  xcrun vtool -set-version-min macos 10.9 10.9 -replace -output "$WORK/leak109" "$WORK/leak"
  mk_stamped "$WORK/a113" arm64 11.0 11.3
  lipo -create "$WORK/leak109" "$WORK/a113" -output "$WORK/fatleak"
  run env MAVERICKS_ALLOW_ARCHS="x86_64 arm64" MAVERICKS_POST_10_9_SYMBOLS='_mav_test_post109' sh "$GUARD" "$WORK/fatleak"
  [ "$status" -ne 0 ]
  [[ "$output" == *_mav_test_post109* ]] || false
}

@test "a pinned third-party binary passes on its content, and only on its exact bytes" {
  fw="$(sh "$BATS_TEST_DIRNAME/../scripts/fetch_sparkle_framework.sh")" || skip "no network to fetch Sparkle"
  run sh "$GUARD" "$fw/Versions/A/Resources/Autoupdate.app/Contents/MacOS/fileop"
  [ "$status" -eq 0 ]
  cp "$fw/Versions/A/Resources/Autoupdate.app/Contents/MacOS/fileop" "$WORK/fileop"; printf 'x' >> "$WORK/fileop"
  run sh "$GUARD" "$WORK/fileop"
  [ "$status" -ne 0 ]
}

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the guard
#       honours the same declared sdk-pin:<glob> exemptions as the package-time rule, read from
#       $MAVERICKS_DEVIATIONS_ROOT/INGREDIENTS.md, and they excuse the minos/sdk rule only.
declare_deviation() { printf '## Conformance deviations\n%s\n' "$1" > "$WORK/INGREDIENTS.md"; }

@test "a matching sdk-pin glob excuses the SDK rule, and says so" {
  mk_stamped "$WORK/r265" x86_64 10.9 26.5
  declare_deviation '- sdk-pin:*/r265: prebuilt upstream, shipped verbatim'
  run env MAVERICKS_DEVIATIONS_ROOT="$WORK" sh "$GUARD" "$WORK/r265"
  [ "$status" -eq 0 ]
  [[ "$output" == *"compat guard: $WORK/r265 is excused from sdk-pin: prebuilt upstream, shipped verbatim"* ]] || false
}

@test "a non-matching sdk-pin glob excuses nothing" {
  mk_stamped "$WORK/r265" x86_64 10.9 26.5
  declare_deviation '- sdk-pin:*/other: prebuilt upstream'
  run env MAVERICKS_DEVIATIONS_ROOT="$WORK" sh "$GUARD" "$WORK/r265"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sdk 26.5"* ]] || false
}

@test "an sdk-pin glob with no reason fails the guard closed" {
  mk_stamped "$WORK/r265" x86_64 10.9 26.5
  declare_deviation '- sdk-pin:*/r265:'
  run env MAVERICKS_DEVIATIONS_ROOT="$WORK" sh "$GUARD" "$WORK/r265"
  [ "$status" -ne 0 ]
  [[ "$output" != *"is excused"* ]] || false
}

@test "an sdk-pin excuse does not excuse an arch outside MAVERICKS_ALLOW_ARCHS" {
  mk_stamped "$WORK/a265" arm64 11.0 26.5
  declare_deviation '- sdk-pin:*/a265: prebuilt upstream'
  run env MAVERICKS_DEVIATIONS_ROOT="$WORK" sh "$GUARD" "$WORK/a265"
  [ "$status" -ne 0 ]
  [[ "$output" == *"arches 'arm64' != 'x86_64'"* ]] || false
  run env MAVERICKS_DEVIATIONS_ROOT="$WORK" MAVERICKS_ALLOW_ARCHS=arm64 sh "$GUARD" "$WORK/a265"
  [ "$status" -eq 0 ]
}

# A recording reader for each knob: logs its name, then runs the host's own tool.
mk_readers() {
  mkdir -p "$WORK/readers"
  for t in lipo nm otool strings; do
    printf '#!/bin/sh\necho %s >> "%s/readers.log"\nexec "%s" "$@"\n' "$t" "$WORK" "$(command -v "$t")" > "$WORK/readers/$t"
    chmod +x "$WORK/readers/$t"
  done
}

@test "LIPO, NM, STRINGS and OTOOL name the readers the guard runs" {
  [ "$HAVE_X8609" = 1 ] || skip "host cannot emit x86_64/10.9"
  mk_readers
  R="$WORK/readers"
  run env LIPO="$R/lipo" NM="$R/nm" STRINGS="$R/strings" OTOOL="$R/otool" sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 0 ]
  for t in lipo nm otool strings; do grep -qx "$t" "$WORK/readers.log"; done
}

@test "an NM that cannot read the binary fails the guard closed" {
  [ "$HAVE_X8609" = 1 ] || skip "host cannot emit x86_64/10.9"
  run env NM=false sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 4 ]
  [[ "$output" == *"CANNOT MEASURE"*"could not read"* ]] || false
}

@test "a STRINGS that cannot read the binary fails the guard closed" {
  [ "$HAVE_X8609" = 1 ] || skip "host cannot emit x86_64/10.9"
  run env STRINGS=false sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 4 ]
  [[ "$output" == *"CANNOT MEASURE"*"could not read"* ]] || false
}

# A reader that runs the host's own tool, except where it is told to fail or to warn.
mk_fat() {
  mk_stamped "$WORK/p109" x86_64 10.9 10.9
  mk_stamped "$WORK/a113" arm64 11.0 11.3
  lipo -create "$WORK/p109" "$WORK/a113" -output "$WORK/fatok"
}

@test "LIPO is the reader that thins a fat binary's x86_64 slice" {
  mk_fat
  mk_readers
  run env LIPO="$WORK/readers/lipo" MAVERICKS_ALLOW_ARCHS="arm64 x86_64" sh "$GUARD" "$WORK/fatok"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^lipo$' "$WORK/readers.log")" -ge 2 ]
  # macho-slices.sh thins each of the 2 slices first; only the guard's own thin, the 3rd, fails.
  printf '#!/bin/sh\ncase "$1" in -thin) echo x >> "%s/thins"; [ "$(wc -l < "%s/thins")" -lt 3 ] || { echo "lipo: thin broke" >&2; exit 1; } ;; esac\nexec "%s" "$@"\n' "$WORK" "$WORK" "$(command -v lipo)" > "$WORK/readers/lipo-nothin"
  chmod +x "$WORK/readers/lipo-nothin"
  run env LIPO="$WORK/readers/lipo-nothin" MAVERICKS_ALLOW_ARCHS="arm64 x86_64" sh "$GUARD" "$WORK/fatok"
  [ "$status" -eq 4 ]
  [[ "$output" == *"CANNOT MEASURE"*"-thin could not read the x86_64 slice"* ]] || false
  [[ "$output" == *"lipo: thin broke"* ]] || false
}

@test "a plain nm that cannot read the binary fails closed under MAVERICKS_REQUIRE_DEFINED_SYMBOLS" {
  [ "$HAVE_X8609" = 1 ] || skip "host cannot emit x86_64/10.9"
  printf '#!/bin/sh\ncase "$1" in -m) exec "%s" "$@" ;; esac\necho "plain nm broke" >&2\nexit 1\n' "$(command -v nm)" > "$WORK/nm-plain-broken"
  chmod +x "$WORK/nm-plain-broken"
  run env NM="$WORK/nm-plain-broken" MAVERICKS_REQUIRE_DEFINED_SYMBOLS=_main sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 4 ]
  [[ "$output" == *"CANNOT MEASURE"*"could not read"* ]] || false
  [[ "$output" == *"plain nm broke"* ]] || false
}

@test "a reader's warnings stay quiet on success; its error is replayed on failure" {
  [ "$HAVE_X8609" = 1 ] || skip "host cannot emit x86_64/10.9"
  printf '#!/bin/sh\necho "nm: noisy warning" >&2\nexec "%s" "$@"\n' "$(command -v nm)" > "$WORK/nm-noisy"
  printf '#!/bin/sh\necho "strings: its own error" >&2\nexit 1\n' > "$WORK/strings-broken"
  chmod +x "$WORK/nm-noisy" "$WORK/strings-broken"
  run env NM="$WORK/nm-noisy" sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 0 ]
  [[ "$output" != *"noisy warning"* ]] || false
  run env STRINGS="$WORK/strings-broken" sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 4 ]
  [[ "$output" == *"strings: its own error"* ]] || false
}

@test "a LIPO or OTOOL that fails fails closed; a file that is not Mach-O is still just unreadable" {
  [ "$HAVE_X8609" = 1 ] || skip "host cannot emit x86_64/10.9"
  run env LIPO=/nonexistent/lipo sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 4 ]
  [[ "$output" == *"CANNOT MEASURE"* ]] || false
  [[ "$output" == *"/nonexistent/lipo"* ]] || false
  run env OTOOL=/nonexistent/otool sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 4 ]
  [[ "$output" == *"/nonexistent/otool"* ]] || false
  printf 'hello\n' > "$WORK/text"
  run sh "$GUARD" "$WORK/text"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not a readable Mach-O"* ]] || false
}
