#!/bin/sh
# platform: host-agnostic
#   usage: set_install_floor.sh --short S --version V --component COMP.pkg --dist DIR [--system-replace]
#            [--resources DIR] [--welcome FILE] [--license FILE] [--conclusion FILE]
#            [--require-scripts] [--base-version V]
#          FILE for --welcome, --license and --conclusion names a file inside --resources.
#          Wraps a flat component pkg into a distributable product archive and prints its path. The
#          Distribution carries the product's floor (.mavergreen/products/S/floor, default 10.9.5),
#          hostArchitectures="x86_64,arm64", and the class's OS range and installation-check, all
#          derived from the component's Mach-O files by lib/arch-rules.sh; exit 1 for an arm64 slice
#          without a newer-macos deviation. The filename, component name, identifier and Installer title are derived from
#          .mavergreen/products/S/: DIR/S-V.pkg, S.pkg, dev.mavergreen.S and "Mavergreen <name>";
#          with --system-replace, DIR/S-system-replace-V.pkg, S-system-replace.pkg,
#          dev.mavergreen.S.system-replace and "Mavergreen <name> System Replace". COMP's own
#          identifier must be the derived one. Every archive also carries dev.mavergreen.base (built
#          via build-base-component.sh, --base-version picks its version) and lists it FIRST in the
#          choices-outline, so its postinstall -- which installs or upgrades /opt/mavergreen/bin/mavergreen
#          -- runs before the product's postinstall runs the helper.
# spec: tests/set-install-floor-base-test.sh -- the base component must be first in the
#       choices-outline: Installer runs the components' postinstalls in Distribution order, after
#       every payload has landed, so only a base listed first has installed or upgraded the helper
#       by the time the product's postinstall runs it.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavergreen-meta.sh"
. "$SELF/lib/name-rules.sh"
. "$SELF/lib/vercmp.sh"
. "$SELF/lib/arch-rules.sh"
. "$SELF/lib/pkg-tree.sh"
. "$SELF/deviation-reason.sh"
LC_ALL=C; export LC_ALL

SHORT=""; VER=""; COMPONENT=""; DISTDIR=""; RES=""; WELCOME=""; LICENSE=""; CONCLUSION=""
REQSCRIPTS="false"; BASEVER=""; SYSREP=""

refuse() { echo "productbuild_floor: $1 is refused; $2" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --title) refuse --title "write .mavergreen/products/<short>/noun" ;;
    --out) refuse --out "the filename is derived, <short>-<version>.pkg; pass --dist" ;;
    --identifier) refuse --identifier "the identifier is dev.mavergreen.<short>" ;;
    --host-arch) refuse --host-arch "every pkg declares hostArchitectures=\"x86_64,arm64\"" ;;
    --min-os) refuse --min-os "the floor is .mavergreen/products/<short>/floor" ;;
    --short|--version|--component|--dist|--resources|--welcome|--license|--conclusion|--base-version)
      [ $# -ge 2 ] || { echo "productbuild_floor: $1 needs a value" >&2; exit 2; } ;;
  esac
  case "$1" in
    --short) SHORT="$2"; shift 2;;
    --version) VER="$2"; shift 2;;
    --component) COMPONENT="$2"; shift 2;;
    --dist) DISTDIR="${2%/}"; shift 2;;
    --system-replace) SYSREP=1; shift;;
    --resources) RES="$2"; shift 2;;
    --welcome) WELCOME="$2"; shift 2;;
    --license) LICENSE="$2"; shift 2;;
    --conclusion) CONCLUSION="$2"; shift 2;;
    --require-scripts) REQSCRIPTS="true"; shift;;
    --base-version) BASEVER="$2"; shift 2;;
    *) echo "productbuild_floor: unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$SHORT" ] && [ -n "$VER" ] && [ -n "$COMPONENT" ] && [ -n "$DISTDIR" ] \
  || { echo "productbuild_floor: need --short --version --component --dist" >&2; exit 2; }
ID="$(mavergreen_name identifier "$SHORT")" || exit $?
TITLE="$(mavergreen_name installer-title "$SHORT")" || exit $?
PKGNAME="$(mavergreen_name pkg "$SHORT" "$VER")" || exit $?
COMP_BASE="$(mavergreen_name component "$SHORT")" || exit $?
if [ -n "$SYSREP" ]; then
  ID="$ID.system-replace"
  TITLE="$TITLE System Replace"
  PKGNAME="$SHORT-system-replace-${PKGNAME#"$SHORT"-}"
  COMP_BASE="${COMP_BASE%.pkg}-system-replace.pkg"
