#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
w="$(mktemp -d "${TMPDIR:-/tmp}/mavergreen-vercmp.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
sh "$here/../scripts/build-base-component.sh" --emit-vercmp "$w/stamped" --version 1.0.9 || fail "--emit-vercmp stamps the comparator"
grep -q 'SELF/lib' "$w/stamped" && fail "the stamped mavergreen-vercmp inlines lib/vercmp.sh instead of sourcing it"
mkdir -p "$w/alone"; cp "$w/stamped" "$w/alone/mavergreen-vercmp"
for vc in "$here/../scripts/mavergreen-vercmp" "$w/alone/mavergreen-vercmp"; do
  expect() {  # $1 status  $2 A  $3 B
    rc=0; sh "$vc" "$2" "$3" >"$w/out" 2>&1 || rc=$?
    [ "$rc" -eq "$1" ] || fail "$vc '$2' '$3' exits $1, got $rc"
    [ ! -s "$w/out" ] || [ "$1" -eq 3 ] || fail "$vc '$2' '$3' prints nothing: $(cat "$w/out")"
  }
  expect 0 1.0.9 1.0.10
  expect 1 1.0 1.0.0
  expect 2 2 1
  expect 0 1.27.2-mavergreen.3 1.27.2-mavergreen.10
  expect 2 9.9p2 9.9p1
  expect 0 20261018.2 20261018.10
  expect 3 1.0-rc1 1.0
  expect 3 '' 1.0
  expect 3 1.0 ''
done
echo "PASS: mavergreen-vercmp"
