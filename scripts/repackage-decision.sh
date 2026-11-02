#!/bin/sh
# platform: host-agnostic
#   usage: repackage-decision.sh
#          env in:  CHANGED (newline-separated paths changed this push)
#                   MAVERGREEN_ROOT (the repo; default: the git top level)
#          stdout:  DISPATCH  or  SKIP=<reason>
#          SKIP=own-upstream-changed when any path is under .mavergreen/upstream/ (a new own upstream
#          is the release's job, not a repackage's); else DISPATCH when any path is under
#          .mavergreen/ingredients/ or matches a line of any ingredient's watch; else
#          SKIP=no-ingredient-changed.
# spec: tests/repackage-decision-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavergreen-meta.sh"

_tmp="${TMPDIR:-/tmp}"
work="$(mktemp -d "${_tmp%/}/repackage-decision.XXXXXX")"
trap 'rm -rf "$work"' EXIT
printf '%s\n' "${CHANGED:-}" > "$work/changed"

if [ -n "$(mg_glob_hits '.mavergreen/upstream/*' "$work/changed")" ]; then
  echo "SKIP=own-upstream-changed"; exit 0
fi
if [ -n "$(mg_glob_hits '.mavergreen/ingredients/*' "$work/changed")" ]; then
  echo "DISPATCH"; exit 0
fi
for _n in $(mg_list ingredients); do
  mg_has "ingredients/$_n/watch" || continue
  while IFS= read -r _g; do
    [ -n "$_g" ] || continue
    if [ -n "$(mg_glob_hits "$_g" "$work/changed")" ]; then
      echo "DISPATCH"; exit 0
    fi
  done <<EOT
$(mg_lines "ingredients/$_n/watch")
EOT
done
echo "SKIP=no-ingredient-changed"
