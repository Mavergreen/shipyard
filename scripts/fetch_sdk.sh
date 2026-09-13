#!/bin/sh
#   usage: fetch_sdk.sh
#          Fetches + caches + checksum-verifies MacOSX10.9.sdk. Prints the SDK root on stdout. Used
#          ONLY to cross-build for 10.9 from a modern host (a native 10.9 box uses its own system
#          SDK). Apple SDK bytes are never committed -- this is a build-time fetch. The cache default
#          is per-machine and durable: TMPDIR gets purged by macOS (stranding the path CMake cached
#          at configure time).
set -eu
. "$(dirname "$0")/mavericks_fetch.sh"
CACHE="${MAVERICKS_SDK_CACHE:-$HOME/Library/Caches/mavericks-sdk}"
URL="${MAVERICKS_SDK_URL:-https://github.com/phracker/MacOSX-SDKs/releases/download/11.3/MacOSX10.9.sdk.tar.xz}"
SHA="${MAVERICKS_SDK_SHA256:-fcf88ce8ff0dd3248b97f4eb81c7909f2cc786725de277f4d05a2b935cc49de0}"
SDK="$CACHE/MacOSX10.9.sdk"
if [ ! -d "$SDK" ]; then
  mav_fetch_pinned "$URL" "$SHA" "$CACHE" "MacOSX10.9.sdk.tar.xz"
  # platform: modern ld (Xcode 15+) warns for every ancient MH_DYLIB_STUB it reads. Where tapi
  #           exists (a modern host; never the 10.9 box), convert those stubs to .tbd once at
  #           extract time: same exported symbols, no warnings. Pinned to tbd-v4 (YAML): the default
  #           v5 is JSON, which some downstream tools can't parse.
  if TAPI=$(xcrun --find tapi 2>/dev/null); then
    LIBDIRS="$SDK/usr/lib $SDK/System/Library/Frameworks"
    find $LIBDIRS -type f \( -name '*.dylib' -o ! -name '*.*' \) | while IFS= read -r f; do
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
