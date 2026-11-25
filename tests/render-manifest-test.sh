#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/render-manifest.sh"
SD="$(sh "$here/../scripts/fetch_stevedore.sh")" || { echo "FAIL: fetch_stevedore.sh failed"; exit 1; }; export STEVEDORE="$SD"
w="$(mktemp -d "${TMPDIR:-/tmp}/render-manifest.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
st="$w/stage"
mkdir -p "$st/usr/local/mavergreen/openssh/bin" "$st/Applications/Mavericks X.app/Contents/MacOS" \
         "$st/Library/LaunchAgents" "$st/Library/Application Support/Mavergreen/OpenSSHUpdater.app/Contents" \
         "$st/Library/Java/JavaVirtualMachines/x.jdk/Contents"
touch "$st/Library/Java/JavaVirtualMachines/x.jdk/Contents/Info.plist"
ln -s /usr/local/mavergreen/openssh "$st/Library/Java/JavaVirtualMachines/x.jdk/Contents/Home"
touch "$st/usr/local/mavergreen/openssh/bin/ssh" "$st/Applications/Mavericks X.app/Contents/MacOS/X" \
      "$st/Library/LaunchAgents/dev.mavergreen.openssh-updatecheck.plist" \
      "$st/Library/Application Support/Mavergreen/OpenSSHUpdater.app/Contents/Info.plist"
sh "$S" --stage "$st" --product openssh --name "OpenSSH for Mavericks" --version 10.5p1-mavericks.5 \
  --replaces /usr/bin/ssh=bin/ssh
M="$st/usr/local/mavergreen/openssh/mavergreen.plist"
p() { "$SD" plist get "$M" "$1"; }
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
outside="$(i=0; while v="$("$SD" plist get "$M" "outside:$i" 2>/dev/null)"; do echo "$v"; i=$((i+1)); done)"
[ "$outside" = "$(printf '%s\n' 'Applications/Mavericks X.app' 'Library/Application Support/Mavergreen/OpenSSHUpdater.app' 'Library/Java/JavaVirtualMachines/x.jdk' 'Library/LaunchAgents/dev.mavergreen.openssh-updatecheck.plist')" ] \
  || fail "outside lists what is installed outside the tree, bundles (a .jdk among them) collapsed, spaces intact: $outside"
nasty_name='O'\''Brien "quoted" \back & <angle>'
sh "$S" --stage "$st" --product openssh --name "$nasty_name" --version 1
[ "$(p name)" = "$nasty_name" ] \
  || fail "name must round-trip exactly through the plist reader, including apostrophe/quotes/backslash/ampersand/angle-brackets"
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
sh "$S" --stage "$st" --product openssh --name x --version 1 --requires 'longboat>=20261019.1' --requires sdk109
[ "$(p requires:0)" = 'longboat>=20261019.1' ] && [ "$(p requires:1)" = sdk109 ] \
  || fail "requires entries are written verbatim, in the order given"
p requires:2 >/dev/null 2>&1 && fail "requires has exactly the entries given"
sh "$S" --stage "$st" --product openssh --name x --version 1
p requires:0 >/dev/null 2>&1 && fail "a product with no requires has no requires key"
sh "$S" --stage "$st" --product openssh --name x --version 1 --requires-on-host x86_64:swift-runtime --requires-on-host 'arm64:sdk113>=1'
[ "$(p requires-on-host:0)" = x86_64:swift-runtime ] && [ "$(p requires-on-host:1)" = 'arm64:sdk113>=1' ] \
  || fail "requires-on-host entries are written verbatim, in the order given"
p requires-on-host:2 >/dev/null 2>&1 && fail "requires-on-host has exactly the entries given"
p requires:0 >/dev/null 2>&1 && fail "requires-on-host does not write requires"
sh "$S" --stage "$st" --product openssh --name x --version 1
p requires-on-host:0 >/dev/null 2>&1 && fail "a product without the flag has no requires-on-host key"
sh "$S" --stage "$st" --product openssh --name x --version 1 --slim-host 'bin/*' --slim-host 'lib/a b.dylib'
[ "$(p slim-host:0)" = 'bin/*' ] && [ "$(p slim-host:1)" = 'lib/a b.dylib' ] || fail "slim-host entries are written verbatim, in order"
p slim-host:2 >/dev/null 2>&1 && fail "slim-host has exactly the entries given"
sh "$S" --stage "$st" --product openssh --name x --version 1
p slim-host:0 >/dev/null 2>&1 && fail "a product without the flag has no slim-host key"
for g in /abs '../x' 'a/../x' './x' 'a/.' '*/*' '*' '?' ''; do
  rc=0; sh "$S" --stage "$st" --product openssh --name x --version 1 --slim-host "$g" 2>/dev/null || rc=$?
  [ "$rc" = 2 ] || fail "--slim-host '$g' exits 2, got $rc"
done
echo "PASS: render-manifest"
