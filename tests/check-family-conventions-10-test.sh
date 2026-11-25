#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib/conventions_fixture.sh"

REPO=Mavergreen/ed25519
sc="$work/sc"; cp -R "$here/../scripts" "$sc"; rm -f "$sc/conventions-grandfathered"
S2="$sc/check-family-conventions.sh"
grandfather() { printf '%s\n' "$@" | sort > "$sc/conventions-grandfathered"; }
gate() {  # $1 = dir
  (cd "$1" && GITHUB_REPOSITORY="$REPO" sh "$S2" 2>&1)
}
fails() {  # $1 = label, $2 = dir, $3 = phrase
  out="$(gate "$2")" && { echo "FAIL: $1 must fail"; exit 1; }
  printf '%s\n' "$out" | grep -qF -- "$3" || { echo "FAIL: $1 should fail with '$3': $out"; exit 1; }
}
passes() {  # $1 = label, $2 = dir
  out="$(gate "$2")" || { echo "FAIL: $1 must pass: $out"; exit 1; }
}
add() { (cd "$1" && git add -A) >/dev/null 2>&1; }
mkrepo9() { mkrepo "$1"; printf '# Build ingredients\n' > "$1/INGREDIENTS.md"; printf 'CMakeUserPresets.json\n' >> "$1/.gitignore"; }
with() {  # $1 = label, $2 = tracked path, $3 = its content
  d="$work/rn-$1"; mkrepo9 "$d"; mkdir -p "$d/$(dirname "$2")"
  printf '%s\n' "$3" > "$d/$2"; add "$d"
}

# spec: SKILL.md "Family conventions" check 41 -- what the unified-toolchains release removed or
#       renamed is refused by name, with its replacement, so a consumer still comparing the build
#       mode against the old values fails here instead of building the wrong way.
grandfather
passes "check 41: the baseline" "$work/ok"

with ed25519 build/build-tools.sh 'if [ "$(sh "$SCRIPTS/mavericks_mode.sh")" != cross ]; then
  :
fi'
fails "check 41: ed25519's != cross" "$work/rn-ed25519" 'toolchain-names build/build-tools.sh'
fails "check 41: names the new mode values" "$work/rn-ed25519" "mavericks"
fails "check 41: names the new mode values" "$work/rn-ed25519" "modern"

with codex CMakeLists.txt 'if(MAVERICKS_MODE STREQUAL "cross")
endif()'
fails "check 41: codex's STREQUAL \"cross\"" "$work/rn-codex" 'toolchain-names CMakeLists.txt'

with gh build/build-updater.sh 'arm=""; [ "$(sh "$SHIPYARD_SCRIPTS/mavericks_mode.sh")" = native ] || arm="--arch arm64"'
fails "check 41: = native" "$work/rn-gh" 'toolchain-names build/build-updater.sh'

with caselist build/mode.sh 'case "$MAVERICKS_MODE" in native|cross|linux) echo "$MAVERICKS_MODE" ;; esac'
fails "check 41: a case list naming the old values" "$work/rn-caselist" 'toolchain-names build/mode.sh'

with quoted cmake/x.cmake 'if(mavericks_mode STREQUAL '"'"'native'"'"')'
fails "check 41: a quoted 'native'" "$work/rn-quoted" 'toolchain-names cmake/x.cmake'

with require CMakeLists.txt 'mavericks_require_expected_mode()'
fails "check 41: mavericks_require_expected_mode" "$work/rn-require" 'toolchain-names CMakeLists.txt'
fails "check 41: says to delete the call" "$work/rn-require" 'delete the call'

with expected CMakePresets.json '{"configurePresets":[{"name":"x","cacheVariables":{"MAVERICKS_EXPECTED_MODE":"native"}}]}'
fails "check 41: MAVERICKS_EXPECTED_MODE in a preset" "$work/rn-expected" 'toolchain-names CMakePresets.json'

with inherits CMakePresets.json '{"configurePresets":[{"name":"x","inherits":"mavericks-native"}]}'
fails "check 41: a preset inheriting mavericks-native" "$work/rn-inherits" 'toolchain-names CMakePresets.json'
fails "check 41: names the new presets" "$work/rn-inherits" 'mavericks-x86_64'
fails "check 41: names the new presets" "$work/rn-inherits" 'macos-arm64'

with workflow .github/workflows/ci.yml 'name: ci
on: push
jobs:
  b:
    runs-on: ubuntu-latest
    steps:
      - run: shipyard-cmake --preset mavericks-cross'
fails "check 41: a workflow naming mavericks-cross" "$work/rn-workflow" 'toolchain-names .github/workflows/ci.yml'

with newvals CMakeLists.txt 'if(MAVERICKS_MODE STREQUAL "modern")
  message(STATUS "MAVERICKS_MODE=${MAVERICKS_MODE}: building native tools for cross-compiling")
endif()'
passes "check 41: the new values, and prose about native tools" "$work/rn-newvals"

with newpresets CMakePresets.json '{"configurePresets":[{"name":"x","inherits":"mavericks-x86_64"},{"name":"y","inherits":"macos-arm64"},{"name":"z","inherits":"mavericks-cross-ish"}]}'
passes "check 41: the new presets, and a longer name" "$work/rn-newpresets"

with unrelated build/b.sh 'CROSS=cross; MODE=native; [ "$MODE" = native ] && echo "$CROSS"'
passes "check 41: native and cross away from the mode" "$work/rn-unrelated"

with comment build/c.sh '# MAVERICKS_MODE was native or cross; mavericks_require_expected_mode() is gone
echo ok  # inherits mavericks-native once'
passes "check 41: comments" "$work/rn-comment"

with tests tests/old-test.sh 'grep -q MAVERICKS_EXPECTED_MODE x; [ "$MAVERICKS_MODE" != cross ]'
passes "check 41: tests/ may assert the old names are gone" "$work/rn-tests"

with dev build/build-tools.sh 'if [ "$(sh "$SCRIPTS/mavericks_mode.sh")" != cross ]; then :; fi'
printf '\n## Conformance deviations\n\n- toolchain-names:build/build-tools.sh: the fixture, exit never\n' >> "$work/rn-dev/INGREDIENTS.md"
add "$work/rn-dev"
passes "check 41: a toolchain-names deviation" "$work/rn-dev"

with gf build/build-tools.sh 'if [ "$(sh "$SCRIPTS/mavericks_mode.sh")" != cross ]; then :; fi'
grandfather "toolchain-names ed25519 build/build-tools.sh"
passes "check 41: a grandfathered path" "$work/rn-gf"
grandfather "toolchain-names ed25519 build/other.sh"
fails "check 41: another path's grandfathered line" "$work/rn-gf" 'toolchain-names build/build-tools.sh'
grandfather

echo "PASS: check-family-conventions-10"
