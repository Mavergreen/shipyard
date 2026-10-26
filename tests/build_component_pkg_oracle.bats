#!/usr/bin/env bats
# platform: macOS-only -- pkgbuild and pkgutil are the oracle the seam is compared against
# The seam's output must match what pkgbuild produces with the old component plist (--analyze, then
# BundleIsRelocatable and BundleIsVersionChecked flipped off) on the same staged tree.

setup() {
  BUILD="$BATS_TEST_DIRNAME/../scripts/build_component_pkg.sh"
  GATE="$BATS_TEST_DIRNAME/../scripts/assert_pkg_installs_in_place.sh"
  command -v pkgbuild >/dev/null 2>&1 && command -v pkgutil >/dev/null 2>&1 || skip "no pkgbuild/pkgutil"
  STEVEDORE="$(sh "$BATS_TEST_DIRNAME/../scripts/fetch_stevedore.sh")" || skip "no stevedore"
  export STEVEDORE SOURCE_DATE_EPOCH=1700000000
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/build_component_pkg_oracle.XXXXXX")"
  APP="$WORK/root/Applications/Fake.app"
  mkdir -p "$APP/Contents/MacOS" "$WORK/scripts"
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
  printf '#!/bin/sh\nexit 0\n' > "$WORK/scripts/postinstall"; chmod +x "$WORK/scripts/postinstall"
}
teardown() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }

old_pkg() {
  plist="$WORK/old-components.plist"
  pkgbuild --analyze --root "$WORK/root" "$plist" >/dev/null 2>&1
  i=0
  while /usr/libexec/PlistBuddy -c "Print :$i" "$plist" >/dev/null 2>&1; do
    for key in BundleIsRelocatable BundleIsVersionChecked; do
      /usr/libexec/PlistBuddy -c "Set :$i:$key false" "$plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :$i:$key bool false" "$plist"
    done
    i=$((i + 1))
  done
  pkgbuild --root "$WORK/root" --component-plist "$plist" --identifier dev.mavergreen.fake \
    --version 1.2.3 --install-location / --scripts "$WORK/scripts" "$WORK/old.pkg" >/dev/null 2>&1
}

new_pkg() {
  sh "$BUILD" --root "$WORK/root" --identifier dev.mavergreen.fake --version 1.2.3 \
    --install-location / --scripts "$WORK/scripts" --out "$WORK/new.pkg" >/dev/null 2>&1
}

facts() {  # $1=pkg
  d="$WORK/x-$(basename "$1" .pkg)"
  pkgutil --expand "$1" "$d"
  pi="$d/PackageInfo"
  for a in identifier version install-location; do
    printf '%s=%s\n' "$a" "$(sed -n "s/.*<pkg-info[^>]* $a=\"\([^\"]*\)\".*/\1/p" "$pi" | head -1)"
  done
  tr '<' '\n' < "$pi" | grep -E '^(relocate|bundle-version)[ />]' | sed 's/ .*//; s/>.*//; s/\/$//' | sort
  tr '<' '\n' < "$pi" | grep -E '^(preinstall|postinstall)' | sed 's/ .*//' | sort
  gzip -dc < "$d/Payload" | cpio -it 2>/dev/null | sort
  (cd "$d" && ls Scripts 2>/dev/null | sort)
  gzip -dc < "$d/Payload" | cpio -itv 2>/dev/null | awk '{print $1, $NF}' | sort -k2
}

@test "oracle: seam output matches pkgbuild with the old component plist" {
  old_pkg
  new_pkg
  [ -f "$WORK/old.pkg" ] && [ -f "$WORK/new.pkg" ]
  facts "$WORK/old.pkg" > "$WORK/old.facts"
  facts "$WORK/new.pkg" > "$WORK/new.facts"
  [ -s "$WORK/old.facts" ]
  diff "$WORK/old.facts" "$WORK/new.facts"
}

@test "gate: a PLAIN pkgbuild pkg is rejected (this is the shipped-bug shape)" {
  pkgbuild --root "$WORK/root" --identifier dev.mavergreen.fake \
    --version 1.2.3 --install-location / "$WORK/plain.pkg"
  run sh "$GATE" "$WORK/plain.pkg"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'BundleIsRelocatable is ON'
  echo "$output" | grep -q 'BundleIsVersionChecked is ON'
}
