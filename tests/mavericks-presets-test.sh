#!/bin/sh
# platform: host-agnostic
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
[ "$(grep -c '"toolchainFile": "${fileDir}/MavericksToolchain.cmake"' "$P" || true)" -eq 2 ] \
  || say "both hidden presets must use \${fileDir}/MavericksToolchain.cmake, so a consumer's preset pins the SDK by inheriting"

command -v cmake >/dev/null 2>&1 || { echo "SKIP: no cmake"; exit 77; }

# spec: SKILL.md "Build OUT of the source tree, onto fast local storage" --
#       a consumer's preset supplies neither binaryDir nor MAVERICKS_BUILD_ROOT,
#       it only inherits; this fixture must match that shape or the test
#       proves nothing about real consumers.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the
#       toolchain file FORCE-sets CMAKE_OSX_SYSROOT to the pinned SDK, which here is an EMPTY fake;
#       a language would make CMake's compiler check link against it and fail, so the fixture
#       enables none (NONE still runs the toolchain file and writes its cache variables).
# spec: mavericks-presets.json's "toolchainFile" is "${fileDir}/MavericksToolchain.cmake" -- ${fileDir}
#       is the directory of the preset FILE that sets it (the fixture's own copy of
#       mavericks-presets.json), so the fixture needs its own copy of the toolchain file and the
#       scripts/ it shells out to, next to it -- exactly how an installed share dir holds them.
fixture() {  # $1 = directory to populate as a CMake source root
  mkdir -p "$1"
  printf 'cmake_minimum_required(VERSION 3.25)\nproject(t NONE)\n' > "$1/CMakeLists.txt"
  cp "$P" "$1/mavericks-presets.json"
  cp "$root/MavericksToolchain.cmake" "$1/MavericksToolchain.cmake"
  cp -R "$root/scripts" "$1/scripts"
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

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- both
#       presets' toolchainFile now runs on every configure below and fetches the pinned SDK;
#       pre-seed a fake cached SDK and point fetch_sdk.sh at it, so this test stays offline (both
#       presets pin CMAKE_OSX_ARCHITECTURES x86_64, so only that SDK is needed).
work3="$(mktemp -d "${TMPDIR:-/tmp}/presets-sdkcache.XXXXXX")"
mkdir -p "$work3/MacOSX10.9.sdk/usr/lib"
MAVERICKS_SDK_CACHE="$work3"; export MAVERICKS_SDK_CACHE

trap 'rm -rf "$work1" "$work2" "$work3" "$bd1" "$bd2" "$bd1cross"' EXIT INT TERM
sdk="$work3/MacOSX10.9.sdk"

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
check_cache_var "$bd1/CMakeCache.txt" CMAKE_OSX_SYSROOT "$sdk" "mavericks-native"
check_cache_var "$bd1cross/CMakeCache.txt" MAVERICKS_EXPECTED_MODE cross "mavericks-cross"
check_cache_var "$bd1cross/CMakeCache.txt" CMAKE_OSX_DEPLOYMENT_TARGET 10.9 "mavericks-cross"
check_cache_var "$bd1cross/CMakeCache.txt" CMAKE_OSX_ARCHITECTURES x86_64 "mavericks-cross"
check_cache_var "$bd1cross/CMakeCache.txt" CMAKE_OSX_SYSROOT "$sdk" "mavericks-cross"

[ "$fails" -eq 0 ] && echo "mavericks-presets: ok"
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
