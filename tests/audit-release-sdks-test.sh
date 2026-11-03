#!/bin/sh
# platform: host-agnostic
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
CL="$(sh "$here/../scripts/fetch_clang22.sh" "$here/../components/clang22")"
LIPO="$CL/bin/llvm-lipo"; OTOOL="$CL/bin/llvm-otool"; NM="$CL/bin/llvm-nm"; export LIPO OTOOL NM
S9="$(sh "$here/../scripts/fetch_sdk.sh")"
printf 'int main(void){return 0;}\n' > "$w/h.c"
mkdir -p "$w/good/dist" "$w/bad/dist" "$w/repo" "$w/unreadable/dist"
build() {  # $1 = recorded sdk  $2 = output
  "$CL/bin/clang" --no-default-config -Wno-unused-command-line-argument -fuse-ld=lld --ld-path="$CL/bin/ld64.lld" -target x86_64-apple-macos10.9 -isysroot "$S9" "-Wl,-platform_version,macos,10.9,$1" "$w/h.c" -o "$2"
}
build 10.9 "$w/good/h"
build 26.5 "$w/h"
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
