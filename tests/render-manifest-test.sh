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
refused() {  # $1 why  $2 text the refusal must say  $3.. arguments after --version 1
  _rf_why="$1"; _rf_say="$2"; shift 2
  rm -f "$M"; _rf_rc=0
  sh "$S" --stage "$st" --product openssh --name x --version 1 "$@" 2>"$w/err" || _rf_rc=$?
  [ "$_rf_rc" -eq 2 ] || fail "$_rf_why: render-manifest must refuse it with exit 2, got $_rf_rc: $(cat "$w/err")"
  grep -qF -- "$_rf_say" "$w/err" || fail "$_rf_why: the refusal must say '$_rf_say': $(cat "$w/err")"
  [ ! -e "$M" ] || fail "$_rf_why: a refused manifest must not be left behind"
}
[ "$(p identifier)" = dev.mavergreen.openssh ] || fail "the identifier comes from the registry"
[ "$(p group)" = openssh ] && [ "$(p line)" = "" ] || fail "group defaults to the product, line to empty"
[ "$(p replaces:/usr/bin/ssh)" = bin/ssh ] || fail "replaces is carried"
[ "$(p appcast)" = "" ] || fail "a manifest rendered without --has-updater names no feed: the product has no updater"
refused "--appcast must be refused: the registry, not the repo, names the feed" \
  "--appcast is derived from shipyard's scripts/product-names" --appcast https://example/appcast.xml
sh "$S" --stage "$st" --product openssh --name "OpenSSH for Mavericks" --version 10.5p1-mavericks.5 \
  --replaces /usr/bin/ssh=bin/ssh --has-updater
