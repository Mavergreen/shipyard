#!/usr/bin/env bats
# platform: host-agnostic
# spec: scripts/assert_binary_compatible.sh -- the unit under test. Builds tiny x86_64/10.9 fixture
#       Mach-Os with controlled symbols, with clang22 and the pinned SDKs.

cc22() {  # $1 target  $2 sysroot  $3 minos  $4 sdk  then clang arguments
  _t="$1"; _r="$2"; _m="$3"; _s="$4"; shift 4
  "$CL/bin/clang" --no-default-config -w -fuse-ld=lld --ld-path="$CL/bin/ld64.lld" -target "$_t" -isysroot "$_r" "-Wl,-platform_version,macos,$_m,$_s" "$@"
}

setup_file() {
  GUARD="$BATS_TEST_DIRNAME/../scripts/assert_binary_compatible.sh"
  CL="$(sh "$BATS_TEST_DIRNAME/../scripts/fetch_clang22.sh" "$BATS_TEST_DIRNAME/../components/clang22")"
  LIPO="$CL/bin/llvm-lipo"; OTOOL="$CL/bin/llvm-otool"; NM="$CL/bin/llvm-nm"; STRINGS="$CL/bin/llvm-strings"
  S9="$(sh "$BATS_TEST_DIRNAME/../scripts/fetch_sdk.sh")"
  S11=""
  if "$CL/bin/clang" -print-targets | grep -q aarch64; then S11="$(sh "$BATS_TEST_DIRNAME/../scripts/fetch_sdk.sh" --arch arm64)"; fi
  FIXTURES="$(mktemp -d "${TMPDIR:-/tmp}/compat_guard_fixtures.XXXXXX")"
  printf 'int main(void){return 0;}\n' > "$FIXTURES/clean.c"
  cc22 x86_64-apple-macos10.9 "$S9" 10.9 10.9 "$FIXTURES/clean.c" -o "$FIXTURES/clean"
  printf 'int mav_test_shim(void){return 0;}\nint main(void){return mav_test_shim();}\n' > "$FIXTURES/shim.c"
  cc22 x86_64-apple-macos10.9 "$S9" 10.9 10.9 "$FIXTURES/shim.c" -o "$FIXTURES/shim"
  printf 'extern int mav_test_post109(void);\nint main(void){return mav_test_post109();}\n' > "$FIXTURES/leak.c"
  cc22 x86_64-apple-macos10.9 "$S9" 10.9 10.9 -Wl,-undefined,dynamic_lookup "$FIXTURES/leak.c" -o "$FIXTURES/leak"
  printf '#import <AppKit/AppKit.h>\nint main(void){(void)[NSColor labelColor];return 0;}\n' > "$FIXTURES/sel_bad.m"
  cc22 x86_64-apple-macos10.9 "$S9" 10.9 10.9 -framework AppKit "$FIXTURES/sel_bad.m" -o "$FIXTURES/sel_bad"
  printf '#import <AppKit/AppKit.h>\nint main(void){(void)[NSColor blackColor];return 0;}\n' > "$FIXTURES/sel_ok.m"
  cc22 x86_64-apple-macos10.9 "$S9" 10.9 10.9 -framework AppKit "$FIXTURES/sel_ok.m" -o "$FIXTURES/sel_ok"
  export FIXTURES GUARD CL S9 S11 LIPO OTOOL NM STRINGS
}
teardown_file() { rm -rf "$FIXTURES"; }

