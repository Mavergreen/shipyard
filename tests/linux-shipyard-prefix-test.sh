#!/bin/sh
# platform: host-agnostic
#   usage: linux-shipyard-prefix-test.sh
#          scripts/install-shipyard-prefix.sh, install@v1's Linux install, lays down exactly the pkg's
#          opt/mavergreen/shipyard: the same files, links and bytes as the Payload of a pkg
#          package-pkg.sh builds from the same checkout. The pkg's macOS-only parts are named here:
#          the updater app and its LaunchAgent outside the prefix, and the manifest's appcast and
#          outside, which name them. It links the exported names into opt/mavergreen/bin,
#          replaces an older install whole, and without root, sudo or a writable root installs per
#          user, its presets naming that prefix. Exit 0 clean, 1 on failure, 77 with no cmake.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
S="$root/scripts"
command -v cmake > /dev/null 2>&1 || { echo "SKIP: no cmake"; exit 77; }
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/linux-shipyard-prefix.XXXXXX")"
trap 'chmod -R u+w "$w" 2>/dev/null; rm -rf "$w"' EXIT
w="$(cd -P "$w" && pwd)"
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
rel=opt/mavergreen/shipyard
MAVERGREEN_REPO_ROOT="$root"; GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-Mavergreen/shipyard}"
export MAVERGREEN_REPO_ROOT GITHUB_REPOSITORY
idf() { sh "$S/updater-identity.sh" "$1" shipyard; }
SOURCE_DATE_EPOCH=1700000000; export SOURCE_DATE_EPOCH

mkdir "$w/r"
SUDO= sh "$S/install-shipyard-prefix.sh" --root "$w/r" --version 1.2.3 > "$w/out" 2> "$w/err" \
  || { echo "FAIL: install-shipyard-prefix.sh failed:"; sed 's/^/    | /' "$w/err"; exit 1; }
[ "$(cat "$w/out")" = "$w/r/$rel" ] || fail "it must print the prefix it installed, $w/r/$rel; got $(cat "$w/out")"

sh "$S/stage-shipyard-prefix.sh" --stage "$w/s" --build "$w/b" --version 1.2.3 > /dev/null 2> "$w/stage.log" \
  || { echo "FAIL: stage-shipyard-prefix.sh failed:"; sed 's/^/    | /' "$w/stage.log"; exit 1; }
app="$w/app/$(idf app | sed 's|.*/||')"
mkdir -p "$app/Contents/MacOS"
printf '#!/bin/sh\n' > "$app/Contents/MacOS/shipyard-updater"; chmod +x "$app/Contents/MacOS/shipyard-updater"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>$(idf bundle-id)</string>
  <key>SUFeedURL</key>
  <string>$(idf feed)</string>
</dict>
</plist>
EOF
sh "$S/package-pkg.sh" --shipyard-prefix "$w/s/$rel" --app "$app" --version 1.2.3 --dist "$w/o" > "$w/pkg.log" 2>&1 \
  || { echo "FAIL: package-pkg.sh failed:"; sed 's/^/    | /' "$w/pkg.log"; exit 1; }
STEVEDORE="$(sh "$S/fetch_stevedore.sh")"
sh "$S/pkg_read.sh" payload "$w/o/shipyard-1.2.3.pkg" dev.mavergreen.shipyard "$w/p" \
  || { echo "FAIL: could not unpack the pkg's Payload"; exit 1; }

listing() {  # $1 = tree: every entry, a link with its target, a file with its mode and checksum
  ( cd "$1" && find . ! -name mavergreen.plist | LC_ALL=C sort | while IFS= read -r e; do
      if [ -h "$e" ]; then printf '%s -> %s\n' "$e" "$(readlink "$e")"
      elif [ -d "$e" ]; then printf '%s/\n' "$e"
      else printf '%s %s %s\n' "$e" "$(ls -l "$e" | cut -c1-10)" "$(cksum < "$e")"; fi
    done )
}
listing "$w/p/$rel" > "$w/pkg.list"
listing "$w/r/$rel" > "$w/linux.list"
[ -s "$w/pkg.list" ] && [ "$(grep -c . "$w/pkg.list")" -gt 50 ] || fail "the pkg's prefix lists almost nothing: $(grep -c . "$w/pkg.list")"
if ! cmp -s "$w/pkg.list" "$w/linux.list"; then
  fail "the Linux-installed prefix differs from the pkg's Payload (< pkg, > Linux):"
  diff "$w/pkg.list" "$w/linux.list" | sed 's/^/    | /' | head -40
fi

app_rel="$(idf app)"
agent="Library/LaunchAgents/$(idf agent-label).plist"
( cd "$w/p" && find . \( -type f -o -type l \) ) | sed 's|^\./||' | grep -v "^$rel/" \
  | awk -v a="$app_rel/" -v l="$agent" 'index($0, a) == 1 { print a; next } { print }' | LC_ALL=C sort -u > "$w/outside"
