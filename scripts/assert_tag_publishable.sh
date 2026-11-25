#!/bin/sh
# platform: host-agnostic
#   usage: assert_tag_publishable.sh VERSION REPO_URL
#          Exit 0 to publish, 1 to refuse: any existing tag refuses. The caller's own remote is asked
#          BY URL: publish-release.yml checks out shipyard, never the calling repo, so there is no
#          `origin` here to ask. Every family repo is public, so this needs no token.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "An existing tag refuses the publish"
set -eu
[ "$#" -eq 2 ] || { echo "usage: assert_tag_publishable.sh VERSION REPO_URL" >&2; exit 2; }
VER="$1"; URL="$2"

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

echo "::error::tag $VER already exists -- another run published it while this one was building." >&2
echo "::error::Nothing was published. Re-dispatch this release: it will compute the next -mavericks.N and rebuild with that version baked in." >&2
exit 1
