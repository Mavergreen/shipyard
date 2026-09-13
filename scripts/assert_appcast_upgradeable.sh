#!/bin/sh
#   usage: assert_appcast_upgradeable.sh --appcast FILE --version V [--upstream-glob G | --tag-glob G]
#          --version        the release being published -- the TAG name; excluded from the tag
#                           search so a tag build compares against its PREDECESSOR, not itself.
#          --upstream-glob  scope for a repo shipping parallel upstream lines (golang: '1.26.*'), so
#                           N is compared within its own line. Searches '<G>-mavericks.*'.
#          --tag-glob       for a repo whose tags are NOT <upstream>-mavericks.N: the whole tag glob,
#                           verbatim. shipyard tags vX.Y.Z and calls this with 'v*.*.*' -- which also
#                           keeps out its moving major tag (v1). Without it the default scope finds
#                           no shipyard tag at all, and every release would take the first-release
#                           exit: the silent no-op this gate refuses. Not combinable with
#                           --upstream-glob.
#          Proves a release's Sparkle appcast will be SEEN AS AN UPGRADE by a client running the
#          previous release:
#            - <sparkle:version> is purely dotted-numeric X.Y.Z.N -- the comparator's total-order
#              domain.
#            - it is STRICTLY GREATER than the previous published release's <sparkle:version>, by
#              the same component-wise numeric comparison SUStandardVersionComparator applies.
#          Runs where the release tags live (the CI release job's checkout). With NO previous tag
#          (the first release) the ordering check is SKIPPED -- and SAID to be, never silently
#          passed. If tags can't be listed at all (not a git checkout) the gate FAILS rather than
#          skip.
# spec: claude-plugins/modernmavericks/skills/modernmavericks-conventions/SKILL.md "The Sparkle
#       comparison version must be dotted-numeric AND monotonic" -- the failure mode this catches is
#       SUStandardVersionComparator returning EQUAL for consecutive "-mavericks.N" repackages, so a
#       client reports "you're up to date". Uses lib.sh's ver_cmp (no `sort -V`, which the 10.9 box's
#       BSD sort lacks) -- the same comparator previous-release-tag.sh uses, so the two cannot
#       disagree on which tag is highest.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"          # numeric(), ver_cmp()

APPCAST=""; VER=""; GLOB=""; TAG_GLOB=""
while [ $# -gt 0 ]; do
  case "$1" in
    --appcast) APPCAST="$2"; shift 2;;
    --version) VER="$2"; shift 2;;
    --upstream-glob) GLOB="$2"; shift 2;;
    --tag-glob) TAG_GLOB="$2"; shift 2;;
    *) echo "assert_appcast_upgradeable: unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$APPCAST" ] && [ -n "$VER" ] || { echo "assert_appcast_upgradeable: need --appcast --version" >&2; exit 2; }
[ -z "$GLOB" ] || [ -z "$TAG_GLOB" ] \
  || { echo "assert_appcast_upgradeable: --upstream-glob or --tag-glob, not both" >&2; exit 2; }
[ -f "$APPCAST" ] || { echo "assert_appcast_upgradeable: no appcast: $APPCAST" >&2; exit 1; }

NEW="$(sed -n 's|.*<sparkle:version>\([^<]*\)</sparkle:version>.*|\1|p' "$APPCAST" | head -1)"
[ -n "$NEW" ] || { echo "assert_appcast_upgradeable: no <sparkle:version> in $APPCAST" >&2; exit 1; }
if ! numeric "$NEW"; then
  echo "assert_appcast_upgradeable: <sparkle:version> '$NEW' is not purely dotted-numeric -- outside SUStandardVersionComparator's orderable domain" >&2
  exit 1
fi

pattern="*-mavericks.*"; [ -z "$GLOB" ] || pattern="${GLOB}-mavericks.*"
[ -z "$TAG_GLOB" ] || pattern="$TAG_GLOB"
if ! tags="$(git tag --list "$pattern" 2>/dev/null)"; then
  echo "assert_appcast_upgradeable: cannot list git tags (not a checkout?) -- run where the release tags live; refusing to skip silently" >&2
  exit 1
fi

PREV_TAG=""; PREV=""
for t in $tags; do
  [ "$t" = "$VER" ] && continue
  # spec: tests/assert_appcast_upgradeable.bats "default scope still skips a stray v-prefixed twin"
  #       -- the leading "v" is stripped only under --tag-glob; legacysupport really has
  #       v1.5.2-mavericks.1 beside 1.5.2-mavericks.1, and the default scope must keep skipping it.
  if [ -n "$TAG_GLOB" ]; then k="${t#v}"; else k="$t"; fi
  k="$(printf '%s' "$k" | sed 's/-mavericks\./\./')"
  numeric "$k" || continue
  if [ -z "$PREV" ] || [ "$(ver_cmp "$k" "$PREV")" = 1 ]; then PREV="$k"; PREV_TAG="$t"; fi
done

if [ -z "$PREV" ]; then
  echo "assert_appcast_upgradeable: ok — sparkle:version $NEW is numeric; no previous release${GLOB:+ in line $GLOB}${TAG_GLOB:+ among tags matching $TAG_GLOB} to order against (first release)"
  exit 0
fi

case "$(ver_cmp "$NEW" "$PREV")" in
  1) echo "assert_appcast_upgradeable: ok — sparkle:version $NEW > previous $PREV (tag $PREV_TAG); a client on the previous release will see an update" ;;
  *) echo "assert_appcast_upgradeable: sparkle:version $NEW does NOT order after previous $PREV (from tag $PREV_TAG) -- a client on $PREV_TAG would NOT see this as an upgrade" >&2
     exit 1 ;;
esac