[ "$(p appcast)" = https://github.com/Mavergreen/openssh/releases/latest/download/openssh.xml ] \
  || fail "with an updater, the feed comes from the registry: openssh's repo, openssh.xml"
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
refused "a replaces target must be an absolute system path" "--replaces wants /abs/path=tree/path" --replaces usr/bin/ssh=bin/ssh
refused "a replaces value with a .. component must be refused" "--replaces value has a . or .. component" --replaces /usr/bin/ssh=../bin/ssh
refused "a replaces value must not itself be an absolute path" "--replaces value must not be absolute" --replaces /usr/bin/ssh=/bin/ssh
refused "a replaces key with a .. component must be refused" "--replaces key has a . or .. component" --replaces /usr/../bin/ssh=bin/ssh
sh "$S" --stage "$st" --product openssh --name x --version 1 \
  --generated "Applications/Linux X.app" --generated Applications/Other.app
[ "$(p generated:0)" = "Applications/Linux X.app" ] && [ "$(p generated:1)" = Applications/Other.app ] \
  || fail "generated entries are written in order, spaces intact -- uninstall removes exactly these"
for bad in "/Applications/X.app|wants a /-relative path" "Applications/../X.app|has a . or .. component" \
    "./Applications/X.app|has a . or .. component" "usr/local/mavergreen|may not name anything under usr/local/mavergreen" \
    "usr/local/mavergreen/openssh/x|may not name anything under usr/local/mavergreen" "|wants a /-relative path" \
    "Applications/X.app/|may not end in / or have an empty segment" "Applications//X.app|may not end in / or have an empty segment"; do
  refused "a generated entry the helper would refuse to uninstall must be refused when the manifest is rendered: '${bad%%|*}'" \
    "--generated ${bad#*|}" --generated "${bad%%|*}"
done
refused "a generated entry with a newline must be refused -- it would render as two entries" "--generated may not contain a newline" \
  --generated "$(printf 'Applications/A.app\nusr/local/mavergreen/sib')"
sh "$S" --stage "$st" --product openssh --name x --version 1 --adopts /etc/sshd_config=sshd_config:config --adopts /etc/ssh_host_ed25519_key=ssh_host_ed25519_key:identity
[ "$(p adopts:/etc/sshd_config:path)" = sshd_config ] && [ "$(p adopts:/etc/sshd_config:kind)" = config ] \
  || fail "adopts is rendered as system path -> {path, kind}"
[ "$(p adopts:/etc/ssh_host_ed25519_key:kind)" = identity ] || fail "a second adopts entry keeps its own kind"
sh "$S" --stage "$st" --product openssh --name x --version 1
"$PB" -c "Print :adopts" "$M" >/dev/null 2>&1 || fail "adopts is always rendered, empty when none are declared"
for bad in "/etc/c=c|wants a :kind" "/etc/c=c:|kind must be config or identity" "/etc/c=c:bogus|kind must be config or identity" \
    "/etc/c=/abs:config|value must not be absolute" "/etc/c=../c:config|value has a . or .. component" \
    "/etc/c=a/./c:config|value has a . or .. component" "/etc/c=a:b:config|path may not contain a colon" \
    "/etc/../c=c:config|key has a . or .. component" "/etc/./c=c:config|key has a . or .. component" \
    "etc/c=c:config|wants /abs/path=var/path:kind" "/usr/local/mavergreen=c:config|key may not be under /usr/local/mavergreen" \
    "/usr/local/mavergreen/x/c=c:config|key may not be under /usr/local/mavergreen" "/etc/c=:config|needs a var-relative path"; do
  refused "a malformed --adopts must be refused: '${bad%%|*}'" "--adopts ${bad#*|}" --adopts "${bad%%|*}"
done
refused "a path in both adopts and replaces must be refused: the helper would both link and copy it" \
  "/usr/bin/ssh is in both --replaces and --adopts" --adopts /usr/bin/ssh=c:config --replaces /usr/bin/ssh=bin/ssh
refused "a path in both replaces and adopts must be refused whichever order they were given" \
  "/usr/bin/ssh is in both --replaces and --adopts" --replaces /usr/bin/ssh=bin/ssh --adopts /usr/bin/ssh=c:config
refused "a man page replaced by a differently named file must be refused: 10.9 man would print gzip bytes" \
  "ssh.1 (from /usr/share/man/man1/ssh.1) cannot be linked to ssh.1.gz (from share/man/man1/ssh.1.gz)" \
  --replaces /usr/share/man/man1/ssh.1=share/man/man1/ssh.1.gz
mkdir -p "$st/usr/local/mavergreen/openssh/share/man/man1"
touch "$st/usr/local/mavergreen/openssh/share/man/man1/ssh.1" "$st/usr/local/mavergreen/openssh/bin/vim"
sh "$S" --stage "$st" --product openssh --name x --version 1 --replaces /usr/share/man/man1/ssh.1=share/man/man1/ssh.1 \
  || fail "a man page replaced by the same basename is fine"
sh "$S" --stage "$st" --product openssh --name x --version 1 --replaces /usr/bin/vi=bin/vim \
  || fail "the basename rule is for man pages only: /usr/bin/vi=bin/vim must be accepted"
T="$st/usr/local/mavergreen/openssh"
ln -s ssh "$T/bin/sshlink"
refused "a replaces target that is a symlink in the stage must be refused: the helper copies files" \
  "--replaces target bin/sshlink is a symlink in the stage" --replaces /usr/bin/slogin=bin/sshlink
rm "$T/bin/sshlink"
for b in app bundle framework plugin kext prefPane; do
  mkdir -p "$T/lib/X.$b/Contents/MacOS"; touch "$T/lib/X.$b/Contents/MacOS/x"
  refused "a replaces target inside a .$b must be refused: bundles are cleared on upgrade" \
    "--replaces target lib/X.$b/Contents/MacOS/x lies inside a bundle" --replaces "/usr/bin/x=lib/X.$b/Contents/MacOS/x"
done
sh "$S" --stage "$st" --product openssh --name x --version 1 --replaces /usr/bin/ssh=bin/ssh \
  || fail "an ordinary file target must still be accepted"
refused "a replaces target missing from the stage must be refused at package time (R60): an upgrade's re-replace would die after the payload landed" \
  "share/man/man8/sshd.8 is missing from the stage" --replaces /usr/share/man/man8/sshd.8=share/man/man8/sshd.8
mkdir -p "$T/bin/sshdir"
refused "a replaces target that is a directory in the stage must be refused at package time (R60): System Replace takes files only" \
  "bin/sshdir is not a regular file" --replaces /usr/bin/sshdir=bin/sshdir
rmdir "$T/bin/sshdir"
refused "a system path given twice in --replaces must be refused: the helper would plan it twice (R68)" \
  "--replaces names /usr/bin/ssh twice" --replaces /usr/bin/ssh=bin/ssh --replaces /usr/bin/ssh=bin/vim
refused "/etc/x and /private/etc/x are one path, so declaring both in --replaces must be refused (R68)" \
  "--replaces names /private/etc/x twice" --replaces /etc/x=bin/ssh --replaces /private/etc/x=bin/vim
refused "/var/x and /private/var/x are one path, so declaring both in --adopts must be refused (R68)" \
  "--adopts names /private/var/x twice" --adopts /var/x=x:identity --adopts /private/var/x=y:identity
refused "a path in --replaces and, spelled under /private, in --adopts must be refused (R68)" \
  "/etc/c is in both --replaces and --adopts" --replaces /private/etc/c=bin/ssh --adopts /etc/c=c:config
refused "two adopts entries at one var path must be refused (R68)" \
  "--adopts gives two entries the var path sudoers" --adopts /etc/a=sudoers:config --adopts /etc/b=sudoers:config
refused "HFS+ compares names case-insensitively, so two adopts var paths differing in case must be refused (R68)" \
  "--adopts gives two entries the var path Sudoers" --adopts /etc/a=sudoers:config --adopts /etc/b=Sudoers:config
for k in /staging/x /applied.plist /applied.plist.tmp /adopted.sha256 /restored.sha256.tmp /.replaced /Staging/x; do
  refused "a replaces key whose first component is a name the save area keeps for itself must be refused: $k (R68)" \
    "--replaces key $k starts with a name" --replaces "$k=bin/ssh"
  refused "an adopts key whose first component is a name the save area keeps for itself must be refused: $k (R68)" \
    "--adopts key $k starts with a name" --adopts "$k=c:config"
done
sh "$S" --stage "$st" --product openssh --name x --version 1 --replaces /stagingx/y=bin/ssh --adopts /etc/staging=c:config \
  || fail "only a whole first component is reserved: /stagingx/y and /etc/staging are ordinary paths (R68)"
mkdir -p "$w/kX=bin" && touch "$w/kX=bin/ssh" "$w/kX=c:config"
refused "a --replaces entry is never expanded as a glob: '$w/k*=bin/ss?' names bin/ss?, which is not staged (M10)" \
  "bin/ss? is missing from the stage" --replaces "$w/k*=bin/ss?"
sh "$S" --stage "$st" --product openssh --name x --version 1 --replaces "$w/kX=bin/ssh" --adopts "$w/k*=c:config" \
  || fail "an --adopts entry is never expanded as a glob, so '$w/k*' is not '$w/kX' (M10)"
echo "PASS: render-manifest"
