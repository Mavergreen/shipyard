#!/usr/bin/env bats
# platform: macOS-only -- every case needs Apple clang, and all of them skip without it
# Unit tests for scripts/assert_binary_compatible.sh. Builds tiny x86_64/10.9 fixture Mach-Os
# with controlled symbols. If the host clang cannot emit an x86_64/10.9 slice, the
# arch/min-OS-dependent cases skip, but the symbol logic still runs.

setup() {
  GUARD="$BATS_TEST_DIRNAME/../scripts/assert_binary_compatible.sh"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/compat_guard_test.XXXXXX")"
  CC=$(command -v clang || command -v cc)
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
  # platform: on the 10.9 box there is no vtool, and none is needed: its native SDK already records 10.9.
  xcrun --find vtool >/dev/null 2>&1 && for fx in clean shim leak sel_bad sel_ok; do
    [ -f "$WORK/$fx" ] || continue
    xcrun vtool -set-version-min macos 10.9 10.9 -replace -output "$WORK/$fx.stamped" "$WORK/$fx" \
      && mv "$WORK/$fx.stamped" "$WORK/$fx"
  done
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
    *)      xcrun vtool -set-build-version macos "$3" "$4" -replace -output "$1" "$WORK/s.$2" ;;
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
