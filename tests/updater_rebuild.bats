#!/usr/bin/env bats
# platform: macOS-only -- builds the Objective-C updater against AppKit and the pinned Sparkle
SHARED="${BATS_TEST_DIRNAME}/.."

setup() {
  SC="${SHIPYARD_CMAKE:-$(command -v shipyard-cmake 2>/dev/null || true)}"
  [ -n "$SC" ] || skip "no shipyard-cmake (install the shipyard pkg, or set SHIPYARD_CMAKE)"
  d="$BATS_TEST_TMPDIR/p"
  mkdir -p "$d"
  cat > "$d/CMakeLists.txt" <<EOF
cmake_minimum_required(VERSION 3.16)
project(t LANGUAGES OBJC)
include("${SHARED}/MavericksSparkle.cmake")
mavericks_add_updater_app(
  PRODUCT openssh
  CONFIRM_TITLE T CONFIRM_BODY B
  VERSION \${V} ED_PUBKEY AAAA ALLOW_GENERIC)
EOF
}

build_at() {
  "$SC" -S "$d" -B "$d/b" -DV="$1" >/dev/null && "$SC" --build "$d/b"
}

key() { /usr/libexec/PlistBuddy -c "Print :$1" "$d/b/openssh-updater.app/Contents/Info.plist"; }

@test "add_updater_app: a rebuild at a new VERSION in the same build dir gives the app that version" {
  run build_at 9.9p2-mavericks.1
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(key CFBundleShortVersionString)" = 9.9p2-mavericks.1 ]
  run build_at 9.9p2-mavericks.2
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(key CFBundleShortVersionString)" = 9.9p2-mavericks.2 ] || { key CFBundleShortVersionString; return 1; }
  [ "$(key CFBundleVersion)" = 9.9.2.2 ] || { key CFBundleVersion; return 1; }
  cmp "$d/b/openssh-updater-Info.plist" "$d/b/openssh-updater.app/Contents/Info.plist"
}
