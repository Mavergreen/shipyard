#!/bin/sh
# platform: host-agnostic
#   usage: local-backfill-policy-test.sh
#          check-local-backfills.sh decides whether scanned candidates may ship: every candidate
#          classified, every inventory row matched, every local-backfill excepted by a scoped
#          INGREDIENTS.md deviation with labeled fields, and only the trusted identity
#          Mavergreen/recaulk exempt from owning backfills.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
C="$here/../scripts/check-local-backfills.sh"
D="$here/../scripts/local-backfill-deviations.sh"
FX="$here/fixtures/local-backfills"
w="$(mktemp -d "${TMPDIR:-/tmp}/lbp-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
unset MAVERGREEN_SOURCE_FILES MAVERGREEN_CHECK_REPOSITORY GITHUB_REPOSITORY GIT_DIR GIT_WORK_TREE 2>/dev/null || true

[ -f "$C" ] || { echo "FAIL: $C does not exist"; exit 1; }
[ -f "$D" ] || { echo "FAIL: $D does not exist"; exit 1; }

T="$w/t"
tree() {
  rm -rf "$T"; cp -R "$FX/$1/repo" "$T"
}
inventory() { printf 'path\tkind\tsymbols\treason\n' > "$T/compatibility-inventory.tsv"; printf '%b' "$1" >> "$T/compatibility-inventory.tsv"; }
deviations() { printf '# t\n\n## Conformance deviations\n\n%s\n' "$1" > "$T/INGREDIENTS.md"; }
list() { (cd "$T" && find . -type f | sed 's|^\./||' | LC_ALL=C sort) > "$w/files"; }
run() {
  list; rc=0
  MAVERGREEN_SOURCE_FILES="$w/files" sh "$C" "$@" "$T" > "$w/out" 2>"$w/err" || rc=$?
}
run_as() {
  id="$1"; shift; list; rc=0
  MAVERGREEN_CHECK_REPOSITORY="$id" MAVERGREEN_SOURCE_FILES="$w/files" sh "$C" "$@" "$T" > "$w/out" 2>"$w/err" || rc=$?
}
expect() {
  want="$1"; label="$2"
  [ "$rc" -eq "$want" ] || { echo "FAIL: $label: expected exit $want, got $rc"; echo "-- stdout"; cat "$w/out"; echo "-- stderr"; cat "$w/err"; exit 1; }
}
says() {
  grep -q -- "$1" "$w/out" || { echo "FAIL: $2: stdout must contain \"$1\"; got:"; cat "$w/out"; cat "$w/err"; exit 1; }
}

LB='src/time_backport.c\tlocal-backfill\tclock_gettime,clock_getres\tour clock for 10.9; Recaulk has no CLOCK_UPTIME_RAW_APPROX yet\n'
GOOD='- local-backfill:src/time_backport.c: CLOCK_UPTIME_RAW_APPROX semantics this product alone needs; symbols=clock_gettime,clock_getres; decision=maintainer accepted a product-specific copy; evidence=https://github.com/Mavergreen/example/pull/7; revisit=when Recaulk supports CLOCK_UPTIME_RAW_APPROX'

tree external-definition; run
expect 1 "an unclassified candidate"
says 'local-backfill: src/time_backport.c:4: ' "an unclassified candidate names its path and line"
says 'compatibility-inventory.tsv' "an unclassified candidate says where to classify it"

tree external-definition; inventory "$LB"; run
expect 1 "a local-backfill classification with no exception"
says 'src/time_backport.c:4: ' "an unexcepted local-backfill names the candidate"
says 'clock_gettime' "an unexcepted local-backfill names the symbol"
says 'Recaulk' "an unexcepted local-backfill says where the code belongs"
run --report
expect 0 "--report never blocks on policy findings"
says 'src/time_backport.c:4: ' "--report prints the finding it does not block on"

tree external-definition; inventory "$LB"; deviations "$GOOD"; run
expect 0 "a narrow, complete exception"
for v in Mavergreen/clang mavergreen/recaulk Mavergreen/recaulk-fork ''; do
  run_as "$v"; expect 0 "a valid exception under identity '$v'"
done

tree external-definition; inventory 'src/time_backport.c\tlocal-backfill\tclock_gettime\tours\n'
deviations "$(printf '%s' "$GOOD" | sed 's/symbols=clock_gettime,clock_getres/symbols=clock_gettime/')"; run
expect 1 "a candidate symbol nobody classified, beside an excepted one"
says 'src/time_backport.c:17: ' "the unclassified clock_getres is named"

