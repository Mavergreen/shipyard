#!/bin/sh
# platform: host-agnostic
#   usage: fetch-sdk-test.sh
#          fetch_sdk.sh selects the pin by arch, verifies it, and fails closed -- against file:// fixtures.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning"
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/fetch_sdk.sh"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/fetch-sdk-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fixture() {  # $1 = sdk dir name; prints "<tarball> <sha256>"
  mkdir -p "$w/src/$1/usr/lib"; : > "$w/src/$1/usr/lib/libSystem.tbd"
  ( cd "$w/src" && tar -czf "$w/$1.tar" "$1" )
  printf '%s %s\n' "$w/$1.tar" "$(shasum -a 256 "$w/$1.tar" | awk '{print $1}')"
}
set -- $(fixture MacOSX11.3.sdk); t113="$1"; s113="$2"
set -- $(fixture MacOSX10.9.sdk); t109="$1"; s109="$2"

out="$(MAVERICKS_SDK_CACHE="$w/c1" MAVERICKS_SDK_URL="file://$t113" MAVERICKS_SDK_SHA256="$s113" sh "$S" --arch arm64)" \
  || { echo "FAIL: --arch arm64 with a verifying fixture must succeed"; exit 1; }
[ "$out" = "$w/c1/MacOSX11.3.sdk" ] || { echo "FAIL: --arch arm64 must print the 11.3 SDK dir, got: $out"; exit 1; }

out="$(MAVERICKS_SDK_CACHE="$w/c2" MAVERICKS_SDK_URL="file://$t109" MAVERICKS_SDK_SHA256="$s109" sh "$S")" \
  || { echo "FAIL: no --arch must default to x86_64 and succeed"; exit 1; }
[ "$out" = "$w/c2/MacOSX10.9.sdk" ] || { echo "FAIL: the default must be the 10.9 SDK dir, got: $out"; exit 1; }

if MAVERICKS_SDK_CACHE="$w/c3" MAVERICKS_SDK_URL="file://$t113" MAVERICKS_SDK_SHA256="$s109" sh "$S" --arch arm64 >/dev/null 2>&1; then
  echo "FAIL: a checksum mismatch must fail"; exit 1
fi
[ ! -e "$w/c3/MacOSX11.3.sdk" ] || { echo "FAIL: a checksum mismatch must leave no SDK dir behind"; exit 1; }
[ ! -e "$w/c3/MacOSX11.3.sdk.tar.xz" ] \
  || { echo "FAIL: a checksum mismatch must not keep the bad tarball, or every later run fails on it"; exit 1; }

rc=0; sh "$S" --arch i386 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: an arch with no pin is a usage error (2), got $rc"; exit 1; }
rc=0; sh "$S" --arch >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: --arch with no value is a usage error (2), got $rc"; exit 1; }

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- a consumer
#       that copies fetch_sdk.sh and mavericks_fetch.sh into its own libexec/ but not sdk-pins.sh gets a
#       usage error naming the missing file, not the shell's own "sdk-pins.sh: not found".
mkdir -p "$w/lonely"
cp "$S" "$here/../scripts/mavericks_fetch.sh" "$w/lonely/"
rc=0; err="$(sh "$w/lonely/fetch_sdk.sh" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: fetch_sdk.sh without sdk-pins.sh beside it must exit 2, got $rc: $err"; exit 1; }
printf '%s' "$err" | grep -q 'sdk-pins\.sh is missing' \
  || { echo "FAIL: fetch_sdk.sh without sdk-pins.sh must say sdk-pins.sh is missing, got: $err"; exit 1; }

# platform: OS X 10.9 has no tapi and, without the Command Line Tools, no xcrun to ask: a first fetch there
#           asks nothing; a newer macOS still asks xcrun for tapi. Fake sw_vers and xcrun, logging, on PATH.
mkdir -p "$w/bin"
printf '#!/bin/sh\necho "xcrun $*" >> "%s/xcrun.log"\nexit 1\n' "$w" > "$w/bin/xcrun"
printf '#!/bin/sh\necho "$FAKE_OS"\n' > "$w/bin/sw_vers"; chmod +x "$w/bin/xcrun" "$w/bin/sw_vers"
: > "$w/xcrun.log"
FAKE_OS=10.9.5 PATH="$w/bin:$PATH" MAVERICKS_SDK_CACHE="$w/c4" MAVERICKS_SDK_URL="file://$t109" MAVERICKS_SDK_SHA256="$s109" \
  sh "$S" > /dev/null || { echo "FAIL: a first fetch on 10.9 must succeed"; exit 1; }
