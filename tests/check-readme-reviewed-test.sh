#!/bin/sh
# platform: host-agnostic
# spec: scripts/check-readme-reviewed.sh -- the first release is gated on a README with the generated marker line removed
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/check-readme-reviewed.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/check-readme-reviewed-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL $1"; exit 1; }

printf '# thing\n\nIt does a thing.\n' > "$w/good.md"
sh "$S" "$w/good.md" >/dev/null 2>&1 || fail "a README without the marker should pass"

printf '# thing\n\nThis README has not been read or edited by a human.\n' > "$w/marked.md"
rc=0; sh "$S" "$w/marked.md" >/dev/null 2> "$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "a README with the marker should exit 1, got $rc"
[ "$(sed -n 1p "$w/err" | cut -d: -f1)" = readme-reviewed ] || fail "the marker failure should open with its id: $(cat "$w/err")"
grep -q 'unreviewed marker' "$w/err" || fail "it should say the marker is still there: $(cat "$w/err")"

rc=0; sh "$S" "$w/none.md" >/dev/null 2> "$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "a missing README should exit 1, got $rc"
[ "$(sed -n 1p "$w/err" | cut -d: -f1)" = readme-reviewed ] || fail "the missing-README failure should open with its id: $(cat "$w/err")"

SHIPYARD_CHECK_RUNLOG="$w/ran" sh "$S" "$w/good.md" >/dev/null 2>&1
grep -qx readme-reviewed "$w/ran" || fail "it should record that readme-reviewed ran"
echo "PASS check-readme-reviewed"
