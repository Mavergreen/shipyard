#!/bin/sh
# platform: macOS-only -- mkbom and lsbom
# spec: explain/os-overwrite.md
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
G="$here/../scripts/gen-os-inventory.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/gen-os-inventory.XXXXXX")"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/tree/usr/bin" "$w/tree/Library/Spaced Name" "$w/receipts" "$w/empty" "$w/other/tree/opt/x"
: > "$w/tree/usr/bin/zz"; : > "$w/tree/Library/Spaced Name/a"; : > "$w/other/tree/opt/x/y"
mkbom "$w/tree" "$w/receipts/com.apple.pkg.Test.bom"
mkbom "$w/other/tree" "$w/receipts/org.example.pkg.Other.bom"
out="$(sh "$G" "$w/receipts")" || { echo "FAIL: the generator should succeed over a receipts directory with an Apple BOM"; exit 1; }
want='Library
Library/Spaced Name
Library/Spaced Name/a
usr
usr/bin
usr/bin/zz'
[ "$out" = "$want" ] || { echo "FAIL: every path of every com.apple.pkg.*.bom, relative to /, sorted, and nothing else -- got:"; printf '%s\n' "$out"; exit 1; }
cp "$w/receipts/com.apple.pkg.Test.bom" "$w/receipts/com.apple.pkg.Again.bom"
[ "$(sh "$G" "$w/receipts")" = "$want" ] || { echo "FAIL: a path two BOMs list is printed once"; exit 1; }
rc=0; sh "$G" "$w/empty" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL: a receipts directory with no com.apple.pkg.*.bom exits 1, not $rc"; exit 1; }
echo "PASS: gen-os-inventory"
