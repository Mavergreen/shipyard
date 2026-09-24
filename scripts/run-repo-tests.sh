#!/bin/sh
# platform: host-agnostic
#   usage: run-repo-tests.sh [ctest-preset]
#          run-repo-tests.sh --strict-host
#          Runs this repo's tests the same way every repo does. With a preset and a CMakeLists.txt
#          declaring `add_test`, drives ctest (container-tools, tailscale); otherwise runs every
#          top-level tests/*.sh and tests/*.bats. Subdirectories are fixtures and sub-suites with
#          their own entry points, not tests to run here. Exit 77 = SKIP. A test whose header
#          declares "# platform: macOS-only -- <why>" is not run off macOS, and says so.
#          --strict-host is for a job that must prove the host-agnostic half works HERE: every test
#          must declare its host, a host-agnostic one that skips (exit 77, or a bats "# skip") FAILS,
#          and running no host-agnostic test at all fails.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Running a repo's
#       tests" -- a newly added test file must run the day it lands, not wait for someone to remember
#       a CI line (macports-legacy-support had 9 test files CI never ran; two had silently rotted).
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
preset=""; strict=0
for a in "$@"; do
  case "$a" in
    --strict-host) strict=1 ;;
    -*) echo "usage: run-repo-tests.sh [ctest-preset] | --strict-host" >&2; exit 2 ;;
    *) preset="$a" ;;
  esac
done
if [ "$strict" -eq 1 ] && [ -n "$preset" ]; then
  echo "run-repo-tests: --strict-host reads each test file's declared host, and a ctest preset runs ctest's own list instead -- pass one or the other" >&2
  exit 2
fi
os="$(uname -s)"

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
    echo "    the shipyard pkg provides shipyard-cmake/ctest/cpack in /usr/local/mavergreen/bin;" >&2
    echo "    install@v1 installs it on a macOS runner, and there is no pkg for Linux --" >&2
    echo "    a Linux job cannot run a shipyard-configured ctest preset" >&2
    exit 1
  }
  echo "run-repo-tests: shipyard-ctest --preset $preset"
  exec shipyard-ctest --preset "$preset" --output-on-failure
fi

[ -d tests ] || { echo "run-repo-tests: no tests/ directory — nothing to run"; exit 0; }

status=0
ran=0; agnostic=0; macskip=0
for t in tests/*.sh tests/*.bats; do
  [ -f "$t" ] || continue
  ran=$((ran + 1))
  host="$(sh "$SELF/host-of.sh" "$t" 2>/dev/null)" || host=""
  if [ "$strict" -eq 1 ] && [ -z "$host" ]; then
    echo "FAIL $t (declares no host; --strict-host needs '# platform: host-agnostic' or '# platform: macOS-only -- <why>' in its header)"
    status=1; continue
  fi
  if [ "$host" = macOS-only ] && [ "$os" != Darwin ]; then
    echo "SKIP $t (macOS-only)"; macskip=$((macskip + 1)); continue
  fi
  [ "$host" = host-agnostic ] && agnostic=$((agnostic + 1))
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
  # spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Running a repo's tests" --
  #       under --strict-host a skip is the second kind, "broken", never the first, "needs a Mac":
  #       those are declared, and were not run at all.
  if [ "$strict" -eq 1 ] && [ "$host" = host-agnostic ]; then
    case "$rc" in
      77) echo "FAIL $t (skipped, but it declares itself host-agnostic, so it must run on $os)"; sed 's/^/    | /' "$log"; status=1; rm -f "$log"; continue ;;
      0) if grep -q '^ok [0-9][0-9]* .*# skip' "$log"; then
           echo "FAIL $t (skipped some of its cases, but it declares itself host-agnostic, so they must run on $os)"; sed 's/^/    | /' "$log"; status=1; rm -f "$log"; continue
         fi ;;
    esac
  fi
  case "$rc" in
    0)  echo "PASS $t" ;;
    77) echo "SKIP $t (unmet prerequisites)" ;;
    *)  echo "FAIL $t (exit $rc)"; sed 's/^/    | /' "$log"; status=1 ;;
  esac
  rm -f "$log"
done
[ "$ran" -gt 0 ] || echo "run-repo-tests: tests/ has no *.sh or *.bats at top level"
if [ "$strict" -eq 1 ]; then
  echo "run-repo-tests: --strict-host on $os: $agnostic host-agnostic suites run, $macskip macOS-only not run"
  [ "$agnostic" -gt 0 ] || { echo "run-repo-tests: --strict-host ran no host-agnostic suite -- a gate that examined nothing has not passed"; status=1; }
fi
exit "$status"
