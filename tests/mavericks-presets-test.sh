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
# spec: tests/installed-presets-test.sh -- the source's toolchainFile is the token the install
#       replaces with the installed toolchain file's absolute path; that test checks the result.
[ "$(grep -c '"toolchainFile": "${fileDir}/MavericksToolchain.cmake"' "$P" || true)" -eq 2 ] \
  || say "both hidden presets must carry \${fileDir}/MavericksToolchain.cmake, the token the install replaces, so a consumer's preset pins the SDK by inheriting"
[ "$(command grep -Eci 'native|cross|EXPECTED_MODE' "$P" || true)" -eq 0 ] \
  || say "mavericks-presets.json still says native, cross or EXPECTED_MODE: $(command grep -Ein 'native|cross|EXPECTED_MODE' "$P")"
if grep -q '"displayName": "x86_64: Mac OS X 10.9, any host"' "$P"; then :; else
  say "mavericks-x86_64's displayName is not 'x86_64: Mac OS X 10.9, any host'"
fi
if grep -q '"displayName": "arm64: macOS 11.0, any host"' "$P"; then :; else
  say "macos-arm64's displayName is not 'arm64: macOS 11.0, any host'"
fi

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
fixture() {  # $1 = directory to populate as a CMake source root  $2 = its configurePresets
  mkdir -p "$1"
  printf 'cmake_minimum_required(VERSION 3.25)\nproject(t NONE)\n' > "$1/CMakeLists.txt"
  cat > "$1/CMakePresets.json" <<JSON
{ "version": 6,
  "cmakeMinimumRequired": { "major": 3, "minor": 25, "patch": 0 },
  "include": ["$installed/mavericks-presets.json"],
  "configurePresets": [ $2 ] }
JSON
}
consumer='{ "name": "x86_64", "inherits": "mavericks-x86_64" }, { "name": "arm64", "inherits": "macos-arm64" }'

check_cache_var() {  # $1=CMakeCache.txt $2=var $3=expected value $4=label
  grep -q "^$2:.*=$3\$" "$1" \
    || say "$4: $2 is not '$3' in $1"
}

# platform: macOS sets TMPDIR with a trailing slash, and cmake normalizes "//" away in the
#           CMAKE_OSX_SYSROOT it caches -- so an unstripped slash here would make the
#           check_cache_var comparison below fail on every real macOS session while looking fine
#           here with TMPDIR unset.
_tmp="${TMPDIR:-/tmp}"
work1="$(mktemp -d "${_tmp%/}/presets1.XXXXXX")"
work2="$(mktemp -d "${_tmp%/}/presets2.XXXXXX")"
work3="$(mktemp -d "${_tmp%/}/presets-sdkcache.XXXXXX")"
work4="$(mktemp -d "${_tmp%/}/presets-shipyard.XXXXXX")"
b1="$(basename "$work1")"; b2="$(basename "$work2")"
broot="$work4/broot"
bd1="$broot/${b1}-x86_64"
bd2="$broot/${b2}-x86_64"
bd1arm="$broot/${b1}-arm64"
bd1dflt="${_tmp%/}/mm-build/${b1}-x86_64"
bd1arm_notmp="/tmp/mm-build/${b1}-arm64"
trap 'rm -rf "$work1" "$work2" "$work3" "$work4" "$bd1dflt" "$bd1arm_notmp"' EXIT INT TERM

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the
#       toolchainFile runs on every configure below and fetches the pinned SDK; pre-seed a fake
#       cached SDK and point fetch_sdk.sh at it, so this test stays offline.
mkdir -p "$work3/MacOSX10.9.sdk/usr/lib" "$work3/MacOSX11.3.sdk/usr/lib"
MAVERICKS_SDK_CACHE="$work3"; export MAVERICKS_SDK_CACHE

cmake -S "$root" -B "$work4/build" > "$work4/install.log" 2>&1 \
  && cmake --install "$work4/build" --prefix "$work4/prefix" >> "$work4/install.log" 2>&1 \
  || { echo "FAIL: shipyard does not install"; sed 's/^/    | /' "$work4/install.log"; exit 1; }
