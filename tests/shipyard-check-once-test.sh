#!/bin/sh
# platform: host-agnostic
# spec: scripts/check-family-conventions.sh -- the comments, portability and host-tools scripts are registered on their own,
#       so under shipyard-check the gate must not run them again; run directly, it still delegates to each.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
w="$(mktemp -d "${TMPDIR:-/tmp}/shipyard-check-once-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL $1"; exit 1; }

root="$w/root"; mkdir -p "$root/.github/workflows" "$w/count"
cp -R "$here/scripts" "$root/scripts"
printf 'name: Release\non: push\n' > "$root/.github/workflows/release.yml"
for s in check-comments check-shell-portability check-host-tools; do
  awk -v s="$s" 'NR == 1 { print; print "echo x >> \"$SHIPYARD_COUNT_DIR/" s "\""; next } { print }' "$root/scripts/$s.sh" > "$root/scripts/$s.tmp"
  mv "$root/scripts/$s.tmp" "$root/scripts/$s.sh"
done
(cd "$root" && git init -q && git add -A) >/dev/null 2>&1
SHIPYARD_COUNT_DIR="$w/count"; export SHIPYARD_COUNT_DIR

runs() { [ -f "$w/count/$1" ] && wc -l < "$w/count/$1" | tr -d ' ' || echo 0; }

(cd "$root" && sh scripts/shipyard-check >/dev/null 2>&1) || :
for s in check-comments check-shell-portability check-host-tools; do
  [ "$(runs "$s")" = 1 ] || fail "$s should run exactly once under shipyard-check, ran $(runs "$s") times"
done

rm -f "$w/count"/*
(cd "$root" && sh scripts/check-family-conventions.sh >/dev/null 2>&1) || :
for s in check-comments check-shell-portability check-host-tools; do
  [ "$(runs "$s")" = 1 ] || fail "$s should run once when the gate is run directly, ran $(runs "$s") times"
done
echo "PASS shipyard-check-once"
