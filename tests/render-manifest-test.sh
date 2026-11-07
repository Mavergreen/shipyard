#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/render-manifest.sh"
SD="$(sh "$here/../scripts/fetch_stevedore.sh")" || { echo "FAIL: fetch_stevedore.sh failed"; exit 1; }; export STEVEDORE="$SD"
w="$(mktemp -d "${TMPDIR:-/tmp}/render-manifest.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
mkdir -p "$w/repo/.mavergreen/products/openssh"; echo OpenSSH > "$w/repo/.mavergreen/products/openssh/noun"
MAVERGREEN_REPO_ROOT="$w/repo"; GITHUB_REPOSITORY=Someone/openssh; export MAVERGREEN_REPO_ROOT GITHUB_REPOSITORY
st="$w/stage"
mkdir -p "$st/usr/local/mavergreen/openssh/bin" "$st/Applications/Mavericks X.app/Contents/MacOS" \
         "$st/Library/LaunchAgents" "$st/Library/Application Support/Mavergreen/OpenSSHUpdater.app/Contents" \
         "$st/Library/Java/JavaVirtualMachines/x.jdk/Contents"
touch "$st/Library/Java/JavaVirtualMachines/x.jdk/Contents/Info.plist"
ln -s /usr/local/mavergreen/openssh "$st/Library/Java/JavaVirtualMachines/x.jdk/Contents/Home"
touch "$st/usr/local/mavergreen/openssh/bin/ssh" "$st/Applications/Mavericks X.app/Contents/MacOS/X" \
      "$st/Library/LaunchAgents/dev.mavergreen.openssh-updatecheck.plist" \
      "$st/Library/Application Support/Mavergreen/OpenSSHUpdater.app/Contents/Info.plist"
sh "$S" --stage "$st" --product openssh --version 10.5p1-mavergreen.5 \
  --replaces /usr/bin/ssh=bin/ssh
M="$st/usr/local/mavergreen/openssh/mavergreen.plist"
p() { "$SD" plist get "$M" "$1"; }
[ "$(p identifier)" = dev.mavergreen.openssh ] || fail "the identifier is derived: dev.mavergreen.<short>"
[ "$(p group)" = openssh ] && [ "$(p line)" = "" ] || fail "group defaults to the product, line to empty"
[ "$(p replaces:/usr/bin/ssh)" = bin/ssh ] || fail "replaces is carried"
[ "$(p appcast)" = "" ] || fail "a manifest rendered without --has-updater names no feed: the product has no updater"
sh "$S" --stage "$st" --product openssh --version 10.5p1-mavergreen.5 \
  --replaces /usr/bin/ssh=bin/ssh --has-updater
[ "$(p appcast)" = https://github.com/Mavergreen/openssh/releases/latest/download/openssh.xml ] \
  || fail "with an updater, the feed is derived: this repo's name under Mavergreen, openssh.xml"
sh "$S" --stage "$st" --product openssh --version 1 --appcast https://example/appcast.xml 2>/dev/null \
  && fail "--appcast must be refused: the feed is derived, never chosen"
outside="$(i=0; while v="$("$SD" plist get "$M" "outside:$i" 2>/dev/null)"; do echo "$v"; i=$((i+1)); done)"
[ "$outside" = "$(printf '%s\n' 'Applications/Mavericks X.app' 'Library/Application Support/Mavergreen/OpenSSHUpdater.app' 'Library/Java/JavaVirtualMachines/x.jdk' 'Library/LaunchAgents/dev.mavergreen.openssh-updatecheck.plist')" ] \
  || fail "outside lists what is installed outside the tree, bundles (a .jdk among them) collapsed, spaces intact: $outside"
nasty_name='O'\''Brien "quoted" \back & <angle>'
printf '%s\n' "$nasty_name" > "$w/repo/.mavergreen/products/openssh/noun"
sh "$S" --stage "$st" --product openssh --version 1
[ "$(p name)" = "$nasty_name" ] \
  || fail "name must round-trip exactly through the plist reader, including apostrophe/quotes/backslash/ampersand/angle-brackets"
echo OpenSSH > "$w/repo/.mavergreen/products/openssh/noun"
sh "$S" --stage "$st" --product openssh --version 1
[ "$(p name)" = OpenSSH ] || fail "the manifest's name is the noun when the product has no line: $(p name)"
for o in name:noun line:line; do
  rc=0; sh "$S" --stage "$st" --product openssh --version 1 --${o%%:*} X 2>"$w/err" || rc=$?
  [ "$rc" -eq 2 ] || fail "--${o%%:*} must be refused with exit 2, got $rc"
  grep -qF ".mavergreen/products/<P>/${o#*:}" "$w/err" || fail "the refusal of --${o%%:*} names products/<P>/${o#*:}: $(cat "$w/err")"
done
mkdir -p "$st/usr/local/mavergreen/go127/bin"; touch "$st/usr/local/mavergreen/go127/bin/go"
mkdir -p "$w/repo/.mavergreen/products/go127"; echo Go > "$w/repo/.mavergreen/products/go127/noun"; echo 1.27 > "$w/repo/.mavergreen/products/go127/line"
sh "$S" --stage "$st" --product go127 --version 1
M="$st/usr/local/mavergreen/go127/mavergreen.plist"
[ "$(p name)" = "Go 1.27" ] || fail "a lined product's manifest name is '<noun> <line>': $(p name)"
[ "$(p line)" = 1.27 ] || fail "the manifest's line is line 1 of products/<P>/line as upstream spells it: $(p line)"
M="$st/usr/local/mavergreen/openssh/mavergreen.plist"
rc=0; sh "$S" --stage "$st" --product not-declared --version 1 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "a product the repo does not declare must be refused (1), got $rc"
grep -q '.mavergreen/products/not-declared/' "$w/err" || fail "the refusal names where to declare it: $(cat "$w/err")"
sh "$S" --stage "$st" --product openssh --version 1 --replaces usr/bin/ssh=bin/ssh 2>/dev/null \
  && fail "a replaces target must be an absolute system path"
sh "$S" --stage "$st" --product openssh --version 1 --replaces /usr/bin/ssh=../bin/ssh 2>/dev/null \
  && fail "a replaces value with a .. component must be refused"
sh "$S" --stage "$st" --product openssh --version 1 --replaces /usr/bin/ssh=/bin/ssh 2>/dev/null \
  && fail "a replaces value must not itself be an absolute path"
sh "$S" --stage "$st" --product openssh --version 1 --replaces /usr/../bin/ssh=bin/ssh 2>/dev/null \
  && fail "a replaces key with a .. component must be refused"
sh "$S" --stage "$st" --product openssh --version 1 \
  --generated "Applications/Linux X.app" --generated Applications/Other.app
[ "$(p generated:0)" = "Applications/Linux X.app" ] && [ "$(p generated:1)" = Applications/Other.app ] \
  || fail "generated entries are written in order, spaces intact -- uninstall removes exactly these"
for bad in /Applications/X.app Applications/../X.app ./Applications/X.app usr/local/mavergreen usr/local/mavergreen/openssh/x '' Applications/X.app/ Applications//X.app; do
  sh "$S" --stage "$st" --product openssh --version 1 --generated "$bad" 2>/dev/null \
    && fail "a generated entry the helper would refuse to uninstall must be refused when the manifest is rendered: '$bad'"
done
sh "$S" --stage "$st" --product openssh --version 1 --generated "$(printf 'Applications/A.app\nusr/local/mavergreen/sib')" 2>/dev/null \
  && fail "a generated entry with a newline must be refused -- it would render as two entries"
echo "PASS: render-manifest"
