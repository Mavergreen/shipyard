#!/bin/sh
# platform: host-agnostic
#   usage: fetch-release-pkg.sh REPO TAG ASSET DIR
#          Downloads Mavergreen/REPO's release TAG asset ASSET into DIR, verified against that release's
#          SHA256SUMS (fetched afresh), every download through shipyard_curl's retries. Prints the path of
#          the verified file. Exit 1 on a failed fetch or an ASSET SHA256SUMS does not list exactly once,
#          2 on a usage error. MAVERGREEN_RELEASES replaces https://github.com (the tests serve file://).
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
[ $# -eq 4 ] || { echo "usage: fetch-release-pkg.sh REPO TAG ASSET DIR" >&2; exit 2; }
REPO=$1; TAG=$2; ASSET=$3; DIR=$4
for v in "$REPO" "$TAG" "$ASSET"; do
  case "$v" in ''|*/*|.|..) echo "fetch-release-pkg: '$v' is not a repo, tag or asset name" >&2; exit 2 ;; esac
done
BASE="${MAVERGREEN_RELEASES:-https://github.com}/Mavergreen/$REPO/releases/download/$TAG"
. "$SELF/mavericks_fetch.sh"
mkdir -p "$DIR"
sums="$(mktemp "${TMPDIR:-/tmp}/fetch-release-pkg.XXXXXX")"
trap 'rm -f "$sums"' EXIT
shipyard_curl "$BASE/SHA256SUMS" "$sums" || { echo "fetch-release-pkg: could not fetch $BASE/SHA256SUMS" >&2; exit 1; }
sha="$(awk -v f="$ASSET" '$2 == f || $2 == "*" f { print $1 }' "$sums")"
case "$sha" in
  *[!0-9a-f]*|'') echo "fetch-release-pkg: $ASSET is not listed (once) in $BASE/SHA256SUMS" >&2; exit 1 ;;
esac
[ "${#sha}" -eq 64 ] || { echo "fetch-release-pkg: $ASSET is not listed (once) in $BASE/SHA256SUMS" >&2; exit 1; }
shipyard_fetch_verified "$BASE/$ASSET" "$sha" "$DIR" "$ASSET" || {
  echo "fetch-release-pkg: could not fetch and verify $BASE/$ASSET" >&2; exit 1; }
printf '%s\n' "$DIR/$ASSET"
