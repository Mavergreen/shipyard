#!/bin/sh
# platform: macOS-only -- builds a Mach-O fixture with Apple clang and reads it through artifact-facts.sh
#   usage: audit-release-sdks-test.sh
#          The audit's verdict over a local dist dir: a pinned tarball passes and names how many
#          Mach-O slices it checked, the runner's SDK fails naming sdk-pin, and a pkg pkgutil cannot
#          expand fails naming "unreadable" rather than passing having examined nothing.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning"
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/audit-release-sdks.sh"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/audit-sdks-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
# platform: xcrun vtool arrived with Xcode 11; a 10.9 box (Xcode 6-era Command Line Tools) has none,
#           and building the fixtures below needs it to stamp an arbitrary recorded SDK version onto
#           a Mach-O binary. The audit itself (audit-release-sdks.sh) is still exercised on that box
#           through its --dist mode elsewhere; only this test's fixture-building needs vtool.
xcrun --find vtool >/dev/null 2>&1 || { echo "SKIP: no vtool (pre-Xcode 11) to stamp the fixtures' recorded SDK"; exit 77; }
printf 'int main(void){return 0;}\n' > "$w/h.c"
mkdir -p "$w/good/dist" "$w/bad/dist" "$w/repo" "$w/unreadable/dist"
cc -arch x86_64 -mmacosx-version-min=10.9 "$w/h.c" -o "$w/h"
xcrun vtool -set-version-min macos 10.9 10.9 -replace -output "$w/good/h" "$w/h"
( cd "$w/good" && tar -czf dist/t-1.0.0-mavericks.1.tar.gz h )
( cd "$w" && tar -czf bad/dist/t-1.0.0-mavericks.1.tar.gz h )
out="$(sh "$S" --dist "$w/good/dist" "$w/repo")" || { echo "FAIL: a pinned release must pass the audit"; exit 1; }
printf '%s' "$out" | grep -q '1 Mach-O slices' || { echo "FAIL: the verdict must name 1 Mach-O slices: $out"; exit 1; }
if out="$(sh "$S" --dist "$w/bad/dist" "$w/repo" 2>&1)"; then echo "FAIL: the runner's SDK must fail the audit"; exit 1; fi
printf '%s' "$out" | grep -q 'sdk-pin' || { echo "FAIL: the verdict must name sdk-pin: $out"; exit 1; }
printf 'not a pkg\n' > "$w/unreadable/dist/x-1.0.0-mavericks.1.pkg"
if out="$(sh "$S" --dist "$w/unreadable/dist" "$w/repo" 2>&1)"; then echo "FAIL: an unreadable pkg must fail the audit"; exit 1; fi
printf '%s' "$out" | grep -q 'unreadable' || { echo "FAIL: the verdict must name unreadable: $out"; exit 1; }
echo "PASS: audit-release-sdks"
