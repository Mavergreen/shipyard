#!/bin/sh
# platform: macOS-only -- productbuild and pkgutil write the distribution
#   usage: set_install_floor.sh --identifier ID --title T --component COMP.pkg --out OUT.pkg
#            [--resources DIR] [--welcome FILE] [--license FILE]
#            [--require-scripts] [--host-arch x86_64] [--min-os 10.9.5]
#          Wraps a flat component pkg into a distributable product archive that enforces a hard OS
#          install floor (default MAVERICKS_MIN_OS, the single source of truth for "the Mavericks
#          install floor" across the family) via productbuild --distribution -- a bare pkgbuild
#          product cannot express an OS floor. Generates distribution.xml from flags (single-
#          component installer), runs productbuild, then self-checks that the floor made it into the
#          output pkg.
# spec: tests/shipyard-package-pkg-test.sh -- package-pkg.sh's own integration coverage exercises
#       --host-arch end to end (both architectures must reach the Distribution).
set -eu

MIN_OS="${MAVERICKS_MIN_OS:-10.9.5}"
ID=""; TITLE=""; COMPONENT=""; OUT=""; RES=""; WELCOME=""; LICENSE=""
REQSCRIPTS="false"; HOSTARCH=""

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
    *) echo "productbuild_floor: unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$ID" ] && [ -n "$TITLE" ] && [ -n "$COMPONENT" ] && [ -n "$OUT" ] \
  || { echo "productbuild_floor: need --identifier --title --component --out" >&2; exit 2; }
[ -f "$COMPONENT" ] || { echo "productbuild_floor: no component pkg: $COMPONENT" >&2; exit 1; }

COMP_DIR=$(dirname "$COMPONENT"); COMP_BASE=$(basename "$COMPONENT")
DIST=$(mktemp -t distribution.XXXXXX.xml)
trap 'rm -f "$DIST"' EXIT

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
  echo "    <choices-outline><line choice=\"default\"><line choice=\"$ID\"/></line></choices-outline>"
  echo '    <choice id="default"/>'
  echo "    <choice id=\"$ID\" visible=\"false\"><pkg-ref id=\"$ID\"/></choice>"
  echo "    <pkg-ref id=\"$ID\" version=\"0\" onConclusion=\"none\">$COMP_BASE</pkg-ref>"
  echo '</installer-gui-script>'
} > "$DIST"

if [ -n "$RES" ]; then
  productbuild --distribution "$DIST" --resources "$RES" --package-path "$COMP_DIR" "$OUT"
else
  productbuild --distribution "$DIST" --package-path "$COMP_DIR" "$OUT"
fi

X=$(mktemp -d -t pkgfloor.XXXXXX)
pkgutil --expand "$OUT" "$X/x"
got=$(grep -o 'os-version min="[0-9.]*"' "$X/x/Distribution" || true)
rm -rf "$X"
[ "$got" = "os-version min=\"$MIN_OS\"" ] \
  || { echo "productbuild_floor: FLOOR MISSING/WRONG in $OUT (got: ${got:-none}, want $MIN_OS)" >&2; exit 1; }
echo "productbuild_floor: $OUT built, install floor $MIN_OS enforced"
