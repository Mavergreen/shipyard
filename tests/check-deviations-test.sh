#!/bin/sh
# platform: host-agnostic
#   usage: check-deviations-test.sh
#          Runs scripts/check-deviations.sh over tests/fixtures/checks/deviation-*/ and over inline
#          INGREDIENTS.md cases: a pass fixture is clean, a fail fixture fails with its own id only.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
S="$here/scripts/check-deviations.sh"
fx="$here/tests/fixtures/checks"
w="$(mktemp -d "${TMPDIR:-/tmp}/check-deviations-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL $1"; exit 1; }

run() {  # $1 = dir holding INGREDIENTS.md and FILES; output in $w/out
  (cd "$1" && SHIPYARD_CHECK_FILES="$1/FILES" sh "$S") > "$w/out" 2>&1
}

for id in deviation-complete deviation-known-check deviation-scope-matches; do
  run "$fx/$id/pass" || fail "$id/pass should be clean: $(cat "$w/out")"
  for d in "$fx/$id"/fail*; do
    if run "$d"; then fail "$(basename "$d") should fail"; fi
    grep -q "^$id: " "$w/out" || fail "$(basename "$d") should fail with $id: $(cat "$w/out")"
    others="$(grep -E '^deviation-[a-z-]+: ' "$w/out" | grep -v "^$id: " || true)"
    [ -z "$others" ] || fail "$(basename "$d") fails only $id, got: $others"
    grep -q '^  fix: ' "$w/out" || fail "$(basename "$d") names a fix"
  done
done

case_() {  # $1 = name, $2 = INGREDIENTS.md body under the section header; FILES lists build/a.sh
  mkdir -p "$w/$1"; printf '# x\n\n## Conformance deviations\n\n%s\n' "$2" > "$w/$1/INGREDIENTS.md"
  printf 'build/a.sh\nbuild/sub/b.sh\n' > "$w/$1/FILES"
}
fails() {  # $1 = name, $2 = id, $3 = text the output must hold
  run "$w/$1" && fail "$1 should fail"
  grep -q "^$2: " "$w/out" || fail "$1 should fail $2: $(cat "$w/out")"
  grep -q -- "$3" "$w/out" || fail "$1 output lacks '$3': $(cat "$w/out")"
}

case_ unknown "- no-such-check: because"
fails unknown deviation-known-check 'shipyard-check --list'

for pair in 'product-layout:stage-product' 'artifact-conformance:artifact-checks-wired' \
            'scheme:version-scheme' 'ingredients:variant-build-info'; do
  case_ "r-${pair%%:*}" "- ${pair%%:*}: because"
  fails "r-${pair%%:*}" deviation-known-check "now \`${pair#*:}\`"
done
for k in sparkle-updater release-assets python3; do
  case_ "r-$k" "- $k: because"
  fails "r-$k" deviation-known-check 'delete the line'
done

case_ noreason "- rosetta:build/*.sh:"
fails noreason deviation-complete 'declares no reason'
case_ emptyglob "- rosetta:no reason given"
fails emptyglob deviation-complete 'empty glob'

case_ nomatch "- rosetta:build/zzz.sh: because"
fails nomatch deviation-scope-matches 'matches no tracked file'
case_ spans "- rosetta:build/*.sh: because"
run "$w/spans" || fail "* spans / as in deviation-reason.sh: $(cat "$w/out")"
case_ repowide "- rosetta: because"
run "$w/repowide" || fail "a repo-wide entry always matches: $(cat "$w/out")"
case_ commentsglob "- comments:build/*.sh: because"
fails commentsglob deviation-scope-matches 'drop the glob'
rm -f "$w/commentsglob/comment-reasons"
case_ commentsrepo "- comments: because"
run "$w/commentsrepo" || fail "a repo-wide comments deviation passes: $(cat "$w/out")"
case_ distscope "- enclosure-url:appcast.xml: the tag carries a v"
run "$w/distscope" || fail "a dist id's glob names an artifact member, not a tracked file: $(cat "$w/out")"

mkdir "$w/none"; : > "$w/none/FILES"
run "$w/none" || fail "no INGREDIENTS.md is clean"
echo "PASS check-deviations"