# platform: every test copies the fixtures into its own $WORK because tests write there (the lipo
#           wrapper's $WORK/thins counter, the nm/strings stand-ins), so a shared directory would
#           leak state between tests.
setup() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/compat_guard_test.XXXXXX")"
  cp -p "$FIXTURES"/* "$WORK"/
}
teardown() { rm -rf "$WORK"; }

@test "clean binary passes" {
  run sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 0 ]
}

@test "post-10.9 undefined import is caught via MAVERICKS_POST_10_9_SYMBOLS" {
  run env MAVERICKS_POST_10_9_SYMBOLS='_mav_test_post109' sh "$GUARD" "$WORK/leak"
  [ "$status" -ne 0 ]
  [[ "$output" == *_mav_test_post109* ]] || false
}

@test "MAVERICKS_REQUIRE_DEFINED_SYMBOLS passes when the symbol is defined" {
  run env MAVERICKS_REQUIRE_DEFINED_SYMBOLS='_mav_test_shim' sh "$GUARD" "$WORK/shim"
  [ "$status" -eq 0 ]
}

@test "MAVERICKS_REQUIRE_DEFINED_SYMBOLS fails when the symbol is absent" {
  run env MAVERICKS_REQUIRE_DEFINED_SYMBOLS='_mav_test_shim' sh "$GUARD" "$WORK/clean"
  [ "$status" -ne 0 ]
}

@test "post-10.9 ObjC selector (labelColor) is caught -- nm can't see it" {
  run sh "$GUARD" "$WORK/sel_bad"
  [ "$status" -ne 0 ]
  [[ "$output" == *labelColor* ]] || false
}

@test "a 10.9-safe selector (blackColor) passes the selector scan" {
  run sh "$GUARD" "$WORK/sel_ok"
  [ "$status" -eq 0 ]
}

@test "MAVERICKS_ALLOW_SELECTORS allowlists a respondsToSelector-guarded selector" {
  run env MAVERICKS_ALLOW_SELECTORS=labelColor sh "$GUARD" "$WORK/sel_bad"
  [ "$status" -eq 0 ]
}

need_arm64() { [ -n "$S11" ] || skip "this clang22 has no arm64 target (the 10.9 native build is x86_64 only)"; }

mk_stamped() {  # $1 out, $2 arch, $3 minos, $4 sdk
  printf 'int main(void){return 0;}\n' > "$WORK/s.c"
  case "$2" in
    x86_64) cc22 "x86_64-apple-macos$3" "$S9" "$3" "$4" "$WORK/s.c" -o "$1" ;;
    *)      need_arm64; cc22 "arm64-apple-macos$3" "$S11" "$3" "$4" "$WORK/s.c" -o "$1" ;;
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
  "$LIPO" -create "$WORK/p109" "$WORK/a265" -output "$WORK/fatbad"
  run env MAVERICKS_ALLOW_ARCHS="x86_64 arm64" sh "$GUARD" "$WORK/fatbad"
  [ "$status" -ne 0 ]
  [[ "$output" == *"arm64 records minos 11.0 sdk 26.5"* ]] || false
  mk_stamped "$WORK/a113" arm64 11.0 11.3
  "$LIPO" -create "$WORK/p109" "$WORK/a113" -output "$WORK/fatok"
  run env MAVERICKS_ALLOW_ARCHS="arm64 x86_64" sh "$GUARD" "$WORK/fatok"
  [ "$status" -eq 0 ]
}

@test "post-10.9 imports are still caught in a fat binary's x86_64 slice" {
  need_arm64
  mk_stamped "$WORK/a113" arm64 11.0 11.3
  "$LIPO" -create "$WORK/leak" "$WORK/a113" -output "$WORK/fatleak"
  run env MAVERICKS_ALLOW_ARCHS="x86_64 arm64" MAVERICKS_POST_10_9_SYMBOLS='_mav_test_post109' sh "$GUARD" "$WORK/fatleak"
  [ "$status" -ne 0 ]
  [[ "$output" == *_mav_test_post109* ]] || false
}

@test "a pinned third-party binary passes on its content, and only on its exact bytes" {
  fw="$(sh "$BATS_TEST_DIRNAME/../scripts/fetch_sparkle_framework.sh")"
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

# spec: scripts/assert_binary_compatible.sh LIPO/NM/STRINGS/OTOOL knobs -- a recording reader for each
#       knob: logs its name, then runs clang22's own tool.
mk_readers() {
  mkdir -p "$WORK/readers"
  for pair in "lipo:$LIPO" "nm:$NM" "otool:$OTOOL" "strings:$STRINGS"; do
    t="${pair%%:*}"; real="${pair#*:}"
    printf '#!/bin/sh\necho %s >> "%s/readers.log"\nexec "%s" "$@"\n' "$t" "$WORK" "$real" > "$WORK/readers/$t"
    chmod +x "$WORK/readers/$t"
  done
}

@test "LIPO, NM, STRINGS and OTOOL name the readers the guard runs" {
  mk_readers
  R="$WORK/readers"
  run env LIPO="$R/lipo" NM="$R/nm" STRINGS="$R/strings" OTOOL="$R/otool" sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 0 ]
  for t in lipo nm otool strings; do grep -qx "$t" "$WORK/readers.log"; done
}

@test "an NM that cannot read the binary fails the guard closed" {
  run env NM=false sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 4 ]
  [[ "$output" == *"CANNOT MEASURE"*"could not read"* ]] || false
}

@test "a STRINGS that cannot read the binary fails the guard closed" {
  run env STRINGS=false sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 4 ]
  [[ "$output" == *"CANNOT MEASURE"*"could not read"* ]] || false
}

# spec: scripts/assert_binary_compatible.sh slice checks -- a fat x86_64/10.9 + arm64/11.3 fixture,
#       "$WORK/fatok".
mk_fat() {
  mk_stamped "$WORK/p109" x86_64 10.9 10.9
  mk_stamped "$WORK/a113" arm64 11.0 11.3
  "$LIPO" -create "$WORK/p109" "$WORK/a113" -output "$WORK/fatok"
}

@test "LIPO is the reader that thins a fat binary's x86_64 slice" {
  mk_fat
  mk_readers
  run env LIPO="$WORK/readers/lipo" MAVERICKS_ALLOW_ARCHS="arm64 x86_64" sh "$GUARD" "$WORK/fatok"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^lipo$' "$WORK/readers.log")" -ge 2 ]
  # spec: scripts/macho-slices.sh -- thins each of the 2 slices first; only the guard's own thin, the
  #       3rd, fails.
  printf '#!/bin/sh\ncase "$1" in -thin) echo x >> "%s/thins"; [ "$(wc -l < "%s/thins")" -lt 3 ] || { echo "lipo: thin broke" >&2; exit 1; } ;; esac\nexec "%s" "$@"\n' "$WORK" "$WORK" "$LIPO" > "$WORK/readers/lipo-nothin"
  chmod +x "$WORK/readers/lipo-nothin"
  run env LIPO="$WORK/readers/lipo-nothin" MAVERICKS_ALLOW_ARCHS="arm64 x86_64" sh "$GUARD" "$WORK/fatok"
  [ "$status" -eq 4 ]
  [[ "$output" == *"CANNOT MEASURE"*"-thin could not read the x86_64 slice"* ]] || false
  [[ "$output" == *"lipo: thin broke"* ]] || false
}

@test "a plain nm that cannot read the binary fails closed under MAVERICKS_REQUIRE_DEFINED_SYMBOLS" {
  printf '#!/bin/sh\ncase "$1" in -m) exec "%s" "$@" ;; esac\necho "plain nm broke" >&2\nexit 1\n' "$NM" > "$WORK/nm-plain-broken"
  chmod +x "$WORK/nm-plain-broken"
  run env NM="$WORK/nm-plain-broken" MAVERICKS_REQUIRE_DEFINED_SYMBOLS=_main sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 4 ]
  [[ "$output" == *"CANNOT MEASURE"*"could not read"* ]] || false
  [[ "$output" == *"plain nm broke"* ]] || false
}

@test "a reader's warnings stay quiet on success; its error is replayed on failure" {
  printf '#!/bin/sh\necho "nm: noisy warning" >&2\nexec "%s" "$@"\n' "$NM" > "$WORK/nm-noisy"
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
