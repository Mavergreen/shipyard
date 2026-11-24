#!/bin/sh
# platform: host-agnostic
#   usage: reproduce.sh --dist DIST --repo OWNER/REPO --tag TAG --repo-root DIR
#          Compares DIST, a rebuild of TAG, with what TAG published. Writes DIST's content manifest
#          (content-manifest.sh, GITHUB_REPOSITORY set to OWNER/REPO) and prints release-decision.sh
#          --compare-only's "-<row>" and "+<row>" lines against TAG. When they differ, each DIST/*.pkg
#          is paired with TAG's asset of the same name and build-equivalence.sh's lines follow. First,
#          when TAG's RELEASE-MANIFEST.txt names a shipyard other than $SHIPYARD_VERSION:
#          "built with shipyard <A>, reproduced with <B>". Exit 0 identical, 1 different, 2 when TAG's
#          manifest cannot be fetched or read, DIST's cannot be written, or on usage.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Reproducible builds" -- a
#       release that can't be rebuilt from its tag isn't reproducible, and the report says where.
set -eu
LC_ALL=C; export LC_ALL
SELF="$(cd "$(dirname "$0")" && pwd)"
usage() { echo "usage: reproduce.sh --dist DIST --repo OWNER/REPO --tag TAG --repo-root DIR" >&2; exit 2; }
dist=""; repo=""; tag=""; root=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dist|--repo|--tag|--repo-root)
      [ $# -ge 2 ] || usage
      case "$1" in --dist) dist="$2" ;; --repo) repo="$2" ;; --tag) tag="$2" ;; --repo-root) root="$2" ;; esac
      shift 2 ;;
    *) usage ;;
  esac
done
[ -d "$dist" ] && [ -n "$tag" ] && [ -d "$root" ] || usage
case "$repo" in */?*) ;; *) usage ;; esac
w="$(mktemp -d "${TMPDIR:-/tmp}/reproduce.XXXXXX")"; trap 'rm -rf "$w"' EXIT

if rm_="$(sh "$SELF/fetch-release-pkg.sh" "${repo#*/}" "$tag" RELEASE-MANIFEST.txt "$w/rm" 2>/dev/null)"; then
  built="$(awk '$1 == "shipyard" { print $2; exit }' "$rm_")"
  [ -z "$built" ] || [ -z "${SHIPYARD_VERSION:-}" ] || [ "$built" = "$SHIPYARD_VERSION" ] \
    || echo "built with shipyard $built, reproduced with $SHIPYARD_VERSION"
fi

GITHUB_REPOSITORY="$repo" sh "$SELF/content-manifest.sh" "$dist" "${tag#v}" "$root" > "$w/manifest" \
  || { echo "reproduce: cannot write the content manifest of $dist" >&2; exit 2; }
rc=0; sh "$SELF/release-decision.sh" --compare-only --manifest "$w/manifest" --repo "$repo" --against "$tag" || rc=$?
[ "$rc" -eq 1 ] || exit "$rc"
for p in "$dist"/*.pkg; do
  [ -f "$p" ] || continue
  old="$(sh "$SELF/fetch-release-pkg.sh" "${repo#*/}" "$tag" "${p##*/}" "$w/old" 2> "$w/err")" \
    || { echo "reproduce: $tag has no ${p##*/} to compare: $(tail -n 1 "$w/err")"; continue; }
  sh "$SELF/build-equivalence.sh" --repo "$root" "$old" "$p" 2>&1 || :
done
exit 1
