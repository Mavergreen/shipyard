#!/bin/sh
# platform: host-agnostic
#   usage: local-backfill-scan-test.sh
#          scan-local-backfills.sh finds CANDIDATE family-authored OS/API backfills and validates
#          compatibility-inventory.tsv; it proves nothing about what it does not find. Each fixture
#          under tests/fixtures/local-backfills/<name>/ is a product tree (repo/) and the exact
#          findings it must yield (expected.tsv).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/scan-local-backfills.sh"
FX="$here/fixtures/local-backfills"
TAB="$(printf '\t')"
w="$(mktemp -d "${TMPDIR:-/tmp}/lbs-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
unset MAVERGREEN_SOURCE_FILES GIT_DIR GIT_WORK_TREE 2>/dev/null || true

[ -f "$S" ] || { echo "FAIL: $S does not exist"; exit 1; }

prep() {
  rm -rf "$w/$1"; cp -R "$FX/$1/repo" "$w/$1"
  (cd "$w/$1" && find . -type f | sed 's|^\./||' | LC_ALL=C sort) > "$w/$1.files"
}
scan() { MAVERGREEN_SOURCE_FILES="$w/$1.files" sh "$S" "$w/$1"; }

for name in external-definition static-inline patch-addition shell-heredoc macro-wrapper \
            disabled-fallback declaration-only command-wrapper test-double pinned-upstream renamed-helper \
            pkgsrc-patch edited-upstream; do
  prep "$name"
  rc=0; out="$(scan "$name" 2>"$w/err")" || rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: $name: a completed scan exits 0, findings or not; got $rc:"; cat "$w/err"; exit 1; }
  printf '%s\n' "$out" | sed '/^$/d' > "$w/got"
  diff "$FX/$name/expected.tsv" "$w/got" > "$w/diff" || {
    echo "FAIL: $name: findings differ from $FX/$name/expected.tsv (< expected, > got):"; cat "$w/diff"; exit 1; }
  cp "$w/got" "$w/got.$name"
  grep -q 'not proof' "$w/err" || { echo "FAIL: $name: a completed scan must say on stderr that finding nothing is not proof of absence; got:"; cat "$w/err"; exit 1; }
done

for name in external-definition static-inline patch-addition shell-heredoc macro-wrapper disabled-fallback; do
  cut -f3,4 "$w/got.$name" | grep -v "^declaration$TAB" | grep -v "$TAB-\$" | grep -q . \
    || { echo "FAIL: $name must yield an implementation finding that names its symbol"; exit 1; }
done

if cut -f3 "$w/got.declaration-only" | grep -vx declaration | grep -q .; then
  echo "FAIL: a declaration alone is a candidate to classify, never an implementation finding"; exit 1
fi
prep declaration-only
rows="$(MAVERGREEN_SOURCE_FILES="$w/declaration-only.files" sh "$S" --inventory "$w/declaration-only")" || { echo "FAIL: declaration-only: its inventory must validate"; exit 1; }
[ "$rows" = "include/mg_decls.h${TAB}product-adaptation${TAB}clock_gettime,aligned_alloc,timingsafe_bcmp${TAB}declares APIs Recaulk implements; the header has not reached Recaulk yet" ] \
  || { echo "FAIL: --inventory must print each validated row, header dropped; got: $rows"; exit 1; }

for pair in command-wrapper:product-adaptation test-double:test-only; do
  name="${pair%%:*}"; kind="${pair#*:}"
  prep "$name"
  rows="$(MAVERGREEN_SOURCE_FILES="$w/$name.files" sh "$S" --inventory "$w/$name")" || { echo "FAIL: $name: its inventory must validate"; exit 1; }
  printf '%s\n' "$rows" | cut -f2 | grep -qx "$kind" \
    || { echo "FAIL: $name: an ordinary wrapper or test double is classified $kind, which needs no release exception; got: $rows"; exit 1; }
done

prep pinned-upstream
MAVERGREEN_SOURCE_FILES="$w/pinned-upstream.files" sh "$S" --inventory "$w/pinned-upstream" | cut -f1 > "$w/classified"
uncovered="$(awk -F "$TAB" 'NR == FNR { c[$1] = 1; next } !($1 in c)' "$w/classified" "$w/got.pinned-upstream")"
[ "$uncovered" = "patches/libfoo-time.patch${TAB}11${TAB}patch-definition${TAB}clock_getres${TAB}patch adds a definition of a known Darwin/Recaulk API" ] \
  || { echo "FAIL: a local patch to pinned upstream code must not inherit the upstream row: the patch's finding is the one left unclassified; got: $uncovered"; exit 1; }

