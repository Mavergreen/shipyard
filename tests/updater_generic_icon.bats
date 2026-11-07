#!/usr/bin/env bats
# platform: host-agnostic
SHARED="${BATS_TEST_DIRNAME}/.."
. "$SHARED/tests/lib/objc-cmake-args.sh"

mk() {
  d="$(mktemp -d "${TMPDIR:-/tmp}/updgen.XXXXXX")"
  mkdir -p "$d/Fake.framework"
  if [ -z "${MK_UNDECLARED:-}" ]; then mkdir -p "$d/.mavergreen/products/$1"; echo "$1" > "$d/.mavergreen/products/$1/noun"; fi
  cat > "$d/CMakeLists.txt" <<EOF
cmake_minimum_required(VERSION 3.16)
project(t LANGUAGES OBJC)
include("${SHARED}/MavericksSparkle.cmake")
mavericks_add_updater_app(
  PRODUCT $1
  CONFIRM_TITLE T CONFIRM_BODY B
  VERSION 1.0.0 ED_PUBKEY AAAA SPARKLE_FRAMEWORK "$d/Fake.framework"
  $2)
${3:-}
EOF
  objc_cmake_args "$SHARED"
  export GITHUB_REPOSITORY="${MK_REPO-Mavergreen/openssh}"
  run objc_cmake -S "$d" -B "$d/b"
}

@test "add_updater_app: no ICON and no opt-in -> configure FATAL" {
  mk openssh ""
  [ "$status" -ne 0 ] || { echo "$output"; rm -rf "$d"; return 1; }
  [[ "$output" == *"no ICON"* ]] || { echo "$output"; rm -rf "$d"; return 1; }
  rm -rf "$d"
}

@test "add_updater_app: ALLOW_GENERIC -> configures with an empty CFBundleIconFile" {
  mk openssh "ALLOW_GENERIC"
  st=$status; out="$output"
  [ "$st" -eq 0 ] || { echo "$out"; rm -rf "$d"; return 1; }
  [[ "$out" == *"GENERIC macOS app icon"* ]] || { echo "$out"; rm -rf "$d"; return 1; }
  grep -A1 'CFBundleIconFile' "$d/b/openssh-updater-Info.plist" | grep -q '<string></string>' \
    || { echo "CFBundleIconFile not empty:"; cat "$d/b/openssh-updater-Info.plist"; rm -rf "$d"; return 1; }
  rm -rf "$d"
}

@test "add_updater_app: the name, bundle id and feed are derived from PRODUCT" {
  mk openssh "ALLOW_GENERIC"
  [ "$status" -eq 0 ] || { echo "$output"; rm -rf "$d"; return 1; }
  p="$d/b/openssh-updater-Info.plist"
  grep -A1 CFBundleExecutable "$p" | grep -q '<string>openssh-updater</string>' \
    || { cat "$p"; rm -rf "$d"; return 1; }
  grep -A1 CFBundleIdentifier "$p" | grep -q '<string>dev.mavergreen.openssh.updater</string>' \
    || { cat "$p"; rm -rf "$d"; return 1; }
  grep -A1 SUFeedURL "$p" | grep -q '<string>https://github.com/Mavergreen/openssh/releases/latest/download/openssh.xml</string>' \
    || { cat "$p"; rm -rf "$d"; return 1; }
  rm -rf "$d"
}

@test "add_updater_app: the target and bundle id are published to the caller, for product code that names the updater" {
  mk go126 "ALLOW_GENERIC" 'message(STATUS "updater=[${MAVERICKS_UPDATER_TARGET}] id=[${MAVERICKS_UPDATER_BUNDLE_ID}]")'
  [ "$status" -eq 0 ] || { echo "$output"; rm -rf "$d"; return 1; }
  [[ "$output" == *"updater=[go126-updater] id=[dev.mavergreen.go126.updater]"* ]] || { echo "$output"; rm -rf "$d"; return 1; }
  rm -rf "$d"
}

@test "add_updater_app: NAME, BUNDLE_ID and FEED_URL are refused -- they are derived" {
  for a in "NAME U" "BUNDLE_ID com.example.U" "FEED_URL http://x/appcast.xml"; do
    mk openssh "ALLOW_GENERIC $a"
    [ "$status" -ne 0 ] || { echo "$a was accepted: $output"; rm -rf "$d"; return 1; }
    [[ "$output" == *"derived from PRODUCT"* ]] || { echo "$output"; rm -rf "$d"; return 1; }
    rm -rf "$d"
  done
}

@test "add_updater_app: a PRODUCT the repo does not declare is refused" {
  MK_UNDECLARED=1 mk no-such-product "ALLOW_GENERIC"
  [ "$status" -ne 0 ] || { echo "$output"; rm -rf "$d"; return 1; }
  [[ "$output" == *".mavergreen/products/no-such-product/"* ]] || { echo "$output"; rm -rf "$d"; return 1; }
  rm -rf "$d"
}

@test "add_updater_app: a feed whose repo cannot be learned is refused, naming the product" {
  MK_REPO= mk openssh "ALLOW_GENERIC"
  [ "$status" -ne 0 ] || { echo "$output"; rm -rf "$d"; return 1; }
  [[ "$output" == *"PRODUCT 'openssh'"* ]] || { echo "$output"; rm -rf "$d"; return 1; }
  [[ "$output" == *"GITHUB_REPOSITORY"* ]] || { echo "$output"; rm -rf "$d"; return 1; }
  rm -rf "$d"
}
