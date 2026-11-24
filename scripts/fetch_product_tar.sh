#!/bin/sh
# platform: host-agnostic
#   usage: fetch_product_tar.sh SHORT VERSION DEST
#          The linux-x86_64 archive of a pinned Mavergreen release, unpacked to DEST and verified against that
#          release's own SHA256SUMS, fetched afresh on every call; an archive SHA256SUMS does not list fails.
#          A tree verified once carries a stamp of the pin's sha256 and the tree's identity (names, modes, sizes, mtimes); while both match, a call
#          trusts it without re-hashing the archive or the tree.
# spec: README.md "Linux product archives" -- pinned user-owned toolchain caches
set -eu
[ $# -eq 3 ] || { echo 'usage: fetch_product_tar.sh SHORT VERSION DEST' >&2; exit 2; }
SELF="$(cd "$(dirname "$0")" && pwd)"
SHORT=$1; VERSION=$2; DEST=$3
for value in "$SHORT" "$VERSION"; do
  case "$value" in ''|.|..|*[!a-zA-Z0-9._-]*) echo "fetch_product_tar: invalid name/version '$value'" >&2; exit 2 ;; esac
done
while [ "${DEST%/}" != "$DEST" ]; do DEST=${DEST%/}; done
case "$DEST" in ''|.|..|/) echo 'fetch_product_tar: unsafe destination' >&2; exit 2 ;; esac
REPO="$(sh "$SELF/product-name.sh" repo "$SHORT")"
CACHE="${MAVERGREEN_TAR_CACHE:-$HOME/.cache/mavergreen-tars}/$REPO/$VERSION"
ASSET="$SHORT-$VERSION-linux-x86_64.tar.gz"
BASE="${MAVERGREEN_RELEASES:-https://github.com}/Mavergreen/$REPO/releases/download/$VERSION"
. "$SELF/mavericks_fetch.sh"
SHA="$(shipyard_release_sha "$BASE" "$ASSET")" || { echo "fetch_product_tar: no verified digest for $ASSET" >&2; exit 1; }
mkdir -p "$(dirname "$DEST")"
DEST="$(cd "$(dirname "$DEST")" && pwd -P)/$(basename "$DEST")"
case "$(basename "$DEST")" in .|..) echo 'fetch_product_tar: unsafe destination' >&2; exit 2 ;; esac
if python3 "$SELF/product-tar.py" --trusted "$SHA" "$DEST"; then printf '%s\n' "$DEST"; exit 0; fi
shipyard_fetch_verified "$BASE/$ASSET" "$SHA" "$CACHE" "$ASSET"
shipyard_lock_take "$DEST.lock" "${SHIPYARD_LOCK_WAIT:-900}" || { echo "fetch_product_tar: lock timeout: $DEST.lock" >&2; exit 1; }
trap 'shipyard_lock_release "$DEST.lock"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
python3 "$SELF/product-tar.py" "$CACHE/$ASSET" "$SHORT" "$SHA" "$DEST"
printf '%s\n' "$DEST"
