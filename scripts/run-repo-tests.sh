#!/bin/sh
#   usage: run-repo-tests.sh [ctest-preset]
#          Runs this repo's tests the same way every repo does. With a preset and a CMakeLists.txt
#          declaring `add_test`, drives ctest (container-tools, tailscale); otherwise runs every
#          top-level tests/*.sh and tests/*.bats. Subdirectories are fixtures and sub-suites with
#          their own entry points, not tests to run here. Exit 77 = SKIP.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Running a repo's
#       tests" -- a newly added test file must run the day it lands, not wait for someone to remember
#       a CI line (macports-legacy-support had 9 test files CI never ran; two had silently rotted).
set -eu
preset="${1:-}"

# platform: every real macOS session -- every GitHub runner, every 10.9 box with a login shell --
#           sets TMPDIR with a trailing slash. A box running with TMPDIR unset falls back to a clean
#           /tmp and never exercises the doubled-slash path a test's own
#           `mktemp -d "$TMPDIR/x.XXXXXX"` produces everywhere else, which is how two suites shipped
#           broken and failed only in CI. Force the shape here.
: "${TMPDIR:=/tmp/}"
export TMPDIR

if [ -n "$preset" ] && [ -f CMakeLists.txt ] && grep -q 'add_test' CMakeLists.txt; then
  # platform: shipyard-ctest, not ctest -- the tree under test was configured by shipyard-cmake, so
  #           its CTestTestfiles name that cmake's own generator. Guarded because install@v1 installs
  #           the pkg only on a macOS runner: on Linux there is no pkg, shipyard-ctest is simply
  #           absent, and a bare `exec` would end the run with "not found" and no hint that the
  #           missing thing is an install step rather than a broken test.
  command -v shipyard-ctest >/dev/null 2>&1 || {
    echo "run-repo-tests: shipyard-ctest not found, and a ctest preset ($preset) was asked for" >&2
    echo "    the shipyard pkg provides shipyard-cmake/ctest/cpack in /usr/local/bin;" >&2
    echo "    install@v1 installs it on a macOS runner, and there is no pkg for Linux --" >&2
    echo "    a Linux job cannot run a shipyard-configured ctest preset" >&2
    exit 1
  }
  echo "run-repo-tests: shipyard-ctest --preset $preset"
  exec shipyard-ctest --preset "$preset" --output-on-failure
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
