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
  case "$mode" in checkout|dist|repo-state|publish|only|build|key|retired) ;; *) fail "$id has a valid mode, got $mode" ;; esac
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
infeasible="update-trusted|tests/assert_update_trusted.bats|it verifies a signature against the family key with ed25519-verify, so its failing case is a signature, which a fixture tree cannot hold
installed-shipyard|tests/assert-installed-shipyard-test.sh|it inspects an installed prefix, which its test assembles in a scratch root
arch-union|tests/lipo-merge-tree-test.sh|it judges two build trees at merge time, which a dist fixture cannot hold
standalone|tests/artifact-conformance-standalone-test.sh|its subject is a product's signed pkg beside an archive cut from the same staged tree, which the test builds with stevedore and stage_standalone.sh rather than checking in
no-standalone|tests/artifact-conformance-standalone-test.sh|it fires only for a product the repo declares whose signed pkg is in the dist, which the test states as facts rather than checking in a built pkg
kext-sig-exception|tests/artifact-conformance-kext-test.sh|its subject is a pkg's kexts and the ids its generated postinstall lists, which the test states as facts and kext-facts-test.sh reads from a pkg built with stevedore
kext-exclude-list|tests/artifact-conformance-kext-test.sh|its subject is a pkg's install scripts, which the test states as facts and kext-facts-test.sh reads from hand-written scripts"
fx="$here/tests/fixtures/checks"
for id in updater sparkle-pristine; do
  awk -F'\t' -v i="$id" '$1 == i && $2 == "retired" { f = 1 } END { exit !f }' "$reg" || fail "$id is retired: no product ships an updater"
done
while IFS="$(printf '\t')" read -r id mode script old fate; do
  if [ "$mode" = retired ]; then
    [ ! -d "$fx/$id" ] || fail "$id is retired, so nothing runs it and it has no fixtures"
    [ "$fate" != P1 ] || fail "$id is retired, so its fate names the phase that retired it, never P1"
    continue
  fi
  case "$fate" in P1|P2|P3|P4|P5) ;; P6) grep -q '^Retired by P6' "$here/explain/$id.md" && continue ;; *) continue ;; esac
  if [ "$mode" = key ]; then
    [ ! -d "$fx/$id" ] || fail "$id is a deviation key, which no check runs, so it has no fixtures"
    continue
  fi
  set -- "$fx/$id"/fail*
  if [ -d "$1" ]; then
    printf '%s\n' "$infeasible" | cut -d'|' -f1 | grep -qx "$id" && fail "$id has a fail fixture, so it is not infeasible: drop it from the list"
    set -- "$fx/$id"/pass*
    [ -d "$1" ] || fail "$id (fate $fate) has a fail fixture but no tests/fixtures/checks/$id/pass* fixture"
    continue
  fi
  row="$(printf '%s\n' "$infeasible" | grep "^$id|" || true)"
  [ -n "$row" ] || fail "$id (fate $fate) has no tests/fixtures/checks/$id/fail* fixture, and is not listed as infeasible with a reason"
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
  if [ "$fate" = later ]; then
    [ "$(grep -c '' "$f")" -eq 1 ] || fail "$id (fate later) is a one-line page"
    grep -Eq '^Not read yet: [^ ]' "$f" || fail "$id (fate later) says 'Not read yet:' and what the key will mean"
    continue
  fi
  if [ "$fate" = P6 ] && [ "$mode" != retired ] && ! grep -q '^Retired by P6' "$f"; then
    :
  elif [ "$mode" = retired ] || { [ "$fate" != P1 ] && [ "$fate" != P2 ] && [ "$fate" != P3 ] && [ "$fate" != P4 ] && [ "$fate" != P5 ]; }; then
    [ "$(grep -c '' "$f")" -eq 1 ] || fail "$id (fate $fate) is a one-line stub"
    grep -q "^Retired by $fate" "$f" || fail "$id (fate $fate) says 'Retired by $fate' and nothing else"
    [ "$mode" != key ] || ! grep -rqE "shipyard_deviat(ed|ion_scopes) $id( |\$|\))" "$here/scripts" \
      || fail "$id is a deviation key a script reads, so its page is more than a stub"
    continue
  fi
  [ "$(grep -c '' "$f")" -gt 8 ] || fail "$id (fate $fate) is more than a stub: only a retired id may be one line"
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
  section_text "$f" Deviating | grep -Eq "No deviation|deviations/$id/" \
    || fail "$id: '## Deviating' names deviations/$id/, or says 'No deviation is read'"
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
kept="MacOSX10.9.sdk
POST_10_9
Requires Mac OS X 10.9.5 or later
mavericks-vm
MAVERICKS_VM_KEY
VoodooInputMavericks.kext
MavericksMultitouch.plugin
build-from-mavericks
on-mavericks"
while IFS="$(printf '\t')" read -r tok repl; do
  [ -n "$tok" ] || fail "scripts/retired-names has no empty token"
  [ -n "$repl" ] || fail "retired token $tok names what replaces it"
  printf '%s\n' "$kept" | while IFS= read -r k; do
    case "$k" in *"$tok"*) echo "FAIL retired token $tok is a substring of the kept name $k, so the denylist would refuse the OS name"; exit 1 ;; esac
  done || exit 1
done < "$here/scripts/retired-names"
echo "PASS check-registry"
