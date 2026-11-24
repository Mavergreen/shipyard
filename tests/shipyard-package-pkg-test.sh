#!/bin/sh
# platform: host-agnostic
# spec: 2026-10-09 C4 -- the pkg is ONE prefix holding shipyard, its three launchers into the cmake
#       product it requires, exported through the mavergreen link farm. No updater, no registration,
#       no arch picking.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
S="$root/scripts/package-pkg.sh"
[ -f "$S" ] || { echo "FAIL: no scripts/package-pkg.sh"; exit 1; }
w="$(mktemp -d "${TMPDIR:-/tmp}/pkg-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
code() { grep -v '^[[:space:]]*#' "$S"; }   # the script minus its comments

code | grep -q -- '--host-arch\|--min-os' && { echo "FAIL: package-pkg.sh passes no --host-arch or --min-os; set_install_floor.sh derives the arches and the floor from the payload"; exit 1; }
mkdir -p "$w/np/opt/mavergreen/shipyard" "$w/npc"; printf '#!/bin/sh\nexit 0\n' > "$w/np/opt/mavergreen/shipyard/tool"
SD="$(sh "$root/scripts/fetch_stevedore.sh")" || { echo "FAIL: fetch_stevedore.sh failed"; exit 1; }
"$SD" component --root "$w/np" --identifier dev.mavergreen.shipyard --version 1.0 --install-location / --mtime 1700000000 --out "$w/npc/shipyard.pkg" >/dev/null
npout="$(SOURCE_DATE_EPOCH=1700000000 MAVERGREEN_REPO_ROOT="$root" sh "$root/scripts/set_install_floor.sh" --short shipyard --version 1.0.0 --component "$w/npc/shipyard.pkg" --dist "$w/npd" --base-version 1.0.0 2>/dev/null)" \
  || { echo "FAIL: a neutral shipyard payload must build"; exit 1; }
"$SD" expand "$npout" "$w/npx" >/dev/null
grep -q '<os-version min="10.9.5"/>' "$w/npx/Distribution" \
  || { echo "FAIL: shipyard is neutral and serves modern developers (newer-macos/modern-developers), so its OS range has no before"; exit 1; }
grep -q 'installation-check' "$w/npx/Distribution" && { echo "FAIL: a neutral shipyard pkg has no installation-check"; exit 1; }
for gone in register-with-cmake sysctl agent-load-cross uname CrossUpdater modernmavericks mavergreen-shipyard emit-preinstall --title; do
  code | grep -q -- "$gone" && { echo "FAIL: package-pkg.sh still mentions $gone"; exit 1; }
done
for c in cmake ctest cpack; do
  code | grep -q -- "--exclude bin/$c" \
    || { echo "FAIL: bin/$c must be in exports-exclude -- a bare $c in the link farm would shadow whatever cmake the user already has on the path"; exit 1; }
done
grep -q 'file(CREATE_LINK "\.\./\${_dest}/scripts/shipyard-check" "\${CMAKE_CURRENT_BINARY_DIR}/compat/shipyard-check" SYMBOLIC)' "$root/CMakeLists.txt" \
  || { echo "FAIL: shipyard's cmake --install must make bin/shipyard-check a RELATIVE link into shipyard's own scripts, so the farm exports the one command CI and developers share"; exit 1; }
grep -q 'file(CREATE_LINK "\.\./\${_dest}/scripts/shipyard-scripts" "\${CMAKE_CURRENT_BINARY_DIR}/compat/shipyard-scripts" SYMBOLIC)' "$root/CMakeLists.txt" \
  || { echo "FAIL: shipyard's cmake --install must make bin/shipyard-scripts a RELATIVE link into shipyard's own scripts"; exit 1; }
grep -q 'file(CREATE_LINK "\.\./\${_dest}/scripts/shipyard-provision" "\${CMAKE_CURRENT_BINARY_DIR}/compat/shipyard-provision" SYMBOLIC)' "$root/CMakeLists.txt" \
  || { echo "FAIL: shipyard's cmake --install must make bin/shipyard-provision a RELATIVE link into shipyard's own scripts"; exit 1; }
code | grep -q 'require_only --shipyard-prefix "\$SPREFIX/bin" "[^"]* shipyard-provision' \
  || { echo "FAIL: package-pkg.sh must accept bin/shipyard-provision in the payload"; exit 1; }
code | grep -q 'require_only --shipyard-prefix "\$SPREFIX/bin" "[^"]* shipyard-scripts' \
  || { echo "FAIL: package-pkg.sh must accept bin/shipyard-scripts in the payload"; exit 1; }
code | grep -q 'require_only --shipyard-prefix "\$SPREFIX/bin" "[^"]* shipyard-check' \
  || { echo "FAIL: package-pkg.sh must accept bin/shipyard-check in the payload"; exit 1; }