[ ! -s "$w/xcrun.log" ] || { echo "FAIL: a first fetch on 10.9 asked xcrun: $(cat "$w/xcrun.log")"; exit 1; }
FAKE_OS=15.6 PATH="$w/bin:$PATH" MAVERICKS_SDK_CACHE="$w/c5" MAVERICKS_SDK_URL="file://$t109" MAVERICKS_SDK_SHA256="$s109" \
  sh "$S" > /dev/null || { echo "FAIL: a first fetch on 15.6 must succeed"; exit 1; }
[ "$(cat "$w/xcrun.log")" = "xcrun --find tapi" ] || { echo "FAIL: a first fetch on 15.6 must ask xcrun for tapi, asked: $(cat "$w/xcrun.log")"; exit 1; }

# platform: concurrent fetches into one cache (six test files share it once they run in parallel) must
#           each print the SDK, with no half-written tarball or half-moved tree left behind.
leftovers() { find "$1" -mindepth 1 -name '.*'; }
MAVERICKS_SDK_CACHE="$w/c6" MAVERICKS_SDK_URL="file://$t109" MAVERICKS_SDK_SHA256="$s109" sh "$S" > "$w/o1" & p1=$!
MAVERICKS_SDK_CACHE="$w/c6" MAVERICKS_SDK_URL="file://$t109" MAVERICKS_SDK_SHA256="$s109" sh "$S" > "$w/o2" & p2=$!
r1=0; r2=0; wait "$p1" || r1=$?; wait "$p2" || r2=$?
[ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] || { echo "FAIL: concurrent cold fetches must both exit 0, got $r1 and $r2"; exit 1; }
[ "$(cat "$w/o1")" = "$w/c6/MacOSX10.9.sdk" ] && [ "$(cat "$w/o2")" = "$w/c6/MacOSX10.9.sdk" ] \
  || { echo "FAIL: concurrent cold fetches must both print the SDK dir, got: $(cat "$w/o1") and $(cat "$w/o2")"; exit 1; }
[ -f "$w/c6/MacOSX10.9.sdk/usr/lib/libSystem.tbd" ] || { echo "FAIL: concurrent cold fetch lost the SDK contents"; exit 1; }
[ -z "$(leftovers "$w/c6")" ] || { echo "FAIL: concurrent cold fetch left temp entries: $(leftovers "$w/c6")"; exit 1; }

# platform: the .tbd conversion runs on the private extract dir BEFORE the SDK is published, so a second
#           process that finds the SDK never sees a half-converted one. Fake sw_vers, xcrun, otool and
#           tapi on PATH so this runs on the 10.9 box (no tapi) and on Linux alike.
mkdir -p "$w/src/MacOSX10.9.sdk/usr/lib" "$w/src/MacOSX10.9.sdk/System/Library/Frameworks" "$w/bin2"
: > "$w/src/MacOSX10.9.sdk/usr/lib/libfoo.dylib"; : > "$w/src/MacOSX10.9.sdk/usr/lib/libbar.dylib"; : > "$w/src/MacOSX10.9.sdk/usr/lib/notes.txt"; mkdir -p "$w/src/MacOSX10.9.sdk/System/Library/Frameworks/Foo.framework"; : > "$w/src/MacOSX10.9.sdk/System/Library/Frameworks/Foo.framework/Foo"
( cd "$w/src" && tar -czf "$w/conv.tar" MacOSX10.9.sdk )
sconv="$(shasum -a 256 "$w/conv.tar" | awk '{print $1}')"
printf '#!/bin/sh\necho 13.0\n' > "$w/bin2/sw_vers"
printf '#!/bin/sh\necho "%s/bin2/tapi"\n' "$w" > "$w/bin2/xcrun"
printf '#!/bin/sh\ncase "$2" in *libbar*) n=6 ;; *) n=9 ;; esac\nprintf "a\\nb\\nc\\n0 0 0 0 %%s\\n" "$n"\n' > "$w/bin2/otool"
printf '#!/bin/sh\nfor a; do last=$a; done\necho "$last" >> "%s/tapi.log"\n' "$w" > "$w/bin2/tapi"
chmod +x "$w/bin2/sw_vers" "$w/bin2/xcrun" "$w/bin2/otool" "$w/bin2/tapi"
: > "$w/tapi.log"
PATH="$w/bin2:$PATH" MAVERICKS_SDK_CACHE="$w/c7" MAVERICKS_SDK_URL="file://$w/conv.tar" MAVERICKS_SDK_SHA256="$sconv" \
  sh "$S" > /dev/null || { echo "FAIL: a fetch that converts stubs must succeed"; exit 1; }
