#!/bin/sh
# platform: host-agnostic
#   usage: shipyard-cmake-refusal-test.sh
#          On a macOS host only the cmake product beside shipyard, at or above shipyard's minimum, may
#          configure against it; any other cmake, even one pointed straight at shipyard, fails naming
#          shipyard-cmake and the minimum. Off macOS any cmake may. A CMAKE_PREFIX_PATH dev override
#          through shipyard-cmake still loads the dev copy. The fixture is a pair <root>/{shipyard,cmake}:
#          THIS box's cmake copied into cmake/, shipyard installed into shipyard/ with that cmake's
#          version as its minimum. Exit 0 clean, 1 on failure, 77 with no cmake to build a fixture from.
# spec: 2026-10-09 C5
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
. "$here/lib/cmake_fixture.sh"
real="$(command -v cmake 2>/dev/null)" || { echo "SKIP: no cmake"; exit 77; }
command -v make >/dev/null 2>&1 || { echo "FAIL: the regeneration case needs make"; exit 1; }
# platform: on a Linux runner, install@v1 exports MavericksShipyard_DIR (and a caller may carry a
#           CMAKE_PREFIX_PATH) for the whole job; either outranks the search every case here tests, so
#           clear both and let the cases that want one set it themselves.
unset MavericksShipyard_DIR CMAKE_PREFIX_PATH
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/refusal-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
# platform: the launcher resolves its prefix physically, and macOS's TMPDIR is under /var, a link to
#           /private/var, so every path compared below is the physical one.
w="$(cd -P "$w" && pwd)"
printf 'message("${CMAKE_VERSION}")\n' > "$w/v.cmake"
ver="$("$real" -P "$w/v.cmake" 2>&1)"
above="$((${ver%%.*} + 1)).0.0"
darwin=0; [ "$(uname -s)" != Darwin ] || darwin=1

fx="$w/fx"
copy_cmake_product "$real" "$fx/cmake"
# platform: keep this output. Redirected to /dev/null, a failure here kills the script under set -e
#           with nothing said, and CI reports a bare "exit 1" with no way to tell what broke.
install_shipyard() {  # $1 = build dir  $2 = prefix  $3 = SHIPYARD_CMAKE_MIN
  "$real" -S "$root" -B "$1" -DSHIPYARD_CMAKE_MIN="$3" > "$1.configure.log" 2>&1 \
    || { echo "FAIL: could not configure shipyard:"; sed 's/^/    | /' "$1.configure.log"; exit 1; }
  "$real" --install "$1" --prefix "$2" > "$1.install.log" 2>&1 \
    || { echo "FAIL: could not install shipyard into $2:"; sed 's/^/    | /' "$1.install.log"; exit 1; }
}
install_shipyard "$w/sb" "$fx/shipyard" "$ver"
install_shipyard "$w/sb" "$w/dev/shipyard" "$ver"
ln -s "$fx/cmake" "$w/dev/cmake"
install_shipyard "$w/sb-above" "$w/above/shipyard" "$above"
ln -s "$fx/cmake" "$w/above/cmake"

mkdir -p "$w/c"
printf 'cmake_minimum_required(VERSION 3.16)\nproject(c NONE)\nfind_package(MavericksShipyard REQUIRED)\nmessage(STATUS "DIR=${MavericksShipyard_DIR}")\n' > "$w/c/CMakeLists.txt"
sc="$fx/shipyard/bin/shipyard-cmake"

out="$("$sc" -S "$w/c" -B "$w/b1" 2>&1)" || { echo "FAIL: the real pair, through shipyard-cmake, must configure; got:"; echo "$out"; exit 1; }
printf '%s' "$out" | grep -q "DIR=$fx/shipyard/share/cmake/MavericksShipyard" || { echo "FAIL: expected the fixture's shipyard; got:"; echo "$out"; exit 1; }

refused() {  # $1 = what  $2 = the minimum the refusal must name; the rest is the configure
  _what="$1"; _min="$2"; shift 2
  if [ "$darwin" -eq 1 ]; then
    if _out="$("$@" 2>&1)"; then echo "FAIL: $_what must be refused on a macOS host"; exit 1; fi
    printf '%s' "$_out" | grep -q 'shipyard-cmake' || { echo "FAIL: refusing $_what must name shipyard-cmake; got:"; echo "$_out"; exit 1; }
    printf '%s' "$_out" | grep -qF "CMake $_min or later" || { echo "FAIL: refusing $_what must name the minimum, $_min; got:"; echo "$_out"; exit 1; }
  else
    _out="$("$@" 2>&1)" || { echo "FAIL: off macOS $_what must configure -- there is no Linux cmake product to demand; got:"; echo "$_out"; exit 1; }
  fi
}
# spec: MavericksShipyardConfig.cmake -- the refusal is keyed on CMAKE_HOST_APPLE, so what each case
#       must get depends on the host running this test, and each host checks its own half.
refused "the host cmake run directly" "$ver" \
  "$real" -S "$w/c" -B "$w/b2" -DMavericksShipyard_DIR="$fx/shipyard/share/cmake/MavericksShipyard"
