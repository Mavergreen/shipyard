#!/bin/sh
# platform: host-agnostic
#   usage: build-updater-test.sh
#          scripts/build_updater.sh builds a registered product's updater from its inputs alone: a .app
#          with Contents/{Info.plist,MacOS/SHORT-updater,Frameworks/Sparkle.framework,Resources}, the
#          asked-for Mach-O arches (x86_64 at minos 10.9; also arm64 at minos 11.0 off 10.9, where
#          the toolchain allows a cross build), an Info.plist carrying the display name, version,
#          public key and the registry's bundle id and feed, and an executable holding the confirm
#          strings. The strings carry ", \, %, &, < and >, which must reach both intact. Fetches
#          clang22, the SDKs and Sparkle over the network.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
case "$(uname -s):$(uname -m)" in
  Linux:x86_64|Darwin:*) ;;
  *) echo "SKIP: clang22 has no release for $(uname -s) $(uname -m)"; exit 77 ;;
esac
_tmp="${TMPDIR:-/tmp}"
T="$(mktemp -d "${_tmp%/}/build-updater.XXXXXX")"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
CL="$(sh "$ROOT/scripts/fetch_clang22.sh" "$ROOT/components/clang22")"
SD="$(sh "$ROOT/scripts/fetch_stevedore.sh")"
printf 'widget dev.mavergreen.widget widget-repo\n' > "$T/names"
MAVERGREEN_PRODUCT_NAMES="$T/names"; export MAVERGREEN_PRODUCT_NAMES
printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n' > "$T/key.pub"
NAME='Mavericks Widget & <Co> "Q"'
TITLE='Widget for "Mavericks" updated'
BODY='New shells & <tabs> get the \new\ widget.'
LOGP='widget "%s" log'
build() {
  sh "$ROOT/scripts/build_updater.sh" --product widget --display-name "$NAME" \
    --confirm-title "$TITLE" --confirm-body "$BODY" --log-prefix "$LOGP" \
    --pubkey "$T/key.pub" --version 1.2.3-mavericks.4 --clang22-pin "$ROOT/components/clang22" "$@"
}

rc=0; build --generic-icon --out-dir "$T/u" > /dev/null 2> "$T/err" || rc=$?
[ "$rc" -eq 2 ] || fail "no --arch: exit $rc, want 2"
rc=0; build --arch x86_64 --icon "$T/key.pub" --generic-icon --out-dir "$T/u" > /dev/null 2> "$T/err" || rc=$?
[ "$rc" -eq 2 ] || fail "both --icon and --generic-icon: exit $rc, want 2"
rc=0; build --arch x86_64 --arch x86_64 --generic-icon --out-dir "$T/u" > /dev/null 2> "$T/err" || rc=$?
[ "$rc" -eq 2 ] || fail "--arch x86_64 twice: exit $rc, want 2"

archs="x86_64"; want='x86_64 10.9 '
[ "$(sh "$ROOT/scripts/mavericks_mode.sh")" = native ] || { archs="x86_64 arm64"; want='arm64 11.0 x86_64 10.9 '; }
set --
for a in $archs; do set -- "$@" --arch "$a"; done
out="$(build "$@" --generic-icon --out-dir "$T/out" 2> "$T/build.log")" || { cat "$T/build.log"; fail "build_updater.sh failed for$archs"; }
app="$T/out/widget-updater.app"
[ "$out" = "$(cd "$T/out" && pwd)/widget-updater.app" ] || fail "stdout must be the .app path alone, got '$out'"
for p in Contents/Info.plist Contents/MacOS/widget-updater Contents/Frameworks/Sparkle.framework Contents/Resources; do
  [ -e "$app/$p" ] || fail "the app has no $p"
done
exe="$app/Contents/MacOS/widget-updater"
got="$("$CL/bin/llvm-lipo" -info "$exe" | sed -n 's/.*: //p' | tr ' ' '\n' | grep . | LC_ALL=C sort | tr '\n' ' ')"
[ "$got" = "$(printf '%s\n' $archs | LC_ALL=C sort | tr '\n' ' ')" ] || fail "the executable's arches are '$got', want '$archs'"
slices="$(LIPO="$CL/bin/llvm-lipo" OTOOL="$CL/bin/llvm-otool" sh "$ROOT/scripts/macho-slices.sh" "$exe" | cut -d' ' -f1,3 | LC_ALL=C sort | tr '\n' ' ')"
[ "$slices" = "$want" ] || fail "the slices record '$slices', want '$want'"
"$CL/bin/llvm-objdump" --macho --private-headers "$exe" > "$T/lc"
grep -q 'LC_LOAD_DYLIB' "$T/lc" && grep -q 'Sparkle.framework' "$T/lc" || fail "llvm-objdump finds no Sparkle load command in $exe"
pl="$app/Contents/Info.plist"
for kv in 'CFBundleIdentifier=dev.mavergreen.widget.updater' "CFBundleName=$NAME" \
  'CFBundleExecutable=widget-updater' 'CFBundleShortVersionString=1.2.3-mavericks.4' 'CFBundleVersion=1.2.3.4' \
  'SUFeedURL=https://github.com/Mavergreen/widget-repo/releases/latest/download/widget.xml' \
  'SUPublicEDKey=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' 'CFBundleIconFile=' 'LSMinimumSystemVersion=10.9'; do
  v="$("$SD" plist get "$pl" "${kv%%=*}" 2>/dev/null || echo '<absent>')"
  [ "$v" = "${kv#*=}" ] || fail "Info.plist ${kv%%=*} is '$v', want '${kv#*=}'"
done
"$CL/bin/llvm-strings" "$exe" > "$T/strings"
grep -qF "$TITLE" "$T/strings" || fail 'the executable lacks the confirm title, with its quotes'
grep -qF "$BODY" "$T/strings" || fail 'the executable lacks the confirm body, with its backslashes'
grep -qF '[widget "%%s" log]' "$T/strings" || fail 'the executable lacks the log prefix, its quotes and percent sign escaped'
python3 -c 'import plistlib, sys; plistlib.load(open(sys.argv[1], "rb"))' "$app/Contents/Info.plist" \
  || fail 'Info.plist is not well-formed XML with &, < and > in the display name'
out2="$(build "$@" --generic-icon --out-dir "$T/out" 2> "$T/build.log")" || { cat "$T/build.log"; fail 'a second build into the same directory failed'; }
[ "$out2" = "$out" ] && [ -f "$exe" ] || fail 'a second build must replace the .app in place'
echo "PASS: build_updater.sh builds widget-updater.app for $archs with its inputs in Info.plist and the executable"
