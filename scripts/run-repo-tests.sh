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
#          MAVERICKS_TEST_JOBS=<n> runs up to n test files at once (default: the CPU count; 1 = one
#          after another). Results still print in file order, each file's log only if it fails.
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

if [ "${MAVERICKS_TEST_JOBS+set}" = set ]; then
  jobs="$MAVERICKS_TEST_JOBS"
  case "$jobs" in
    ''|*[!0-9]*) jobs="" ;;
    *) [ "$jobs" -gt 0 ] 2>/dev/null || jobs="" ;;
  esac
  [ -n "$jobs" ] || {
    echo "run-repo-tests: MAVERICKS_TEST_JOBS must be a positive integer, got '$MAVERICKS_TEST_JOBS'" >&2
    exit 2
  }
else
  # platform: no one command reports the CPU count everywhere -- getconf on Linux and modern macOS,
  #           sysctl on a 10.9 box without it, nproc on a minimal Linux image.
  jobs=""
  for probe in "getconf _NPROCESSORS_ONLN" "sysctl -n hw.ncpu" nproc; do
    jobs="$($probe 2>/dev/null)" || jobs=""
    case "$jobs" in ''|*[!0-9]*|0) jobs="" ;; *) break ;; esac
  done
  : "${jobs:=1}"
fi

# platform: the launcher is perl because no POSIX sh can do what a parallel run needs. A background
#           job in a non-interactive shell starts with SIGINT and SIGQUIT ignored, and a signal
#           ignored at entry cannot be trapped, so a test that traps INT (fetch_pinned_source.bats,
#           mavergreen-helper-test.sh) would silently lose its trap. `set -m` is no way out: dash
#           without a tty (every Linux CI step) prints "can't access tty" and leaves job control
#           off. perl resets both signals and gives the file its own process group. Without perl
#           the files run one at a time in the foreground, exactly as before parallelism existed.
have_perl=0
command -v perl >/dev/null 2>&1 && have_perl=1
[ "$have_perl" -eq 1 ] || jobs=1

