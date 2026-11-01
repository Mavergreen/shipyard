#!/usr/bin/env bats
# platform: host-agnostic
# spec: scripts/assert_binary_compatible.sh -- the unit under test. Reads the checked-in Mach-O fixtures
#       in tests/fixtures/macho (built once by tests/fixtures/macho/build.sh) with LLVM's readers, so
#       it runs the same on 10.9, modern macOS and Linux and needs no compiler.

setup() {
  GUARD="$BATS_TEST_DIRNAME/../scripts/assert_binary_compatible.sh"
  SELF="$BATS_TEST_DIRNAME/../scripts"
  . "$SELF/lib/macho-tools.sh"
  for v in LIPO NM STRINGS OTOOL; do
    mach_tool "$v" 2>/dev/null || skip "no LLVM reader for $v (install llvm, or set $v)"
  done
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/compat_guard_test.XXXXXX")"
  cp -p "$BATS_TEST_DIRNAME"/fixtures/macho/* "$WORK"/
}
teardown() { [ -z "${WORK:-}" ] || rm -rf "$WORK"; }

first_is() {  # the first line of $output starts with "$1: "
  case "$output" in "$1: "*) return 0 ;; *) echo "first line should start with '$1: ', got: $output"; return 1 ;; esac
}

@test "clean binary passes" {
  run sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 0 ]
}

@test "post-10.9 undefined import is caught via MAVERICKS_POST_10_9_SYMBOLS" {
  run env MAVERICKS_POST_10_9_SYMBOLS='_mav_test_post109' sh "$GUARD" "$WORK/leak"
  [ "$status" -ne 0 ]
  first_is compat-imports
  [[ "$output" == *_mav_test_post109* ]] || false
}

@test "MAVERICKS_REQUIRE_DEFINED_SYMBOLS passes when the symbol is defined" {
  run env MAVERICKS_REQUIRE_DEFINED_SYMBOLS='_mav_test_shim' sh "$GUARD" "$WORK/shim"
  [ "$status" -eq 0 ]
}

@test "MAVERICKS_REQUIRE_DEFINED_SYMBOLS fails when the symbol is absent" {
  run env MAVERICKS_REQUIRE_DEFINED_SYMBOLS='_mav_test_shim' sh "$GUARD" "$WORK/clean"
  [ "$status" -ne 0 ]
  first_is compat-required-defined
}

@test "post-10.9 ObjC selector (labelColor) is caught -- nm can't see it" {
  run sh "$GUARD" "$WORK/sel_bad"
  [ "$status" -ne 0 ]
  first_is compat-selectors
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

@test "x86_64 recording the runner's SDK fails -- the audit's blind spot" {
  run sh "$GUARD" "$WORK/r265"
  [ "$status" -ne 0 ]
  first_is sdk-pin
  [[ "$output" == *"sdk 26.5"* ]] || false
}

@test "x86_64 recording the pinned 10.9 SDK passes" {
  run sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 0 ]
}

@test "an arch named twice in MAVERICKS_ALLOW_ARCHS is still the same arch set" {
  run env MAVERICKS_ALLOW_ARCHS="x86_64 x86_64" sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 0 ]
}

@test "an arm64 slice needs MAVERICKS_ALLOW_ARCHS, and then the 11.3 pin" {
  run sh "$GUARD" "$WORK/a113"
  [ "$status" -ne 0 ]
  first_is compat-archs
  run env MAVERICKS_ALLOW_ARCHS=arm64 sh "$GUARD" "$WORK/a113"
  [ "$status" -eq 0 ]
  run env MAVERICKS_ALLOW_ARCHS=arm64 sh "$GUARD" "$WORK/a265"
  [ "$status" -ne 0 ]
  first_is sdk-pin
}

@test "a universal binary with one bad slice fails and names that slice" {
  run env MAVERICKS_ALLOW_ARCHS="x86_64 arm64" sh "$GUARD" "$WORK/fatbad"
  [ "$status" -ne 0 ]
  first_is sdk-pin
  [[ "$output" == *"arm64 records minos 11.0 sdk 26.5"* ]] || false
  run env MAVERICKS_ALLOW_ARCHS="arm64 x86_64" sh "$GUARD" "$WORK/fatok"
  [ "$status" -eq 0 ]
}

@test "post-10.9 imports are still caught in a fat binary's x86_64 slice" {
  run env MAVERICKS_ALLOW_ARCHS="x86_64 arm64" MAVERICKS_POST_10_9_SYMBOLS='_mav_test_post109' sh "$GUARD" "$WORK/fatleak"
  [ "$status" -ne 0 ]
  first_is compat-imports
  [[ "$output" == *_mav_test_post109* ]] || false
}

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the guard
#       honours the same declared sdk-pin:<glob> exemptions as the package-time rule, read from
#       $MAVERICKS_DEVIATIONS_ROOT/.mavergreen/deviations/, and they excuse the minos/sdk rule only.
declare_deviation() { . "$BATS_TEST_DIRNAME/lib/deviation_tree.sh"; deviation "$WORK" sdk-pin "$1" "$2" "$3"; }

@test "a matching sdk-pin glob excuses the SDK rule, and says so" {
  declare_deviation r265 '*/r265' 'prebuilt upstream, shipped verbatim'
  run env MAVERICKS_DEVIATIONS_ROOT="$WORK" sh "$GUARD" "$WORK/r265"
  [ "$status" -eq 0 ]
  [[ "$output" == *"compat guard: $WORK/r265 is excused from sdk-pin: prebuilt upstream, shipped verbatim"* ]] || false
}

