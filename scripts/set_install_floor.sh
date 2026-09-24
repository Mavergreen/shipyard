#!/bin/sh
# platform: macOS-only -- productbuild and pkgutil write the distribution
#   usage: set_install_floor.sh --identifier ID --title T --component COMP.pkg --out OUT.pkg
#            [--resources DIR] [--welcome FILE] [--license FILE]
#            [--require-scripts] [--host-arch x86_64] [--min-os 10.9.5] [--base-version V]
#          Wraps a flat component pkg into a distributable product archive that enforces a hard OS
#          install floor (default MAVERICKS_MIN_OS, the single source of truth for "the Mavericks
#          install floor" across the family) via productbuild --distribution -- a bare pkgbuild
#          product cannot express an OS floor. Generates distribution.xml from flags (single-
#          component installer), runs productbuild, then self-checks that the floor made it into the
#          output pkg. Every archive also carries dev.mavergreen.base (built via
#          build-base-component.sh, --base-version picks its version; default: the base's own
#          default) and lists it FIRST in the choices-outline, so its payload lands before the
#          product's own scripts run. The base component is built into a private temp directory, not
#          the caller's --component directory, so a caller that globs that directory afterward never
#          sees it.
# spec: tests/shipyard-package-pkg-test.sh -- package-pkg.sh's own integration coverage exercises
#       --host-arch end to end (both architectures must reach the Distribution).
# spec: tests/set-install-floor-base-test.sh -- the base component must be first in the
#       choices-outline: Installer lays down every component's payload before running any
#       postinstall, in Distribution order, so a product's postinstall can rely on the helper only
#       if the base's payload already landed.
set -eu

MIN_OS="${MAVERICKS_MIN_OS:-10.9.5}"
ID=""; TITLE=""; COMPONENT=""; OUT=""; RES=""; WELCOME=""; LICENSE=""
REQSCRIPTS="false"; HOSTARCH=""; BASEVER=""

while [ $# -gt 0 ]; do
  case "$1" in
    --identifier) ID="$2"; shift 2;;
    --title) TITLE="$2"; shift 2;;
    --component) COMPONENT="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --resources) RES="$2"; shift 2;;
    --welcome) WELCOME="$2"; shift 2;;
    --license) LICENSE="$2"; shift 2;;
    --require-scripts) REQSCRIPTS="true"; shift;;
    --host-arch) HOSTARCH="$2"; shift 2;;
    --min-os) MIN_OS="$2"; shift 2;;
    --base-version) BASEVER="$2"; shift 2;;
    *) echo "productbuild_floor: unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$ID" ] && [ -n "$TITLE" ] && [ -n "$COMPONENT" ] && [ -n "$OUT" ] \
  || { echo "productbuild_floor: need --identifier --title --component --out" >&2; exit 2; }
[ "$ID" != dev.mavergreen.base ] \
  || { echo "productbuild_floor: --identifier may not be dev.mavergreen.base -- the base component is added automatically" >&2; exit 2; }
[ -f "$COMPONENT" ] || { echo "productbuild_floor: no component pkg: $COMPONENT" >&2; exit 1; }

COMP_DIR=$(dirname "$COMPONENT"); COMP_BASE=$(basename "$COMPONENT")
[ "$COMP_BASE" != mavergreen-base.pkg ] || { echo "productbuild_floor: the product component may not be named mavergreen-base.pkg" >&2; exit 2; }
BASEDIR=$(mktemp -d "${TMPDIR:-/tmp}/mavergreen-base.XXXXXX")
DIST=$(mktemp -t distribution.XXXXXX.xml)
trap 'rm -f "$DIST"; rm -rf "$BASEDIR"' EXIT

BASE="$BASEDIR/mavergreen-base.pkg"
if [ -n "$BASEVER" ]; then
  sh "$(dirname "$0")/build-base-component.sh" --version "$BASEVER" --out "$BASE" >&2
else
  sh "$(dirname "$0")/build-base-component.sh" --out "$BASE" >&2
fi

_opts="customize=\"never\" require-scripts=\"$REQSCRIPTS\""
[ -n "$HOSTARCH" ] && _opts="$_opts hostArchitectures=\"$HOSTARCH\""

{
  echo '<?xml version="1.0" encoding="utf-8"?>'
  echo '<installer-gui-script minSpecVersion="1">'
  echo "    <title>$TITLE</title>"
  [ -n "$WELCOME" ] && echo "    <welcome file=\"$(basename "$WELCOME")\" mime-type=\"text/html\"/>"
  [ -n "$LICENSE" ] && echo "    <license file=\"$(basename "$LICENSE")\"/>"
  echo "    <allowed-os-versions><os-version min=\"$MIN_OS\"/></allowed-os-versions>"
  echo "    <options $_opts/>"
  echo "    <choices-outline><line choice=\"default\"><line choice=\"dev.mavergreen.base\"/><line choice=\"$ID\"/></line></choices-outline>"
  echo '    <choice id="default"/>'
  echo '    <choice id="dev.mavergreen.base" visible="false"><pkg-ref id="dev.mavergreen.base"/></choice>'
  echo "    <choice id=\"$ID\" visible=\"false\"><pkg-ref id=\"$ID\"/></choice>"
  echo '    <pkg-ref id="dev.mavergreen.base" version="0" onConclusion="none">mavergreen-base.pkg</pkg-ref>'
  echo "    <pkg-ref id=\"$ID\" version=\"0\" onConclusion=\"none\">$COMP_BASE</pkg-ref>"
  echo '</installer-gui-script>'
} > "$DIST"

if [ -n "$RES" ]; then
  productbuild --distribution "$DIST" --resources "$RES" --package-path "$COMP_DIR" --package-path "$BASEDIR" "$OUT"
else
  productbuild --distribution "$DIST" --package-path "$COMP_DIR" --package-path "$BASEDIR" "$OUT"
fi

X=$(mktemp -d -t pkgfloor.XXXXXX)
pkgutil --expand "$OUT" "$X/x"
got=$(grep -o 'os-version min="[0-9.]*"' "$X/x/Distribution" || true)
first="$(sed -n 's/.*<line choice="\([^"]*\)".*/\1/p' "$X/x/Distribution" | grep -v '^default$' | head -1)"
rm -rf "$X"
[ "$got" = "os-version min=\"$MIN_OS\"" ] \
  || { echo "productbuild_floor: FLOOR MISSING/WRONG in $OUT (got: ${got:-none}, want $MIN_OS)" >&2; exit 1; }
[ "$first" = dev.mavergreen.base ] \
  || { echo "productbuild_floor: dev.mavergreen.base is not first in $OUT" >&2; exit 1; }
echo "productbuild_floor: $OUT built, install floor $MIN_OS enforced"
