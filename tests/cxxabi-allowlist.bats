#!/usr/bin/env bats
# platform: macOS-only -- the fixture archives are Mach-O, built with cc and ar

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/cxxabi-allowlist-test.XXXXXX")" && pwd)"
  if [ -z "${NM:-}" ]; then
    NM=nm
    [ ! -x /usr/local/mavergreen/clang22/bin/llvm-nm ] || NM=/usr/local/mavergreen/clang22/bin/llvm-nm
  fi
  export NM
  command -v cc >/dev/null 2>&1 && command -v ar >/dev/null 2>&1 || skip "no cc and ar"
  printf '\t.globl ___cxa_uncaught_exceptions\n___cxa_uncaught_exceptions:\n\tret\n\t.globl __ZTISt9exception\n\t.data\n__ZTISt9exception:\n\t.quad 0\n' > "$WORK/a.s"
  printf '\t.globl _foo\n_foo:\n\tret\n' > "$WORK/b.s"
  ( cd "$WORK" && cc -c a.s b.s && ar rcs fixture.a a.o b.o ) > /dev/null 2>&1 || skip "cannot build a Mach-O fixture"
}
teardown() { rm -rf "$WORK"; }

pkg_release() {  # pkg_release: serve a Recaulk release holding the fixture archive, listed in SHA256SUMS
  PIN="$(sed -n 's/^RECAULK_VERSION=//p' "$ROOT/scripts/recaulk.pin")"
  REL="$WORK/rel/Mavergreen/recaulk/releases/download/$PIN"
  STEVEDORE="${STEVEDORE:-$(sh "$ROOT/scripts/fetch_stevedore.sh")}"
  export STEVEDORE SOURCE_DATE_EPOCH=1700000000
  mkdir -p "$REL" "$WORK/base/usr/local/mavergreen/.base" "$WORK/prod/usr/local/mavergreen/recaulk/lib"
  echo x > "$WORK/base/usr/local/mavergreen/.base/x"
  cp "$WORK/fixture.a" "$WORK/prod/usr/local/mavergreen/recaulk/lib/librecaulk.a"
  sh "$ROOT/scripts/build_component_pkg.sh" --root "$WORK/base" --identifier dev.mavergreen.base --version 1.0 --install-location / --out "$WORK/base.pkg" > /dev/null 2>&1
  sh "$ROOT/scripts/build_component_pkg.sh" --root "$WORK/prod" --identifier dev.mavergreen.recaulk --version 1.0 --install-location / --out "$WORK/prod.pkg" > /dev/null 2>&1
  cat > "$WORK/dist.xml" <<DIST
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
  <pkg-ref id="dev.mavergreen.base" version="1.0">base.pkg</pkg-ref>
  <pkg-ref id="dev.mavergreen.recaulk" version="1.0">prod.pkg</pkg-ref>
  <choices-outline><line choice="dev.mavergreen.base"/><line choice="dev.mavergreen.recaulk"/></choices-outline>
  <choice id="dev.mavergreen.base"><pkg-ref id="dev.mavergreen.base"/></choice>
  <choice id="dev.mavergreen.recaulk"><pkg-ref id="dev.mavergreen.recaulk"/></choice>
</installer-gui-script>
DIST
  "$STEVEDORE" product --distribution "$WORK/dist.xml" --package "$WORK/base.pkg" --package "$WORK/prod.pkg" \
    --mtime 1700000000 --out "$REL/recaulk-$PIN.pkg" > /dev/null
  ( cd "$REL" && shasum -a 256 "recaulk-$PIN.pkg" > SHA256SUMS )
  export MAVERGREEN_RELEASES="file://$WORK/rel" MAVERGREEN_PKG_CACHE="$WORK/cache" SHIPYARD_FETCH_BACKOFF=0
  export TMPDIR="$WORK"
}

@test "allow-list is the archive's exported machinery" {
  run sh "$ROOT/scripts/cxxabi-allowlist.sh" "$WORK/fixture.a"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' __ZTISt9exception ___cxa_uncaught_exceptions | LC_ALL=C sort)" ] || false
}

@test "the machinery pattern is one line" {
  [ "$(wc -l < "$ROOT/scripts/cxxabi-machinery.txt" | tr -d ' ')" = 1 ]
  [ "$(printf '___cxa_throw\n_foo\n__Unwind_Resume\n' | grep -E -f "$ROOT/scripts/cxxabi-machinery.txt" | wc -l | tr -d ' ')" = 2 ]
}

@test "no allow-list, no pass" {
  printf 'not an archive\n' > "$WORK/bad.a"
  run sh -c "sh '$ROOT/scripts/cxxabi-allowlist.sh' '$WORK/bad.a' 2>/dev/null"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  run sh -c "sh '$ROOT/scripts/cxxabi-allowlist.sh' '$WORK/missing.a' 2>/dev/null"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "a missing NM fails clearly" {
  run env NM=/nonexistent/nm sh "$ROOT/scripts/cxxabi-allowlist.sh" "$WORK/fixture.a"
  [ "$status" -eq 1 ]
  [[ "$output" == *"/nonexistent/nm"* ]] || false
}

@test "an archive with no machinery is no allow-list" {
  ( cd "$WORK" && ar rcs plain.a b.o )
  run sh -c "sh '$ROOT/scripts/cxxabi-allowlist.sh' '$WORK/plain.a' 2>/dev/null"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "with no archive it reads the pinned Recaulk's librecaulk.a" {
  pkg_release
  run sh -c "sh '$ROOT/scripts/cxxabi-allowlist.sh' 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' __ZTISt9exception ___cxa_uncaught_exceptions | LC_ALL=C sort)" ] || false
}

@test "the pinned fetch is verified" {
  pkg_release
  printf '%064d  recaulk-%s.pkg\n' 0 "$PIN" > "$REL/SHA256SUMS"
  run sh -c "sh '$ROOT/scripts/cxxabi-allowlist.sh' 2>/dev/null"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}
