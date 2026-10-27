#!/bin/sh
# platform: host-agnostic
#   usage: gen-conventions-grandfathered.sh <clones-dir> > scripts/conventions-grandfathered
#          Lists the org's unarchived repos (gh repo list Mavergreen), clones each into <clones-dir>
#          or refreshes an existing clone to origin's default branch (<clones-dir> is owned by this
#          script: new or empty, or marked by a sentinel file; it refuses anything else, and a
#          clone whose origin is not Mavergreen/<name>), keeps those whose workflows
#          reference family-conventions.yml (the repos this gate runs in, registered or not), runs a
#          copy of this gate WITHOUT the grandfathered file in each, and prints what the checks that
#          consult it (packager, macos-runner, artifact-conformance) find, as sorted
#          "<check> <repo> <job|path>" lines. shipyard itself is read from this working tree.
#          Needs gh and a python3 with PyYAML first on PATH.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SELF/.." && pwd)"
clones="${1:?usage: gen-conventions-grandfathered.sh <clones-dir>}"
sentinel=".gen-conventions-grandfathered"
if [ -d "$clones" ] && [ ! -f "$clones/$sentinel" ] && [ -n "$(ls -A "$clones")" ]; then
  echo "gen-conventions-grandfathered: $clones is not empty and is not a directory this script made (no $sentinel in it); give it an empty or new directory" >&2
  exit 2
fi
mkdir -p "$clones"; : > "$clones/$sentinel"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/gen-grandfathered.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT
cp -R "$SELF" "$tmp/scripts"; rm -f "$tmp/scripts/conventions-grandfathered"
{ echo shipyard; gh repo list Mavergreen --no-archived --limit 500 --json name -q '.[].name' </dev/null; } | sort -u > "$tmp/repos"
while read -r repo; do
  case "$repo" in ''|.*|*[!A-Za-z0-9._-]*) echo "gen-conventions-grandfathered: refusing the repo name '$repo'" >&2; exit 2 ;; esac
  if [ "$repo" = shipyard ]; then dir="$ROOT"; else
    dir="$clones/$repo"
    if [ -e "$dir" ]; then
      url="$(git -C "$dir" config --get remote.origin.url </dev/null 2>/dev/null || :)"; url="${url%.git}"
      case "$url" in
        */Mavergreen/"$repo"|*:Mavergreen/"$repo") ;;
        *) echo "gen-conventions-grandfathered: $dir exists but its origin is '$url', not Mavergreen/$repo; remove it yourself" >&2; exit 2 ;;
      esac
      git -C "$dir" fetch -q --depth 1 origin HEAD </dev/null >&2
      git -C "$dir" reset -q --hard FETCH_HEAD </dev/null >&2
    else
      gh repo clone "Mavergreen/$repo" "$dir" </dev/null -- --depth 1 >&2
    fi
    set -- "$dir"/.github/workflows/*
    [ -e "$1" ] || continue
    grep -qs 'family-conventions\.yml' "$@" </dev/null || continue
  fi
  (cd "$dir" && GITHUB_REPOSITORY="Mavergreen/$repo" sh "$tmp/scripts/check-family-conventions.sh" 2>&1 >/dev/null </dev/null || :) \
    | sed -n \
        -e "s|^check-family-conventions: \(packager\) \([^ ]*\): .*|\1 $repo \2|p" \
        -e "s|^check-family-conventions: \(macos-runner\) \([^ ]*\): .*|\1 $repo \2|p" \
        -e "s|.*builds a \.pkg (\([^ )]*\) via stevedore).*|artifact-conformance $repo \1|p"
done < "$tmp/repos" > "$tmp/found"
LC_ALL=C sort -u "$tmp/found"
