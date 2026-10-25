#!/bin/sh
# platform: host-agnostic
#   usage: fetch_sdk.sh [--arch x86_64|arm64]
#          Fetches + caches + checksum-verifies the family's PINNED SDK for one arch (sdk-pins.sh):
#          MacOSX10.9.sdk for x86_64 (the default), MacOSX11.3.sdk for arm64. Prints the SDK root on
#          stdout, with SDKSettings.json added where the SDK ships none (sdk-pins.sh). A native 10.9
#          build uses this pin too, never xcrun's own SDK (MavericksToolchain.cmake).
#          Apple SDK bytes are never committed -- this is a build-time fetch. The cache default is per-machine and durable:
#          TMPDIR gets purged by macOS (stranding the path CMake cached at configure time).
#          MAVERICKS_SDK_URL / MAVERICKS_SDK_SHA256 override the selected arch's pin (the tests use
#          them); MAVERICKS_SDK_CACHE moves the cache. Exit 2 on a usage error or an arch with no pin.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- a repo that
#       ships this script (a toolchain's libexec/, e.g.) ships its two sourced helpers beside it.
[ -f "$SELF/sdk-pins.sh" ] || { echo "fetch_sdk: sdk-pins.sh is missing beside $0 -- copy it with fetch_sdk.sh and mavericks_fetch.sh (SKILL.md \"SDK pinning\")" >&2; exit 2; }
. "$SELF/mavericks_fetch.sh"
. "$SELF/sdk-pins.sh"
ARCH=x86_64
case "$#:${1:-}" in
  0:) ;;
  2:--arch) ARCH="$2" ;;
  *) echo "usage: fetch_sdk.sh [--arch x86_64|arm64]" >&2; exit 2 ;;
esac
pin="$(shipyard_sdk_pin "$ARCH")" || { echo "fetch_sdk: no pinned SDK for arch '$ARCH' (x86_64 and arm64 have one)" >&2; exit 2; }
# shellcheck disable=SC2086  # the pin is four space-free words by construction
set -- $pin
CACHE="${MAVERICKS_SDK_CACHE:-$HOME/Library/Caches/mavericks-sdk}"
URL="${MAVERICKS_SDK_URL:-$1}"
SHA="${MAVERICKS_SDK_SHA256:-$2}"
SDK="$CACHE/$4"
if [ ! -d "$SDK" ]; then
  # spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the SDK is
  #       published as shipped, stubs and all, on every host: never converted to .tbd.
  shipyard_fetch_pinned "$URL" "$SHA" "$CACHE" "$3"
fi
[ -d "$SDK/usr/lib" ] || { echo "SDK missing usr/lib: $SDK" >&2; exit 1; }
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- an SDK that
#       ships no SDKSettings.json gets the pin's, in a fresh cache or an old one alike; a correct one is
#       never rewritten.
if json="$(shipyard_sdk_settings_json "$ARCH")" \
   && ! printf '%s\n' "$json" | cmp -s - "$SDK/SDKSettings.json"; then
  j="$(mktemp "$SDK/.SDKSettings.json.XXXXXX")" || { echo "fetch_sdk: cannot write SDKSettings.json into $SDK" >&2; exit 1; }
  { printf '%s\n' "$json" > "$j" && chmod 644 "$j" && mv -f "$j" "$SDK/SDKSettings.json"; } \
    || { rm -f "$j"; echo "fetch_sdk: cannot write SDKSettings.json into $SDK" >&2; exit 1; }
fi
echo "$SDK"