fi
[ "$ID" != dev.mavergreen.base ] \
  || { echo "productbuild_floor: the product's identifier may not be dev.mavergreen.base -- the base component is added automatically" >&2; exit 2; }
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

[ "$COMP_BASE" != mavergreen-base.pkg ] || { echo "productbuild_floor: the product component may not be named mavergreen-base.pkg" >&2; exit 2; }
BASEDIR=$(mktemp -d "${TMPDIR:-/tmp}/mavergreen-base.XXXXXX")
DIST="$BASEDIR/distribution.xml"
trap 'rm -rf "$BASEDIR"' EXIT
EPOCH="$(sh "$SELF/source-date-epoch.sh")"
STEVEDORE="$(sh "$SELF/fetch_stevedore.sh")"

"$STEVEDORE" expand "$COMPONENT" "$BASEDIR/comp-x" >&2
got_id="$(sed -n 's/.*<pkg-info[^>]*[[:space:]]identifier="\([^"]*\)".*/\1/p' "$BASEDIR/comp-x/PackageInfo" 2>/dev/null | head -1)"
[ "$got_id" = "$ID" ] \
  || { echo "productbuild_floor: $COMPONENT is identified as ${got_id:-nothing}; $SHORT's component must be $ID" >&2; exit 1; }
mkdir -p "$BASEDIR/comp"
cp "$COMPONENT" "$BASEDIR/comp/$COMP_BASE"
COMPONENT="$BASEDIR/comp/$COMP_BASE"

FLOOR="$(mavergreen_floor "$SHORT")" || exit $?
shipyard_deviations "$(dirname "$(mg_dir)")" >/dev/null || exit 1
if shipyard_deviated newer-macos "$SHORT" >/dev/null; then NEWER=yes; else NEWER=no; fi
TREE="$(mavergreen_prefix "$SHORT" | sed 's|^/||')/"
TARGETS="$(mg_dir)/products/$SHORT/target"
SLICES="$BASEDIR/slices"
: > "$SLICES"
if [ -f "$BASEDIR/comp-x/Payload" ]; then
  af_unpack_payload "$BASEDIR/comp-x/Payload" || { echo "productbuild_floor: cannot unpack the payload of $COMPONENT" >&2; exit 1; }
  ( cd "$AF_ROOT" && find . -type f | sed 's|^\./||' | sort ) > "$BASEDIR/files"
  while IFS= read -r _rel; do
    [ -n "$_rel" ] || continue
    _full="$AF_LOC$_rel"
    _kind="$(af_macho_kind "$AF_ROOT/$_rel")"
    [ -n "$_kind" ] || continue
    case "$_full" in "$TREE"*) ! arch_is_target "${_full#"$TREE"}" "$TARGETS" || continue;; esac
    _rc=0; sh "$SELF/macho-slices.sh" "$AF_ROOT/$_rel" > "$BASEDIR/one" 2> "$BASEDIR/one.err" || _rc=$?
    case "$_rc" in
      0) ;;
      1) [ "$_kind" = loose ] && continue
         echo "productbuild_floor: $_full has a Mach-O magic that macho-slices.sh rejects" >&2; cat "$BASEDIR/one.err" >&2; exit 1;;
      *) echo "productbuild_floor: cannot read the Mach-O file $_full" >&2; cat "$BASEDIR/one.err" >&2; exit 1;;
    esac
    _enc="$(printf '%s\n' "$_full" | af_enc)"
    awk -v p="$_enc" '{ print p, $1, $3 }' "$BASEDIR/one" >> "$SLICES"
  done < "$BASEDIR/files"
fi
arch_derive < "$SLICES" > "$BASEDIR/derived" 2> "$BASEDIR/derive.err" \
  || { echo "productbuild_floor: $(cat "$BASEDIR/derive.err")" >&2; exit 1; }
CLASS="$(sed -n 's/^class //p' "$BASEDIR/derived")"
ARM64FLOOR="$(sed -n 's/^arm64-floor //p' "$BASEDIR/derived")"
arch_rule "$CLASS" "$NEWER" "$FLOOR" "$ARM64FLOOR" >/dev/null 2>&1 || {
  _arm="$(awk '$2 ~ /^arm64/ { print $1; exit }' "$SLICES" | sed 's/%20/ /g; s/%25/%/g')"
  echo "productbuild_floor: $SHORT ships an arm64 slice ($_arm), which serves only macOS 11 or later; declare .mavergreen/deviations/newer-macos/<label>/ with scope $SHORT" >&2
  exit 1
}
ARCH_LINES="$(arch_distribution "$CLASS" "$NEWER" "$FLOOR" "$ARM64FLOOR")" || exit 1
RANGE="$(arch_requires_line "$CLASS" "$NEWER" "$FLOOR" "$ARM64FLOOR")"

