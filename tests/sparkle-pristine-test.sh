#!/bin/sh
# platform: host-agnostic
#   usage: sparkle-pristine-test.sh
#          An embedded Sparkle.framework must be the pinned one byte for byte, symlinks included.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning"
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/assert_sparkle_pristine.sh"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/sparkle-pristine.XXXXXX")"; trap 'rm -rf "$w"' EXIT
p="$w/pin/Sparkle.framework"
mkdir -p "$p/Versions/A/Resources"; printf 'bin\n' > "$p/Versions/A/Sparkle"; printf 'res\n' > "$p/Versions/A/Resources/r"
ln -s A "$p/Versions/Current"; ln -s Versions/Current/Sparkle "$p/Sparkle"
copy() { rm -rf "$w/e"; mkdir -p "$w/e"; cp -R "$p" "$w/e/"; }

copy; sh "$S" "$w/e/Sparkle.framework" "$p" >/dev/null || { echo "FAIL: a cp -R copy is pristine"; exit 1; }
copy; rm "$w/e/Sparkle.framework/Versions/Current"; cp -R "$p/Versions/A" "$w/e/Sparkle.framework/Versions/Current"
if sh "$S" "$w/e/Sparkle.framework" "$p" >/dev/null 2>&1; then echo "FAIL: a symlink flattened to a copy is not pristine"; exit 1; fi
copy; printf 'x' >> "$w/e/Sparkle.framework/Versions/A/Sparkle"
if sh "$S" "$w/e/Sparkle.framework" "$p" >/dev/null 2>&1; then echo "FAIL: a changed byte is not pristine"; exit 1; fi
copy; : > "$w/e/Sparkle.framework/Versions/A/extra"
if sh "$S" "$w/e/Sparkle.framework" "$p" >/dev/null 2>&1; then echo "FAIL: an extra file is not pristine"; exit 1; fi
rc=0; sh "$S" "$w/nope" "$p" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: a missing framework is a usage error (2), got $rc"; exit 1; }
echo "PASS: sparkle-pristine"