echo "limit: an in-place edit to a vendored file classified upstream looks exactly like the unmodified file"
grep "^vendor/libfoo/src/time.c$TAB" "$w/got.pinned-upstream" | diff - "$w/got.edited-upstream" >/dev/null \
  || { echo "FAIL: edited-upstream: the scanner now tells an edited upstream file from the pinned one -- update this detection-limit regression and its expected.tsv"; exit 1; }

prep unknown-classification
rc=0; scan unknown-classification > /dev/null 2>"$w/err" || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: an unsupported kind is a malformed inventory (exit 2); got $rc"; exit 1; }
grep -q polyfill "$w/err" || { echo "FAIL: the refusal must name the unsupported kind; got:"; cat "$w/err"; exit 1; }
rc=0; MAVERGREEN_SOURCE_FILES="$w/unknown-classification.files" sh "$S" --inventory "$w/unknown-classification" > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: --inventory must refuse an unsupported kind too (exit 2); got $rc"; exit 1; }

echo "limit: a backfill under a name the scanner does not know yields no finding; source review decides it and names the symbol in compatibility-inventory.tsv"
prep renamed-helper
[ -z "$(scan renamed-helper 2>/dev/null)" ] || { echo "FAIL: renamed-helper: the scanner now detects an unknown renamed helper by itself -- update this detection-limit regression and its expected.tsv"; exit 1; }
printf 'path\tkind\tsymbols\treason\nsrc/mg_time.c\tlocal-backfill\tmg_monotonic_now\tsource review: a private clock_gettime(CLOCK_MONOTONIC)\n' > "$w/renamed-helper/compatibility-inventory.tsv"
echo compatibility-inventory.tsv >> "$w/renamed-helper.files"
out="$(scan renamed-helper 2>/dev/null)"
[ "$out" = "src/mg_time.c${TAB}4${TAB}definition${TAB}mg_monotonic_now${TAB}defines an inventory-declared symbol" ] \
  || { echo "FAIL: a symbol the inventory names must be detected like a known API; got: $out"; exit 1; }

prep test-double
scan test-double 2>/dev/null | grep -q fake_clock.c || { echo "FAIL: a classified finding must still be reported"; exit 1; }

a="$(scan external-definition 2>/dev/null)"; b="$(scan external-definition 2>/dev/null)"
[ "$a" = "$b" ] || { echo "FAIL: two scans of one tree must print identical bytes"; exit 1; }
LC_ALL=C sort -t "$TAB" -k1,1 -k2,2n -k3,3 -k4,4 "$w/got.disabled-fallback" | diff - "$w/got.disabled-fallback" >/dev/null \
  || { echo "FAIL: findings are sorted by path, then line numerically"; exit 1; }

