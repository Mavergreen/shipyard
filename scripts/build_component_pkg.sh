#!/bin/sh
# platform: host-agnostic
#   usage: build_component_pkg.sh --root DIR --identifier ID --version V --install-location LOC
#                                  --out PKG [--scripts DIR]
#          Prints the output .pkg path on stdout (everything else goes to stderr), matching
#          set_install_floor.sh. Files are stamped with $SOURCE_DATE_EPOCH, or when unset the commit
#          time of $MAVERICKS_ROOT when that is a git work tree, else of the repo at the caller's current
#          directory; a caller without git must export SOURCE_DATE_EPOCH. A group- or world-writable
#          entry under the root (a symlink aside) is refused, naming it, and the root itself is made
#          0755, so the installer never gives the install location the mode a umask-002 stage
#          left. Exit 1 on a writable entry or a missing root, 2 on a usage error.
# platform: builds a flat component .pkg with stevedore, whose bundles install EXACTLY where
#           declared and ALWAYS overwrite. stevedore writes every component install-in-place, so
#           PackageKit's two "defer to whatever is already on disk" defaults are OFF on every bundle:
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
#           regression (a product that bypasses this, or a packager change) fails CI instead
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

wr="$(cd "$ROOT" && find . ! -name . ! -type l \( -perm -020 -o -perm -002 \) | LC_ALL=C sort | head -1)"
[ -z "$wr" ] || { echo "build_component_pkg: ${wr#./} in $ROOT is group- or world-writable; stage the payload under umask 022" >&2; exit 1; }
chmod 0755 "$ROOT"

SELF="$(cd "$(dirname "$0")" && pwd)"
EPOCH="$(sh "$SELF/source-date-epoch.sh")"
STEVEDORE="$(sh "$SELF/fetch_stevedore.sh")"

n="$(find "$ROOT" -type d \( -name '*.app' -o -name '*.bundle' \) \
       \( -exec test -f '{}/Contents/Info.plist' \; -o -exec test -f '{}/Info.plist' \; \) -print | wc -l)"
n=$((n + 0))
echo "build_component_pkg: forced install-in-place on $n bundle component(s)" >&2

set -- component --root "$ROOT" --identifier "$IDENT" --version "$VER" --install-location "$LOC" \
       --mtime "$EPOCH"
[ -n "$SCRIPTS" ] && set -- "$@" --scripts "$SCRIPTS"
"$STEVEDORE" "$@" --out "$OUT" >&2

echo "$OUT"
