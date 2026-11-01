#!/bin/sh
# platform: host-agnostic
#   usage: updater-linux-test.sh
#          updater builds on Linux: shipyard's universal Sparkle updater, cross-built by clang22 one arch per
#          configure and merged with llvm-lipo (tests/lib/build-updater.sh), is a Mach-O app with
#          Contents/MacOS/shipyard-updater, an x86_64 slice recording minos 10.9 and an arm64 slice
#          recording minos 11.0, and a Sparkle.framework that assert_sparkle_pristine.sh accepts. With
#          UPDATER_TEST_OUT set it leaves the app there as shipyard-updater-linux.tar, for CI to upload.
#          Fetches clang22's Linux archive, both SDKs and Sparkle over the network.
set -eu
[ "$(uname -s)" = Linux ] || { echo 'SKIP: the Linux updater build'; exit 77; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
_tmp="${TMPDIR:-/tmp}"
T="$(mktemp -d "${_tmp%/}/updater-linux.XXXXXX")"; trap 'rm -rf "$T"' EXIT
CL="$(sh "$ROOT/scripts/fetch_clang22.sh" "$ROOT/components/clang22")"
fail() { echo "FAIL: $*"; exit 1; }
app="$T/shipyard-updater.app"

sh "$ROOT/tests/lib/build-updater.sh" --arch x86_64 --arch arm64 --out "$app" > "$T/build.log" 2>&1 \
  || { cat "$T/build.log"; fail 'build-updater.sh could not cross-build the universal updater on Linux'; }
exe="$app/Contents/MacOS/shipyard-updater"
[ -f "$exe" ] || fail "the app has no Contents/MacOS/shipyard-updater"
[ -f "$app/Contents/Info.plist" ] || fail 'the app has no Contents/Info.plist'
archs="$("$CL/bin/llvm-lipo" -info "$exe" 2>/dev/null | sed -n 's/.*: //p')" || :
[ -n "$archs" ] || fail "$exe is not Mach-O"
case " $archs " in *' x86_64 '*) ;; *) fail "the updater has no x86_64 slice: '$archs'" ;; esac
case " $archs " in *' arm64 '*) ;; *) fail "the updater has no arm64 slice: '$archs'" ;; esac
for s in x86_64:10.9 arm64:11.0; do
  a="${s%%:*}"; floor="${s#*:}"
  "$CL/bin/llvm-otool" -arch "$a" -l "$exe" > "$T/lc-$a"
  grep -E "(version|minos) $floor\$" "$T/lc-$a" > /dev/null || fail "the $a slice must record minos $floor"
done
fw="$app/Contents/Frameworks/Sparkle.framework"
[ -d "$fw" ] || fail 'the app embeds no Sparkle.framework'
sh "$ROOT/scripts/assert_sparkle_pristine.sh" "$fw" "$(sh "$ROOT/scripts/fetch_sparkle_framework.sh")" \
  || fail 'the embedded Sparkle.framework is not the pinned one, byte for byte and link for link'
if [ -n "${UPDATER_TEST_OUT:-}" ]; then
  mkdir -p "$UPDATER_TEST_OUT"
  tar -cf "$UPDATER_TEST_OUT/shipyard-updater-linux.tar" -C "$T" shipyard-updater.app
fi
echo 'PASS: updater builds on Linux: universal Mach-O app, minos 10.9 and 11.0, pristine Sparkle'
