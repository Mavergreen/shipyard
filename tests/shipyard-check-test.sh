#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
lib="$here/scripts/check-lib.sh"
SHIPYARD_CHECK_DIR="$here/scripts"; export SHIPYARD_CHECK_DIR
sc="$here/scripts/shipyard-check"
fail() { echo "FAIL $1"; exit 1; }
t="$(mktemp -d "${TMPDIR:-/tmp}/shipyard-check-test.XXXXXX")"
trap 'rm -rf "$t"' EXIT

out="$(sh -c '. "$1"; chk_fail tests-run-in-ci "CI never runs the tests" "the suite can rot unseen" "add a run-repo-tests step"; exit "$chk_status"' sh "$lib" 2>&1 >/dev/null)" && fail "chk_fail sets a non-zero status"
[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 3 ] || fail "chk_fail prints three lines: $out"
printf '%s\n' "$out" | sed -n 1p | grep -Eq '^[a-z0-9-]+: .+\. .+\.$' || fail "first line shape: $out"
printf '%s\n' "$out" | sed -n 2p | grep -q '^  fix: ' || fail "second line is fix: $out"
[ "$(printf '%s\n' "$out" | sed -n 3p)" = "  more: shipyard-check --explain tests-run-in-ci" ] || fail "third line: $out"

rc=0; sh -c '. "$1"; chk_fail no-such-id a b c' sh "$lib" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "unregistered id exits 2, got $rc"

list="$(sh "$sc" --list)"
for id in $(cut -f1 "$here/scripts/check-ids.tsv"); do
  printf '%s\n' "$list" | grep -q "^$id	" || fail "--list prints $id"
done

[ "$(sh "$sc" --explain tests-run-in-ci)" = "$(cat "$here/explain/tests-run-in-ci.md")" ] || fail "--explain prints the file"

rc=0; sh "$sc" --only no-such-id >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "--only of an unknown id exits 2, got $rc"
rc=0; sh "$sc" --bogus >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "usage error exits 2, got $rc"

rc=0; SHIPYARD_CHECK_REGISTRY=/dev/null sh "$sc" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "a mode with zero ids exits 2, got $rc"

