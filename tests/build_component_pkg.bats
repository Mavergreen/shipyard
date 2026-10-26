#!/usr/bin/env bats
# platform: host-agnostic
# Tests for scripts/build_component_pkg.sh and scripts/assert_pkg_installs_in_place.sh. A tiny real
# .app bundle stands in for a product payload. The packager is the pinned stevedore, fetched once.

setup() {
  BUILD="$BATS_TEST_DIRNAME/../scripts/build_component_pkg.sh"
  GATE="$BATS_TEST_DIRNAME/../scripts/assert_pkg_installs_in_place.sh"
  STEVEDORE="$(sh "$BATS_TEST_DIRNAME/../scripts/fetch_stevedore.sh")" || skip "no stevedore"
  export STEVEDORE
  export SOURCE_DATE_EPOCH=1700000000
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/build_component_pkg_test.XXXXXX")"
  APP="$WORK/root/Applications/Fake.app"
  mkdir -p "$APP/Contents/MacOS"
  cat > "$APP/Contents/Info.plist" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.mavergreen.fake</string>
<key>CFBundleName</key><string>Fake</string>
<key>CFBundleExecutable</key><string>Fake</string>
<key>CFBundleVersion</key><string>1.2.3</string>
<key>CFBundleShortVersionString</key><string>1.2.3</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PL
  printf '#!/bin/sh\ntrue\n' > "$APP/Contents/MacOS/Fake"; chmod +x "$APP/Contents/MacOS/Fake"
}
teardown() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }

build() {
  sh "$BUILD" --root "$WORK/root" --identifier dev.mavergreen.fake \
    --version 1.2.3 --install-location / --out "$1"
}

@test "build_component_pkg: writes a component that installs in place" {
  run build "$WORK/clean.pkg"
  [ "$status" -eq 0 ]
  [ -f "$WORK/clean.pkg" ]
  run sh "$GATE" "$WORK/clean.pkg"
  [ "$status" -eq 0 ]
}

@test "build_component_pkg: stdout is the out path alone and the bundle count goes to stderr" {
  out="$(build "$WORK/clean.pkg" 2>"$WORK/err")"
  [ "$out" = "$WORK/clean.pkg" ]
  grep -q 'forced install-in-place on 1 bundle component(s)' "$WORK/err"
}

@test "build_component_pkg: leaves no -components.plist" {
  run build "$WORK/clean.pkg"
  [ "$status" -eq 0 ]
  [ ! -e "$WORK/clean-components.plist" ]
}

@test "build_component_pkg: same tree same bytes" {
  build "$WORK/a.pkg" >/dev/null 2>&1
  build "$WORK/b.pkg" >/dev/null 2>&1
  cmp "$WORK/a.pkg" "$WORK/b.pkg"
}

@test "build_component_pkg: no epoch source fails naming SOURCE_DATE_EPOCH" {
  mkdir "$WORK/nogit"
  cd "$WORK/nogit"
  unset SOURCE_DATE_EPOCH
  GIT_CEILING_DIRECTORIES="$WORK" run build "$WORK/none.pkg"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q SOURCE_DATE_EPOCH
  [ ! -e "$WORK/none.pkg" ]
}

@test "build_component_pkg: a missing argument exits 2" {
  run sh "$BUILD" --root "$WORK/root" --identifier x --version 1 --install-location /
  [ "$status" -eq 2 ]
}

@test "build_component_pkg: an unknown argument exits 2" {
  run sh "$BUILD" --bogus
  [ "$status" -eq 2 ]
}

@test "build_component_pkg: a missing root exits 1" {
  run sh "$BUILD" --root "$WORK/nope" --identifier x --version 1 --install-location / --out "$WORK/x.pkg"
  [ "$status" -eq 1 ]
}

# needs stevedore >= the release after 20261026.1 (its tree walk skips ._* files)
@test "build_component_pkg: AppleDouble files never reach the pkg" {
  mkdir -p "$WORK/dirty/x" "$WORK/clean/x"
  printf 'data\n' > "$WORK/dirty/x/f"; printf 'junk\n' > "$WORK/dirty/x/._f"
  printf 'data\n' > "$WORK/clean/x/f"
  for v in dirty clean; do
    sh "$BUILD" --root "$WORK/$v" --identifier dev.mavergreen.fake --version 1 \
      --install-location / --out "$WORK/$v.pkg" >/dev/null 2>&1
  done
  cmp "$WORK/dirty.pkg" "$WORK/clean.pkg"
}

@test "gate: missing pkg fails loudly rather than passing vacuously" {
  run sh "$GATE" "$WORK/does-not-exist.pkg"
  [ "$status" -ne 0 ]
}
