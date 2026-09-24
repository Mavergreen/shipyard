#!/bin/sh
# platform: host-agnostic
#   usage: resolve-version.sh [auto|local]
#          Prints this repo's full version (<upstream>-mavericks.N), writing VERSION if it is not
#          there yet. VERSION is a build PRODUCT -- written here, read by cmake and the updater,
#          gitignored, never committed. An existing VERSION is reused as-is: within one CI run, an
#          earlier job already resolved it and every job must agree.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Versioning" --
#       the shipped state lives in tags; container-tools shipped -mavericks.14 while its committed
#       VERSION still said .2, which also made its tag-triggered publish path (tag must equal
#       VERSION) impossible to satisfy.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"          # MAVERICKS_ROOT, upstream_version()

mode="${1:-auto}"
vfile="$MAVERICKS_ROOT/VERSION"

if [ -f "$vfile" ]; then
  ver="$(tr -d '[:space:]' < "$vfile")"
  [ -n "$ver" ] || { echo "resolve-version: $vfile is empty -- delete it to re-derive" >&2; exit 1; }
  printf '%s\n' "$ver"
  exit 0
fi

upfile="${MAVERICKS_UPSTREAM_FILE:-$MAVERICKS_ROOT/UPSTREAM_VERSION}"
[ -f "$upfile" ] || {
  echo "resolve-version: no VERSION and no UPSTREAM_VERSION ($upfile)" >&2
  echo "  UPSTREAM_VERSION is the committed input; VERSION is derived from it plus the shipped tags." >&2
  exit 1
}

ver="$(sh "$SELF/version.sh" "$mode" | sed -n 's/^FULL=//p')"
[ -n "$ver" ] || { echo "resolve-version: version.sh produced no FULL=" >&2; exit 1; }
printf '%s\n' "$ver" > "$vfile"
printf '%s\n' "$ver"
