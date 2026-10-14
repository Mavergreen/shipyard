#!/bin/sh
# platform: host-agnostic
#   usage: dist-fixtures-test.sh
#          Runs shipyard-check --dist over tests/fixtures/checks/<id>/{pass,fail}/ for every dist id
#          that has a dist/ directory there. A pass fixture must come out clean. A fail fixture must
#          fail with that id and only that id, in the message shape (<id>: ...). Each fixture holds
#          dist/ (the files a release publishes), ENV (VAR=value lines) and, when it declares
#          deviations, INGREDIENTS.md.
# spec: scripts/shipyard-check -- the fixtures are the dist half of "every check has a passing and a
#       failing fixture"; the pkgs in them are built once by tests/fixtures/pkgs/build.sh.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
fx="$here/fixtures/checks"
. "$root/scripts/lib/macho-tools.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/dist-fixtures.XXXXXX")"; trap 'rm -rf "$w"' EXIT
have_llvm=1
mach_tool OTOOL 2>/dev/null && mach_tool LIPO 2>/dev/null && mach_tool NM 2>/dev/null && mach_tool STRINGS 2>/dev/null || have_llvm=0

ran=0; skipped=0
for d in "$fx"/*/pass "$fx"/*/fail; do
  [ -d "$d/dist" ] || continue
  id="$(basename "$(dirname "$d")")"; kind="$(basename "$d")"
  if [ "$have_llvm" -eq 0 ] && ls "$d"/dist/*.tar.gz >/dev/null 2>&1; then
    skipped=$((skipped + 1)); continue
  fi
  rc=0
  (
    while IFS= read -r l; do [ -z "$l" ] || export "$l"; done < "$d/ENV"
    SHIPYARD_CHECK_REPO="$d"; export SHIPYARD_CHECK_REPO
    exec sh "$root/scripts/shipyard-check" --dist "$d/dist" --only "$id"
  ) > "$w/out" 2>&1 < /dev/null || rc=$?
  ran=$((ran + 1))
  if [ "$kind" = pass ]; then
    [ "$rc" -eq 0 ] || { echo "FAIL $id/pass: should be clean, got:"; cat "$w/out"; exit 1; }
    continue
  fi
  [ "$rc" -ne 0 ] || { echo "FAIL $id/fail: should fail, got:"; cat "$w/out"; exit 1; }
  grep -q "^$id: " "$w/out" || { echo "FAIL $id/fail: no failure starts with '$id: ', got:"; cat "$w/out"; exit 1; }
  others="$(sed -n 's/^  more: shipyard-check --explain //p' "$w/out" | sort -u | grep -vx "$id" || true)"
  [ -z "$others" ] || { echo "FAIL $id/fail: should violate only $id, also: $others"; cat "$w/out"; exit 1; }
  grep -q '^  fix: ' "$w/out" || { echo "FAIL $id/fail: no fix line in the message"; cat "$w/out"; exit 1; }
done
[ "$ran" -gt 0 ] || { echo "FAIL no dist fixtures ran"; exit 1; }
if [ "$skipped" -gt 0 ]; then
  echo "dist-fixtures: skip: $skipped fixture(s) need LLVM's Mach-O readers"
  exit 77
fi
echo "PASS: dist-fixtures ($ran fixtures)"
