#!/usr/bin/env bats
# platform: host-agnostic
SHARED="${BATS_TEST_DIRNAME}/.."
. "$SHARED/tests/lib/objc-cmake-args.sh"

setup() {
  objc_cmake_args "$SHARED"
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
  objc_cmake -S "$d" -B "$d/b" -DV="$1" >/dev/null && "$CMAKE" --build "$d/b"
}

key() { grep -A1 "<key>$1</key>" "$d/b/openssh-updater.app/Contents/Info.plist" | sed -n 's|.*<string>\(.*\)</string>.*|\1|p'; }

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
