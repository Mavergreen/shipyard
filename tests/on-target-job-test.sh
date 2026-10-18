#!/bin/sh
# platform: host-agnostic
#   usage: on-target-job-test.sh
#          ci.yml carries an on-target job that runs the fixtures in the 10.9 guest, with python-315's
#          latest release, verified against its SHA256SUMS, installed there for the checks that need
#          python3. Linux and macOS run the same runner, so the fixture count can be compared across hosts.
# spec: .github/workflows/ci.yml on-target -- the flag-day P1 ruling R5, on since python-315 phase 1 shipped
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
ci="$here/.github/workflows/ci.yml"
fail() { echo "FAIL $1"; exit 1; }

job="$(awk '/^  on-target:/ { on = 1; print; next } on && /^  [a-z]/ { exit } on' "$ci")"
[ -n "$job" ] || fail "ci.yml has an on-target job"
printf '%s\n' "$job" | grep -q '^    if:' && fail "on-target runs: python-315 phase 1 has shipped"
printf '%s\n' "$job" | grep -q 'SKIPPED' && fail "on-target's name no longer says it is skipped"
printf '%s\n' "$job" | grep -q 'gh release download -R Mavergreen/python-315 .*SHA256SUMS' || fail "on-target fetches python-315's latest release and its SHA256SUMS"
printf '%s\n' "$job" | grep -q 'sha256sum -c' || fail "on-target verifies the pkg against SHA256SUMS"
printf '%s\n' "$job" | grep -q 'installer -pkg' || fail "on-target installs python-315 in the guest"
printf '%s\n' "$job" | grep -q 'uses: Mavergreen/mavericks-vm@v1' || fail "on-target runs in the mavericks-vm guest"
printf '%s\n' "$job" | grep -q 'sh tests/check-fixtures-run.sh' || fail "on-target runs the fixture runner"
printf '%s\n' "$job" | grep -q 'continue-on-error' && fail "on-target must not pass silently by continue-on-error"

test="$(awk '/^  test:/ { on = 1; print; next } on && /^  [a-z]/ { exit } on' "$ci")"
printf '%s\n' "$test" | grep -q 'run: sh scripts/run-repo-tests.sh' || fail "ci.yml's macOS job runs the suite, whose tests/*.sh glob holds the fixture runner"
printf '%s\n' "$test" | grep -q 'tests/check-fixtures-run.sh' && fail "ci.yml's macOS job runs the fixture runner once, through run-repo-tests.sh, not again as its own step"
grep -q 'sh tests/check-fixtures-run.sh --strict' "$here/.github/workflows/linux-host.yml" || fail "linux-host.yml runs the fixture runner strictly"
grep -q 'sh tests/check-fixtures-run.sh --no-git' "$here/.github/workflows/linux-host.yml" || fail "linux-host.yml runs the fixture runner with git hidden"
echo "PASS on-target-job"
