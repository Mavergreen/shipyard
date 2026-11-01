#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
list="$here/on-target-tests"
[ -s "$list" ] || { echo "FAIL: tests/on-target-tests is empty or absent"; exit 1; }
while IFS= read -r t; do
  [ -n "$t" ] || continue
  [ -f "$here/../$t" ] || { echo "FAIL: tests/on-target-tests names $t, which does not exist"; exit 1; }
  if grep -qE '(^|[^[:alnum:]_.-])git[[:space:]]' "$here/../$t"; then
    echo "FAIL: $t runs git, which the 10.9 guest lacks"; exit 1
  fi
  if grep -q 'python3' "$here/../$t" && ! grep -qE 'command -v python3|chk_python3|which python3' "$here/../$t"; then
    echo "FAIL: $t uses python3 without guarding for its absence"; exit 1
  fi
done < "$list"
echo "on-target-tests-test: ok"
