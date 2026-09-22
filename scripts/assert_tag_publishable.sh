#!/bin/sh
#   usage: assert_tag_publishable.sh VERSION REPO_URL REF_TYPE REF_NAME SHA
#          Exit 0 to publish, 1 to refuse. The caller's own remote is asked BY URL: publish-release.yml
#          checks out shipyard, never the calling repo, so there is no `origin` here to ask. Every
#          family repo is public, so this needs no token.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "An existing tag
#       refuses the publish -- except the tag that triggered the run" -- two runs can compute the
#       same -mavericks.(N+1) and both build it; the loser must not publish and must not relabel (the
#       version is already baked into the pkg and the appcast), so it re-dispatches. A run started BY
#       a pushed tag always finds its own tag, and blanket refusal made the documented "publish from
#       a tag" model impossible (clang had no working release path at all), so that case publishes,
#       and only that case: the run's ref IS this version's tag, and the tag names the commit being
#       published.
set -eu
[ "$#" -eq 5 ] || { echo "usage: assert_tag_publishable.sh VERSION REPO_URL REF_TYPE REF_NAME SHA" >&2; exit 2; }
VER="$1"; URL="$2"; REF_TYPE="$3"; REF_NAME="$4"; SHA="$5"

set +e
# platform: both spellings, since an annotated tag's ref is the tag OBJECT and its "^{}" entry is
#           the commit; an exact pattern returns only the first, so ask for the peeled one by name
#           too.
refs="$(git ls-remote --tags "$URL" "refs/tags/$VER" "refs/tags/$VER^{}" 2>/dev/null)"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "::error::could not read tags from $URL (git ls-remote exit $rc) -- refusing to publish without knowing whether $VER is taken." >&2
  exit 1
fi
[ -n "$refs" ] || { echo "tag $VER is free"; exit 0; }

if [ "$REF_TYPE" != tag ] || [ "$REF_NAME" != "$VER" ]; then
  echo "::error::tag $VER already exists -- another run published it while this one was building." >&2
  echo "::error::Nothing was published. Re-dispatch this release: it will compute the next -mavericks.N and rebuild with that version baked in." >&2
  exit 1
fi

for sha in $(printf '%s\n' "$refs" | awk '{print $1}'); do
  if [ "$sha" = "$SHA" ]; then
    echo "tag $VER is the tag that triggered this run, at $SHA"
    exit 0
  fi
done
echo "::error::tag $VER triggered this run but points at $(printf '%s\n' "$refs" | awk 'NR==1{print $1}'), not at the commit being published ($SHA)." >&2
echo "::error::Nothing was published. A tag must name the commit whose artifacts it labels." >&2
exit 1
