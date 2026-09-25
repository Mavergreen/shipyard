#!/bin/sh
# platform: host-agnostic
#   usage: fetch-sdk-test.sh
#          fetch_sdk.sh selects the pin by arch, verifies it, and fails closed -- against file:// fixtures.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning"
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/fetch_sdk.sh"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/fetch-sdk-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fixture() {  # $1 = sdk dir name; prints "<tarball> <sha256>"
  mkdir -p "$w/src/$1/usr/lib"; : > "$w/src/$1/usr/lib/libSystem.tbd"
  ( cd "$w/src" && tar -czf "$w/$1.tar" "$1" )
  printf '%s %s\n' "$w/$1.tar" "$(shasum -a 256 "$w/$1.tar" | awk '{print $1}')"
}
set -- $(fixture MacOSX11.3.sdk); t113="$1"; s113="$2"
set -- $(fixture MacOSX10.9.sdk); t109="$1"; s109="$2"

out="$(MAVERICKS_SDK_CACHE="$w/c1" MAVERICKS_SDK_URL="file://$t113" MAVERICKS_SDK_SHA256="$s113" sh "$S" --arch arm64)" \
  || { echo "FAIL: --arch arm64 with a verifying fixture must succeed"; exit 1; }
[ "$out" = "$w/c1/MacOSX11.3.sdk" ] || { echo "FAIL: --arch arm64 must print the 11.3 SDK dir, got: $out"; exit 1; }

out="$(MAVERICKS_SDK_CACHE="$w/c2" MAVERICKS_SDK_URL="file://$t109" MAVERICKS_SDK_SHA256="$s109" sh "$S")" \
  || { echo "FAIL: no --arch must default to x86_64 and succeed"; exit 1; }
[ "$out" = "$w/c2/MacOSX10.9.sdk" ] || { echo "FAIL: the default must be the 10.9 SDK dir, got: $out"; exit 1; }

if MAVERICKS_SDK_CACHE="$w/c3" MAVERICKS_SDK_URL="file://$t113" MAVERICKS_SDK_SHA256="$s109" sh "$S" --arch arm64 >/dev/null 2>&1; then
  echo "FAIL: a checksum mismatch must fail"; exit 1
fi
[ ! -e "$w/c3/MacOSX11.3.sdk" ] || { echo "FAIL: a checksum mismatch must leave no SDK dir behind"; exit 1; }

rc=0; sh "$S" --arch i386 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: an arch with no pin is a usage error (2), got $rc"; exit 1; }
rc=0; sh "$S" --arch >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: --arch with no value is a usage error (2), got $rc"; exit 1; }

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- a consumer
#       that copies fetch_sdk.sh and mavericks_fetch.sh into its own libexec/ but not sdk-pins.sh gets a
#       usage error naming the missing file, not the shell's own "sdk-pins.sh: not found".
mkdir -p "$w/lonely"
cp "$S" "$here/../scripts/mavericks_fetch.sh" "$w/lonely/"
rc=0; err="$(sh "$w/lonely/fetch_sdk.sh" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: fetch_sdk.sh without sdk-pins.sh beside it must exit 2, got $rc: $err"; exit 1; }
printf '%s' "$err" | grep -q 'sdk-pins\.sh is missing' \
  || { echo "FAIL: fetch_sdk.sh without sdk-pins.sh must say sdk-pins.sh is missing, got: $err"; exit 1; }

echo "PASS: fetch-sdk"
