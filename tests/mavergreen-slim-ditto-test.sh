#!/bin/sh
# platform: macOS-only -- runs the real /usr/bin/ditto on a copy of /bin/ls; run by hand on the 10.9 box and on golden-gate (tests/maintainer-tests)
#   usage: mavergreen-slim-ditto-test.sh
#          `mavergreen slim apply` with the real ditto, against a temporary --root holding a copy of
#          /bin/ls. On an x86_64 Mac the copy keeps only arches the host runs and still runs. On an
#          arm64 Mac, MAVERGREEN_HOST_ARCH=arm64 with `slim on` thins it to arm64 alone and it still runs.
# spec: scripts/mavergreen.sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
MGS="$here/../scripts/mavergreen.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/mavergreen-slim-ditto.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
[ "$(uname -s)" = Darwin ] || { echo "not a Mac -- skipping"; exit 77; }
V="$w/vol"; T="$V/usr/local/mavergreen"
mkdir -p "$T/p/bin" "$T/var"
copy="$T/p/bin/ls"
cp /bin/ls "$copy"
cat > "$T/p/mavergreen.plist" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>product</key><string>p</string><key>group</key><string>p</string>
<key>identifier</key><string>dev.mavergreen.p</string><key>version</key><string>1.0</string>
</dict></plist>
PL
unset MAVERGREEN_HOST_ARCH MAVERGREEN_DITTO || true
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then
  MAVERGREEN_HOST_ARCH=arm64; export MAVERGREEN_HOST_ARCH
  sh "$MGS" --root "$V" slim on >/dev/null || fail "slim on"
  info="$(file "$copy")"
  case "$info" in *x86_64*|*i386*) fail "an arm64 host's slimmed copy keeps no Intel slice: $info" ;; esac
  case "$info" in *arm64*) ;; *) fail "the copy keeps its arm64 slice: $info" ;; esac
else
  sh "$MGS" --root "$V" slim apply p >/dev/null || fail "slim apply"
  info="$(file "$copy")"
  case "$info" in *arm64*) fail "an x86_64 host's copy keeps no arm64 slice: $info" ;; esac
fi
"$copy" / >/dev/null || fail "the slimmed copy must still run"
echo "PASS: mavergreen-slim-ditto"
