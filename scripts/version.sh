#!/bin/sh
# platform: host-agnostic
#   usage: version.sh [auto|local]
#          Derives the full version (<upstream>-mavergreen.N) and its tag. Whether it is published is
#          the release decision's (release-decision.sh), never this script's.
#            auto  (default): a push, for feedback: the line's current N, or 1 for an untagged upstream.
#            local          : a dispatch: the line's next N, maxExistingN + 1.
#          N resets to 1 automatically whenever the upstream version changes (a new upstream has no tags
#          yet). Tag set comes from `git tag`, or from $MAVERGREEN_TAGS (newline-separated) when set
#          (tests).
# spec: tests/version-lib-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"          # sets MAVERGREEN_REPO_ROOT if unset; provides upstream_version()

mode="${1:-auto}"
U="$(upstream_version)"

if [ -n "${MAVERGREEN_TAGS+x}" ]; then
  tags="$MAVERGREEN_TAGS"
else
  tags="$(git -C "$MAVERGREEN_REPO_ROOT" tag --list "${U}-mavergreen.*" 2>/dev/null || true)"
fi

maxN=0
for t in $tags; do
  case "$t" in
    "${U}-mavergreen."*)
      n="${t##*.}"
      case "$n" in ''|*[!0-9]*) : ;; *) [ "$n" -gt "$maxN" ] && maxN="$n" ;; esac
      ;;
  esac
done

case "$mode" in
  auto)  if [ "$maxN" -eq 0 ]; then N=1; else N="$maxN"; fi ;;
  local) N=$((maxN + 1)) ;;
  *) echo "version.sh: mode must be 'auto' or 'local' (got '$mode')" >&2; exit 2 ;;
esac

full="${U}-mavergreen.${N}"
printf 'FULL=%s\nTAG=%s\n' "$full" "$full"
