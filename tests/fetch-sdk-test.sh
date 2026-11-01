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
leftovers() { find "$1" -mindepth 1 -name '.*'; }
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

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the pinned
#       10.9 SDK stays byte-for-byte the archive's (clang22's setup-sdk verifies the tree against it);
#       only a sibling made on request carries the SDKSettings.json Swift needs.
want_json='{"CanonicalName":"macosx10.9","MaximumDeploymentTarget":"10.9","Version":"10.9"}'
[ ! -e "$w/c2/MacOSX10.9.sdk/SDKSettings.json" ] || { echo "FAIL: the default fetch must leave no SDKSettings.json in the pinned 10.9 SDK"; exit 1; }
[ "$(cd "$w/c2" && find MacOSX10.9.sdk | LC_ALL=C sort)" = "$(cd "$w/src" && find MacOSX10.9.sdk | LC_ALL=C sort)" ] \
  || { echo "FAIL: the pinned 10.9 SDK's file list must equal the archive's"; exit 1; }
[ ! -e "$w/c1/MacOSX11.3.sdk/SDKSettings.json" ] || { echo "FAIL: the arm64 SDK ships its own SDKSettings.json; fetch_sdk.sh must not invent one"; exit 1; }
[ ! -e "$w/c2/with-sdk-settings-json" ] || { echo "FAIL: the default fetch must not make the sibling"; exit 1; }

mkdir -p "$w/c7/MacOSX10.9.sdk/usr/lib"
printf '%s\n' "$want_json" > "$w/c7/MacOSX10.9.sdk/SDKSettings.json"
out="$(MAVERICKS_SDK_CACHE="$w/c7" MAVERICKS_SDK_URL="file://$w/absent.tar" MAVERICKS_SDK_SHA256="$s109" sh "$S")" \
  || { echo "FAIL: an already-unpacked 10.9 SDK must be used without a download"; exit 1; }
[ "$out" = "$w/c7/MacOSX10.9.sdk" ] || { echo "FAIL: an already-unpacked SDK must print its dir, got: $out"; exit 1; }
[ ! -e "$w/c7/MacOSX10.9.sdk/SDKSettings.json" ] || { echo "FAIL: the SDKSettings.json v1.0.544 wrote must be removed"; exit 1; }
[ ! -e "$w/c7/MacOSX10.9.sdk.tar.xz" ] || { echo "FAIL: healing the SDK must not download it"; exit 1; }
[ -z "$(leftovers "$w/c7")" ] || { echo "FAIL: healing the SDK left temp entries"; exit 1; }

printf '{"Version":"10.9"}\n' > "$w/c7/MacOSX10.9.sdk/SDKSettings.json"
MAVERICKS_SDK_CACHE="$w/c7" MAVERICKS_SDK_URL="file://$w/absent.tar" MAVERICKS_SDK_SHA256="$s109" sh "$S" >/dev/null \
  || { echo "FAIL: a foreign SDKSettings.json must not fail the fetch"; exit 1; }
[ "$(cat "$w/c7/MacOSX10.9.sdk/SDKSettings.json")" = '{"Version":"10.9"}' ] || { echo "FAIL: a foreign SDKSettings.json must be left alone"; exit 1; }

sib() { MAVERICKS_SDK_SETTINGS_JSON=1 MAVERICKS_SDK_CACHE="$w/c9" MAVERICKS_SDK_URL="file://$t109" MAVERICKS_SDK_SHA256="$s109" sh "$S" "$@"; }
out="$(sib)" || { echo "FAIL: MAVERICKS_SDK_SETTINGS_JSON=1 must succeed"; exit 1; }
[ "$out" = "$w/c9/with-sdk-settings-json/MacOSX10.9.sdk" ] || { echo "FAIL: the opt-in must print the sibling, got: $out"; exit 1; }
[ -f "$out/SDKSettings.json" ] && [ ! -L "$out/SDKSettings.json" ] || { echo "FAIL: the sibling's SDKSettings.json must be a real file"; exit 1; }
[ "$(cat "$out/SDKSettings.json")" = "$want_json" ] && [ "$(wc -l < "$out/SDKSettings.json" | tr -d ' ')" = 1 ] \
  || { echo "FAIL: the sibling's SDKSettings.json must be the pin's JSON plus a newline"; exit 1; }
[ -L "$out/usr" ] && [ "$(readlink "$out/usr")" = "$w/c9/MacOSX10.9.sdk/usr" ] \
  || { echo "FAIL: the sibling's entries must be symlinks to the pinned SDK's, absolute"; exit 1; }
