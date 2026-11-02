#!/bin/sh
# platform: macOS-only -- builds the pkg
#   usage: package-pkg.sh --shipyard-prefix DIR --app APP --version V --out PKG
#          Packages shipyard as ONE prefix -- /usr/local/mavergreen/shipyard holding shipyard itself
#          (share/cmake/MavericksShipyard), the launchers bin/shipyard-{cmake,ctest,cpack} into the
#          cmake product, and bin/{cmake,ctest,cpack} linked to them -- plus one universal updater and
#          the dev.mavergreen.base component. The mavergreen helper exports the shipyard-* names
#          into /usr/local/mavergreen/bin, never the bare cmake/ctest/cpack; nothing is installed into
#          /usr/local/bin. The install scripts come from stage_product.sh, and its preinstall refuses
#          a box without the cmake product at .mavergreen/ingredients/cmake/VERSION. The updater is a stopgap
#          until Mavericks Lineup exists.
# spec: 2026-10-09 C4 -- shipyard ships no CMake of its own: the launchers run the cmake product
#       installed beside it, with shipyard on CMAKE_PREFIX_PATH.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "On-target/
#       off-target parity" -- shipyard's own .pkg is the worked example: one artifact serves both
#       boxes because developing under Mavericks and developing under modern macOS are equally
#       first-class, and two pkgs would make someone choose, silently wrong when they choose badly.
#       --host-arch x86_64,arm64 is BOTH arches -- without arm64, Installer on Apple Silicon offers
#       Rosetta for a pkg with scripts and runs them translated, the very prompt this pkg exists to
#       avoid.
# spec: tests/shipyard-package-pkg-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/registry-lookup.sh"
. "$SELF/mavergreen-meta.sh"
SPREFIX=""; APP=""; VER=""; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --shipyard-prefix) SPREFIX="${2%/}"; shift 2;;
    --app) APP="${2%/}"; shift 2;;
    --version) VER="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    *) echo "package-pkg: unknown option $1" >&2; exit 2;;
  esac
done

registry_need package-pkg identifier shipyard; ID="$REG_V"
PREFIX_DIR="/usr/local/mavergreen/shipyard"
registry_need package-pkg updater-app shipyard; APP_REL="$REG_V"
APP_NAME="${APP_REL##*/}"

: "${SPREFIX:?package-pkg: --shipyard-prefix required}"
: "${APP:?package-pkg: --app required}"
: "${VER:?package-pkg: --version required}"
: "${OUT:?package-pkg: --out required}"

[ "$(basename "$APP")" = "$APP_NAME" ] \
  || { echo "package-pkg: --app must be a $APP_NAME (its LaunchAgent runs that name); got $APP" >&2; exit 2; }
