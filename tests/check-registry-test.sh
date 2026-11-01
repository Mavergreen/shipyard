#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
reg="$here/scripts/check-ids.tsv"
fail() { echo "FAIL $1"; exit 1; }

[ -f "$reg" ] || fail "scripts/check-ids.tsv exists"

ids="$(cut -f1 "$reg")"
for id in $ids; do
  printf '%s\n' "$id" | grep -Eq '^[a-z][a-z0-9-]*$' || fail "id $id is lowercase kebab-case"
done
dups="$(printf '%s\n' "$ids" | sort | uniq -d)"
[ -z "$dups" ] || fail "ids are unique, duplicated: $dups"

while IFS="$(printf '\t')" read -r id mode script old fate; do
  [ -n "$fate" ] || fail "$id has five columns"
  case "$mode" in checkout|dist|repo-state|publish|only|build|key) ;; *) fail "$id has a valid mode, got $mode" ;; esac
  [ -f "$here/$script" ] || fail "$id: script $script exists"
  [ -f "$here/explain/$id.md" ] || fail "$id has explain/$id.md"
done < "$reg"

for f in "$here"/explain/*.md; do
  b="$(basename "$f" .md)"
  [ "$b" = README ] && continue
  printf '%s\n' "$ids" | grep -qx "$b" || fail "explain/$b.md names a registered id"
done

for s in "$here"/scripts/check-*.sh "$here"/scripts/assert*.sh; do
  [ "$(basename "$s")" = check-lib.sh ] && continue
  rel="scripts/$(basename "$s")"
  cut -f3 "$reg" | grep -qx "$rel" || fail "$rel is the script of at least one id"
done
infeasible="update-trusted|tests/assert_update_trusted.bats|it verifies a signed pkg against the updater's embedded key, so its failing case is a built, signed pkg that a fixture tree cannot hold
installed-shipyard|tests/assert-installed-shipyard-test.sh|it inspects an installed prefix, which its test assembles in a scratch root"
fx="$here/tests/fixtures/checks"
while IFS="$(printf '\t')" read -r id mode script old fate; do
  [ "$fate" = P1 ] || continue
  if [ "$mode" = key ]; then
    [ ! -d "$fx/$id" ] || fail "$id is a deviation key, which no check runs, so it has no fixtures"
    continue
  fi
  set -- "$fx/$id"/fail*
  if [ -d "$1" ]; then
    printf '%s\n' "$infeasible" | cut -d'|' -f1 | grep -qx "$id" && fail "$id has a fail fixture, so it is not infeasible: drop it from the list"
    set -- "$fx/$id"/pass*
    [ -d "$1" ] || fail "$id (fate P1) has a fail fixture but no tests/fixtures/checks/$id/pass* fixture"
    continue
  fi
  row="$(printf '%s\n' "$infeasible" | grep "^$id|" || true)"
  [ -n "$row" ] || fail "$id (fate P1) has no tests/fixtures/checks/$id/fail* fixture, and is not listed as infeasible with a reason"
  t="$(printf '%s\n' "$row" | cut -d'|' -f2)"
  [ -f "$here/$t" ] || fail "$id is listed as infeasible and covered by $t, which does not exist"
  grep -q "$id" "$here/$t" || fail "$id is listed as infeasible and covered by $t, which never names $id"
done < "$reg"
for row in $(printf '%s\n' "$infeasible" | cut -d'|' -f1); do
  cut -f1 "$reg" | grep -qx "$row" || fail "the infeasible list names $row, which is not a registered id"
done
section_lines() {
  awk -v h="## $2" '
    $0 == h { on = 1; next }
    /^## / { on = 0 }
    on && NF { n++ }
    END { print n + 0 }
  ' "$1"
}
section_text() {
  awk -v h="## $2" '
    $0 == h { on = 1; next }
    /^## / { on = 0 }
    on
  ' "$1"
}
while IFS="$(printf '\t')" read -r id mode script old fate; do
  f="$here/explain/$id.md"
  if [ "$fate" != P1 ]; then
    [ "$(grep -c '' "$f")" -eq 1 ] || fail "$id (fate $fate) is a one-line stub"
    grep -q "^Retired by $fate" "$f" || fail "$id (fate $fate) says 'Retired by $fate' and nothing else"
    continue
  fi
  [ "$(grep -c '' "$f")" -gt 8 ] || fail "$id (fate P1) is more than a stub: only a retired id may be one line"
  head -n 1 "$f" | grep -q "^$id: " || fail "$id: explain/$id.md opens with the id and its rule, as '$id: <the rule>.'"
  grep -q '```' "$f" && fail "$id: explanations are prose, with no code fences"
  prev=0
  for h in Why Incident Limits Deviating; do
    [ "$(grep -cx "## $h" "$f")" -eq 1 ] || fail "$id: explain/$id.md has exactly one '## $h' heading"
    ln="$(grep -nx "## $h" "$f" | cut -d: -f1)"
    [ "$ln" -gt "$prev" ] || fail "$id: the headings come in the order Why, Incident, Limits, Deviating"
    prev="$ln"
    [ "$(section_lines "$f" "$h")" -gt 0 ] || fail "$id: '## $h' is not empty"
  done
  section_text "$f" Incident | grep -Eiq 'None recorded\.|[0-9]{4}-[0-9]{2}-[0-9]{2}|undated' \
    || fail "$id: '## Incident' names a dated event, says it is undated, or says 'None recorded.'"
  section_text "$f" Deviating | grep -Eq "No deviation|- $id[:\"]|- $id\$|deviations/$id/" \
    || fail "$id: '## Deviating' names deviations/$id/ (or the old '- $id:' line), or says 'No deviation is read'"
  last="$(awk 'NF { l = $0 } END { print l }' "$f")"
  case "$old" in
    new*|"deviation key"*)
      printf '%s\n' "$last" | grep -q '^New in the flag day' \
        || fail "$id: the last line starts 'New in the flag day', got: $last" ;;
    "gate "*)
      key="$(printf '%s' "$old" | sed 's/^gate \([0-9][0-9a-z]*\).*/\1/')"
      printf '%s\n' "$last" | grep -Eq "^Formerly gate checks? (.*[^0-9a-z])?$key([^0-9a-z]|\$)" \
        || fail "$id: the last line starts 'Formerly gate check $key', got: $last" ;;
    *)
      key="${old##* }"
      printf '%s\n' "$last" | grep -q '^Formerly ' && printf '%s\n' "$last" | grep -qF -- "$key" \
        || fail "$id: the last line starts 'Formerly' and names $key, got: $last" ;;
  esac
done < "$reg"
echo "PASS check-registry"
