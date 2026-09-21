#!/bin/sh
# The shared presets must not name a build directory inside the source tree, and
# their MAVERICKS_BUILD_ROOT default must actually resolve through `inherits`.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
P="$root/mavericks-presets.json"
fails=0
say() { echo "FAIL: $1"; fails=$((fails+1)); }

if grep -q '"binaryDir"' "$P"; then say "a shared hidden preset names a binaryDir; it cannot know the repo's name"; fi
grep -q '"MAVERICKS_BUILD_ROOT": "\$penv{TMPDIR}/mm-build"' "$P" \
  || say "MAVERICKS_BUILD_ROOT is not defaulted to TMPDIR"

command -v cmake >/dev/null 2>&1 || { echo "SKIP: no cmake"; exit 77; }
work="$(mktemp -d "${TMPDIR:-/tmp}/presets.XXXXXX")"
# MAVERICKS_BUILD_ROOT defaults to a FIXED path under TMPDIR (not one scoped to
# $work), so a leftover binaryDir from a prior run points at a source directory
# that no longer exists once $work is cleaned up -- CMake then refuses to
# reconfigure ("does not match the source ... used to generate cache"). Clean
# up the binaryDir alongside $work so repeated runs do not collide.
trap 'rm -rf "$work" "${TMPDIR:-/tmp}/mm-build/t-native"' EXIT INT TERM
rm -rf "${TMPDIR:-/tmp}/mm-build/t-native"
mkdir -p "$work/src"
printf 'cmake_minimum_required(VERSION 3.25)\nproject(t C)\n' > "$work/src/CMakeLists.txt"
cp "$P" "$work/src/mavericks-presets.json"
cat > "$work/src/CMakePresets.json" <<'JSON'
{ "version": 6,
  "cmakeMinimumRequired": { "major": 3, "minor": 25, "patch": 0 },
  "include": ["mavericks-presets.json"],
  "configurePresets": [
    { "name": "native", "inherits": "mavericks-native",
      "binaryDir": "$env{MAVERICKS_BUILD_ROOT}/t-native" } ] }
JSON
out="$(cd "$work/src" && cmake --preset native 2>&1)" \
  || say "the shared native preset does not configure: $out"
case "$out" in *"$work/src"*) say "configured INSIDE the source tree" ;; esac

[ "$fails" -eq 0 ] && echo "mavericks-presets: ok"
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
