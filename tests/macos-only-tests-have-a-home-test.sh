#!/bin/sh
# platform: host-agnostic
#   usage: macos-only-tests-have-a-home-test.sh
#          A test that declares itself macOS-only must run somewhere: in the 10.9 guest (listed in
#          tests/on-target-tests) or by hand on the maintainer's modern Mac, Golden Gate (listed in
#          tests/maintainer-tests). Every path in either list must exist and be macOS-only.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
cd "$root"
bad=0
for f in $(grep -lE '^# platform: macOS-only' tests/*.sh tests/*.bats 2>/dev/null); do
  grep -qxF "$f" tests/on-target-tests && continue
  grep -qxF "$f" tests/maintainer-tests && continue
  echo "FAIL: $f is macOS-only and runs neither in the 10.9 guest (tests/on-target-tests) nor by hand on the maintainer's Mac (tests/maintainer-tests)"
  bad=1
done
for list in tests/on-target-tests tests/maintainer-tests; do
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    [ -f "$t" ] || { echo "FAIL: $list names $t, which does not exist"; bad=1; continue; }
    [ "$list" = tests/on-target-tests ] || grep -qE '^# platform: macOS-only' "$t" \
      || { echo "FAIL: $list names $t, which is not macOS-only, so CI's Linux job already runs it"; bad=1; }
  done < "$list"
done
[ "$bad" -eq 0 ] || exit 1
echo "PASS: macos-only-tests-have-a-home"