@test "a non-matching sdk-pin glob excuses nothing" {
  declare_deviation other '*/other' 'prebuilt upstream'
  run env MAVERICKS_DEVIATIONS_ROOT="$WORK" sh "$GUARD" "$WORK/r265"
  [ "$status" -ne 0 ]
  first_is sdk-pin
  [[ "$output" == *"sdk 26.5"* ]] || false
}

@test "an sdk-pin glob with no reason fails the guard closed" {
  declare_deviation r265 '*/r265' ''
  run env MAVERICKS_DEVIATIONS_ROOT="$WORK" sh "$GUARD" "$WORK/r265"
  [ "$status" -ne 0 ]
  first_is deviation-complete
  [[ "$output" != *"is excused"* ]] || false
}

@test "an sdk-pin excuse does not excuse an arch outside MAVERICKS_ALLOW_ARCHS" {
  declare_deviation a265 '*/a265' 'prebuilt upstream'
  run env MAVERICKS_DEVIATIONS_ROOT="$WORK" sh "$GUARD" "$WORK/a265"
  [ "$status" -ne 0 ]
  first_is compat-archs
  [[ "$output" == *"arches 'arm64' != 'x86_64'"* ]] || false
  run env MAVERICKS_DEVIATIONS_ROOT="$WORK" MAVERICKS_ALLOW_ARCHS=arm64 sh "$GUARD" "$WORK/a265"
  [ "$status" -eq 0 ]
}

# spec: scripts/assert_binary_compatible.sh LIPO/NM/STRINGS/OTOOL knobs -- a recording reader for each
#       knob: logs its name, then runs the LLVM tool the seam found.
mk_readers() {
  mkdir -p "$WORK/readers"
  for pair in lipo:"$LIPO" nm:"$NM" otool:"$OTOOL" strings:"$STRINGS"; do
    printf '#!/bin/sh\necho %s >> "%s/readers.log"\nexec "%s" "$@"\n' "${pair%%:*}" "$WORK" "${pair#*:}" > "$WORK/readers/${pair%%:*}"
    chmod +x "$WORK/readers/${pair%%:*}"
  done
}

@test "LIPO, NM, STRINGS and OTOOL name the readers the guard runs" {
  mk_readers
  R="$WORK/readers"
  run env LIPO="$R/lipo" NM="$R/nm" STRINGS="$R/strings" OTOOL="$R/otool" sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 0 ]
  for t in lipo nm otool strings; do grep -qx "$t" "$WORK/readers.log"; done
}

@test "an NM that cannot read the binary fails the guard closed, naming compat-imports" {
  run env NM=false sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 1 ]
  first_is compat-imports
  [[ "$output" == *"CANNOT MEASURE"*"could not read"* ]] || false
}

