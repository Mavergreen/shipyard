#!/bin/sh
# platform: host-agnostic
#   usage: on-target-job-test.sh
#          ci.yml carries an on-target job that runs the fixtures in the 10.9 guest, and until python-315
#          phase 1 ships it is skipped in a way the Actions UI shows with the reason in its name. Linux and
#          macOS run the same runner, so the fixture count can be compared across hosts.
# spec: .github/workflows/ci.yml on-target -- the flag-day P1 ruling R5: present and skipped, with a stated reason, until python-315 ships
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
ci="$here/.github/workflows/ci.yml"
fail() { echo "FAIL $1"; exit 1; }

job="$(awk '/^  on-target:/ { on = 1; print; next } on && /^  [a-z]/ { exit } on' "$ci")"
[ -n "$job" ] || fail "ci.yml has an on-target job"
printf '%s\n' "$job" | grep -qx '    if: false' || fail "on-target is skipped (if: false) until python-315 phase 1 ships"
printf '%s\n' "$job" | grep -q '^    name: .*SKIPPED.*python-315' || fail "on-target's name states why it is skipped"
printf '%s\n' "$job" | grep -q 'uses: Mavergreen/mavericks-vm@v1' || fail "on-target runs in the mavericks-vm guest"
printf '%s\n' "$job" | grep -q 'sh tests/check-fixtures-run.sh' || fail "on-target runs the fixture runner"
printf '%s\n' "$job" | grep -q 'continue-on-error' && fail "on-target must not pass silently by continue-on-error"

grep -q 'sh tests/check-fixtures-run.sh' "$ci" || fail "ci.yml's macOS job runs the fixture runner"
grep -q 'sh tests/check-fixtures-run.sh --strict' "$here/.github/workflows/linux-host.yml" || fail "linux-host.yml runs the fixture runner strictly"
grep -q 'sh tests/check-fixtures-run.sh --no-git' "$here/.github/workflows/linux-host.yml" || fail "linux-host.yml runs the fixture runner with git hidden"
echo "PASS on-target-job"
