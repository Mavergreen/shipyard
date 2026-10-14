#!/bin/sh
# platform: host-agnostic
#   usage: push-tag-with-token.sh <tag> [<sha>] [-m <message>]
#          push-tag-with-token.sh --delete <tag>
#          Force-pushes an annotated tag at <sha> (default HEAD) to $GITHUB_REPOSITORY, or deletes it.
#          The token comes from GH_TOKEN through GIT_ASKPASS, so a checkout made with
#          persist-credentials: false can still push and no token is on a command line.
set -eu
: "${GH_TOKEN:?push-tag-with-token: GH_TOKEN is required}"
: "${GITHUB_REPOSITORY:?push-tag-with-token: GITHUB_REPOSITORY is required}"
url="https://x-access-token@github.com/$GITHUB_REPOSITORY"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/push-tag.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT
printf '#!/bin/sh\necho "$GH_TOKEN"\n' > "$tmp/askpass"; chmod +x "$tmp/askpass"
authed() { GIT_ASKPASS="$tmp/askpass" GIT_TERMINAL_PROMPT=0 git "$@"; }
push() { authed push "$@"; }

if [ "${1:-}" = "--delete" ]; then
  [ $# -eq 2 ] || { echo "usage: push-tag-with-token.sh --delete <tag>" >&2; exit 2; }
  push "$url" ":refs/tags/$2"
  echo "deleted $2"
  exit 0
fi

tag="${1:?usage: push-tag-with-token.sh <tag> [<sha>] [-m <message>]}"; shift
sha=HEAD; msg="$tag"
[ $# -eq 0 ] || [ "$1" = "-m" ] || { sha="$1"; shift; }
[ "${1:-}" != "-m" ] || { msg="${2:?push-tag-with-token: -m needs a message}"; }

# platform: this force-push used to be unconditional, so two overlapping releases raced and
#           whichever job finished LAST won -- on 2026-09-16 that moved v1 BACKWARDS onto an
#           older commit and served every consumer a stale action for 40 minutes. Moving the
#           tag only forward is monotonic whatever order the jobs finish in.
rc=0; remote="$(authed ls-remote "$url" "refs/tags/$tag")" || rc=$?
if [ "$rc" -ne 0 ]; then
  echo "push-tag-with-token: cannot read $tag from $GITHUB_REPOSITORY (git ls-remote exit $rc), so it cannot tell whether moving it would go backwards; nothing was pushed" >&2
  exit 1
fi
if [ -n "$remote" ]; then
  authed fetch --force "$url" "refs/tags/$tag:refs/tags/$tag" \
    || { echo "push-tag-with-token: $GITHUB_REPOSITORY has $tag, but fetching it failed; nothing was pushed" >&2; exit 1; }
else
  git tag -d "$tag" >/dev/null 2>&1 || :
fi
if git rev-parse -q --verify "$tag^{commit}" >/dev/null 2>&1 \
   && git merge-base --is-ancestor "$sha" "$tag^{commit}"; then
  echo "$tag is already at or ahead of $(git rev-parse --short "$sha"); leaving it alone"
  exit 0
fi
git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  tag -f -a "$tag" -m "$msg" "$sha"
push -f "$url" "$tag"
echo "moved $tag -> $(git rev-parse --short "$sha")"