bad_exception() {
  label="$1"; entry="$2"; needle="$3"
  tree external-definition; inventory "$LB"; deviations "$entry"; run
  expect 1 "$label"
  says "$needle" "$label"
  run --report; expect 0 "$label (--report)"
}
bad_exception "a missing revisit=" "$(printf '%s' "$GOOD" | sed 's/; revisit=.*//')" 'no revisit= field'
bad_exception "a blank revisit=" "$(printf '%s' "$GOOD" | sed 's/revisit=.*/revisit= /')" 'revisit='
bad_exception "a missing symbols=" "$(printf '%s' "$GOOD" | sed 's/ symbols=[^;]*;//')" 'no symbols= field'
bad_exception "a missing evidence=" "$(printf '%s' "$GOOD" | sed 's/ evidence=[^;]*;//')" 'no evidence= field'
bad_exception "a missing decision=" "$(printf '%s' "$GOOD" | sed 's/ decision=[^;]*;//')" 'no decision= field'
bad_exception "no concrete reason" "$(printf '%s' "$GOOD" | sed 's/: CLOCK[^;]*;/:/')" 'concrete reason'
bad_exception "a self-asserted approved=true" "$(printf '%s' "$GOOD" | sed 's/$/; approved=true/')" 'self-asserted'
bad_exception "an unknown label" "$(printf '%s' "$GOOD" | sed 's/$/; owner=me/')" 'unknown label'
bad_exception "a label given twice" "$(printf '%s' "$GOOD" | sed 's/$/; revisit=never/')" 'more than once'
bad_exception "a wildcard scope" "$(printf '%s' "$GOOD" | sed 's|src/time_backport.c:|src/*.c:|')" 'wildcard'
bad_exception "a bare exemption" '- local-backfill: we need it; symbols=clock_gettime; decision=yes; evidence=a PR; revisit=later' 'bare'
bad_exception "an unmatched scope" "$(printf '%s' "$GOOD" | sed 's|src/time_backport.c:|src/other.c:|')" 'src/other.c'
bad_exception "a symbol the classification does not name" "$(printf '%s' "$GOOD" | sed 's/symbols=clock_gettime,clock_getres/symbols=clock_gettime,clock_getres,mkostemp/')" 'mkostemp'
bad_exception "a wildcard symbol" "$(printf '%s' "$GOOD" | sed 's/symbols=clock_gettime,clock_getres/symbols=clock_*/')" 'is not a name'
bad_exception "an exception that does not cover a classified symbol" "$(printf '%s' "$GOOD" | sed 's/symbols=clock_gettime,clock_getres/symbols=clock_gettime/')" 'src/time_backport.c:17: '
bad_exception "a Recaulk-already-provides-it excuse" "$(printf '%s' "$GOOD" | sed 's/: CLOCK[^;]*;/: Recaulk already provides clock_gettime;/')" 'Recaulk already provides'
bad_exception "two exceptions for one file" "$(printf '%s\n%s' "$GOOD" "$GOOD")" 'more than one'

tree external-definition; inventory "$LB"; printf '# t\n\n## Conformance deviations\n\n- local-backfill:src/time_backport.c:\n' > "$T/INGREDIENTS.md"
run; expect 2 "an exception record the common parser refuses"
run --report; expect 2 "an exception record the common parser refuses (--report)"

tree external-definition; inventory "$LB"
printf '# t\n\n## Conformance deviations\n\n- sdk-pin:*/lib/libfoo.dylib: prebuilt upstream\n- comments: legacy\n%s\n' "$GOOD" > "$T/INGREDIENTS.md"
run; expect 0 "deviations for other rules sit beside a local-backfill exception untouched"

tree test-double; printf 'path\tkind\tsymbols\treason\ntests/fakes/fake_clock.c\tpolyfill\tclock_gettime\tx\n' > "$T/compatibility-inventory.tsv"
run; expect 2 "a malformed inventory"
run --report; expect 2 "a malformed inventory (--report)"
run_as Mavergreen/recaulk; expect 2 "a malformed inventory, even for Recaulk"

rc=0; sh "$C" "$w/no-such-repo" > /dev/null 2>&1 || rc=$?; expect 2 "a missing REPO"
rc=0; sh "$C" > /dev/null 2>&1 || rc=$?; expect 2 "no REPO"
rc=0; sh "$C" --strict-ish "$T" > /dev/null 2>&1 || rc=$?; expect 2 "an unknown option"

tree test-double; run; expect 0 "a test-only classification"
tree command-wrapper; run; expect 0 "a symbol-less product-adaptation classification"
tree declaration-only; run; expect 0 "a classified header of declarations"

tree test-double; inventory 'tests/fakes/fake_clock.c\ttest-only\tclock_gettime,clock_getres\ta fake\n'; run
expect 1 "an inventory symbol that matches no candidate"
says 'clock_getres' "an unmatched inventory symbol is named"
tree external-definition; inventory "$LB"'src/time_backport.c\tproduct-adaptation\t-\tthe file is a shim\n'; deviations "$GOOD"; run
expect 1 "a symbol-less row on a file with no symbol-less candidate"
says 'matches no candidate' "a symbol-less unmatched row"

tree pinned-upstream; inventory 'vendor/libfoo/src/time.c\tupstream\tclock_gettime\tlibfoo 1.2.3 at the commit pinned in components/libfoo/version, unmodified\npatches/libfoo-time.patch\tupstream\tclock_getres\tlibfoo upstream\n'; run
expect 1 "an upstream classification of a local patch"
says 'patches/libfoo-time.patch' "an upstream patch row is named"
says 'local modification' "an upstream patch row says why it cannot be upstream"
tree pkgsrc-patch; inventory 'patches/patch-aa\tupstream\taligned_alloc\tpkgsrc patch pinned at 2026Q3, unmodified\npatches/patch-src_time.c\tupstream\tclock_gettime\tpkgsrc patch pinned at 2026Q3, unmodified\n'; run
expect 1 "an upstream classification of a patch recognised by its content"
says 'patches/patch-aa' "a content-detected patch row is named"

