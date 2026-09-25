#!/bin/sh
# platform: host-agnostic
#   usage: msc-template-test.sh
#          scripts/templates/msc.sh is how a product's build scripts find shipyard with no registry:
#          $SHIPYARD_SCRIPTS when CI exported it, else asking shipyard-cmake where find_package
#          lands. Exit 0 clean, 1 on failure, 77 with no cmake for the probe case.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
. "$here/lib/cmake_fixture.sh"
T="$root/scripts/templates/msc.sh"
[ -f "$T" ] || { echo "FAIL: no $T"; exit 1; }
# platform: macOS sets TMPDIR with a trailing slash, and cmake normalizes "//" away -- so an
#           unstripped TMPDIR makes the string comparison below fail on every real macOS session
#           while looking fine here with TMPDIR unset.
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/msc-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT

mkdir -p "$w/s"
got="$(env -i PATH=/usr/bin:/bin SHIPYARD_SCRIPTS="$w/s" sh -c ". '$T'; printf '%s' \"\$SHIPYARD\"")" \
  || { echo "FAIL: with SHIPYARD_SCRIPTS set, msc.sh must succeed"; exit 1; }
[ "$got" = "$w/s" ] || { echo "FAIL: SHIPYARD must be \$SHIPYARD_SCRIPTS; got '$got'"; exit 1; }

installed_cm=/usr/local/mavergreen/bin/shipyard-cmake
grep -qF "$installed_cm" "$T" || { echo "FAIL: msc.sh must fall back to $installed_cm when shipyard-cmake is off PATH (a launchd job, a non-login shell)"; exit 1; }
# platform: both cases run against a copy whose absolute fallback is rewritten, so neither depends on
#           whether this box has shipyard installed.
sed "s#$installed_cm#$w/nowhere/shipyard-cmake#g" "$T" > "$w/msc-nofallback.sh"
if msg="$(env -i PATH=/usr/bin:/bin sh -c ". '$w/msc-nofallback.sh'" 2>&1)"; then echo "FAIL: must fail with nothing to find"; exit 1; fi
printf '%s' "$msg" | grep -q 'install the shipyard pkg' || { echo "FAIL: message must say to install the pkg; got: $msg"; exit 1; }
got="$(env -i PATH=/usr/bin:/bin sh -c ". '$w/msc-nofallback.sh' >/dev/null 2>&1; printf '%s' \"\$SHIPYARD\"" || true)"
[ "$got" != "/scripts" ] || { echo "FAIL: a failed probe set SHIPYARD to the literal '/scripts'"; exit 1; }
[ -z "$got" ] || { echo "FAIL: a failed probe must leave SHIPYARD empty; got '$got'"; exit 1; }

real="$(command -v cmake 2>/dev/null)" || { echo "SKIP: no cmake for the probe case"; exit 77; }
croot="$(printf 'message("${CMAKE_ROOT}")\n' > "$w/r.cmake"; "$real" -P "$w/r.cmake" 2>&1)"
fx="$w/fx"; mkdir -p "$fx/bin" "$fx/share" "$w/pbin"
cp "$real" "$fx/bin/cmake"
# spec: tests/lib/cmake_fixture.sh -- the two ways a copied CMAKE_ROOT goes wrong are written out
#       there, and tests/cmake-fixture-test.sh proves the helper on this box.
copy_cmake_root "$croot" "$fx/share/$(basename "$croot")"
# platform: keep this output. Redirected to /dev/null, a failure here kills the script under set -e
#           with nothing said, and CI reports a bare "exit 1" with no way to tell what broke.
"$real" -S "$root" -B "$w/sb" > "$w/configure.log" 2>&1 \
  || { echo "FAIL: could not configure shipyard for the fixture:"; sed 's/^/    | /' "$w/configure.log"; exit 1; }
HOME="$w/home" "$real" --install "$w/sb" --prefix "$fx" > "$w/install.log" 2>&1 \
  || { echo "FAIL: could not install shipyard into the fixture prefix:"; sed 's/^/    | /' "$w/install.log"; exit 1; }
ln -s "$fx/bin/cmake" "$w/pbin/shipyard-cmake"
got="$(env -i PATH="$w/pbin:/usr/bin:/bin" TMPDIR="${TMPDIR:-/tmp}" sh -c ". '$T'; printf '%s|%s' \"\$SHIPYARD\" \"\$SHIPYARD_SCRIPTS\"")" \
  || { echo "FAIL: the probe must find the fixture's shipyard"; exit 1; }
want="$fx/share/cmake/MavericksShipyard/scripts"
[ "$got" = "$want|$want" ] || { echo "FAIL: probe gave '$got', want '$want|$want'"; exit 1; }

mkdir -p "$w/fallback"; ln -s "$fx/bin/cmake" "$w/fallback/shipyard-cmake"
sed "s#$installed_cm#$w/fallback/shipyard-cmake#g" "$T" > "$w/msc-fallback.sh"
got="$(env -i PATH=/usr/bin:/bin TMPDIR="${TMPDIR:-/tmp}" sh -c ". '$w/msc-fallback.sh'; printf '%s' \"\$SHIPYARD\"")" \
  || { echo "FAIL: with shipyard-cmake off PATH (a launchd job, a non-login shell), msc.sh must fall back to the absolute $installed_cm"; exit 1; }
[ "$got" = "$want" ] || { echo "FAIL: the absolute fallback must find that shipyard's scripts; got '$got', want '$want'"; exit 1; }

echo "PASS: msc-template"
