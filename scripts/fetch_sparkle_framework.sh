#!/bin/sh
#   usage: fetch_sparkle_framework.sh
#          Fetches + caches + checksum-verifies the PREBUILT Sparkle 1.27.3 framework, producing a
#          per-arch thinned copy and printing its path. Sparkle bytes are never committed --
#          build-time fetch. The fetched fat framework is cached UNMUTATED; per-arch thinned copies
#          live beside it, so different callers/arches don't stomp each other.
#            MAVERICKS_SPARKLE_ARCH=x86_64 (default): 10.9 Intel updater slice.
#            MAVERICKS_SPARKLE_ARCH=arm64            : native Apple-Silicon updater slice (min-11).
#            MAVERICKS_SPARKLE_ARCH=all              : leave fat (both).
# platform: 1.27.3 is the last Sparkle that runs on 10.9 (LC_VERSION_MIN_MACOSX 10.9 verified
#           on-device for the x86_64 slice); the release framework itself is fat x86_64+arm64.
set -eu
. "$(dirname "$0")/mavericks_fetch.sh"

ARCH="${MAVERICKS_SPARKLE_ARCH:-x86_64}"
CACHE="${MT2_SPARKLE_CACHE:-$HOME/Library/Caches/mt2-sparkle}"
URL="https://github.com/sparkle-project/Sparkle/releases/download/1.27.3/Sparkle-1.27.3.tar.xz"
SHA="b4c70198aba86a65dc04550fbd0a97243a9ba3b98d73d138c877347f27920952"
FAT="$CACHE/fat/Sparkle.framework"     # unmutated fetched framework
OUT="$CACHE/$ARCH/Sparkle.framework"   # per-arch thinned copy (what we print)

if [ ! -d "$FAT" ]; then
  mav_fetch_pinned "$URL" "$SHA" "$CACHE/fat" "Sparkle-1.27.3.tar.xz" Sparkle.framework
fi
if [ ! -d "$OUT" ]; then
  mkdir -p "$CACHE/$ARCH"
  cp -R "$FAT" "$OUT"
  if [ "$ARCH" != "all" ]; then
    for bin in "$OUT/Versions/A/Sparkle" "$OUT/Versions/A/Resources/Autoupdate.app/Contents/MacOS/Autoupdate"; do
      [ -f "$bin" ] && lipo "$bin" -verify_arch "$ARCH" 2>/dev/null \
        && lipo -thin "$ARCH" "$bin" -output "$bin.x" && mv "$bin.x" "$bin" || true
    done
  fi
fi
[ -f "$OUT/Versions/A/Sparkle" ] || { echo "Sparkle fetch failed: $OUT" >&2; exit 1; }
echo "$OUT"
