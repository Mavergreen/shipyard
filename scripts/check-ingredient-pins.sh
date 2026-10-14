#!/bin/sh
# platform: host-agnostic
#   usage: check-ingredient-pins.sh [caller-workflow-path]
#          Guards the ingredient pin declaration. The notes and the repackage trigger read ONE list
#          (ingredient-pins.sh), so they cannot disagree -- but a list can still be wrong on its own:
#          a typo'd glob that matches nothing, or a caller whose every watched path is own-upstream,
#          both yield silently thinner release notes and a repackage that never fires. A repo with no
#          caller workflow has no ingredients and passes trivially.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/check-lib.sh"
caller="${1:-.github/workflows/repackage-on-ingredient-bump.yml}"

if [ ! -f "$caller" ]; then
  chk_notrun ingredient-pins "no $caller, so this repo declares no build ingredients"
  exit 0
fi

if grep -Eq '^[[:space:]]+workflow_call:' "$caller" \
   && ! grep -Eq '^[[:space:]]+(push|pull_request|workflow_dispatch|schedule|release):|^(on|"on"):.*(push|pull_request|workflow_dispatch|schedule|release)' "$caller"; then
  chk_notrun ingredient-pins "$caller is a reusable workflow, not a caller, so it declares no ingredients"
  exit 0
fi

chk_ran ingredient-pins
pins="$(sh "$SELF/ingredient-pins.sh" "$caller")"
if [ -z "$pins" ]; then
  chk_fail ingredient-pins "$caller watches paths, but none expand to a tracked ingredient pin" \
    "a glob matches nothing (a typo?), or every watched path is own-upstream-paths, and either way the notes thin silently and the repackage never fires" \
    "correct the paths: glob in $caller, or narrow own-upstream-paths"
  exit 1
fi

for p in $pins; do
  # spec: scripts/ingredient-pins.sh -- a "path:KEY" entry (own-upstream-paths key form) names a
  #       tracked FILE plus a key excluded from it; only the path half is a git path, so strip the
  #       key before testing it.
  path="${p%%:*}"
  git ls-files --error-unmatch "$path" >/dev/null 2>&1 \
    || chk_fail ingredient-pins "pin '$p' is not tracked in git" \
         "the notes read pin history from git, so an untracked pin has none" \
         "git add $path, or drop it from $caller's paths"
done

[ "$chk_status" -eq 0 ] && printf 'check-ingredient-pins: ok — %s\n' "$(printf '%s' "$pins" | tr '\n' ' ')"
exit "$chk_status"
