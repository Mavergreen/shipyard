#!/bin/sh
# platform: host-agnostic
#   usage: gen-conventions-grandfathered.sh <clones-dir> > scripts/conventions-grandfathered
#          Lists the org's unarchived repos (gh repo list Mavergreen), clones each into <clones-dir>
#          or refreshes an existing clone to origin's default branch, keeps those whose workflows
#          reference family-conventions.yml (the repos this gate runs in, registered or not), runs a
#          copy of this gate WITHOUT the grandfathered file in each, and prints what the checks that
#          consult it (packager, macos-runner, artifact-conformance) find, as sorted
#          "<check> <repo> <job|path>" lines. shipyard itself is read from this working tree.
#          Needs gh and a python3 with PyYAML first on PATH.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SELF/.." && pwd)"
clones="${1:?usage: gen-conventions-grandfathered.sh <clones-dir>}"
mkdir -p "$clones"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/gen-grandfathered.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT
cp -R "$SELF" "$tmp/scripts"; rm -f "$tmp/scripts/conventions-grandfathered"
{ echo shipyard; gh repo list Mavergreen --no-archived --limit 500 --json name -q '.[].name'; } | sort -u > "$tmp/repos"
while read -r repo; do
  if [ "$repo" = shipyard ]; then dir="$ROOT"; else
    dir="$clones/$repo"
    if [ -d "$dir/.git" ]; then
      git -C "$dir" fetch -q --depth 1 origin HEAD >&2
      git -C "$dir" reset -q --hard FETCH_HEAD >&2
    else
      rm -rf "$dir"; gh repo clone "Mavergreen/$repo" "$dir" -- --depth 1 >&2
    fi
    # shellcheck disable=SC2046  # a deliberate word-split list of workflow files
    grep -qs 'family-conventions\.yml' $(ls "$dir"/.github/workflows/* 2>/dev/null) || continue
  fi
  (cd "$dir" && GITHUB_REPOSITORY="Mavergreen/$repo" sh "$tmp/scripts/check-family-conventions.sh" 2>&1 >/dev/null || :) \
    | sed -n \
        -e "s|^check-family-conventions: \(packager\) \([^ ]*\): .*|\1 $repo \2|p" \
        -e "s|^check-family-conventions: \(macos-runner\) \([^ ]*\): .*|\1 $repo \2|p" \
        -e "s|.*builds a \.pkg (\([^ )]*\) via stevedore).*|artifact-conformance $repo \1|p"
done < "$tmp/repos" | LC_ALL=C sort -u
