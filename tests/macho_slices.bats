#!/usr/bin/env bats
# platform: host-agnostic
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning"

setup() {
  S="$BATS_TEST_DIRNAME/../scripts/macho-slices.sh"
  CL="$(sh "$BATS_TEST_DIRNAME/../scripts/fetch_clang22.sh" "$BATS_TEST_DIRNAME/../components/clang22")"
  LIPO="$CL/bin/llvm-lipo"; OTOOL="$CL/bin/llvm-otool"
  export LIPO OTOOL
  S9="$(sh "$BATS_TEST_DIRNAME/../scripts/fetch_sdk.sh")"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/macho_slices.XXXXXX")"
  printf 'int main(void){return 0;}\n' > "$WORK/m.c"
  cc22 x86_64-apple-macos10.9 "$S9" 10.9 10.9 "$WORK/m.c" -o "$WORK/x109"
  if "$CL/bin/llc" --version | grep -q aarch64; then
    S11="$(sh "$BATS_TEST_DIRNAME/../scripts/fetch_sdk.sh" --arch arm64)"
    cc22 arm64-apple-macos11.0 "$S11" 11.0 11.3 "$WORK/m.c" -o "$WORK/a113"
    "$LIPO" -create "$WORK/x109" "$WORK/a113" -output "$WORK/fat"
  fi
}
cc22() {  # $1 target  $2 sysroot  $3 minos  $4 sdk  then clang arguments
  _t="$1"; _r="$2"; _m="$3"; _s="$4"; shift 4
  "$CL/bin/clang" --no-default-config -Wno-unused-command-line-argument -fuse-ld=lld --ld-path="$CL/bin/ld64.lld" -target "$_t" -isysroot "$_r" "-Wl,-platform_version,macos,$_m,$_s" "$@"
}
need_fat() { [ -f "$WORK/fat" ] || skip "this clang22 has no arm64 target (the 10.9 native build is x86_64 only)"; }
teardown() { [ -z "${WORK:-}" ] || rm -rf "$WORK"; }

@test "a thin x86_64 binary: one line, its recorded minos and sdk" {
  run sh "$S" "$WORK/x109"
  [ "$status" -eq 0 ]
  [ "$output" = "x86_64 EXECUTE 10.9 10.9" ]
}

@test "a fat binary: one line per slice, LC_BUILD_VERSION's minos not the linker's version" {
  need_fat
  run sh "$S" "$WORK/fat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"x86_64 EXECUTE 10.9 10.9"* ]] || false
  [[ "$output" == *"arm64 EXECUTE 11.0 11.3"* ]] || false
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "a static archive: members report OBJECT" {
  cc22 x86_64-apple-macos10.9 "$S9" 10.9 10.9 -c "$WORK/m.c" -o "$WORK/m.o"
  "$CL/bin/llvm-ar" rcs "$WORK/libm.a" "$WORK/m.o"
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
  need_fat
  mkdir -p "$WORK/readers"
  for pair in "lipo:$LIPO" "otool:$OTOOL"; do
    t="${pair%%:*}"; real="${pair#*:}"
    printf '#!/bin/sh\necho "%s $1" >> "%s/readers.log"\nexec "%s" "$@"\n' "$t" "$WORK" "$real" > "$WORK/readers/$t"
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
  printf '#!/bin/sh\ncase "$1" in -l) echo "otool: -l broke" >&2; exit 1 ;; esac\nexec "%s" "$@"\n' "$OTOOL" > "$WORK/otool-nol"
  chmod +x "$WORK/otool-nol"
  run env OTOOL="$WORK/otool-nol" sh "$S" "$WORK/x109"
  [ "$status" -eq 4 ]
  [[ "$output" == *"-l could not read"* ]] || false
  [[ "$output" == *"otool: -l broke"* ]] || false
}

@test "an OTOOL that fails only for -hv, on a file LIPO read, fails closed (exit 4)" {
  printf '#!/bin/sh\ncase "$1" in -hv) echo "otool: -hv broke" >&2; exit 1 ;; esac\nexec "%s" "$@"\n' "$OTOOL" > "$WORK/otool-nohv"
  chmod +x "$WORK/otool-nohv"
  for f in x109 fat; do
    [ -f "$WORK/$f" ] || continue
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
