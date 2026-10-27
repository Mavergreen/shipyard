#!/bin/sh
# platform: host-agnostic
#   usage: gen-conventions-grandfathered.sh <clones-dir> > scripts/conventions-grandfathered
#          Clones (depth 1, with gh) every repo in scripts/product-names that <clones-dir> lacks,
#          runs a copy of this gate WITHOUT the grandfathered file in each, and prints what the
#          checks that consult it (packager, macos-runner, artifact-conformance) find, as sorted
#          "<check> <repo> <job|path>" lines. shipyard itself is read from this working tree, not
#          cloned. Needs a python3 with PyYAML first on PATH.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SELF/.." && pwd)"
clones="${1:?usage: gen-conventions-grandfathered.sh <clones-dir>}"
mkdir -p "$clones"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/gen-grandfathered.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT
cp -R "$SELF" "$tmp/scripts"; rm -f "$tmp/scripts/conventions-grandfathered"
for repo in $(awk '!/^#/ && NF { print $3 }' "$SELF/product-names" | sort -u); do
  if [ "$repo" = shipyard ]; then dir="$ROOT"; else
    dir="$clones/$repo"
    [ -d "$dir" ] || gh repo clone "Mavergreen/$repo" "$dir" -- --depth 1 >&2
  fi
  (cd "$dir" && GITHUB_REPOSITORY="Mavergreen/$repo" sh "$tmp/scripts/check-family-conventions.sh" 2>&1 >/dev/null || :) \
    | sed -n \
        -e "s|^check-family-conventions: \(packager\) \([^ :]*\): .*|\1 $repo \2|p" \
        -e "s|^check-family-conventions: \(macos-runner\) \([^ :]*\): .*|\1 $repo \2|p" \
        -e "s|.*builds a \.pkg (\([^ )]*\) via stevedore).*|artifact-conformance $repo \1|p"
done | LC_ALL=C sort -u