[ -f "$out/usr/lib/libSystem.tbd" ] || { echo "FAIL: the sibling must resolve usr/lib through the symlink"; exit 1; }
[ ! -e "$w/c9/MacOSX10.9.sdk/SDKSettings.json" ] \
  && [ "$(cd "$w/c9" && find MacOSX10.9.sdk | LC_ALL=C sort)" = "$(cd "$w/src" && find MacOSX10.9.sdk | LC_ALL=C sort)" ] \
  || { echo "FAIL: the opt-in must leave the pinned SDK pristine"; exit 1; }
[ -z "$(leftovers "$w/c9")" ] || { echo "FAIL: the opt-in left temp entries: $(leftovers "$w/c9")"; exit 1; }
ino="$(ls -i "$out/SDKSettings.json" | awk '{print $1}')"
sib >/dev/null || { echo "FAIL: a repeated opt-in must succeed"; exit 1; }
[ "$(ls -i "$out/SDKSettings.json" | awk '{print $1}')" = "$ino" ] || { echo "FAIL: a correct sibling must not be rebuilt"; exit 1; }

printf '{"Version":' > "$out/SDKSettings.json"
sib >/dev/null || { echo "FAIL: the opt-in must repair a sibling with wrong JSON"; exit 1; }
[ "$(cat "$out/SDKSettings.json")" = "$want_json" ] || { echo "FAIL: the opt-in must replace a sibling's wrong JSON"; exit 1; }
rm "$out/usr"
sib >/dev/null || { echo "FAIL: the opt-in must repair a sibling missing an entry"; exit 1; }
[ -f "$out/usr/lib/libSystem.tbd" ] || { echo "FAIL: the opt-in must restore a missing sibling entry"; exit 1; }
ln -sfn /nonexistent "$out/usr"
sib >/dev/null || { echo "FAIL: the opt-in must repair a sibling with a stale entry"; exit 1; }
[ -f "$out/usr/lib/libSystem.tbd" ] || { echo "FAIL: the opt-in must restore a stale sibling entry"; exit 1; }

out="$(MAVERICKS_SDK_SETTINGS_JSON=1 MAVERICKS_SDK_CACHE="$w/c10" MAVERICKS_SDK_URL="file://$t113" MAVERICKS_SDK_SHA256="$s113" sh "$S" --arch arm64)" \
  || { echo "FAIL: the opt-in on arm64 must succeed"; exit 1; }
[ "$out" = "$w/c10/MacOSX11.3.sdk" ] || { echo "FAIL: the opt-in on arm64 must print the pristine 11.3 SDK, got: $out"; exit 1; }
[ ! -e "$w/c10/with-sdk-settings-json" ] || { echo "FAIL: the opt-in on arm64 must make no sibling"; exit 1; }

for v in 0 yes true; do
  rc=0; MAVERICKS_SDK_SETTINGS_JSON=$v MAVERICKS_SDK_CACHE="$w/c11" sh "$S" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || { echo "FAIL: MAVERICKS_SDK_SETTINGS_JSON=$v is a usage error (2), got $rc"; exit 1; }
done
MAVERICKS_SDK_SETTINGS_JSON= MAVERICKS_SDK_CACHE="$w/c2" MAVERICKS_SDK_URL="file://$t109" MAVERICKS_SDK_SHA256="$s109" sh "$S" >/dev/null \
  || { echo "FAIL: an empty MAVERICKS_SDK_SETTINGS_JSON is the same as unset"; exit 1; }

