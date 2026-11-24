#!/bin/sh
# platform: host-agnostic
#   usage: retry-decision.sh VERSION REPO_URL GITHUB_REF
#          stdout: RETRY  or  SKIP=<not-main|tag-free>
#          exit 1 when the answer is unknown (git ls-remote fails) or on an unexpected argument.
set -eu
[ "$#" -eq 3 ] || { echo "usage: retry-decision.sh VERSION REPO_URL GITHUB_REF" >&2; exit 1; }
VER="$1"; URL="$2"; REF="$3"
[ -n "$VER" ] && [ -n "$URL" ] || { echo "retry-decision: VERSION and REPO_URL are required" >&2; exit 1; }

[ "$REF" = refs/heads/main ] || { echo "SKIP=not-main"; exit 0; }

set +e
refs="$(git ls-remote --tags "$URL" "refs/tags/$VER" 2>/dev/null)"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "retry-decision: could not read tags from $URL (git ls-remote exit $rc)" >&2
  exit 1
fi
[ -n "$refs" ] || { echo "SKIP=tag-free"; exit 0; }
echo "RETRY"