installed="$work4/prefix/share/cmake/MavericksShipyard"
sdk="$work3/MacOSX10.9.sdk"

fixture "$work1" "$consumer"
fixture "$work2" "$consumer"

# platform: presets cannot default a variable, so binaryDir takes MAVERICKS_BUILD_ROOT as the caller
#           sets it.
MAVERICKS_BUILD_ROOT="$broot"; export MAVERICKS_BUILD_ROOT

out1="$(cd "$work1" && cmake --preset x86_64 2>&1)" \
  || say "checkout 1 does not configure: $out1"
if [ -e "$work1/CMakeCache.txt" ]; then say "checkout 1 configured INSIDE its own source tree"; fi

out2="$(cd "$work2" && cmake --preset x86_64 2>&1)" \
  || say "checkout 2 does not configure: $out2"
if [ -e "$work2/CMakeCache.txt" ]; then say "checkout 2 configured INSIDE its own source tree"; fi

[ -f "$bd1/CMakeCache.txt" ] \
  || say "checkout 1 did not build at $bd1 -- binaryDir does not honour MAVERICKS_BUILD_ROOT and key off the checkout's name"
[ -f "$bd2/CMakeCache.txt" ] \
  || say "checkout 2 did not build at $bd2 -- binaryDir does not honour MAVERICKS_BUILD_ROOT and key off the checkout's name"
if [ "$bd1" = "$bd2" ]; then say "two different checkouts resolved to the SAME build directory"; fi

# platform: reconfiguring here catches the failure mode CMake would raise on
#           a collided binaryDir -- a cache left pointing at checkout 2's
#           source makes this call fail with "does not match the source
#           ... used to generate cache".
out1b="$(cd "$work1" && cmake --preset x86_64 2>&1)" \
  || say "checkout 1 does not reconfigure after checkout 2 ran: $out1b"

# platform: a guard here (`[ -f ... ] &&`) would skip these checks silently
#           if it ever failed, without touching $fails -- omit it on
#           purpose; existence was already asserted above.
check_cache_var "$bd1/CMakeCache.txt" CMAKE_OSX_DEPLOYMENT_TARGET 10.9 "mavericks-x86_64"
check_cache_var "$bd1/CMakeCache.txt" CMAKE_OSX_ARCHITECTURES x86_64 "mavericks-x86_64"
check_cache_var "$bd1/CMakeCache.txt" CMAKE_OSX_SYSROOT "$sdk" "mavericks-x86_64"
if grep -q '^MAVERICKS_EXPECTED_MODE' "$bd1/CMakeCache.txt" 2>/dev/null; then
  say "mavericks-x86_64 still sets MAVERICKS_EXPECTED_MODE"
fi
check_cache_var "$bd1/CMakeCache.txt" MAVERICKS_PRESET_BUILD_ROOT "$broot" "mavericks-x86_64"

# spec: MavericksToolchain.cmake -- a preset whose MAVERICKS_BUILD_ROOT is empty would build at /, so
#       the toolchain file stops it; a configure that names its own -B never sets the variable.
fixture "$work4/emptyroot" "{ \"name\": \"e\", \"inherits\": \"mavericks-x86_64\", \"binaryDir\": \"$work4/emptyroot-build\", \"environment\": { \"MAVERICKS_BUILD_ROOT\": \"\" } }"
if oute="$(cd "$work4/emptyroot" && cmake --preset e 2>&1)"; then
  say "a preset with an empty MAVERICKS_BUILD_ROOT configures: $oute"
fi
case "$(printf '%s' "$oute" | tr '\n' ' ' | tr -s ' ')" in
  *"MAVERICKS_BUILD_ROOT is unset: set it, or configure through shipyard-cmake"*) ;;
  *) say "a preset with an empty MAVERICKS_BUILD_ROOT is not refused by name: $oute" ;;