[ -s "$w/tapi.log" ] || { echo "FAIL: the stub conversion never ran tapi"; exit 1; }
[ -z "$(grep -v '/\.mav-extract\.' "$w/tapi.log")" ] \
  || { echo "FAIL: tapi must convert only inside the private extract dir, before publishing; it touched: $(grep -v '/\.mav-extract\.' "$w/tapi.log")"; exit 1; }

# platform: MAVERGREEN_PROGRESS=1 adds stub-conversion lines to stderr (not a terminal here, so whole lines only);
#           unset, stderr is exactly what it was before. The fixture above has 3 files the `find` lists
#           (libfoo.dylib, libbar.dylib, Foo.framework/Foo); the fake otool calls two of them stubs.
PATH="$w/bin2:$PATH" MAVERICKS_SDK_CACHE="$w/c8" MAVERICKS_SDK_URL="file://$w/conv.tar" MAVERICKS_SDK_SHA256="$sconv" \
  sh "$S" > /dev/null 2> "$w/err-off" || { echo "FAIL: a fetch that converts stubs must succeed (switch unset)"; exit 1; }
PATH="$w/bin2:$PATH" MAVERGREEN_PROGRESS=1 MAVERICKS_SDK_CACHE="$w/c9" MAVERICKS_SDK_URL="file://$w/conv.tar" MAVERICKS_SDK_SHA256="$sconv" \
  sh "$S" > /dev/null 2> "$w/err-on" || { echo "FAIL: a fetch that converts stubs must succeed (switch on)"; exit 1; }
# platform: byte-identity -- the literal is what fetch_sdk.sh printed to stderr before this change on the same run (only mav_fetch_verified's shasum line); temp names are normalised.
[ "$(sed "s|$w/c8|CACHE|; s|\.[A-Za-z0-9]\{6\}: OK\$|.XXXXXX: OK|" "$w/err-off")" = 'CACHE/.MacOSX10.9.sdk.tar.xz.XXXXXX: OK' ] \
  || { echo "FAIL: with the switch unset stderr must be unchanged, got: $(cat "$w/err-off")"; exit 1; }
grep -qx 'fetch_sdk: converting stubs to \.tbd (3 files to check)' "$w/err-on" \
  || { echo "FAIL: switch on must announce 3 files to check, got: $(cat "$w/err-on")"; exit 1; }
grep -qx 'fetch_sdk: converted 2 stubs' "$w/err-on" \
  || { echo "FAIL: switch on must report 2 stubs converted, got: $(cat "$w/err-on")"; exit 1; }
[ -z "$(tr -d -c '\r' < "$w/err-on")" ] || { echo "FAIL: a non-terminal must get whole lines, never \\r"; exit 1; }
[ -z "$(leftovers "$w/c9")" ] \
  || { echo "FAIL: the conversion left temp entries in the cache: $(leftovers "$w/c9")"; exit 1; }

# platform: no tapi (the 10.9 path, and Linux): nothing is added, switch or no switch.
FAKE_OS=10.9.5 PATH="$w/bin:$PATH" MAVERGREEN_PROGRESS=1 MAVERICKS_SDK_CACHE="$w/c10" MAVERICKS_SDK_URL="file://$t109" MAVERICKS_SDK_SHA256="$s109" \
  sh "$S" > /dev/null 2> "$w/err-notapi" || { echo "FAIL: a first fetch on 10.9 with the switch on must succeed"; exit 1; }
! grep -q '^fetch_sdk:' "$w/err-notapi" || { echo "FAIL: without tapi the switch adds no fetch_sdk lines, got: $(cat "$w/err-notapi")"; exit 1; }

echo "PASS: fetch-sdk"
