#!/bin/sh
# platform: host-agnostic
#   usage: shipyard-cmake-min-test.sh
#          The minimum configured into the installed MavericksShipyardConfig.cmake is the Kitware part
#          of .mavergreen/ingredients/cmake/VERSION; -DSHIPYARD_CMAKE_MIN replaces it for one configure only, and a
#          value that is not a version fails the configure. Exit 0 clean, 1 on failure, 77 with no cmake.
# spec: 2026-10-09 C5
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
cm="$(command -v cmake 2>/dev/null)" || { echo "SKIP: no cmake"; exit 77; }
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/shipyard-cmake-min.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
pin="$(sed -n '1s/-mavericks\.[0-9][0-9]*$//p' "$root/.mavergreen/ingredients/cmake/VERSION")"
[ -n "$pin" ] || { echo "FAIL: .mavergreen/ingredients/cmake/VERSION is not X.Y.Z-mavericks.N"; exit 1; }
baked() { sed -n 's/^ *set(_shipyard_cmake_min "\(.*\)")$/\1/p' "$w/b/MavericksShipyardConfig.cmake"; }

"$cm" -S "$root" -B "$w/b" > "$w/c1.log" 2>&1 || { echo "FAIL: shipyard does not configure:"; sed 's/^/    | /' "$w/c1.log"; exit 1; }
[ "$(baked)" = "$pin" ] || fail "with no -DSHIPYARD_CMAKE_MIN the minimum must be the pin's $pin; got '$(baked)'"
"$cm" -S "$root" -B "$w/b" -DSHIPYARD_CMAKE_MIN=3.1.4 > "$w/c2.log" 2>&1 || { echo "FAIL: -DSHIPYARD_CMAKE_MIN=3.1.4 does not configure:"; sed 's/^/    | /' "$w/c2.log"; exit 1; }
[ "$(baked)" = 3.1.4 ] || fail "-DSHIPYARD_CMAKE_MIN=3.1.4 must be the minimum; got '$(baked)'"
"$cm" -S "$root" -B "$w/b" > "$w/c3.log" 2>&1 || { echo "FAIL: the reconfigure does not configure:"; sed 's/^/    | /' "$w/c3.log"; exit 1; }
[ "$(baked)" = "$pin" ] || fail "a later configure without -DSHIPYARD_CMAKE_MIN must read the pin again; got '$(baked)'"
for bad in "" 4.4.4-mavericks.1 four; do
  rc=0; "$cm" -S "$root" -B "$w/bad" -DSHIPYARD_CMAKE_MIN="$bad" > "$w/bad.log" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "-DSHIPYARD_CMAKE_MIN='$bad' must fail the configure"
  grep -qF "'$bad', not a version" "$w/bad.log" && grep -q '.mavergreen/ingredients/cmake/VERSION' "$w/bad.log" \
    || { fail "-DSHIPYARD_CMAKE_MIN='$bad' must be named, with .mavergreen/ingredients/cmake/VERSION:"; sed 's/^/    | /' "$w/bad.log"; }
  rm -rf "$w/bad"
done

[ "$fails" -eq 0 ] || { echo "FAIL: $fails case(s) in shipyard-cmake-min"; exit 1; }
echo "PASS: shipyard-cmake-min"
