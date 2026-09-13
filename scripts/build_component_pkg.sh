#!/bin/sh
#   usage: build_component_pkg.sh --root DIR --identifier ID --version V --install-location LOC
#                                  --out PKG [--scripts DIR]
#          Prints the output .pkg path on stdout (everything else goes to stderr), matching
#          set_install_floor.sh.
# platform: builds a flat component .pkg whose bundles install EXACTLY where declared and ALWAYS
#           overwrite, by turning OFF PackageKit's two "defer to whatever is already on disk"
#           defaults on every bundle:
#             BundleIsRelocatable=false    -- otherwise Installer, finding a bundle with the same
#               CFBundleIdentifier already on disk at a DIFFERENT path, RELOCATES the payload onto
#               that old path and ignores the declared install-location. (mavericks-container-tools:
#               a renamed menu-bar .app kept reinstalling under its OLD name, so the rename never
#               landed and a cleanup step then deleted the relocated copy. /var/log/install.log:
#               "<new>.app relocated to <old>.app".)
#             BundleIsVersionChecked=false -- otherwise Installer compares the on-disk
#               CFBundleVersion and SKIPS the component when the installed one is >= the pkg's, so an
#               update silently no-ops. (mavericks-magic-trackpad2: a legacy kext hardcoded 1.0.0 and
#               never updated. Proven 2026-07-09.)
#           Both are one bug family: an internally-consistent .pkg that behaves wrong on a machine
#           that already has a previous version -- invisible to any check that reads the artifact in
#           isolation. Pair with assert_pkg_installs_in_place.sh, which gates the BUILT .pkg so a
#           regression (a product that bypasses this, or a future pkgbuild default) fails CI instead
#           of shipping.
set -eu

ROOT=""; IDENT=""; VER=""; LOC=""; OUT=""; SCRIPTS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2;;
    --identifier) IDENT="$2"; shift 2;;
    --version) VER="$2"; shift 2;;
    --install-location) LOC="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --scripts) SCRIPTS="$2"; shift 2;;
    *) echo "build_component_pkg: unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$ROOT" ] && [ -n "$IDENT" ] && [ -n "$VER" ] && [ -n "$LOC" ] && [ -n "$OUT" ] \
  || { echo "build_component_pkg: need --root --identifier --version --install-location --out" >&2; exit 2; }
[ -d "$ROOT" ] || { echo "build_component_pkg: no payload root: $ROOT" >&2; exit 1; }

# platform: --analyze emits a component plist: an array with one dict per BUNDLE in the payload
#           (plain files are not components and never appear). Flip both flags off on every entry,
#           Add-ing the key when --analyze omitted it. PlistBuddy (not python) so this runs on the
#           10.9 dev box AND macOS-26 CI.
plist="$(dirname "$OUT")/$(basename "$OUT" .pkg)-components.plist"
pkgbuild --analyze --root "$ROOT" "$plist" >&2
i=0
while /usr/libexec/PlistBuddy -c "Print :$i" "$plist" >/dev/null 2>&1; do
  for key in BundleIsRelocatable BundleIsVersionChecked; do
    /usr/libexec/PlistBuddy -c "Set :$i:$key false" "$plist" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :$i:$key bool false" "$plist"
  done
  i=$((i + 1))
done
echo "build_component_pkg: forced install-in-place on $i bundle component(s)" >&2

set -- --root "$ROOT" --component-plist "$plist" \
       --identifier "$IDENT" --version "$VER" --install-location "$LOC"
[ -n "$SCRIPTS" ] && set -- "$@" --scripts "$SCRIPTS"
pkgbuild "$@" "$OUT" >&2

echo "$OUT"
