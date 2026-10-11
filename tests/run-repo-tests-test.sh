#!/bin/sh
# platform: host-agnostic
# spec: scripts/run-repo-tests.sh -- exit 77 is the SKIP idiom container-tools already uses for
#       its boot-proof.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/run-repo-tests.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/run-repo-tests-test.XXXXXX")"; trap 'rm -rf "$work"' EXIT
cd "$work"; mkdir -p tests

mkdir -p empty && (cd empty && sh "$S" >/dev/null) || { echo "FAIL no-tests-dir should pass"; exit 1; }

printf '#!/bin/sh\necho ok\n'        > tests/a-test.sh
printf '#!/bin/sh\nexit 77\n'        > tests/b-skips.sh
out="$(sh "$S")" || { echo "FAIL all-passing should exit 0: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'PASS.*a-test.sh' || { echo "FAIL pass line: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'SKIP.*b-skips.sh' || { echo "FAIL skip line: $out"; exit 1; }

printf '#!/bin/sh\nexit 1\n' > tests/c-fails.sh
if out="$(sh "$S" 2>&1)"; then echo "FAIL failing test should fail the runner: $out"; exit 1; fi
printf '%s\n' "$out" | grep -q 'FAIL.*c-fails.sh' || { echo "FAIL fail line: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'SKIP.*c-fails.sh' && { echo "FAIL: a genuine failure must not be reported as a skip"; exit 1; }
rm tests/c-fails.sh

mkdir -p tests/fixtures
printf '#!/bin/sh\nexit 1\n' > tests/fixtures/nested.sh
sh "$S" >/dev/null || { echo "FAIL: subdirectories are fixtures/sub-suites with their own entry points, not tests to run -- nested script must not be run"; exit 1; }

printf '#!/usr/bin/env bats\n@test "trivial" { true; }\n' > tests/d.bats
# platform: Ubuntu installs bats as /usr/bin/bats, beside sh itself, so PATH=/usr/bin:/bin hid
#           nothing there. A PATH holding only what the runner itself calls hides bats on every host.
nobats="$work/nobats"; mkdir -p "$nobats"
for c in sh dirname uname mktemp awk sed grep rm; do ln -s "$(command -v "$c")" "$nobats/$c"; done
if out="$(PATH="$nobats" sh "$S" 2>&1)"; then echo "FAIL missing bats should fail the runner: $out"; exit 1; fi
printf '%s\n' "$out" | grep -q 'FAIL tests/d.bats' \
  || { echo "FAIL: a .bats file with no bats is a FAILURE not a skip -- install@v1 provides bats on every runner, so its absence means the environment is broken, and a skipped assertion is one nobody is checking, which is the whole hole this runner exists to close: $out"; exit 1; }
printf '%s\n' "$out" | grep -qi 'bats' || { echo "FAIL should say bats is missing: $out"; exit 1; }
sh "$S" >/dev/null || { echo "FAIL bats file should pass when bats is installed"; exit 1; }

printf '#!/bin/sh\necho "the specific reason it broke"\nexit 1\n' > tests/e-loud.sh
out="$(sh "$S" 2>&1 || true)"
printf '%s\n' "$out" | grep -q 'the specific reason it broke' \
  || { echo "FAIL: a failing test must SAY something -- reporting \"FAIL tests/x.sh (exit 1)\" and discarding the output leaves whoever reads CI with no way to tell a broken test from a broken product, which is exactly the position ed25519 once put us in; got: $out"; exit 1; }
rm -f tests/e-loud.sh

printf '#!/bin/sh\necho "chatty but fine"\nexit 0\n' > tests/f-chatty.sh
out="$(sh "$S" 2>&1 || true)"
printf '%s\n' "$out" | grep -q 'chatty but fine' \
  && { echo "FAIL: a passing test must stay quiet, or the signal drowns -- it printed its output"; exit 1; }
rm -f tests/f-chatty.sh

# spec: SKILL.md "Running a repo's tests" -- --strict-host. Every case asserts the runner's EXIT
#       STATUS. uname is stubbed so each case means the same thing on a Mac and on Linux, and each
#       failing case keeps a passing host-agnostic suite beside it, so it fails for its own reason.
stub="$work/stub"; mkdir -p "$stub"
printf '#!/bin/sh\necho Linux\n' > "$stub/uname"; chmod +x "$stub/uname"
onlinux() { PATH="$stub:$PATH" sh "$S" "$@"; }
fresh() { rm -rf tests; mkdir tests; }
agn='#!/bin/sh\n# platform: host-agnostic\n'
mac='#!/bin/sh\n# platform: macOS-only -- a fixture\n'

fresh; printf "${agn}exit 0\n" > tests/a.sh; printf "${mac}exit 1\n" > tests/m.sh
out="$(onlinux --strict-host 2>&1)" || { echo "FAIL strict: one passing host-agnostic suite and one macOS-only must pass: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'SKIP tests/m.sh (macOS-only)' || { echo "FAIL strict: a macOS-only suite must be named as not run: $out"; exit 1; }
printf '%s\n' "$out" | grep -q '1 host-agnostic suites run, 1 macOS-only not run' || { echo "FAIL strict: the count must be printed: $out"; exit 1; }

fresh; printf "${mac}exit 1\n" > tests/m.sh
onlinux >/dev/null 2>&1 || { echo "FAIL: WITHOUT --strict-host a declared macOS-only suite is still not run off macOS"; exit 1; }

fresh; printf '#!/bin/sh\nexit 0\n' > tests/u.sh; printf "${agn}exit 0\n" > tests/a.sh
if out="$(onlinux --strict-host 2>&1)"; then echo "FAIL strict: an undeclared suite must fail, even beside a passing host-agnostic one: $out"; exit 1; fi
printf '%s\n' "$out" | grep -q 'FAIL tests/u.sh (declares no host' || { echo "FAIL strict: the undeclared suite must be named: $out"; exit 1; }
onlinux >/dev/null 2>&1 || { echo "FAIL: WITHOUT --strict-host an undeclared suite runs as before"; exit 1; }

fresh; printf "${agn}exit 77\n" > tests/s.sh; printf "${agn}exit 0\n" > tests/a.sh
if out="$(onlinux --strict-host 2>&1)"; then echo "FAIL strict: a host-agnostic suite that skips must fail: $out"; exit 1; fi
onlinux >/dev/null 2>&1 || { echo "FAIL: WITHOUT --strict-host exit 77 is still a skip"; exit 1; }

fresh; printf '#!/usr/bin/env bats\n# platform: host-agnostic\n@test "t" { skip "no"; }\n' > tests/s.bats; printf "${agn}exit 0\n" > tests/a.sh
if out="$(onlinux --strict-host 2>&1)"; then echo "FAIL strict: a host-agnostic bats file that skips a case must fail: $out"; exit 1; fi

fresh; printf "${mac}exit 0\n" > tests/m.sh
if out="$(onlinux --strict-host 2>&1)"; then echo "FAIL strict: running no host-agnostic suite at all must fail: $out"; exit 1; fi

fresh; printf "${agn}exit 1\n" > tests/f.sh; printf "${agn}exit 0\n" > tests/a.sh
if onlinux --strict-host >/dev/null 2>&1; then echo "FAIL strict: a failing host-agnostic suite must fail the runner"; exit 1; fi

rc=0; sh "$S" --strict-host some-preset >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: --strict-host with a ctest preset is a usage error (exit 2), got $rc"; exit 1; }

# spec: SKILL.md "Running a repo's tests" -- the runner starts up to MAVERICKS_TEST_JOBS files at
#       once and still prints their results in file order. Each case gets a fresh tests/ directory.
host='#!/bin/sh\n# platform: host-agnostic\n'

fresh; printf "${host}sleep 2\nexit 0\n" > tests/a.sh; printf "${host}exit 0\n" > tests/b.sh
out="$(MAVERICKS_TEST_JOBS=2 sh "$S" 2>&1)" || { echo "FAIL parallel: both files pass, the run must exit 0: $out"; exit 1; }
[ "$(printf '%s\n' "$out" | grep '^PASS')" = "PASS tests/a.sh
PASS tests/b.sh" ] || { echo "FAIL parallel: results must print in file order even when a later file finishes first: $out"; exit 1; }

# spec: scripts/run-repo-tests.sh header (MAVERICKS_TEST_JOBS) -- a free slot is refilled the moment any
#       file finishes, not when the oldest does. With 2 jobs, a.sh holds one slot for 4 s, b.sh frees
#       the other at once, and c.sh must start in it while a.sh still runs: a.sh exits 1 unless c.sh
#       has already started. Results still print in file order.
fresh; rm -f "$work/c.started"
printf "${host}sleep 4\n[ -e \"$work/c.started\" ]\n" > tests/a.sh
printf "${host}exit 0\n" > tests/b.sh
printf "${host}touch \"$work/c.started\"\n" > tests/c.sh
out="$(MAVERICKS_TEST_JOBS=2 sh "$S" 2>&1)" || { echo "FAIL refill: c.sh must start while the oldest file a.sh still runs, in the slot b.sh freed: $out"; exit 1; }
[ "$(printf '%s\n' "$out" | grep '^PASS')" = "PASS tests/a.sh
PASS tests/b.sh
PASS tests/c.sh" ] || { echo "FAIL refill: results must still print in file order: $out"; exit 1; }

# spec: scripts/run-repo-tests.sh header (MAVERICKS_TEST_JOBS) -- each file holds a lock directory for 2 s,
#       so two files running at once make the second to take it fail, and one at a time never do.
lockfile='#!/bin/sh\n# platform: host-agnostic\nmkdir "$LOCK" || exit 1\nsleep 2\nrmdir "$LOCK"\n'
fresh; printf "$lockfile" > tests/a.sh; printf "$lockfile" > tests/b.sh
LOCK="$work/lock"; export LOCK
if MAVERICKS_TEST_JOBS=2 sh "$S" >/dev/null 2>&1; then echo "FAIL parallel: with 2 jobs the two files must overlap, so the second to take the lock fails"; exit 1; fi
MAVERICKS_TEST_JOBS=1 sh "$S" >/dev/null 2>&1 || { echo "FAIL serial: with 1 job the files run one after another, so neither finds the lock taken"; exit 1; }

fresh; printf "${host}echo boom\nexit 1\n" > tests/x.sh
rc=0; out="$(MAVERICKS_TEST_JOBS=3 sh "$S" 2>&1)" || rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL parallel: a failing file must fail the run with exit 1, got $rc: $out"; exit 1; }
printf '%s\n' "$out" | grep -q '^FAIL tests/x.sh (exit 1)$' || { echo "FAIL parallel: the failing file must be named: $out"; exit 1; }
printf '%s\n' "$out" | grep -q '^    | boom$' || { echo "FAIL parallel: the failing file's log must print: $out"; exit 1; }

fresh; printf "${host}sleep 2\nexit 0\n" > tests/a.sh; printf '#!/bin/sh\nexit 0\n' > tests/b.sh; printf "${host}exit 0\n" > tests/c.sh
rc=0; out="$(MAVERICKS_TEST_JOBS=2 onlinux --strict-host 2>&1)" || rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL strict parallel: an undeclared file must fail the run, got $rc: $out"; exit 1; }
[ "$(printf '%s\n' "$out" | grep -E '^(PASS|FAIL) ' | sed 's/ (.*//')" = "PASS tests/a.sh
FAIL tests/b.sh
PASS tests/c.sh" ] || { echo "FAIL strict parallel: a file decided before launch must keep its place in file order: $out"; exit 1; }

fresh; printf '#!/bin/sh\nif read -r x; then exit 1; fi\nexit 0\n' > tests/in.sh
yes | sh "$S" >/dev/null 2>&1 || { echo "FAIL: a test file must read /dev/null, not the runner's stdin, or parallel files would fight over it"; exit 1; }

fresh; printf "${host}exit 0\n" > tests/a.sh
for bad in 0 x -1 ""; do
  rc=0; err="$(MAVERICKS_TEST_JOBS="$bad" sh "$S" 2>&1 >/dev/null)" || rc=$?
  [ "$rc" -eq 2 ] || { echo "FAIL: MAVERICKS_TEST_JOBS='$bad' is a usage error (exit 2), got $rc"; exit 1; }
  printf '%s\n' "$err" | grep -q 'MAVERICKS_TEST_JOBS' || { echo "FAIL: the usage error for '$bad' must name MAVERICKS_TEST_JOBS: $err"; exit 1; }
done

out="$(MAVERICKS_TEST_JOBS=64 sh "$S" 2>&1)" || { echo "FAIL: more jobs than files must still pass: $out"; exit 1; }
[ "$(printf '%s\n' "$out" | grep -c '^PASS')" -eq 1 ] || { echo "FAIL: one file, one PASS line: $out"; exit 1; }

# spec: scripts/run-repo-tests.sh "# platform:" comment on have_perl -- with no perl the runner runs
#       files one at a time in the foreground, as it did before parallelism. The PATH holds only
#       what the runner and the lock-taking files call, so it cannot find perl on any host.
noperl="$work/noperl"; mkdir -p "$noperl"
for c in sh dirname uname mktemp awk sed grep rm sleep mkdir rmdir; do ln -s "$(command -v "$c")" "$noperl/$c"; done
fresh; printf "$lockfile" > tests/a.sh; printf "$lockfile" > tests/b.sh
PATH="$noperl" command -v perl >/dev/null 2>&1 && { echo "FAIL: the no-perl PATH still finds perl"; exit 1; }
PATH="$noperl" MAVERICKS_TEST_JOBS=2 sh "$S" >/dev/null 2>&1 \
  || { echo "FAIL no perl: with no perl the files must run one at a time, so neither finds the lock taken"; exit 1; }
rc=0; PATH="$noperl" MAVERICKS_TEST_JOBS=x sh "$S" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL no perl: a bad MAVERICKS_TEST_JOBS is still a usage error (exit 2), got $rc"; exit 1; }

if ! command -v perl >/dev/null 2>&1; then
  echo "no perl -- skipping the signal and interrupt cases, which need it to start the runner" >&2
  echo "PASS: run-repo-tests"
  exit 0
fi

# platform: a process started in the background by a non-interactive shell has SIGINT ignored, and a
#           signal ignored at entry cannot be trapped. The runner's files must still get a live
#           SIGINT, or a test that traps INT (fetch_pinned_source.bats) loses its trap on a CI host
#           whose runner step started that way. perl starts the runner here with SIGINT ignored.
fresh
printf "${host}trap 'echo trapped > \"$work/trapped\"; exit 0' INT\nkill -INT \$\$\nsleep 1\nexit 1\n" > tests/t.sh
out="$(MAVERICKS_TEST_JOBS=2 perl -e '$SIG{INT} = "IGNORE"; exec @ARGV' sh "$S" 2>&1)" \
  || { echo "FAIL: a file that traps SIGINT must be able to, even when the runner started with it ignored: $out"; exit 1; }
[ -e "$work/trapped" ] || { echo "FAIL: the file's INT trap never fired"; exit 1; }

# platform: a background job in a non-interactive shell starts with SIGINT ignored, and a signal
#           ignored on entry cannot be trapped -- the same holds for this test file when its own
#           runner started it in the background. perl resets SIGINT before exec (tests/mavergreen-
#           helper-test.sh's process-group case uses perl for setpgrp), so the runner here can trap
#           the interrupt. Each file starts a grandchild that writes `survived`, so the case fails
#           unless the runner stops the whole process group, not just each file's own shell.
fresh; mkdir -p tmp
for n in a b; do
  printf "${host}touch \"$work/started.\$\$\"\nsh -c 'sleep 3; touch \"$work/survived\"' &\nwait\n" > "tests/$n.sh"
done
MAVERICKS_TEST_JOBS=2 TMPDIR="$work/tmp/" perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV' sh "$S" >/dev/null 2>&1 &
runner=$!
waited=0
while [ "$(ls "$work" | grep -c '^started\.')" -lt 2 ]; do
  waited=$((waited + 1)); [ "$waited" -lt 100 ] || { echo "FAIL: the two test files never started"; kill "$runner" 2>/dev/null || :; exit 1; }
  sleep 0.1 2>/dev/null || sleep 1
done
kill -INT "$runner"
rc=0; wait "$runner" || rc=$?
sleep 4
[ "$rc" -ne 0 ] || { echo "FAIL: an interrupted run must exit non-zero"; exit 1; }
[ ! -e "$work/survived" ] || { echo "FAIL: an interrupt must stop every running test file and what it started, but a grandchild ran to its end"; exit 1; }
[ -z "$(ls "$work/tmp" | grep '^run-repo-tests\.')" ] || { echo "FAIL: an interrupted run must remove its results directory"; exit 1; }

echo "PASS: run-repo-tests"
