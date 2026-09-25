#!/bin/sh
# platform: host-agnostic
#   usage: sparkle-fetch-test.sh
#          fetch_sparkle_framework.sh returns the pinned framework verbatim -- symlinks intact -- from an
#          archive whose members are spelled "./Sparkle.framework/...", as the real release's are.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning"
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/fetch_sparkle_framework.sh"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/sparkle-fetch-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fw="$w/src/Sparkle.framework"
mkdir -p "$fw/Versions/A/Resources"
printf 'bytes\n' > "$fw/Versions/A/Sparkle"
ln -s A "$fw/Versions/Current"
ln -s Versions/Current/Sparkle "$fw/Sparkle"
ln -s Versions/Current/Resources "$fw/Resources"
mkdir -p "$w/src/Extras"; : > "$w/src/Extras/other"
# platform: "./"-prefixed members, exactly as upstream's Sparkle-1.27.3.tar.xz spells them -- GNU tar
#           matches a named member only as spelled, which is how the unprefixed name broke on Linux.
( cd "$w/src" && tar -czf "$w/sparkle.tar" ./Sparkle.framework ./Extras )
sha="$(shasum -a 256 "$w/sparkle.tar" | awk '{print $1}')"

out="$(MT2_SPARKLE_CACHE="$w/c" MAVERICKS_SPARKLE_URL="file://$w/sparkle.tar" MAVERICKS_SPARKLE_SHA256="$sha" sh "$S")" \
  || { echo "FAIL: fetching a verifying archive must succeed"; exit 1; }
[ "$out" = "$w/c/fat/Sparkle.framework" ] || { echo "FAIL: must print the fat framework path, got: $out"; exit 1; }
[ -L "$out/Versions/Current" ] && [ "$(readlink "$out/Versions/Current")" = A ] \
  || { echo "FAIL: Versions/Current must survive as a symlink to A"; exit 1; }
[ -L "$out/Sparkle" ] || { echo "FAIL: the top-level Sparkle must survive as a symlink"; exit 1; }
cmp -s "$out/Versions/A/Sparkle" "$fw/Versions/A/Sparkle" || { echo "FAIL: the binary must be byte-identical"; exit 1; }

rc=0; MAVERICKS_SPARKLE_ARCH=x86_64 MT2_SPARKLE_CACHE="$w/c2" sh "$S" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: a set MAVERICKS_SPARKLE_ARCH must be refused with 2 -- thinning breaks Sparkle's seal; got $rc"; exit 1; }

if MT2_SPARKLE_CACHE="$w/c3" MAVERICKS_SPARKLE_URL="file://$w/sparkle.tar" MAVERICKS_SPARKLE_SHA256=0000000000000000000000000000000000000000000000000000000000000000 sh "$S" >/dev/null 2>&1; then
  echo "FAIL: a checksum mismatch must fail"; exit 1
fi
echo "PASS: sparkle-fetch"
