#!/bin/sh
# platform: host-agnostic
#   usage: fetch-name-inputs.sh REPO SHA SHORT DEST
#          Fetches .mavergreen/products/SHORT/noun and line of REPO at SHA into
#          DEST/.mavergreen/products/SHORT/, through the GitHub API with $GH_TOKEN, never git. A
#          missing noun is fatal; a missing line is not, since a product need not have one. Also fetches
#          every .mavergreen/deviations/publish-unchanged/<label>/{scope,reason,revisit} into DEST, which
#          release-decision.sh reads; a repo with none fetches none.
# spec: tests/publish-notes-shape-test.sh
set -eu
[ $# -eq 4 ] || { echo "usage: fetch-name-inputs.sh REPO SHA SHORT DEST" >&2; exit 2; }
repo="$1"; sha="$2"; short="$3"; dest="$4"
case "$short" in
  ''|-*|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*)
    echo "fetch-name-inputs: '$short' is not a short name (lowercase letters, digits and hyphens)" >&2; exit 2 ;;
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
  missing) rm -f "$err"; echo "fetch-name-inputs: $repo has no .mavergreen/products/$short/noun at $sha; write it" >&2; exit 1 ;;
  *) echo "fetch-name-inputs: could not fetch .mavergreen/products/$short/noun of $repo at $sha: $(cat "$err")" >&2; rm -f "$err"; exit 1 ;;
esac
[ -s "$d/noun" ] || { rm -f "$err"; echo "fetch-name-inputs: .mavergreen/products/$short/noun of $repo at $sha is empty" >&2; exit 1; }
get line
case "$status" in
  ok|missing) ;;
  *) echo "fetch-name-inputs: could not fetch .mavergreen/products/$short/line of $repo at $sha: $(cat "$err")" >&2; rm -f "$err"; exit 1 ;;
esac
rm -f "$err"
pu=.mavergreen/deviations/publish-unchanged
if labels="$(gh api "repos/$repo/contents/$pu?ref=$sha" --jq '.[] | select(.type == "dir") | .name' 2> "$dest/.err")"; then
  for l in $labels; do
    case "$l" in ''|.*|*/*) echo "fetch-name-inputs: '$l' is not a deviation label" >&2; exit 1 ;; esac
    mkdir -p "$dest/$pu/$l"
    for f in scope reason revisit; do
      gh api -H 'Accept: application/vnd.github.raw' "repos/$repo/contents/$pu/$l/$f?ref=$sha" > "$dest/$pu/$l/$f" 2> "$dest/.err" \
        || { echo "fetch-name-inputs: could not fetch $pu/$l/$f of $repo at $sha: $(cat "$dest/.err")" >&2; rm -f "$dest/.err"; exit 1; }
    done
  done
elif ! grep -q 'HTTP 404' "$dest/.err"; then
  echo "fetch-name-inputs: could not list $pu of $repo at $sha: $(cat "$dest/.err")" >&2; rm -f "$dest/.err"; exit 1
fi
rm -f "$dest/.err"
