#!/bin/sh
# platform: host-agnostic
#   usage: shipyard-scripts-test.sh
#          scripts/shipyard-scripts prints shipyard's scripts directory: $SHIPYARD_SCRIPTS when set,
#          else wherever shipyard-cmake's find_package(MavericksShipyard) lands (so a
#          CMAKE_PREFIX_PATH dev override moves the scripts with the modules), else through the
#          absolute /usr/local/mavergreen/bin/shipyard-cmake. The stub cases need no cmake and
#          run in the 10.9 guest; the real-cmake cases are skipped without one.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
. "$here/lib/cmake_fixture.sh"
T="$root/scripts/shipyard-scripts"
[ -f "$T" ] || { echo "FAIL: no $T"; exit 1; }
# platform: macOS sets TMPDIR with a trailing slash, and cmake normalizes "//" away.
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/shipyard-scripts-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
w="$(cd -P "$w" && pwd)"
installed_cm=/usr/local/mavergreen/bin/shipyard-cmake

mkdir -p "$w/s"
got="$(env -i PATH=/usr/bin:/bin SHIPYARD_SCRIPTS="$w/s" sh "$T")" \
  || { echo "FAIL: with SHIPYARD_SCRIPTS set, shipyard-scripts must succeed"; exit 1; }
[ "$got" = "$w/s" ] || { echo "FAIL: must print \$SHIPYARD_SCRIPTS; got '$got'"; exit 1; }

grep -qF "$installed_cm" "$T" || { echo "FAIL: must fall back to $installed_cm when shipyard-cmake is off PATH"; exit 1; }

sed "s#$installed_cm#$w/nowhere/shipyard-cmake#g" "$T" > "$w/nofallback"
if msg="$(env -i PATH=/usr/bin:/bin sh "$w/nofallback" 2>&1)"; then echo "FAIL: must fail with nothing to find"; exit 1; fi
printf '%s' "$msg" | grep -q 'install the shipyard pkg' || { echo "FAIL: message must say to install the pkg; got: $msg"; exit 1; }
out="$(env -i PATH=/usr/bin:/bin sh "$w/nofallback" 2>/dev/null || true)"
[ -z "$out" ] || { echo "FAIL: a failed probe must print nothing on stdout; got '$out'"; exit 1; }

mkdir -p "$w/stubbin" "$w/stubprefix/scripts"
cat > "$w/stubbin/shipyard-cmake" <<STUB
#!/bin/sh
echo "-- SHIPYARD_DIR=$w/stubprefix"
STUB
chmod +x "$w/stubbin/shipyard-cmake"
got="$(env -i PATH="$w/stubbin:/usr/bin:/bin" TMPDIR="$_tmp" sh "$T")" \
  || { echo "FAIL: must find the scripts through a shipyard-cmake on PATH"; exit 1; }
[ "$got" = "$w/stubprefix/scripts" ] || { echo "FAIL: stub probe gave '$got'"; exit 1; }

mkdir -p "$w/fallback"; cp "$w/stubbin/shipyard-cmake" "$w/fallback/shipyard-cmake"
sed "s#$installed_cm#$w/fallback/shipyard-cmake#g" "$T" > "$w/withfallback"
got="$(env -i PATH=/usr/bin:/bin TMPDIR="$_tmp" sh "$w/withfallback")" \
  || { echo "FAIL: with shipyard-cmake off PATH, must fall back to the absolute $installed_cm"; exit 1; }
[ "$got" = "$w/stubprefix/scripts" ] || { echo "FAIL: fallback gave '$got'"; exit 1; }

real="$(command -v cmake 2>/dev/null)" || { echo "PASS: shipyard-scripts (stub cases; SKIP real cmake: none)"; exit 0; }
printf 'message("${CMAKE_VERSION}")\n' > "$w/v.cmake"
ver="$("$real" -P "$w/v.cmake" 2>&1)"
fx="$w/fx"; mkdir -p "$w/pbin"
copy_cmake_product "$real" "$fx/cmake"
"$real" -S "$root" -B "$w/sb" -DSHIPYARD_CMAKE_MIN="$ver" > "$w/configure.log" 2>&1 \
  || { echo "FAIL: could not configure shipyard for the fixture:"; sed 's/^/    | /' "$w/configure.log"; exit 1; }
"$real" --install "$w/sb" --prefix "$fx/shipyard" > "$w/install.log" 2>&1 \
  || { echo "FAIL: could not install shipyard into the fixture prefix:"; sed 's/^/    | /' "$w/install.log"; exit 1; }
ln -s "$fx/shipyard/bin/shipyard-cmake" "$w/pbin/shipyard-cmake"
want="$fx/shipyard/share/cmake/MavericksShipyard/scripts"
[ -x "$fx/shipyard/bin/shipyard-scripts" ] || { echo "FAIL: the install must put shipyard-scripts in bin/"; exit 1; }
got="$(env -i PATH="$w/pbin:/usr/bin:/bin" TMPDIR="$_tmp" "$fx/shipyard/bin/shipyard-scripts")" \
  || { echo "FAIL: the installed shipyard-scripts must find its own scripts"; exit 1; }
[ "$got" = "$want" ] || { echo "FAIL: installed shipyard-scripts gave '$got', want '$want'"; exit 1; }

"$real" --install "$w/sb" --prefix "$w/dev" > "$w/install-dev.log" 2>&1 \
  || { echo "FAIL: could not install the dev copy:"; sed 's/^/    | /' "$w/install-dev.log"; exit 1; }
got="$(env -i PATH="$w/pbin:/usr/bin:/bin" TMPDIR="$_tmp" CMAKE_PREFIX_PATH="$w/dev" sh "$T")" \
  || { echo "FAIL: must find the dev copy under CMAKE_PREFIX_PATH"; exit 1; }
[ "$got" = "$w/dev/share/cmake/MavericksShipyard/scripts" ] || { echo "FAIL: under CMAKE_PREFIX_PATH gave '$got'"; exit 1; }

mkdir -p "$w/fb2"; ln -s "$fx/shipyard/bin/shipyard-cmake" "$w/fb2/shipyard-cmake"
sed "s#$installed_cm#$w/fb2/shipyard-cmake#g" "$T" > "$w/realfallback"
got="$(env -i PATH=/usr/bin:/bin TMPDIR="$_tmp" sh "$w/realfallback")" \
  || { echo "FAIL: with shipyard-cmake off PATH, the absolute fallback must work"; exit 1; }
[ "$got" = "$want" ] || { echo "FAIL: the absolute fallback gave '$got', want '$want'"; exit 1; }

echo "PASS: shipyard-scripts"
