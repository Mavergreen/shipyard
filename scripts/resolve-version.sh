#!/bin/sh
# platform: host-agnostic
#   usage: resolve-version.sh [auto|local]
#          With no mode, a workflow_dispatch run ($GITHUB_EVENT_NAME) resolves local, the line's next N,
#          and any other run auto, its current N.
#          Prints this repo's full version (<upstream>-mavergreen.N), writing VERSION if it is not
#          there yet. VERSION is a build PRODUCT -- written here, read by cmake,
#          gitignored, never committed. An existing VERSION is reused as-is: within one CI run, an
#          earlier job already resolved it and every job must agree.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Versioning" --
#       the shipped state lives in tags; container-tools shipped release 14 of one upstream while its committed
#       VERSION still said .2, which also made its tag-triggered publish path (tag must equal
#       VERSION) impossible to satisfy.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"          # MAVERGREEN_REPO_ROOT, mg_dir

if [ $# -gt 0 ]; then mode="$1"
elif [ "${GITHUB_EVENT_NAME:-}" = workflow_dispatch ]; then mode=local
else mode=auto
fi
vfile="$MAVERGREEN_REPO_ROOT/VERSION"

if [ -f "$vfile" ]; then
  ver="$(tr -d '[:space:]' < "$vfile")"
  [ -n "$ver" ] || { echo "resolve-version: $vfile is empty -- delete it to re-derive" >&2; exit 1; }
  printf '%s\n' "$ver"
  exit 0
fi

[ -d "$(mg_dir)/upstream" ] || {
  echo "resolve-version: no VERSION and no $(mg_dir)/upstream/" >&2
  echo "  .mavergreen/upstream/ is the committed input; VERSION is derived from it plus the shipped tags." >&2
  exit 1
}

ver="$(sh "$SELF/version.sh" "$mode" | sed -n 's/^FULL=//p')"
[ -n "$ver" ] || { echo "resolve-version: version.sh produced no FULL=" >&2; exit 1; }
printf '%s\n' "$ver" > "$vfile"
printf '%s\n' "$ver"
