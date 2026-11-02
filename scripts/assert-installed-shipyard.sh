#!/bin/sh
# platform: macOS-only -- lipo checks the installed universal binaries
#   usage: assert-installed-shipyard.sh --cmake-version V [--root DIR]
#          Asserts that an INSTALLED mavericks-shipyard is what we meant to ship: the cmake product
#          beside it is the CMake in .mavergreen/ingredients/cmake/VERSION and universal; the farm's
#          shipyard-cmake, shipyard-ctest, shipyard-cpack, shipyard-check and shipyard-scripts are executable on the
#          default PATH, and shipyard-check runs from there; a probe under a stripped environment
#          finds shipyard through shipyard-cmake; shipyard's own pins are installed beside its scripts;
#          the installed updater is universal; nothing is left in /usr/local/bin from the old layout;
#          an installed mavergreen helper passes its own check; and any other cmake is refused, by
#          name. --root defaults to "/" (a real install); a fixture root makes this unit-testable.
#          Exit 0 clean, 1 on a failed assertion, 2 on a usage error.
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
FARM="$R/usr/local/mavergreen/bin"
CM="$FARM/shipyard-cmake"
PREFIX="$R/usr/local/mavergreen/shipyard"
PRODUCT="$R/usr/local/mavergreen/cmake/bin/cmake"
CFGDIR="$PREFIX/share/cmake/MavericksShipyard"
EXE="$R/Library/Application Support/Mavergreen/shipyard-updater.app/Contents/MacOS/shipyard-updater"

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

if [ -x "$PRODUCT" ]; then
  if ! "$PRODUCT" --version > "$W/version.txt" 2>&1; then
    fail "the cmake product ($PRODUCT) does not run: $(cat "$W/version.txt")"
  elif ! grep -q "cmake version $WANT" "$W/version.txt"; then
    fail "the cmake product is not CMake $WANT: $(head -1 "$W/version.txt")"
  fi
else
  fail "no executable cmake product at $PRODUCT -- shipyard's launchers run it, and install@v1 installs it first"
fi
if [ -x "$CM" ]; then
  "$CM" --version > "$W/launcher.txt" 2>&1 \
    || fail "shipyard-cmake ($CM) does not run: $(cat "$W/launcher.txt")"
else
  fail "no executable shipyard-cmake at $CM"
fi

for c in shipyard-cmake shipyard-ctest shipyard-cpack shipyard-check shipyard-scripts; do
  [ -x "$FARM/$c" ] \
    || fail "no executable $FARM/$c -- the pkg exports all five through the link farm on the default PATH"
done
if [ -x "$FARM/shipyard-check" ]; then
  "$FARM/shipyard-check" --explain tests-run-in-ci >/dev/null 2>"$W/check.log" \
    || fail "shipyard-check does not run from the link farm: $(cat "$W/check.log")"
fi
# platform: -L as well as -e -- a leftover link whose old prefix was removed by hand dangles, and -e
#           alone reads a dangling link as absent.
if [ -e "$R/usr/local/bin/shipyard-cmake" ] || [ -L "$R/usr/local/bin/shipyard-cmake" ]; then
  fail "$R/usr/local/bin/shipyard-cmake is left over from the old layout -- it shadows the farm's shipyard-cmake on the default PATH; remove it by hand"
fi
if [ -f "$R/usr/local/bin/mavergreen" ]; then
  sh "$R/usr/local/bin/mavergreen" --root "$ROOT" check || fail "mavergreen check failed"
fi
# spec: 2026-10-09 C4 -- shipyard-cmake is a launcher script, so the slices are the cmake product's.
if [ -x "$PRODUCT" ]; then
  cmarchs="$(lipo -info "$PRODUCT" 2>&1 || true)"
  case "$cmarchs" in
    *x86_64*) ;;
    *) fail "the cmake product has no x86_64 slice, so it cannot run on 10.9: $cmarchs" ;;
  esac
  case "$cmarchs" in
    *arm64*) ;;
    *) fail "the cmake product has no arm64 slice, so it cannot run on Apple Silicon: $cmarchs" ;;
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

[ -f "$CFGDIR/.mavergreen/ingredients/stevedore/VERSION" ] \
  || fail "no $CFGDIR/.mavergreen/ingredients/stevedore/VERSION: the installed scripts read shipyard's own pins from $CFGDIR/.mavergreen/ingredients/"

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
# spec: 2026-10-09 C5 -- the config accepts the cmake product, so a cmake on PATH that resolves under
#       /usr/local/mavergreen/ (the product, or shipyard's compatibility link to its launcher) is ours.
# platform: 10.9 has no realpath and no readlink -f, so links are followed one at a time.
_o="$other"
while [ -n "$_o" ]; do
  case "$_o" in "$R"/usr/local/mavergreen/*) other=""; break ;; esac
  [ -L "$_o" ] || break
  _l="$(readlink "$_o")"
  case "$_l" in /*) _o="$_l" ;; *) _o="${_o%/*}/$_l" ;; esac
done
if [ -n "$other" ]; then
  if "$other" -S "$W/probe" -B "$W/other" -DMavericksShipyard_DIR="$CFGDIR" > "$W/other.log" 2>&1; then
    fail "$other configured against shipyard; every cmake but the cmake product must be refused"
  fi
  grep -q 'shipyard-cmake' "$W/other.log" \
    || fail "the refusal does not name shipyard-cmake, so it does not say what to run instead: $(cat "$W/other.log")"
  refusal="other cmakes refused"
else
  echo "::warning::installed shipyard: no other cmake on PATH to check the refusal against" >&2
  refusal="no other cmake here to check the refusal against"
fi

[ "$bad" -eq 0 ] || exit 1
echo "installed shipyard: shipyard-cmake runs CMake $WANT and finds shipyard in $CFGDIR; updater universal; $refusal"
