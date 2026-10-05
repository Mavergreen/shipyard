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
  xcrun vtool -set-build-version macos 11.0 11.3 -tool ld 1000.0 -replace -output "$WORK/a113" "$WORK/a"
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

@test "LIPO and OTOOL name the readers it runs, with the same answer" {
  mkdir -p "$WORK/readers"
  for t in lipo otool; do
    printf '#!/bin/sh\necho "%s $1" >> "%s/readers.log"\nexec "%s" "$@"\n' "$t" "$WORK" "$(command -v "$t")" > "$WORK/readers/$t"
    chmod +x "$WORK/readers/$t"
  done
  run env LIPO="$WORK/readers/lipo" OTOOL="$WORK/readers/otool" sh "$S" "$WORK/fat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"x86_64 EXECUTE 10.9 10.9"* ]] || false
  [[ "$output" == *"arm64 EXECUTE 11.0 11.3"* ]] || false
  grep -qx 'lipo -info' "$WORK/readers.log"
  grep -qx 'lipo -thin' "$WORK/readers.log"
  grep -qx 'otool -hv' "$WORK/readers.log"
  grep -qx 'otool -l' "$WORK/readers.log"
}

@test "an OTOOL that fails only for -l fails closed (exit 4), not as a slice with no version" {
  printf '#!/bin/sh\ncase "$1" in -l) echo "otool: -l broke" >&2; exit 1 ;; esac\nexec "%s" "$@"\n' "$(command -v otool)" > "$WORK/otool-nol"
  chmod +x "$WORK/otool-nol"
  run env OTOOL="$WORK/otool-nol" sh "$S" "$WORK/x109"
  [ "$status" -eq 4 ]
  [[ "$output" == *"-l could not read"* ]] || false
  [[ "$output" == *"otool: -l broke"* ]] || false
}

@test "an OTOOL that fails only for -hv, on a file LIPO read, fails closed (exit 4)" {
  printf '#!/bin/sh\ncase "$1" in -hv) echo "otool: -hv broke" >&2; exit 1 ;; esac\nexec "%s" "$@"\n' "$(command -v otool)" > "$WORK/otool-nohv"
  chmod +x "$WORK/otool-nohv"
  for f in x109 fat; do
    run env OTOOL="$WORK/otool-nohv" sh "$S" "$WORK/$f"
    [ "$status" -eq 4 ]
    [[ "$output" == *"-hv could not read"* ]] || false
    [[ "$output" == *"otool: -hv broke"* ]] || false
  done
}

@test "a Java class file (cafebabe) is not Mach-O: exit 1" {
  printf '\312\376\272\276\000\000\000\064junk' > "$WORK/C.class"
  run sh "$S" "$WORK/C.class"
  [ "$status" -eq 1 ]
}

@test "a LIPO or OTOOL that cannot run is exit 4 naming it; a non-Mach-O file stays exit 1" {
  run env LIPO=/nonexistent/lipo sh "$S" "$WORK/x109"
  [ "$status" -eq 4 ]
  [[ "$output" == *"/nonexistent/lipo"* ]] || false
  run env OTOOL=/nonexistent/otool sh "$S" "$WORK/x109"
  [ "$status" -eq 4 ]
  [[ "$output" == *"/nonexistent/otool"* ]] || false
  printf 'hello\n' > "$WORK/t"
  run sh "$S" "$WORK/t"
  [ "$status" -eq 1 ]
}