refused "a cmake below the minimum, through shipyard-cmake" "$above" \
  "$w/above/shipyard/bin/shipyard-cmake" -S "$w/c" -B "$w/b2a"

out="$(CMAKE_PREFIX_PATH="$w/dev/shipyard" "$sc" -S "$w/c" -B "$w/b3" 2>&1)" || { echo "FAIL: dev override must configure; got:"; echo "$out"; exit 1; }
printf '%s' "$out" | grep -q "DIR=$w/dev/shipyard/share/cmake/MavericksShipyard" || { echo "FAIL: dev override must load the dev copy; got:"; echo "$out"; exit 1; }

# spec: R-P1-23 -- the refusal is keyed on CMAKE_HOST_APPLE and must NOT fire on a non-Apple host:
#       shipyard ships no Linux pkg and no Linux cmake, so demanding shipyard-cmake there is
#       incoherent, and it broke container-tools' two ubuntu-latest jobs.
# platform: CMAKE_HOST_APPLE cannot be turned off from the command line -- CMake sets it as a normal
#           variable, which shadows any -D. In script mode a set() before the include does reach it,
#           so `cmake -P` exercises the real guard in the real file with a CMAKE_COMMAND that has no
#           shipyard beside it: the Linux runner's situation exactly.
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
#       action's own CHECKOUT, where the config sits at the root rather than under share/cmake and
#       the minimum comes from components/cmake/version; copies of it pin this box's cmake and one
#       above it.
checkout() {  # $1 = dir  $2 = the pin it carries
  mkdir -p "$1/components/cmake"
  cp "$root"/*.cmake "$1/"
  printf '%s\n' "$2" > "$1/components/cmake/version"
}
checkout "$w/co" "$ver-mavericks.1"
checkout "$w/co-above" "$above-mavericks.1"
out="$(MavericksShipyard_DIR="$w/co" "$sc" -S "$w/c" -B "$w/b4" 2>&1)" \
  || { echo "FAIL: MavericksShipyard_DIR pointed at a shipyard CHECKOUT must configure (that is what install@v1 exports on Linux); got:"; echo "$out"; exit 1; }
printf '%s' "$out" | grep -q "DIR=$w/co" || { echo "FAIL: expected the checkout's config; got:"; echo "$out"; exit 1; }
refused "a cmake below a checkout's pin" "$above" \
  env MavericksShipyard_DIR="$w/co-above" "$sc" -S "$w/c" -B "$w/b4a"
refused "the host cmake run directly against a checkout" "$ver" \
  env MavericksShipyard_DIR="$w/co" "$real" -S "$w/c" -B "$w/b4b"

# spec: 2026-10-09 C4 -- a build directory configured before the switch names shipyard/bin/cmake as its
#       CMAKE_COMMAND and its CMAKE_ROOT under shipyard/share, so the compatibility link must
#       regenerate it. Configuring through that link and pointing the build files back at the old
#       layout reproduces one.
"$fx/shipyard/bin/cmake" -G "Unix Makefiles" -S "$w/c" -B "$w/regen" > "$w/regen.log" 2>&1 \
  || { echo "FAIL: configuring through the compatibility link failed:"; sed 's/^/    | /' "$w/regen.log"; exit 1; }
grep -rlF "$fx/cmake/" "$w/regen" | while IFS= read -r f; do
  sed "s#$fx/cmake/#$fx/shipyard/#g" "$f" > "$f.old" && mv "$f.old" "$f"
done
grep -qxF "CMAKE_COMMAND:INTERNAL=$fx/shipyard/bin/cmake" "$w/regen/CMakeCache.txt" \
  || { echo "FAIL: could not point the build directory at the old layout:"; grep '^CMAKE_COMMAND' "$w/regen/CMakeCache.txt"; exit 1; }
sleep 1; touch "$w/c/CMakeLists.txt"
out="$("$fx/shipyard/bin/cmake" --build "$w/regen" 2>&1)" \
  || { echo "FAIL: a build directory from before the switch must regenerate; got:"; echo "$out"; exit 1; }
printf '%s' "$out" | grep -q "DIR=$fx/shipyard/share/cmake/MavericksShipyard" \
  || { echo "FAIL: the build did not re-run configure; got:"; echo "$out"; exit 1; }

echo "PASS: shipyard-cmake-refusal"
