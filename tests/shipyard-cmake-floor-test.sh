#!/bin/sh
# platform: host-agnostic
#   usage: shipyard-cmake-floor-test.sh
#          The configured minimum cmake and the pkg's --requires cmake>= are one floor, read from
#          .mavergreen/products/shipyard/requires/cmake/min: a copy whose cmake pin is bumped above it
#          still configures, and packages, with that min. Exit 0 clean, 1 on failure, 77 with no cmake.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
cm="$(command -v cmake 2>/dev/null)" || { echo "SKIP: no cmake"; exit 77; }
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/shipyard-cmake-floor.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
src="$w/src"; mkdir "$src"
(cd "$root" && tar cf - --exclude ./.git --exclude ./tests .) | (cd "$src" && tar xf -)
min="$(sed -n 1p "$src/.mavergreen/products/shipyard/requires/cmake/min")"
[ -n "$min" ] || { echo "FAIL: .mavergreen/products/shipyard/requires/cmake/min is empty"; exit 1; }
printf '99.0.0-mavericks.1\n# renovate: datasource=github-releases depName=Mavergreen/cmake\n' > "$src/.mavergreen/ingredients/cmake/VERSION"

"$cm" -S "$src" -B "$w/b" > "$w/c.log" 2>&1 || { echo "FAIL: the copy does not configure:"; sed 's/^/    | /' "$w/c.log"; exit 1; }
baked="$(sed -n 's/^ *set(_shipyard_cmake_min "\(.*\)")$/\1/p' "$w/b/MavericksShipyardConfig.cmake")"
[ "$baked" = "${min%%-mavericks.*}" ] \
  || fail "the configured minimum must be the Kitware part of requires/cmake/min ($min), not the bumped pin; got '$baked'"

printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/stage-args"\nexit 3\n' "$w" > "$src/scripts/stage_product.sh"
p="$w/prefix"; mkdir -p "$p/bin" "$p/share/cmake/MavericksShipyard"
: > "$p/share/cmake/MavericksShipyard/MavericksShipyardConfig.cmake"
printf '{\n  "toolchainFile": "/usr/local/mavergreen/shipyard/share/cmake/MavericksShipyard/MavericksToolchain.cmake"\n}\n' \
  > "$p/share/cmake/MavericksShipyard/mavericks-presets.json"
for c in cmake ctest cpack; do
  printf '#!/bin/sh\n' > "$p/bin/shipyard-$c"; chmod +x "$p/bin/shipyard-$c"; ln -s "shipyard-$c" "$p/bin/$c"
done
mkdir "$w/shipyard-updater.app"
rc=0; sh "$src/scripts/package-pkg.sh" --shipyard-prefix "$p" --app "$w/shipyard-updater.app" --version 1.0.1 --out "$w/o.pkg" > "$w/p.log" 2>&1 || rc=$?
[ "$rc" -eq 3 ] && [ -f "$w/stage-args" ] || { echo "FAIL: package-pkg.sh did not reach stage_product.sh (exit $rc):"; sed 's/^/    | /' "$w/p.log"; exit 1; }
grep -qxF "cmake>=$min" "$w/stage-args" \
  || fail "the pkg must require cmake>=$min from requires/cmake/min, not the bumped pin; got: $(grep 'cmake>=' "$w/stage-args" || echo none)"

[ "$fails" -eq 0 ] || { echo "FAIL: $fails case(s) in shipyard-cmake-floor"; exit 1; }
echo "PASS: shipyard-cmake-floor"
