#!/bin/sh
#   usage: run-repo-tests.sh [ctest-preset]
#          Runs this repo's tests the same way every repo does. With a preset and a CMakeLists.txt
#          declaring `add_test`, drives ctest (container-tools, tailscale); otherwise runs every
#          top-level tests/*.sh and tests/*.bats. Subdirectories are fixtures and sub-suites with
#          their own entry points, not tests to run here. Exit 77 = SKIP.
# spec: claude-plugins/modernmavericks/skills/modernmavericks-conventions/SKILL.md "Running a repo's
#       tests" -- a newly added test file must run the day it lands, not wait for someone to remember
#       a CI line (macports-legacy-support had 9 test files CI never ran; two had silently rotted).
set -eu
preset="${1:-}"

if [ -n "$preset" ] && [ -f CMakeLists.txt ] && grep -q 'add_test' CMakeLists.txt; then
  echo "run-repo-tests: ctest --preset $preset"
  exec ctest --preset "$preset" --output-on-failure
fi

[ -d tests ] || { echo "run-repo-tests: no tests/ directory — nothing to run"; exit 0; }

status=0
ran=0
for t in tests/*.sh tests/*.bats; do
  [ -f "$t" ] || continue
  ran=$((ran + 1))
  rc=0
  log="$(mktemp "${TMPDIR:-/tmp}/run-repo-tests.XXXXXX")"
  case "$t" in
    *.bats)
      command -v bats >/dev/null 2>&1 || {
        echo "FAIL $t (bats not installed -- install@v1 provides it in CI; 'brew install bats-core' locally)"
        status=1; rm -f "$log"; continue
      }
      bats "$t" > "$log" 2>&1 || rc=$? ;;
    *) sh "$t" > "$log" 2>&1 || rc=$? ;;
  esac
  case "$rc" in
    0)  echo "PASS $t" ;;
    77) echo "SKIP $t (unmet prerequisites)" ;;
    *)  echo "FAIL $t (exit $rc)"; sed 's/^/    | /' "$log"; status=1 ;;
  esac
  rm -f "$log"
done
[ "$ran" -gt 0 ] || echo "run-repo-tests: tests/ has no *.sh or *.bats at top level"
exit "$status"