code | grep -q -- '--exclude bin/shipyard-check' \
  && { echo "FAIL: bin/shipyard-check must be exported through the link farm, not excluded"; exit 1; }
code | grep -q 'ln -s' && { echo "FAIL: package-pkg.sh makes links of its own; the launchers and compatibility links come from shipyard's cmake --install"; exit 1; }
code | grep -q -- '--cmake-tree' && { echo "FAIL: package-pkg.sh still takes --cmake-tree; CMake is the cmake product's now, never shipyard's payload"; exit 1; }
# spec: 2026-10-09 C4 -- the preinstall refuses a box without the cmake product at shipyard's pin.
code | grep -q -- '--requires' \
  && { echo "FAIL: package-pkg.sh passes no --requires; stage_product.sh reads .mavergreen/products/shipyard/requires/cmake/"; exit 1; }
[ -s "$root/.mavergreen/products/shipyard/requires/cmake/min" ] && [ -s "$root/.mavergreen/ingredients/cmake/REPO" ] \
  || { echo "FAIL: the cmake requirement's min and its releases' REPO are declared in .mavergreen/, where stage_product.sh reads them"; exit 1; }
code | grep -q 'PREFIX_DIR="$(mavergreen_prefix shipyard)"' \
  || { echo "FAIL: shipyard installs into mavergreen_prefix shipyard, the one directory its short name owns"; exit 1; }
code | grep -q 'usr/local' && { echo "FAIL: shipyard installs nothing under /usr/local"; exit 1; }
code | grep -q 'updater-identity\|--updater-app' && { echo "FAIL: shipyard's pkg ships no updater; package-pkg.sh stages none"; exit 1; }
code | grep -q 'registry' && { echo "FAIL: package-pkg.sh derives shipyard's identity; it reads no registry"; exit 1; }
code | grep -q 'stage_product.sh' || { echo "FAIL: shipyard gets its install scripts from stage_product.sh like every product"; exit 1; }
code | grep -q -- '--base-version "\$VER"' \
  || { echo "FAIL: the base component shipyard ships must be stamped with the version being built (--base-version \"\$VER\")"; exit 1; }

code | grep -q 'set_install_floor.sh" --short shipyard ' \
  || { echo "FAIL: shipyard's archive is named, titled and identified by set_install_floor.sh --short shipyard, like every product's"; exit 1; }
for missing in --shipyard-prefix --version --dist; do
  args="--shipyard-prefix $w/p --version 1.0.0 --dist $w/o"
  args="$(printf '%s' "$args" | sed "s|$missing [^ ]*||")"
  # shellcheck disable=SC2086
  if err="$(sh "$S" $args 2>&1 >/dev/null)"; then echo "FAIL: $missing must be required"; exit 1; fi
  printf '%s\n' "$err" | grep -q -- "$missing" \
    || { echo "FAIL: the refusal for a missing $missing must name it; got '$err'"; exit 1; }
done
rc=0
err="$(sh "$S" --shipyard-prefix "$w/p" --version 1.0.0 --dist "$w/o" --out "$w/o.pkg" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: --out is refused as a usage error (exit 2); got $rc"; exit 1; }
printf '%s\n' "$err" | grep -qF 'the filename is derived, <short>-<version>.pkg; pass --dist' \
  || { echo "FAIL: the refusal of --out names its fix; got '$err'"; exit 1; }
rc=0
err="$(sh "$S" --shipyard-prefix "$w/p" --app "$w/shipyard-updater.app" --version 1.0.0 --dist "$w/o" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: --app is refused as a usage error (exit 2), since the pkg ships no updater; got $rc"; exit 1; }
printf '%s\n' "$err" | grep -q -- '--app' || { echo "FAIL: the refusal of --app names it; got '$err'"; exit 1; }

