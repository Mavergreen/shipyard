#!/bin/sh
# platform: host-agnostic
#   usage: fetch_product_pkg.sh [--asset NAME] SHORT VERSION DEST
#          One component of a pinned Mavergreen release's .pkg, for a build that consumes another family
#          product (librecaulk.a out of Recaulk's pkg, say). SHORT is a short name in the registry
#          (scripts/product-names, or $MAVERGREEN_PRODUCT_NAMES), which supplies the repo and the
#          component's pkg identifier, so a caller cannot disagree with the registry. VERSION is the
#          release tag. NAME is the release asset, default SHORT-VERSION.pkg; pass it where a product's
#          pkg is named otherwise. The pkg is fetched once into
#          ${MAVERGREEN_PKG_CACHE:-$HOME/Library/Caches/mavergreen-pkgs}/REPO/VERSION and verified by
#          mavericks_fetch.sh's shipyard_fetch_verified against the release's SHA256SUMS, which is fetched
#          afresh on every call; an asset SHA256SUMS does not list fails. The component is picked by its
#          PackageInfo identifier, never by position (a product archive lists dev.mavergreen.base first).
#          DEST is REPLACED by its usr/local/mavergreen/SHORT tree, extracted beside DEST and swapped in,
#          unless DEST.stamp says DEST already holds this very pkg's tree: then DEST is kept, since a
#          parallel build may be running a compiler out of it. Calls for one DEST take turns through the
#          lock directory DEST.lock, waiting up to SHIPYARD_LOCK_WAIT seconds (default 900) for it.
#          Prints DEST on stdout; progress goes to stderr. Exit 1 on a failed fetch, checksum or
#          extraction, 2 on a usage error or a registry that cannot answer. MAVERGREEN_RELEASES replaces
#          https://github.com (the tests serve a file:// tree).
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
usage() { echo "usage: fetch_product_pkg.sh [--asset NAME] SHORT VERSION DEST" >&2; exit 2; }
ASSET=""
if [ "${1:-}" = --asset ]; then [ $# -ge 2 ] || usage; ASSET=$2; shift 2; fi
[ $# -eq 3 ] || usage
SHORT=$1; VERSION=$2; DEST=$3
while [ "${DEST%/}" != "$DEST" ]; do DEST="${DEST%/}"; done
case "$DEST" in ''|.|..) echo "fetch_product_pkg: refusing DEST '$DEST'" >&2; exit 2 ;; esac
case "$VERSION" in ''|*/*|.|..) echo "fetch_product_pkg: '$VERSION' is not a release tag" >&2; exit 2 ;; esac
lookup() {
  _v="$(sh "$SELF/product-name.sh" "$1" "$SHORT")" && return 0
  _rc=$?
  echo "fetch_product_pkg: the registry has no $1 for '$SHORT'" >&2; exit "$_rc"
}
lookup repo; REPO=$_v
lookup identifier; ID=$_v
[ -n "$ASSET" ] || ASSET="$SHORT-$VERSION.pkg"
BASE="${MAVERGREEN_RELEASES:-https://github.com}/Mavergreen/$REPO/releases/download/$VERSION"
CACHE="${MAVERGREEN_PKG_CACHE:-$HOME/Library/Caches/mavergreen-pkgs}/$REPO/$VERSION"
. "$SELF/mavericks_fetch.sh"

mkdir -p "$CACHE" "$(dirname "$DEST")"
DEST="$(cd "$(dirname "$DEST")" && pwd -P)/$(basename "$DEST")"
tmp=""; old=""; locked=""
cleanup() {
  if [ -n "$old" ] && [ -e "$old/dest" ] && [ ! -e "$DEST" ]; then mv "$old/dest" "$DEST"; fi
  rm -rf ${tmp:+"$tmp"} ${old:+"$old"}
  [ -z "$locked" ] || rmdir "$DEST.lock" 2>/dev/null || :
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
tmp="$(mktemp -d "$DEST.tmp.XXXXXX")"
shipyard_curl "$BASE/SHA256SUMS" "$tmp/SHA256SUMS" || {
  echo "fetch_product_pkg: could not fetch $BASE/SHA256SUMS" >&2; exit 1; }
SHA="$(awk -v f="$ASSET" '$2 == f || $2 == "*" f { print $1 }' "$tmp/SHA256SUMS")"
case "$SHA" in
  *[!0-9a-f]*|'') echo "fetch_product_pkg: $ASSET is not listed (once) in $BASE/SHA256SUMS" >&2; exit 1 ;;
esac
[ "${#SHA}" -eq 64 ] || { echo "fetch_product_pkg: $ASSET is not listed (once) in $BASE/SHA256SUMS" >&2; exit 1; }
waited=0
until mkdir "$DEST.lock" 2>/dev/null; do
  [ "$waited" -lt "${SHIPYARD_LOCK_WAIT:-900}" ] || {
    echo "fetch_product_pkg: $DEST.lock is still held after ${waited}s; remove it if no fetch of $DEST is running" >&2; exit 1; }
  sleep 1; waited=$((waited + 1))
done
locked=1
stamp="$ID $VERSION $SHA"
if [ -d "$DEST" ] && [ "$(cat "$DEST.stamp" 2>/dev/null || :)" = "$stamp" ]; then
  echo "$ID $VERSION already extracted: $DEST" >&2
  printf '%s\n' "$DEST"; exit 0
fi
rm -f "$DEST.stamp"
shipyard_fetch_verified "$BASE/$ASSET" "$SHA" "$CACHE" "$ASSET" || {
  echo "fetch_product_pkg: could not fetch and verify $BASE/$ASSET" >&2; exit 1; }

[ -n "${STEVEDORE:-}" ] || STEVEDORE="$(sh "$SELF/fetch_stevedore.sh")" || { echo "fetch_product_pkg: no stevedore to expand the pkg with" >&2; exit 1; }
"$STEVEDORE" expand "$CACHE/$ASSET" "$tmp/expanded" >&2 || {
  echo "fetch_product_pkg: could not expand $CACHE/$ASSET" >&2; exit 1; }
matches="$(grep -l "identifier=\"$ID\"" "$tmp"/expanded/*/PackageInfo 2>/dev/null || true)"
n="$(printf '%s\n' "$matches" | grep -c . || true)"
[ "$n" = 1 ] || {
  echo "fetch_product_pkg: expected one component $ID in $ASSET, found $n" >&2; exit 1; }
comp="$(dirname "$matches")"
mkdir "$tmp/payload"
( cd "$tmp/payload" && gzip -dc "$comp/Payload" | cpio -id --quiet 2>/dev/null ) || {
  echo "fetch_product_pkg: could not unpack the Payload of $ID" >&2; exit 1; }
tree="$tmp/payload/usr/local/mavergreen/$SHORT"
[ -d "$tree" ] || { echo "fetch_product_pkg: $ID installs no usr/local/mavergreen/$SHORT" >&2; exit 1; }
if [ -e "$DEST" ] || [ -L "$DEST" ]; then old="$(mktemp -d "$DEST.old.XXXXXX")"; mv "$DEST" "$old/dest"; fi
mv "$tree" "$DEST" || { echo "fetch_product_pkg: could not move the tree to $DEST" >&2; exit 1; }
printf '%s\n' "$stamp" > "$DEST.stamp"
echo "$ID $VERSION extracted: $DEST" >&2
printf '%s\n' "$DEST"