[ -d "$APP" ] || { echo "package-pkg: no such app: $APP" >&2; exit 1; }
cmake_min="$(MAVERGREEN_ROOT="$SELF/.." mg_value products/shipyard/requires/cmake/min 2>/dev/null || true)"
[ -n "$cmake_min" ] || { echo "package-pkg: no cmake minimum in $SELF/../.mavergreen/products/shipyard/requires/cmake/min" >&2; exit 1; }
require_only() {  # $1 = flag  $2 = dir  $3 = allowed top-level names, space-separated
  _flag="$1"; _dir="$2"; _allowed="$3"
  for _e in "$_dir"/* "$_dir"/.*; do
    [ -e "$_e" ] || continue                        # an unmatched glob stays literal
    _b="$(basename "$_e")"
    case "$_b" in
      .|..) continue ;;
      ._*) continue ;;                              # stripped from the stage below, so it never ships
    esac
    _ok=no
    for _a in $_allowed; do
      if [ "$_b" = "$_a" ]; then _ok=yes; fi
    done
    [ "$_ok" = yes ] || {
      echo "package-pkg: $_flag has an unexpected top-level entry: $_b" >&2
      echo "    everything in $_dir is installed under $PREFIX_DIR, and the payload is" >&2
      echo "    specified exactly (spec 2026-09-11 decision 1): $_allowed" >&2
      echo "    move $_dir/$_b elsewhere, or add it to the payload deliberately" >&2
      exit 1
    }
  done
}
[ -f "$SPREFIX/share/cmake/MavericksShipyard/MavericksShipyardConfig.cmake" ] \
  || { echo "package-pkg: --shipyard-prefix has no share/cmake/MavericksShipyard: $SPREFIX" >&2; exit 1; }
# spec: 2026-09-11 decision 1 -- the prefix BECOMES the product prefix verbatim, so the enumeration of
#       the payload is a gate rather than a description: a stray shipyard-cmake-tree.tar.gz once
#       shipped a copy of the whole payload inside the payload, and nothing complained.
require_only --shipyard-prefix "$SPREFIX" "bin share"
require_only --shipyard-prefix "$SPREFIX/bin" "cmake ctest cpack shipyard-cmake shipyard-ctest shipyard-cpack shipyard-check shipyard-scripts"
# spec: 2026-10-09 C4 -- the compatibility links keep a build directory configured before the cmake
#       product regenerating, so each must name its launcher.
for c in cmake ctest cpack; do
  { [ -x "$SPREFIX/bin/shipyard-$c" ] && [ ! -L "$SPREFIX/bin/shipyard-$c" ]; } \
    || { echo "package-pkg: --shipyard-prefix has no launcher bin/shipyard-$c: $SPREFIX" >&2; exit 1; }
  [ -L "$SPREFIX/bin/$c" ] && [ "$(readlink "$SPREFIX/bin/$c")" = "shipyard-$c" ] \
    || { echo "package-pkg: --shipyard-prefix bin/$c must be a link to shipyard-$c: $SPREFIX" >&2; exit 1; }
done
# spec: tests/installed-presets-test.sh -- the install bakes its --prefix into the presets' toolchainFile, so this prefix
#       must have been installed AS $PREFIX_DIR (staged under DESTDIR), or every consumer's
#       `cmake --preset` looks for the toolchain file in a directory that exists only on the runner.
presets="$SPREFIX/share/cmake/MavericksShipyard/mavericks-presets.json"
want="$PREFIX_DIR/share/cmake/MavericksShipyard/MavericksToolchain.cmake"
[ -f "$presets" ] || { echo "package-pkg: --shipyard-prefix has no mavericks-presets.json: $presets" >&2; exit 1; }
tcs="$(sed -n 's/^[[:space:]]*"toolchainFile":[[:space:]]*"\([^"]*\)".*/\1/p' "$presets")"
wrong="$(printf '%s\n' "$tcs" | grep -vxF "$want" || true)"
if [ -z "$tcs" ] || [ -n "$wrong" ]; then
  echo "package-pkg: $presets must name toolchainFile $want; it names: ${wrong:-nothing}" >&2
  echo "    install shipyard into the pkg's prefix, staged:" >&2
  echo "    DESTDIR=<stage> shipyard-cmake --install <build> --prefix $PREFIX_DIR" >&2
  echo "    and pass --shipyard-prefix <stage>$PREFIX_DIR" >&2
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/shipyard-pkg.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/stage"; SCR="$WORK/scripts"
mkdir -p "$STAGE$PREFIX_DIR" "$SCR" "$WORK/component" "$(dirname "$OUT")"
COPYFILE_DISABLE=1 cp -R "$SPREFIX"/. "$STAGE$PREFIX_DIR/"

# platform: an NFS or otherwise shared stage sprays AppleDouble "._*" sidecars, which would ship as
#           payload -- and, left in place while the manifest is rendered, be listed in its `outside`.
strip_appledouble() { find "$STAGE" -name '._*' -delete 2>/dev/null || true; }
strip_appledouble
sh "$SELF/stage_product.sh" --stage "$STAGE" --product shipyard --name "Mavericks Shipyard" \
  --version "$VER" --exclude bin/cmake --exclude bin/ctest --exclude bin/cpack \
  --requires "cmake>=$cmake_min" --updater-app "$APP" --scripts-out "$SCR"
strip_appledouble

# platform: pkgbuild makes a payload holding a .app relocatable and version-checked, so a locally
#           built updater elsewhere on disk would capture it; build_component_pkg.sh does not.
comp="$WORK/component/mavericks-shipyard.pkg"
sh "$SELF/build_component_pkg.sh" --root "$STAGE" --identifier "$ID" --version "$VER" \
  --install-location / --scripts "$SCR" --out "$comp" >&2

sh "$SELF/set_install_floor.sh" \
  --identifier "$ID" \
  --title "Mavericks Shipyard ${VER}" \
  --component "$comp" \
  --out "$OUT" \
  --host-arch x86_64,arm64 \
  --base-version "$VER" \
  --require-scripts >&2

echo "built $OUT" >&2
