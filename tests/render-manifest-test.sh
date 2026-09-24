#!/bin/sh
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
  --appcast https://example/appcast.xml --replaces /usr/bin/ssh=bin/ssh
M="$st/usr/local/mavergreen/openssh/mavergreen.plist"
p() { "$PB" -c "Print :$1" "$M"; }
[ "$(p identifier)" = dev.mavergreen.openssh ] || fail "the identifier comes from the registry"
[ "$(p group)" = openssh ] && [ "$(p line)" = "" ] || fail "group defaults to the product, line to empty"
[ "$(p replaces:/usr/bin/ssh)" = bin/ssh ] || fail "replaces is carried"
outside="$(i=0; while v="$("$PB" -c "Print :outside:$i" "$M" 2>/dev/null)"; do echo "$v"; i=$((i+1)); done)"
[ "$outside" = "$(printf '%s\n' 'Applications/Mavericks X.app' 'Library/Application Support/Mavergreen/OpenSSHUpdater.app' 'Library/LaunchAgents/dev.mavergreen.openssh-updatecheck.plist')" ] \
  || fail "outside lists what is installed outside the tree, bundles collapsed, spaces intact: $outside"
sh "$S" --stage "$st" --product not-registered --name x --version 1 2>/dev/null && fail "an unregistered product must be refused"
sh "$S" --stage "$st" --product openssh --name x --version 1 --replaces usr/bin/ssh=bin/ssh 2>/dev/null \
  && fail "a replaces target must be an absolute system path"
sh "$S" --stage "$st" --product openssh --name x --version 1 --replaces /usr/bin/ssh=../bin/ssh 2>/dev/null \
  && fail "a replaces value with a .. component must be refused"
sh "$S" --stage "$st" --product openssh --name x --version 1 --replaces /usr/bin/ssh=/bin/ssh 2>/dev/null \
  && fail "a replaces value must not itself be an absolute path"
sh "$S" --stage "$st" --product openssh --name x --version 1 --replaces /usr/../bin/ssh=bin/ssh 2>/dev/null \
  && fail "a replaces key with a .. component must be refused"
echo "PASS: render-manifest"
