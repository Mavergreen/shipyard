#!/bin/sh
# platform: host-agnostic
#   usage: macos-only-tests-have-a-home-test.sh
#          A test that declares itself macOS-only must run somewhere: in the 10.9 guest (listed in
#          tests/on-target-tests) or in release.yml's canary job. Every path in tests/on-target-tests
#          must exist.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
cd "$root"
bad=0
canary="$(awk '/^  canary:/ { on = 1; next } on && /^  [A-Za-z0-9_-]+:/ { on = 0 } on' .github/workflows/release.yml)"
[ -n "$canary" ] || { echo "FAIL: release.yml has no canary job"; exit 1; }
for f in $(grep -lE '^# platform: macOS-only' tests/*.sh tests/*.bats 2>/dev/null); do
  grep -qxF "$f" tests/on-target-tests && continue
  printf '%s\n' "$canary" | grep -qF "$f" && continue
  echo "FAIL: $f is macOS-only and runs neither in the 10.9 guest (tests/on-target-tests) nor in release.yml's canary"
  bad=1
done
while IFS= read -r t; do
  [ -n "$t" ] || continue
  [ -f "$t" ] || { echo "FAIL: tests/on-target-tests names $t, which does not exist"; bad=1; }
done < tests/on-target-tests
[ "$bad" -eq 0 ] || exit 1
echo "PASS: macos-only-tests-have-a-home"