tree pinned-upstream; inventory 'vendor/libfoo/src/time.c\tupstream\tclock_gettime\tfrom libfoo\npatches/libfoo-time.patch\tlocal-backfill\tclock_getres\tours\n'; run
expect 1 "an upstream classification that cites no pin and unchanged origin"
says 'vendor/libfoo/src/time.c' "an uncited upstream row is named"
says 'pin' "an uncited upstream row says to cite the pin"
inventory 'vendor/libfoo/src/time.c\tupstream\tclock_gettime\tlibfoo 1.2.3, unmodified\npatches/libfoo-time.patch\tlocal-backfill\tclock_getres\tours\n'; run
says 'vendor/libfoo/src/time.c: an upstream row' "an upstream row that says unmodified but names no pin"
inventory 'vendor/libfoo/src/time.c\tupstream\tclock_gettime\tlibfoo 1.2.3 at the commit pinned in components/libfoo/version\npatches/libfoo-time.patch\tlocal-backfill\tclock_getres\tours\n'; run
says 'vendor/libfoo/src/time.c: an upstream row' "an upstream row that names the pin but not that the source is unmodified"

tree external-definition; mkdir -p "$w/recaulk"; rm -rf "$w/recaulk/t"; mv "$T" "$w/recaulk/t"; T="$w/recaulk/t"
inventory "$LB"; printf 'Mavergreen/recaulk\n' > "$T/REPOSITORY"
run; expect 1 "a directory named recaulk, no trusted identity"
run_as Mavergreen/clang; expect 1 "a directory named recaulk under another trusted identity"
list; rc=0; GITHUB_REPOSITORY=Mavergreen/recaulk MAVERGREEN_SOURCE_FILES="$w/files" sh "$C" "$T" > "$w/out" 2>"$w/err" || rc=$?; expect 1 "GITHUB_REPOSITORY is not the trusted input"
run_as mavergreen/recaulk; expect 1 "the identity is exact, case included"
run_as Mavergreen/recaulk; expect 0 "canonical Recaulk owns its backfills"
rm "$T/compatibility-inventory.tsv"
run_as Mavergreen/recaulk; expect 0 "canonical Recaulk needs no classification of its own backfills"
inventory 'src/time_backport.c\tlocal-backfill\tclock_gettime,mkostemp\tours\n'
run_as Mavergreen/recaulk; expect 1 "canonical Recaulk still fails an unmatched inventory row"
inventory "$LB"; deviations "$(printf '%s' "$GOOD" | sed 's/; revisit=.*//')"
run_as Mavergreen/recaulk; expect 1 "canonical Recaulk still fails an invalid exception"
T="$w/t"

echo "rule: source-only -- linking librecaulk.a and calling what it backfills is never a finding"
rm -rf "$T"; mkdir -p "$T/src" "$T/lib"
printf '#include <time.h>\nint now(struct timespec *t) { return clock_gettime(CLOCK_MONOTONIC, t); }\n' > "$T/src/now.c"
printf 'add_executable(now src/now.c)\ntarget_link_libraries(now PRIVATE recaulk)\n' > "$T/CMakeLists.txt"
printf '!<arch>\n_clock_gettime\n_aligned_alloc\n' > "$T/lib/librecaulk.a"
run; expect 0 "a product that links librecaulk.a statically and calls its backfills"
[ ! -s "$w/out" ] || { echo "FAIL: a Recaulk-linked product must yield no findings; got:"; cat "$w/out"; exit 1; }

tree external-definition; inventory "$LB"; deviations "$GOOD"; list
rc=0; MAVERGREEN_SOURCE_FILES="$w/files" sh "$D" "$T" > "$w/dout" 2>"$w/derr" || rc=$?
expect 0 "the deviation helper on a valid exception"
printf 'exception\tsrc/time_backport.c\tclock_gettime,clock_getres\n' > "$w/want"
cut -f1-3 "$w/dout" | diff "$w/want" - > /dev/null || { echo "FAIL: the helper prints one exception record per valid entry; got:"; cat "$w/dout"; exit 1; }
deviations "$(printf '%s' "$GOOD" | sed 's/; revisit=.*//')"
rc=0; sh "$D" "$T" > "$w/dout" 2>&1 || rc=$?
expect 1 "the deviation helper on an invalid exception"
deviations "$(printf '%s' "$GOOD" | sed 's/$/; approved=true/')"
rc=0; sh "$D" "$T" > "$w/dout" 2>&1 || rc=$?
expect 1 "the deviation helper on a self-asserted approval"
if grep -q '^exception' "$w/dout"; then echo "FAIL: an entry with an unknown label must yield no exception record; got:"; cat "$w/dout"; exit 1; fi

echo "PASS: local-backfill-policy"
