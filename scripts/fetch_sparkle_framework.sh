#!/bin/sh
# platform: host-agnostic
#   usage: fetch_sparkle_framework.sh
#          Fetches + caches + checksum-verifies the PREBUILT Sparkle 1.27.3 framework and prints its path.
#          It is embedded VERBATIM -- fat, symlinks intact -- because its code signature seals every file
#          including Autoupdate, so thinning a slice out breaks that seal. Sparkle bytes are never
#          committed. MAVERICKS_SPARKLE_URL / MAVERICKS_SPARKLE_SHA256 override the pin (the tests use
#          them). Exit 2 if MAVERICKS_SPARKLE_ARCH is set: per-arch thinning is gone.
# platform: 1.27.3 is the last Sparkle that runs on 10.9 (LC_VERSION_MIN_MACOSX 10.9 verified on-device
#           for the x86_64 slice). It is prebuilt against SDK 12.0, so the SDK rule exempts exactly these
#           bytes by content (sdk-pins.sh).
set -eu
. "$(dirname "$0")/mavericks_fetch.sh"

if [ -n "${MAVERICKS_SPARKLE_ARCH:-}" ]; then
  echo "fetch_sparkle_framework: MAVERICKS_SPARKLE_ARCH is gone -- Sparkle is embedded fat and unthinned, because thinning breaks its code-signature seal; unset it" >&2
  exit 2
fi
CACHE="${MT2_SPARKLE_CACHE:-$HOME/Library/Caches/mt2-sparkle}"
URL="${MAVERICKS_SPARKLE_URL:-https://github.com/sparkle-project/Sparkle/releases/download/1.27.3/Sparkle-1.27.3.tar.xz}"
SHA="${MAVERICKS_SPARKLE_SHA256:-b4c70198aba86a65dc04550fbd0a97243a9ba3b98d73d138c877347f27920952}"
FAT="$CACHE/fat/Sparkle.framework"

if [ ! -d "$FAT" ]; then
  # platform: the release archive spells its members "./Sparkle.framework/..."; GNU tar extracts a
  #           named member only as spelled, bsdtar either way, so the name carries the "./".
  mav_fetch_pinned "$URL" "$SHA" "$CACHE/fat" "Sparkle-1.27.3.tar.xz" ./Sparkle.framework
fi
[ -f "$FAT/Versions/A/Sparkle" ] || { echo "Sparkle fetch failed: $FAT" >&2; exit 1; }
echo "$FAT"
