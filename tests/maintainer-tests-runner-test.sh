#!/bin/sh
# platform: host-agnostic
#   usage: maintainer-tests-runner-test.sh
#          scripts/maintainer-tests.sh BOX runs that box's tests/maintainer-tests lines, and only
#          those, with SHIPYARD_ON_TARGET=1, says PASS, FAIL or SKIP for each, and exits 1 if any
#          failed. Runs against a fixture tree, never the real list.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
w="$(mktemp -d "${TMPDIR:-/tmp}/maintainer-tests.XXXXXX")"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/scripts" "$w/tests"
cp "$root/scripts/maintainer-tests.sh" "$w/scripts/"
printf '#!/bin/sh\n[ "$SHIPYARD_ON_TARGET" = 1 ] || exit 3\necho ran >> "%s/ran.ok"\n' "$w" > "$w/tests/ok-test.sh"
printf '#!/bin/sh\necho SKIP: not here; exit 77\n' > "$w/tests/skip-test.sh"
printf '#!/bin/sh\necho it broke; exit 1\n' > "$w/tests/bad-test.sh"
printf '#!/bin/sh\necho ran >> "%s/ran.other"\n' "$w" > "$w/tests/other-test.sh"
cat > "$w/tests/maintainer-tests" <<'L'
10.9 tests/ok-test.sh
10.9 tests/skip-test.sh
golden-gate tests/other-test.sh
L
bad=0
rc=0; out="$(sh "$w/scripts/maintainer-tests.sh" 10.9 2>&1)" || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: a box whose tests pass or skip must exit 0, got $rc:"; printf '%s\n' "$out" | sed 's/^/    | /'; bad=1; }
printf '%s\n' "$out" | grep -qx 'PASS tests/ok-test.sh' || { echo "FAIL: no PASS line for ok-test.sh"; bad=1; }
printf '%s\n' "$out" | grep -q '^SKIP tests/skip-test.sh' || { echo "FAIL: no SKIP line for skip-test.sh"; bad=1; }
[ -f "$w/ran.ok" ] || { echo "FAIL: ok-test.sh did not run with SHIPYARD_ON_TARGET=1"; bad=1; }
[ ! -f "$w/ran.other" ] || { echo "FAIL: golden-gate's test ran for box 10.9"; bad=1; }
echo "golden-gate tests/bad-test.sh" >> "$w/tests/maintainer-tests"
rc=0; out="$(sh "$w/scripts/maintainer-tests.sh" golden-gate 2>&1)" || rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL: a failing test must exit 1, got $rc"; bad=1; }
printf '%s\n' "$out" | grep -q '^FAIL tests/bad-test.sh' || { echo "FAIL: no FAIL line for bad-test.sh:"; printf '%s\n' "$out" | sed 's/^/    | /'; bad=1; }
printf '%s\n' "$out" | grep -q 'it broke' || { echo "FAIL: a failed test's output must be shown"; bad=1; }
rc=0; sh "$w/scripts/maintainer-tests.sh" no-such-box > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: a box with no lines must be a usage error (2), got $rc"; bad=1; }
rc=0; sh "$w/scripts/maintainer-tests.sh" > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: no box must be a usage error (2), got $rc"; bad=1; }
[ "$bad" -eq 0 ] || exit 1
echo "PASS: maintainer-tests-runner"
