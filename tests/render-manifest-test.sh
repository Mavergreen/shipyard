#!/bin/sh
# platform: macOS-only -- PlistBuddy reads back the rendered manifest
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/render-manifest.sh"
PB=/usr/libexec/PlistBuddy; [ -x "$PB" ] || { echo "no PlistBuddy -- skipping"; exit 77; }
w="$(mktemp -d "${TMPDIR:-/tmp}/render-manifest.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
st="$w/stage"
mkdir -p "$st/usr/local/mavergreen/openssh/bin" "$st/Applications/Mavericks X.app/Contents/MacOS" \
         "$st/Library/LaunchAgents" "$st/Library/Application Support/Mavergreen/OpenSSHUpdater.app/Contents"
touch "$st/usr/local/mavergreen/openssh/bin/ssh" "$st/Applications/Mavericks X.app/Contents/MacOS/X" \
      "$st/Library/LaunchAgents/dev.mavergreen.openssh-updatecheck.plist" \
      "$st/Library/Application Support/Mavergreen/OpenSSHUpdater.app/Contents/Info.plist"
sh "$S" --stage "$st" --product openssh --name "OpenSSH for Mavericks" --version 10.5p1-mavericks.5 \
  --replaces /usr/bin/ssh=bin/ssh
M="$st/usr/local/mavergreen/openssh/mavergreen.plist"
p() { "$PB" -c "Print :$1" "$M"; }
[ "$(p identifier)" = dev.mavergreen.openssh ] || fail "the identifier comes from the registry"
[ "$(p group)" = openssh ] && [ "$(p line)" = "" ] || fail "group defaults to the product, line to empty"
[ "$(p replaces:/usr/bin/ssh)" = bin/ssh ] || fail "replaces is carried"
[ "$(p appcast)" = "" ] || fail "a manifest rendered without --has-updater names no feed: the product has no updater"
sh "$S" --stage "$st" --product openssh --name "OpenSSH for Mavericks" --version 10.5p1-mavericks.5 \
  --replaces /usr/bin/ssh=bin/ssh --has-updater
[ "$(p appcast)" = https://github.com/Mavergreen/openssh/releases/latest/download/openssh.xml ] \
  || fail "with an updater, the feed comes from the registry: openssh's repo, openssh.xml"
sh "$S" --stage "$st" --product openssh --name x --version 1 --appcast https://example/appcast.xml 2>/dev/null \
  && fail "--appcast must be refused: the registry, not the repo, names the feed"
outside="$(i=0; while v="$("$PB" -c "Print :outside:$i" "$M" 2>/dev/null)"; do echo "$v"; i=$((i+1)); done)"
[ "$outside" = "$(printf '%s\n' 'Applications/Mavericks X.app' 'Library/Application Support/Mavergreen/OpenSSHUpdater.app' 'Library/LaunchAgents/dev.mavergreen.openssh-updatecheck.plist')" ] \
  || fail "outside lists what is installed outside the tree, bundles collapsed, spaces intact: $outside"
nasty_name='O'\''Brien "quoted" \back & <angle>'
sh "$S" --stage "$st" --product openssh --name "$nasty_name" --version 1
[ "$(p name)" = "$nasty_name" ] \
  || fail "name must round-trip exactly through PlistBuddy, including apostrophe/quotes/backslash/ampersand/angle-brackets"
sh "$S" --stage "$st" --product not-registered --name x --version 1 2>/dev/null && fail "an unregistered product must be refused"
MAVERGREEN_PRODUCT_NAMES="$w/absent-registry" sh "$S" --stage "$st" --product openssh --name x --version 1 2>"$w/err" \
  && fail "an unreadable registry must refuse the manifest"
grep -q "cannot look up openssh in shipyard's registry" "$w/err" && grep -q absent-registry "$w/err" \
  || fail "an unreadable registry is reported as such, with product-name.sh's reason: $(cat "$w/err")"
sh "$S" --stage "$st" --product openssh --name x --version 1 --replaces usr/bin/ssh=bin/ssh 2>/dev/null \
  && fail "a replaces target must be an absolute system path"
sh "$S" --stage "$st" --product openssh --name x --version 1 --replaces /usr/bin/ssh=../bin/ssh 2>/dev/null \
  && fail "a replaces value with a .. component must be refused"
sh "$S" --stage "$st" --product openssh --name x --version 1 --replaces /usr/bin/ssh=/bin/ssh 2>/dev/null \
  && fail "a replaces value must not itself be an absolute path"
sh "$S" --stage "$st" --product openssh --name x --version 1 --replaces /usr/../bin/ssh=bin/ssh 2>/dev/null \
  && fail "a replaces key with a .. component must be refused"
sh "$S" --stage "$st" --product openssh --name x --version 1 \
  --generated "Applications/Linux X.app" --generated Applications/Other.app
[ "$(p generated:0)" = "Applications/Linux X.app" ] && [ "$(p generated:1)" = Applications/Other.app ] \
  || fail "generated entries are written in order, spaces intact -- uninstall removes exactly these"
for bad in /Applications/X.app Applications/../X.app ./Applications/X.app usr/local/mavergreen usr/local/mavergreen/openssh/x '' Applications/X.app/ Applications//X.app; do
  sh "$S" --stage "$st" --product openssh --name x --version 1 --generated "$bad" 2>/dev/null \
    && fail "a generated entry the helper would refuse to uninstall must be refused when the manifest is rendered: '$bad'"
done
sh "$S" --stage "$st" --product openssh --name x --version 1 --generated "$(printf 'Applications/A.app\nusr/local/mavergreen/sib')" 2>/dev/null \
  && fail "a generated entry with a newline must be refused -- it would render as two entries"
echo "PASS: render-manifest"
