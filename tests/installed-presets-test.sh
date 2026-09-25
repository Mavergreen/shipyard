#!/bin/sh
# platform: host-agnostic
# platform: CMake expands a preset's ${fileDir} against the file of the preset being CONFIGURED, not
#           the file that wrote the macro -- so an inherited "${fileDir}/MavericksToolchain.cmake"
#           names the CONSUMER's directory ("Could not find toolchain file: <consumer>/..."; CMake
#           3.28 and 4.4.3). The installed presets must name the installed toolchain file absolutely.
# platform: `cmake --install --prefix` replaces the configured prefix only at install time, and
#           DESTDIR moves only where files land -- so the path is baked at install time, following
#           --prefix (a developer's install) and leaving DESTDIR out (a pkg stage is not the prefix).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
cm="$(command -v shipyard-cmake 2>/dev/null || command -v cmake 2>/dev/null || true)"
[ -n "$cm" ] || { echo "SKIP: no cmake"; exit 77; }

# platform: macOS sets TMPDIR with a trailing slash; strip it so the paths compared below are the
#           ones cmake writes back.
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/installed-presets.XXXXXX")"
trap 'rm -rf "$w"' EXIT INT TERM
fails=0
say() { echo "FAIL: $1"; fails=$((fails+1)); }
rel=share/cmake/MavericksShipyard

"$cm" -S "$root" -B "$w/build" > "$w/configure.log" 2>&1 \
  || { echo "FAIL: shipyard does not configure"; sed 's/^/    | /' "$w/configure.log"; exit 1; }
"$cm" --install "$w/build" --prefix "$w/A" > "$w/install-A.log" 2>&1 \
  || { echo "FAIL: cmake --install --prefix fails"; sed 's/^/    | /' "$w/install-A.log"; exit 1; }
# platform: every install rewrites the build dir's install_manifest.txt, so read it before the next.
grep -qxF "$w/A/$rel/mavericks-presets.json" "$w/build/install_manifest.txt" 2>/dev/null \
  || say "--prefix: install_manifest.txt does not list the presets file, so an uninstall would leave it behind"
DESTDIR="$w/D" "$cm" --install "$w/build" --prefix "$w/B" > "$w/install-B.log" 2>&1 \
  || { echo "FAIL: DESTDIR= cmake --install --prefix fails"; sed 's/^/    | /' "$w/install-B.log"; exit 1; }

toolchains() {  # $1 = an installed mavericks-presets.json; prints each toolchainFile value
  sed -n 's/^[[:space:]]*"toolchainFile":[[:space:]]*"\([^"]*\)".*/\1/p' "$1"
}
check_install() {  # $1 = label  $2 = the installed presets file  $3 = the prefix it must name
  [ -f "$2" ] || { say "$1: no presets file at $2"; return 0; }
  want="$3/$rel/MavericksToolchain.cmake"
  n="$(toolchains "$2" | wc -l | tr -d ' ')"
  [ "$n" -eq 2 ] || say "$1: expected both hidden presets to set toolchainFile; found $n"
  toolchains "$2" | while IFS= read -r got; do
    [ "$got" = "$want" ] || echo "$1: toolchainFile is '$got', not the installed '$want'"
  done > "$w/mismatch"
  if [ -s "$w/mismatch" ]; then say "$(cat "$w/mismatch")"; fi
  if grep -q 'fileDir' "$2"; then say "$1: the installed presets still carry \${fileDir}"; fi
}
check_install "--prefix" "$w/A/$rel/mavericks-presets.json" "$w/A"
[ -f "$w/A/$rel/MavericksToolchain.cmake" ] \
  || say "--prefix: the toolchain file the presets name is not installed at $w/A/$rel"

check_install "DESTDIR" "$w/D$w/B/$rel/mavericks-presets.json" "$w/B"
if grep -qF "$w/D" "$w/D$w/B/$rel/mavericks-presets.json" 2>/dev/null; then
  say "DESTDIR: the staging root leaked into the installed presets; the pkg stage is not where they install"
fi
[ -f "$w/D$w/B/$rel/MavericksToolchain.cmake" ] \
  || say "DESTDIR: the toolchain file is not staged beside the presets at $w/D$w/B/$rel"

# spec: SKILL.md "Build OUT of the source tree, onto fast local storage" -- the consumer lives in
#       ANOTHER directory and only includes and inherits, exactly as README.md shows; a fixture beside
#       the presets file would hide the bug, since there both fileDirs are one directory.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the
#       toolchain file really runs here (Linux included): it fetches the pinned SDK, so a fake cached
#       one keeps this offline, and the fixture enables no language, since a compiler check would
#       link against that empty SDK.
mkdir -p "$w/consumer" "$w/sdk/MacOSX10.9.sdk/usr/lib"
printf 'cmake_minimum_required(VERSION 3.25)\nproject(t NONE)\n' > "$w/consumer/CMakeLists.txt"
cat > "$w/consumer/CMakePresets.json" <<JSON
{ "version": 6,
  "cmakeMinimumRequired": { "major": 3, "minor": 25, "patch": 0 },
  "include": ["$w/A/$rel/mavericks-presets.json"],
  "configurePresets": [ { "name": "cross", "inherits": "mavericks-cross" } ] }
JSON
out="$(cd "$w/consumer" && TMPDIR="$w" MAVERICKS_SDK_CACHE="$w/sdk" "$cm" --preset cross 2>&1)" \
  || say "a consumer inheriting mavericks-cross does not configure: $out"
case "$out" in
  *"Could not find toolchain file"*) say "the consumer's toolchain file did not resolve: $out" ;;
esac
cache="$w/mm-build/consumer-cross/CMakeCache.txt"
grep -qxF "CMAKE_TOOLCHAIN_FILE:FILEPATH=$w/A/$rel/MavericksToolchain.cmake" "$cache" 2>/dev/null \
  || say "the consumer's CMAKE_TOOLCHAIN_FILE is not the installed toolchain file: $(grep '^CMAKE_TOOLCHAIN_FILE' "$cache" 2>/dev/null || echo "no $cache")"

[ "$fails" -eq 0 ] && echo "installed-presets: ok"
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
