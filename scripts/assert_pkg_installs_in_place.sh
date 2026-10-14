#!/bin/sh
# platform: host-agnostic
#   usage: assert_pkg_installs_in_place.sh PKG [PKG...]
#          assert_pkg_installs_in_place.sh        (under shipyard-check --dist: every .pkg in the dist)
#          Gates a BUILT .pkg against the two install-time footguns build_component_pkg.sh disables,
#          by reading what the .pkg ACTUALLY declares in its PackageInfo -- so a regression (a
#          product that bypassed the helper, or a future pkgbuild default change) fails CI instead of
#          shipping and being discovered live on a user's machine, weeks later, one product at a
#          time. Every check in the family so far has verified that artifacts AGREE with each other;
#          none exercised what the installer DOES on a machine that already has the previous version.
#          This gate closes that gap for relocation + version-skip. PackageInfo is a plain XML file
#          in the pkg, read with bsdtar on every host (lib/pkg-read.sh), so the gate needs neither
#          pkgutil nor a Mac.
# platform: for every component PackageInfo inside the .pkg, asserts (both verified empirically
#           against real pkgbuild output, 2026-07-31 -- pkgbuild encodes these differently than one
#           might guess):
#             <relocate> lists NO bundles       => BundleIsRelocatable=false  (installs at the
#                                                   declared path). The pkg-info root's
#                                                   relocatable="false" ATTRIBUTE is a red herring --
#                                                   pkgbuild emits it even for a relocatable
#                                                   component; the <relocate> ELEMENT's membership is
#                                                   the operative signal.
#             <bundle-version> lists NO bundles => BundleIsVersionChecked=false (always overwrites;
#                                                   pkgbuild files a version-checked bundle under
#                                                   <bundle-version>, NOT under <upgrade-bundle>,
#                                                   which lists every upgradable bundle regardless of
#                                                   the flag).
#           A relocatable / version-checked bundle appears as <bundle id="..."/> under those elements.
#           A clean pkg leaves them empty (<relocate/> / <bundle-version/>) or absent.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/check-lib.sh"
. "$SELF/lib/pkg-read.sh"
if [ "$#" -eq 0 ] && [ -n "${SHIPYARD_CHECK_DIST:-}" ]; then
  for _p in "$SHIPYARD_CHECK_DIST"/*.pkg; do
    [ -f "$_p" ] || continue
    set -- "$@" "$_p"
  done
  [ "$#" -gt 0 ] || { chk_notrun pkg-in-place "no .pkg in $SHIPYARD_CHECK_DIST"; exit 0; }
fi
chk_ran pkg-in-place
[ "$#" -ge 1 ] || { echo "assert_pkg_installs_in_place: need at least one .pkg" >&2; exit 2; }

rule="a pkg's bundles install where it says and always overwrite"
fix="build the component via build_component_pkg.sh, which turns BundleIsRelocatable and BundleIsVersionChecked off"

# platform: a PackageInfo's XML may be pretty-printed or written as one line, and its
#           <bundle-version> element name shares the "bundle" prefix with the <bundle> children
#           counted here.
count_bundles() {  # $1=PackageInfo  $2=element
  tr '<' '\n' < "$1" | awk -v e="$2" '
    $0 ~ "^" e "[ >]"      { inside = 1; next }   # <e> or <e ...>  (NOT self-closing <e/>)
    $0 ~ "^/" e "[ >]?$"   { inside = 0 }         # </e>
    inside && $0 ~ "^bundle[ >]" { c++ }          # <bundle ...> child
    END { print c + 0 }'
}

for pkg in "$@"; do
  [ -f "$pkg" ] || { chk_fail pkg-in-place "$rule" "$pkg does not exist" "pass the built .pkg's path"; continue; }
  x="$(mktemp -d "${TMPDIR:-/tmp}/pkg-inplace.XXXXXX")"   # template: 10.9 BSD mktemp requires one
  rc=0; af_extract "$pkg" "$x" || rc=$?
  if [ "$rc" -ne 0 ]; then
    chk_fail pkg-in-place "$rule" "$pkg cannot be read, so its bundles cannot be checked$([ "$rc" -ne 2 ] || echo ' (no bsdtar found)')" \
      "install libarchive-tools or set BSDTAR to bsdtar's path, and make sure the pkg is a readable xar"
    af_rm "$x"; continue
  fi
  found=0
  # platform: a product archive nests one or more component.pkg dirs; a bare component pkg has
  #           PackageInfo at the top. find covers both.
  for pi in $(find "$x" -name PackageInfo | sed 's/ /%20/g'); do
    pi="$(printf '%s' "$pi" | sed 's/%20/ /g')"
    found=1
    r="$(count_bundles "$pi" relocate)"
    if [ "$r" -gt 0 ]; then
      chk_fail pkg-in-place "$rule" "$pkg: $r bundle(s) under <relocate> -- BundleIsRelocatable is ON" "$fix"
    fi
    u="$(count_bundles "$pi" bundle-version)"
    if [ "$u" -gt 0 ]; then
      chk_fail pkg-in-place "$rule" "$pkg: $u bundle(s) under <bundle-version> -- BundleIsVersionChecked is ON" "$fix"
    fi
  done
  [ "$found" -eq 1 ] || chk_fail pkg-in-place "$rule" "$pkg: no PackageInfo found" "build the pkg with pkgbuild, which writes one"
  af_rm "$x"
done

[ "$chk_status" -ne 0 ] || echo "assert_pkg_installs_in_place: ok — every bundle installs in place"
exit "$chk_status"
