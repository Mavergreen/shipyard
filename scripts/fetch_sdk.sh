#!/bin/sh
# platform: host-agnostic
#   usage: fetch_sdk.sh [--arch x86_64|arm64]
#          Fetches + caches + checksum-verifies the family's PINNED SDK for one arch (sdk-pins.sh):
#          MacOSX10.9.sdk for x86_64 (the default), MacOSX11.3.sdk for arm64. Prints the SDK root on
#          stdout, exactly as its archive shipped it. A native 10.9
#          build uses this pin too, never xcrun's own SDK (MavericksToolchain.cmake).
#          MAVERICKS_SDK_SETTINGS_JSON=1 prints instead, for an arch whose pin has none (x86_64), a sibling
#          <cache>/with-sdk-settings-json/<SDK dir>: symlinks to the pinned SDK's entries plus the
#          SDKSettings.json Swift reads its SDK version from. The sibling is interim until clang22's
#          setup-sdk accepts that file in the pinned SDK.
#          Apple SDK bytes are never committed -- this is a build-time fetch. The cache default is per-machine and durable:
#          TMPDIR gets purged by macOS (stranding the path CMake cached at configure time).
#          MAVERICKS_SDK_URL / MAVERICKS_SDK_SHA256 override the selected arch's pin (the tests use
#          them); MAVERICKS_SDK_CACHE moves the cache. Exit 2 on a usage error, a bad
#          MAVERICKS_SDK_SETTINGS_JSON, or an arch with no pin.
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
case "${MAVERICKS_SDK_SETTINGS_JSON:-}" in
  ""|1) ;;
  *) echo "fetch_sdk: MAVERICKS_SDK_SETTINGS_JSON must be unset, empty or 1" >&2; exit 2 ;;
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
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the pinned
#       SDK stays as its archive shipped it; the SDKSettings.json v1.0.544 wrote into it goes, any other stays.
json="$(shipyard_sdk_settings_json "$ARCH" || true)"
if [ -n "$json" ] && [ -f "$SDK/SDKSettings.json" ] && printf '%s\n' "$json" | cmp -s - "$SDK/SDKSettings.json"; then
  rm -f "$SDK/SDKSettings.json" || { echo "fetch_sdk: cannot remove the stale SDKSettings.json from $SDK" >&2; exit 1; }
fi
if [ "${MAVERICKS_SDK_SETTINGS_JSON:-}" = 1 ] && [ -n "$json" ]; then
  SIB="$CACHE/with-sdk-settings-json"
  sibling_ok() {
    [ -f "$SIB/$4/SDKSettings.json" ] && [ ! -L "$SIB/$4/SDKSettings.json" ] \
      && printf '%s\n' "$json" | cmp -s - "$SIB/$4/SDKSettings.json" || return 1
    _want="$(find "$SDK" -mindepth 1 -maxdepth 1 ! -name SDKSettings.json -exec basename {} \; | LC_ALL=C sort)"
    _have="$(find "$SIB/$4" -mindepth 1 -maxdepth 1 ! -name SDKSettings.json -exec basename {} \; | LC_ALL=C sort)"
    [ "$_want" = "$_have" ] || return 1
    for _e in $_want; do
      [ -L "$SIB/$4/$_e" ] && [ "$(readlink "$SIB/$4/$_e")" = "$SDK/$_e" ] || return 1
    done
  }
  if ! sibling_ok "$@"; then
    mkdir -p "$SIB"
    t="$(mktemp -d "$SIB/.new.XXXXXX")" || { echo "fetch_sdk: cannot write into $SIB" >&2; exit 1; }
    mkdir "$t/$4"
    find "$SDK" -mindepth 1 -maxdepth 1 ! -name SDKSettings.json | while IFS= read -r e; do
      ln -s "$e" "$t/$4/$(basename "$e")"
    done
    printf '%s\n' "$json" > "$t/$4/SDKSettings.json" && chmod 644 "$t/$4/SDKSettings.json" \
      || { rm -rf "$t"; echo "fetch_sdk: cannot write SDKSettings.json into $SIB" >&2; exit 1; }
    if [ -e "$SIB/$4" ]; then mv "$SIB/$4" "$t/old" || true; fi
    mv "$t/$4" "$SIB/$4" 2>/dev/null || sibling_ok "$@" \
      || { rm -rf "$t"; echo "fetch_sdk: cannot install $SIB/$4" >&2; exit 1; }
    rm -rf "$t"
  fi
  SDK="$SIB/$4"
fi
echo "$SDK"
