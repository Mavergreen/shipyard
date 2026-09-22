#!/bin/sh
#   usage: shipyard-version.sh          (prints FULL=<line>.<count> and TAG=v<line>.<count>)
#          shipyard's own version -- UPSTREAM_VERSION holds the LINE (major.minor); the patch is the
#          commit count, so a new commit is necessarily a new version with no discipline to remember.
#          NOT resolve-version.sh: that hardcodes -mavericks.N, which is for repackaged upstreams, not
#          for us.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "shipyard: consume
#       its facilities, never hand-roll them" -- we are our own upstream, consumed through a MOVING
#       tag (@v1), so the version must change whenever the content does: UPSTREAM_VERSION once sat at
#       1.0.5 while 13 commits each shipped to fifteen repos through @v1, every one claiming to be
#       1.0.5.
# spec: tests/shipyard-version-test.sh
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$root/UPSTREAM_VERSION" ] || { echo "shipyard-version: no $root/UPSTREAM_VERSION" >&2; exit 1; }
line="$(sed -n '1p' "$root/UPSTREAM_VERSION" | tr -d ' \t')"

case "$line" in
  [0-9]*.[0-9]*.*) echo "shipyard-version: UPSTREAM_VERSION holds the LINE (major.minor), not a full version: $line" >&2; exit 1 ;;
  [0-9]*.[0-9]*) : ;;
  *) echo "shipyard-version: UPSTREAM_VERSION is not a major.minor line: $line" >&2; exit 1 ;;
esac

# platform: `--is-shallow-repository` needs git >= 2.15 (2017); that floor is safe for every runner
#           and dev box in this family.
if [ "$(git -C "$root" rev-parse --is-shallow-repository)" = "true" ]; then
  echo "shipyard-version: $root is a shallow clone; the commit count is meaningless there. Fetch full history (fetch-depth: 0 in CI, or 'git fetch --unshallow' locally) and retry." >&2
  exit 1
fi

count="$(git -C "$root" rev-list --count HEAD)"
echo "FULL=$line.$count"
echo "TAG=v$line.$count"
