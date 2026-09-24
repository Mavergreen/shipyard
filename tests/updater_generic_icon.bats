#!/usr/bin/env bats
# platform: macOS-only -- the updater is Objective-C against AppKit
# mavericks_add_updater_app: ICON is optional. With no ICON you must explicitly opt into the
# generic macOS app icon (ALLOW_GENERIC / -DMAVERICKS_ALLOW_GENERIC_ICON=ON); doing so ships an
# empty CFBundleIconFile (the standard generic app icon) and embeds no artwork.
SHARED="${BATS_TEST_DIRNAME}/.."

# Configure a tiny updater project with a FAKE Sparkle framework (so no network fetch) and an
# inline ED_PUBKEY (so no keyfile needed). $1 = extra add_updater_app args. Sets $d, $status, $output.
mk() {
  d="$(mktemp -d "${TMPDIR:-/tmp}/updgen.XXXXXX")"
  mkdir -p "$d/Fake.framework"
  cat > "$d/CMakeLists.txt" <<EOF
cmake_minimum_required(VERSION 3.16)
project(t LANGUAGES OBJC)
include("${SHARED}/MavericksSparkle.cmake")
mavericks_add_updater_app(
  NAME U BUNDLE_ID com.example.U FEED_URL http://x/appcast.xml
  CONFIRM_TITLE T CONFIRM_BODY B
  VERSION 1.0.0 ED_PUBKEY AAAA SPARKLE_FRAMEWORK "$d/Fake.framework"
  $1)
EOF
  run cmake -S "$d" -B "$d/b"
}

@test "add_updater_app: no ICON and no opt-in -> configure FATAL" {
  mk ""
  [ "$status" -ne 0 ] || { echo "$output"; rm -rf "$d"; return 1; }
  [[ "$output" == *"no ICON"* ]] || { echo "$output"; rm -rf "$d"; return 1; }
  rm -rf "$d"
}

@test "add_updater_app: ALLOW_GENERIC -> configures with an empty CFBundleIconFile" {
  mk "ALLOW_GENERIC"
  st=$status; out="$output"
  [ "$st" -eq 0 ] || { echo "$out"; rm -rf "$d"; return 1; }
  [[ "$out" == *"GENERIC macOS app icon"* ]] || { echo "$out"; rm -rf "$d"; return 1; }
  grep -A1 'CFBundleIconFile' "$d/b/U-Info.plist" | grep -q '<string></string>' \
    || { echo "CFBundleIconFile not empty:"; cat "$d/b/U-Info.plist"; rm -rf "$d"; return 1; }
  rm -rf "$d"
}
