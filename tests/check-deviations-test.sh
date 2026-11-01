#!/bin/sh
# platform: host-agnostic
#   usage: check-deviations-test.sh
#          Runs scripts/check-deviations.sh over tests/fixtures/checks/deviation-*/ and over inline
#          .mavergreen/deviations/ cases: a pass fixture is clean, a fail fixture fails with its own id only.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
S="$here/scripts/check-deviations.sh"
fx="$here/tests/fixtures/checks"
w="$(mktemp -d "${TMPDIR:-/tmp}/check-deviations-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL $1"; exit 1; }

run() {  # $1 = dir holding .mavergreen/deviations/ and FILES; output in $w/out
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

. "$here/tests/lib/deviation_tree.sh"
case_() {  # $1 = name, then deviation's arguments after the root; FILES lists build/a.sh and build/sub/b.sh
  _n="$1"; shift
  mkdir -p "$w/$_n"; printf 'build/a.sh\nbuild/sub/b.sh\n' > "$w/$_n/FILES"
  deviation "$w/$_n" "$@"
}
fails() {  # $1 = name, $2 = id, $3 = text the output must hold
  run "$w/$1" && fail "$1 should fail"
  grep -q "^$2: " "$w/out" || fail "$1 should fail $2: $(cat "$w/out")"
  grep -q -- "$3" "$w/out" || fail "$1 output lacks '$3': $(cat "$w/out")"
  others="$(grep -E '^deviation-[a-z-]+: ' "$w/out" | grep -v "^$2: " || true)"
  [ -z "$others" ] || fail "$1 fails only $2, got: $others"
}

case_ unknown no-such-check x '*' because
fails unknown deviation-complete 'shipyard-check --list'
case_ key host linux linux 'no bash 3.2 here'
run "$w/key" || fail "a key id is a known check: $(cat "$w/out")"

for pair in 'product-layout:stage-product' 'artifact-conformance:artifact-checks-wired' \
            'scheme:version-scheme' 'ingredients:variant-build-info'; do
  case_ "r-${pair%%:*}" "${pair%%:*}" x '*' because
  fails "r-${pair%%:*}" deviation-known-check "now \`${pair#*:}\`"
done
for k in msc-template sparkle-updater release-assets python3; do
  case_ "r-$k" "$k" x '*' because
  fails "r-$k" deviation-known-check 'delete the directory'
done

case_ noreason rosetta x 'build/*.sh' ''
fails noreason deviation-complete 'no reason'
case_ emptyscope rosetta x '' 'no scope given'
fails emptyscope deviation-complete 'empty scope'
case_ norevisit rosetta x 'build/*.sh' because ''
fails norevisit deviation-complete 'no revisit'
case_ line2 rosetta x 'build/*.sh' because
printf 'build/*.sh\nbuild/sub/*.sh\n' > "$w/line2/.mavergreen/deviations/rosetta/x/scope"
fails line2 deviation-complete 'second line'
case_ badlabel rosetta Bad_Label 'build/*.sh' because
fails badlabel deviation-complete 'label'

case_ nomatch rosetta x 'build/zzz.sh' because
fails nomatch deviation-scope-matches 'matches no tracked file'
case_ spans rosetta x 'build/*b.sh' because
printf 'build/sub/b.sh\n' > "$w/spans/FILES"
run "$w/spans" || fail "* spans / as in deviation-reason.sh: $(cat "$w/out")"
case_ repowide rosetta x '*' because
run "$w/repowide" || fail "a repo-wide entry always matches: $(cat "$w/out")"
case_ commentsglob comments x 'build/*.sh' because
run "$w/commentsglob" || fail "a comments deviation may be scoped like any other: $(cat "$w/out")"
case_ commentsnomatch comments x 'vendor/*' because
fails commentsnomatch deviation-scope-matches 'vendor/\*'
case_ commentsrepo comments x '*' because
run "$w/commentsrepo" || fail "a repo-wide comments deviation passes: $(cat "$w/out")"
case_ distscope enclosure-url x 'appcast.xml' 'the tag carries a v'
run "$w/distscope" || fail "a dist id's glob names an artifact member, not a tracked file: $(cat "$w/out")"
case_ spaced rosetta x 'build/my tool.sh' because
printf 'build/my tool.sh\n' >> "$w/spaced/FILES"
run "$w/spaced" || fail "a scope with a space matches the path with that space: $(cat "$w/out")"
case_ spacedmiss rosetta x 'build/my tool.sh' because
printf 'build/myXtool.sh\n' >> "$w/spacedmiss/FILES"
fails spacedmiss deviation-scope-matches '"build/my tool.sh"'

mkdir "$w/none"; : > "$w/none/FILES"
run "$w/none" || fail "no .mavergreen/ is clean"
mkdir "$w/old"; : > "$w/old/FILES"
printf '# x\n\n## Conformance deviations\n\n- no-such-check: because\n' > "$w/old/INGREDIENTS.md"
run "$w/old" || fail "INGREDIENTS.md's ## Conformance deviations is not read: $(cat "$w/out")"
echo "PASS check-deviations"
