#!/bin/sh
# platform: host-agnostic
#   usage: shipyard-provision-on-target-test.sh
#          Provisions the real pinned cmake release with shipyard-provision, into a scratch directory
#          with nothing installed, and asserts the cmake=<path> it prints holds the product. Needs
#          network. It is the 10.9 guest's proof.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
_tmp="${TMPDIR:-/tmp}"
w="$(cd -P "$(mktemp -d "${_tmp%/}/shipyard-provision-on-target.XXXXXX")" && pwd)"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
out="$(CI= MAVERGREEN_ROOT="$root" MAVERGREEN_PREFIX="$w/no-prefix" MAVERGREEN_PKG_CACHE="$w/cache" \
  sh "$root/scripts/shipyard-provision" --only cmake --into "$w/into" 2>"$w/err")" \
  || { cat "$w/err"; fail "shipyard-provision --only cmake failed"; }
case "$out" in
  cmake=/*) ;;
  *) fail "want one cmake=<path> line, got: $out" ;;
esac
path="${out#cmake=}"
[ "$path" = "$w/into/cmake-$(sed -n 1p "$root/.mavergreen/ingredients/cmake/VERSION")" ] || fail "cmake was provisioned to $path, not under --into"
[ -d "$path/bin" ] && [ -f "$path/mavergreen.plist" ] || fail "$path holds no cmake product (bin/, mavergreen.plist)"
echo "PASS: shipyard-provision provisioned the pinned cmake at $path"
