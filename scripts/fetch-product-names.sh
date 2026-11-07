#!/bin/sh
# platform: host-agnostic
#   usage: fetch-product-names.sh REPO SHA SHORT DEST
#          Fetches .mavergreen/products/SHORT/noun and line of REPO at SHA into
#          DEST/.mavergreen/products/SHORT/, through the GitHub API with $GH_TOKEN, never git. A
#          missing noun is fatal; a missing line is not, since a product need not have one.
# spec: tests/publish-notes-shape-test.sh
set -eu
[ $# -eq 4 ] || { echo "usage: fetch-product-names.sh REPO SHA SHORT DEST" >&2; exit 2; }
repo="$1"; sha="$2"; short="$3"; dest="$4"
case "$short" in
  ''|-*|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*)
    echo "fetch-product-names: '$short' is not a short name (lowercase letters, digits and hyphens)" >&2; exit 2 ;;
esac
d="$dest/.mavergreen/products/$short"
mkdir -p "$d"
err="$d/.err"
get() {
  if gh api -H 'Accept: application/vnd.github.raw' "repos/$repo/contents/.mavergreen/products/$short/$1?ref=$sha" > "$d/$1" 2> "$err"; then
    status=ok
  elif grep -q 'HTTP 404' "$err"; then
    status=missing
  else
    status=failed
  fi
  [ "$status" = ok ] || rm -f "$d/$1"
}
get noun
case "$status" in
  ok) ;;
  missing) rm -f "$err"; echo "fetch-product-names: $repo has no .mavergreen/products/$short/noun at $sha; write it" >&2; exit 1 ;;
  *) echo "fetch-product-names: could not fetch .mavergreen/products/$short/noun of $repo at $sha: $(cat "$err")" >&2; rm -f "$err"; exit 1 ;;
esac
[ -s "$d/noun" ] || { rm -f "$err"; echo "fetch-product-names: .mavergreen/products/$short/noun of $repo at $sha is empty" >&2; exit 1; }
get line
case "$status" in
  ok|missing) ;;
  *) echo "fetch-product-names: could not fetch .mavergreen/products/$short/line of $repo at $sha: $(cat "$err")" >&2; rm -f "$err"; exit 1 ;;
esac
rm -f "$err"