mkdir -p "$w/c8/MacOSX11.3.sdk/usr/lib"
printf '{"Version":"11.3"}' > "$w/c8/MacOSX11.3.sdk/SDKSettings.json"
MAVERICKS_SDK_CACHE="$w/c8" sh "$S" --arch arm64 >/dev/null || { echo "FAIL: a cached arm64 SDK must be used"; exit 1; }
[ "$(cat "$w/c8/MacOSX11.3.sdk/SDKSettings.json")" = '{"Version":"11.3"}' ] \
  || { echo "FAIL: the arm64 SDK's own SDKSettings.json must be left as shipped"; exit 1; }

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

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the SDK keeps
#       its MH_DYLIB_STUB form on every host. No host asks xcrun or runs tapi,
#       even where both exist. Fake sw_vers, xcrun, otool and tapi on PATH, logging, so this runs anywhere.
mkdir -p "$w/bin"
printf '#!/bin/sh\necho "$FAKE_OS"\n' > "$w/bin/sw_vers"
printf '#!/bin/sh\necho "xcrun $*" >> "%s/tools.log"\necho "%s/bin/tapi"\n' "$w" "$w" > "$w/bin/xcrun"
printf '#!/bin/sh\necho "otool $*" >> "%s/tools.log"\nprintf "a\\nb\\nc\\n0 0 0 0 9\\n"\n' "$w" > "$w/bin/otool"
printf '#!/bin/sh\necho "tapi $*" >> "%s/tools.log"\n' "$w" > "$w/bin/tapi"
chmod +x "$w/bin/sw_vers" "$w/bin/xcrun" "$w/bin/otool" "$w/bin/tapi"
mkdir -p "$w/stub/MacOSX10.9.sdk/usr/lib/system" "$w/stub/MacOSX10.9.sdk/System/Library/Frameworks/Foo.framework"
printf 'stub' > "$w/stub/MacOSX10.9.sdk/usr/lib/libSystem.B.dylib"
ln -s libSystem.B.dylib "$w/stub/MacOSX10.9.sdk/usr/lib/libSystem.dylib"
printf 'stub' > "$w/stub/MacOSX10.9.sdk/usr/lib/system/libsystem_c.dylib"
printf 'stub' > "$w/stub/MacOSX10.9.sdk/System/Library/Frameworks/Foo.framework/Foo"
( cd "$w/stub" && tar -czf "$w/stub.tar" MacOSX10.9.sdk )
sstub="$(shasum -a 256 "$w/stub.tar" | awk '{print $1}')"
for os in 10.9.5 13.0; do
  : > "$w/tools.log"
  FAKE_OS=$os PATH="$w/bin:$PATH" MAVERGREEN_PROGRESS=1 MAVERICKS_SDK_CACHE="$w/c-$os" MAVERICKS_SDK_URL="file://$w/stub.tar" MAVERICKS_SDK_SHA256="$sstub" \
    sh "$S" > /dev/null 2> "$w/err-$os" || { echo "FAIL: a first fetch on $os must succeed"; exit 1; }
  [ ! -s "$w/tools.log" ] || { echo "FAIL: a first fetch on $os must run no tapi, xcrun or otool, ran: $(cat "$w/tools.log")"; exit 1; }
  d="$( (cd "$w/stub" && find MacOSX10.9.sdk) | LC_ALL=C sort)"
  [ "$(cd "$w/c-$os" && find MacOSX10.9.sdk | LC_ALL=C sort)" = "$d" ] \
    || { echo "FAIL: a first fetch on $os must keep the SDK's files as shipped, got: $(cd "$w/c-$os" && find MacOSX10.9.sdk -name '*.tbd')"; exit 1; }
  [ "$(cat "$w/c-$os/MacOSX10.9.sdk/usr/lib/libSystem.B.dylib")" = stub ] && [ -L "$w/c-$os/MacOSX10.9.sdk/usr/lib/libSystem.dylib" ] \
    || { echo "FAIL: a first fetch on $os must keep libSystem's stub and its link unchanged"; exit 1; }
  ! grep -qi 'tbd\|stub' "$w/err-$os" || { echo "FAIL: progress on $os must say nothing about converting, got: $(cat "$w/err-$os")"; exit 1; }
done

# platform: concurrent fetches into one cache (six test files share it once they run in parallel) must
#           each print the SDK, with no half-written tarball or half-moved tree left behind.
MAVERICKS_SDK_CACHE="$w/c6" MAVERICKS_SDK_URL="file://$t109" MAVERICKS_SDK_SHA256="$s109" sh "$S" > "$w/o1" & p1=$!
MAVERICKS_SDK_CACHE="$w/c6" MAVERICKS_SDK_URL="file://$t109" MAVERICKS_SDK_SHA256="$s109" sh "$S" > "$w/o2" & p2=$!
r1=0; r2=0; wait "$p1" || r1=$?; wait "$p2" || r2=$?
[ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] || { echo "FAIL: concurrent cold fetches must both exit 0, got $r1 and $r2"; exit 1; }
[ "$(cat "$w/o1")" = "$w/c6/MacOSX10.9.sdk" ] && [ "$(cat "$w/o2")" = "$w/c6/MacOSX10.9.sdk" ] \
  || { echo "FAIL: concurrent cold fetches must both print the SDK dir, got: $(cat "$w/o1") and $(cat "$w/o2")"; exit 1; }
[ -f "$w/c6/MacOSX10.9.sdk/usr/lib/libSystem.tbd" ] || { echo "FAIL: concurrent cold fetch lost the SDK contents"; exit 1; }
[ -z "$(leftovers "$w/c6")" ] || { echo "FAIL: concurrent cold fetch left temp entries: $(leftovers "$w/c6")"; exit 1; }

echo "PASS: fetch-sdk"
