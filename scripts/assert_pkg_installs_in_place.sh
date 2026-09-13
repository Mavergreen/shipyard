#!/bin/sh
#   usage: assert_pkg_installs_in_place.sh PKG [PKG...]
#          Gates a BUILT .pkg against the two install-time footguns build_component_pkg.sh disables,
#          by reading what the .pkg ACTUALLY declares in its PackageInfo -- so a regression (a
#          product that bypassed the helper, or a future pkgbuild default change) fails CI instead of
#          shipping and being discovered live on a user's machine, weeks later, one product at a
#          time. Every check in the family so far has verified that artifacts AGREE with each other;
#          none exercised what the installer DOES on a machine that already has the previous version.
#          This gate closes that gap for relocation + version-skip.
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
[ "$#" -ge 1 ] || { echo "assert_pkg_installs_in_place: need at least one .pkg" >&2; exit 2; }

# platform: counts <bundle ...> children of a named element in a PackageInfo. Splitting on '<' turns
#           the XML -- whether pretty-printed or one line -- into one token per tag, so the element's
#           open/close and its <bundle> children are inspectable without an XML parser. The [ >]
#           guards matter: they keep <bundle-version> (the element scanned for) from being mistaken
#           for a <bundle> child, and keep a <bundle> child from matching the sibling
#           <bundle-version> token ("bundle-version", not "bundle ").
count_bundles() {  # $1=PackageInfo  $2=element
  tr '<' '\n' < "$1" | awk -v e="$2" '
    $0 ~ "^" e "[ >]"      { inside = 1; next }   # <e> or <e ...>  (NOT self-closing <e/>)
    $0 ~ "^/" e "[ >]?$"   { inside = 0 }         # </e>
    inside && $0 ~ "^bundle[ >]" { c++ }          # <bundle ...> child
    END { print c + 0 }'
}

status=0
for pkg in "$@"; do
  [ -f "$pkg" ] || { echo "assert_pkg_installs_in_place: no such pkg: $pkg" >&2; status=1; continue; }
  x="$(mktemp -d "${TMPDIR:-/tmp}/pkg-inplace.XXXXXX")"   # template: 10.9 BSD mktemp requires one
  if ! pkgutil --expand "$pkg" "$x/e" >/dev/null 2>&1; then
    echo "assert_pkg_installs_in_place: cannot expand $pkg" >&2; status=1; rm -rf "$x"; continue
  fi
  found=0
  # platform: a product archive nests one or more component.pkg dirs; a bare component pkg has
  #           PackageInfo at the top. find covers both.
  for pi in $(find "$x/e" -name PackageInfo); do
    found=1
    r="$(count_bundles "$pi" relocate)"
    if [ "$r" -gt 0 ]; then
      echo "assert_pkg_installs_in_place: $pkg: $r bundle(s) under <relocate> -- BundleIsRelocatable is ON; build via build_component_pkg.sh" >&2
      status=1
    fi
    u="$(count_bundles "$pi" bundle-version)"
    if [ "$u" -gt 0 ]; then
      echo "assert_pkg_installs_in_place: $pkg: $u bundle(s) under <bundle-version> -- BundleIsVersionChecked is ON; build via build_component_pkg.sh" >&2
      status=1
    fi
  done
  [ "$found" -eq 1 ] || { echo "assert_pkg_installs_in_place: $pkg: no PackageInfo found" >&2; status=1; }
  rm -rf "$x"
done

[ "$status" -eq 0 ] && echo "assert_pkg_installs_in_place: ok — every bundle installs in place"
exit "$status"