mkdir "$t/nogit"; printf 'a.txt\nb.txt\n' > "$t/files"
got="$(cd "$t/nogit" && SHIPYARD_CHECK_FILES="$t/files" sh -c '. "$1"; chk_tracked_files' sh "$lib")"
[ "$got" = "a.txt
b.txt" ] || fail "SHIPYARD_CHECK_FILES overrides git, got: $got"
rc=0; (cd "$t/nogit" && GIT_CEILING_DIRECTORIES="$t" sh -c '. "$1"; chk_tracked_files' sh "$lib") >/dev/null 2>"$t/err" || rc=$?
[ "$rc" != 0 ] && grep -q '^tracked-files: ' "$t/err" || fail "no git and no list fails tracked-files"

mkdir "$t/stubs"; cp "$here/scripts/check-lib.sh" "$t/stubs/"
printf 'ok-a\tcheckout\tscripts/ok.sh\t1\tP1\nok-b\tcheckout\tscripts/ok.sh\t2\tP1\nbad\tcheckout\tscripts/bad.sh\t3\tP1\ndst\tdist\tscripts/ok.sh\t4\tP1\n' > "$t/reg"
mkdir "$t/scripts"; printf '. "$SHIPYARD_CHECK_DIR/check-lib.sh"\nfor i in ok-a ok-b dst; do chk_ran "$i"; done\n' > "$t/scripts/ok.sh"; printf 'echo oops >&2\nexit 1\n' > "$t/scripts/bad.sh"
rc=0; SHIPYARD_CHECK_REGISTRY="$t/reg" SHIPYARD_CHECK_ROOT="$t" sh "$sc" >"$t/out" 2>/dev/null || rc=$?
[ "$rc" = 1 ] || fail "a failing script exits 1, got $rc"
last="$(tail -1 "$t/out")"
[ "$last" = "shipyard-check: 3 checks, 1 failed" ] || fail "count line, got: $last"
last="$(SHIPYARD_CHECK_REGISTRY="$t/reg" SHIPYARD_CHECK_ROOT="$t" sh "$sc" --only ok-a)" || fail "--only ok-a passes"
[ "$last" = "shipyard-check: 1 checks, 0 failed" ] || fail "--only count, got: $last"
last="$(SHIPYARD_CHECK_REGISTRY="$t/reg" SHIPYARD_CHECK_ROOT="$t" sh "$sc" --only ok-a --only dst)" || fail "--only runs any mode"
[ "$last" = "shipyard-check: 2 checks, 0 failed" ] || fail "--only both, got: $last"
printf 'nr\tcheckout\tscripts/nr.sh\t5\tP1\n' >> "$t/reg"
printf '. "$SHIPYARD_CHECK_DIR/check-lib.sh"\nchk_notrun nr "no input"\nexit 0\n' > "$t/scripts/nr.sh"
last="$(SHIPYARD_CHECK_REGISTRY="$t/reg" SHIPYARD_CHECK_ROOT="$t" sh "$sc" --only ok-a --only nr | tail -n 2 | tr '\n' '|')"
[ "$last" = "nr: not run: no input|shipyard-check: 1 checks, 0 failed, 1 not run|" ] || fail "a check that did not run is said so and not counted, got: $last"
printf 'quiet\tcheckout\tscripts/quiet.sh\t6\tP1\nk\tkey\tscripts/ok.sh\t7\tP1\n' >> "$t/reg"
printf '. "$SHIPYARD_CHECK_DIR/check-lib.sh"\nexit 0\n' > "$t/scripts/quiet.sh"
rc=0; SHIPYARD_CHECK_REGISTRY="$t/reg" SHIPYARD_CHECK_ROOT="$t" sh "$sc" --only ok-a quiet >"$t/out" 2>"$t/err" || rc=$?
[ "$rc" = 1 ] || fail "a check its script never reports fails, got exit $rc"
grep -q '^quiet: did not report\. scripts/quiet\.sh exited 0' "$t/err" || fail "the unreported check is named: $(cat "$t/err")"
[ "$(tail -n 1 "$t/out")" = "shipyard-check: 2 checks, 1 failed" ] || fail "an unreported check counts as a failure, got: $(tail -n 1 "$t/out")"
rc=0; SHIPYARD_CHECK_REGISTRY="$t/reg" SHIPYARD_CHECK_ROOT="$t" sh "$sc" --only k >/dev/null 2>"$t/err" || rc=$?
[ "$rc" = 2 ] && grep -q "deviation key" "$t/err" || fail "--only of a deviation key exits 2, saying so: $rc $(cat "$t/err")"
printf 'a\tcheckout\tscripts/keyed.sh\t1\tP1\nl\tkey\tscripts/keyed.sh\t2\tP5\nd\tdist\tscripts/keyed.sh\t3\tP1\n' > "$t/reg-key"
printf '. "$SHIPYARD_CHECK_DIR/check-lib.sh"\nfor i in a l d; do chk_ran "$i"; done\n' > "$t/scripts/keyed.sh"
last="$(SHIPYARD_CHECK_REGISTRY="$t/reg-key" SHIPYARD_CHECK_ROOT="$t" SHIPYARD_CHECK_VERSION=1 sh "$sc" --dist "$here/tests/fixtures/checks/version/pass/dist" | tail -n 1)" || fail "the keyed --dist run passes"
[ "$last" = "shipyard-check: 2 checks, 0 failed" ] || fail "a --dist run counts checks, never a deviation key, even one its script reports: $last"
mkdir "$t/nogh"; printf '#!/bin/sh\nexit 1\n' > "$t/nogh/gh"; chmod +x "$t/nogh/gh"
for id in repo-auto-merge repo-required-context; do
  rc=0; PATH="$t/nogh:$PATH" sh "$sc" --only "$id" >"$t/out" 2>"$t/err" || rc=$?
  [ "$rc" = 2 ] || fail "--only $id without an admin token exits 2, got $rc"
  grep -q 'needs an admin token' "$t/err" || fail "--only $id names the admin token: $(cat "$t/err")"
done
rc=0; PATH="$t/nogh:$PATH" sh "$sc" --repo-state >"$t/out" 2>"$t/err" || rc=$?
[ "$rc" = 2 ] || fail "--repo-state without an admin token exits 2, got $rc"

for d in "$t/no-such-dir" "$t/empty-dist"; do
  rm -rf "$t/empty-dist"; mkdir "$t/empty-dist"; printf 'notes\n' > "$t/empty-dist/RELEASE_NOTES.md"
  rc=0; SHIPYARD_CHECK_VERSION=1.0-mavericks.1 sh "$sc" --dist "$d" >"$t/out" 2>"$t/err" || rc=$?
  [ "$rc" = 2 ] || fail "--dist $d, which holds no artifact, exits 2, got $rc: $(cat "$t/out")"
  grep -qF -- "$d" "$t/err" || fail "the --dist refusal names $d: $(cat "$t/err")"
done
rc=0; env -u SHIPYARD_CHECK_VERSION sh "$sc" --dist "$t" >"$t/out" 2>"$t/err" || rc=$?
[ "$rc" = 2 ] || fail "--dist without SHIPYARD_CHECK_VERSION exits 2, got $rc"
grep -q 'SHIPYARD_CHECK_VERSION' "$t/err" || fail "the --dist usage error names SHIPYARD_CHECK_VERSION: $(cat "$t/err")"
mkdir "$t/inv"; printf 'chk_here\tcheckout\tscripts/pwd.sh\t1\tP1\n' > "$t/reg-pwd"
printf '. "$SHIPYARD_CHECK_DIR/check-lib.sh"\nchk_ran chk_here\npwd > "%s/pwd.out"\n' "$t" > "$t/scripts/pwd.sh"
(cd "$t/inv" && SHIPYARD_CHECK_REGISTRY="$t/reg-pwd" SHIPYARD_CHECK_ROOT="$t" sh "$sc" >/dev/null) || fail "the pwd stub check passes"
[ "$(cat "$t/pwd.out")" = "$(cd "$t/inv" && pwd)" ] || fail "checks run in the directory shipyard-check was invoked from, got: $(cat "$t/pwd.out")"
echo "PASS shipyard-check"