@test "a STRINGS that cannot read the binary fails the guard closed, naming compat-selectors" {
  run env STRINGS=false sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 1 ]
  first_is compat-selectors
  [[ "$output" == *"CANNOT MEASURE"*"could not read"* ]] || false
}

@test "LIPO is the reader that thins a fat binary's x86_64 slice" {
  mk_readers
  run env LIPO="$WORK/readers/lipo" MAVERICKS_ALLOW_ARCHS="arm64 x86_64" sh "$GUARD" "$WORK/fatok"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^lipo$' "$WORK/readers.log")" -ge 2 ]
  # spec: scripts/macho-slices.sh -- thins each of the 2 slices first; only the guard's own thin, the
  #       3rd, fails.
  printf '#!/bin/sh\ncase "$1" in -thin) echo x >> "%s/thins"; [ "$(wc -l < "%s/thins")" -lt 3 ] || { echo "lipo: thin broke" >&2; exit 1; } ;; esac\nexec "%s" "$@"\n' "$WORK" "$WORK" "$LIPO" > "$WORK/readers/lipo-nothin"
  chmod +x "$WORK/readers/lipo-nothin"
  run env LIPO="$WORK/readers/lipo-nothin" MAVERICKS_ALLOW_ARCHS="arm64 x86_64" sh "$GUARD" "$WORK/fatok"
  [ "$status" -eq 1 ]
  first_is compat-imports
  [[ "$output" == *"CANNOT MEASURE"*"-thin could not read the x86_64 slice"* ]] || false
  [[ "$output" == *"lipo: thin broke"* ]] || false
}

@test "a plain nm that cannot read the binary fails closed under MAVERICKS_REQUIRE_DEFINED_SYMBOLS" {
  printf '#!/bin/sh\ncase "$1" in -m) exec "%s" "$@" ;; esac\necho "plain nm broke" >&2\nexit 1\n' "$NM" > "$WORK/nm-plain-broken"
  chmod +x "$WORK/nm-plain-broken"
  run env NM="$WORK/nm-plain-broken" MAVERICKS_REQUIRE_DEFINED_SYMBOLS=_main sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 1 ]
  first_is compat-required-defined
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
  [ "$status" -eq 1 ]
  [[ "$output" == *"strings: its own error"* ]] || false
}

@test "a LIPO or OTOOL that fails fails closed naming it; a file that is not Mach-O is still just unreadable" {
  run env LIPO=/nonexistent/lipo sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 1 ]
  first_is compat-archs
  [[ "$output" == *"CANNOT MEASURE"* ]] || false
  [[ "$output" == *"/nonexistent/lipo"* ]] || false
  run env OTOOL=/nonexistent/otool sh "$GUARD" "$WORK/clean"
  [ "$status" -eq 1 ]
  [[ "$output" == *"/nonexistent/otool"* ]] || false
  printf 'hello\n' > "$WORK/text"
  run sh "$GUARD" "$WORK/text"
  [ "$status" -eq 1 ]
  first_is compat-archs
  [[ "$output" == *"is not a readable Mach-O"* ]] || false
}

@test "no binary named and no dist: nothing measured fails closed" {
  run env -u SHIPYARD_CHECK_DIST sh "$GUARD"
  [ "$status" -eq 1 ]
  first_is compat-archs
}

@test "under --dist it reads every Mach-O in a tarball, and matches a deviation against its path inside" {
  mkdir -p "$WORK/dist"
  cp "$BATS_TEST_DIRNAME/fixtures/checks/sdk-pin/fail/dist/tool.tar.gz" "$WORK/dist/"
  run env SHIPYARD_CHECK_DIST="$WORK/dist" sh "$GUARD"
  [ "$status" -ne 0 ]
  first_is sdk-pin
  declare_deviation tool 'tool' 'built against a newer SDK, shipped verbatim'
  run env SHIPYARD_CHECK_DIST="$WORK/dist" MAVERICKS_DEVIATIONS_ROOT="$WORK" sh "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tool is excused from sdk-pin"* ]] || false
}
