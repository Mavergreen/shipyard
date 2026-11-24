#!/bin/sh
# platform: host-agnostic
#   usage: macos-only-tests-have-a-home-test.sh
#          shipyard's CI runs no macOS or 10.9 job, so a test that declares itself macOS-only must be in
#          tests/maintainer-tests, the list the maintainer runs by hand. Each line there is "<box> <test>",
#          where <box> is 10.9 (the maintainer's Mavericks box) or golden-gate (the modern Apple Silicon
#          Mac), and every named test must exist.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
cd "$root"
bad=0
[ ! -e tests/on-target-tests ] || { echo "FAIL: tests/on-target-tests is gone with the 10.9 guest job; its tests belong in tests/maintainer-tests"; bad=1; }
while read -r box t rest; do
  [ -n "$box" ] || continue
  case "$box" in 10.9|golden-gate) ;; *) echo "FAIL: tests/maintainer-tests: '$box $t' names no box (10.9 or golden-gate)"; bad=1; continue;; esac
  [ -n "$t" ] && [ -z "$rest" ] || { echo "FAIL: tests/maintainer-tests: '$box $t $rest' is not '<box> <test>'"; bad=1; continue; }
  [ -f "$t" ] || { echo "FAIL: tests/maintainer-tests names $t, which does not exist"; bad=1; }
done < tests/maintainer-tests
for f in $(grep -lE '^# platform: macOS-only' tests/*.sh tests/*.bats 2>/dev/null); do
  awk -v f="$f" '$2 == f { found = 1 } END { exit !found }' tests/maintainer-tests && continue
  echo "FAIL: $f is macOS-only, and shipyard's CI runs no macOS job, so it must be listed in tests/maintainer-tests"
  bad=1
done
[ "$bad" -eq 0 ] || exit 1
echo "PASS: macos-only-tests-have-a-home"