BASE="$BASEDIR/mavergreen-base.pkg"
if [ -n "$BASEVER" ]; then
  sh "$SELF/build-base-component.sh" --version "$BASEVER" --out "$BASE" >&2
else
  sh "$SELF/build-base-component.sh" --out "$BASE" >&2
fi

_opts="customize=\"never\" require-scripts=\"$REQSCRIPTS\" hostArchitectures=\"x86_64,arm64\""

{
  echo '<?xml version="1.0" encoding="utf-8"?>'
  echo '<installer-gui-script minSpecVersion="1">'
  echo "    <title>$(mg_xml_text "$TITLE")</title>"
  [ -n "$WELCOME" ] && echo "    <welcome file=\"$(basename "$WELCOME")\" mime-type=\"text/html\"/>"
  [ -n "$LICENSE" ] && echo "    <license file=\"$(basename "$LICENSE")\"/>"
  [ -n "$CONCLUSION" ] && echo "    <conclusion file=\"$(basename "$CONCLUSION")\" mime-type=\"text/html\"/>"
  printf '%s\n' "$ARCH_LINES" | awk -v opts="<options $_opts/>" '
    NR == 2 { print opts }
    /^<script><!\[CDATA\[$/ { print "<script>"; s = 1; next }
    /^\]\]><\/script>$/ { print "</script>"; s = 0; next }
    s { gsub(/&/, "\\&amp;"); gsub(/</, "\\&lt;"); gsub(/>/, "\\&gt;") }
    { print }
    END { if (NR < 2) print opts }' | sed 's/^/    /'
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

set -- product --distribution "$DIST" --package "$BASE" --package "$COMPONENT" --mtime "$EPOCH"
[ -z "$RES" ] || set -- "$@" --resources "$RES"
mkdir -p "$DISTDIR"
OUT="$DISTDIR/$PKGNAME"
"$STEVEDORE" "$@" --out "$OUT" >&2

X=$(mktemp -d "${TMPDIR:-/tmp}/pkgfloor.XXXXXX")
"$STEVEDORE" expand "$OUT" "$X/x" >&2
got="$(sed 's/^[[:space:]]*//' "$X/x/Distribution" | awk '
  /^<os-version / { print; next }
  /^<installation-check / { print; next }
  /^<script>$/ { print "<script><![CDATA["; s = 1; next }
  /^<\/script>$/ { print "]]></script>"; s = 0; next }
  s { gsub(/&lt;/, "<"); gsub(/&gt;/, ">"); gsub(/&amp;/, "\\&") }
  s { print }')"
opts="$(grep -c "<options [^>]*hostArchitectures=\"x86_64,arm64\"" "$X/x/Distribution" || true)"
order="$(sed 's/^[[:space:]]*//' "$X/x/Distribution" | awk '/^<(allowed-os-versions|options|installation-check|script)[ >\/]/ { t = $1; sub(/^</, "", t); sub(/[>\/].*/, "", t); printf "%s ", t }')"
first="$(sed -n 's/.*<line choice="\([^"]*\)".*/\1/p' "$X/x/Distribution" | grep -v '^default$' | head -1)"
concl="$(grep -c '<conclusion file=' "$X/x/Distribution" || true)"
rm -rf "$X"
want="$(printf '%s\n' "$ARCH_LINES" | sed -e 's/^<allowed-os-versions>//' -e 's|</allowed-os-versions>$||')"
[ "$got" = "$want" ] \
  || { echo "productbuild_floor: the OS range or installation-check in $OUT is not the class's (got: $got; want: $want)" >&2; exit 1; }
[ "$opts" -ge 1 ] \
  || { echo "productbuild_floor: hostArchitectures=\"x86_64,arm64\" is missing from $OUT" >&2; exit 1; }
case "$ARCH_LINES" in
  *installation-check*) want_order="allowed-os-versions options installation-check script ";;
  *) want_order="allowed-os-versions options ";;
esac
[ "$order" = "$want_order" ] \
  || { echo "productbuild_floor: $OUT orders its elements as \"$order\", not \"$want_order\"" >&2; exit 1; }
[ "$first" = dev.mavergreen.base ] \
  || { echo "productbuild_floor: dev.mavergreen.base is not first in $OUT" >&2; exit 1; }
[ -z "$CONCLUSION" ] || [ "$concl" -ge 1 ] \
  || { echo "productbuild_floor: the conclusion pane did not make it into $OUT" >&2; exit 1; }
echo "productbuild_floor: $OUT built: $CLASS, $RANGE" >&2
printf '%s\n' "$OUT"
