#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
C="$here/../scripts/check-metadata.sh"

work="$(mktemp -d "${TMPDIR:-/tmp}/repackage-wiring-t.XXXXXX")"; trap 'rm -rf "$work"' EXIT

wiring() { ( cd "$1" && SHIPYARD_CHECK_SELECTED=repackage-wiring sh "$C" 2>&1 ); }

mkdir -p "$work/nocaller/.mavergreen/ingredients"
if ! out="$(wiring "$work/nocaller")"; then
  echo "FAIL: an empty .mavergreen/ingredients/ counts as no ingredients, so no caller is needed: $out"; exit 1
fi

mkdir -p "$work/caller/.mavergreen/ingredients" "$work/caller/.github/workflows"
printf 'jobs:\n  r:\n    uses: Mavergreen/shipyard/.github/workflows/repackage-on-ingredient-bump.yml@v1\n' \
  > "$work/caller/.github/workflows/repackage-on-ingredient-bump.yml"
if out="$(wiring "$work/caller")"; then
  echo "FAIL: a caller with only an empty .mavergreen/ingredients/ is a caller without ingredients"; exit 1
fi
case "$out" in
  repackage-wiring:*"holds no ingredient"*) ;;
  *) echo "FAIL: should name the caller as having no ingredient: $out"; exit 1 ;;
esac

wf="$here/../.github/workflows/repackage-on-ingredient-bump.yml"
grep -q 'dispatch-field' "$wf" && { echo "FAIL: repackage-on-ingredient-bump.yml takes no dispatch-field: every release.yml takes one dispatch shape"; exit 1; }
line="$(grep 'gh workflow run' "$wf")" || { echo "FAIL: repackage-on-ingredient-bump.yml dispatches with gh workflow run"; exit 1; }
case "$line" in *' -f '*|*' --field '*|*' -F '*) echo "FAIL: the bump dispatch passes no field, so the decision publishes only on changed content: $line"; exit 1 ;; esac
case "$line" in *'--ref main'*) ;; *) echo "FAIL: the bump dispatches release.yml on main: $line"; exit 1 ;; esac

echo "PASS: repackage-wiring"
