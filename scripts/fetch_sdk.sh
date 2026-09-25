#!/bin/sh
# platform: host-agnostic
#   usage: fetch_sdk.sh [--arch x86_64|arm64]
#          Fetches + caches + checksum-verifies the family's PINNED SDK for one arch (sdk-pins.sh):
#          MacOSX10.9.sdk for x86_64 (the default), MacOSX11.3.sdk for arm64. Prints the SDK root on
#          stdout. A native 10.9 box uses xcrun's own 10.9 SDK when it has one (MavericksToolchain.cmake),
#          and this pin otherwise. Apple SDK bytes are never committed -- this is a build-time fetch. The cache default is per-machine and durable:
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
pin="$(mav_sdk_pin "$ARCH")" || { echo "fetch_sdk: no pinned SDK for arch '$ARCH' (x86_64 and arm64 have one)" >&2; exit 2; }
# shellcheck disable=SC2086  # the pin is four space-free words by construction
set -- $pin
CACHE="${MAVERICKS_SDK_CACHE:-$HOME/Library/Caches/mavericks-sdk}"
URL="${MAVERICKS_SDK_URL:-$1}"
SHA="${MAVERICKS_SDK_SHA256:-$2}"
SDK="$CACHE/$4"
if [ ! -d "$SDK" ]; then
  mav_fetch_pinned "$URL" "$SHA" "$CACHE" "$3"
  # platform: modern ld (Xcode 15+) warns for every ancient MH_DYLIB_STUB it reads. Where tapi
  #           exists (a modern host; never the 10.9 box), convert those stubs to .tbd once at
  #           extract time: same exported symbols, no warnings. Pinned to tbd-v4 (YAML): the default
  #           v5 is JSON, which some downstream tools can't parse.
  # platform: guarded macOS-only call -- xcrun is absent off macOS, so the `if` skips the whole conversion
  if TAPI=$(xcrun --find tapi 2>/dev/null); then
    LIBDIRS="$SDK/usr/lib $SDK/System/Library/Frameworks"
    find $LIBDIRS -type f \( -name '*.dylib' -o ! -name '*.*' \) | while IFS= read -r f; do
      # platform: guarded macOS-only call -- inside the `if TAPI=$(xcrun ...)` above, so only where xcrun exists
      [ "$(otool -h "$f" 2>/dev/null | awk 'NR==4 {print $5}')" = 9 ] || continue
      "$TAPI" stubify --filetype=tbd-v4 --delete-input-file "$f" 2>/dev/null || :  # unconvertible: keep stub
    done
    # platform: re-point symlinks whose target was converted. Loop to fixpoint: chains like
    #           libc.dylib -> libSystem.dylib -> libSystem.B.dylib need multiple passes.
    changed=1
    while [ "$changed" = 1 ]; do
      changed=0
      for l in $(find $LIBDIRS -type l); do
        [ -e "$l" ] && continue
        t=$(readlink "$l")
        case "$l" in *.dylib) new_l="${l%.dylib}.tbd" ;; *) new_l="$l.tbd" ;; esac
        case "$t" in *.dylib) new_t="${t%.dylib}.tbd" ;; *) new_t="$t.tbd" ;; esac
        case "$new_t" in /*) tgt="$SDK$new_t" ;; *) tgt="$(dirname "$l")/$new_t" ;; esac
        [ -e "$tgt" ] || continue
        ln -sf "$new_t" "$new_l"
        rm "$l"
        changed=1
      done
    done
  fi
fi
[ -d "$SDK/usr/lib" ] || { echo "SDK missing usr/lib: $SDK" >&2; exit 1; }
echo "$SDK"
