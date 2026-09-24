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

echo "PASS: run-repo-tests"
