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
echo "PASS check-registry"
