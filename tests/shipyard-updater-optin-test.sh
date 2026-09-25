#!/bin/sh
# platform: macOS-only -- the updater is Objective-C against AppKit
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
command -v cmake >/dev/null 2>&1 || { echo "SKIP: no cmake"; exit 77; }
work="$(mktemp -d "${TMPDIR:-/tmp}/updater-optin.XXXXXX")"; trap 'rm -rf "$work"' EXIT

cmake -S "$root" -B "$work/off" >"$work/off.log" 2>&1 || { echo "FAIL: default configure failed"; sed -n '1,20p' "$work/off.log"; exit 1; }
grep -qi "The OBJC compiler identification" "$work/off.log" \
  && { echo "FAIL: shipyard is LANGUAGES NONE -- an unconditional ObjC target would quietly make a compiler a requirement for installing a package of shell scripts, so the updater must be opt-in; default configure enabled ObjC anyway"; exit 1; }
[ -d "$work/off/CMakeFiles/MavericksShipyardUpdater.dir" ] \
  && { echo "FAIL: default configure created an updater target, but cmake --install must work on a box with no ObjC compiler at all"; exit 1; }

if cmake -S "$root" -B "$work/on" -DSHIPYARD_BUILD_UPDATER=ON -DMAVERICKS_ALLOW_GENERIC_ICON=ON >"$work/on.log" 2>&1; then
  grep -qi "The OBJC compiler identification" "$work/on.log" \
    || { echo "FAIL: opt-in configure did not enable ObjC"; exit 1; }
else
  grep -qiE "fetch_sparkle|download|network|curl" "$work/on.log" \
    || { echo "FAIL: opt-in configure failed for a non-Sparkle reason (a CMake syntax error is not a legitimate skip)"; sed -n '1,25p' "$work/on.log"; exit 1; }
  echo "SKIP: cannot fetch Sparkle here; opt-in path not exercised"; exit 77
fi

# spec: 2026-09-11 -- one universal updater, so no per-arch target name or bundle id survives.
# platform: comments are skipped -- CMakeLists.txt's own comments may name the shared mavericks-cross
#           preset, which is prose about presets, not a per-arch updater slice.
if grep -v '^[[:space:]]*#' "$root/CMakeLists.txt" | grep -q 'CrossUpdater\|-cross'; then
  echo "FAIL: CMakeLists.txt still defines a -cross updater slice; there is one universal app now"; exit 1
fi
# spec: scripts/fetch_sparkle_framework.sh -- Sparkle is embedded fat and verbatim, so both per-arch
#       builds embed the identical framework and the merge has only the executable left to lipo; the
#       script refuses MAVERICKS_SPARKLE_ARCH, so a CMakeLists that still set it would fail to configure.
if grep -q 'MAVERICKS_SPARKLE_ARCH' "$root/CMakeLists.txt"; then
  echo "FAIL: CMakeLists.txt must not set MAVERICKS_SPARKLE_ARCH -- Sparkle is always fat now, and the fetch refuses it"; exit 1
fi

echo "PASS: shipyard-updater-optin"
