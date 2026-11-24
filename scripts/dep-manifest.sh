#!/bin/sh
# platform: host-agnostic
#   usage: dep-manifest.sh DEP
#          Prints the RELEASE-MANIFEST.txt of the release ingredient DEP pins (.mavergreen/ingredients/DEP/
#          REPO and VERSION, or those of the ingredient its `from` names), fetched with fetch-release-pkg.sh,
#          verified against that release's SHA256SUMS, and cached under
#          ${XDG_CACHE_HOME:-$HOME/.cache}/mavergreen/release-manifests/<repo>/<tag>.
#          Exit 0; 3 when the release publishes no manifest and its pin is not -mavergreen.N (a -mavericks.N
#          or an own-upstream release from before the flag day predates them); 1 on any other failure, a
#          -mavergreen.N release without one included; 2 on a usage error.
# spec: tests/dep-manifest-test.sh
set -eu
LC_ALL=C; export LC_ALL
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavergreen-meta.sh"
[ $# -eq 1 ] && [ -n "$1" ] || { echo "usage: dep-manifest.sh DEP" >&2; exit 2; }
dep="$1"
die() { echo "dep-manifest: $1" >&2; exit "${2:-1}"; }
src="$dep"
if from="$(mg_value "ingredients/$dep/from")"; then src="$from"; fi
slug="$(mg_value "ingredients/$src/REPO")" || die "ingredients/$src/REPO is missing from $(mg_dir)"
tag="$(mg_value "ingredients/$src/VERSION")" || die "ingredients/$src/VERSION is missing from $(mg_dir)"
repo="${slug#*/}"
case "$repo$tag" in *[!a-zA-Z0-9._-]*|'') die "ingredients/$src pins '$slug' '$tag', not a release" ;; esac
cache="${XDG_CACHE_HOME:-$HOME/.cache}/mavergreen/release-manifests/$repo"
if [ -s "$cache/$tag" ]; then cat "$cache/$tag"; exit 0; fi
mkdir -p "$cache"
t="$(mktemp -d "$cache/.fetch.XXXXXX")"; trap 'rm -rf "$t"' EXIT
if ! sh "$SELF/fetch-release-pkg.sh" "$repo" "$tag" RELEASE-MANIFEST.txt "$t" > /dev/null 2> "$t/err"; then
  mg=0; case "$tag" in *-mavergreen.[0-9]*) case "${tag##*-mavergreen.}" in *[!0-9]*) ;; *) mg=1 ;; esac ;; esac
  if [ "$mg" -eq 0 ] && grep -qE 'RELEASE-MANIFEST.txt is not listed|has no RELEASE-MANIFEST.txt' "$t/err"; then
    die "$slug $tag has no RELEASE-MANIFEST.txt: a release before the flag day predates them" 3
  fi
  die "cannot read the release manifest of $slug $tag: $(tail -n 1 "$t/err")"
fi
mv "$t/RELEASE-MANIFEST.txt" "$cache/$tag"
cat "$cache/$tag"