rdir="$(mktemp -d "${TMPDIR:-/tmp}/run-repo-tests.XXXXXX")"
# platform: each file's pid is its perl launcher's, which made itself a process-group leader, so a
#           signal to "-pid" reaches the file and everything it started, not just the shell running
#           it. Closing a terminal sends HUP, which would otherwise orphan every running file. Each
#           running file's waiting subshell is stopped too, and a bare `wait` reaps them all: left
#           alive, one could write into the results directory while the EXIT trap removes it, and
#           the removal would fail. Only a file with no rc file yet gets a signal: a finished
#           wrapper's pid is freed once the shell reaps it and may belong to an unrelated process.
stop_running() {
  for f in "$rdir"/*.pid; do
    [ -f "$f" ] || continue
    [ ! -f "${f%.pid}.rc" ] || continue
    IFS= read -r p < "$f"
    kill -s TERM -- "-$p" 2>/dev/null || kill -s TERM "$p" 2>/dev/null || :
    if [ -f "${f%.pid}.wpid" ]; then
      IFS= read -r w < "${f%.pid}.wpid"
      kill -s TERM "$w" 2>/dev/null || :
    fi
  done
  wait 2>/dev/null || :
}
trap 'rm -rf "$rdir"' EXIT
trap 'stop_running; exit 130' INT TERM
trap 'stop_running; exit 129' HUP

# platform: POSIX sh has no `wait -n` (bash 3.2 on 10.9 lacks it), so a file's completion is the
#           appearance of its rc file, written by the subshell that waits on its launcher. Any
#           finished file frees its slot at once; results still print in file order, each when
#           every file before it has printed.
drain_oldest() {
  rest="${pending# }"; di="${rest%% *}"; pending="${rest#"$di"}"
  IFS= read -r dt < "$rdir/$di.name"
  if [ -f "$rdir/$di.msg" ]; then
    IFS= read -r dmsg < "$rdir/$di.msg"; echo "$dmsg"
    [ ! -f "$rdir/$di.failed" ] || status=1
    return 0
  fi
  IFS= read -r dhost < "$rdir/$di.host"
  IFS= read -r rc < "$rdir/$di.rc"
  log="$rdir/$di.log"
  # spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Running a repo's tests" --
  #       under --strict-host a skip is the second kind, "broken", never the first, "needs a Mac":
  #       those are declared, and were not run at all.
  if [ "$strict" -eq 1 ] && [ "$dhost" = host-agnostic ]; then
    case "$rc" in
      77) echo "FAIL $dt (skipped, but it declares itself host-agnostic, so it must run on $os)"; sed 's/^/    | /' "$log"; status=1; return 0 ;;
      0) if grep -q '^ok [0-9][0-9]* .*# skip' "$log"; then
           echo "FAIL $dt (skipped some of its cases, but it declares itself host-agnostic, so they must run on $os)"; sed 's/^/    | /' "$log"; status=1; return 0
         fi ;;
    esac
  fi
  case "$rc" in
    0)  echo "PASS $dt" ;;
    77) echo "SKIP $dt (unmet prerequisites)" ;;
    *)  echo "FAIL $dt (exit $rc)"; sed 's/^/    | /' "$log"; status=1 ;;
  esac
}

# spec: scripts/run-repo-tests.sh header -- results print in file order, so this prints every leading
#       file whose outcome is known and stops at the first that is not.
print_ready() {
  while [ -n "$pending" ]; do
    rest="${pending# }"; ri="${rest%% *}"
    [ -f "$rdir/$ri.msg" ] || [ -f "$rdir/$ri.rc" ] || return 0
    drain_oldest
  done
}

count_running() {
  running=0; still=""
  for r in $live; do
    [ ! -f "$rdir/$r.rc" ] || continue
    running=$((running + 1)); still="$still $r"
  done
  live="$still"
}

# platform: nothing in POSIX sh sleeps until a file appears, so the runner polls. 0.2 s is a
#           fraction of the shortest test; a sleep that rejects fractions (older BSD) takes 1 s.
nap() { sleep 0.2 2>/dev/null || sleep 1; }

# spec: scripts/run-repo-tests.sh header -- a file whose outcome is known before it would run (no
#       host declared, macOS-only off macOS, no bats) prints in its own place in file order, so its
#       message waits in the results directory until its turn.
decide() {
  printf '%s\n' "$1" > "$rdir/$i.msg"
  [ "${2:-}" != fail ] || : > "$rdir/$i.failed"
}

status=0
ran=0; agnostic=0; macskip=0
i=0; running=0; live=""; pending=""
for t in tests/*.sh tests/*.bats; do
  [ -f "$t" ] || continue
  ran=$((ran + 1))
  i=$((i + 1))
  print_ready
  pending="$pending $i"
  printf '%s\n' "$t" > "$rdir/$i.name"
  host="$(sh "$SELF/host-of.sh" "$t" 2>/dev/null)" || host=""
  if [ "$strict" -eq 1 ] && [ -z "$host" ]; then
    decide "FAIL $t (declares no host; --strict-host needs '# platform: host-agnostic' or '# platform: macOS-only -- <why>' in its header)" fail
    continue
  fi
  if [ "$host" = macOS-only ] && [ "$os" != Darwin ]; then
    decide "SKIP $t (macOS-only)"; macskip=$((macskip + 1)); continue
  fi
  [ "$host" != host-agnostic ] || agnostic=$((agnostic + 1))
  printf '%s\n' "$host" > "$rdir/$i.host"
  case "$t" in
    *.bats)
      command -v bats >/dev/null 2>&1 || {
        decide "FAIL $t (bats not installed -- install@v1 provides it in CI; 'brew install bats-core' locally)" fail
        continue
      }
      set -- bats "$t" ;;
    *) set -- sh "$t" ;;
  esac
  if [ "$have_perl" -eq 1 ]; then
    while :; do
      print_ready; count_running
      if [ "$running" -lt "$jobs" ]; then break; fi
      nap
    done
    # platform: the subshell records the launcher's pid, waits for it, and publishes its exit status
    #           by rename so the rc file appears whole. Its errors are muted: an orphan left by a
    #           killed runner finds the results directory gone.
    (
      perl -e '$SIG{INT} = $SIG{QUIT} = "DEFAULT"; setpgrp(0, 0); exec @ARGV or die "run-repo-tests: exec $ARGV[0]: $!\n"' -- "$@" > "$rdir/$i.log" 2>&1 < /dev/null &
      pid=$!
      {
        printf '%s\n' "$pid" > "$rdir/$i.pid"
        rc=0; wait "$pid" || rc=$?
        printf '%s\n' "$rc" > "$rdir/$i.rc.tmp"
        mv "$rdir/$i.rc.tmp" "$rdir/$i.rc"
      } 2>/dev/null
    ) &
    printf '%s\n' "$!" > "$rdir/$i.wpid"
    live="$live $i"
  else
    rc=0
    "$@" > "$rdir/$i.log" 2>&1 || rc=$?
    printf '%s\n' "$rc" > "$rdir/$i.rc"
  fi
done
while [ -n "$pending" ]; do
  print_ready
  [ -z "$pending" ] || nap
done
wait
[ "$ran" -gt 0 ] || echo "run-repo-tests: tests/ has no *.sh or *.bats at top level"
if [ "$strict" -eq 1 ]; then
  echo "run-repo-tests: --strict-host on $os: $agnostic host-agnostic suites run, $macskip macOS-only not run"
  [ "$agnostic" -gt 0 ] || { echo "run-repo-tests: --strict-host ran no host-agnostic suite -- a gate that examined nothing has not passed"; status=1; }
fi
exit "$status"
