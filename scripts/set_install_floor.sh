#!/bin/sh
# platform: macOS-only -- productbuild and pkgutil write the distribution
#   usage: set_install_floor.sh --identifier ID --title T --component COMP.pkg --out OUT.pkg
#            [--resources DIR] [--welcome FILE] [--license FILE] [--conclusion FILE]
#            [--require-scripts] [--host-arch x86_64] [--min-os 10.9.5] [--base-version V]
#          FILE for --welcome, --license and --conclusion names a file inside --resources.
#          Wraps a flat component pkg into a distributable product archive that enforces a hard OS
#          install floor (default MAVERICKS_MIN_OS, the single source of truth for "the Mavericks
#          install floor" across the family) via productbuild --distribution -- a bare pkgbuild
#          product cannot express an OS floor. Generates distribution.xml from flags, runs
#          productbuild, then self-checks that the floor made it into the output pkg. Every archive
#          also carries dev.mavergreen.base (built via build-base-component.sh, --base-version picks
#          its version; default: the base's own default) and lists it FIRST in the choices-outline,
#          so its postinstall -- which installs or upgrades /usr/local/bin/mavergreen -- runs before
#          the product's postinstall runs the helper. The base component is built into a private
#          temp directory, not the caller's --component directory, so a caller that globs that
#          directory afterward never sees it.
# spec: tests/shipyard-package-pkg-test.sh -- package-pkg.sh's own integration coverage exercises
#       --host-arch end to end (both architectures must reach the Distribution).
# spec: tests/set-install-floor-base-test.sh -- the base component must be first in the
#       choices-outline: Installer runs the components' postinstalls in Distribution order, after
#       every payload has landed, so only a base listed first has installed or upgraded the helper
#       by the time the product's postinstall runs it.
set -eu

MIN_OS="${MAVERICKS_MIN_OS:-10.9.5}"
ID=""; TITLE=""; COMPONENT=""; OUT=""; RES=""; WELCOME=""; LICENSE=""; CONCLUSION=""
REQSCRIPTS="false"; HOSTARCH=""; BASEVER=""

while [ $# -gt 0 ]; do
  case "$1" in
    --identifier|--title|--component|--out|--resources|--welcome|--license|--conclusion|--host-arch|--min-os|--base-version)
      [ $# -ge 2 ] || { echo "productbuild_floor: $1 needs a value" >&2; exit 2; } ;;
  esac
  case "$1" in
    --identifier) ID="$2"; shift 2;;
    --title) TITLE="$2"; shift 2;;
    --component) COMPONENT="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --resources) RES="$2"; shift 2;;
    --welcome) WELCOME="$2"; shift 2;;
    --license) LICENSE="$2"; shift 2;;
    --conclusion) CONCLUSION="$2"; shift 2;;
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
[ -z "$CONCLUSION" ] || [ -n "$RES" ] \
  || { echo "productbuild_floor: --conclusion needs --resources, the directory holding the file" >&2; exit 2; }
case "$WELCOME" in
  */*|*'"'*|*'&'*|*'<'*) echo "productbuild_floor: --welcome must be a plain file name, no / \" & or < -- it is interpolated into the Distribution XML" >&2; exit 2;;
esac
case "$LICENSE" in
  */*|*'"'*|*'&'*|*'<'*) echo "productbuild_floor: --license must be a plain file name, no / \" & or < -- it is interpolated into the Distribution XML" >&2; exit 2;;
esac
case "$CONCLUSION" in
  */*|*'"'*|*'&'*|*'<'*) echo "productbuild_floor: --conclusion must be a plain file name, no / \" & or < -- it is interpolated into the Distribution XML" >&2; exit 2;;
esac
[ -z "$RES" ] || [ -z "$WELCOME" ] || [ -f "$RES/$WELCOME" ] \
  || { echo "productbuild_floor: --welcome file not found: $RES/$WELCOME" >&2; exit 2; }
[ -z "$RES" ] || [ -z "$LICENSE" ] || [ -f "$RES/$LICENSE" ] \
  || { echo "productbuild_floor: --license file not found: $RES/$LICENSE" >&2; exit 2; }
[ -z "$CONCLUSION" ] || [ -f "$RES/$CONCLUSION" ] \
  || { echo "productbuild_floor: --conclusion file not found: $RES/$CONCLUSION" >&2; exit 2; }
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
  [ -n "$CONCLUSION" ] && echo "    <conclusion file=\"$(basename "$CONCLUSION")\" mime-type=\"text/html\"/>"
  echo "    <allowed-os-versions><os-version min=\"$MIN_OS\"/></allowed-os-versions>"
  echo "    <options $_opts/>"
  echo '    <choices-outline>'
  echo '        <line choice="default">'
  echo '            <line choice="dev.mavergreen.base"/>'
  echo "            <line choice=\"$ID\"/>"
  echo '        </line>'
  echo '    </choices-outline>'
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
concl="$(grep -c '<conclusion file=' "$X/x/Distribution" || true)"
rm -rf "$X"
[ "$got" = "os-version min=\"$MIN_OS\"" ] \
  || { echo "productbuild_floor: FLOOR MISSING/WRONG in $OUT (got: ${got:-none}, want $MIN_OS)" >&2; exit 1; }
[ "$first" = dev.mavergreen.base ] \
  || { echo "productbuild_floor: dev.mavergreen.base is not first in $OUT" >&2; exit 1; }
[ -z "$CONCLUSION" ] || [ "$concl" -ge 1 ] \
  || { echo "productbuild_floor: the conclusion pane did not make it into $OUT" >&2; exit 1; }
echo "productbuild_floor: $OUT built, install floor $MIN_OS enforced"
