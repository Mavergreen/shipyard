#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
C="$here/../scripts/check-metadata.sh"
fx="$here/fixtures/checks"
. "$here/lib/fixture_tree.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/legacy-top-level-t.XXXXXX")"; trap 'rm -rf "$work"' EXIT

goes() {  # $1 = fixture, $2 = the legacy name, $3 = where the failure says it goes
  t="$work/$1"
  fixture_tree "$fx" "$fx/legacy-top-level/$1" "$t"
  rm -f "$t/FILES"
  if out="$(cd "$t" && SHIPYARD_CHECK_SELECTED=legacy-top-level SHIPYARD_CHECK_FILES="$fx/legacy-top-level/$1/FILES" sh "$C" 2>&1)"; then
    echo "FAIL $1: expected $2 to be refused"; exit 1
  fi
  printf '%s\n' "$out" | grep -F "legacy-top-level: $2 is legacy metadata at the top level: " | grep -Fq -e "$3" \
    || { echo "FAIL $1: the failure should name $2 and say $3: $out"; exit 1; }
}

goes fail INGREDIENTS.md ".mavergreen/"
goes fail-ingredients-title INGREDIENTS.md ".mavergreen/"
goes fail-upstream-version UPSTREAM_VERSION ".mavergreen/upstream/VERSION"
goes fail-upstream-commit UPSTREAM_COMMIT ".mavergreen/upstream/COMMIT"
goes fail-pins-env pins.env ".mavergreen/ingredients/<name>/"
goes fail-manifest MANIFEST "it is retired"
goes fail-components components/ ".mavergreen/ingredients/<name>/"
goes fail-intree .mavericks-intree ".mavergreen/intree"
goes fail-comment-reasons comment-reasons ".mavergreen/config/comment-reasons"
goes fail-msc msc.sh "it is retired"
goes fail-build-msc build/msc.sh "it is retired"

printf '%s\n' "$out" | grep -Fq 'shipyard-scripts' \
  || { echo "FAIL: a retired msc.sh should name what replaces it: $out"; exit 1; }
goes fail-release-notes release-notes/ ".mavergreen/release-notes/"
goes fail INGREDIENTS.md "it may hold a ## Declared state section and nothing else"
printf '%s\n' "$out" | grep -Fq '.mavergreen/deviations/<check>/<label>/' \
  || { echo "FAIL: an INGREDIENTS.md with deviations should say where deviations go now: $out"; exit 1; }

echo "PASS: legacy-top-level"
