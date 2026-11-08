#!/bin/sh
# platform: host-agnostic
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Running a repo's tests" -- a
#       shell that dies on an unset variable is a failure, whatever its exit status. On 10.9, whose sh
#       is bash 3.2, `set -eu` plus an EXIT trap that succeeds exits 0 from that death: bash 3.2 runs
#       the trap with $? 0 and keeps that status. So a test that crashed halfway read as a PASS, and
#       the runner itself could die and report nothing as success. Every case below exits 0 there.
#       Its own file, not run-repo-tests-test.sh: that one needs bats, which a 10.9 box may lack.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/run-repo-tests.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/run-repo-tests-unset-test.XXXXXX")"; trap 'rm -rf "$work"' EXIT
cd "$work"; mkdir -p tests
fail() { echo "FAIL: $*"; exit 1; }

# platform: the dying shell is the test file's; each `printf` writes a file whose trap succeeds.
printf '#!/bin/sh\nset -eu\ntrap '"'"'rm -f "${TMPDIR:-/tmp}/rrt-none.$$"'"'"' EXIT\necho "$RRT_NEVER_SET_ANYWHERE"\necho reached\n' > tests/a-unset.sh
printf '#!/bin/sh\necho fine\n' > tests/b-fine.sh
if out="$(sh "$S" 2>&1)"; then fail "a test that died on an unset variable passed: $out"; fi
printf '%s\n' "$out" | grep -q 'FAIL tests/a-unset.sh' || fail "the unset-variable death is not that test's failure: $out"
printf '%s\n' "$out" | grep -q 'RRT_NEVER_SET_ANYWHERE' || fail "the failure does not say which variable: $out"
printf '%s\n' "$out" | grep -q 'reached' && fail "the dead test ran on: $out"
printf '%s\n' "$out" | grep -q 'PASS tests/b-fine.sh' || fail "a passing test beside it did not pass: $out"

# spec: scripts/run-repo-tests.sh header -- the same death through a null ${x:?}.
printf '#!/bin/sh\nset -eu\ntrap '"'"'true'"'"' EXIT\nempty=\n: "${empty:?}"\n' > tests/a-unset.sh
if out="$(sh "$S" 2>&1)"; then fail "a test that died on a null \${x:?} passed: $out"; fi
printf '%s\n' "$out" | grep -q 'FAIL tests/a-unset.sh' || fail "the \${x:?} death is not that test's failure: $out"

# spec: scripts/run-repo-tests.sh own_death -- a child's death that the test checked is not the test's death:
#       the test passes or fails by its exit status, as before.
printf '#!/bin/sh\nset -eu\nsh -c '"'"'set -u; echo "$RRT_CHILD_UNSET"'"'"' 2>&1 || echo "child failed, as it should"\n' > tests/a-unset.sh
out="$(sh "$S" 2>&1)" || fail "a test whose child died, as it meant, failed the run: $out"

# spec: scripts/run-repo-tests.sh EXIT trap -- the runner itself: a copy with one unset expansion after its
#       EXIT trap fails the run, where it used to exit 0 having run nothing.
rm tests/a-unset.sh
mkdir -p "$work/rrt"
cp "$here/../scripts/host-of.sh" "$work/rrt/host-of.sh"
sed 's/^status=0$/: "$RRT_NEVER_SET_ANYWHERE"; status=0/' "$S" > "$work/rrt/run-repo-tests.sh"
grep -q RRT_NEVER_SET_ANYWHERE "$work/rrt/run-repo-tests.sh" || fail "the runner copy has no unset expansion"
if out="$(sh "$work/rrt/run-repo-tests.sh" 2>&1)"; then fail "a runner that died on an unset variable exited 0: $out"; fi
printf '%s\n' "$out" | grep -q 'RRT_NEVER_SET_ANYWHERE' || fail "the runner's death does not say why: $out"

echo "PASS: run-repo-tests-unset"
