#!/usr/bin/env bats
# Tests for scripts/build_component_pkg.sh and scripts/assert_pkg_installs_in_place.sh -- the
# install-in-place guarantee. A tiny real .app bundle stands in for a product payload, so pkgbuild
# actually classifies it as a relocatable/version-checked component (a plain-file payload would not
# exercise either flag). macOS-only: pkgbuild/pkgutil are the system under test, so skip elsewhere.

setup() {
  BUILD="$BATS_TEST_DIRNAME/../scripts/build_component_pkg.sh"
  GATE="$BATS_TEST_DIRNAME/../scripts/assert_pkg_installs_in_place.sh"
  command -v pkgbuild >/dev/null 2>&1 && command -v pkgutil >/dev/null 2>&1 || skip "no pkgbuild/pkgutil"
  WORK="$(mktemp -d -t build_component_pkg_test)"
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

@test "build_component_pkg: output installs in place (relocation + version-check both off)" {
  run sh "$BUILD" --root "$WORK/root" --identifier dev.mavergreen.fake \
    --version 1.2.3 --install-location / --out "$WORK/clean.pkg"
  [ "$status" -eq 0 ]
  [ -f "$WORK/clean.pkg" ]
  # component plist the helper generated has both flags flipped
  grep -A1 BundleIsRelocatable "$WORK/clean-components.plist" | grep -q '<false/>'
  grep -A1 BundleIsVersionChecked "$WORK/clean-components.plist" | grep -q '<false/>'
  # and the built artifact passes the gate
  run sh "$GATE" "$WORK/clean.pkg"
  [ "$status" -eq 0 ]
}

@test "gate: a PLAIN pkgbuild pkg is rejected (this is the shipped-bug shape)" {
  pkgbuild --root "$WORK/root" --identifier dev.mavergreen.fake \
    --version 1.2.3 --install-location / "$WORK/plain.pkg"
  run sh "$GATE" "$WORK/plain.pkg"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'BundleIsRelocatable is ON'
  echo "$output" | grep -q 'BundleIsVersionChecked is ON'
}

@test "gate: missing pkg fails loudly rather than passing vacuously" {
  run sh "$GATE" "$WORK/does-not-exist.pkg"
  [ "$status" -ne 0 ]
}
