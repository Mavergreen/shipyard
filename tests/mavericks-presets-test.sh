#!/bin/sh
# platform: CMake refuses to reconfigure a binaryDir last generated from a
#           different source path ("does not match the source ... used to
#           generate cache"), so two checkouts of one repo sharing one fixed
#           binaryDir break the second one's reconfigure.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
P="$root/mavericks-presets.json"
fails=0
say() { echo "FAIL: $1"; fails=$((fails+1)); }

if [ "$(grep -c '"binaryDir"' "$P" || true)" -ne 2 ]; then
  say "expected both hidden presets to declare binaryDir (a fixed default cannot tell two checkouts of the same repo apart)"
fi
if [ "$(grep -c '${sourceDirName}' "$P" || true)" -ne 2 ]; then
  say "expected both hidden presets' binaryDir to key off \${sourceDirName} so two checkouts do not collide"
fi
grep -q '"MAVERICKS_BUILD_ROOT": "\$penv{TMPDIR}/mm-build"' "$P" \
  || say "MAVERICKS_BUILD_ROOT is not defaulted to TMPDIR"

command -v cmake >/dev/null 2>&1 || { echo "SKIP: no cmake"; exit 77; }

# spec: SKILL.md "Build OUT of the source tree, onto fast local storage" --
#       a consumer's preset supplies neither binaryDir nor MAVERICKS_BUILD_ROOT,
#       it only inherits; this fixture must match that shape or the test
#       proves nothing about real consumers.
fixture() {  # $1 = directory to populate as a CMake source root
  mkdir -p "$1"
  printf 'cmake_minimum_required(VERSION 3.25)\nproject(t C)\n' > "$1/CMakeLists.txt"
  cp "$P" "$1/mavericks-presets.json"
  cat > "$1/CMakePresets.json" <<'JSON'
{ "version": 6,
  "cmakeMinimumRequired": { "major": 3, "minor": 25, "patch": 0 },
  "include": ["mavericks-presets.json"],
  "configurePresets": [
    { "name": "native", "inherits": "mavericks-native" },
    { "name": "cross", "inherits": "mavericks-cross" } ] }
JSON
}

check_cache_var() {  # $1=CMakeCache.txt $2=var $3=expected value $4=label
  grep -q "^$2:.*=$3\$" "$1" \
    || say "$4: $2 is not '$3' in $1"
}

work1="$(mktemp -d "${TMPDIR:-/tmp}/presets1.XXXXXX")"
work2="$(mktemp -d "${TMPDIR:-/tmp}/presets2.XXXXXX")"
b1="$(basename "$work1")"; b2="$(basename "$work2")"
bd1="${TMPDIR:-/tmp}/mm-build/${b1}-native"
bd2="${TMPDIR:-/tmp}/mm-build/${b2}-native"
bd1cross="${TMPDIR:-/tmp}/mm-build/${b1}-cross"
trap 'rm -rf "$work1" "$work2" "$bd1" "$bd2" "$bd1cross"' EXIT INT TERM

fixture "$work1"
fixture "$work2"

out1="$(cd "$work1" && cmake --preset native 2>&1)" \
  || say "checkout 1 does not configure: $out1"
if [ -e "$work1/CMakeCache.txt" ]; then say "checkout 1 configured INSIDE its own source tree"; fi

out2="$(cd "$work2" && cmake --preset native 2>&1)" \
  || say "checkout 2 does not configure: $out2"
if [ -e "$work2/CMakeCache.txt" ]; then say "checkout 2 configured INSIDE its own source tree"; fi

[ -f "$bd1/CMakeCache.txt" ] \
  || say "checkout 1 did not build at the \${sourceDirName}-derived path $bd1 -- binaryDir is not keying off the checkout's name"
[ -f "$bd2/CMakeCache.txt" ] \
  || say "checkout 2 did not build at the \${sourceDirName}-derived path $bd2 -- binaryDir is not keying off the checkout's name"
if [ "$bd1" = "$bd2" ]; then say "two different checkouts resolved to the SAME build directory"; fi

# platform: reconfiguring here catches the failure mode CMake would raise on
#           a collided binaryDir -- a cache left pointing at checkout 2's
#           source makes this call fail with "does not match the source
#           ... used to generate cache".
out1b="$(cd "$work1" && cmake --preset native 2>&1)" \
  || say "checkout 1 does not reconfigure after checkout 2 ran: $out1b"

out1cross="$(cd "$work1" && cmake --preset cross 2>&1)" \
  || say "checkout 1 does not configure the cross preset: $out1cross"
[ -f "$bd1cross/CMakeCache.txt" ] \
  || say "checkout 1's cross configure produced no CMakeCache.txt"

# platform: a guard here (`[ -f ... ] &&`) would skip these checks silently
#           if it ever failed, without touching $fails -- omit it on
#           purpose; existence was already asserted above.
check_cache_var "$bd1/CMakeCache.txt" MAVERICKS_EXPECTED_MODE native "mavericks-native"
check_cache_var "$bd1/CMakeCache.txt" CMAKE_OSX_DEPLOYMENT_TARGET 10.9 "mavericks-native"
check_cache_var "$bd1/CMakeCache.txt" CMAKE_OSX_ARCHITECTURES x86_64 "mavericks-native"
check_cache_var "$bd1cross/CMakeCache.txt" MAVERICKS_EXPECTED_MODE cross "mavericks-cross"
check_cache_var "$bd1cross/CMakeCache.txt" CMAKE_OSX_DEPLOYMENT_TARGET 10.9 "mavericks-cross"
check_cache_var "$bd1cross/CMakeCache.txt" CMAKE_OSX_ARCHITECTURES x86_64 "mavericks-cross"

[ "$fails" -eq 0 ] && echo "mavericks-presets: ok"
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