# spec: 2026-09-11 decision 1 -- --shipyard-prefix BECOMES the product prefix verbatim, so a stray
#       file in it (a tarball, a .DS_Store, a build dir) would otherwise install into
#       /opt/mavergreen/shipyard.
mkfixture() {  # $1 = dir: a shipyard prefix that passes every other check
  rm -rf "$1"
  mkdir -p "$1/sp/bin" "$1/sp/share/cmake/MavergreenShipyard"
  for c in cmake ctest cpack; do
    printf '#!/bin/sh\n' > "$1/sp/bin/shipyard-$c"; chmod +x "$1/sp/bin/shipyard-$c"
    ln -s "shipyard-$c" "$1/sp/bin/$c"
  done
  : > "$1/sp/share/cmake/MavergreenShipyard/MavergreenShipyardConfig.cmake"
  presets "$1" /opt/mavergreen/shipyard
  : > "$1/notadir"
}
presets() {  # $1 = fixture dir  $2 = the prefix its installed presets name
  _t="$2/share/cmake/MavergreenShipyard/MavergreenToolchain.cmake"
  printf '{ "configurePresets": [\n  { "name": "a",\n    "toolchainFile": "%s" },\n  { "name": "b",\n    "toolchainFile": "%s" } ] }\n' \
    "$_t" "$_t" > "$1/sp/share/cmake/MavergreenShipyard/mavergreen-presets.json"
}
# platform: --dist under a plain FILE, so a fixture that passes every input check stops at the first
#           mkdir after them -- exercising the checks without pkgbuild, and without a special case
#           for valid input.
run_pkg() {  # $1 = fixture dir; sets $rc and $err
  rc=0
  err="$(sh "$S" --shipyard-prefix "$1/sp" --version 1.0.0 --dist "$1/notadir/o" 2>&1 >/dev/null)" || rc=$?
}
mkfixture "$w/fa"; run_pkg "$w/fa"
[ "$rc" -ne 0 ] || { echo "FAIL: the fixture was built to stop at --dist; it did not fail at all"; exit 1; }
printf '%s\n' "$err" | grep -q 'notadir' \
  || { echo "FAIL: bin (three launchers, three compatibility links) and share are the payload; the fixture must pass every check and stop at --dist; got '$err'"; exit 1; }
mkfixture "$w/fc"; mkdir -p "$w/fc/sp/build"; run_pkg "$w/fc"
[ "$rc" -ne 0 ] || { echo "FAIL: a stray dir at the --shipyard-prefix root must be refused"; exit 1; }
printf '%s\n' "$err" | grep -q 'build' \
  || { echo "FAIL: the refusal must name the stray entry; got '$err'"; exit 1; }
printf '%s\n' "$err" | grep -q -- '--shipyard-prefix' \
  || { echo "FAIL: the refusal must name the flag that carried it; got '$err'"; exit 1; }
mkfixture "$w/fs"; : > "$w/fs/sp/bin/shipyard-cmake-tree.tar.gz"; run_pkg "$w/fs"
[ "$rc" -ne 0 ] || { echo "FAIL: a stray file in --shipyard-prefix's bin must be refused"; exit 1; }
printf '%s\n' "$err" | grep -q 'shipyard-cmake-tree.tar.gz' \
  || { echo "FAIL: the refusal must name the stray entry; got '$err'"; exit 1; }
for c in cmake ctest cpack; do
  mkfixture "$w/fl"; rm "$w/fl/sp/bin/shipyard-$c"; run_pkg "$w/fl"
  printf '%s\n' "$err" | grep -q "bin/shipyard-$c" \
    || { echo "FAIL: a --shipyard-prefix with no launcher bin/shipyard-$c must be refused, naming it; got '$err'"; exit 1; }
  mkfixture "$w/fk"; rm "$w/fk/sp/bin/$c"; cp "$w/fk/sp/bin/shipyard-$c" "$w/fk/sp/bin/$c"; run_pkg "$w/fk"
  printf '%s\n' "$err" | grep -q "bin/$c" \
    || { echo "FAIL: bin/$c must be the compatibility link to shipyard-$c, so a build directory configured before the cmake product still regenerates; got '$err'"; exit 1; }
done

# spec: scripts/package-pkg.sh -- the install bakes its --prefix into the presets' toolchainFile, so a prefix
#       installed anywhere but the pkg's own (a bare `--prefix "$RUNNER_TEMP/..."`) ships presets naming
#       a runner's temp dir, and every consumer's `cmake --preset` fails.
mkfixture "$w/fd"; presets "$w/fd" "$w/fd/sp"; run_pkg "$w/fd"
[ "$rc" -ne 0 ] || { echo "FAIL: presets naming a toolchain file outside the pkg's prefix must be refused"; exit 1; }
printf '%s\n' "$err" | grep -q 'toolchainFile' \
  || { echo "FAIL: the refusal must say it is the presets' toolchainFile that is wrong; got '$err'"; exit 1; }
printf '%s\n' "$err" | grep -q 'DESTDIR' \
  || { echo "FAIL: the refusal must say how to stage the install (DESTDIR); got '$err'"; exit 1; }
mkfixture "$w/fe"; rm "$w/fe/sp/share/cmake/MavergreenShipyard/mavergreen-presets.json"; run_pkg "$w/fe"
printf '%s\n' "$err" | grep -q 'mavergreen-presets.json' \
  || { echo "FAIL: a --shipyard-prefix with no mavergreen-presets.json must be refused, naming it; got '$err'"; exit 1; }

echo "PASS: shipyard-package-pkg"
