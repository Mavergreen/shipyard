#!/bin/sh
# platform: host-agnostic
#   usage: fetch_product_tar.sh SHORT VERSION SHA256 DEST
# spec: README.md "Linux product archives" -- pinned user-owned toolchain caches
set -eu
[ $# -eq 4 ] || { echo 'usage: fetch_product_tar.sh SHORT VERSION SHA256 DEST' >&2; exit 2; }
SELF="$(cd "$(dirname "$0")" && pwd)"
SHORT=$1; VERSION=$2; SHA=$3; DEST=$4
for value in "$SHORT" "$VERSION"; do
  case "$value" in ''|.|..|*[!a-zA-Z0-9._-]*) echo "fetch_product_tar: invalid name/version '$value'" >&2; exit 2 ;; esac
done
case "$SHA" in ''|*[!0-9a-f]*) echo 'fetch_product_tar: invalid SHA-256' >&2; exit 2 ;; esac
[ "${#SHA}" -eq 64 ] || exit 2
while [ "${DEST%/}" != "$DEST" ]; do DEST=${DEST%/}; done
case "$DEST" in ''|.|..|/) echo 'fetch_product_tar: unsafe destination' >&2; exit 2 ;; esac
REPO="$(sh "$SELF/product-name.sh" repo "$SHORT")"
CACHE="${MAVERGREEN_TAR_CACHE:-$HOME/.cache/mavergreen-tars}/$REPO/$VERSION"
ASSET="$SHORT-$VERSION-linux-x86_64.tar.gz"
BASE="${MAVERGREEN_RELEASES:-https://github.com}/Mavergreen/$REPO/releases/download/$VERSION"
. "$SELF/mavericks_fetch.sh"
shipyard_fetch_verified "$BASE/$ASSET" "$SHA" "$CACHE" "$ASSET"
mkdir -p "$(dirname "$DEST")"
DEST="$(cd "$(dirname "$DEST")" && pwd -P)/$(basename "$DEST")"
case "$(basename "$DEST")" in .|..) echo 'fetch_product_tar: unsafe destination' >&2; exit 2 ;; esac
waited=0
until mkdir "$DEST.lock" 2>/dev/null; do
  [ "$waited" -lt "${SHIPYARD_LOCK_WAIT:-900}" ] || { echo "fetch_product_tar: lock timeout: $DEST.lock" >&2; exit 1; }
  sleep 1; waited=$((waited + 1))
done
trap 'rmdir "$DEST.lock" 2>/dev/null || :' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
python3 "$SELF/product-tar.py" "$CACHE/$ASSET" "$SHORT" "$SHA" "$DEST"
printf '%s\n' "$DEST"
