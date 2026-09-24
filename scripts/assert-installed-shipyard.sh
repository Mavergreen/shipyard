#!/bin/sh
# platform: macOS-only -- lipo checks the installed universal binaries
#   usage: assert-installed-shipyard.sh --cmake-version V [--root DIR]
#          Asserts that an INSTALLED mavericks-shipyard is what we meant to ship: shipyard-cmake runs
#          and is the CMake in cmake.pin; it is OURS (universal, with shipyard-ctest and
#          shipyard-cpack beside it on the default PATH); a probe under a stripped environment
#          resolves shipyard inside shipyard-cmake's own prefix; the installed updater is universal;
#          and any other cmake is refused, by name. --root defaults to "/" (a real install); a
#          fixture root makes this unit-testable. Exit 0 clean, 1 on a failed assertion, 2 on a usage
#          error.
# spec: R-P1-17 -- these assertions used to live inline in release.yml's install smoke, the one step
#       that runs ONLY on a push to main, which left them unrunnable until the very push that must
#       not be a rehearsal. release.yml, ci.yml and tests/assert-installed-shipyard-test.sh now share
#       this one statement of what an installed shipyard looks like.
set -eu

ROOT="/"; WANT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2;;
    --cmake-version) WANT="$2"; shift 2;;
    *) echo "assert-installed-shipyard: unknown option $1" >&2; exit 2;;
  esac
done
# spec: scripts/run-repo-tests.sh -- a usage error exits 2, never 1: a caller that forgot the pin
#       must not be told "the installed shipyard is wrong", and 77 is reserved for SKIP.
[ -n "$WANT" ] || { echo "assert-installed-shipyard: --cmake-version required" >&2; exit 2; }
[ -d "$ROOT" ] || { echo "assert-installed-shipyard: no such root: $ROOT" >&2; exit 2; }

R="${ROOT%/}"
CM="$R/usr/local/bin/shipyard-cmake"
PREFIX="$R/usr/local/mavergreen-shipyard"
CFGDIR="$PREFIX/share/cmake/MavericksShipyard"
EXE="$R/Library/Application Support/Mavergreen/MavericksShipyardUpdater.app/Contents/MacOS/MavericksShipyardUpdater"

bad=0
fail() { echo "::error::installed shipyard: $*" >&2; bad=1; }

W="$(mktemp -d "${TMPDIR:-/tmp}/shipyard-assert.XXXXXX")"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/probe"
printf '%s\n' \
  'cmake_minimum_required(VERSION 3.16)' \
  'project(probe NONE)' \
  'find_package(MavericksShipyard REQUIRED)' \
  'message(STATUS "DIR=${MavericksShipyard_DIR}")' \
  > "$W/probe/CMakeLists.txt"

if [ -x "$CM" ]; then
  if ! "$CM" --version > "$W/version.txt" 2>&1; then
    fail "shipyard-cmake ($CM) does not run: $(cat "$W/version.txt")"
  elif ! grep -q "cmake version $WANT" "$W/version.txt"; then
    fail "shipyard-cmake is not CMake $WANT: $(head -1 "$W/version.txt")"
  fi
else
  fail "no executable shipyard-cmake at $CM"
fi

for c in shipyard-cmake shipyard-ctest shipyard-cpack; do
  [ -x "$R/usr/local/bin/$c" ] \
    || fail "no executable $R/usr/local/bin/$c -- the pkg puts all three on the default PATH"
done
if [ -x "$CM" ]; then
  cmarchs="$(lipo -info "$CM" 2>&1 || true)"
  case "$cmarchs" in
    *x86_64*) ;;
    *) fail "shipyard-cmake has no x86_64 slice, so it cannot run on 10.9: $cmarchs" ;;
  esac
  case "$cmarchs" in
    *arm64*) ;;
    *) fail "shipyard-cmake has no arm64 slice, so it cannot run on Apple Silicon: $cmarchs" ;;
  esac
fi

# platform: env -i keeps a leaked CMAKE_PREFIX_PATH, or an inherited PATH that puts another prefix
#           first, from making this pass for the wrong reason. HOME is carried through only because
#           cmake wants somewhere to write cache files.
if [ -x "$CM" ]; then
  env -i HOME="${HOME:-$W}" PATH=/usr/bin:/bin \
    "$CM" -S "$W/probe" -B "$W/own" > "$W/own.log" 2>&1 || true
  grep -q "DIR=$CFGDIR" "$W/own.log" \
    || fail "shipyard-cmake did not find shipyard at $CFGDIR under a stripped environment: $(cat "$W/own.log")"
fi

# platform: 10.9's lipo has no -archs, so read the slices with lipo -info;
#           check-shell-portability.sh bans the idiom outright.
if [ -f "$EXE" ]; then
  archs="$(lipo -info "$EXE" 2>&1 || true)"
  case "$archs" in
    *x86_64*) ;;
    *) fail "the installed updater has no x86_64 slice: $archs" ;;
  esac
  case "$archs" in
    *arm64*) ;;
    *) fail "the installed updater has no arm64 slice: $archs" ;;
  esac
else
  fail "no installed updater executable at $EXE"
fi

other="$(command -v cmake 2>/dev/null || true)"
case "$other" in
  "$PREFIX"/*) other="" ;;   # shipyard's own, reached under another name: not a foreign cmake
esac
if [ -n "$other" ]; then
  if "$other" -S "$W/probe" -B "$W/other" -DMavericksShipyard_DIR="$CFGDIR" > "$W/other.log" 2>&1; then
    fail "$other configured against shipyard; every cmake but shipyard's must be refused"
  fi
  grep -q 'shipyard-cmake' "$W/other.log" \
    || fail "the refusal does not name shipyard-cmake, so it does not say what to run instead: $(cat "$W/other.log")"
  refusal="other cmakes refused"
else
  echo "::warning::installed shipyard: no other cmake on PATH to check the refusal against" >&2
  refusal="no other cmake here to check the refusal against"
fi

[ "$bad" -eq 0 ] || exit 1
echo "installed shipyard: shipyard-cmake $WANT finds shipyard in $CFGDIR; updater universal; $refusal"
