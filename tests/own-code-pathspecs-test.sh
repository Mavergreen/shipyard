#!/bin/sh
# platform: host-agnostic
# spec: scripts/own-code-pathspecs.sh -- the family's one own-code path list: exclusions by default,
#       the positive pin pathspecs with --pins; a refusing parser exits 2.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
P="$here/../scripts/own-code-pathspecs.sh"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/own-code-pathspecs-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT

mkdir -p "$w/r"
printf '%s\n' '# Build ingredients' '' '## Declared state' '' '- upstream: pins.env:UP' '' \
  '## Conformance deviations' '' '- self-upstream-exclude:docs/**: prose' > "$w/r/INGREDIENTS.md"

sh "$P" --root "$w/r" > "$w/out"
[ "$(tail -n 2 "$w/out")" = ':(exclude,literal)pins.env
:(exclude,glob)docs/**' ] || { echo "FAIL: the last two exclusions must be the declared file and the glob"; cat "$w/out"; exit 1; }
[ "$(head -n 1 "$w/out")" = ':(exclude,glob)UPSTREAM_VERSION' ] || { echo "FAIL: the fixed list comes first"; exit 1; }

sh "$P" --root "$w/r" --pins > "$w/out"
grep -qxF ':(literal)pins.env' "$w/out" || { echo "FAIL: --pins must list the declared-state file"; cat "$w/out"; exit 1; }
for s in ':(glob)UPSTREAM_VERSION' ':(glob)components/*/version' ':(glob)ingredients/**'; do
  grep -qxF "$s" "$w/out" || { echo "FAIL: --pins lacks $s"; exit 1; }
done

mkdir -p "$w/pw/.github/workflows"
printf '%s\n' '# Build ingredients' '' '## Declared state' '' '- upstream: UPSTREAM_VERSION' > "$w/pw/INGREDIENTS.md"
printf '%s\n' 'jobs:' '  r:' '    with:' '      paths: ["tools.env"]' '      own-upstream-paths: tools.env:X' \
  > "$w/pw/.github/workflows/repackage-on-ingredient-bump.yml"
git init -q "$w/pw"; git -C "$w/pw" add -A >/dev/null 2>&1 || true
echo 1 > "$w/pw/tools.env"; git -C "$w/pw" add tools.env
sh "$P" --root "$w/pw" --pins > "$w/out"
grep -qxF ':(literal)tools.env' "$w/out" || { echo "FAIL: --pins must list each ingredient-pins.sh path, :KEY stripped"; cat "$w/out"; exit 1; }

mkdir -p "$w/bad"
printf '%s\n' '# Build ingredients' '' '## Declared state' '' '- upstream:' > "$w/bad/INGREDIENTS.md"
_rc=0; sh "$P" --root "$w/bad" >"$w/out" 2>"$w/err" || _rc=$?
[ "$_rc" = 2 ] || { echo "FAIL: a malformed declared state must exit 2, got $_rc"; exit 1; }
grep -q "Declared state" "$w/err" || { echo "FAIL: the refusal must say why"; exit 1; }

echo "PASS: own-code-pathspecs"