esac
outb="$(cmake -S "$work4/emptyroot" -B "$work4/plain-build" -DCMAKE_TOOLCHAIN_FILE="$installed/MavericksToolchain.cmake" 2>&1)" \
  || say "a configure with -B and the toolchain file, and no preset, does not configure: $outb"

# spec: scripts/shipyard-launcher.sh -- with MAVERICKS_BUILD_ROOT unset, shipyard-cmake supplies
#       $TMPDIR/mm-build.
outd="$(cd "$work1" && env -u MAVERICKS_BUILD_ROOT SHIPYARD_LAUNCHER_HOST=linux "$work4/prefix/bin/shipyard-cmake" --preset x86_64 2>&1)" \
  || say "shipyard-cmake --preset x86_64 with MAVERICKS_BUILD_ROOT unset does not configure: $outd"
[ -f "$bd1dflt/CMakeCache.txt" ] \
  || say "shipyard-cmake with MAVERICKS_BUILD_ROOT unset did not build under \$TMPDIR/mm-build ($bd1dflt)"

# spec: README.md -- consumers inherit mavericks-x86_64; the old names are gone, with no alias, so a
#       consumer still on one fails configure.
for old in mavericks-native mavericks-cross; do
  fixture "$work4/old-$old" "{ \"name\": \"old\", \"inherits\": \"$old\" }"
  if outo="$(cd "$work4/old-$old" && cmake --preset old 2>&1)"; then
    say "a consumer inheriting $old still configures: $outo"
  fi
  case "$outo" in
    *"$old"*) ;;
    *) say "a consumer inheriting $old fails without naming $old: $outo" ;;
  esac
done

# spec: MavericksMode.cmake -- MAVERICKS_EXPECTED_MODE, whatever its value, stops the configure and
#       names the replacement; without it the module runs.
printf 'set(APPLE 1)\nlist(APPEND CMAKE_MODULE_PATH "%s")\nif(DEFINED EXP)\n  set(MAVERICKS_EXPECTED_MODE "${EXP}")\nendif()\ninclude(MavericksMode)\n' \
  "$root" > "$work4/guard.cmake"
for exp in native cross modern; do
  if outg="$(cmake -DEXP="$exp" -P "$work4/guard.cmake" 2>&1)"; then
    say "MAVERICKS_EXPECTED_MODE $exp is accepted"
  fi
  case "$(printf '%s' "$outg" | tr '\n' ' ' | tr -s ' ')" in
    *"MAVERICKS_EXPECTED_MODE is gone"*"mavericks-x86_64 or macos-arm64"*"reconfigure with --fresh)"*) ;;
    *) say "MAVERICKS_EXPECTED_MODE $exp does not say it is gone, name the presets and suggest --fresh: $outg" ;;
  esac
done
outn="$(cmake -P "$work4/guard.cmake" 2>&1)" || say "MavericksMode.cmake fails with no MAVERICKS_EXPECTED_MODE: $outn"

# spec: MavericksToolchain.cmake -- a 10.9 host builds x86_64 only, so the arm64 preset is exercised
#       on modern hosts and Linux.
if [ "$(sh "$root/scripts/mavericks_mode.sh")" = mavericks ]; then
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
  # platform: presets cannot default an environment variable (no fallback syntax); the launcher is
  #           the supported entry point, and with TMPDIR and MAVERICKS_BUILD_ROOT unset it builds
  #           under /tmp/mm-build.
  out1arm2="$(cd "$work1" && env -u TMPDIR -u MAVERICKS_BUILD_ROOT SHIPYARD_LAUNCHER_HOST=linux "$work4/prefix/bin/shipyard-cmake" --preset arm64 2>&1)" \
    || say "shipyard-cmake --preset arm64 with TMPDIR unset does not configure: $out1arm2"
  [ -f "$bd1arm_notmp/CMakeCache.txt" ] \
    || say "shipyard-cmake with TMPDIR unset did not build under /tmp/mm-build ($bd1arm_notmp)"
fi

[ "$fails" -eq 0 ] && echo "mavericks-presets: ok"
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
