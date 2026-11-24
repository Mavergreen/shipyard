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

if [ "$(grep -c '"binaryDir"' "$P" || true)" -ne 3 ]; then
  say "expected all three hidden presets to declare binaryDir (a fixed default cannot tell two checkouts of the same repo apart)"
fi
if [ "$(grep -c '${sourceDirName}' "$P" || true)" -ne 3 ]; then
  say "expected all three hidden presets' binaryDir to key off \${sourceDirName} so two checkouts do not collide"
fi
grep -q '"MAVERICKS_BUILD_ROOT": "\$penv{TMPDIR}/mm-build"' "$P" \
  || say "MAVERICKS_BUILD_ROOT is not defaulted to TMPDIR"
# spec: tests/installed-presets-test.sh -- the source's toolchainFile is the token the install
#       replaces with the installed toolchain file's absolute path; that test checks the result.
[ "$(grep -c '"toolchainFile": "${fileDir}/MavericksToolchain.cmake"' "$P" || true)" -eq 3 ] \
  || say "all three hidden presets must carry \${fileDir}/MavericksToolchain.cmake, the token the install replaces, so a consumer's preset pins the SDK by inheriting"

command -v cmake >/dev/null 2>&1 || { echo "SKIP: no cmake"; exit 77; }

# spec: SKILL.md "Build OUT of the source tree, onto fast local storage" --
#       a consumer's preset supplies neither binaryDir nor MAVERICKS_BUILD_ROOT,
#       it only inherits; this fixture must match that shape or the test
#       proves nothing about real consumers.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the
#       toolchain file FORCE-sets CMAKE_OSX_SYSROOT to the pinned SDK, which here is an EMPTY fake;
#       a language would make CMake's compiler check link against it and fail, so the fixture
#       enables none (NONE still runs the toolchain file and writes its cache variables).
# platform: the fixture includes an INSTALLED shipyard's presets from its own, different directory,
#           as README.md shows consumers doing. A copy of the presets beside the fixture hid a
#           released bug: CMake expands an inherited ${fileDir} against the CONSUMER's file, and
#           there the two directories were one.
fixture() {  # $1 = directory to populate as a CMake source root
  mkdir -p "$1"
  printf 'cmake_minimum_required(VERSION 3.25)\nproject(t NONE)\n' > "$1/CMakeLists.txt"
  cat > "$1/CMakePresets.json" <<JSON
{ "version": 6,
  "cmakeMinimumRequired": { "major": 3, "minor": 25, "patch": 0 },
  "include": ["$installed/mavericks-presets.json"],
  "configurePresets": [
    { "name": "native", "inherits": "mavericks-native" },
    { "name": "cross", "inherits": "mavericks-cross" },
    { "name": "arm64", "inherits": "macos-arm64" } ] }
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
bd1arm="${TMPDIR:-/tmp}/mm-build/${b1}-arm64"
bd1arm_notmp="/tmp/mm-build/${b1}-arm64"

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- both
#       presets' toolchainFile now runs on every configure below and fetches the pinned SDK;
#       pre-seed a fake cached SDK and point fetch_sdk.sh at it, so this test stays offline (both
#       presets pin CMAKE_OSX_ARCHITECTURES x86_64, so only that SDK is needed).
# platform: macOS sets TMPDIR with a trailing slash, and cmake normalizes "//" away in the
#           CMAKE_OSX_SYSROOT it caches -- so an unstripped slash here would make the
#           check_cache_var comparison below fail on every real macOS session while looking fine
#           here with TMPDIR unset.
_tmp="${TMPDIR:-/tmp}"
work3="$(mktemp -d "${_tmp%/}/presets-sdkcache.XXXXXX")"
mkdir -p "$work3/MacOSX10.9.sdk/usr/lib" "$work3/MacOSX11.3.sdk/usr/lib"
MAVERICKS_SDK_CACHE="$work3"; export MAVERICKS_SDK_CACHE

work4="$(mktemp -d "${_tmp%/}/presets-shipyard.XXXXXX")"
trap 'rm -rf "$work1" "$work2" "$work3" "$work4" "$bd1" "$bd2" "$bd1cross" "$bd1arm" "$bd1arm_notmp"' EXIT INT TERM
cmake -S "$root" -B "$work4/build" > "$work4/install.log" 2>&1 \
  && cmake --install "$work4/build" --prefix "$work4/prefix" >> "$work4/install.log" 2>&1 \
  || { echo "FAIL: shipyard does not install"; sed 's/^/    | /' "$work4/install.log"; exit 1; }
installed="$work4/prefix/share/cmake/MavericksShipyard"
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

# spec: MavericksToolchain.cmake -- a 10.9 host builds x86_64 only, so the arm64 preset is exercised
#       on modern hosts and Linux; no preset name or displayName for it says "cross".
if command grep -A2 '"name": "macos-arm64"' "$P" | command grep -qi cross; then
  say "macos-arm64's name or displayName says cross"
fi
if command grep -q '"displayName": "arm64: macOS 11.0, any host"' "$P"; then :; else
  say "macos-arm64's displayName is not 'arm64: macOS 11.0, any host'"
fi
if [ "$(sh "$root/scripts/mavericks_mode.sh")" = native ]; then
  echo "SKIP: arm64 preset cases (a 10.9 host builds x86_64 only)"
else
  sdk11="$work3/MacOSX11.3.sdk"
  [ "$(sh "$root/scripts/fetch_sdk.sh" --arch arm64)" = "$sdk11" ] \
    || say "fetch_sdk.sh --arch arm64 does not print the seeded $sdk11"
  out1arm="$(cd "$work1" && cmake --preset arm64 2>&1)" \
    || say "checkout 1 does not configure the arm64 preset: $out1arm"
  [ -f "$bd1arm/CMakeCache.txt" ] \
    || say "checkout 1's arm64 configure produced no CMakeCache.txt at $bd1arm"
  check_cache_var "$bd1arm/CMakeCache.txt" CMAKE_OSX_ARCHITECTURES arm64 "macos-arm64"
  check_cache_var "$bd1arm/CMakeCache.txt" CMAKE_OSX_DEPLOYMENT_TARGET 11.0 "macos-arm64"
  check_cache_var "$bd1arm/CMakeCache.txt" CMAKE_OSX_SYSROOT "$sdk11" "macos-arm64"
  # spec: MavericksMode.cmake -- "modern" is the arm64 preset's expected mode: any host that is not
  #       10.9. It passes the guard here and still fails a host that is the other kind.
  guard() { cmake -DEXP="$1" -P "$work4/guard.cmake" >/dev/null 2>&1; }
  printf 'set(APPLE 1)\nlist(APPEND CMAKE_MODULE_PATH "%s")\nset(MAVERICKS_EXPECTED_MODE "${EXP}")\ninclude(MavericksMode)\n' "$root" > "$work4/guard.cmake"
  guard modern || say "MAVERICKS_EXPECTED_MODE modern is refused on a modern host"
  if guard native; then say "MAVERICKS_EXPECTED_MODE native is accepted on a modern host"; fi
  # platform: presets cannot default $penv{TMPDIR} (no fallback syntax), so an unset TMPDIR makes
  #           the build root /mm-build; the launcher is the supported entry point there, and
  #           exports /tmp.
  rm -rf "$bd1arm"
  out1arm2="$(cd "$work1" && env -u TMPDIR "$work4/prefix/bin/shipyard-cmake" --preset arm64 2>&1)" \
    || say "shipyard-cmake --preset arm64 with TMPDIR unset does not configure: $out1arm2"
  [ -f "$bd1arm_notmp/CMakeCache.txt" ] \
    || say "shipyard-cmake with TMPDIR unset did not build under /tmp/mm-build ($bd1arm_notmp)"
fi

[ "$fails" -eq 0 ] && echo "mavericks-presets: ok"
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
