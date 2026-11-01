#!/bin/sh
# platform: host-agnostic
#   usage: gen-conventions-grandfathered.sh <clones-dir> > scripts/conventions-grandfathered
#          Lists the org's unarchived repos (gh repo list Mavergreen), clones each into <clones-dir>
#          or refreshes an existing clone to origin's default branch (<clones-dir> is owned by this
#          script: new or empty, or marked by a sentinel file; it refuses anything else, and a
#          clone whose origin is not Mavergreen/<name>), keeps those whose workflows
#          reference family-conventions.yml (the repos this gate runs in, registered or not), runs a
#          copy of this gate WITHOUT the grandfathered file in each, and prints what the checks that
#          consult it (packager, macos-runner, artifact-checks-wired, modern-smoke) find, as sorted
#          "<check> <repo> <job|path>" lines. shipyard itself is read from this working tree,
#          and the org's .github profile repo is skipped.
#          modern-smoke and cxxabi are also found in what each repo last shipped: the latest release's pkgs,
#          downloaded into <clones-dir>/.releases/<repo>/<tag> (kept until the tag moves), read by
#          artifact-facts.sh and that copy of check-artifact-conformance.sh; cxxabi is one line per
#          installed path (%20-encoded) with a cxxabi fact and no cxxabi:<glob> declaration. A release that cannot
#          be read fails the run; a repo with no release, or none carrying a pkg, ships nothing.
#          Needs gh, a python3 with PyYAML first on PATH, and lipo, otool and nm (or LIPO, OTOOL and NM).
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
. "$tmp/scripts/deviation-reason.sh"
{ echo shipyard; gh repo list Mavergreen --no-archived --limit 500 --json name -q '.[].name' </dev/null; } | sort -u > "$tmp/repos"
while read -r repo; do
  [ "$repo" != .github ] || continue
  case "$repo" in ''|.*|*[!A-Za-z0-9._-]*) echo "gen-conventions-grandfathered: refusing the repo name '$repo'" >&2; exit 2 ;; esac
  if [ "$repo" = shipyard ]; then dir="$ROOT"; else
    dir="$clones/$repo"
    if [ -e "$dir" ]; then
      top="$(git -C "$dir" rev-parse --show-toplevel </dev/null 2>/dev/null || :)"
      phys="$(cd -P "$dir" && pwd -P)"
      [ -n "$top" ] && [ "$(cd -P "$top" && pwd -P)" = "$phys" ] \
        || { echo "gen-conventions-grandfathered: $dir is not itself a git checkout (git finds '${top:-none}' above it); remove it yourself" >&2; exit 2; }
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
        -e "s|^\(packager\): \([^ ]*\) builds a pkg .*|\1 $repo \2|p" \
        -e "s|^\(macos-runner\): \([^ ]*\) runs on a macos-.*|\1 $repo \2|p" \
        -e "s|^\(modern-smoke\): .*|\1 $repo release.yml:modern-smoke|p" \
        -e "s|.*builds a \.pkg (\([^ )]*\) via stevedore).*|artifact-checks-wired $repo \1|p"
  rc=0; view="$(gh release view --repo "Mavergreen/$repo" --json tagName,assets --jq '.tagName, (.assets[].name)' </dev/null 2>"$tmp/err")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    grep -q 'release not found' "$tmp/err" && continue
    echo "gen-conventions-grandfathered: cannot read Mavergreen/$repo's latest release: $(cat "$tmp/err")" >&2; exit 1
  fi
  tag="$(printf '%s\n' "$view" | head -1)"
  case "$tag" in ''|.*|*[!A-Za-z0-9._+-]*) echo "gen-conventions-grandfathered: refusing Mavergreen/$repo's release tag '$tag'" >&2; exit 2 ;; esac
  printf '%s\n' "$view" | sed 1d | grep -q '\.pkg$' || continue
  rel="$clones/.releases/$repo"
  if [ ! -f "$rel/$tag/.complete" ]; then
    rm -rf "$rel"; mkdir -p "$rel/$tag"
    gh release download "$tag" --repo "Mavergreen/$repo" --pattern '*.pkg' --dir "$rel/$tag" </dev/null >&2
    : > "$rel/$tag/.complete"
  fi
  (cd "$dir" && GITHUB_REPOSITORY="Mavergreen/$repo" sh "$tmp/scripts/artifact-facts.sh" "$rel/$tag" "$tag" "$dir" </dev/null 2>"$tmp/err" || :) > "$tmp/facts"
  if grep -q '^abort ' "$tmp/facts" || ! grep -qx 'end-of-facts' "$tmp/facts"; then
    echo "gen-conventions-grandfathered: cannot read what Mavergreen/$repo $tag shipped: $(cat "$tmp/err")" >&2; exit 1
  fi
  grep '^deviation ' "$tmp/facts" > "$tmp/devs" || :
  awk '$1 == "cxxabi-defines" || $1 == "cxxabi-loads" { print $3 }' "$tmp/facts" | LC_ALL=C sort -u | while read -r p; do
    [ -n "$(shipyard_deviation_reason "$tmp/devs" cxxabi "$(printf '%s' "$p" | sed -e 's/%20/ /g' -e 's/%25/%/g')")" ] \
      || echo "cxxabi $repo $p"
  done
  if sh "$tmp/scripts/check-artifact-conformance.sh" < "$tmp/facts" 2>&1 >/dev/null | grep -q '^arm64: .* with an arm64 slice'; then
    echo "modern-smoke $repo release.yml:modern-smoke"
  fi
done < "$tmp/repos" > "$tmp/found"
LC_ALL=C sort -u "$tmp/found"