bad() {
  label="$1"; shift
  rc=0; "$@" > /dev/null 2>"$w/err" || rc=$?
  [ "$rc" -eq 2 ] || { echo "FAIL: $label: must exit 2 (could not scan / malformed inventory); got $rc"; cat "$w/err"; exit 1; }
  [ -s "$w/err" ] || { echo "FAIL: $label: exit 2 must say why on stderr"; exit 1; }
}
inv() {
  prep test-double
  printf '%b' "$1" > "$w/test-double/compatibility-inventory.tsv"
  bad "$2" scan test-double
  bad "$2 (--inventory)" env MAVERGREEN_SOURCE_FILES="$w/test-double.files" sh "$S" --inventory "$w/test-double"
}
H='path\tkind\tsymbols\treason\n'
inv '' "an empty inventory (no header)"
inv 'tests/fakes/fake_clock.c\ttest-only\tclock_gettime\ta fake\n' "an inventory with no header"
inv "${H}"'tests/fakes/fake_clock.c\ttest-only\tclock_gettime\n' "a row with three columns"
inv "${H}"'tests/fakes/fake_clock.c\ttest-only\tclock_gettime\ta fake\textra\n' "a row with five columns"
inv "${H}"'tests/fakes/fake_clock.c\ttest-only\tclock_gettime\t\n' "a row with an empty reason"
inv "${H}"'tests/fakes/fake_clock.c\ttest-only\tclock_gettime\ta fake\r\n' "a CRLF row"
inv "${H}"'../outside.c\ttest-only\t-\ta fake\n' "a traversal path"
inv "${H}"'tests/../tests/fakes/fake_clock.c\ttest-only\t-\ta fake\n' "a path with a .. segment"
inv "${H}"'/etc/passwd\ttest-only\t-\ta fake\n' "an absolute path"
inv "${H}"'./tests/fakes/fake_clock.c\ttest-only\t-\ta fake\n' "a path with a . segment"
inv "${H}"'tests/fakes/*.c\ttest-only\t-\ta fake\n' "a wildcard path"
inv "${H}"'tests/fakes\ttest-only\t-\ta fake\n' "a directory-wide row"
inv "${H}"'tests/fakes/missing.c\ttest-only\t-\ta fake\n' "a row naming a nonexistent file"
inv "${H}"'tests/fakes/fake_clock.c\ttest-only\tclock_gettime\ta fake\ntests/fakes/fake_clock.c\tlocal-backfill\tclock_gettime\tagain\n' "a duplicate row"
inv "${H}"'tests/fakes/fake_clock.c\ttest-only\tclock_*\ta fake\n' "a wildcard symbol"
inv "${H}"'tests/fakes/fake_clock.c\ttest-only\tclock_gettime,,x\ta fake\n' "an empty symbol"
inv "${H}"'tests/fakes/fake_clock.c\tTest-Only\t-\ta fake\n' "a kind in the wrong case"

prep test-double
printf 'untracked.c\n' > "$w/test-double/untracked.c"
printf '%s\n' 'path	kind	symbols	reason' 'untracked.c	test-only	-	not in the source list' > "$w/test-double/compatibility-inventory.tsv"
bad "a row naming a file outside the source list" scan test-double

prep external-definition
bad "no git checkout and no MAVERGREEN_SOURCE_FILES" sh "$S" "$w/external-definition"
bad "MAVERGREEN_SOURCE_FILES naming a missing list" env MAVERGREEN_SOURCE_FILES="$w/nope" sh "$S" "$w/external-definition"
: > "$w/empty.files"
bad "an empty source list" env MAVERGREEN_SOURCE_FILES="$w/empty.files" sh "$S" "$w/external-definition"
printf 'src/time_backport.c\nsrc/gone.c\n' > "$w/gone.files"
bad "a source list naming a missing file" env MAVERGREEN_SOURCE_FILES="$w/gone.files" sh "$S" "$w/external-definition"
printf '../escape.c\n' > "$w/trav.files"
bad "a source list with a traversal path" env MAVERGREEN_SOURCE_FILES="$w/trav.files" sh "$S" "$w/external-definition"
printf '/etc/hosts\n' > "$w/abs.files"
bad "a source list with an absolute path" env MAVERGREEN_SOURCE_FILES="$w/abs.files" sh "$S" "$w/external-definition"
bad "a missing REPO" env MAVERGREEN_SOURCE_FILES="$w/external-definition.files" sh "$S" "$w/no-such-repo"
bad "no REPO argument" sh "$S"

if git --version >/dev/null 2>&1; then
  prep external-definition
  g="$w/external-definition"
  printf 'int clock_gettime(clockid_t c, struct timespec *t) { return 0; }\n' > "$w/untracked-def.c"
  (cd "$g" && git init -q . && git add src && cp "$w/untracked-def.c" src/untracked.c)
  rc=0; out="$(sh "$S" "$g" 2>"$w/err")" || rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: a git checkout scans its tracked files with no list given; got $rc"; cat "$w/err"; exit 1; }
  [ "$out" = "$(cat "$FX/external-definition/expected.tsv")" ] \
    || { echo "FAIL: a git checkout must scan exactly its tracked files (untracked src/untracked.c excluded); got:"; echo "$out"; exit 1; }
  mkdir -p "$w/outer"; (cd "$w/outer" && git init -q . && mkdir sub && cp "$g/src/time_backport.c" sub/ && git add sub)
  bad "a subdirectory of a checkout, with no list" sh "$S" "$w/outer/sub"
else
  echo "note: git does not run here; the git file-list path was not exercised"
fi

echo "PASS: local-backfill-scan"
