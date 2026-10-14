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
  case "$mode" in checkout|dist|repo-state|publish|only|build) ;; *) fail "$id has a valid mode, got $mode" ;; esac
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
installed-shipyard|tests/assert-installed-shipyard-test.sh|it inspects an installed prefix, which its test assembles in a scratch root
host|tests/check-bash32-parse-test.sh|it is a deviation key, not a check: it excuses bash32-parse on a host, and that test declares and withdraws it"
fx="$here/tests/fixtures/checks"
while IFS="$(printf '\t')" read -r id mode script old fate; do
  [ "$fate" = P1 ] || continue
  set -- "$fx/$id"/fail*
  if [ -d "$1" ]; then
    printf '%s\n' "$infeasible" | cut -d'|' -f1 | grep -qx "$id" && fail "$id has a fail fixture, so it is not infeasible: drop it from the list"
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
echo "PASS check-registry"