printf '%s\n%s\n' "$agent" "$app_rel/" | LC_ALL=C sort > "$w/outside.want"
cmp -s "$w/outside" "$w/outside.want" || { fail "the pkg's macOS-only parts are its updater app and LaunchAgent, and nothing else outside the prefix; got:"; sed 's/^/    | /' "$w/outside"; }

strip() {  # $1 = mavergreen.plist, less the appcast and outside the macOS updater fills
  awk '/<key>appcast<\/key>/ { getline; next }
       /<key>outside<\/key>/ { skip = 1; next }
       skip && /<\/array>/ { skip = 0; next }
       !skip' "$1"
}
strip "$w/p/$rel/mavergreen.plist" > "$w/pkg.plist"
strip "$w/r/$rel/mavergreen.plist" > "$w/linux.plist"
cmp -s "$w/pkg.plist" "$w/linux.plist" \
  || { fail "the manifests differ beyond appcast and outside:"; diff "$w/pkg.plist" "$w/linux.plist" | sed 's/^/    | /'; }
outside() {  # $1 = mavergreen.plist: its outside array, one entry a line
  awk '/<key>outside<\/key>/ { on = 1; next } on && /<\/array>/ { exit }
       on && /<string>/ { sub(/.*<string>/, ""); sub(/<\/string>.*/, ""); print }' "$1"
}
[ -z "$("$STEVEDORE" plist get "$w/r/$rel/mavergreen.plist" appcast 2>/dev/null || echo unreadable)" ] \
  || fail "the Linux manifest installs no updater, so its appcast must be empty"
[ -z "$(outside "$w/r/$rel/mavergreen.plist")" ] \
  || fail "the Linux manifest installs nothing outside the prefix, so its outside must be empty; got $(outside "$w/r/$rel/mavergreen.plist")"
[ "$("$STEVEDORE" plist get "$w/p/$rel/mavergreen.plist" appcast 2>/dev/null || :)" = "$(idf feed)" ] \
  || fail "the pkg's manifest must name shipyard's feed as its appcast"
[ "$(outside "$w/p/$rel/mavergreen.plist" | sed 's|^\(.*\.app\)$|\1/|' | LC_ALL=C sort)" = "$(cat "$w/outside.want")" ] \
  || fail "the pkg's manifest must list the updater app and LaunchAgent as outside; got $(outside "$w/p/$rel/mavergreen.plist")"

farm="$(cd "$w/r/opt/mavergreen/bin" && for f in *; do printf '%s -> %s\n' "$f" "$(readlink "$f")"; done)"
want="shipyard-cmake -> ../shipyard/bin/shipyard-cmake
shipyard-cpack -> ../shipyard/bin/shipyard-cpack
shipyard-ctest -> ../shipyard/bin/shipyard-ctest"
[ "$farm" = "$want" ] || fail "opt/mavergreen/bin must link exactly the three launchers, never bare cmake/ctest/cpack; got
$farm"

SUDO= sh "$S/install-shipyard-prefix.sh" --root "$w/r" --version 1.2.4 > /dev/null 2> "$w/err" \
  || { fail "a second install over the first failed:"; sed 's/^/    | /' "$w/err"; }
[ "$("$STEVEDORE" plist get "$w/r/$rel/mavergreen.plist" version 2>/dev/null || :)" = 1.2.4 ] \
  || fail "a second install must replace the first; the manifest still says $("$STEVEDORE" plist get "$w/r/$rel/mavergreen.plist" version 2>/dev/null || :)"
left="$(ls -A "$w/r/opt/mavergreen/.install-products/shipyard")"
[ -z "$left" ] || fail "an install must leave nothing staged beside the prefix; left: $left"

if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$w/ro" "$w/home"; chmod 555 "$w/ro"
  rc=0
  env -u MAVERGREEN_USER_PREFIX SUDO= HOME="$w/home" sh "$S/install-shipyard-prefix.sh" --root "$w/ro" --version 1.2.3 \
    > "$w/out" 2> "$w/err" || rc=$?
  up="$w/home/.local/mavergreen/shipyard"
  [ "$rc" -eq 0 ] || { fail "with no root, sudo or writable root it must install per user; exit $rc:"; sed 's/^/    | /' "$w/err"; }
  [ "$(cat "$w/out")" = "$up" ] || fail "the per-user install must print its prefix, $up; got $(cat "$w/out")"
  grep -qF "so shipyard goes to $up" "$w/err" || fail "the per-user install must say where it went on stderr"
  grep -qF "\"toolchainFile\": \"$up/share/cmake/MavergreenShipyard/MavergreenToolchain.cmake\"" "$up/share/cmake/MavergreenShipyard/mavergreen-presets.json" 2>/dev/null \
    || fail "the per-user install's presets must name its own toolchain file"
  [ -h "$w/home/.local/mavergreen/bin/shipyard-cmake" ] || fail "the per-user install must link its launchers into $w/home/.local/mavergreen/bin"
  [ -z "$(ls -A "$w/ro")" ] || fail "the per-user install wrote into the read-only root"
fi

[ "$fails" -eq 0 ] || { echo "FAIL: $fails case(s) in linux-shipyard-prefix"; exit 1; }
echo "PASS: linux-shipyard-prefix"
