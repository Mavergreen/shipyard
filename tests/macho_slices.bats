#!/usr/bin/env bats
# platform: macOS-only -- needs Apple clang, lipo and vtool to build and stamp its fixtures
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning"

setup() {
  S="$BATS_TEST_DIRNAME/../scripts/macho-slices.sh"
  # platform: vtool arrived with Xcode 11; the 10.9 box (Xcode 6) runs this suite too and has none.
  xcrun --find vtool >/dev/null 2>&1 || skip "no vtool (pre-Xcode 11) to stamp fixtures"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/macho_slices.XXXXXX")"
  printf 'int main(void){return 0;}\n' > "$WORK/m.c"
  clang -arch x86_64 -mmacosx-version-min=10.9 "$WORK/m.c" -o "$WORK/x"
  clang -arch arm64 -mmacosx-version-min=11.0 "$WORK/m.c" -o "$WORK/a"
  # platform: vtool rewrites the recorded SDK without needing that SDK, so no fixture downloads one.
  xcrun vtool -set-version-min macos 10.9 10.9 -replace -output "$WORK/x109" "$WORK/x"
  xcrun vtool -set-build-version macos 11.0 11.3 -replace -output "$WORK/a113" "$WORK/a"
  lipo -create "$WORK/x109" "$WORK/a113" -output "$WORK/fat"
}
teardown() { [ -z "${WORK:-}" ] || rm -rf "$WORK"; }

@test "a thin x86_64 binary: one line, its recorded minos and sdk" {
  run sh "$S" "$WORK/x109"
  [ "$status" -eq 0 ]
  [ "$output" = "x86_64 EXECUTE 10.9 10.9" ]
}

@test "a fat binary: one line per slice, LC_BUILD_VERSION's minos not the linker's version" {
  run sh "$S" "$WORK/fat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"x86_64 EXECUTE 10.9 10.9"* ]] || false
  [[ "$output" == *"arm64 EXECUTE 11.0 11.3"* ]] || false
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "a static archive: members report OBJECT" {
  clang -arch x86_64 -mmacosx-version-min=10.9 -c "$WORK/m.c" -o "$WORK/m.o"
  ar rcs "$WORK/libm.a" "$WORK/m.o"
  run sh "$S" "$WORK/libm.a"
  [ "$status" -eq 0 ]
  [[ "$output" == "x86_64 OBJECT 10.9 "* ]] || false
}

@test "not Mach-O: exit 1" {
  printf 'hello\n' > "$WORK/t"
  run sh "$S" "$WORK/t"
  [ "$status" -eq 1 ]
}
