#!/usr/bin/env bats
# platform: host-agnostic
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- reads the
#       checked-in Mach-O fixtures in tests/fixtures/macho with LLVM's readers, so it runs the same on
#       10.9, modern macOS and Linux and needs no compiler.

setup() {
  S="$BATS_TEST_DIRNAME/../scripts/macho-slices.sh"
  . "$BATS_TEST_DIRNAME/../scripts/lib/macho-tools.sh"
  for v in LIPO OTOOL; do
    mach_tool "$v" 2>/dev/null || skip "no LLVM reader for $v (install llvm, or set $v)"
  done
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/macho_slices.XXXXXX")"
  cp -p "$BATS_TEST_DIRNAME"/fixtures/macho/* "$WORK"/
}
teardown() { [ -z "${WORK:-}" ] || rm -rf "$WORK"; }

@test "a thin x86_64 binary: one line, its recorded minos and sdk" {
  run sh "$S" "$WORK/clean"
  [ "$status" -eq 0 ]
  [ "$output" = "x86_64 EXECUTE 10.9 10.9" ]
}

@test "a thin arm64 binary: LC_BUILD_VERSION's minos and sdk" {
  run sh "$S" "$WORK/a113"
  [ "$status" -eq 0 ]
  [ "$output" = "arm64 EXECUTE 11.0 11.3" ]
}

@test "a fat binary: one line per slice, LC_BUILD_VERSION's minos not the linker's version" {
  run sh "$S" "$WORK/fatok"
  [ "$status" -eq 0 ]
  [[ "$output" == *"x86_64 EXECUTE 10.9 10.9"* ]] || false
  [[ "$output" == *"arm64 EXECUTE 11.0 11.3"* ]] || false
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "a static archive: members report OBJECT" {
  run sh "$S" "$WORK/libm.a"
  echo "# status=$status output=$output" >&3
  echo "# lipo: $("$LIPO" -info "$WORK/libm.a" 2>&1)" >&3
  echo "# otool: $("$OTOOL" -hv "$WORK/libm.a" 2>&1 | head -8)" >&3
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
  for pair in lipo:"$LIPO" otool:"$OTOOL"; do
    printf '#!/bin/sh\necho "%s $1" >> "%s/readers.log"\nexec "%s" "$@"\n' "${pair%%:*}" "$WORK" "${pair#*:}" > "$WORK/readers/${pair%%:*}"
    chmod +x "$WORK/readers/${pair%%:*}"
  done
  run env LIPO="$WORK/readers/lipo" OTOOL="$WORK/readers/otool" sh "$S" "$WORK/fatok"
  [ "$status" -eq 0 ]
  [[ "$output" == *"x86_64 EXECUTE 10.9 10.9"* ]] || false
  [[ "$output" == *"arm64 EXECUTE 11.0 11.3"* ]] || false
  grep -qx 'lipo -info' "$WORK/readers.log"
  grep -qx 'lipo -thin' "$WORK/readers.log"
  grep -qx 'otool -hv' "$WORK/readers.log"
  grep -qx 'otool -l' "$WORK/readers.log"
}

@test "an OTOOL that fails only for -l fails closed (exit 4), not as a slice with no version" {
  printf '#!/bin/sh\ncase "$1" in -l) echo "otool: -l broke" >&2; exit 1 ;; esac\nexec "%s" "$@"\n' "$OTOOL" > "$WORK/otool-nol"
  chmod +x "$WORK/otool-nol"
  run env OTOOL="$WORK/otool-nol" sh "$S" "$WORK/clean"
  [ "$status" -eq 4 ]
  [[ "$output" == *"-l could not read"* ]] || false
  [[ "$output" == *"otool: -l broke"* ]] || false
}

@test "an OTOOL that fails only for -hv, on a file LIPO read, fails closed (exit 4)" {
  printf '#!/bin/sh\ncase "$1" in -hv) echo "otool: -hv broke" >&2; exit 1 ;; esac\nexec "%s" "$@"\n' "$OTOOL" > "$WORK/otool-nohv"
  chmod +x "$WORK/otool-nohv"
  for f in clean fatok; do
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
  run env LIPO=/nonexistent/lipo sh "$S" "$WORK/clean"
  [ "$status" -eq 4 ]
  [[ "$output" == *"/nonexistent/lipo"* ]] || false
  run env OTOOL=/nonexistent/otool sh "$S" "$WORK/clean"
  [ "$status" -eq 4 ]
  [[ "$output" == *"/nonexistent/otool"* ]] || false
  printf 'hello\n' > "$WORK/t"
  run sh "$S" "$WORK/t"
  [ "$status" -eq 1 ]
}
