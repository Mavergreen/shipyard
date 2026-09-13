#!/bin/sh
#   usage: shipyard-cmake-refusal-test.sh
#          Only shipyard's own cmake may configure against shipyard: "its own" means the running
#          cmake lives in a prefix that also holds a shipyard. Any other cmake, even one pointed
#          straight at shipyard, must fail at configure naming shipyard-cmake; a CMAKE_PREFIX_PATH
#          dev override through a real shipyard-cmake must still work and load the dev copy. The
#          fixture is a prefix built from THIS box's cmake plus shipyard installed into it. Exit 0
#          clean, 1 on failure, 77 with no cmake to build a fixture from.
# spec: 2026-09-11 decision 2 -- the refusal is the whole mechanism the design rests on since the
#       user package registry was removed.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
. "$here/lib/cmake_fixture.sh"
real="$(command -v cmake 2>/dev/null)" || { echo "SKIP: no cmake"; exit 77; }
# platform: macOS sets TMPDIR with a trailing slash, and cmake normalizes "//" away when it prints
#           MavericksShipyard_DIR -- so an unstripped slash makes case 1's grep fail on every real
#           macOS session while looking fine here with TMPDIR unset.
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/refusal-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
croot="$(printf 'message("${CMAKE_ROOT}")\n' > "$w/r.cmake"; "$real" -P "$w/r.cmake" 2>&1)"
fx="$w/fx"; mkdir -p "$fx/bin" "$fx/share"
cp "$real" "$fx/bin/cmake"
# spec: tests/lib/cmake_fixture.sh -- the two ways a copied CMAKE_ROOT goes wrong are written out
#       there, and tests/cmake-fixture-test.sh proves the helper on this box.
copy_cmake_root "$croot" "$fx/share/$(basename "$croot")"
# platform: CMake's find_package consults the user package registry BEFORE it searches a cmake's own
#           install prefix, and this box may carry an entry from a shipyard installed outside the
#           fixture -- so every configure below runs under its own never-written-to scratch HOME, or
#           an ambient entry silently outranks the copy under test.
# platform: keep this output. Redirected to /dev/null, a failure here kills the script under set -e
#           with nothing said, and CI reports a bare "exit 1" with no way to tell what broke.
"$real" -S "$root" -B "$w/sb" > "$w/configure.log" 2>&1 \
  || { echo "FAIL: could not configure shipyard for the fixture:"; sed 's/^/    | /' "$w/configure.log"; exit 1; }
HOME="$w/home-fx" "$real" --install "$w/sb" --prefix "$fx" > "$w/install-fx.log" 2>&1 \
  || { echo "FAIL: could not install shipyard into the fixture prefix:"; sed 's/^/    | /' "$w/install-fx.log"; exit 1; }
HOME="$w/home-dev" "$real" --install "$w/sb" --prefix "$w/dev" > "$w/install-dev.log" 2>&1 \
  || { echo "FAIL: could not install the second (dev) copy:"; sed 's/^/    | /' "$w/install-dev.log"; exit 1; }

mkdir -p "$w/c"
printf 'cmake_minimum_required(VERSION 3.16)\nproject(c NONE)\nfind_package(MavericksShipyard REQUIRED)\nmessage(STATUS "DIR=${MavericksShipyard_DIR}")\n' > "$w/c/CMakeLists.txt"

out="$(HOME="$w/home-run" "$fx/bin/cmake" -S "$w/c" -B "$w/b1" 2>&1)" || { echo "FAIL: a shipyard-cmake must configure; got:"; echo "$out"; exit 1; }
printf '%s' "$out" | grep -q "DIR=$fx/share/cmake/MavericksShipyard" || { echo "FAIL: expected the fixture's shipyard; got:"; echo "$out"; exit 1; }

if out="$(HOME="$w/home-run" "$real" -S "$w/c" -B "$w/b2" -DMavericksShipyard_DIR="$fx/share/cmake/MavericksShipyard" 2>&1)"; then
  echo "FAIL: a foreign cmake must be refused"; exit 1
fi
printf '%s' "$out" | grep -q 'shipyard-cmake' || { echo "FAIL: the refusal must name shipyard-cmake; got:"; echo "$out"; exit 1; }

out="$(HOME="$w/home-run" CMAKE_PREFIX_PATH="$w/dev" "$fx/bin/cmake" -S "$w/c" -B "$w/b3" 2>&1)" || { echo "FAIL: dev override must configure; got:"; echo "$out"; exit 1; }
printf '%s' "$out" | grep -q "DIR=$w/dev/share/cmake/MavericksShipyard" || { echo "FAIL: dev override must load the dev copy; got:"; echo "$out"; exit 1; }

# spec: R-P1-23 -- the refusal is keyed on CMAKE_HOST_APPLE and must NOT fire on a non-Apple host:
#       shipyard ships no Linux pkg and no Linux cmake, so demanding shipyard-cmake there is
#       incoherent, and it broke container-tools' two ubuntu-latest jobs.
# platform: this box IS Apple and CMAKE_HOST_APPLE cannot be turned off from the command line --
#           CMake sets it as a normal variable, which shadows any -D. In script mode a set() before
#           the include does reach it, so `cmake -P` exercises the real guard in the real file with a
#           CMAKE_COMMAND that has no shipyard beside it: the Linux runner's situation exactly.
probe() {  # $1 = CMAKE_HOST_APPLE value; prints the config's verdict
  printf 'set(CMAKE_HOST_APPLE %s)\nset(CMAKE_COMMAND "%s/no-such-prefix/bin/cmake")\ninclude("%s/MavericksShipyardConfig.cmake")\nmessage(STATUS "CONFIGURED")\n' \
    "$1" "$w" "$root" > "$w/probe-$1.cmake"
  ( cd "$w" && "$real" -P "$w/probe-$1.cmake" 2>&1 )
}
if out="$(probe 1)"; then echo "FAIL: on an Apple host a cmake with no shipyard beside it must be refused; got:"; echo "$out"; exit 1; fi
printf '%s' "$out" | grep -q 'shipyard-cmake' || { echo "FAIL: the Apple-host refusal must name shipyard-cmake; got:"; echo "$out"; exit 1; }
out="$(probe 0)" || { echo "FAIL: on a NON-Apple host the config must load anyway (no Linux pkg exists to demand); got:"; echo "$out"; exit 1; }
printf '%s' "$out" | grep -q 'CONFIGURED' || { echo "FAIL: the non-Apple host did not reach the end of the config; got:"; echo "$out"; exit 1; }

# spec: .github/actions/install/action.yml -- its non-macOS path points MavericksShipyard_DIR at the
#       action's own CHECKOUT, where the config sits at the root rather than under share/cmake, and
#       the guard must not misfire on that.
out="$(HOME="$w/home-run" MavericksShipyard_DIR="$root" "$fx/bin/cmake" -S "$w/c" -B "$w/b4" 2>&1)" \
  || { echo "FAIL: MavericksShipyard_DIR pointed at a shipyard CHECKOUT must configure (that is what install@v1 exports on Linux); got:"; echo "$out"; exit 1; }
printf '%s' "$out" | grep -q "DIR=$root" || { echo "FAIL: expected the checkout's config; got:"; echo "$out"; exit 1; }

echo "PASS: shipyard-cmake-refusal"
