#!/bin/sh
# platform: host-agnostic
#   usage: audit-release-sdks-test.sh
#          The audit's verdict over a local dist dir: a pinned tarball passes and names how many
#          Mach-O slices it checked, the runner's SDK fails naming sdk-pin, and a pkg pkgutil cannot
#          expand fails naming "unreadable" rather than passing having examined nothing. The Mach-Os are the
#          checked-in fixtures in tests/fixtures/macho.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning"
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/audit-release-sdks.sh"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/audit-sdks-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
. "$here/../scripts/lib/macho-tools.sh"
mach_tool OTOOL 2>/dev/null && mach_tool LIPO 2>/dev/null || { echo "SKIP: no LLVM readers (install llvm, or set OTOOL and LIPO)"; exit 77; }
mkdir -p "$w/good/dist" "$w/bad/dist" "$w/repo" "$w/unreadable/dist" "$w/src"
cp "$here/fixtures/macho/clean" "$w/src/h"
( cd "$w/src" && tar -czf "$w/good/dist/t-1.0.0-mavericks.1.tar.gz" h )
cp "$here/fixtures/macho/r265" "$w/src/h"
( cd "$w/src" && tar -czf "$w/bad/dist/t-1.0.0-mavericks.1.tar.gz" h )
out="$(sh "$S" --dist "$w/good/dist" "$w/repo")" || { echo "FAIL: a pinned release must pass the audit"; exit 1; }
printf '%s' "$out" | grep -q '1 Mach-O slices' || { echo "FAIL: the verdict must name 1 Mach-O slices: $out"; exit 1; }
if out="$(sh "$S" --dist "$w/bad/dist" "$w/repo" 2>&1)"; then echo "FAIL: the runner's SDK must fail the audit"; exit 1; fi
printf '%s' "$out" | grep -q 'sdk-pin' || { echo "FAIL: the verdict must name sdk-pin: $out"; exit 1; }
printf 'not a pkg\n' > "$w/unreadable/dist/x-1.0.0-mavericks.1.pkg"
if out="$(sh "$S" --dist "$w/unreadable/dist" "$w/repo" 2>&1)"; then echo "FAIL: an unreadable pkg must fail the audit"; exit 1; fi
printf '%s' "$out" | grep -q 'unreadable' || { echo "FAIL: the verdict must name unreadable: $out"; exit 1; }
echo "PASS: audit-release-sdks"
