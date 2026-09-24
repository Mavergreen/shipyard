#!/usr/bin/env bats
# platform: host-agnostic
# mavericks_require_icon: forced icon decision (FATAL unless real .icns or explicit generic).
SHARED="${BATS_TEST_DIRNAME}/.."

# Configure a tiny project whose CMakeLists calls mavericks_require_icon with $1 (extra args).
# Echoes cmake's combined output; status reflects configure success/failure.
try_icon() {  # $1 = the require-icon args line; $2 (optional) = extra -D flags
  d="$(mktemp -d "${TMPDIR:-/tmp}/reqicon.XXXXXX")"
  cat > "$d/CMakeLists.txt" <<EOF
cmake_minimum_required(VERSION 3.16)
project(t LANGUAGES NONE)
include("${SHARED}/MavericksDecisions.cmake")
add_custom_target(app)
mavericks_require_icon($1)
EOF
  run cmake ${2:-} -S "$d" -B "$d/b"
  rm -rf "$d"
}

@test "require_icon: no decision -> configure FATAL" {
  try_icon "TARGET app"
  [ "$status" -ne 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"no icon decided"* ]] || return 1
}

@test "require_icon: explicit ALLOW_GENERIC -> configures" {
  try_icon "TARGET app ALLOW_GENERIC"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"GENERIC icon by explicit opt-in"* ]] || return 1
}

@test "require_icon: -DMAVERICKS_ALLOW_GENERIC_ICON=ON -> configures" {
  try_icon "TARGET app" "-DMAVERICKS_ALLOW_GENERIC_ICON=ON"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "require_icon: ICNS that exists -> configures + wires it" {
  d="$(mktemp -d "${TMPDIR:-/tmp}/reqicns.XXXXXX")"; : > "$d/AppIcon.icns"
  cat > "$d/CMakeLists.txt" <<EOF
cmake_minimum_required(VERSION 3.16)
project(t LANGUAGES NONE)
include("${SHARED}/MavericksDecisions.cmake")
add_custom_target(app)
mavericks_require_icon(TARGET app ICNS "$d/AppIcon.icns")
EOF
  run cmake -S "$d" -B "$d/b"
  st=$status; out="$output"; rm -rf "$d"
  [ "$st" -eq 0 ] || { echo "$out"; return 1; }
  [[ "$out" == *"ships app icon AppIcon.icns"* ]] || return 1
}

@test "require_icon: ICNS declared but MISSING -> configure FATAL" {
  try_icon "TARGET app ICNS /no/such/AppIcon.icns"
  [ "$status" -ne 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"Refusing to build"* ]] || return 1
}

@test "require_icon: a denylisted PLACEHOLDER icns -> configure FATAL" {
  d="$(mktemp -d "${TMPDIR:-/tmp}/reqph.XXXXXX")"; printf 'solid-fill placeholder\n' > "$d/AppIcon.icns"
  h="$(shasum -a 256 "$d/AppIcon.icns" | awk '{print $1}')"
  printf '%s  # test placeholder\n' "$h" > "$d/deny.sha256"
  cat > "$d/CMakeLists.txt" <<EOF
cmake_minimum_required(VERSION 3.16)
project(t LANGUAGES NONE)
include("${SHARED}/MavericksDecisions.cmake")
add_custom_target(app)
mavericks_require_icon(TARGET app ICNS "$d/AppIcon.icns")
EOF
  run cmake -DMAVERICKS_PLACEHOLDER_DENYLIST="$d/deny.sha256" -S "$d" -B "$d/b"
  st=$status; out="$output"; rm -rf "$d"
  [ "$st" -ne 0 ] || { echo "$out"; return 1; }
  [[ "$out" == *"PLACEHOLDER"* ]] || { echo "$out"; return 1; }
}

@test "require_icon: denylisted placeholder + MAVERICKS_ALLOW_GENERIC_ICON -> configures" {
  d="$(mktemp -d "${TMPDIR:-/tmp}/reqpha.XXXXXX")"; printf 'solid-fill placeholder\n' > "$d/AppIcon.icns"
  h="$(shasum -a 256 "$d/AppIcon.icns" | awk '{print $1}')"
  printf '%s\n' "$h" > "$d/deny.sha256"
  cat > "$d/CMakeLists.txt" <<EOF
cmake_minimum_required(VERSION 3.16)
project(t LANGUAGES NONE)
include("${SHARED}/MavericksDecisions.cmake")
add_custom_target(app)
mavericks_require_icon(TARGET app ICNS "$d/AppIcon.icns")
EOF
  run cmake -DMAVERICKS_PLACEHOLDER_DENYLIST="$d/deny.sha256" -DMAVERICKS_ALLOW_GENERIC_ICON=ON -S "$d" -B "$d/b"
  st=$status; out="$output"; rm -rf "$d"
  [ "$st" -eq 0 ] || { echo "$out"; return 1; }
}
