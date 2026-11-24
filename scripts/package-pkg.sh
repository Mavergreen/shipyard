#!/bin/sh
# platform: host-agnostic
#   usage: package-pkg.sh --shipyard-prefix DIR --version V --dist DIR
#          package-pkg.sh --shipyard-prefix DIR --version V --tree-only DEST [--installed-as P]
#          Packages shipyard as ONE prefix -- /opt/mavergreen/shipyard holding shipyard itself
#          (share/cmake/MavergreenShipyard), the launchers bin/shipyard-{cmake,ctest,cpack} into the
#          cmake product, and bin/{cmake,ctest,cpack} linked to them -- plus the dev.mavergreen.base
#          component. It ships no updater, so --app is refused. The mavergreen helper exports the shipyard-* names
#          into /opt/mavergreen/bin, never the bare cmake/ctest/cpack. The install scripts come from
#          stage_product.sh, and its preinstall refuses a box without the cmake product at or above
#          .mavergreen/products/shipyard/requires/cmake/min. The pkg is DIR/shipyard-V.pkg.
#          --tree-only stops before the pkg: DEST gets the prefix as the pkg installs it,
#          mavergreen.plist included. --installed-as is the prefix DIR was
#          installed as (default $(mavergreen_prefix shipyard)), which its presets must name.
# spec: 2026-10-09 C4 -- shipyard ships no CMake of its own: the launchers run the cmake product
#       installed beside it, with shipyard on CMAKE_PREFIX_PATH.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "On-target/
#       off-target parity" -- shipyard's own .pkg is the worked example: one artifact serves both
#       boxes because developing under Mavericks and developing under modern macOS are equally
#       first-class, and two pkgs would make someone choose, silently wrong when they choose badly.
# spec: tests/shipyard-package-pkg-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavergreen-meta.sh"
. "$SELF/lib/name-rules.sh"
MAVERGREEN_REPO_ROOT="$SELF/.."; export MAVERGREEN_REPO_ROOT
SPREFIX=""; VER=""; DISTDIR=""; TREE=""; AS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --shipyard-prefix) SPREFIX="${2%/}"; shift 2;;
    --app) echo "package-pkg: --app is refused; shipyard's pkg ships no updater, the Engine updates it" >&2; exit 2;;
    --version) VER="$2"; shift 2;;
    --out) echo "package-pkg: --out is refused; the filename is derived, <short>-<version>.pkg; pass --dist" >&2; exit 2;;
    --dist) DISTDIR="$2"; shift 2;;
    --tree-only) TREE="${2%/}"; shift 2;;
    --installed-as) AS="${2%/}"; shift 2;;
    *) echo "package-pkg: unknown option $1" >&2; exit 2;;
  esac
done

ID="$(mavergreen_name identifier shipyard)" || exit $?
PREFIX_DIR="$(mavergreen_prefix shipyard)"

: "${SPREFIX:?package-pkg: --shipyard-prefix required}"
: "${VER:?package-pkg: --version required}"
if [ -n "$TREE" ]; then
  [ -z "$DISTDIR" ] || { echo "package-pkg: --tree-only builds no pkg, so it takes no --dist" >&2; exit 2; }
  [ ! -e "$TREE" ] || { echo "package-pkg: --tree-only $TREE already exists" >&2; exit 1; }
else
  [ -z "$AS" ] || { echo "package-pkg: --installed-as goes with --tree-only; the pkg installs at $PREFIX_DIR" >&2; exit 2; }
  : "${DISTDIR:?package-pkg: --dist required}"
fi
case "${AS:-/}" in /*) : ;; *) echo "package-pkg: --installed-as must be absolute: $AS" >&2; exit 2 ;; esac
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
[ -f "$SPREFIX/share/cmake/MavergreenShipyard/MavergreenShipyardConfig.cmake" ] \
  || { echo "package-pkg: --shipyard-prefix has no share/cmake/MavergreenShipyard: $SPREFIX" >&2; exit 1; }
# spec: 2026-09-11 decision 1 -- the prefix BECOMES the product prefix verbatim, so the enumeration of
#       the payload is a gate rather than a description: a stray shipyard-cmake-tree.tar.gz once
#       shipped a copy of the whole payload inside the payload, and nothing complained.
require_only --shipyard-prefix "$SPREFIX" "bin share"
require_only --shipyard-prefix "$SPREFIX/bin" "cmake ctest cpack shipyard-cmake shipyard-ctest shipyard-cpack shipyard-check shipyard-scripts shipyard-provision"
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
presets="$SPREFIX/share/cmake/MavergreenShipyard/mavergreen-presets.json"
want="${AS:-$PREFIX_DIR}/share/cmake/MavergreenShipyard/MavergreenToolchain.cmake"
[ -f "$presets" ] || { echo "package-pkg: --shipyard-prefix has no mavergreen-presets.json: $presets" >&2; exit 1; }
tcs="$(sed -n 's/^[[:space:]]*"toolchainFile":[[:space:]]*"\([^"]*\)".*/\1/p' "$presets")"
wrong="$(printf '%s\n' "$tcs" | grep -vxF "$want" || true)"
if [ -z "$tcs" ] || [ -n "$wrong" ]; then
  echo "package-pkg: $presets must name toolchainFile $want; it names: ${wrong:-nothing}" >&2
  echo "    install shipyard into the pkg's prefix, staged:" >&2
  echo "    sh scripts/stage-shipyard-prefix.sh --stage <stage> --build <build> --prefix ${AS:-$PREFIX_DIR}" >&2
  echo "    (it runs DESTDIR=<stage> cmake --install <build> --prefix ${AS:-$PREFIX_DIR})" >&2
  echo "    and pass --shipyard-prefix <stage>${AS:-$PREFIX_DIR}" >&2
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/shipyard-pkg.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/stage"; SCR="$WORK/scripts"
mkdir -p "$STAGE$PREFIX_DIR" "$SCR" "$WORK/component"
# platform: ubuntu-latest's mkdir says only "mkdir: Already exists", naming no path, so this names it.
[ -n "$TREE" ] || mkdir -p "$DISTDIR" || { echo "package-pkg: cannot make the --dist directory $DISTDIR" >&2; exit 1; }
COPYFILE_DISABLE=1 cp -R "$SPREFIX"/. "$STAGE$PREFIX_DIR/"

# platform: an NFS or otherwise shared stage sprays AppleDouble "._*" sidecars, which would ship as
#           payload.
strip_appledouble() { find "$STAGE" -name '._*' -delete 2>/dev/null || true; }
strip_appledouble
set -- --stage "$STAGE" --product shipyard \
  --version "$VER" --exclude bin/cmake --exclude bin/ctest --exclude bin/cpack \
  --scripts-out "$SCR"
sh "$SELF/stage_product.sh" "$@"
strip_appledouble
if [ -n "$TREE" ]; then
  mkdir -p "$TREE" && cp -R "$STAGE$PREFIX_DIR"/. "$TREE/" || { echo "package-pkg: cannot copy the staged prefix to $TREE" >&2; exit 1; }
  echo "staged $TREE" >&2
  exit 0
fi

comp="$WORK/component/$(mavergreen_name component shipyard)"
sh "$SELF/build_component_pkg.sh" --root "$STAGE" --identifier "$ID" --version "$VER" \
  --install-location / --scripts "$SCR" --out "$comp" >&2

OUT="$(sh "$SELF/set_install_floor.sh" --short shipyard \
  --version "$VER" \
  --component "$comp" \
  --dist "$DISTDIR" \
  --base-version "$VER" \
  --require-scripts)"

echo "built $OUT" >&2
