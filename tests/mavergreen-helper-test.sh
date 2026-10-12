#!/bin/sh
# platform: macOS-only -- PlistBuddy writes the fixture manifests the helper reads
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
MG="$here/../scripts/mavergreen.sh"
PB=/usr/libexec/PlistBuddy
[ -x "$PB" ] || { echo "no PlistBuddy -- skipping"; exit 77; }
w="$(mktemp -d "${TMPDIR:-/tmp}/mavergreen-helper.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
V="$w/vol"; T="$V/usr/local/mavergreen"
mg() { MAVERGREEN_TRUSTED_UID="$(id -u)" sh "$MG" --root "$V" "$@"; }
mkproduct() {  # $1 product  $2 group  $3 line  $4.. files under the tree
  _p="$1"; _g="$2"; _l="$3"; shift 3
  mkdir -p "$T/$_p"
  for _f in "$@"; do mkdir -p "$T/$_p/$(dirname "$_f")"; echo "$_p" > "$T/$_p/$_f"; done
  rm -f "$T/$_p/mavergreen.plist"
  "$PB" -c "Add :product string $_p" -c "Add :group string $_g" -c "Add :line string $_l" \
        -c "Add :identifier string dev.mavergreen.$_p" -c "Add :version string 1.0" "$T/$_p/mavergreen.plist" >/dev/null
}
target() { readlink "$T/$1"; }

mkproduct openssh openssh "" bin/ssh "bin/ssh add" share/man/man1/ssh.1
mg link openssh || fail "linking a single-line product must succeed"
[ "$(target bin/ssh)" = ../openssh/bin/ssh ] || fail "a single-line product exports its bare names, relatively"
[ "$(target "bin/ssh add")" = "../openssh/bin/ssh add" ] || fail "a name with a space must be linked intact"
[ "$(target share/man/man1/ssh.1)" = ../../../openssh/share/man/man1/ssh.1 ] || fail "manpages are exported"
[ ! -e "$T/bin/ssh-" ] || fail "a product with no line exports no versioned names"
mg link openssh || fail "link must be idempotent"

mkproduct go126 go 126 bin/go bin/gofmt share/man/man1/go.1.gz
mkproduct go127 go 127 bin/go bin/gofmt
mg link go126
[ "$(target bin/go)" = ../go126/bin/go ] || fail "the first member of a group is selected automatically"
[ "$(target bin/go-126)" = ../go126/bin/go ] || fail "a line product always exports <cmd>-<line>"
[ "$(target share/man/man1/go-126.1.gz)" = ../../../go126/share/man/man1/go.1.gz ] \
  || fail "a manpage's line goes before its section suffix: go-126.1.gz"
mg link go127
[ "$(target bin/go)" = ../go126/bin/go ] || fail "installing another line must never take the selection"
[ "$(target bin/go-127)" = ../go127/bin/go ] || fail "the second line still exports its versioned names"

mg unlink go126
[ "$(mg select go)" = go126 ] || fail "unlink never changes a selection: an upgrade's preinstall runs it on the selected line"
mg link go126
[ "$(target bin/go)" = ../go126/bin/go ] \
  || fail "an upgrade (unlink then link) of the selected line must keep the selection"

mg select go go127
[ "$(target bin/go)" = ../go127/bin/go ] || fail "select moves the bare names"
[ "$(target bin/gofmt)" = ../go127/bin/gofmt ] || fail "select moves every bare name of the group"
[ "$(target bin/go-126)" = ../go126/bin/go ] || fail "select leaves versioned names alone"
[ "$(mg select go)" = go127 ] || fail "select with no product prints the selection"

mkproduct rogue rogue "" bin/ssh
mg link rogue 2>"$w/err" && fail "a bare name owned by another group must be refused"
grep -q openssh "$w/err" || fail "the refusal must name the owner"
[ "$(target bin/ssh)" = ../openssh/bin/ssh ] || fail "a refused link must change nothing"
rm -rf "$T/rogue"

mkproduct xa xg 22 bin/x
mkproduct xb xg 23 bin/x-22
mg link xa || fail "setup: link the first member"
mg link xb || fail "a second member whose file shares a name with the first's versioned link links fine while not selected"
mg select xg xb 2>"$w/err" && fail "a member must not take a sibling's versioned link x-22 as its bare name"
grep -q 'xa' "$w/err" || fail "the refusal must name the owner: $(cat "$w/err")"
[ "$(target bin/x-22)" = ../xa/bin/x ] || fail "a refused select changes nothing: x-22 is still xa's versioned link"
[ "$(target bin/x)" = ../xa/bin/x ] && [ "$(mg select xg)" = xa ] || fail "a refused select leaves the selection and bare names alone"
[ "$(target bin/x-22-23)" = ../xb/bin/x-22 ] || fail "the second member keeps its own versioned link"
mg unlink xa; mg unlink xb; rm -rf "$T/xa" "$T/xb" "$T/var/mavergreen/selections/xg"

mkproduct shipyard shipyard "" bin/cmake bin/shipyard-cmake
"$PB" -c "Add :exports-exclude array" -c "Add :exports-exclude:0 string bin/cmake" "$T/shipyard/mavergreen.plist"
mg link shipyard
[ ! -e "$T/bin/cmake" ] && [ ! -L "$T/bin/cmake" ] || fail "exports-exclude must keep a name out of the farm"
[ -L "$T/bin/shipyard-cmake" ] || fail "names not excluded are still exported"

mg unlink openssh
[ ! -L "$T/bin/ssh" ] && [ ! -L "$T/share/man/man1/ssh.1" ] || fail "unlink removes every link the product owns"
[ -L "$T/bin/go" ] || fail "unlink removes only its own product's links"

mkproduct oddsections oddsections "" bin/odd share/man/mann/after.n share/man/man9/k.9
mg link oddsections
[ -L "$T/share/man/mann/after.n" ] || fail "a manpage in section n (share/man/mann) is exported"
[ -L "$T/share/man/man9/k.9" ] || fail "a manpage in section 9 (share/man/man9) is exported"
mg unlink oddsections
[ ! -L "$T/share/man/mann/after.n" ] \
  || fail "unlink must remove a link in a man section outside man1-man8 (mann)"
[ ! -L "$T/share/man/man9/k.9" ] \
  || fail "unlink must remove a link in a man section outside man1-man8 (man9)"
rm -rf "$T/oddsections"

mg list | grep -q '^go127 go 127 1.0 selected$' || fail "list shows product group line version and selection: $(mg list)"
mg link no-such 2>/dev/null && fail "linking a product that is not installed must fail"
rc=0; mg link '../x' 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "a malformed product name is a usage error (exit 2), got $rc"
mkproduct var var "" bin/var-tool
rc=0; mg link var 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "a name the install layout reserves (var) is not a product, even with a hand-made manifest: want exit 2, got $rc"
[ ! -L "$T/bin/var-tool" ] || fail "a refused reserved name must link nothing"
rm -f "$T/var/mavergreen.plist" "$T/var/bin/var-tool"; rmdir "$T/var/bin"
mkproduct kept kept "" bin/kept-tool
rc=0; mg link kept 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "kept/ holds the originals restore keeps, so kept is not a product name (R78): want exit 2, got $rc"
rm -rf "$T/kept"

mg link openssh
mg check || fail "a consistent farm must pass check: $(mg check 2>&1)"
rm -rf "$T/go127/bin/gofmt"
mg check 2>"$w/err" && fail "a dangling link must fail check"
grep -q 'bin/gofmt' "$w/err" || fail "check must name the dangling link"
mkproduct go127 go 127 bin/go bin/gofmt

stub="$w/stub"; mkdir -p "$stub"
for c in launchctl pkgutil sudo; do printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\n' "$c" "$w" > "$stub/$c"; chmod +x "$stub/$c"; done
mkdir -p "$V/Applications/Go.app/Contents" "$V/Library/LaunchAgents" "$T/var/go127"
touch "$V/Library/LaunchAgents/dev.mavergreen.go127-updatecheck.plist"
"$PB" -c "Add :outside array" -c "Add :outside:0 string Applications/Go.app" \
      -c "Add :outside:1 string Library/LaunchAgents/dev.mavergreen.go127-updatecheck.plist" "$T/go127/mavergreen.plist"
: > "$w/calls"
PATH="$stub:$PATH" mg uninstall go127 || fail "uninstall must succeed"
[ ! -e "$T/go127" ] && [ ! -e "$T/var/go127" ] || fail "uninstall removes the tree and its var/"
[ ! -e "$V/Applications/Go.app" ] && [ ! -e "$V/Library/LaunchAgents/dev.mavergreen.go127-updatecheck.plist" ] \
  || fail "uninstall removes everything the manifest lists outside the tree"
[ "$(target bin/go)" = ../go126/bin/go ] || fail "uninstalling the selected member selects the one member left"
grep -q "pkgutil --volume $V --forget dev.mavergreen.go127" "$w/calls" || fail "uninstall forgets the receipt on the named volume: $(cat "$w/calls")"
grep -q launchctl "$w/calls" && fail "uninstall on a non-boot volume must not touch launchd: $(cat "$w/calls")"
[ "$(sh "$MG" version)" = "@MAVERGREEN_VERSION@" ] || fail "version prints the stamped version (unstamped in the source tree)"

mkproduct widget widget "" bin/widget
mkdir -p "$V/Applications/Widget.app/Contents" "$V/Library/Extensions" "$V/Library/LaunchAgents" "$T/sibling"
touch "$V/Library/Extensions/marker" "$T/sibling/marker"
touch "$V/Library/LaunchAgents/dev.mavergreen.widget-updatecheck.plist"
"$PB" -c "Add :outside array" \
      -c "Add :outside:0 string Applications/Widget.app" \
      -c "Add :outside:1 string Library" \
      -c "Add :outside:2 string usr/local/mavergreen/sibling" \
      -c "Add :outside:3 string Library/Extensions" \
      -c "Add :outside:4 string Library/LaunchAgents/dev.mavergreen.widget-updatecheck.plist" \
      "$T/widget/mavergreen.plist" >/dev/null
rc=0; PATH="$stub:$PATH" mg uninstall widget 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "uninstall with a refused outside entry must exit non-zero"
[ ! -e "$T/widget" ] || fail "uninstall always removes the product's own tree, even when an outside entry is refused"
[ ! -e "$V/Applications/Widget.app" ] || fail "an outside .app bundle is removed"
[ -d "$V/Library" ] || fail "a bare top-level directory like Library must be refused, not rm -rf'd whole"
grep -q '^mavergreen: refusing to remove Library -- ' "$w/err" || fail "uninstall must name a refused non-bundle directory on stderr"
[ -d "$T/sibling" ] && [ -f "$T/sibling/marker" ] \
  || fail "an outside path under usr/local/mavergreen must be refused -- it can name a sibling product's tree"
grep -q "unsafe outside path 'usr/local/mavergreen/sibling'" "$w/err" \
  || fail "uninstall must name a refused path under the mavergreen tree on stderr"
[ -d "$V/Library/Extensions" ] && [ -f "$V/Library/Extensions/marker" ] \
  || fail "a plain directory like Library/Extensions must be refused, not rm -rf'd whole"
[ ! -e "$V/Library/LaunchAgents/dev.mavergreen.widget-updatecheck.plist" ] \
  || fail "an outside entry AFTER a refused one must still be removed (best-effort, not abort-on-first-failure)"
mkproduct preset preset "" bin/preset
mkdir -p "$V/Applications/Linux Preset.app/Contents"
"$PB" -c "Add :generated array" -c "Add :generated:0 string Applications/Linux Preset.app" \
      -c "Add :generated:1 string Applications/Never Materialized.app" "$T/preset/mavergreen.plist" >/dev/null
PATH="$stub:$PATH" mg uninstall preset 2>"$w/err" \
  || fail "uninstall must succeed when a generated entry was never created: $(cat "$w/err")"
[ ! -e "$V/Applications/Linux Preset.app" ] \
  || fail "uninstall removes an app the product generated at install time, which no payload carries"
mkproduct badgen badgen "" bin/badgen
"$PB" -c "Add :generated array" -c "Add :generated:0 string /Applications" "$T/badgen/mavergreen.plist" >/dev/null
rc=0; PATH="$stub:$PATH" mg uninstall badgen 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "a generated entry in a shape the helper refuses must fail uninstall"
grep -q "unsafe generated path '/Applications'" "$w/err" || fail "uninstall must name the refused generated entry: $(cat "$w/err")"
[ -d "$V/Applications" ] || fail "a refused generated entry must not be removed"
mkproduct slashgen slashgen "" bin/slashgen
mkdir -p "$w/elsewhere/Real.app/Contents"; touch "$w/elsewhere/Real.app/Contents/Info.plist"
ln -s "$w/elsewhere/Real.app" "$V/Applications/Linux Slash.app"
"$PB" -c "Add :generated array" -c "Add :generated:0 string Applications/Linux Slash.app/" "$T/slashgen/mavergreen.plist" >/dev/null
rc=0; PATH="$stub:$PATH" mg uninstall slashgen 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "a generated entry ending in / must fail uninstall"
grep -q "unsafe generated path 'Applications/Linux Slash.app/'" "$w/err" || fail "uninstall must name a refused trailing-slash entry: $(cat "$w/err")"
[ -f "$w/elsewhere/Real.app/Contents/Info.plist" ] \
  || fail "a trailing slash must not make uninstall follow a symlinked bundle and delete its target outside the volume"
mv "$V/Applications" "$w/apps-aside"
mkdir -p "$w/beyond/Linux X.app/Contents"; touch "$w/beyond/Linux X.app/Contents/Info.plist"
ln -s "$w/beyond" "$V/Applications"
mkproduct escape escape "" bin/escape
"$PB" -c "Add :generated array" -c "Add :generated:0 string Applications/Linux X.app" "$T/escape/mavergreen.plist" >/dev/null
rc=0; PATH="$stub:$PATH" mg uninstall escape 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "an entry whose parent resolves outside the volume must fail uninstall"
grep -q "refusing to remove Applications/Linux X.app -- " "$w/err" || fail "uninstall must name the entry whose parent escapes the volume: $(cat "$w/err")"
[ -f "$w/beyond/Linux X.app/Contents/Info.plist" ] \
  || fail "a symlinked ancestor must not make uninstall delete a bundle outside the volume"
[ ! -e "$T/escape" ] || fail "uninstall still removes the product's own tree after refusing an escaping entry"
rm -f "$V/Applications"
mkdir -p "$V/Apps/Linux Y.app/Contents"
ln -s "$V/Apps" "$V/Applications"
mkproduct inapps inapps "" bin/inapps
"$PB" -c "Add :generated array" -c "Add :generated:0 string Applications/Linux Y.app" "$T/inapps/mavergreen.plist" >/dev/null
PATH="$stub:$PATH" mg uninstall inapps 2>"$w/err" \
  || fail "an entry whose parent is a symlink that stays inside the volume must be removable: $(cat "$w/err")"
[ ! -e "$V/Apps/Linux Y.app" ] || fail "a symlinked ancestor that stays inside the volume must not block removal"
rm -f "$V/Applications"; mv "$w/apps-aside" "$V/Applications"
mkproduct varescape varescape "" bin/varescape
mv "$T/var" "$w/var-aside"
mkdir -p "$w/beyond-var/varescape"; touch "$w/beyond-var/varescape/state"
ln -s "$w/beyond-var" "$T/var"
rc=0; PATH="$stub:$PATH" mg uninstall varescape 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "a var dir whose parent resolves outside the volume must fail uninstall"
grep -q "refusing to remove $T/var/varescape -- " "$w/err" || fail "uninstall must name the var dir it refuses: $(cat "$w/err")"
[ -f "$w/beyond-var/varescape/state" ] || fail "a symlinked var/ must not make uninstall delete state outside the volume"
[ ! -e "$T/varescape" ] || fail "uninstall still removes the product's tree after refusing its var dir"
rm -f "$T/var"; mv "$w/var-aside" "$T/var"

mkproduct openssh openssh "" bin/ssh sbin/sshd share/man/man1/ssh.1
chmod 4755 "$T/openssh/bin/ssh"
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/ssh string bin/ssh" \
      -c "Add :replaces:/usr/sbin/sshd string sbin/sshd" \
      -c "Add :replaces:/usr/share/man/man1/ssh.1 string share/man/man1/ssh.1" "$T/openssh/mavergreen.plist"
mkdir -p "$V/usr/bin" "$V/usr/sbin" "$V/usr/share/man/man1" "$V/System/Library/CoreServices"
echo apple-ssh > "$V/usr/bin/ssh"; chmod 711 "$V/usr/bin/ssh"; echo apple-man > "$V/usr/share/man/man1/ssh.1"
SA="$T/var/system-replace/openssh"
sha() { shasum -a 256 < "$1" | awk '{ print $1 }'; }
is_copy() { [ -f "$1" ] && [ ! -L "$1" ] && cmp -s "$1" "$2"; }
"$PB" -c "Add :ProductVersion string 26.0" "$V/System/Library/CoreServices/SystemVersion.plist" >/dev/null
mg system-replace openssh 2>"$w/err" && fail "system-replace must refuse a volume that is not 10.9"
grep -q 'sealed\|10.9' "$w/err" || fail "the refusal must say why"
"$PB" -c "Set :ProductVersion 10.9.5" "$V/System/Library/CoreServices/SystemVersion.plist"
mg system-replace openssh || fail "system-replace on 10.9 must succeed"
is_copy "$V/usr/bin/ssh" "$T/openssh/bin/ssh" \
  || fail "a program's system path becomes a real file equal to the tree file, not a link a sandbox judges by its target"
[ "$(stat -f %Mp%Lp "$V/usr/bin/ssh")" = 4755 ] || fail "the copy keeps the tree file's mode, setuid included: $(stat -f %Mp%Lp "$V/usr/bin/ssh")"
[ "$(cat "$SA/usr/bin/ssh")" = apple-ssh ] || fail "the original is saved"
is_copy "$V/usr/sbin/sshd" "$T/openssh/sbin/sshd" || fail "a program with no original still gets its copy"
[ "$(readlink "$V/usr/share/man/man1/ssh.1")" = /usr/local/mavergreen/openssh/share/man/man1/ssh.1 ] \
  || fail "a man page's system path stays a link into the tree"
[ "$(cat "$SA/usr/share/man/man1/ssh.1")" = apple-man ] || fail "a man page's original is saved"
[ "$("$PB" -c 'Print :replaces:/usr/bin/ssh' "$SA/applied.plist" 2>/dev/null)" = bin/ssh ] \
  || fail "applied.plist records the declaration that was applied"
[ "$("$PB" -c 'Print :copies:/usr/bin/ssh' "$SA/applied.plist" 2>/dev/null)" = "$(sha "$T/openssh/bin/ssh")" ] \
  || fail "applied.plist records the sha256 of the copy it installed"
[ "$("$PB" -c 'Print :copies:/usr/share/man/man1/ssh.1' "$SA/applied.plist" 2>/dev/null)" = link:/usr/local/mavergreen/openssh/share/man/man1/ssh.1 ] \
  || fail "applied.plist records what a man-page entry should hold as link:<target>"
[ "$("$PB" -c 'Print :originals:/usr/bin/ssh' "$SA/applied.plist" 2>/dev/null)" = "$(sha "$SA/usr/bin/ssh")" ] \
  || fail "applied.plist records the sha256 of the original it found, before changing anything"
[ "$("$PB" -c 'Print :originals:/usr/sbin/sshd' "$SA/applied.plist" 2>/dev/null)" = - ] \
  || fail "applied.plist records - for a system path that had no original"
[ -f "$SA/.replaced" ] || fail "a finished system-replace marks .replaced"
mg check 2>"$w/err" || true
if grep -q 'usr/bin/ssh\|usr/sbin/sshd\|man1/ssh.1' "$w/err"; then fail "check must not report a fresh replacement: $(cat "$w/err")"; fi
mg system-replace openssh || fail "system-replace must be idempotent"
[ "$(cat "$SA/usr/bin/ssh")" = apple-ssh ] || fail "a second replace must not overwrite the saved original with our own copy"
[ ! -e "$SA/usr/sbin/sshd" ] || fail "a second replace must not save our own copy as an original"
rm "$V/usr/bin/ssh"; echo apple-update > "$V/usr/bin/ssh"
mg check 2>"$w/err" && fail "a replaced path that is no longer our copy is drift, and check must fail"
grep -qF "/usr/bin/ssh is no longer openssh's copy" "$w/err" \
  || fail "check must call an overwritten copy no longer ours, judged by its recorded sha256, not stale: $(cat "$w/err")"
if grep -q 'usr/bin/ssh is stale' "$w/err"; then fail "an overwritten copy is not stale: $(cat "$w/err")"; fi
mg system-replace openssh 2>"$w/err" && fail "system-replace must refuse a drifted path whose original was already saved"
grep -q 'system-restore\|already saved' "$w/err" || fail "the refusal must say to run system-restore"
[ "$(cat "$SA/usr/bin/ssh")" = apple-ssh ] \
  || fail "a refused system-replace must not touch the saved original"
[ -f "$SA/.replaced" ] || fail "a refused system-replace must not remove the .replaced marker"
[ "$(cat "$V/usr/bin/ssh")" = apple-update ] || fail "a refused system-replace must leave the drifted path alone"
rm "$V/usr/bin/ssh"; cp -p "$T/openssh/bin/ssh" "$V/usr/bin/ssh"
mg system-restore openssh || fail "system-restore must succeed"
[ "$(cat "$V/usr/bin/ssh")" = apple-ssh ] && [ ! -L "$V/usr/bin/ssh" ] || fail "restore puts the original back"
[ "$(stat -f %Mp%Lp "$V/usr/bin/ssh")" = 0711 ] || fail "restore puts the original's mode back"
[ ! -e "$V/usr/sbin/sshd" ] && [ ! -L "$V/usr/sbin/sshd" ] || fail "restore removes a copy that had no original"
[ "$(cat "$V/usr/share/man/man1/ssh.1")" = apple-man ] && [ ! -L "$V/usr/share/man/man1/ssh.1" ] \
  || fail "restore puts a man page's original back over its link"
[ ! -e "$T/var/system-replace/openssh" ] || fail "restore clears its saved state"
gid="$(id -g)"; GD="$V/var/db/dslocal/nodes/Default"
own_group() {  # $1 name  $2.. members; writes the fake volume's directory-service record for the test user's gid
  mkdir -p "$GD/groups"; rm -f "$GD/groups/$1.plist"; _gn="$1"; shift
  "$PB" -c "Add :gid array" -c "Add :gid:0 string $gid" -c "Add :users array" "$GD/groups/$_gn.plist" >/dev/null
  _k=0; for _m in "$@"; do "$PB" -c "Add :users:$_k string $_m" "$GD/groups/$_gn.plist"; _k=$((_k + 1)); done
  mkdir -p "$GD/users"; [ -f "$GD/users/root.plist" ] \
    || "$PB" -c "Add :gid array" -c "Add :gid:0 string 0" -c "Add :name array" -c "Add :name:0 string root" "$GD/users/root.plist" >/dev/null
}
mkproduct ownchk ownchk "" bin/ownchk
"$PB" -c "Add :replaces dict" -c "Add :replaces:/opt/sys/ownchk string bin/ownchk" "$T/ownchk/mavergreen.plist"
mkdir -p "$V/opt/sys" "$V/opt/own dir"; echo apple-own > "$V/opt/own dir/real"; ln -s "/opt/own dir/real" "$V/opt/sys/ownchk"
refuses_untouched() {  # $1 why  $2 text the refusal must name
  mg system-replace ownchk 2>"$w/err" && fail "system-replace must refuse: $1"
  grep -q "$2" "$w/err" || fail "the refusal must name $2 ($1): $(cat "$w/err")"
  [ "$(readlink "$V/opt/sys/ownchk")" = "/opt/own dir/real" ] \
    || fail "a refused system-replace must change nothing ($1)"
  [ ! -e "$T/var/system-replace/ownchk" ] || fail "a refused system-replace must leave no .replaced ($1)"
}
chmod 777 "$V/opt/own dir"
refuses_untouched "a world-writable directory on the way" "own dir"
chmod 777 "$V/opt/sys"
refuses_untouched "a world-writable directory holding the system path" "opt/sys"
chmod 755 "$V/opt/sys"
chmod 755 "$V/opt/own dir"; chmod 777 "$T/ownchk/bin"
refuses_untouched "a world-writable directory above the tree target" "ownchk/bin"
chmod 755 "$T/ownchk/bin"
chgrp "$gid" "$V/opt/own dir"; chmod 775 "$V/opt/own dir"
own_group ownchkgrp alice
refuses_untouched "a group-writable directory whose group lists a non-root member" "own dir"
rm -f "$GD/groups/ownchkgrp.plist"
refuses_untouched "a group-writable directory whose group record is missing" "own dir"
own_group ownchkgrp
mkdir -p "$GD/users"
"$PB" -c "Add :gid array" -c "Add :gid:0 string $gid" "$GD/users/bob.plist" >/dev/null
refuses_untouched "a group-writable directory whose group is some user's primary group" "own dir"
rm -f "$GD/users/bob.plist"
own_group ownchkgrp root
mg system-replace ownchk || fail "a group-writable directory whose only member is root (stock wheel) must be accepted"
is_copy "$V/opt/sys/ownchk" "$T/ownchk/bin/ownchk" || fail "an accepted replace copies the program to the path"
mg check 2>"$w/err" || true
if grep -q "not root-only" "$w/err"; then fail "check must not report root-only directories: $(cat "$w/err")"; fi
chmod 777 "$V/opt/sys"
mg check 2>"$w/err" && fail "check must fail once a directory on a replaced path becomes world-writable"
grep -q "opt/sys is not root-only" "$w/err" || fail "check must name the directory that became writable: $(cat "$w/err")"
chmod 755 "$V/opt/sys"
mg system-restore ownchk || fail "setup: system-restore ownchk must succeed"
rm -rf "$T/ownchk" "$GD" "$V/opt"
own_set() {  # $1 group  $2 key  $3 value; adds a one-element array to the group's record
  "$PB" -c "Add :$2 array" -c "Add :$2:0 string $3" "$GD/groups/$1.plist" >/dev/null
}
ownfix() {  # $1 the replaced system path, under the fake volume; $2 optional: make /opt/sys group-writable by the test gid
  rm -rf "$T/ownchk" "$V/opt" "$GD"
  mkproduct ownchk ownchk "" bin/ownchk
  "$PB" -c "Add :replaces dict" -c "Add :replaces:$1 string bin/ownchk" "$T/ownchk/mavergreen.plist"
  mkdir -p "$V$(dirname "$1")"; echo apple-own > "$V$1"
}
refused() {  # $1 why  $2 text the refusal must contain
  mg system-replace ownchk 2>"$w/err" && fail "system-replace must refuse: $1"
  grep -q "$2" "$w/err" || fail "the refusal must say '$2' ($1): $(cat "$w/err")"
  [ ! -e "$T/var/system-replace/ownchk" ] || fail "a refused system-replace must leave no .replaced ($1)"
}
accepted() {
  mg system-replace ownchk 2>"$w/err" || fail "system-replace must accept: $1: $(cat "$w/err")"
  mg system-restore ownchk || fail "setup: restoring after the accepted case ($1) must succeed"
}
shared_dir() { chgrp "$gid" "$V/opt/sys"; chmod 775 "$V/opt/sys"; }

ownfix /opt/sys/ownchk
chmod +a "everyone allow delete_child" "$V/opt/sys" || fail "setup: chmod +a must work on the test volume"
refused "an ACL allow entry on a directory of the path" "opt/sys carries an ACL"
rm -rf "$V/opt"; ownfix /opt/sys/ownchk
chmod +a "everyone deny add_subdirectory" "$V/opt/sys"
accepted "a deny-only ACL"
chmod +a "everyone allow write" "$T/ownchk/bin/ownchk" || fail "setup: chmod +a on the tree file"
refused "an ACL allow entry on the tree file" "ownchk/bin/ownchk carries an ACL"

ownfix /opt/sys/ownchk; shared_dir
own_group g1 root; own_set g1 nestedgroups ABCD
refused "a group with a nested group" "opt/sys is not root-only"
own_group g1 root; own_set g1 groupmembers 11111111-2222-3333-4444-555555555555
refused "a group with a non-root member UUID" "opt/sys is not root-only"
own_group g1 root; rm -f "$GD/groups/g1.plist"; own_group g1 root; own_set g1 groupmembers FFFFEEEE-DDDD-CCCC-BBBB-AAAA00000000
accepted "a group whose only member UUID is root's"
own_group g1 root; own_group g2 alice
refused "a second record with the same gid lists a non-root member" "opt/sys is not root-only"
rm -f "$GD/groups/g2.plist"; mkdir -p "$GD/users"; echo garbage > "$GD/users/bad.plist"
refused "an unreadable user record" "opt/sys is not root-only"
rm -f "$GD/users/bad.plist"
accepted "root-only group with every record readable"
rm -f "$GD/users/root.plist"
refused "a volume whose user records do not include root's, so its primary groups were never read (M4)" "opt/sys is not root-only"
own_group g1 root; "$PB" -c "Delete :users" -c "Add :users string alice" "$GD/groups/g1.plist"
refused "a group whose users key is a string rather than a list, which hides its members (M4)" "opt/sys is not root-only"
own_group g1 root; "$PB" -c "Add :name array" -c "Add :name:0 string carol" -c "Add :gid string $gid" "$GD/users/carol.plist" >/dev/null
refused "a user record whose gid is a string rather than a list, which hides its primary group (M4)" "opt/sys is not root-only"
rm -f "$GD/users/carol.plist"
accepted "a root-only group once every record is well formed"

ownfix /opt/sys/ownchk
mkdir -p "$V/opt/h1" "$V/opt/h2"; rm "$V/opt/sys/ownchk"
ln -s /opt/h1/l "$V/opt/sys/ownchk"; ln -s /opt/h2/real "$V/opt/h1/l"; chmod 777 "$V/opt/h2"
refused "a second link hop through a world-writable directory" "opt/h2 is not root-only"

ownfix /opt/sys/ownchk
mkdir -p "$V/opt/ww"; echo x > "$V/opt/ww/x"; chmod 777 "$V/opt/ww"; rm "$T/ownchk/bin/ownchk"; ln -s ../../../../../opt/ww/x "$T/ownchk/bin/ownchk"
refused "a tree file that is a link into a world-writable directory" "opt/ww is not root-only"

ownfix /opt/A/B/C/ownchk
rm -rf "$V/opt/A/B"; mkdir -p "$V/opt/X/Y/C"; echo apple-own > "$V/opt/X/Y/C/ownchk"; ln -s /opt/X/Y "$V/opt/A/B"
chmod 777 "$V/opt/A"
refused "a world-writable directory that holds an intermediate symlink" "opt/A is not root-only"

ownfix /opt/sys/ownchk
rm "$V/opt/sys/ownchk"; ln -s /opt/l1 "$V/opt/sys/ownchk"; ln -s /opt/l2 "$V/opt/l1"; ln -s /opt/l1 "$V/opt/l2"
refused "a link loop" "link loop"

ownfix /opt/sys/ownchk; shared_dir; own_group g1 root
chgrp "$gid" "$T/ownchk/bin/ownchk"; chmod 664 "$T/ownchk/bin/ownchk"
accepted "a group-writable tree file whose group is root-only"
own_group g1 alice; chmod 755 "$V/opt/sys"
refused "a group-writable tree file with a non-root group member" "ownchk/bin/ownchk is not root-only"
rm -rf "$T/ownchk" "$GD" "$V/opt"

( R=""; PB="$PB"; MAVERGREEN_TRUSTED_UID=4242
  eval "$(awk '/^words_ok\(\)/ { p = 1 } /^offender_text\(\)/ { p = 0 } p' "$MG")"
  root_only_chain / >/dev/null ) \
  || fail "the test uid seam must be ignored when the root is /, or a production root could be judged by a caller-chosen uid"
dscls="$w/dscl"; mkdir -p "$dscls"
cat > "$dscls/dscl" <<'STUB'
#!/bin/sh
case "$*" in
  ". -search /Groups PrimaryGroupID 0") printf 'wheel\t\tPrimaryGroupID = (\n    0\n)\n' ;;
  ". -read /Groups/wheel GroupMembership") echo "GroupMembership: root" ;;
  ". -read /Groups/wheel GroupMembers") echo "No such key: GroupMembers" ;;
  ". -read /Groups/wheel NestedGroups") echo "No such key: NestedGroups" ;;
  ". -list /Users PrimaryGroupID") printf '%s' "$DSCL_USERS" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$dscls/dscl"
bootgroup() {  # $1 what dscl lists as each user's primary group; succeeds when wheel (gid 0) is root-only on the boot volume
  ( R=""; PB="$PB"; PATH="$dscls:$PATH"; DSCL_USERS="$1"; export DSCL_USERS
    eval "$(awk '/^words_ok\(\)/ { p = 1 } /^offender_text\(\)/ { p = 0 } p' "$MG")"
    group_root_only 0 )
}
bootgroup "$(printf 'root 0\ndaemon 1\n')" || fail "setup: on the boot volume, wheel is root-only when dscl lists root and no other user in it"
bootgroup "$(printf 'root 0\nalice 0\n')" && fail "setup: on the boot volume, a user whose primary group is wheel makes it not root-only"
bootgroup "" && fail "an empty user list on the boot volume is not proof that no user has wheel as primary group: root's own record must be among those read (M4)"

mkproduct twoentry twoentry "" bin/a
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/a string bin/a" \
      -c "Add :replaces:/usr/bin/z string bin/missing" "$T/twoentry/mavergreen.plist"
echo original-a > "$V/usr/bin/a"
mg system-replace twoentry 2>"$w/err" \
  && fail "a refused entry must refuse the whole system-replace, even when an earlier entry already looked fine"
grep -q 'bin/missing' "$w/err" || fail "the refusal must name the entry it refused"
[ ! -L "$V/usr/bin/a" ] && [ "$(cat "$V/usr/bin/a")" = original-a ] \
  || fail "a refused first-time system-replace must change nothing, even for an entry that comes before the refused one"
[ ! -e "$T/var/system-replace/twoentry" ] || fail "a refused first-time system-replace must leave no .replaced"

mkproduct escapee escapee "" bin/f
"$PB" -c "Add :replaces dict" -c "Add :replaces:/../escaped-by-mavergreen-test string bin/f" \
      "$T/escapee/mavergreen.plist"
mg system-replace escapee 2>"$w/err" && fail "a replaces key containing .. must be refused"
grep -q unsafe "$w/err" || fail "the refusal must say the entry is unsafe"
[ ! -e "$V/../escaped-by-mavergreen-test" ] || fail "a refused .. entry must not touch anything outside the volume"
[ ! -L "$V/usr/bin/f" ] && [ ! -e "$V/usr/bin/f" ] || fail "a refused .. entry must not touch /usr/bin either"
[ ! -e "$T/var/system-replace/escapee" ] || fail "a refused .. entry must leave no .replaced"

mkproduct dropped dropped "" bin/h bin/h2
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/h string bin/h" \
      -c "Add :replaces:/usr/bin/h2 string bin/h2" "$T/dropped/mavergreen.plist"
echo apple-h > "$V/usr/bin/h"
mg system-replace dropped || fail "setup: system-replace dropped must succeed"
"$PB" -c "Delete :replaces:/usr/bin/h" -c "Delete :replaces:/usr/bin/h2" "$T/dropped/mavergreen.plist"
mg system-restore dropped || fail "system-restore must succeed even when its manifest no longer lists the entry"
[ "$(cat "$V/usr/bin/h")" = apple-h ] && [ ! -L "$V/usr/bin/h" ] \
  || fail "system-restore must put back an original whose manifest entry was since dropped"
[ ! -e "$V/usr/bin/h2" ] \
  || fail "system-restore must act on applied.plist, removing a copy with no original whose manifest entry was since dropped"
[ ! -e "$T/var/system-replace/dropped" ] || fail "system-restore must clear its saved state once everything is back"

mkproduct driftfile driftfile "" bin/k
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/k string bin/k" "$T/driftfile/mavergreen.plist"
echo apple-k > "$V/usr/bin/k"
mg system-replace driftfile || fail "setup: system-replace driftfile must succeed"
rm "$V/usr/bin/k"; echo updated-k > "$V/usr/bin/k"
rc=0; mg system-restore driftfile 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "system-restore must fail when the live path is no longer our link"
[ "$(cat "$V/usr/bin/k")" = updated-k ] || fail "system-restore must not clobber a drifted live path"
[ "$(cat "$T/var/system-replace/driftfile/usr/bin/k")" = apple-k ] \
  || fail "system-restore must keep the saved original when it cannot put it back"
grep -q /usr/bin/k "$w/err" || fail "system-restore must name the path it could not restore"

mkproduct driftdir driftdir "" bin/l
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/l string bin/l" "$T/driftdir/mavergreen.plist"
echo apple-l > "$V/usr/bin/l"
mg system-replace driftdir || fail "setup: system-replace driftdir must succeed"
rm "$V/usr/bin/l"; mkdir "$V/usr/bin/l"
rc=0; mg system-restore driftdir 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "system-restore must fail when a directory now occupies the live path"
[ -d "$V/usr/bin/l" ] || fail "system-restore must not remove or move into a directory occupying the live path"
[ "$(cat "$T/var/system-replace/driftdir/usr/bin/l")" = apple-l ] \
  || fail "system-restore must keep the saved original when the live path is a directory"

mkproduct rostore rostore "" bin/i
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/i string bin/i" "$T/rostore/mavergreen.plist"
echo apple-i > "$V/usr/bin/i"
mg system-replace rostore || fail "setup: system-replace rostore must succeed"
chmod 555 "$V/usr/bin"
rc=0; mg system-restore rostore 2>"$w/err" || rc=$?
chmod 755 "$V/usr/bin"
[ "$rc" -ne 0 ] || fail "system-restore must fail when it cannot remove the link (read-only directory)"
[ -f "$T/var/system-replace/rostore/usr/bin/i" ] || fail "a failed system-restore must keep the saved original so a retry can use it"
[ ! -e "$T/var/system-replace/rostore/.replaced" ] \
  || fail "a restore that stopped partway has already unmarked .replaced, so the next upgrade does not re-apply what the admin asked to undo (M6)"
mg check 2>"$w/err" || true
grep -qF "rostore: a System Replace did not finish" "$w/err" || fail "check reports a restore that stopped partway as unfinished (M6): $(cat "$w/err")"
mg system-restore rostore || fail "a retried system-restore must succeed once the obstruction is gone"
[ "$(cat "$V/usr/bin/i")" = apple-i ] || fail "the retried system-restore must put the original back"

mkproduct rouninstall rouninstall "" bin/j
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/j string bin/j" "$T/rouninstall/mavergreen.plist"
echo apple-j > "$V/usr/bin/j"
mg system-replace rouninstall || fail "setup: system-replace rouninstall must succeed"
chmod 555 "$V/usr/bin"
rc=0; PATH="$stub:$PATH" mg uninstall rouninstall 2>"$w/err" || rc=$?
chmod 755 "$V/usr/bin"
[ "$rc" -ne 0 ] || fail "uninstall must fail when its system-restore fails"
[ -f "$T/rouninstall/mavergreen.plist" ] || fail "a failed system-restore must stop uninstall before it removes the product's tree"
[ -f "$T/var/system-replace/rouninstall/usr/bin/j" ] \
  || fail "a failed system-restore during uninstall must keep the saved original so a retry can use it"
PATH="$stub:$PATH" mg uninstall rouninstall || fail "a retried uninstall must succeed once the obstruction is gone"
[ ! -e "$T/rouninstall" ] || fail "the retried uninstall must finish removing the product"

mkproduct dirorig dirorig "" bin/m
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/m string bin/m" "$T/dirorig/mavergreen.plist"
mkdir -p "$V/usr/bin/m"; echo inner > "$V/usr/bin/m/inner"
mg system-replace dirorig 2>"$w/err" && fail "system-replace must refuse an entry whose live path is a real directory"
grep -q directory "$w/err" || fail "the refusal must say it is a directory"
[ -d "$V/usr/bin/m" ] && [ ! -L "$V/usr/bin/m" ] && [ -f "$V/usr/bin/m/inner" ] \
  || fail "a refused directory original must be left intact"
[ ! -e "$T/var/system-replace/dirorig" ] || fail "a refused directory original must leave no .replaced"

mkproduct wholedir wholedir "" bin/n
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin string bin/n" "$T/wholedir/mavergreen.plist"
mg system-replace wholedir 2>"$w/err" && fail "system-replace must refuse a replaces key that names a whole directory"
grep -q directory "$w/err" || fail "the refusal must say it is a directory"
[ -d "$V/usr/bin" ] && [ ! -L "$V/usr/bin" ] || fail "a refused whole-directory key must leave /usr/bin intact"
[ ! -e "$T/var/system-replace/wholedir" ] || fail "a refused whole-directory key must leave no .replaced"

mkproduct edited edited "" bin/ed1
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/ed1 string bin/ed1" "$T/edited/mavergreen.plist"
echo apple-ed1 > "$V/usr/bin/ed1"
mg system-replace edited || fail "setup: system-replace edited must succeed"
echo tampered >> "$V/usr/bin/ed1"
rc=0; mg system-restore edited 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "system-restore must fail when a copy was edited after it was installed"
grep -qF "/usr/bin/ed1 was changed after mavergreen installed it; keeping the saved original" "$w/err" \
  || fail "system-restore must say the copy was changed and the original is kept: $(cat "$w/err")"
[ "$(tail -n 1 "$V/usr/bin/ed1")" = tampered ] || fail "system-restore must leave an edited copy in place"
[ "$(cat "$T/var/system-replace/edited/usr/bin/ed1")" = apple-ed1 ] \
  || fail "system-restore must keep the saved original of an edited copy for a retry"

mkproduct noorig noorig "" bin/no1
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/no1 string bin/no1" "$T/noorig/mavergreen.plist"
mg system-replace noorig || fail "setup: system-replace noorig must succeed"
echo tampered >> "$V/usr/bin/no1"
rc=0; mg system-restore noorig 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "system-restore must fail when a copy with no original was changed after it was installed"
grep -qF "/usr/bin/no1 was changed after mavergreen installed it" "$w/err" \
  || fail "system-restore must say the copy with no original was changed: $(cat "$w/err")"
[ "$(tail -n 1 "$V/usr/bin/no1")" = tampered ] || fail "system-restore must leave a changed copy with no original in place"
rm "$V/usr/bin/no1"
mg system-restore noorig || fail "setup: system-restore noorig must succeed once the changed copy is gone"

mkproduct same same "" bin/sm
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/sm string bin/sm" "$T/same/mavergreen.plist"
cp "$T/same/bin/sm" "$V/usr/bin/sm"; ino="$(stat -f %i "$V/usr/bin/sm")"
mg system-replace same || fail "setup: system-replace same must succeed"
[ "$(stat -f %i "$T/var/system-replace/same/usr/bin/sm" 2>/dev/null)" = "$ino" ] \
  || fail "an original byte-identical to the tree file, with no sha record, must still be saved, not taken for our copy"
mg system-restore same || fail "system-restore same must succeed"
[ -f "$V/usr/bin/sm" ] && [ "$(stat -f %i "$V/usr/bin/sm")" = "$ino" ] \
  || fail "restore must put back an original that was byte-identical to the tree file"

mkproduct orphan orphan "" bin/or share/man/man1/or.1
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/or string bin/or" \
      -c "Add :replaces:/usr/share/man/man1/or.1 string share/man/man1/or.1" "$T/orphan/mavergreen.plist"
mg system-replace orphan || fail "setup: system-replace orphan must succeed"
cp -p "$T/orphan/bin/or" "$V/usr/bin/.or.mavergreen-tmp"; chmod 4755 "$V/usr/bin/.or.mavergreen-tmp"
ln -s /usr/local/mavergreen/orphan/share/man/man1/or.1 "$V/usr/share/man/man1/.or.1.mavergreen-tmp"
mg system-restore orphan || fail "system-restore orphan must succeed"
[ ! -e "$V/usr/bin/.or.mavergreen-tmp" ] \
  || fail "restore must remove a staging file a killed replace left behind -- a hidden setuid copy in a system directory"
[ ! -L "$V/usr/share/man/man1/.or.1.mavergreen-tmp" ] || fail "restore must remove our own staged link a killed replace left behind"

mvstub="$w/faults"; mkdir -p "$mvstub"
faultstub() {  # $1 tool  $2 the variable naming the path suffix at which it fails
  printf '#!/bin/sh\nfor a; do last="$a"; done\nif [ -n "$%s" ]; then case "$last" in */"$%s") exit 1 ;; esac; fi\nexec /bin/%s "$@"\n' "$2" "$2" "$1" > "$mvstub/$1"
  chmod +x "$mvstub/$1"
}
faultstub mv MV_FAIL; faultstub ln LN_FAIL; faultstub rm RM_FAIL; faultstub cp CP_FAIL
printf '#!/bin/sh\n[ -z "$FIND_FAIL" ] || exit 1\nexec /usr/bin/find "$@"\n' > "$mvstub/find"; chmod +x "$mvstub/find"
cat > "$mvstub/stat" <<'STUB'
#!/bin/sh
if [ -n "$STAT_OTHER" ] && [ "$1" = -f ] && [ "$2" = %d ]; then case "$3" in */"$STAT_OTHER") echo 999999; exit 0 ;; esac; fi
exec /usr/bin/stat "$@"
STUB
chmod +x "$mvstub/stat"
mkproduct retry retry "" bin/ra1 bin/ra2
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/ra1 string bin/ra1" \
      -c "Add :replaces:/usr/bin/ra2 string bin/ra2" "$T/retry/mavergreen.plist"
echo apple-ra1 > "$V/usr/bin/ra1"; echo apple-ra2 > "$V/usr/bin/ra2"
mg system-replace retry || fail "setup: system-replace retry must succeed"
echo tampered >> "$V/usr/bin/ra2"
mg system-restore retry 2>"$w/err" && fail "setup: a restore whose second copy was edited must fail"
is_copy "$V/usr/bin/ra1" "$T/retry/bin/ra1" && [ -f "$T/var/system-replace/retry/.replaced" ] \
  || fail "a restore that would refuse one entry puts nothing back, not even an entry before it (R64)"
cp -p "$T/retry/bin/ra2" "$V/usr/bin/ra2"
(PATH="$mvstub:$PATH" MV_FAIL=usr/bin/ra2 mg system-restore retry 2>"$w/err") && fail "setup: a restore whose second move fails must fail"
[ "$(cat "$V/usr/bin/ra1")" = apple-ra1 ] || fail "setup: the partial restore put the first original back"
"$PB" -c 'Print :replaces:/usr/bin/ra1' "$T/var/system-replace/retry/applied.plist" >/dev/null 2>&1 \
  && fail "restore must drop each entry from applied.plist as it completes it"
"$PB" -c 'Print :copies:/usr/bin/ra1' "$T/var/system-replace/retry/applied.plist" >/dev/null 2>&1 \
  && fail "restore must drop a completed entry's sha256 record too"
mg system-restore retry 2>"$w/err" || fail "the retried restore must succeed once the move works: $(cat "$w/err")"
if grep -q ra1 "$w/err"; then fail "a retried restore must say nothing about an entry an earlier attempt finished: $(cat "$w/err")"; fi
[ "$(cat "$V/usr/bin/ra2")" = apple-ra2 ] || fail "the retried restore puts the second original back"
[ ! -e "$T/var/system-replace/retry" ] || fail "the retried restore clears the state once the last entry is gone"

mkproduct stale stale "" bin/st
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/st string bin/st" "$T/stale/mavergreen.plist"
mg system-replace stale || fail "setup: system-replace stale must succeed"
mg check 2>"$w/err" || true
if grep -q 'usr/bin/st ' "$w/err"; then fail "check must not report a copy that matches its tree file: $(cat "$w/err")"; fi
echo newer >> "$T/stale/bin/st"
mg check 2>"$w/err" && fail "check must fail when a copy no longer matches its tree file"
grep -qF "/usr/bin/st is stale: it no longer matches /usr/local/mavergreen/stale/bin/st" "$w/err" \
  || fail "check must name the stale copy and its tree file: $(cat "$w/err")"
mg system-restore stale || fail "setup: system-restore stale must succeed"

mkproduct spacey spacey "" "bin/s p"
"$PB" -c "Add :replaces dict" -c "Add ':replaces:/usr/bin/s p' string 'bin/s p'" "$T/spacey/mavergreen.plist"
echo apple-sp > "$V/usr/bin/s p"
mg system-replace spacey || fail "system-replace must accept an entry whose system path has a space"
is_copy "$V/usr/bin/s p" "$T/spacey/bin/s p" || fail "an entry whose system path has a space must be replaced by a copy"
[ "$("$PB" -c 'Print ":replaces:/usr/bin/s p"' "$T/var/system-replace/spacey/applied.plist" 2>/dev/null)" = "bin/s p" ] \
  || fail "applied.plist must record an entry whose system path has a space"
mg check 2>"$w/err" || true
if grep -q 'usr/bin/s p' "$w/err"; then fail "check must read an entry whose system path has a space: $(cat "$w/err")"; fi
mg system-restore spacey || fail "system-restore must succeed for an entry whose system path has a space"
[ "$(cat "$V/usr/bin/s p")" = apple-sp ] || fail "restore puts back an original whose system path has a space"
[ ! -e "$T/var/system-replace/spacey" ] || fail "restore of a spaced entry clears its saved state"

mkproduct hardlink hardlink "" bin/gzip
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/gzip string bin/gzip" "$T/hardlink/mavergreen.plist"
echo apple-gzip > "$V/usr/bin/gzip"; ln "$V/usr/bin/gzip" "$V/usr/bin/gunzip"
ino="$(stat -f %i "$V/usr/bin/gunzip")"
mg system-replace hardlink || fail "setup: system-replace hardlink must succeed"
[ "$(stat -f %i "$T/var/system-replace/hardlink/usr/bin/gzip")" = "$ino" ] \
  || fail "the saved original must be the original's inode, not a copy of it"
[ "$(cat "$V/usr/bin/gunzip")" = apple-gzip ] || fail "replacing one name of a hardlink group must leave its siblings alone"
mg system-restore hardlink || fail "system-restore hardlink must succeed"
[ "$(stat -f %i "$V/usr/bin/gzip")" = "$ino" ] && [ "$(stat -f %i "$V/usr/bin/gunzip")" = "$ino" ] \
  || fail "a restored original must be the same inode as its hardlink siblings again"

mkproduct unread unread "" bin/u
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/u string bin/u" "$T/unread/mavergreen.plist"
cp "$T/unread/bin/u" "$V/usr/bin/u"; ino="$(stat -f %i "$V/usr/bin/u")"
chmod 000 "$T/unread/bin/u"
mg system-replace unread 2>"$w/err" && fail "system-replace must fail when it cannot read the tree file"
grep -q "cannot read" "$w/err" || fail "the refusal must say it cannot read the tree file: $(cat "$w/err")"
chmod 644 "$T/unread/bin/u"
[ -f "$V/usr/bin/u" ] && [ "$(stat -f %i "$V/usr/bin/u")" = "$ino" ] \
  || fail "a copy that could not be staged must leave the system path holding its original, never absent"
[ ! -e "$T/var/system-replace/unread/usr" ] || fail "a copy that could not be staged must save nothing"
[ ! -e "$T/var/system-replace/unread/.replaced" ] || fail "a failed system-replace must not mark .replaced"
mg system-restore unread || fail "system-restore after a replace that changed nothing must succeed"
[ "$(cat "$V/usr/bin/u")" = unread ] && [ "$(stat -f %i "$V/usr/bin/u")" = "$ino" ] \
  || fail "system-restore with no save and no sha record must leave an original identical to the tree file, never take it for our copy"
[ ! -e "$T/var/system-replace/unread" ] || fail "system-restore after a replace that changed nothing clears its state"

halfway() {
  mkproduct halfway halfway "" bin/hf1 bin/hf2
  "$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/hf1 string bin/hf1" \
        -c "Add :replaces:/usr/bin/hf2 string bin/hf2" "$T/halfway/mavergreen.plist"
  echo apple-hf1 > "$V/usr/bin/hf1"; echo apple-hf2 > "$V/usr/bin/hf2"
  (PATH="$mvstub:$PATH" MV_FAIL="usr/bin/$1" mg system-replace halfway 2>"$w/err") && fail "setup: a replace whose last move fails must fail"
  HB="$T/var/system-replace/halfway"
}
halfway hf2
mg check 2>"$w/err" && fail "check must fail while a System Replace is half finished"
grep -qF "halfway: a System Replace did not finish; run mavergreen system-replace halfway or mavergreen system-restore halfway" "$w/err" \
  || fail "check must report a product with applied.plist and no .replaced: $(cat "$w/err")"
is_copy "$V/usr/bin/hf1" "$T/halfway/bin/hf1" || fail "setup: the first entry of the half-finished replace is a copy"
[ "$(stat -f %i "$HB/usr/bin/hf2")" = "$(stat -f %i "$V/usr/bin/hf2")" ] \
  || fail "setup: interrupted between ln and mv, the save and the system path are one inode"
[ ! -e "$V/usr/bin/.hf2.mavergreen-tmp" ] || fail "a failed swap must not leave its staged copy behind"
[ ! -e "$HB/.replaced" ] || fail "a half-finished replace must not mark .replaced, which is marked last"
[ "$("$PB" -c 'Print :copies:/usr/bin/hf1' "$HB/applied.plist" 2>/dev/null)" = "$(sha "$T/halfway/bin/hf1")" ] \
  || fail "each copy's sha256 must be recorded right after it is swapped in, before a later entry fails"
mg system-replace halfway 2>"$w/err" || fail "a rerun must complete a replace interrupted between saving and swapping: $(cat "$w/err")"
is_copy "$V/usr/bin/hf2" "$T/halfway/bin/hf2" || fail "the rerun must swap the copy in"
[ "$(cat "$HB/usr/bin/hf2")" = apple-hf2 ] || fail "the rerun must keep the original it had already saved"
[ -f "$HB/.replaced" ] || fail "the completed rerun marks .replaced"
mg system-restore halfway || fail "setup: system-restore halfway must succeed"
[ "$(cat "$V/usr/bin/hf1")" = apple-hf1 ] && [ "$(cat "$V/usr/bin/hf2")" = apple-hf2 ] || fail "setup: halfway restored"
rm -rf "$T/halfway"
halfway hf2
PATH="$stub:$PATH" mg uninstall halfway 2>"$w/err" || fail "uninstall must restore a half-finished replace: $(cat "$w/err")"
[ "$(cat "$V/usr/bin/hf1")" = apple-hf1 ] && [ ! -L "$V/usr/bin/hf1" ] \
  || fail "uninstall must act on applied.plist even without .replaced, putting back the original of the copy it swapped in"
[ "$(cat "$V/usr/bin/hf2")" = apple-hf2 ] || fail "uninstall must leave an original that was saved but never swapped"
[ ! -e "$T/var/system-replace/halfway" ] \
  || fail "restoring a save that is the system path's own inode removes the save; rename(2) between two links to one file does nothing"

rm -rf "$T/halfway"
halfway hf1
[ "$(cat "$V/usr/bin/hf1")" = apple-hf1 ] && [ "$(cat "$V/usr/bin/hf2")" = apple-hf2 ] \
  || fail "setup: a replace interrupted at its first swap leaves every system path holding its original"
"$PB" -c 'Print :replaces:/usr/bin/hf2' "$HB/applied.plist" >/dev/null 2>&1 \
  || fail "applied.plist must hold the whole declaration before the first system path changes"
PATH="$stub:$PATH" mg uninstall halfway 2>"$w/err" || fail "uninstall must restore a replace interrupted at its first swap: $(cat "$w/err")"
[ "$(cat "$V/usr/bin/hf1")" = apple-hf1 ] || fail "uninstall must leave an original that was saved but never swapped"
[ ! -e "$T/var/system-replace/halfway" ] \
  || fail "applied.plist is written before the first change, so uninstall finds and clears a save made before any swap"

mkproduct linkdir linkdir "" bin/ld
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/ld string bin/ld" "$T/linkdir/mavergreen.plist"
mkdir -p "$V/opt/ldtarget"; ln -s ../../opt/ldtarget "$V/usr/bin/ld"
mg system-replace linkdir 2>"$w/err" && fail "system-replace must refuse a program entry whose system path is a link to a directory"
grep -q 'link to a directory' "$w/err" || fail "the refusal must say the path is a link to a directory: $(cat "$w/err")"
[ "$(readlink "$V/usr/bin/ld")" = ../../opt/ldtarget ] && [ -z "$(ls -A "$V/opt/ldtarget")" ] \
  || fail "a refused link to a directory must be left alone, nothing moved into the directory"
[ ! -e "$T/var/system-replace/linkdir" ] || fail "a refused link to a directory must change nothing"
rm -f "$V/usr/bin/ld"; rm -rf "$V/opt"

mkproduct manswap manswap "" share/man/man1/ms.1
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/share/man/man1/ms.1 string share/man/man1/ms.1" "$T/manswap/mavergreen.plist"
echo apple-ms > "$V/usr/share/man/man1/ms.1"; ino="$(stat -f %i "$V/usr/share/man/man1/ms.1")"
(PATH="$mvstub:$PATH" MV_FAIL=usr/share/man/man1/ms.1 mg system-replace manswap 2>"$w/err") \
  && fail "setup: a man-page swap whose final move fails must fail system-replace"
[ "$(cat "$V/usr/share/man/man1/ms.1")" = apple-ms ] && [ ! -L "$V/usr/share/man/man1/ms.1" ] \
  && [ "$(stat -f %i "$V/usr/share/man/man1/ms.1")" = "$ino" ] \
  || fail "a man page's system path must hold its original until the staged link is moved over it, never absent"
[ ! -e "$T/var/system-replace/manswap/.replaced" ] || fail "a failed man-page swap must not mark .replaced"
mg system-replace manswap 2>"$w/err" || fail "a rerun must complete an interrupted man-page swap: $(cat "$w/err")"
[ "$(readlink "$V/usr/share/man/man1/ms.1")" = /usr/local/mavergreen/manswap/share/man/man1/ms.1 ] \
  || fail "the rerun links the man page into the tree"
[ "$(stat -f %i "$T/var/system-replace/manswap/usr/share/man/man1/ms.1")" = "$ino" ] \
  || fail "a man page's original is saved by hard link, the same inode"
(PATH="$mvstub:$PATH" RM_FAIL=usr/share/man/man1/ms.1 mg system-restore manswap 2>"$w/err") \
  || fail "restoring a man page renames the saved original over our link in one mv, with no rm first: $(cat "$w/err")"
[ "$(cat "$V/usr/share/man/man1/ms.1")" = apple-ms ] && [ "$(stat -f %i "$V/usr/share/man/man1/ms.1")" = "$ino" ] \
  || fail "restore puts the man page's original inode back"
(PATH="$mvstub:$PATH" MV_FAIL=usr/share/man/man1/ms.1 mg system-replace manswap 2>"$w/err") \
  && fail "setup: a second man-page swap whose final move fails must fail"
mg system-restore manswap 2>"$w/err" || fail "restore must finish a man-page swap interrupted between saving and swapping: $(cat "$w/err")"
[ "$(cat "$V/usr/share/man/man1/ms.1")" = apple-ms ] && [ "$(stat -f %i "$V/usr/share/man/man1/ms.1")" = "$ino" ] \
  && [ ! -e "$T/var/system-replace/manswap" ] \
  || fail "restoring a man page whose save is its own inode removes the save and leaves the original"

mkproduct lnfail lnfail "" share/man/man1/lf.1
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/share/man/man1/lf.1 string share/man/man1/lf.1" "$T/lnfail/mavergreen.plist"
echo apple-lf > "$V/usr/share/man/man1/lf.1"
rc=0; (PATH="$mvstub:$PATH" LN_FAIL=usr/share/man/man1/.lf.1.mavergreen-tmp mg system-replace lnfail 2>"$w/err") || rc=$?
[ "$rc" -ne 0 ] || fail "a failing ln -s must fail system-replace, never be swallowed"
[ ! -e "$T/var/system-replace/lnfail/.replaced" ] || fail "a failing ln -s must not let system-replace mark .replaced"
[ "$(cat "$V/usr/share/man/man1/lf.1")" = apple-lf ] && [ ! -L "$V/usr/share/man/man1/lf.1" ] \
  || fail "a failing ln -s must leave the man page's original in place"
mg system-restore lnfail || fail "setup: system-restore lnfail must succeed"

mkproduct otherdev otherdev "" bin/od
"$PB" -c "Add :replaces dict" -c "Add :replaces:/opt/odev/od string bin/od" "$T/otherdev/mavergreen.plist"
mkdir -p "$V/opt/odev"; echo apple-od > "$V/opt/odev/od"
(PATH="$mvstub:$PATH" STAT_OTHER=opt/odev mg system-replace otherdev 2>"$w/err") \
  && fail "system-replace must refuse a system path on another volume than its save area, before any change"
grep -q '/opt/odev/od' "$w/err" && grep -q 'volume' "$w/err" \
  || fail "the refusal must name the path and say it is on another volume: $(cat "$w/err")"
[ "$(cat "$V/opt/odev/od")" = apple-od ] || fail "a refused other-volume path must keep its original"
[ ! -e "$T/var/system-replace/otherdev" ] || fail "a refused other-volume path must change nothing"
rm -rf "$T/otherdev" "$V/opt"

mkproduct ownapplied ownapplied "" bin/oa
"$PB" -c "Add :replaces dict" -c "Add :replaces:/opt/oa/oa string bin/oa" "$T/ownapplied/mavergreen.plist"
mkdir -p "$V/opt/oa"
mg system-replace ownapplied || fail "setup: system-replace ownapplied must succeed"
"$PB" -c "Delete :replaces:/opt/oa/oa" "$T/ownapplied/mavergreen.plist"
chmod 777 "$V/opt/oa"
mg check 2>"$w/err" && fail "check must fail when a directory on an applied path becomes world-writable"
grep -q "opt/oa is not root-only" "$w/err" \
  || fail "check must judge ownership over what applied.plist records, not the current manifest: $(cat "$w/err")"
chmod 755 "$V/opt/oa"
mg system-restore ownapplied || fail "setup: system-restore ownapplied must succeed"
rm -rf "$V/opt"

mkproduct wedge wedge "" bin/w1
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/w1 string bin/w1" "$T/wedge/mavergreen.plist"
echo apple-w1 > "$V/usr/bin/w1"; ino="$(stat -f %i "$V/usr/bin/w1")"
mg system-replace wedge || fail "setup: system-replace wedge must succeed"
mv -f "$T/var/system-replace/wedge/usr/bin/w1" "$V/usr/bin/w1"
mg system-restore wedge 2>"$w/err" \
  || fail "a restore killed after putting an original back, before dropping its entry, must finish on rerun: $(cat "$w/err")"
[ "$(cat "$V/usr/bin/w1")" = apple-w1 ] && [ "$(stat -f %i "$V/usr/bin/w1")" = "$ino" ] \
  || fail "finishing an interrupted restore leaves the original it already put back"
[ ! -s "$w/err" ] || fail "an entry already restored is finished silently: $(cat "$w/err")"
[ ! -e "$T/var/system-replace/wedge" ] || fail "finishing an interrupted restore clears its state"

mkproduct killrep killrep "" bin/k1
chmod 4755 "$T/killrep/bin/k1"
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/sbin/k1 string bin/k1" "$T/killrep/mavergreen.plist"
rm -f "$V/usr/sbin/k1"
mg system-replace killrep || fail "setup: system-replace killrep must succeed"
"$PB" -c "Delete :copies:/usr/sbin/k1" "$T/var/system-replace/killrep/applied.plist"; rm -f "$T/var/system-replace/killrep/.replaced"
mg system-replace killrep 2>"$w/err" || fail "a rerun after a replace killed once its copy was in place must succeed: $(cat "$w/err")"
[ ! -e "$T/var/system-replace/killrep/usr/sbin/k1" ] \
  || fail "a rerun must never save mavergreen's own (setuid) copy as the original"
mg system-restore killrep 2>"$w/err" || fail "system-restore killrep must succeed: $(cat "$w/err")"
[ ! -e "$V/usr/sbin/k1" ] || fail "restore removes a copy that had no original, even after an interrupted replace"
[ ! -e "$T/var/system-replace/killrep" ] || fail "restore after an interrupted replace clears its state"

mkproduct beforeln beforeln "" bin/bl
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/bl string bin/bl" "$T/beforeln/mavergreen.plist"
echo apple-bl > "$V/usr/bin/bl"
(PATH="$mvstub:$PATH" LN_FAIL=usr/local/mavergreen/var/system-replace/beforeln/usr/bin/bl mg system-replace beforeln 2>"$w/err") \
  && fail "setup: a replace whose save of the original fails must fail"
[ "$(cat "$V/usr/bin/bl")" = apple-bl ] && [ ! -e "$T/var/system-replace/beforeln/usr/bin/bl" ] \
  || fail "setup: a replace stopped before saving leaves the original and saves nothing"
cp "$T/beforeln/bin/bl" "$V/usr/bin/.bl.mavergreen-tmp"
mg system-replace beforeln 2>"$w/err" || fail "a replace killed before saving the original must finish on rerun: $(cat "$w/err")"
is_copy "$V/usr/bin/bl" "$T/beforeln/bin/bl" && [ "$(cat "$T/var/system-replace/beforeln/usr/bin/bl")" = apple-bl ] \
  && [ ! -e "$V/usr/bin/.bl.mavergreen-tmp" ] || fail "the rerun swaps the copy in and saves the original"
mg system-restore beforeln || fail "setup: system-restore beforeln must succeed"
[ "$(cat "$V/usr/bin/bl")" = apple-bl ] || fail "restore after a rerun puts the original back"

mkproduct stagefail stagefail "" bin/sf
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/sf string bin/sf" "$T/stagefail/mavergreen.plist"
echo apple-sf > "$V/usr/bin/sf"; ino="$(stat -f %i "$V/usr/bin/sf")"
(PATH="$mvstub:$PATH" CP_FAIL=usr/bin/.sf.mavergreen-tmp mg system-replace stagefail 2>"$w/err") \
  && fail "system-replace must fail when it cannot stage the copy"
[ "$(cat "$V/usr/bin/sf")" = apple-sf ] && [ "$(stat -f %i "$V/usr/bin/sf")" = "$ino" ] \
  || fail "a copy that could not be staged must leave the system path holding its original, never absent"
[ ! -e "$T/var/system-replace/stagefail/usr" ] || fail "a copy that could not be staged must save nothing"
[ ! -e "$T/var/system-replace/stagefail/.replaced" ] || fail "a replace that could not stage must not mark .replaced"
mg system-restore stagefail 2>"$w/err" || fail "system-restore after a replace that changed nothing must succeed: $(cat "$w/err")"
[ "$(cat "$V/usr/bin/sf")" = apple-sf ] && [ "$(stat -f %i "$V/usr/bin/sf")" = "$ino" ] \
  || fail "system-restore after a replace that changed nothing must leave the original"
[ ! -e "$T/var/system-replace/stagefail" ] || fail "system-restore after a replace that changed nothing clears its state"

mkproduct recchg recchg "" bin/rc
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/rc string bin/rc" "$T/recchg/mavergreen.plist"
echo apple-rc > "$V/usr/bin/rc"
(PATH="$mvstub:$PATH" CP_FAIL=usr/bin/.rc.mavergreen-tmp mg system-replace recchg 2>"$w/err") && fail "setup: a replace that cannot stage must fail"
echo admin-rc > "$V/usr/bin/rc"
mg system-replace recchg 2>"$w/err" && fail "a rerun must refuse a system path that changed since mavergreen recorded its original"
grep -qF "/usr/bin/rc has changed since mavergreen recorded it" "$w/err" || fail "the refusal must name the changed path: $(cat "$w/err")"
[ "$(cat "$V/usr/bin/rc")" = admin-rc ] && [ ! -e "$T/var/system-replace/recchg/usr/bin/rc" ] \
  || fail "a refused rerun must leave the changed file alone and save nothing"
echo apple-rc > "$V/usr/bin/rc"
mg system-restore recchg || fail "setup: system-restore recchg must succeed once the original is back"

mkproduct lostsave lostsave "" bin/ls1
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/ls1 string bin/ls1" "$T/lostsave/mavergreen.plist"
echo apple-ls1 > "$V/usr/bin/ls1"
mg system-replace lostsave || fail "setup: system-replace lostsave must succeed"
mv "$T/var/system-replace/lostsave/usr/bin/ls1" "$w/ls1-aside"
mg system-replace lostsave 2>"$w/err" && fail "a rerun must refuse when the original saved for a replaced path is missing"
grep -qF "/usr/bin/ls1 is lostsave's, but the original saved for it is missing" "$w/err" \
  || fail "the refusal must name the path whose saved original is missing: $(cat "$w/err")"
is_copy "$V/usr/bin/ls1" "$T/lostsave/bin/ls1" || fail "a refused rerun must leave the copy in place"
mv "$w/ls1-aside" "$T/var/system-replace/lostsave/usr/bin/ls1"
mg system-restore lostsave || fail "setup: system-restore lostsave must succeed once the save is back"
[ "$(cat "$V/usr/bin/ls1")" = apple-ls1 ] || fail "setup: lostsave restored"

mkproduct upg upg "" bin/up
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/up string bin/up" "$T/upg/mavergreen.plist"
echo apple-up > "$V/usr/bin/up"
(PATH="$mvstub:$PATH" CP_FAIL=usr/bin/.up.mavergreen-tmp mg system-replace upg 2>"$w/err") && fail "setup: a replace that cannot stage must fail"
echo upg-v2 > "$T/upg/bin/up"
mg system-replace upg 2>"$w/err" || fail "a rerun after the tree changed must succeed: $(cat "$w/err")"
is_copy "$V/usr/bin/up" "$T/upg/bin/up" || fail "the rerun installs the current tree file"
[ "$("$PB" -c 'Print :copies:/usr/bin/up' "$T/var/system-replace/upg/applied.plist" 2>/dev/null)" = "$(sha "$T/upg/bin/up")" ] \
  || fail "a rerun that swaps must record the copy it installs now, not the one an interrupted run meant to"
mg check 2>"$w/err" || true
if grep -q 'usr/bin/up ' "$w/err"; then fail "check must not report a copy installed by a rerun after the tree changed: $(cat "$w/err")"; fi
mg system-restore upg 2>"$w/err" || fail "restore after an interrupted replace and a changed tree must succeed: $(cat "$w/err")"
[ "$(cat "$V/usr/bin/up")" = apple-up ] || fail "that restore puts the original back"

stagedlink() {  # $1 product  $2 man page base name; leaves our staged symlink behind the way a kill would
  ln -s "/usr/local/mavergreen/$1/share/man/man1/$2" "$V/usr/share/man/man1/.$2.mavergreen-tmp"
}
mkproduct mbefore mbefore "" share/man/man1/mb.1
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/share/man/man1/mb.1 string share/man/man1/mb.1" "$T/mbefore/mavergreen.plist"
echo apple-mb > "$V/usr/share/man/man1/mb.1"
(PATH="$mvstub:$PATH" MV_FAIL=usr/share/man/man1/mb.1 mg system-replace mbefore 2>"$w/err") && fail "setup: an interrupted man-page swap must fail"
rm -f "$T/var/system-replace/mbefore/usr/share/man/man1/mb.1"; stagedlink mbefore mb.1
mg system-replace mbefore 2>"$w/err" \
  || fail "a man-page swap killed after staging its link, before saving, must finish on rerun: $(cat "$w/err")"
[ "$(readlink "$V/usr/share/man/man1/mb.1")" = /usr/local/mavergreen/mbefore/share/man/man1/mb.1 ] \
  && [ "$(cat "$T/var/system-replace/mbefore/usr/share/man/man1/mb.1")" = apple-mb ] \
  && [ ! -L "$V/usr/share/man/man1/.mb.1.mavergreen-tmp" ] || fail "that rerun links the man page, saves the original, and leaves no staged link"
mg system-restore mbefore || fail "setup: system-restore mbefore must succeed"

mkproduct mafter mafter "" share/man/man1/ma.1
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/share/man/man1/ma.1 string share/man/man1/ma.1" "$T/mafter/mavergreen.plist"
echo apple-ma > "$V/usr/share/man/man1/ma.1"
(PATH="$mvstub:$PATH" MV_FAIL=usr/share/man/man1/ma.1 mg system-replace mafter 2>"$w/err") && fail "setup: an interrupted man-page swap must fail"
stagedlink mafter ma.1
mg system-replace mafter 2>"$w/err" \
  || fail "a man-page swap killed after saving, before the rename, must finish on rerun: $(cat "$w/err")"
[ "$(readlink "$V/usr/share/man/man1/ma.1")" = /usr/local/mavergreen/mafter/share/man/man1/ma.1 ] \
  && [ "$(cat "$T/var/system-replace/mafter/usr/share/man/man1/ma.1")" = apple-ma ] || fail "that rerun links the man page and keeps the save"
mg system-restore mafter || fail "setup: system-restore mafter must succeed"

mkproduct mnone mnone "" share/man/man1/mn.1
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/share/man/man1/mn.1 string share/man/man1/mn.1" "$T/mnone/mavergreen.plist"
rm -f "$V/usr/share/man/man1/mn.1"
(PATH="$mvstub:$PATH" MV_FAIL=usr/share/man/man1/mn.1 mg system-replace mnone 2>"$w/err") && fail "setup: an interrupted man-page swap must fail"
stagedlink mnone mn.1
mg system-replace mnone 2>"$w/err" \
  || fail "a man-page swap with no original, killed after staging, must finish on rerun: $(cat "$w/err")"
[ "$(readlink "$V/usr/share/man/man1/mn.1")" = /usr/local/mavergreen/mnone/share/man/man1/mn.1 ] || fail "that rerun links the man page"
mg system-restore mnone || fail "setup: system-restore mnone must succeed"
[ ! -L "$V/usr/share/man/man1/mn.1" ] && [ ! -L "$V/usr/share/man/man1/.mn.1.mavergreen-tmp" ] || fail "restore leaves no link behind"

mkproduct mforeign mforeign "" share/man/man1/mf.1
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/share/man/man1/mf.1 string share/man/man1/mf.1" "$T/mforeign/mavergreen.plist"
echo apple-mf > "$V/usr/share/man/man1/mf.1"; ln -s /elsewhere "$V/usr/share/man/man1/.mf.1.mavergreen-tmp"
mg system-replace mforeign 2>"$w/err" && fail "system-replace must still refuse a staging link that is not the one it would stage"
grep -qF ".mf.1.mavergreen-tmp exists and is not a regular file" "$w/err" || fail "the refusal must name the staging path: $(cat "$w/err")"
[ "$(readlink "$V/usr/share/man/man1/.mf.1.mavergreen-tmp")" = /elsewhere ] || fail "a foreign staging link must be left alone"
rm -f "$V/usr/share/man/man1/.mf.1.mavergreen-tmp"; rm -rf "$T/mforeign" "$T/var/system-replace/mforeign"

mkproduct ident ident "" bin/id1
chmod 4755 "$T/ident/bin/id1"
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/id1 string bin/id1" "$T/ident/mavergreen.plist"
cp "$T/ident/bin/id1" "$V/usr/bin/id1"; chmod 755 "$V/usr/bin/id1"; ino="$(stat -f %i "$V/usr/bin/id1")"
(PATH="$mvstub:$PATH" MV_FAIL=usr/bin/id1 mg system-replace ident 2>"$w/err") && fail "setup: an interrupted swap must fail"
mg system-replace ident 2>"$w/err" || fail "setup: the rerun must succeed: $(cat "$w/err")"
[ "$(stat -f %Mp%Lp "$V/usr/bin/id1")" = 4755 ] \
  || fail "a rerun must finish swapping in the (setuid) copy over a byte-identical original it had already saved"
[ "$(stat -f %i "$T/var/system-replace/ident/usr/bin/id1")" = "$ino" ] || fail "the saved original is still the original's inode"
mg system-restore ident || fail "setup: system-restore ident must succeed"
[ "$(stat -f %i "$V/usr/bin/id1")" = "$ino" ] && [ "$(stat -f %Mp%Lp "$V/usr/bin/id1")" = 0755 ] \
  || fail "restore puts the byte-identical original back with its own mode"

mkproduct mandir mandir "" share/man/man1/md.1
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/share/man/man1/md.1 string share/man/man1/md.1" "$T/mandir/mavergreen.plist"
echo apple-md > "$V/usr/share/man/man1/md.1"
mg system-replace mandir || fail "setup: system-replace mandir must succeed"
rm "$T/mandir/share/man/man1/md.1"; mkdir "$T/mandir/share/man/man1/md.1"
rc=0; mg system-restore mandir 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "restore must refuse when our link's target has become a directory"
[ -z "$(ls -A "$T/mandir/share/man/man1/md.1")" ] || fail "restore must not move the original into a directory"
[ "$(cat "$T/var/system-replace/mandir/usr/share/man/man1/md.1")" = apple-md ] \
  || fail "restore must keep the saved original when our link's target is a directory"
rmdir "$T/mandir/share/man/man1/md.1"; echo mandir > "$T/mandir/share/man/man1/md.1"
mg system-restore mandir || fail "setup: system-restore mandir must succeed once the target is a file again"

mkproduct rmstage rmstage "" bin/dx
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/dx string bin/dx" "$T/rmstage/mavergreen.plist"
echo apple-dx > "$V/usr/bin/dx"
mg system-replace rmstage || fail "setup: system-replace rmstage must succeed"
echo leftover > "$V/usr/bin/.dx.mavergreen-tmp"
rc=0; (PATH="$mvstub:$PATH" RM_FAIL=usr/bin/.dx.mavergreen-tmp mg system-restore rmstage 2>"$w/err") || rc=$?
[ "$rc" -ne 0 ] || fail "restore must fail when it cannot remove a leftover staging file"
"$PB" -c 'Print :replaces:/usr/bin/dx' "$T/var/system-replace/rmstage/applied.plist" >/dev/null 2>&1 \
  || fail "restore must keep an entry whose leftover staging file it could not remove"
mg system-restore rmstage 2>"$w/err" || fail "a retried restore removes the staging file and finishes: $(cat "$w/err")"
[ ! -e "$V/usr/bin/.dx.mavergreen-tmp" ] && [ "$(cat "$V/usr/bin/dx")" = apple-dx ] \
  || fail "the retried restore removes the staging file and puts the original back"

mkproduct findfail findfail "" bin/ff
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/ff string bin/ff" "$T/findfail/mavergreen.plist"
echo apple-ff > "$V/usr/bin/ff"
mg system-replace findfail || fail "setup: system-replace findfail must succeed"
echo apple-other > "$T/var/system-replace/findfail/usr/bin/ffother"
rc=0; (PATH="$mvstub:$PATH" FIND_FAIL=1 mg system-restore findfail 2>"$w/err") || rc=$?
[ "$rc" -ne 0 ] || fail "restore must fail closed when it cannot list the save area"
[ "$(cat "$T/var/system-replace/findfail/usr/bin/ffother")" = apple-other ] \
  || fail "a save area restore could not list must be kept, saved originals and all"
rm "$T/var/system-replace/findfail/usr/bin/ffother"
mg system-restore findfail || fail "setup: system-restore findfail must succeed"

mkproduct tmpdir tmpdir "" bin/td
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/td string bin/td" "$T/tmpdir/mavergreen.plist"
echo apple-td > "$V/usr/bin/td"; mkdir "$V/usr/bin/.td.mavergreen-tmp"
mg system-replace tmpdir 2>"$w/err" && fail "system-replace must refuse when the staging path is a directory"
grep -qF "/usr/bin/.td.mavergreen-tmp" "$w/err" || fail "the refusal must name the staging path: $(cat "$w/err")"
[ "$(cat "$V/usr/bin/td")" = apple-td ] || fail "a refused staging path must leave the original in place"
[ ! -e "$T/var/system-replace/tmpdir" ] || fail "a refused staging path must change nothing, saving nothing"
[ -d "$V/usr/bin/.td.mavergreen-tmp" ] || fail "a refused staging path must be left alone"
rmdir "$V/usr/bin/.td.mavergreen-tmp"; echo stale > "$V/usr/bin/.td.mavergreen-tmp"
mg system-replace tmpdir || fail "system-replace must replace a stale regular file at the staging path"
is_copy "$V/usr/bin/td" "$T/tmpdir/bin/td" || fail "a stale staging file must not end up at the system path"
[ ! -e "$V/usr/bin/.td.mavergreen-tmp" ] || fail "the staging file is gone once it is swapped in"
mg system-restore tmpdir || fail "setup: system-restore tmpdir must succeed"

mkproduct stray stray "" bin/sy
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/sy string bin/sy" "$T/stray/mavergreen.plist"
mg system-replace stray || fail "setup: system-replace stray must succeed"
mkdir -p "$T/var/system-replace/stray/usr/bin"; echo apple-other > "$T/var/system-replace/stray/usr/bin/other"
rc=0; mg system-restore stray 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "system-restore must fail rather than discard a saved file applied.plist does not name"
is_copy "$V/usr/bin/sy" "$T/stray/bin/sy" && [ -f "$T/var/system-replace/stray/.replaced" ] \
  || fail "a saved file applied.plist does not name refuses the restore before any change: the copy is still in place (R72)"
mkdir -p "$T/stray/libexec/mavergreen"; printf '#!/bin/sh\ntouch "%s/stray.ran"\n' "$w" > "$T/stray/libexec/mavergreen/pre-uninstall"
chmod +x "$T/stray/libexec/mavergreen/pre-uninstall"
rc=0; PATH="$stub:$PATH" mg uninstall stray 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] && [ ! -e "$w/stray.ran" ] && [ -d "$T/stray" ] && is_copy "$V/usr/bin/sy" "$T/stray/bin/sy" && grep -q usr/bin/other "$w/err" \
  || fail "uninstall refuses over a stray saved file before its pre-uninstall hook, changing nothing (R72): $(cat "$w/err")"
rm "$T/stray/libexec/mavergreen/pre-uninstall"
[ "$(cat "$T/var/system-replace/stray/usr/bin/other")" = apple-other ] || fail "system-restore must keep a saved file it cannot place"
grep -q usr/bin/other "$w/err" || fail "system-restore must name the saved file it kept: $(cat "$w/err")"
rm "$T/var/system-replace/stray/usr/bin/other"
mg system-restore stray || fail "setup: system-restore stray must succeed once the stray save is gone"

mkproduct legacy legacy "" bin/lg bin/lg2
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/lg string bin/lg" \
      -c "Add :replaces:/usr/bin/lg2 string bin/lg2" "$T/legacy/mavergreen.plist"
legacy() {
  LB="$T/var/system-replace/legacy"; mkdir -p "$LB/usr/bin"
  echo apple-lg > "$LB/usr/bin/lg"; : > "$LB/.replaced"
  rm -f "$V/usr/bin/lg" "$V/usr/bin/lg2"
  ln -s /usr/local/mavergreen/legacy/bin/lg "$V/usr/bin/lg"; ln -s /usr/local/mavergreen/legacy/bin/lg2 "$V/usr/bin/lg2"
}
legacy
mg check 2>"$w/err" || true
if grep -q 'usr/bin/lg' "$w/err"; then fail "check must judge a product replaced before applied.plist by its links: $(cat "$w/err")"; fi
mg system-replace legacy 2>"$w/err" && fail "system-replace must refuse a product the older helper replaced, which kept no applied.plist"
grep -qF "mavergreen system-restore legacy" "$w/err" || fail "the refusal must tell the admin to run system-restore first: $(cat "$w/err")"
[ "$(readlink "$V/usr/bin/lg")" = /usr/local/mavergreen/legacy/bin/lg ] && [ "$(cat "$LB/usr/bin/lg")" = apple-lg ] \
  && [ ! -e "$LB/applied.plist" ] || fail "a refused legacy replace must change nothing"
mg system-restore legacy || fail "system-restore must restore a product replaced before applied.plist existed"
[ "$(cat "$V/usr/bin/lg")" = apple-lg ] && [ ! -L "$V/usr/bin/lg" ] || fail "a legacy restore puts the original back"
[ ! -e "$V/usr/bin/lg2" ] && [ ! -L "$V/usr/bin/lg2" ] || fail "a legacy restore removes a link that had no original"

mkdir -p "$V/etc" "$V/var/db/receipts"
SR="$T/var/system-replace"
gone() { [ ! -e "$1" ] && [ ! -L "$1" ]; }
holds() { [ -f "$1" ] && [ ! -L "$1" ] && [ "$(cat "$1")" = "$2" ]; }
links() { [ "$(readlink "$T/var/$1/$2")" = "$3" ]; }
mkadopt() {  # $1 product  $2.. abs=var-rel:kind entries for its manifest's adopts
  _ap="$1"; shift
  mkproduct "$_ap" "$_ap" "" bin/stub
  rm -rf "$T/var/$_ap" "$SR/$_ap"
  "$PB" -c "Add :adopts dict" "$T/$_ap/mavergreen.plist"
  for _ae in "$@"; do
    _aa="${_ae%%=*}"; _av="${_ae#*=}"
    "$PB" -c "Add ':adopts:$_aa' dict" -c "Add ':adopts:$_aa:path' string '${_av%:*}'" \
          -c "Add ':adopts:$_aa:kind' string '${_av##*:}'" "$T/$_ap/mavergreen.plist"
  done
}
seeded() {  # $1 product  $2 var-rel  $3 content; the var file and its seed record, as the generated postinstall writes them
  mkdir -p "$(dirname "$T/var/$1/$2")"; printf '%s\n' "$3" > "$T/var/$1/$2"
  printf '%s  %s\n' "$(sha "$T/var/$1/$2")" "$2" >> "$T/var/$1/.mavergreen-seeded"
}
receipt() {  # $1 volume  $2 package  $3 path as the BOM spells it  $4 file whose cksum is Apple's stock content  $5 optional size to record instead
  _ck="$(cksum < "$4")"; _rl="$w/bomlist"
  { printf '.\t40755\t0/0\n'; _rd=.; _rr="${3#./}"
    while case "$_rr" in */*) true ;; *) false ;; esac; do
      _rd="$_rd/${_rr%%/*}"; _rr="${_rr#*/}"; printf '%s\t40755\t0/0\n' "$_rd"
    done
    printf '%s\t100644\t0/0\t%s\t%s\n' "$3" "${5:-${_ck#* }}" "${_ck%% *}"
  } > "$_rl"
  mkdir -p "$1/var/db/receipts"; mkbom -i "$_rl" "$1/var/db/receipts/com.apple.pkg.$2.bom" 2>/dev/null || true
  lsbom -p f "$1/var/db/receipts/com.apple.pkg.$2.bom" | grep -qxF "$3" || fail "setup: mkbom must record $3 in the $2 receipt"
}

mkadopt ab /etc/ab_config=ab_config:config
mg system-replace ab 2>"$w/err" || fail "system-replace must succeed when an adopted entry is absent on both sides: $(cat "$w/err")"
gone "$V/etc/ab_config" && gone "$T/var/ab/ab_config" || fail "an entry absent on both sides is skipped: no file at the system path, no link in var"
[ "$("$PB" -c 'Print :adopts:/etc/ab_config:kind' "$SR/ab/applied.plist" 2>/dev/null)" = config ] \
  && [ "$("$PB" -c 'Print :adopts:/etc/ab_config:path' "$SR/ab/applied.plist" 2>/dev/null)" = ab_config ] \
  || fail "applied.plist records each adopts entry as {path, kind}"
mkdir -p "$T/var/ab"; echo later-ab > "$T/var/ab/ab_config"
mg system-replace ab 2>"$w/err" || fail "a rerun with a skipped entry must succeed: $(cat "$w/err")"
gone "$V/etc/ab_config" && holds "$T/var/ab/ab_config" later-ab \
  || fail "a file the product creates after replace, at a skipped entry's var path, stays an ordinary var file"
mg system-restore ab || fail "system-restore of a skipped entry must succeed"
gone "$V/etc/ab_config" && holds "$T/var/ab/ab_config" later-ab && gone "$SR/ab" \
  || fail "restoring a skipped entry changes nothing and leaves no save area"

mkadopt ap /etc/ap_config=ap_config:config
seeded ap ap_config product-ap
mg system-replace ap 2>"$w/err" || fail "system-replace must succeed for an absent system file: $(cat "$w/err")"
holds "$V/etc/ap_config" product-ap || fail "with no system file, the product's file moves in as a real file at the system path"
links ap ap_config /etc/ap_config || fail "the product's var path becomes a link to the system path"
mg check 2>"$w/err" || true
if grep -q ap_config "$w/err"; then fail "check must not report a fresh adoption: $(cat "$w/err")"; fi
mg system-restore ap || fail "system-restore of an adoption with no original must succeed"
gone "$V/etc/ap_config" || fail "restore leaves the system path absent when there was no original"
holds "$T/var/ap/ap_config" product-ap || fail "restore moves the live file back to var as a real file"

mkadopt sd /etc/sd_config=sd_config:config
echo apple-sd > "$V/etc/sd_config"; chmod 640 "$V/etc/sd_config"; ino="$(stat -f %i "$V/etc/sd_config")"
receipt "$V" sd ./private/etc/sd_config "$V/etc/sd_config"
seeded sd sd_config default-sd
mg system-replace sd 2>"$w/err" || fail "system-replace stock/default must succeed: $(cat "$w/err")"
holds "$V/etc/sd_config" default-sd \
  || fail "a system file listed in an Apple receipt as ./private/etc/... is stock, so the product's default moves in"
[ "$(stat -f %Lp "$V/etc/sd_config")" = 640 ] || fail "the adopted file takes the original's mode"
links sd sd_config /etc/sd_config || fail "stock/default: var becomes a link to the system path"
[ "$(stat -f %i "$SR/sd/etc/sd_config")" = "$ino" ] || fail "the system file's original is saved by inode"
[ "$(awk '{ print $2 }' "$SR/sd/adopted.sha256")" = /etc/sd_config ] \
  && [ "$(awk '{ print $1 }' "$SR/sd/adopted.sha256")" = "$(sha "$V/etc/sd_config")" ] \
  || fail "adopted.sha256 records the sha256 of the content that became live: $(cat "$SR/sd/adopted.sha256")"
mg system-restore sd || fail "system-restore sd must succeed"
holds "$V/etc/sd_config" apple-sd && [ "$(stat -f %i "$V/etc/sd_config")" = "$ino" ] \
  || fail "restore puts the original back, by inode"
holds "$T/var/sd/sd_config" default-sd || fail "restore puts the live file back in var"
gone "$SR/sd/applied.plist" && gone "$SR/sd/adopted.sha256" && gone "$SR/sd/staging" && gone "$SR/sd/etc" \
  || fail "restore clears the save area: $(ls -R "$SR/sd")"
grep -qxF "$(sha "$V/etc/sd_config") system /etc/sd_config" "$SR/sd/restored.sha256" \
  && grep -qxF "$(sha "$T/var/sd/sd_config") var /etc/sd_config" "$SR/sd/restored.sha256" \
  || fail "restore keeps restored.sha256, recording what went back to each side: $(cat "$SR/sd/restored.sha256" 2>&1)"
mg system-restore sd || fail "a second system-restore must succeed"
[ -f "$SR/sd/restored.sha256" ] && holds "$V/etc/sd_config" apple-sd && gone "$V/restored.sha256" \
  || fail "a second system-restore must keep restored.sha256 and never treat it as a saved original"

mkadopt se /etc/se_config=se_config:config
echo apple-se > "$V/etc/se_config"; receipt "$V" se ./etc/se_config "$V/etc/se_config"
seeded se se_config default-se
mg system-replace se 2>"$w/err" || fail "system-replace stock/default (./etc spelling) must succeed: $(cat "$w/err")"
holds "$V/etc/se_config" default-se || fail "a system file listed in an Apple receipt as ./etc/... is stock too"
mg system-restore se || fail "setup: system-restore se must succeed"

mkadopt sz /etc/sz_config=sz_config:config
echo apple-sz > "$V/etc/sz_config"; receipt "$V" sz ./etc/sz_config "$V/etc/sz_config" 99
seeded sz sz_config default-sz
mg system-replace sz 2>"$w/err" || fail "setup: system-replace sz must succeed: $(cat "$w/err")"
holds "$V/etc/sz_config" apple-sz || fail "a receipt whose crc matches but whose size does not is not stock: crc and size must both match"
mg system-restore sz || fail "setup: system-restore sz must succeed"

mkadopt sc /etc/sc_config=sc_config:config
echo apple-sc > "$V/etc/sc_config"; receipt "$V" sc ./etc/sc_config "$V/etc/sc_config"
seeded sc sc_config default-sc; echo admin-sc > "$T/var/sc/sc_config"
mg system-replace sc 2>"$w/err" || fail "system-replace stock/customized must succeed: $(cat "$w/err")"
holds "$V/etc/sc_config" admin-sc || fail "a customized product file moves in over a stock system file"
mg system-restore sc || fail "setup: system-restore sc must succeed"

mkadopt cd /etc/cd_config=cd_config:config
echo admin-cd > "$V/etc/cd_config"; ino="$(stat -f %i "$V/etc/cd_config")"; seeded cd cd_config default-cd
mg system-replace cd 2>"$w/err" || fail "system-replace customized/default must succeed: $(cat "$w/err")"
holds "$V/etc/cd_config" admin-cd || fail "a customized system file stays and becomes live over the product's default"
links cd cd_config /etc/cd_config || fail "customized/default: var becomes a link to the system path"
[ "$(stat -f %i "$SR/cd/etc/cd_config")" = "$ino" ] && [ "$(stat -f %i "$V/etc/cd_config")" != "$ino" ] \
  || fail "the original is saved by inode and a copy becomes live, so editing the live file never touches the original"
holds "$SR/cd/staging/cd_config" default-cd || fail "the product's default is set aside in the save area"
mg system-restore cd || fail "system-restore cd must succeed"
holds "$V/etc/cd_config" admin-cd && [ "$(stat -f %i "$V/etc/cd_config")" = "$ino" ] || fail "customized/default: restore puts the original back"
holds "$T/var/cd/cd_config" admin-cd || fail "customized/default: restore puts the live file in var"

mkadopt ci /etc/ci_config=ci_config:config
echo admin-ci > "$V/etc/ci_config"; seeded ci ci_config default-ci; echo admin-ci > "$T/var/ci/ci_config"
mg system-replace ci 2>"$w/err" || fail "system-replace customized/customized identical must succeed: $(cat "$w/err")"
holds "$V/etc/ci_config" admin-ci && links ci ci_config /etc/ci_config || fail "customized and identical: the system file stays"
mg system-restore ci || fail "setup: system-restore ci must succeed"

mkadopt cc /etc/cc_config=cc_config:config
echo admin-cc > "$V/etc/cc_config"; ino="$(stat -f %i "$V/etc/cc_config")"
seeded cc cc_config default-cc; echo product-cc > "$T/var/cc/cc_config"
mg system-replace cc 2>"$w/err" && fail "system-replace must refuse when both sides are customized and differ"
grep -qF /etc/cc_config "$w/err" && grep -qF /usr/local/mavergreen/var/cc/cc_config "$w/err" && grep -q 'match' "$w/err" \
  || fail "the refusal must name both paths and the way out: $(cat "$w/err")"
holds "$V/etc/cc_config" admin-cc && [ "$(stat -f %i "$V/etc/cc_config")" = "$ino" ] && holds "$T/var/cc/cc_config" product-cc \
  && gone "$SR/cc" || fail "a refused adoption changes nothing"

mkadopt idsys /etc/idsys_key=idsys_key:identity
echo apple-key > "$V/etc/idsys_key"; mkdir -p "$T/var/idsys"; echo product-key > "$T/var/idsys/idsys_key"
mg system-replace idsys 2>"$w/err" || fail "system-replace of an identity with a system file must succeed: $(cat "$w/err")"
holds "$V/etc/idsys_key" apple-key && links idsys idsys_key /etc/idsys_key || fail "an identity's system file wins whenever it exists"
mg system-restore idsys || fail "setup: system-restore idsys must succeed"
holds "$V/etc/idsys_key" apple-key || fail "restore puts the identity's original back"
mkadopt idvar /etc/idvar_key=idvar_key:identity
mkdir -p "$T/var/idvar"; echo product-key > "$T/var/idvar/idvar_key"
mg system-replace idvar 2>"$w/err" || fail "system-replace of an identity with no system file must succeed: $(cat "$w/err")"
holds "$V/etc/idvar_key" product-key && links idvar idvar_key /etc/idvar_key || fail "with no system file, the product's identity moves in"
mg system-restore idvar || fail "setup: system-restore idvar must succeed"
gone "$V/etc/idvar_key" && holds "$T/var/idvar/idvar_key" product-key || fail "restore removes an identity file that had no original"

mkadopt fsym /etc/fsym_config=fsym_config:config
mkdir -p "$V/usr/local/etc"; echo admin-fsym > "$V/usr/local/etc/fsym_config"; ln -s /usr/local/etc/fsym_config "$V/etc/fsym_config"
seeded fsym fsym_config default-fsym
mg system-replace fsym 2>"$w/err" && fail "system-replace must refuse an adopted system path that is a symlink it did not make"
grep -qF /etc/fsym_config "$w/err" && grep -q symlink "$w/err" || fail "the refusal must name the symlink: $(cat "$w/err")"
[ "$(readlink "$V/etc/fsym_config")" = /usr/local/etc/fsym_config ] && holds "$T/var/fsym/fsym_config" default-fsym \
  && gone "$SR/fsym" || fail "a refused foreign symlink changes nothing"
rm -f "$V/etc/fsym_config"; rm -rf "$V/usr/local/etc"

mkadopt norc /etc/norc_config=norc_config:config
echo apple-norc > "$V/etc/norc_config"; receipt "$V" norc ./etc/norc_config "$V/etc/norc_config"
seeded norc norc_config default-norc
mv "$V/var/db/receipts" "$w/receipts-aside"
mg system-replace norc 2>"$w/err" || fail "system-replace must not fail when the receipts directory is missing: $(cat "$w/err")"
mv "$w/receipts-aside" "$V/var/db/receipts"
holds "$V/etc/norc_config" apple-norc || fail "with no receipts, a system file is customized, never stock, so it stays"
mg system-restore norc || fail "setup: system-restore norc must succeed"

mkadopt rt /etc/rt_config=rt_config:config
echo admin-rt > "$V/etc/rt_config"; seeded rt rt_config default-rt
mg system-replace rt 2>"$w/err" || fail "setup: system-replace rt must succeed: $(cat "$w/err")"
echo admin-rt-2 > "$V/etc/rt_config"
mg system-restore rt || fail "setup: system-restore rt must succeed"
holds "$V/etc/rt_config" admin-rt && holds "$T/var/rt/rt_config" admin-rt-2 || fail "setup: restore returns the original and the edited live file"
mg system-replace rt 2>"$w/err" || fail "restore then replace with no edits must not refuse: $(cat "$w/err")"
holds "$V/etc/rt_config" admin-rt-2 || fail "after a restore, re-replace takes the var file, the most recent intent"
mg system-restore rt || fail "setup: the second system-restore rt must succeed"
echo edit-sys > "$V/etc/rt_config"
mg system-replace rt 2>"$w/err" || fail "an edit on the system side only since the restore must not refuse: $(cat "$w/err")"
holds "$V/etc/rt_config" edit-sys || fail "with var still at its restore baseline, the edited system file wins"
mg system-restore rt || fail "setup: the third system-restore rt must succeed"
echo edit-sys-2 > "$V/etc/rt_config"; echo edit-var > "$T/var/rt/rt_config"
mg system-replace rt 2>"$w/err" && fail "edits on both sides since the restore must refuse"
grep -qF /etc/rt_config "$w/err" && grep -qF /usr/local/mavergreen/var/rt/rt_config "$w/err" || fail "that refusal names both: $(cat "$w/err")"
holds "$V/etc/rt_config" edit-sys-2 && holds "$T/var/rt/rt_config" edit-var || fail "that refusal changes nothing"

mkadopt vd /etc/vd_config=vd_config:config
mkdir -p "$T/var/vd/vd_config"
mg system-replace vd 2>"$w/err" && fail "system-replace must refuse an adopted var path that is a directory"
grep -qF "/usr/local/mavergreen/var/vd/vd_config is not a regular file" "$w/err" || fail "that refusal names the var path: $(cat "$w/err")"
gone "$V/etc/vd_config" && [ -d "$T/var/vd/vd_config" ] && gone "$SR/vd" || fail "that refusal changes nothing"

mkadopt sp "/etc/sp conf=sp conf:config"
echo apple-sp > "$V/etc/sp conf"; receipt "$V" sp "./private/etc/sp conf" "$V/etc/sp conf"
seeded sp "sp conf" default-sp
mg system-replace sp 2>"$w/err" || fail "system-replace must accept an adopted path with a space: $(cat "$w/err")"
holds "$V/etc/sp conf" default-sp && links sp "sp conf" "/etc/sp conf" || fail "an adopted path with a space is adopted intact"
[ "$("$PB" -c 'Print ":adopts:/etc/sp conf:path"' "$SR/sp/applied.plist" 2>/dev/null)" = "sp conf" ] \
  || fail "applied.plist records an adopted path with a space intact"
mg check 2>"$w/err" || true
if grep -q 'sp conf' "$w/err"; then fail "check must not report an adopted path with a space: $(cat "$w/err")"; fi
mg system-restore sp || fail "system-restore of an adopted path with a space must succeed"
holds "$V/etc/sp conf" apple-sp && holds "$T/var/sp/sp conf" default-sp || fail "restore of a spaced adopted path puts both back"
grep -qF " system /etc/sp conf" "$SR/sp/restored.sha256" || fail "restored.sha256 keeps a path with a space intact"

V2="$w/vol2"; T2="$V2/usr/local/mavergreen"
mg2() { MAVERGREEN_TRUSTED_UID="$(id -u)" sh "$MG" --root "$V2" "$@"; }
mkadopt fv /etc/fv_config=fv_config:config
mkdir -p "$V2/System/Library/CoreServices" "$V2/etc" "$T2/var/fv"
cp "$V/System/Library/CoreServices/SystemVersion.plist" "$V2/System/Library/CoreServices/"
cp -Rp "$T/fv" "$T2/fv"
echo apple-fv > "$V/etc/fv_config"; echo apple-fv > "$V2/etc/fv_config"
receipt "$V" fv ./etc/fv_config "$V/etc/fv_config"; receipt "$V2" other ./etc/other "$V2/etc/fv_config"
seeded fv fv_config default-fv; cp -p "$T/var/fv/fv_config" "$T/var/fv/.mavergreen-seeded" "$T2/var/fv/"
mg2 system-replace fv 2>"$w/err" || fail "system-replace on a second volume must succeed: $(cat "$w/err")"
holds "$V2/etc/fv_config" apple-fv || fail "a volume's stock check reads only that volume's receipts, not another volume's"
mg system-replace fv 2>"$w/err" || fail "setup: system-replace fv must succeed: $(cat "$w/err")"
holds "$V/etc/fv_config" default-fv || fail "the volume whose receipt lists the file judges it stock"
mg system-restore fv || fail "setup: system-restore fv must succeed"
rm -rf "$V2"

f3() {  # two adopted entries, stock system files and seeded defaults
  mkadopt f3 /etc/f3a=f3a:config /etc/f3b=f3b:config
  echo apple-f3a > "$V/etc/f3a"; echo apple-f3b > "$V/etc/f3b"
  receipt "$V" f3a ./etc/f3a "$V/etc/f3a"; receipt "$V" f3b ./etc/f3b "$V/etc/f3b"
  seeded f3 f3a default-f3a; seeded f3 f3b default-f3b
  inoa="$(stat -f %i "$V/etc/f3a")"; inob="$(stat -f %i "$V/etc/f3b")"; inov="$(stat -f %i "$T/var/f3/f3b")"
}
f3
(PATH="$mvstub:$PATH" MV_FAIL=etc/f3b mg system-replace f3 2>"$w/err") && fail "setup: a replace whose second adopted swap fails must fail"
holds "$V/etc/f3a" default-f3a && links f3 f3a /etc/f3a || fail "setup: the first adopted entry was adopted before the second failed"
holds "$V/etc/f3b" apple-f3b && [ "$(stat -f %i "$V/etc/f3b")" = "$inob" ] && holds "$T/var/f3/f3b" default-f3b \
  || fail "a failed adopted swap leaves its system path holding the original and its var file in place"
mg system-replace f3 2>"$w/err" || fail "a rerun must complete a replace that stopped at an adopted entry: $(cat "$w/err")"
holds "$V/etc/f3a" default-f3a && holds "$V/etc/f3b" default-f3b && links f3 f3a /etc/f3a && links f3 f3b /etc/f3b \
  || fail "the rerun adopts both entries"
[ "$(stat -f %i "$SR/f3/etc/f3a")" = "$inoa" ] && [ "$(stat -f %i "$SR/f3/etc/f3b")" = "$inob" ] \
  || fail "the rerun keeps both originals saved by inode"
[ -f "$SR/f3/.replaced" ] || fail "the completed rerun marks .replaced"
mg system-restore f3 || fail "setup: system-restore f3 must succeed"
f3
(PATH="$mvstub:$PATH" MV_FAIL=etc/f3b mg system-replace f3 2>"$w/err") && fail "setup: the second adopted swap fails again"
mg system-restore f3 2>"$w/err" || fail "system-restore must undo a replace that stopped at an adopted entry: $(cat "$w/err")"
holds "$V/etc/f3a" apple-f3a && [ "$(stat -f %i "$V/etc/f3a")" = "$inoa" ] && holds "$T/var/f3/f3a" default-f3a \
  || fail "restore at the failed point puts the first entry's original back"
holds "$V/etc/f3b" apple-f3b && [ "$(stat -f %i "$V/etc/f3b")" = "$inob" ] && [ "$(stat -f %i "$T/var/f3/f3b")" = "$inov" ] \
  || fail "restore at the failed point leaves the second entry untouched"
gone "$SR/f3/applied.plist" && gone "$SR/f3/etc" || fail "that restore clears the save area"
f3
mkdir "$V/etc/.f3b.mavergreen-tmp"
mg system-replace f3 2>"$w/err" && fail "system-replace must refuse when an adopted entry's staging path is a directory"
grep -qF /etc/.f3b.mavergreen-tmp "$w/err" || fail "the refusal must name the staging path: $(cat "$w/err")"
holds "$V/etc/f3a" apple-f3a && holds "$T/var/f3/f3a" default-f3a && gone "$SR/f3" || fail "that refusal comes before any change"
rmdir "$V/etc/.f3b.mavergreen-tmp"

mkadopt lp /etc/lp_config=lp_config:config
echo apple-lp > "$V/etc/lp_config"; receipt "$V" lp ./etc/lp_config "$V/etc/lp_config"; seeded lp lp_config default-lp
(PATH="$mvstub:$PATH" MV_FAIL=var/lp/lp_config mg system-replace lp 2>"$w/err") && fail "setup: a replace whose var link fails must fail"
holds "$V/etc/lp_config" default-lp && holds "$T/var/lp/lp_config" default-lp || fail "setup: swapped in, var not yet linked"
ln -s /etc/lp_config "$T/var/lp/.lp_config.mavergreen-tmp"
mg system-replace lp 2>"$w/err" || fail "a rerun must finish linking var after the swap, past its own staged link: $(cat "$w/err")"
links lp lp_config /etc/lp_config && holds "$V/etc/lp_config" default-lp && holds "$SR/lp/etc/lp_config" apple-lp \
  && gone "$T/var/lp/.lp_config.mavergreen-tmp" || fail "that rerun links var and keeps the saved original"
mg system-restore lp || fail "setup: system-restore lp must succeed"
holds "$V/etc/lp_config" apple-lp && holds "$T/var/lp/lp_config" default-lp || fail "setup: lp restored"
rm -rf "$SR/lp"
(PATH="$mvstub:$PATH" MV_FAIL=var/lp/lp_config mg system-replace lp 2>"$w/err") && fail "setup: a second replace whose var link fails must fail"
ln -s /etc/lp_config "$T/var/lp/.lp_config.mavergreen-tmp"
mg system-restore lp 2>"$w/err" || fail "restore must undo a replace that swapped in but never linked var: $(cat "$w/err")"
holds "$V/etc/lp_config" apple-lp && holds "$T/var/lp/lp_config" default-lp && gone "$SR/lp/etc" \
  || fail "that restore puts the original back and leaves var's file"
gone "$T/var/lp/.lp_config.mavergreen-tmp" || fail "that restore removes the link replace staged beside var"
[ ! -f "$SR/lp/restored.sha256" ] \
  || fail "restoring an entry that was never linked records no restore baseline, so the admin's customization is never taken for one"

mkadopt sl /etc/sl_config=sl_config:config
echo apple-sl > "$V/etc/sl_config"; receipt "$V" sl ./etc/sl_config "$V/etc/sl_config"; seeded sl sl_config default-sl
mg system-replace sl || fail "setup: system-replace sl must succeed"
echo tool-sl > "$w/sl"; mv "$w/sl" "$T/var/sl/sl_config"
mg system-replace sl 2>"$w/err" && fail "a rerun must refuse when the var link was replaced by a different real file"
grep -qF /etc/sl_config "$w/err" && grep -qF /usr/local/mavergreen/var/sl/sl_config "$w/err" || fail "that refusal names both: $(cat "$w/err")"
holds "$T/var/sl/sl_config" tool-sl && holds "$V/etc/sl_config" default-sl || fail "that refusal changes neither file"
cp "$V/etc/sl_config" "$T/var/sl/sl_config"
mg system-replace sl 2>"$w/err" || fail "a rerun must relink a var file identical to the system file: $(cat "$w/err")"
links sl sl_config /etc/sl_config || fail "that rerun relinks var"
mg system-restore sl || fail "setup: system-restore sl must succeed"

mkadopt rb /etc/rb_config=rb_config:config
echo apple-rb > "$V/etc/rb_config"; ino="$(stat -f %i "$V/etc/rb_config")"
receipt "$V" rb ./etc/rb_config "$V/etc/rb_config"; seeded rb rb_config default-rb
mg system-replace rb || fail "setup: system-replace rb must succeed"
echo edit-rb >> "$V/etc/rb_config"
(PATH="$mvstub:$PATH" MV_FAIL=etc/rb_config mg system-restore rb 2>"$w/err") && fail "setup: a restore whose original fails to go back must fail"
[ "$(sha "$T/var/rb/rb_config")" = "$(sha "$V/etc/rb_config")" ] && [ ! -L "$T/var/rb/rb_config" ] \
  || fail "setup: restore moved the live file back to var first"
grep -qxF "$(sha "$V/etc/rb_config") var /etc/rb_config" "$SR/rb/restored.sha256" \
  || fail "restore records its baselines before its first change"
mg system-replace rb 2>"$w/err" || fail "a replace after a restore stopped midway must relink var: $(cat "$w/err")"
links rb rb_config /etc/rb_config && [ "$(sed -n 2p "$V/etc/rb_config")" = edit-rb ] || fail "that replace keeps the edited live file"
(PATH="$mvstub:$PATH" MV_FAIL=etc/rb_config mg system-restore rb 2>"$w/err") && fail "setup: the restore stops midway again"
mg system-restore rb 2>"$w/err" || fail "a rerun must finish a restore stopped after moving the live file to var: $(cat "$w/err")"
holds "$V/etc/rb_config" apple-rb && [ "$(stat -f %i "$V/etc/rb_config")" = "$ino" ] && [ "$(sed -n 2p "$T/var/rb/rb_config")" = edit-rb ] \
  || fail "that rerun puts the original back and leaves the live file in var"

mkadopt ra /etc/ra_config=ra_config:config
echo apple-ra > "$V/etc/ra_config"; receipt "$V" ra ./etc/ra_config "$V/etc/ra_config"; seeded ra ra_config default-ra
mg system-replace ra || fail "setup: system-replace ra must succeed"
(PATH="$mvstub:$PATH" MV_FAIL=var/ra/ra_config mg system-restore ra 2>"$w/err") && fail "setup: a restore whose var move fails must fail"
links ra ra_config /etc/ra_config && holds "$V/etc/ra_config" default-ra || fail "a restore that cannot move the live file to var changes nothing"
echo junk > "$T/var/ra/.ra_config.mavergreen-tmp"
mg system-restore ra 2>"$w/err" || fail "a rerun must finish that restore past its leftover temp file: $(cat "$w/err")"
holds "$V/etc/ra_config" apple-ra && holds "$T/var/ra/ra_config" default-ra && gone "$T/var/ra/.ra_config.mavergreen-tmp" \
  || fail "that rerun restores both sides and removes the leftover"

mkadopt rd /etc/rd_config=rd_config:config
echo admin-rd > "$V/etc/rd_config"; seeded rd rd_config default-rd
mg system-replace rd || fail "setup: system-replace rd must succeed"
echo admin-rd-2 > "$V/etc/rd_config"
(PATH="$mvstub:$PATH" MV_FAIL=applied.plist mg system-restore rd 2>"$w/err") && fail "setup: a restore that cannot drop its entry must fail"
holds "$V/etc/rd_config" admin-rd && holds "$T/var/rd/rd_config" admin-rd-2 || fail "setup: rd's files are already restored"
mg system-restore rd 2>"$w/err" || fail "a rerun must finish a restore stopped before dropping its entry: $(cat "$w/err")"
gone "$SR/rd/applied.plist" || fail "that rerun drops the entry"
mg system-replace rd 2>"$w/err" || fail "the baselines recorded before the interrupted restore must still let replace round-trip: $(cat "$w/err")"
holds "$V/etc/rd_config" admin-rd-2 || fail "that replace takes the var file"
mg system-restore rd || fail "setup: system-restore rd must succeed"

mkadopt ck /etc/ck_config=ck_config:config
seeded ck ck_config product-ck
mg system-replace ck || fail "setup: system-replace ck must succeed"
mv "$V/etc/ck_config" "$w/ck"
mg check 2>"$w/err" && fail "check must fail when an adopted system path is missing"
grep -qF "/etc/ck_config is adopted by ck, but it is missing" "$w/err" || fail "check names the missing adopted file: $(cat "$w/err")"
ln -s /elsewhere "$V/etc/ck_config"
mg check 2>"$w/err" && fail "check must fail when an adopted system path is no longer a real file"
grep -qF "/etc/ck_config is adopted by ck, but it is no longer a real file" "$w/err" || fail "check names the adopted path that became a link: $(cat "$w/err")"
rm "$V/etc/ck_config"; mv "$w/ck" "$V/etc/ck_config"
cp "$V/etc/ck_config" "$w/ck"; mv "$w/ck" "$T/var/ck/ck_config"
mg check 2>"$w/err" && fail "check must fail when the var path is no longer the product's link"
grep -qF "/usr/local/mavergreen/var/ck/ck_config is no longer ck's link to /etc/ck_config" "$w/err" \
  || fail "check names a var path a tool replaced by saving through it: $(cat "$w/err")"
rm "$T/var/ck/ck_config"; ln -s /etc/ck_config "$T/var/ck/ck_config"
chmod 777 "$V/etc"
mg check 2>"$w/err" && fail "check must fail when a directory on an adopted path becomes world-writable"
grep -q "etc is not root-only" "$w/err" || fail "check judges the ownership of adopted paths: $(cat "$w/err")"
chmod 755 "$V/etc"
mg system-restore ck || fail "setup: system-restore ck must succeed"

mkadopt wr /etc/wr_config=wr_config:config
seeded wr wr_config product-wr; chmod 666 "$T/var/wr/wr_config"
mg system-replace wr 2>"$w/err" && fail "system-replace must refuse an adopted var file a non-root user can write"
grep -qF "var/wr/wr_config is not root-only" "$w/err" || fail "that refusal names the var file: $(cat "$w/err")"
gone "$V/etc/wr_config" && gone "$SR/wr" || fail "that refusal changes nothing"

mkadopt sa /etc/sa_config=sa_config:config
echo apple-sa > "$V/etc/sa_config"; receipt "$V" sa ./etc/sa_config "$V/etc/sa_config"
mg system-replace sa 2>"$w/err" || fail "system-replace stock/absent must succeed: $(cat "$w/err")"
holds "$V/etc/sa_config" apple-sa && links sa sa_config /etc/sa_config || fail "a stock system file with no product file stays and becomes live"
mg system-restore sa || fail "setup: system-restore sa must succeed"
holds "$V/etc/sa_config" apple-sa && holds "$T/var/sa/sa_config" apple-sa || fail "restore of stock/absent puts the original back and the live file in var"

mkadopt lps /etc/lps_config=lps_config:config
echo admin-lps > "$V/etc/lps_config"; seeded lps lps_config default-lps
(PATH="$mvstub:$PATH" MV_FAIL=var/lps/lps_config mg system-replace lps 2>"$w/err") && fail "setup: a replace whose var link fails must fail"
mg system-replace lps 2>"$w/err" \
  || fail "a rerun must finish linking var when the system file won and var still holds the default it recorded: $(cat "$w/err")"
links lps lps_config /etc/lps_config && holds "$V/etc/lps_config" admin-lps && holds "$SR/lps/staging/lps_config" default-lps \
  || fail "that rerun links var and sets the default aside"
mg system-restore lps || fail "setup: system-restore lps must succeed"
rm -rf "$SR/lps"; rm -f "$T/var/lps/lps_config"; seeded lps lps_config default-lps
(PATH="$mvstub:$PATH" MV_FAIL=var/lps/lps_config mg system-replace lps 2>"$w/err") && fail "setup: the var link fails again"
mg system-restore lps 2>"$w/err" || fail "restore must undo a system-wins swap whose var link never happened: $(cat "$w/err")"
holds "$V/etc/lps_config" admin-lps && holds "$T/var/lps/lps_config" default-lps && gone "$SR/lps/etc" \
  || fail "that restore puts the original back and leaves var's default"

mkadopt vo /etc/vo_config=vo_config:config
echo admin-vo > "$V/etc/vo_config"
(PATH="$mvstub:$PATH" CP_FAIL=etc/.vo_config.mavergreen-tmp mg system-replace vo 2>"$w/err") && fail "setup: a replace that cannot stage beside the system file must fail"
seeded vo vo_config default-vo
(PATH="$mvstub:$PATH" MV_FAIL=var/vo/vo_config mg system-replace vo 2>"$w/err") && fail "setup: a rerun whose var link fails must fail"
mg system-replace vo 2>"$w/err" \
  || fail "a rerun must record the var file it found when it swapped, not what an earlier interrupted run saw: $(cat "$w/err")"
links vo vo_config /etc/vo_config && holds "$V/etc/vo_config" admin-vo && holds "$SR/vo/staging/vo_config" default-vo \
  || fail "that rerun links var and sets the seeded default aside"
mg system-restore vo || fail "setup: system-restore vo must succeed"

mkadopt sx /etc/sx_config=sx_config:config
echo admin-sx > "$V/etc/sx_config"; seeded sx sx_config default-sx
(PATH="$mvstub:$PATH" LN_FAIL=system-replace/sx/staging/sx_config mg system-replace sx 2>"$w/err") \
  || fail "a var file that cannot be hard-linked into the save area must be set aside by copy: $(cat "$w/err")"
links sx sx_config /etc/sx_config && holds "$SR/sx/staging/sx_config" default-sx || fail "that replace sets the default aside and links var"
mg system-restore sx || fail "setup: system-restore sx must succeed"

mkadopt cl /etc/cl_config=cl_config:config
echo admin-cl > "$V/etc/cl_config"; seeded cl cl_config default-cl
mg system-replace cl || fail "setup: system-replace cl must succeed"
(PATH="$mvstub:$PATH" RM_FAIL=system-replace/cl/staging mg system-restore cl 2>"$w/err") && fail "setup: a restore that cannot clear its staging must fail"
[ -f "$SR/cl/applied.plist" ] && gone "$SR/cl/.replaced" \
  || fail "a restore stopped while clearing its save area must remove .replaced first and applied.plist last"
mg system-restore cl 2>"$w/err" || fail "a rerun must finish clearing the save area: $(cat "$w/err")"
gone "$V/staging" && gone "$SR/cl/staging" && gone "$SR/cl/applied.plist" && [ -f "$SR/cl/restored.sha256" ] \
  && holds "$V/etc/cl_config" admin-cl || fail "that rerun clears the save area and never takes its staging for saved originals"

mkadopt rc2 /etc/rc2_config=rc2_config:config
echo apple-rc2 > "$V/etc/rc2_config"; receipt "$V" rc2 ./etc/rc2_config "$V/etc/rc2_config"; seeded rc2 rc2_config default-rc2
(PATH="$mvstub:$PATH" CP_FAIL=etc/.rc2_config.mavergreen-tmp mg system-replace rc2 2>"$w/err") && fail "setup: a replace that cannot stage beside the system file must fail"
holds "$V/etc/rc2_config" apple-rc2 && gone "$SR/rc2/etc" || fail "setup: nothing changed at the system path"
echo admin-rc2 > "$V/etc/rc2_config"
mg system-replace rc2 2>"$w/err" && fail "a rerun must refuse an adopted system file that changed since mavergreen recorded it"
grep -qF "/etc/rc2_config has changed since mavergreen recorded it" "$w/err" || fail "that refusal names the path: $(cat "$w/err")"
holds "$V/etc/rc2_config" admin-rc2 && gone "$SR/rc2/etc" || fail "that refusal changes nothing"
echo apple-rc2 > "$V/etc/rc2_config"
mg system-restore rc2 >"$w/out" || fail "setup: system-restore rc2 must succeed once the original is back"
[ ! -s "$w/out" ] || fail "restoring an adoption that never swapped reports nothing: its original is where it always was: $(cat "$w/out")"

mkadopt gs /etc/gs_config=gs_config:config
echo admin-gs > "$V/etc/gs_config"
(PATH="$mvstub:$PATH" MV_FAIL=var/gs/gs_config mg system-replace gs 2>"$w/err") && fail "setup: a replace whose var link fails must fail"
rm "$V/etc/gs_config"
mg system-replace gs 2>"$w/err" && fail "a rerun must refuse to link var to an adopted system file that has gone"
grep -qF /etc/gs_config "$w/err" || fail "that refusal names the system path: $(cat "$w/err")"
gone "$T/var/gs/gs_config" || fail "that refusal links nothing"
rm -rf "$T/gs" "$T/var/gs" "$SR/gs"

mkproduct mix mix "" bin/mx
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/mx string bin/mx" \
      -c "Add :adopts dict" -c "Add :adopts:/etc/mx_config dict" -c "Add :adopts:/etc/mx_config:path string mx_config" \
      -c "Add :adopts:/etc/mx_config:kind string config" "$T/mix/mavergreen.plist"
rm -rf "$T/var/mix" "$SR/mix"
echo apple-mx > "$V/usr/bin/mx"; echo admin-mx > "$V/etc/mx_config"; seeded mix mx_config default-mx
mg system-replace mix 2>"$w/err" || fail "setup: system-replace mix must succeed: $(cat "$w/err")"
"$PB" -c "Delete :adopts:/etc/mx_config" "$T/mix/mavergreen.plist"
mv "$SR/mix/etc/mx_config" "$w/mx-aside"
mg system-restore mix 2>"$w/err" && fail "setup: restore must fail while the adopted entry's saved original is missing"
is_copy "$V/usr/bin/mx" "$T/mix/bin/mx" || fail "that restore puts nothing back, not even the program, while one entry cannot be restored (R64)"
[ "$("$PB" -c 'Print :adopts:/etc/mx_config:path' "$SR/mix/applied.plist" 2>/dev/null)" = mx_config ] \
  || fail "restore's per-entry rewrite of applied.plist must keep an adopted entry it could not restore"
mv "$w/mx-aside" "$SR/mix/etc/mx_config"
mg system-restore mix 2>"$w/err" || fail "a retried restore finishes the adopted entry: $(cat "$w/err")"
holds "$V/etc/mx_config" admin-mx && holds "$T/var/mix/mx_config" admin-mx && holds "$V/usr/bin/mx" apple-mx || fail "that retry puts every original back"

mkadopt sg /etc/sga=sga:config /etc/sgb=sgb:config
echo admin-sga > "$V/etc/sga"; echo admin-sgb > "$V/etc/sgb"
(PATH="$mvstub:$PATH" CP_FAIL=system-replace/sg/staging/sgb mg system-replace sg 2>"$w/err") && fail "setup: a replace that cannot stage its second entry must fail"
gone "$SR/sg/staging" && gone "$SR/sg" || fail "a replace that fails before its write-ahead record removes the staging it created: $(ls -R "$SR/sg" 2>&1)"
holds "$V/etc/sga" admin-sga && holds "$V/etc/sgb" admin-sgb || fail "that failed replace changes nothing"
mg system-restore sg 2>"$w/err" || fail "system-restore after a replace that changed nothing must succeed: $(cat "$w/err")"
gone "$V/staging" || fail "a restore after a failed replace must never put staged files on the system volume"

mkadopt ps /etc/ps_key=ps_key:identity
mkdir -p "$SR/ps/staging"; echo private-key > "$SR/ps/staging/ps_key"
mg system-restore ps 2>"$w/err" && fail "system-restore must fail when staging/ is left with no applied.plist"
grep -qF "ps: $SR/ps holds an unfinished staging directory; it was left in place" "$w/err" \
  || fail "that failure names the staging directory: $(cat "$w/err")"
gone "$V/staging" && gone "$V/ps_key" && holds "$SR/ps/staging/ps_key" private-key \
  || fail "restore without applied.plist leaves staging/ where it is and never moves it onto the system volume"
rm -rf "$SR/ps/staging/ps_key"
mg system-restore ps 2>"$w/err" && fail "system-restore must fail when an empty staging/ is left with no applied.plist"
grep -qF "ps: $SR/ps holds an unfinished staging directory; it was left in place" "$w/err" \
  || fail "an empty staging/ left by a kill is called an unfinished staging directory, not files (T6c): $(cat "$w/err")"
rm -rf "$SR/ps"

mkadopt kg /etc/kg_key=kg_key:identity
mkdir -p "$T/var/kg"; echo product-key > "$T/var/kg/kg_key"
(PATH="$mvstub:$PATH" CP_FAIL=etc/.kg_key.mavergreen-tmp mg system-replace kg 2>"$w/err") && fail "setup: a replace killed before its first swap must fail"
echo generated-key > "$V/etc/kg_key"
mg system-replace kg 2>"$w/err" && fail "a rerun must refuse a system file that appeared after mavergreen recorded it as absent"
grep -qF "/etc/kg_key was absent when mavergreen recorded it" "$w/err" || fail "that refusal says the file appeared: $(cat "$w/err")"
holds "$V/etc/kg_key" generated-key && holds "$T/var/kg/kg_key" product-key || fail "that refusal changes nothing"
mg system-restore kg 2>"$w/err" && fail "system-restore must refuse to remove a file that appeared at a path with no original"
grep -qF /etc/kg_key "$w/err" || fail "that restore refusal names the path: $(cat "$w/err")"
holds "$V/etc/kg_key" generated-key && [ "$("$PB" -c 'Print :adopts:/etc/kg_key:kind' "$SR/kg/applied.plist" 2>/dev/null)" = identity ] \
  || fail "that restore leaves the foreign file and drops nothing"
mv "$V/etc/kg_key" "$w/kg-aside"
mg system-restore kg 2>"$w/err" || fail "restore succeeds once the foreign file is moved aside: $(cat "$w/err")"

mkadopt ls3 /etc/ls3_config=ls3_config:config
echo admin-ls3 > "$V/etc/ls3_config"; seeded ls3 ls3_config default-ls3
(PATH="$mvstub:$PATH" MV_FAIL=var/ls3/ls3_config mg system-replace ls3 2>"$w/err") && fail "setup: a replace whose var link fails must fail"
rm -f "$SR/ls3/staging/ls3_config"; mkdir "$SR/ls3/staging/ls3_config"
mg system-replace ls3 2>"$w/err" && fail "a link-only rerun must refuse a directory at staging/<rel> before any change"
grep -qF "$SR/ls3/staging/ls3_config is in the way" "$w/err" || fail "that refusal names the staging node: $(cat "$w/err")"
holds "$T/var/ls3/ls3_config" default-ls3 && gone "$T/var/ls3/.ls3_config.mavergreen-tmp" || fail "that refusal changes nothing"
rmdir "$SR/ls3/staging/ls3_config"
mg system-replace ls3 2>"$w/err" || fail "setup: the rerun links once the directory is gone: $(cat "$w/err")"
mg system-restore ls3 || fail "setup: system-restore ls3 must succeed"

cat > "$mvstub/shasum" <<'STUB'
#!/bin/sh
t="$(mktemp "${TMPDIR:-/tmp}/shastub.XXXXXX")" || exit 1
cat > "$t"
if [ -n "$SHA_FAIL" ] && grep -q "$SHA_FAIL" "$t"; then
  n=$(($(cat "$SHA_COUNT" 2>/dev/null || echo 0) + 1)); echo "$n" > "$SHA_COUNT"
  if [ "$n" = "${SHA_NTH:-1}" ]; then rm -f "$t"; exit 1; fi
fi
/usr/bin/shasum "$@" < "$t"; rc=$?; rm -f "$t"; exit "$rc"
STUB
chmod +x "$mvstub/shasum"
shafail() {  # $1 marker  $2 which checksum of content holding it fails  $3.. the mg command
  _sm="$1"; _sn="$2"; shift 2; rm -f "$w/shacount"
  (PATH="$mvstub:$PATH" SHA_FAIL="$_sm" SHA_NTH="$_sn" SHA_COUNT="$w/shacount" mg "$@" 2>"$w/err")
}
mkadopt hs /etc/hs_config=hs_config:config
echo "admin-hs MARK-HS" > "$V/etc/hs_config"; seeded hs hs_config default-hs
shafail MARK-HS 2 system-replace hs && fail "a decision whose checksum of the system file fails must refuse"
grep -qF "could not checksum /etc/hs_config" "$w/err" || fail "that refusal names the system file: $(cat "$w/err")"
gone "$SR/hs" && holds "$T/var/hs/hs_config" default-hs || fail "that refusal changes nothing"
mkadopt hv /etc/hv_config=hv_config:config
echo apple-hv > "$V/etc/hv_config"; receipt "$V" hv ./etc/hv_config "$V/etc/hv_config"
mkdir -p "$T/var/hv"; echo "product-hv MARK-HV" > "$T/var/hv/hv_config"
shafail MARK-HV 2 system-replace hv && fail "a decision whose checksum of the var file fails must refuse"
grep -qF "could not checksum /usr/local/mavergreen/var/hv/hv_config" "$w/err" || fail "that refusal names the var file: $(cat "$w/err")"
gone "$SR/hv" && holds "$V/etc/hv_config" apple-hv || fail "that refusal changes nothing"
mkadopt hr /etc/hr_config=hr_config:config
mkdir -p "$T/var/hr"; echo "product-hr MARK-HR" > "$T/var/hr/hr_config"
mg system-replace hr || fail "setup: system-replace hr must succeed"
shafail MARK-HR 2 system-restore hr && fail "a restore that cannot checksum the live file must fail"
links hr hr_config /etc/hr_config && [ -f "$V/etc/hr_config" ] && ! grep -q " var /etc/hr_config" "$SR/hr/restored.sha256" 2>/dev/null \
  || fail "that restore changes nothing and records no baseline"
mg system-restore hr || fail "setup: system-restore hr must succeed"
mkadopt ho /etc/ho_config=ho_config:config
echo "apple-ho MARK-HO" > "$V/etc/ho_config"; receipt "$V" ho ./etc/ho_config "$V/etc/ho_config"; seeded ho ho_config default-ho
mg system-replace ho || fail "setup: system-replace ho must succeed"
shafail MARK-HO 1 system-restore ho && fail "a restore that cannot checksum the saved original must fail"
links ho ho_config /etc/ho_config && holds "$SR/ho/etc/ho_config" "apple-ho MARK-HO" || fail "that restore changes nothing"
mg system-restore ho || fail "setup: system-restore ho must succeed"
rm -f "$mvstub/shasum"

mkadopt ub /etc/ub_config=ub_config:config
echo apple-ub > "$V/etc/ub_config"; receipt "$V" ub ./etc/ub_config "$V/etc/ub_config"; seeded ub ub_config default-ub
chmod 000 "$V/var/db/receipts/com.apple.pkg.ub.bom"
mg system-replace ub 2>"$w/err" || fail "system-replace must not fail on an unreadable receipt: $(cat "$w/err")"
chmod 644 "$V/var/db/receipts/com.apple.pkg.ub.bom"
holds "$V/etc/ub_config" apple-ub || fail "a file listed only in an unreadable receipt is not stock, so it stays"
mg system-restore ub || fail "setup: system-restore ub must succeed"

hostf=""
for _hf in /etc/csh.login /etc/csh.cshrc /etc/zshenv /etc/networks /etc/manpaths /etc/profile; do
  [ -r "$_hf" ] || continue
  _hck="$(cksum < "$_hf")"
  if for _hb in /var/db/receipts/com.apple.pkg.*.bom; do lsbom -p fcs "$_hb" 2>/dev/null; done \
     | F="$_hf" C="${_hck%% *}" Z="${_hck#* }" awk -F '\t' '($1 == "./private" ENVIRON["F"] || $1 == "." ENVIRON["F"]) && $2 == ENVIRON["C"] && $3 == ENVIRON["Z"] { f = 1 } END { exit !f }'
  then hostf="$_hf"; break; fi
done
if [ -n "$hostf" ]; then
  mkadopt hostr "$hostf=hostr_conf:config"
  mkdir -p "$V$(dirname "$hostf")"; cp "$hostf" "$V$hostf"; seeded hostr hostr_conf default-hostr
  mg system-replace hostr 2>"$w/err" || fail "setup: system-replace hostr must succeed: $(cat "$w/err")"
  cmp -s "$V$hostf" "$hostf" || fail "a file that is stock only by the running system's receipts is customized on another volume: receipts are read under --root alone"
  mg system-restore hostr || fail "setup: system-restore hostr must succeed"
else
  echo "no host file matches a host receipt -- skipping the host-receipts isolation test" >&2
fi

hook() {  # $1 product  $2 hook name  $3 the hook's body after its shebang
  mkdir -p "$T/$1/libexec/mavergreen"
  printf '#!/bin/sh\n%s\n' "$3" > "$T/$1/libexec/mavergreen/$2"; chmod +x "$T/$1/libexec/mavergreen/$2"
}
untouched() {  # $1 product  $2 why; the mkhk product's system files, var file and save area are as before
  holds "$V/etc/$1_config" "admin-$1" && [ "$(stat -f %i "$V/etc/$1_config")" = "$ino" ] \
    && holds "$V/usr/bin/$1" "apple-$1" && [ "$(stat -f %i "$V/usr/bin/$1")" = "$bino" ] \
    && holds "$T/var/$1/$1_config" "default-$1" && gone "$SR/$1" \
    && gone "$V/etc/.$1_config.mavergreen-tmp" && gone "$V/usr/bin/.$1.mavergreen-tmp" \
    || fail "$2: every path must be left untouched and no save area created ($(ls -A "$SR/$1" 2>&1))"
}
mkhk() {  # $1 product: an adopted config the admin customized, a seeded default, and a replaced program
  mkadopt "$1" "/etc/$1_config=$1_config:config"
  "$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/$1 string bin/stub" "$T/$1/mavergreen.plist"
  echo "admin-$1" > "$V/etc/$1_config"; echo "apple-$1" > "$V/usr/bin/$1"; seeded "$1" "$1_config" "default-$1"
  ino="$(stat -f %i "$V/etc/$1_config")"; bino="$(stat -f %i "$V/usr/bin/$1")"
}

mkhk hk1
hook hk1 pre-system-replace "echo ran > '$w/hk1.ran'; exit 1"
rc=0; mg system-replace hk1 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "system-replace must refuse when its pre-system-replace hook exits non-zero"
[ -f "$w/hk1.ran" ] || fail "setup: the pre-system-replace hook must have run"
grep -qF "$T/hk1/libexec/mavergreen/pre-system-replace" "$w/err" || fail "the refusal names the pre-system-replace hook: $(cat "$w/err")"
untouched hk1 "a refusing pre-system-replace hook"

mkhk hk2
chmod 640 "$V/etc/hk2_config"
hook hk2 pre-system-replace "f=\"\$MAVERGREEN_STAGING/hk2_config\"
printf '%s|%s|%s|%s\n' \"\$MAVERGREEN_ROOT\" \"\$MAVERGREEN_PRODUCT\" \"\$MAVERGREEN_STAGING\" \"\$(stat -f %Lp \"\$f\")\" > '$w/hk2.env'
{ cat \"\$f\" && echo 'Include hook-line'; } > \"\$f.new\" && chmod 600 \"\$f.new\" && /bin/mv \"\$f.new\" \"\$f\""
mg system-replace hk2 2>"$w/err" || fail "system-replace must succeed when its pre-system-replace hook exits 0: $(cat "$w/err")"
[ "$(cat "$w/hk2.env")" = "$V|hk2|$SR/hk2/staging|640" ] \
  || fail "the pre-system-replace hook gets MAVERGREEN_ROOT, MAVERGREEN_PRODUCT and MAVERGREEN_STAGING, and a staged file already holding the original's mode: $(cat "$w/hk2.env")"
printf 'admin-hk2\nInclude hook-line\n' > "$w/hk2.expect"
is_copy "$V/etc/hk2_config" "$w/hk2.expect" || fail "the hook's edit to the staged file becomes live at the system path: $(cat "$V/etc/hk2_config")"
[ "$(stat -f %Lp "$V/etc/hk2_config")" = 640 ] \
  || fail "a staged file the hook rewrote still takes the original's mode: $(stat -f %Lp "$V/etc/hk2_config")"
[ "$(awk '{ print $1 }' "$SR/hk2/adopted.sha256")" = "$(sha "$w/hk2.expect")" ] \
  || fail "adopted.sha256 records the content the hook left, which is what became live"
links hk2 hk2_config /etc/hk2_config || fail "after the hook, var links to the system path"
mg system-restore hk2 >"$w/out" 2>"$w/err" || fail "setup: system-restore hk2 must succeed: $(cat "$w/err")"
if grep -q 'settings in /etc/hk2_config' "$w/out"; then fail "restore reports no settings for a config left as it was adopted: $(cat "$w/out")"; fi

mkhk hk3
mkdir -p "$T/hk3/libexec/mavergreen"
printf '#!/bin/sh\ntouch "%s/hk3.ran"\n' "$w" > "$w/hk3-real"; chmod +x "$w/hk3-real"
ln -s "$w/hk3-real" "$T/hk3/libexec/mavergreen/pre-system-replace"
rc=0; mg system-replace hk3 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "system-replace must refuse a symlinked pre-system-replace hook"
grep -qF "$T/hk3/libexec/mavergreen/pre-system-replace" "$w/err" || fail "the refusal names the symlinked hook: $(cat "$w/err")"
gone "$w/hk3.ran" || fail "a refused symlinked hook's target must never run"
untouched hk3 "a symlinked pre-system-replace hook"

mkhk hk4
hook hk4 pre-system-replace 'f="$MAVERGREEN_STAGING/hk4_config"; echo elsewhere > "$f.real"; rm -f "$f"; ln -s "$f.real" "$f"'
rc=0; mg system-replace hk4 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "system-replace must refuse when its pre-system-replace hook leaves a staged file that is not a regular file"
grep -qF "$SR/hk4/staging/hk4_config" "$w/err" || fail "that refusal names the staged file: $(cat "$w/err")"
untouched hk4 "a hook that left a symlink in staging"

mkhk hk5
mkdir -p "$T/hk5/libexec/mavergreen"
printf '#!/bin/sh\ntouch "%s/hk5.ran"\n' "$w" > "$w/hk5-real"; chmod +x "$w/hk5-real"
ln -s "$w/hk5-real" "$T/hk5/libexec/mavergreen/post-system-replace"
rc=0; mg system-replace hk5 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "system-replace must refuse a symlinked post-system-replace hook before any change"
grep -qF "$T/hk5/libexec/mavergreen/post-system-replace" "$w/err" || fail "the refusal names the symlinked post hook: $(cat "$w/err")"
gone "$w/hk5.ran" || fail "a refused symlinked post hook's target must never run"
untouched hk5 "a symlinked post-system-replace hook"

mkhk hk6
hook hk6 post-system-replace "printf '%s|%s|%s\n' \"\$MAVERGREEN_ROOT\" \"\$MAVERGREEN_PRODUCT\" \"\${MAVERGREEN_STAGING-unset}\" > '$w/hk6.env'
[ -f \"\$MAVERGREEN_ROOT/usr/local/mavergreen/var/system-replace/hk6/.replaced\" ] && echo marked >> '$w/hk6.env'
exit 3"
(MAVERGREEN_STAGING=/leaked; export MAVERGREEN_STAGING; mg system-replace hk6 2>"$w/err") \
  || fail "a failing post-system-replace hook is reported, and replace still succeeds: $(cat "$w/err")"
grep -qF "$T/hk6/libexec/mavergreen/post-system-replace" "$w/err" && grep -q 'status 3' "$w/err" \
  || fail "the post-system-replace failure is reported, naming the hook and its status: $(cat "$w/err")"
[ "$(sed -n 1p "$w/hk6.env")" = "$V|hk6|unset" ] \
  || fail "a post hook gets MAVERGREEN_ROOT and MAVERGREEN_PRODUCT, and never MAVERGREEN_STAGING: $(cat "$w/hk6.env")"
[ "$(sed -n 2p "$w/hk6.env")" = marked ] || fail "the post-system-replace hook runs after .replaced is marked"
is_copy "$V/usr/bin/hk6" "$T/hk6/bin/stub" && links hk6 hk6_config /etc/hk6_config && [ -f "$SR/hk6/.replaced" ] \
  || fail "a failing post-system-replace hook leaves the replacement in place"
rm "$T/hk6/libexec/mavergreen/post-system-replace"
mg system-restore hk6 || fail "setup: system-restore hk6 must succeed"

mkhk hk7
mg system-replace hk7 2>"$w/err" || fail "setup: system-replace hk7 must succeed: $(cat "$w/err")"
hook hk7 post-system-restore "printf '%s|%s|%s\n' \"\$MAVERGREEN_ROOT\" \"\$MAVERGREEN_PRODUCT\" \"\${MAVERGREEN_STAGING-unset}\" > '$w/hk7.env'
grep -qx apple-hk7 \"\$MAVERGREEN_ROOT/usr/bin/hk7\" && echo restored >> '$w/hk7.env'
exit 4"
rc=0; mg system-restore hk7 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "system-restore must exit non-zero when its post-system-restore hook fails"
grep -qF "$T/hk7/libexec/mavergreen/post-system-restore" "$w/err" || fail "the failure names the post-system-restore hook: $(cat "$w/err")"
[ "$(cat "$w/hk7.env" 2>&1)" = "$V|hk7|unset
restored" ] || fail "the post-system-restore hook runs after the originals are back, with ROOT and PRODUCT only: $(cat "$w/hk7.env" 2>&1)"
holds "$V/usr/bin/hk7" apple-hk7 && [ "$(stat -f %i "$V/usr/bin/hk7")" = "$bino" ] \
  && holds "$V/etc/hk7_config" admin-hk7 && [ "$(stat -f %i "$V/etc/hk7_config")" = "$ino" ] && gone "$SR/hk7/applied.plist" \
  || fail "a failing post-system-restore hook leaves the originals restored"

mkhk hk8
mg system-replace hk8 2>"$w/err" || fail "setup: system-replace hk8 must succeed: $(cat "$w/err")"
"$PB" -c "Add ':adopts:/etc/hk8b_config' dict" -c "Add ':adopts:/etc/hk8b_config:path' string hk8b_config" \
      -c "Add ':adopts:/etc/hk8b_config:kind' string config" "$T/hk8/mavergreen.plist"
seeded hk8 hk8b_config default-hk8b
cp "$SR/hk8/applied.plist" "$w/hk8.applied"
hook hk8 pre-system-replace 'exit 1'
(mg system-replace hk8 2>"$w/err") && fail "setup: a rerun with a refusing pre-system-replace hook must fail"
gone "$SR/hk8/staging/hk8b_config" || fail "a refusing hook leaves no staged candidate behind, even in a staging/ that was already there"
[ -f "$SR/hk8/staging/hk8_config" ] || fail "a refusing hook leaves the files staging/ already held"
cmp -s "$SR/hk8/applied.plist" "$w/hk8.applied" && holds "$T/var/hk8/hk8b_config" default-hk8b && gone "$V/etc/hk8b_config" \
  || fail "a refusing hook on a rerun changes nothing"
rm "$T/hk8/libexec/mavergreen/pre-system-replace"
mg system-restore hk8 || fail "setup: system-restore hk8 must succeed"

mkproduct hk9 hk9 "" bin/hk9
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/hk9 string bin/hk9" "$T/hk9/mavergreen.plist"
echo apple-hk9 > "$V/usr/bin/hk9"
hook hk9 pre-system-replace '[ -d "$MAVERGREEN_STAGING" ] || exit 7'
mg system-replace hk9 2>"$w/err" || fail "MAVERGREEN_STAGING is a directory even for a product that adopts nothing: $(cat "$w/err")"
mg system-restore hk9 || fail "setup: system-restore hk9 must succeed"

mkadopt hk10 /etc/hk10_config=hk10_config:config
echo apple-hk10 > "$V/etc/hk10_config"; chmod 640 "$V/etc/hk10_config"; receipt "$V" hk10 ./etc/hk10_config "$V/etc/hk10_config"
seeded hk10 hk10_config default-hk10; chmod 644 "$T/var/hk10/hk10_config"
hook hk10 pre-system-replace "stat -f %Lp \"\$MAVERGREEN_STAGING/hk10_config\" > '$w/hk10.mode'"
mg system-replace hk10 2>"$w/err" || fail "setup: system-replace hk10 must succeed: $(cat "$w/err")"
holds "$V/etc/hk10_config" default-hk10 || fail "setup: the product's default moves in over a stock system file"
[ "$(cat "$w/hk10.mode")" = 640 ] \
  || fail "the pre-system-replace hook sees a staged product file that already has the original's mode: $(cat "$w/hk10.mode")"
mg system-restore hk10 || fail "setup: system-restore hk10 must succeed"

mkproduct sk sk "" bin/sk
chmod 4755 "$T/sk/bin/sk"
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/sk string bin/sk" "$T/sk/mavergreen.plist"
echo apple-sk > "$V/usr/bin/sk"; chmod 4711 "$V/usr/bin/sk"
(umask 022; mg system-replace sk 2>"$w/err") || fail "setup: system-replace sk must succeed: $(cat "$w/err")"
[ "$(stat -f %Mp%Lp "$SR/sk/usr/bin/sk")" = 4711 ] || fail "setup: the saved original keeps its setuid mode"
[ "$(stat -f %Lp "$SR/sk")" = 700 ] \
  || fail "the save area holds setuid originals, so only its owner can reach them, whatever the umask (R62): $(stat -f %Lp "$SR/sk")"
mg check 2>"$w/err" || true
if grep -qF "$SR/sk " "$w/err"; then fail "check must not report a root-only save area: $(cat "$w/err")"; fi
chmod 755 "$SR/sk"
mg check 2>"$w/err" && fail "check must fail once other users can reach the save area (R62)"
grep -qF "$SR/sk holds sk's saved originals" "$w/err" || fail "check names the save area other users can reach (R62): $(cat "$w/err")"
(umask 022; mg system-replace sk 2>"$w/err") || fail "a rerun must succeed: $(cat "$w/err")"
[ "$(stat -f %Lp "$SR/sk")" = 700 ] || fail "every system-replace makes a save area an older helper left open root-only again (R62): $(stat -f %Lp "$SR/sk")"
chmod 777 "$SR"
mg system-replace sk 2>"$w/err" && fail "system-replace must refuse while a directory above the save area is not root-only (R62)"
grep -qF "$SR is not root-only" "$w/err" || fail "that refusal names the directory: $(cat "$w/err")"
mg check 2>"$w/err" && fail "check must fail while a directory above the save area is not root-only (R62)"
grep -qF "$SR is not root-only" "$w/err" || fail "check names that directory: $(cat "$w/err")"
chmod 755 "$SR"
mg system-restore sk || fail "setup: system-restore sk must succeed"

Ve="$w/Mac=HD"; Te="$Ve/usr/local/mavergreen"
mkdir -p "$Ve/usr/bin" "$Ve/System/Library/CoreServices"
"$PB" -c "Add :ProductVersion string 10.9.5" "$Ve/System/Library/CoreServices/SystemVersion.plist" >/dev/null
mge() { MAVERGREEN_TRUSTED_UID="$(id -u)" sh "$MG" --root "$Ve" "$@"; }
(T="$Te"; mkproduct eq eq "" bin/eq; hook eq pre-system-replace "echo 'visudo -c: parse error' >&2; exit 1")
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/eq string bin/eq" "$Te/eq/mavergreen.plist"
echo apple-eq > "$Ve/usr/bin/eq"
rc=0; mge system-replace eq >"$w/out" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "a pre-system-replace hook that exits 1 refuses the replace when the volume's path holds = too (R63): got $rc"
grep -qF "visudo -c: parse error" "$w/err" && grep -qF "$Te/eq/libexec/mavergreen/pre-system-replace" "$w/err" \
  || fail "the hook ran, and the refusal names it: $(cat "$w/err")"
[ ! -s "$w/out" ] || fail "running a hook prints nothing of the helper's own on stdout, never the environment (R63): $(head -c 300 "$w/out")"
holds "$Ve/usr/bin/eq" apple-eq && gone "$Te/var/system-replace/eq" || fail "that refusal changes nothing (R63)"
(T="$Te"; hook eq pre-system-replace "printf '%s|%s|%s\n' \"\$MAVERGREEN_ROOT\" \"\$MAVERGREEN_PRODUCT\" \"\$MAVERGREEN_STAGING\" > '$w/eq.env'")
mge system-replace eq >"$w/out" 2>"$w/err" || fail "system-replace on a volume whose path holds = must succeed: $(cat "$w/err")"
[ "$(cat "$w/eq.env")" = "$Ve|eq|$Te/var/system-replace/eq/staging" ] \
  || fail "the hook gets each MAVERGREEN_* variable intact, = and all (R63): $(cat "$w/eq.env")"
[ ! -s "$w/out" ] || fail "a passing hook prints nothing of the helper's own on stdout (R63): $(head -c 300 "$w/out")"
mge system-restore eq || fail "setup: system-restore eq must succeed"
(T="$Te"; hook eq pre-uninstall "touch '$w/eq.ran'; exit 1")
rc=0; PATH="$stub:$PATH" mge uninstall eq >"$w/out" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] && [ -f "$w/eq.ran" ] && [ -d "$Te/eq" ] && [ ! -s "$w/out" ] \
  || fail "a failing pre-uninstall hook still stops uninstall on a volume whose path holds = (R63): rc $rc, $(cat "$w/err")"
rm -rf "$Ve"

mkhk hm
hook hm pre-system-replace "touch '$w/hm.ran'"
chmod 777 "$T/hm/libexec/mavergreen"
rc=0; mg system-replace hm 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "system-replace must refuse to run a hook from a directory another user can write (M5)"
grep -qF "$T/hm/libexec/mavergreen is not root-only" "$w/err" || fail "that refusal names the directory: $(cat "$w/err")"
gone "$w/hm.ran" || fail "a hook in a directory another user can write never runs (M5)"
untouched hm "a hook in a world-writable directory"
chmod 755 "$T/hm/libexec/mavergreen"; chmod 777 "$T/hm/libexec/mavergreen/pre-system-replace"
rc=0; mg system-replace hm 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] && grep -qF "$T/hm/libexec/mavergreen/pre-system-replace is not root-only" "$w/err" && gone "$w/hm.ran" \
  || fail "a hook file another user can write never runs, and the refusal names it (M5): $(cat "$w/err")"
untouched hm "a world-writable hook"
rm "$T/hm/libexec/mavergreen/pre-system-replace"; chmod 777 "$T/hm/libexec/mavergreen"
mg system-replace hm 2>"$w/err" || fail "setup: system-replace hm with no hook must succeed: $(cat "$w/err")"
hook hm post-system-restore "touch '$w/hm.post'"
rc=0; mg system-restore hm 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] && gone "$w/hm.post" && grep -qF "$T/hm/libexec/mavergreen is not root-only" "$w/err" \
  || fail "a post-system-restore hook in a directory another user can write is refused (R70): $(cat "$w/err")"
is_copy "$V/usr/bin/hm" "$T/hm/bin/stub" && links hm hm_config /etc/hm_config && [ -f "$SR/hm/.replaced" ] \
  || fail "a post-system-restore hook the ownership walk refuses stops the restore before any change (R77)"
rm "$T/hm/libexec/mavergreen/post-system-restore"
hook hm pre-uninstall "touch '$w/hm.ran'"
rc=0; PATH="$stub:$PATH" mg uninstall hm 2>"$w/err" || rc=$?
[ "$rc" -eq 0 ] && [ -f "$w/hm.ran" ] && gone "$T/hm" \
  || fail "a pre-uninstall hook keeps the checks it had before System Replace, so it runs from a tree directory another user can write, as on a Mac whose /usr/local Homebrew owns (R70): rc $rc, $(cat "$w/err")"

mkadopt rp /etc/rp_a=rp_a:config /etc/rp_b=rp_b:config /etc/rp_n=rp_n:config /etc/rp_k=rp_k:identity
echo admin-a > "$V/etc/rp_a"; echo admin-b > "$V/etc/rp_b"; echo key-k > "$V/etc/rp_k"
seeded rp rp_a default-a; seeded rp rp_b default-b; seeded rp rp_n default-n
mg system-replace rp 2>"$w/err" || fail "setup: system-replace rp must succeed: $(cat "$w/err")"
echo 'PasswordAuthentication no' >> "$V/etc/rp_a"; echo 'UsePAM yes' >> "$V/etc/rp_n"; echo secret-k >> "$V/etc/rp_k"
mg system-restore rp >"$w/out" 2>"$w/err" || fail "setup: system-restore rp must succeed: $(cat "$w/err")"
grep -qxF 'mavergreen: settings in /etc/rp_a that the restored original does not have:' "$w/out" \
  || fail "restore prints a header for an adopted config edited since it was adopted: $(cat "$w/out")"
grep -qxF '+PasswordAuthentication no' "$w/out" || fail "restore prints a diff -u of the original against the live file: $(cat "$w/out")"
grep -q "^--- $SR/rp/etc/rp_a" "$w/out" && grep -q '^+++ .*/etc/rp_a' "$w/out" \
  || fail "the diff runs from the original being restored to the live file: $(cat "$w/out")"
grep -qxF 'mavergreen: settings in /etc/rp_n that the restored original does not have:' "$w/out" \
  && grep -q '^--- /dev/null' "$w/out" && grep -qxF '+UsePAM yes' "$w/out" \
  || fail "an edited config with no original is diffed against nothing: $(cat "$w/out")"
if grep -q 'rp_b' "$w/out"; then fail "restore reports nothing for an adopted config left as it was adopted: $(cat "$w/out")"; fi
if grep -q 'rp_k\|secret-k' "$w/out"; then fail "restore never diffs an identity entry: $(cat "$w/out")"; fi

mkadopt us /etc/us_a=us_a:config /etc/us_b=us_b:config /etc/us_c=us_c:config /etc/us_k=us_k:identity
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/us string bin/stub" "$T/us/mavergreen.plist"
echo apple-us > "$V/usr/bin/us"; echo key-us > "$V/etc/us_k"
seeded us us_a default-a; seeded us us_b default-b; echo product-c > "$T/var/us/us_c"
mg system-replace us 2>"$w/err" || fail "setup: system-replace us must succeed: $(cat "$w/err")"
echo admin-edit >> "$V/etc/us_a"; echo key-edit >> "$V/etc/us_k"; cp "$V/etc/us_a" "$w/us_a.expect"
PATH="$stub:$PATH" mg uninstall us >"$w/out" 2>"$w/err" || fail "uninstall of a replaced product must succeed: $(cat "$w/err")"
is_copy "$V/etc/us_a.mavergreen-save" "$w/us_a.expect" \
  || fail "uninstall keeps a replaced product's changed config as <path>.mavergreen-save"
grep -qF /etc/us_a.mavergreen-save "$w/out" || fail "uninstall says where it kept the changed config: $(cat "$w/out")"
gone "$V/etc/us_b.mavergreen-save" || fail "uninstall saves nothing for a config that still matches its seed"
holds "$V/etc/us_c.mavergreen-save" product-c || fail "a config with no seed record counts as changed, so uninstall keeps it (R8)"
gone "$V/etc/us_k.mavergreen-save" || fail "uninstall never saves an identity entry"
gone "$V/etc/us_a" && holds "$V/etc/us_k" key-us && holds "$V/usr/bin/us" apple-us \
  || fail "uninstall restores the originals before removing the product"
gone "$T/us" && gone "$T/var/us" && gone "$SR/us" || fail "uninstall removes the tree, var/ and var/system-replace/us: $(ls -A "$SR/us" 2>&1)"
mkadopt us /etc/us_a=us_a:config /etc/us_b=us_b:config /etc/us_c=us_c:config /etc/us_k=us_k:identity
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/us string bin/stub" "$T/us/mavergreen.plist"
seeded us us_a default-a; seeded us us_b default-b; echo product-c > "$T/var/us/us_c"
mg system-replace us 2>"$w/err" || fail "a reinstalled product replaces again after uninstall: $(cat "$w/err")"
holds "$V/etc/us_a" default-a && is_copy "$V/usr/bin/us" "$T/us/bin/stub" && holds "$V/etc/us_k" key-us \
  || fail "the replace after uninstall and reinstall starts from the restored originals"
mg system-restore us || fail "setup: system-restore us must succeed"

mkadopt nr /etc/nr_config=nr_config:config
echo apple-nr > "$V/etc/nr_config"; seeded nr nr_config default-nr; echo admin-nr > "$T/var/nr/nr_config"
outside() { (cd "$V" && find . -path ./usr/local/mavergreen/nr -prune -o -path ./usr/local/mavergreen/var/nr -prune -o -print | sort); }
outside > "$w/nr.before"
PATH="$stub:$PATH" mg uninstall nr 2>"$w/err" || fail "uninstall of a never-replaced product must succeed: $(cat "$w/err")"
outside > "$w/nr.after"
cmp -s "$w/nr.before" "$w/nr.after" \
  || fail "uninstalling a never-replaced product writes nothing outside its tree and var: $(diff "$w/nr.before" "$w/nr.after")"

mkadopt hf6 /etc/hf6_config=hf6_config:config
echo admin-hf6 > "$V/etc/hf6_config"; seeded hf6 hf6_config default-hf6
mg system-replace hf6 2>"$w/err" || fail "setup: system-replace hf6 must succeed: $(cat "$w/err")"
rm "$SR/hf6/.replaced"
PATH="$stub:$PATH" mg uninstall hf6 2>"$w/err" || fail "uninstall of a half-finished replace must succeed: $(cat "$w/err")"
holds "$V/etc/hf6_config.mavergreen-save" admin-hf6 || fail "uninstall keeps changed config whenever applied.plist records a replace, .replaced or not (R75)"
holds "$V/etc/hf6_config" admin-hf6 && gone "$T/hf6" || fail "uninstall of a half-finished replace restores and removes it"

mkproduct so so "" bin/so
mkdir -p "$SR/so/usr/bin"; echo apple-so > "$SR/so/usr/bin/so"
rc=0; PATH="$stub:$PATH" mg uninstall so 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "uninstall must refuse while its save area holds a saved original that no applied.plist names"
grep -qF usr/bin/so "$w/err" || fail "that refusal names the saved original: $(cat "$w/err")"
holds "$SR/so/usr/bin/so" apple-so && [ -d "$T/so" ] || fail "uninstall never removes a saved original with the save area"
mg system-restore so 2>"$w/err" || fail "setup: a legacy system-restore so must succeed: $(cat "$w/err")"
PATH="$stub:$PATH" mg uninstall so 2>"$w/err" || fail "uninstall succeeds once the original is back: $(cat "$w/err")"
holds "$V/usr/bin/so" apple-so && gone "$SR/so" && gone "$T/so" || fail "the original stays restored after uninstall"

mkadopt ex /etc/ex_config=ex_config:config
seeded ex ex_config default-ex
mg system-replace ex 2>"$w/err" || fail "setup: system-replace ex must succeed: $(cat "$w/err")"
echo admin-ex >> "$V/etc/ex_config"; cp "$V/etc/ex_config" "$w/ex.expect"
hook ex pre-uninstall "touch '$w/ex.ran'"
mkdir "$V/etc/.ex_config.mavergreen-save.mavergreen-tmp"
rc=0; PATH="$stub:$PATH" mg uninstall ex 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "uninstall must refuse when the temporary path beside the save it would write is not a regular file"
grep -qF /etc/.ex_config.mavergreen-save.mavergreen-tmp "$w/err" || fail "that refusal names the temporary path: $(cat "$w/err")"
gone "$w/ex.ran" && links ex ex_config /etc/ex_config && [ -d "$T/ex" ] || fail "that refusal comes before any change"
rmdir "$V/etc/.ex_config.mavergreen-save.mavergreen-tmp"
mkdir "$V/etc/ex_config.mavergreen-save"
rc=0; PATH="$stub:$PATH" mg uninstall ex 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "uninstall must refuse when the save path is a directory, which mv would move the save into"
grep -qF /etc/ex_config.mavergreen-save "$w/err" || fail "that refusal names the save path: $(cat "$w/err")"
gone "$w/ex.ran" && links ex ex_config /etc/ex_config && [ -d "$T/ex" ] && [ -d "$V/etc/ex_config.mavergreen-save" ] \
  && gone "$V/etc/ex_config.mavergreen-save/ex_config.mavergreen-save" || fail "that refusal comes before any change"
rmdir "$V/etc/ex_config.mavergreen-save"
echo older-save > "$V/etc/ex_config.mavergreen-save"
rc=0; (PATH="$mvstub:$stub:$PATH" MV_FAIL=etc/ex_config.mavergreen-save mg uninstall ex 2>"$w/err") || rc=$?
[ "$rc" -ne 0 ] || fail "setup: an uninstall whose rename of the new save fails must fail"
holds "$V/etc/ex_config.mavergreen-save" older-save && is_copy "$T/var/ex/ex_config" "$w/ex.expect" && [ -d "$T/ex" ] \
  && gone "$V/etc/.ex_config.mavergreen-save.mavergreen-tmp" \
  || fail "until the new save is renamed into place, the older save and the var file both stay"
PATH="$stub:$PATH" mg uninstall ex >"$w/out" 2>"$w/err" || fail "uninstall overwrites an older .mavergreen-save rather than refusing (R34): $(cat "$w/err")"
is_copy "$V/etc/ex_config.mavergreen-save" "$w/ex.expect" || fail "the older save is replaced by the config uninstall keeps (R34)"
grep -qF /etc/ex_config.mavergreen-save "$w/out" && gone "$T/ex" && gone "$V/etc/.ex_config.mavergreen-save.mavergreen-tmp" \
  || fail "uninstall says where it kept the config and finishes: $(cat "$w/out")"

mkadopt ei /etc/ei_config=ei_config:config
seeded ei ei_config default-ei
mg system-replace ei 2>"$w/err" || fail "setup: system-replace ei must succeed: $(cat "$w/err")"
echo admin-ei >> "$V/etc/ei_config"
cp "$V/etc/ei_config" "$V/etc/ei_config.mavergreen-save"; sino="$(stat -f %i "$V/etc/ei_config.mavergreen-save")"
echo stale > "$V/etc/.ei_config.mavergreen-save.mavergreen-tmp"
PATH="$stub:$PATH" mg uninstall ei 2>"$w/err" || fail "uninstall must succeed when the existing save already holds the config: $(cat "$w/err")"
[ "$(stat -f %i "$V/etc/ei_config.mavergreen-save")" = "$sino" ] && gone "$T/ei" \
  || fail "an identical existing save is left as it is"
gone "$V/etc/.ei_config.mavergreen-save.mavergreen-tmp" || fail "uninstall removes a leftover temporary file beside the save"

mkadopt pf /etc/pf_config=pf_config:config
seeded pf pf_config default-pf
mg system-replace pf 2>"$w/err" || fail "setup: system-replace pf must succeed: $(cat "$w/err")"
echo admin-pf >> "$V/etc/pf_config"; cp "$V/etc/pf_config" "$w/pf.expect"
hook pf post-system-restore 'exit 5'
rc=0; PATH="$stub:$PATH" mg uninstall pf 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "uninstall exits non-zero when its post-system-restore hook fails (R33)"
grep -qF "$T/pf/libexec/mavergreen/post-system-restore" "$w/err" || fail "uninstall reports the failing post-system-restore hook: $(cat "$w/err")"
gone "$T/pf" && gone "$T/var/pf" && gone "$SR/pf" && is_copy "$V/etc/pf_config.mavergreen-save" "$w/pf.expect" && gone "$V/etc/pf_config" \
  || fail "a failing post-system-restore hook does not stop uninstall from finishing (R33)"

mkadopt kl /etc/kl_config=kl_config:config
seeded kl kl_config default-kl
mg system-replace kl 2>"$w/err" || fail "setup: system-replace kl must succeed: $(cat "$w/err")"
echo admin-kl >> "$V/etc/kl_config"; cp "$V/etc/kl_config" "$w/kl.expect"
hook kl post-system-restore "if [ ! -e '$w/kl.killed' ]; then touch '$w/kl.killed'; kill -9 \$PPID; sleep 5; fi"
rc=0; PATH="$stub:$PATH" mg uninstall kl 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] && [ -f "$w/kl.killed" ] || fail "setup: an uninstall killed after its restore must fail"
gone "$V/etc/kl_config.mavergreen-save" && is_copy "$T/var/kl/kl_config" "$w/kl.expect" \
  || fail "setup: the kill lands after the restore and before the save"
PATH="$stub:$PATH" mg uninstall kl 2>"$w/err" || fail "a rerun of an uninstall killed between restore and save must succeed: $(cat "$w/err")"
is_copy "$V/etc/kl_config.mavergreen-save" "$w/kl.expect" \
  || fail "a rerun of an uninstall killed between restore and save still keeps the admin's config"
gone "$T/kl" && gone "$SR/kl" || fail "the rerun finishes the uninstall"

mkadopt vc /etc/vc_config=vc_config:config
seeded vc vc_config default-vc
mg system-replace vc 2>"$w/err" || fail "setup: system-replace vc must succeed: $(cat "$w/err")"
echo admin-vc >> "$V/etc/vc_config"
hook vc post-system-restore "if [ ! -e '$w/vc.changed' ]; then touch '$w/vc.changed'; echo late-vc >> \"\$MAVERGREEN_ROOT/usr/local/mavergreen/var/vc/vc_config\"; fi"
cp "$V/etc/vc_config" "$w/vc.expect"; echo late-vc >> "$w/vc.expect"
rc=0; PATH="$stub:$PATH" mg uninstall vc 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "uninstall stops when the var file no longer holds what it planned to save"
grep -qF /usr/local/mavergreen/var/vc/vc_config "$w/err" || fail "that stop names the var file: $(cat "$w/err")"
is_copy "$T/var/vc/vc_config" "$w/vc.expect" && [ -d "$T/vc" ] && gone "$V/etc/vc_config.mavergreen-save" \
  || fail "uninstall never removes a var file it has not saved and checked"
PATH="$stub:$PATH" mg uninstall vc 2>"$w/err" || fail "the rerun must succeed: $(cat "$w/err")"
is_copy "$V/etc/vc_config.mavergreen-save" "$w/vc.expect" && gone "$T/vc" || fail "the rerun saves what the var file holds now"

mkadopt wc /etc/wc_config=wc_config:config
seeded wc wc_config default-wc
mg system-replace wc 2>"$w/err" || fail "setup: system-replace wc must succeed: $(cat "$w/err")"
echo admin-wc >> "$V/etc/wc_config"; cp "$V/etc/wc_config" "$w/wc.expect"
hook wc post-system-restore "echo someone-else > \"\$MAVERGREEN_ROOT/etc/wc_config.mavergreen-save\""
PATH="$stub:$PATH" mg uninstall wc 2>"$w/err" || fail "uninstall overwrites a save that appeared after it planned its own (R34): $(cat "$w/err")"
is_copy "$V/etc/wc_config.mavergreen-save" "$w/wc.expect" && gone "$T/wc" && gone "$T/var/wc" \
  || fail "the config uninstall keeps replaces a save that appeared, and uninstall finishes (R34)"

mkadopt wd /etc/wd_config=wd_config:config
seeded wd wd_config default-wd
mg system-replace wd 2>"$w/err" || fail "setup: system-replace wd must succeed: $(cat "$w/err")"
echo admin-wd >> "$V/etc/wd_config"; cp "$V/etc/wd_config" "$w/wd.expect"
hook wd post-system-restore "mkdir -p \"\$MAVERGREEN_ROOT/etc/wd_config.mavergreen-save\""
rc=0; PATH="$stub:$PATH" mg uninstall wd 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "uninstall stops when a directory appears where it would keep the config"
grep -qF /etc/wd_config.mavergreen-save "$w/err" || fail "that stop names the save path: $(cat "$w/err")"
is_copy "$T/var/wd/wd_config" "$w/wd.expect" && [ -d "$T/wd" ] && gone "$V/etc/wd_config.mavergreen-save/.wd_config.mavergreen-save.mavergreen-tmp" \
  || fail "uninstall never moves the save into a directory, and keeps the var file"

mkadopt cj /etc/cj_config=cj_config:config
seeded cj cj_config default-cj
mg system-replace cj 2>"$w/err" || fail "setup: system-replace cj must succeed: $(cat "$w/err")"
echo admin-cj >> "$V/etc/cj_config"; cp "$V/etc/cj_config" "$w/cj.expect"
mkdir -p "$w/cpjunk"
printf '#!/bin/sh\nfor a; do last="$a"; done\ncase "$last" in *.mavergreen-save.mavergreen-tmp) echo junk > "$last"; exit 0 ;; esac\nexec /bin/cp "$@"\n' > "$w/cpjunk/cp"
chmod +x "$w/cpjunk/cp"
rc=0; (PATH="$w/cpjunk:$stub:$PATH" mg uninstall cj 2>"$w/err") || rc=$?
[ "$rc" -ne 0 ] || fail "uninstall stops when the save it wrote does not hold the config"
gone "$V/etc/cj_config.mavergreen-save" && gone "$V/etc/.cj_config.mavergreen-save.mavergreen-tmp" \
  && is_copy "$T/var/cj/cj_config" "$w/cj.expect" && [ -d "$T/cj" ] \
  || fail "a save that fails its check is never put in place, and the var file is kept"
PATH="$stub:$PATH" mg uninstall cj 2>"$w/err" || fail "the rerun must succeed: $(cat "$w/err")"
is_copy "$V/etc/cj_config.mavergreen-save" "$w/cj.expect" && gone "$T/cj" || fail "the rerun keeps the admin's config"

mkproduct hookgood hookgood "" bin/hookgood
mkdir -p "$T/hookgood/libexec/mavergreen"
mkdir -p "$T/var/hookgood"; touch "$T/var/hookgood/state"
cat > "$T/hookgood/libexec/mavergreen/pre-uninstall" <<EOF
#!/bin/sh
[ -d "\$MAVERGREEN_ROOT/usr/local/mavergreen/\$MAVERGREEN_PRODUCT" ] || exit 9
[ -f "\$MAVERGREEN_ROOT/usr/local/mavergreen/var/\$MAVERGREEN_PRODUCT/state" ] || exit 9
printf '%s %s\n' "\$MAVERGREEN_ROOT" "\$MAVERGREEN_PRODUCT" >> "$w/hook.log"
exit 0
EOF
chmod +x "$T/hookgood/libexec/mavergreen/pre-uninstall"
: > "$w/hook.log"
PATH="$stub:$PATH" mg uninstall hookgood || fail "uninstall must succeed when its pre-uninstall hook exits 0"
[ ! -e "$T/hookgood" ] && [ ! -e "$T/var/hookgood" ] \
  || fail "uninstall still removes the tree and var/ after a successful hook"
grep -qxF "$V hookgood" "$w/hook.log" \
  || fail "the hook must run first, on the target volume, with MAVERGREEN_ROOT/MAVERGREEN_PRODUCT set and the tree/var still visible: $(cat "$w/hook.log")"

mkproduct hookfail hookfail "" bin/hookfail
mg link hookfail || fail "setup: link hookfail"
mkdir -p "$T/hookfail/libexec/mavergreen" "$V/Applications/HookFail.app/Contents" "$T/var/hookfail"
touch "$T/var/hookfail/state"
"$PB" -c "Add :outside array" -c "Add :outside:0 string Applications/HookFail.app" "$T/hookfail/mavergreen.plist" >/dev/null
printf '#!/bin/sh\nexit 1\n' > "$T/hookfail/libexec/mavergreen/pre-uninstall"
chmod +x "$T/hookfail/libexec/mavergreen/pre-uninstall"
: > "$w/calls"
rc=0; PATH="$stub:$PATH" mg uninstall hookfail 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "uninstall must fail when its pre-uninstall hook exits non-zero"
grep -qF "$T/hookfail/libexec/mavergreen/pre-uninstall" "$w/err" \
  || fail "the failure message must name the hook's path: $(cat "$w/err")"
[ -d "$T/hookfail" ] || fail "a failing pre-uninstall hook must leave the product's tree in place"
[ -d "$T/var/hookfail" ] && [ -f "$T/var/hookfail/state" ] \
  || fail "a failing pre-uninstall hook must leave the product's var/ in place"
[ -L "$T/bin/hookfail" ] || fail "a failing pre-uninstall hook must leave the product's farm links in place"
[ -d "$V/Applications/HookFail.app" ] || fail "a failing pre-uninstall hook must leave outside entries in place"
[ "$(mg select hookfail)" = hookfail ] || fail "a failing pre-uninstall hook must leave the selection alone"
grep -q 'forget dev.mavergreen.hookfail' "$w/calls" \
  && fail "a failing pre-uninstall hook must leave the receipt in place: $(cat "$w/calls")"

mkproduct hookcancel hookcancel "" bin/hookcancel
mkdir -p "$T/hookcancel/libexec/mavergreen"
printf '#!/bin/sh\nexit 130\n' > "$T/hookcancel/libexec/mavergreen/pre-uninstall"
chmod +x "$T/hookcancel/libexec/mavergreen/pre-uninstall"
rc=0; PATH="$stub:$PATH" mg uninstall hookcancel 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "uninstall must fail when its pre-uninstall hook exits above 128"
grep -qi cancelled "$w/err" || fail "a pre-uninstall hook exiting above 128 must be reported as cancelled, not failed: $(cat "$w/err")"
grep -qF "$T/hookcancel/libexec/mavergreen/pre-uninstall" "$w/err" \
  || fail "the cancellation message must name the hook's path: $(cat "$w/err")"
[ -d "$T/hookcancel" ] || fail "a cancelled pre-uninstall hook must remove nothing"

mkproduct hooknonexec hooknonexec "" bin/hooknonexec
mkdir -p "$T/hooknonexec/libexec/mavergreen"
: > "$T/hooknonexec/libexec/mavergreen/pre-uninstall"
rc=0; PATH="$stub:$PATH" mg uninstall hooknonexec 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "a non-executable pre-uninstall hook must fail uninstall"
grep -q 'not executable' "$w/err" || fail "the refusal must say the hook is not executable: $(cat "$w/err")"
[ -d "$T/hooknonexec" ] || fail "a non-executable pre-uninstall hook must remove nothing"

mkproduct hooklink hooklink "" bin/hooklink
mkdir -p "$T/hooklink/libexec/mavergreen" "$w/outside-hook"
printf '#!/bin/sh\ntouch "%s/ran"\nexit 0\n' "$w/outside-hook" > "$w/outside-hook/real"
chmod +x "$w/outside-hook/real"
ln -s "$w/outside-hook/real" "$T/hooklink/libexec/mavergreen/pre-uninstall"
rc=0; PATH="$stub:$PATH" mg uninstall hooklink 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "a symlinked pre-uninstall hook must be refused, whatever it points at"
grep -qF "$T/hooklink/libexec/mavergreen/pre-uninstall" "$w/err" \
  || fail "the refusal must name the symlinked hook's path: $(cat "$w/err")"
[ ! -e "$w/outside-hook/ran" ] || fail "a refused symlinked pre-uninstall hook's target must never run"
[ -d "$T/hooklink" ] || fail "a refused symlinked pre-uninstall hook must remove nothing"

mkproduct hookbeforerestore hookbeforerestore "" bin/hookbr
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/hookbr string bin/hookbr" "$T/hookbeforerestore/mavergreen.plist"
echo apple-hookbr > "$V/usr/bin/hookbr"
mg system-replace hookbeforerestore || fail "setup: system-replace hookbeforerestore must succeed"
mkdir -p "$T/hookbeforerestore/libexec/mavergreen"
printf '#!/bin/sh\nexit 1\n' > "$T/hookbeforerestore/libexec/mavergreen/pre-uninstall"
chmod +x "$T/hookbeforerestore/libexec/mavergreen/pre-uninstall"
rc=0; PATH="$stub:$PATH" mg uninstall hookbeforerestore 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "a failing pre-uninstall hook must fail uninstall even for a product with replaced system files"
is_copy "$V/usr/bin/hookbr" "$T/hookbeforerestore/bin/hookbr" \
  || fail "a failing pre-uninstall hook must run before system-restore -- the replaced system path must still be our copy"
[ -f "$T/var/system-replace/hookbeforerestore/usr/bin/hookbr" ] \
  || fail "a failing pre-uninstall hook must run before system-restore -- the saved original must still be waiting, untouched"
grep -qF "$T/hookbeforerestore/libexec/mavergreen/pre-uninstall" "$w/err" \
  || fail "the failure message must name the hook: $(cat "$w/err")"

mkproduct hookescape hookescape "" bin/hookescape
mkdir -p "$w/beyond-hook"
printf '#!/bin/sh\nexit 0\n' > "$w/beyond-hook/pre-uninstall"
chmod +x "$w/beyond-hook/pre-uninstall"
mkdir -p "$T/hookescape/libexec"
ln -s "$w/beyond-hook" "$T/hookescape/libexec/mavergreen"
rc=0; PATH="$stub:$PATH" mg uninstall hookescape 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "a pre-uninstall hook whose parent directory resolves outside the volume must fail uninstall"
grep -q 'pre-uninstall' "$w/err" || fail "the refusal must name the hook: $(cat "$w/err")"
[ -d "$T/hookescape" ] || fail "an escaping pre-uninstall hook's parent must not let uninstall remove anything"

aplist() { "$PB" -c "Print :$2" "$SR/$1/applied.plist" 2>/dev/null; }
probe="$w/probe"; mkdir -p "$probe"
for _t in mv rm ln cp; do
  printf '#!/bin/sh\n[ -f "$PROBE" ] && [ ! -L "$PROBE" ] || echo "$PROBE was absent before %s $*" >> "$PROBE_LOG"\nexec /bin/%s "$@"\n' "$_t" "$_t" > "$probe/$_t"
  chmod +x "$probe/$_t"
done
nth="$w/nth"; mkdir -p "$nth"
cat > "$nth/mv" <<'STUB'
#!/bin/sh
for a; do last="$a"; done
case "$last" in */"$MVN_SUFFIX")
  n=$(( $(cat "$MVN_COUNT" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$MVN_COUNT"
  [ "$n" -ne "$MVN_NTH" ] || exit 1 ;;
esac
exec /bin/mv "$@"
STUB
chmod +x "$nth/mv"

mkproduct ua ua "" bin/ua1 bin/ua2
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/ua1 string bin/ua1" "$T/ua/mavergreen.plist"
echo apple-ua1 > "$V/usr/bin/ua1"; echo apple-ua2 > "$V/usr/bin/ua2"
mg system-replace ua || fail "setup: system-replace ua must succeed"
ino="$(stat -f %i "$V/usr/bin/ua1")"
"$PB" -c "Add :replaces:/usr/bin/ua2 string bin/ua2" -c "Add :adopts dict" -c "Add :adopts:/etc/ua_config dict" \
      -c "Add :adopts:/etc/ua_config:path string ua_config" -c "Add :adopts:/etc/ua_config:kind string config" "$T/ua/mavergreen.plist"
seeded ua ua_config default-ua
hook ua pre-system-replace "ls \"\$MAVERGREEN_STAGING\" > '$w/ua.staged'"
hook ua post-system-replace "touch '$w/ua.post'"
mkdir -p "$V/opt/uaw"; chmod 777 "$V/opt/uaw"; echo apple-ua3 > "$V/opt/uaw/ua3"
"$PB" -c "Add :replaces:/opt/uaw/ua3 string bin/ua2" "$T/ua/mavergreen.plist"
echo ua1-v2 > "$T/ua/bin/ua1"
mg system-replace ua 2>"$w/err" && fail "an upgrade must refuse a new entry that fails the ownership precondition"
grep -q "opt/uaw is not root-only" "$w/err" || fail "that refusal names the offending directory: $(cat "$w/err")"
[ "$(cat "$V/usr/bin/ua1")" = ua ] && [ "$(stat -f %i "$V/usr/bin/ua1")" = "$ino" ] && holds "$V/usr/bin/ua2" apple-ua2 \
  && holds "$V/opt/uaw/ua3" apple-ua3 && gone "$V/etc/ua_config" && holds "$T/var/ua/ua_config" default-ua && gone "$w/ua.staged" \
  || fail "a refused upgrade changes nothing: no copy refreshed, no new entry applied, no hook run"
aplist ua replaces:/usr/bin/ua2 >/dev/null && fail "a refused upgrade leaves applied.plist as it was"
"$PB" -c "Delete :replaces:/opt/uaw/ua3" "$T/ua/mavergreen.plist"; rm -rf "$V/opt/uaw"
echo ua > "$T/ua/bin/ua1"
mg system-replace ua 2>"$w/err" || fail "an upgrade that adds entries must succeed: $(cat "$w/err")"
is_copy "$V/usr/bin/ua2" "$T/ua/bin/ua2" && holds "$SR/ua/usr/bin/ua2" apple-ua2 \
  || fail "an upgrade applies a newly declared replaces entry and saves its original"
holds "$V/etc/ua_config" default-ua && links ua ua_config /etc/ua_config || fail "an upgrade applies a newly declared adopts entry"
[ "$(cat "$w/ua.staged" 2>/dev/null)" = ua_config ] || fail "an upgrade runs the pre-system-replace hook with the new entry staged"
[ -f "$w/ua.post" ] || fail "an upgrade runs the post-system-replace hook"
[ "$(stat -f %i "$V/usr/bin/ua1")" = "$ino" ] || fail "an upgrade leaves an unchanged entry alone"
[ "$(aplist ua replaces:/usr/bin/ua2)" = bin/ua2 ] && [ "$(aplist ua adopts:/etc/ua_config:kind)" = config ] \
  && [ "$(aplist ua originals:/usr/bin/ua2)" = "$(sha "$SR/ua/usr/bin/ua2")" ] || fail "applied.plist records the new entries"
mg system-restore ua || fail "setup: system-restore ua must succeed"
holds "$V/usr/bin/ua1" apple-ua1 && holds "$V/usr/bin/ua2" apple-ua2 && gone "$V/etc/ua_config" || fail "setup: ua restored"

mkproduct ud ud "" bin/ud1 bin/ud2 bin/udk share/man/man1/ud.1
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/ud1 string bin/ud1" -c "Add :replaces:/usr/bin/ud2 string bin/ud2" \
      -c "Add :replaces:/usr/bin/udk string bin/udk" -c "Add :replaces:/usr/share/man/man1/ud.1 string share/man/man1/ud.1" \
      -c "Add :adopts dict" -c "Add :adopts:/etc/ud_config dict" -c "Add :adopts:/etc/ud_config:path string ud_config" \
      -c "Add :adopts:/etc/ud_config:kind string config" "$T/ud/mavergreen.plist"
echo apple-ud1 > "$V/usr/bin/ud1"; echo apple-man-ud > "$V/usr/share/man/man1/ud.1"; echo apple-ud > "$V/etc/ud_config"
receipt "$V" ud ./etc/ud_config "$V/etc/ud_config"; seeded ud ud_config default-ud
mg system-replace ud 2>"$w/err" || fail "setup: system-replace ud must succeed: $(cat "$w/err")"
echo admin-ud >> "$V/etc/ud_config"
for k in /usr/bin/ud1 /usr/bin/ud2 /usr/share/man/man1/ud.1; do "$PB" -c "Delete :replaces:$k" "$T/ud/mavergreen.plist"; done
"$PB" -c "Delete :adopts:/etc/ud_config" "$T/ud/mavergreen.plist"
mg system-replace ud >"$w/out" 2>"$w/err" || fail "an upgrade that drops entries must succeed: $(cat "$w/err")"
holds "$V/usr/bin/ud1" apple-ud1 || fail "an upgrade puts back the original of a copy it no longer declares"
gone "$V/usr/bin/ud2" || fail "an upgrade removes a copy it no longer declares that had no original"
holds "$V/usr/share/man/man1/ud.1" apple-man-ud || fail "an upgrade puts back a man page's original over the link it no longer declares"
holds "$V/etc/ud_config" apple-ud && holds "$T/var/ud/ud_config" "$(printf 'default-ud\nadmin-ud')" \
  || fail "an upgrade restores an adoption it no longer declares: the original goes back, the live config back to var"
grep -qF "settings in /etc/ud_config that the restored original does not have" "$w/out" && grep -qx '+admin-ud' "$w/out" \
  || fail "restoring a dropped config entry prints the restore report: $(cat "$w/out")"
is_copy "$V/usr/bin/udk" "$T/ud/bin/udk" && [ -f "$SR/ud/.replaced" ] || fail "an entry still declared stays replaced"
for k in replaces:/usr/bin/ud1 replaces:/usr/bin/ud2 replaces:/usr/share/man/man1/ud.1 adopts:/etc/ud_config \
         copies:/usr/bin/ud1 copies:/usr/share/man/man1/ud.1 copies:/etc/ud_config originals:/usr/bin/ud1 originals:/etc/ud_config \
         originals:/usr/local/mavergreen/var/ud/ud_config; do
  aplist ud "$k" >/dev/null && fail "applied.plist drops $k once the upgrade has restored it"
done
[ "$(aplist ud replaces:/usr/bin/udk)" = bin/udk ] || fail "applied.plist keeps the entry still declared"
gone "$SR/ud/usr/bin/ud1" && gone "$SR/ud/etc/ud_config" && gone "$SR/ud/usr/share/man/man1/ud.1" \
  || fail "originals put back leave the save area"
mg system-restore ud || fail "setup: system-restore ud must succeed"
gone "$V/usr/bin/udk" && gone "$SR/ud/applied.plist" || fail "setup: ud restored"

mkproduct ux ux "" bin/ux1 bin/ux2 bin/ux3
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/ux1 string bin/ux1" -c "Add :replaces:/usr/bin/ux2 string bin/ux2" \
      "$T/ux/mavergreen.plist"
echo apple-ux1 > "$V/usr/bin/ux1"; echo apple-ux2 > "$V/usr/bin/ux2"; echo apple-ux3 > "$V/usr/bin/ux3"
mg system-replace ux || fail "setup: system-replace ux must succeed"
old="$(sha "$V/usr/bin/ux2")"
echo tampered >> "$V/usr/bin/ux1"; echo ux2-v2 > "$T/ux/bin/ux2"
"$PB" -c "Delete :replaces:/usr/bin/ux1" -c "Add :replaces:/usr/bin/ux3 string bin/ux3" "$T/ux/mavergreen.plist"
rc=0; mg system-replace ux 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "an upgrade must fail when an entry it no longer declares cannot be restored (R18)"
grep -qF "/usr/bin/ux1 was changed after mavergreen installed it; keeping the saved original" "$w/err" \
  || fail "that failure gives restore's own reason: $(cat "$w/err")"
[ "$(tail -n 1 "$V/usr/bin/ux1")" = tampered ] && holds "$SR/ux/usr/bin/ux1" apple-ux1 && [ "$(sha "$V/usr/bin/ux2")" = "$old" ] \
  && holds "$V/usr/bin/ux3" apple-ux3 && gone "$SR/ux/usr/bin/ux3" && [ "$(aplist ux replaces:/usr/bin/ux1)" = bin/ux1 ] \
  || fail "that refusal comes before any change: the dropped entry, the changed copy and the new entry are all as they were"
cp -p "$T/ux/bin/ux1" "$V/usr/bin/ux1"
mg system-replace ux 2>"$w/err" || fail "the upgrade succeeds once the dropped copy is ours again: $(cat "$w/err")"
holds "$V/usr/bin/ux1" apple-ux1 && is_copy "$V/usr/bin/ux2" "$T/ux/bin/ux2" && is_copy "$V/usr/bin/ux3" "$T/ux/bin/ux3" \
  || fail "that upgrade restores the dropped entry, refreshes the changed copy and applies the new one"
mg system-restore ux || fail "setup: system-restore ux must succeed"

mkproduct ur ur "" bin/ur
chmod 755 "$T/ur/bin/ur"
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/ur string bin/ur" "$T/ur/mavergreen.plist"
echo apple-ur > "$V/usr/bin/ur"
mg system-replace ur || fail "setup: system-replace ur must succeed"
ino="$(stat -f %i "$SR/ur/usr/bin/ur")"
echo ur-v2 > "$T/ur/bin/ur"; chmod 4755 "$T/ur/bin/ur"
: > "$w/probe.log"
(PATH="$probe:$PATH" PROBE="$V/usr/bin/ur" PROBE_LOG="$w/probe.log" mg system-replace ur 2>"$w/err") \
  || fail "an upgrade whose tree file changed must succeed: $(cat "$w/err")"
[ ! -s "$w/probe.log" ] || fail "the system path is a real file throughout a refresh: $(cat "$w/probe.log")"
is_copy "$V/usr/bin/ur" "$T/ur/bin/ur" && [ "$(stat -f %Mp%Lp "$V/usr/bin/ur")" = 4755 ] \
  || fail "a changed tree file refreshes the copy, mode included"
holds "$SR/ur/usr/bin/ur" apple-ur && [ "$(stat -f %i "$SR/ur/usr/bin/ur")" = "$ino" ] || fail "a refresh leaves the saved original untouched"
[ "$(aplist ur copies:/usr/bin/ur)" = "$(sha "$T/ur/bin/ur")" ] || fail "a refresh records the new copy's sha256"
aplist ur refreshing:/usr/bin/ur >/dev/null && fail "a finished refresh leaves no refreshing record"
mg check 2>"$w/err" || true
if grep -q 'usr/bin/ur ' "$w/err"; then fail "check reports nothing after a refresh: $(cat "$w/err")"; fi
mg system-restore ur || fail "setup: system-restore ur must succeed"
holds "$V/usr/bin/ur" apple-ur || fail "restore after a refresh puts the original back"

mkproduct ui ui "" bin/ui1 bin/ui2
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/ui1 string bin/ui1" -c "Add :replaces:/usr/bin/ui2 string bin/ui2" "$T/ui/mavergreen.plist"
echo apple-ui1 > "$V/usr/bin/ui1"
uiv() { echo "ui1-$1" > "$T/ui/bin/ui1"; echo "ui2-$1" > "$T/ui/bin/ui2"; }
uirefresh() {  # $1 version that is in place  $2 the next one  $3.. how the refresh is killed
  uiv "$1"; mg system-replace ui 2>"$w/err" || fail "setup: system-replace ui at $1 must succeed: $(cat "$w/err")"
  o1="$(sha "$V/usr/bin/ui1")"; o2="$(sha "$V/usr/bin/ui2")"; uiv "$2"; rm -f "$w/mvn"
  (PATH="$3:$PATH"; export PATH; for _a in $4; do export "$_a"; done; mg system-replace ui 2>"$w/err") && fail "setup: a refresh killed midway must fail"
  [ "$(aplist ui refreshing:/usr/bin/ui2)" = "$o2" ] && [ "$(aplist ui copies:/usr/bin/ui2)" = "$(sha "$T/ui/bin/ui2")" ] \
    || fail "a refresh records the copy it replaces and the one it installs before swapping (R36)"
  [ "$(sha "$V/usr/bin/ui2")" = "$o2" ] || fail "setup: the second copy is not refreshed yet"
}
uirefresh v1 v2 "$mvstub" MV_FAIL=usr/bin/ui1
[ "$(sha "$V/usr/bin/ui1")" = "$o1" ] && [ "$(aplist ui refreshing:/usr/bin/ui1)" = "$o1" ] || fail "setup: killed between the record and the swap"
mg check 2>"$w/err" || true
grep -qF "/usr/bin/ui1 is stale" "$w/err" && ! grep -q "ui1 is no longer" "$w/err" \
  || fail "check calls a copy whose refresh was interrupted stale, not foreign: $(cat "$w/err")"
mg system-restore ui 2>"$w/err" || fail "restore must work after a refresh killed before its swap (R36): $(cat "$w/err")"
holds "$V/usr/bin/ui1" apple-ui1 && gone "$V/usr/bin/ui2" && gone "$SR/ui" || fail "that restore puts back the original and removes the copy with none"
uirefresh v3 v4 "$mvstub" MV_FAIL=usr/bin/ui1
mg system-replace ui 2>"$w/err" || fail "a rerun must finish a refresh killed before its swap (R36): $(cat "$w/err")"
is_copy "$V/usr/bin/ui1" "$T/ui/bin/ui1" && is_copy "$V/usr/bin/ui2" "$T/ui/bin/ui2" && holds "$SR/ui/usr/bin/ui1" apple-ui1 \
  || fail "that rerun installs the new copies and keeps the saved original"
{ aplist ui refreshing:/usr/bin/ui1 || aplist ui refreshing:/usr/bin/ui2; } >/dev/null && fail "that rerun leaves no refreshing record"
uirefresh v4 v5 "$nth" "MVN_SUFFIX=applied.plist MVN_NTH=2 MVN_COUNT=$w/mvn"
is_copy "$V/usr/bin/ui1" "$T/ui/bin/ui1" && [ "$(aplist ui refreshing:/usr/bin/ui1)" = "$o1" ] \
  || fail "setup: killed after the first swap, before its refreshing record was dropped"
mg system-replace ui 2>"$w/err" || fail "a rerun must finish a refresh killed after its swap (R36): $(cat "$w/err")"
is_copy "$V/usr/bin/ui1" "$T/ui/bin/ui1" && is_copy "$V/usr/bin/ui2" "$T/ui/bin/ui2" && holds "$SR/ui/usr/bin/ui1" apple-ui1 \
  && ! aplist ui refreshing:/usr/bin/ui1 >/dev/null && ! aplist ui refreshing:/usr/bin/ui2 >/dev/null \
  || fail "that rerun finishes both copies and drops the refreshing records"
uirefresh v5 v6 "$nth" "MVN_SUFFIX=applied.plist MVN_NTH=2 MVN_COUNT=$w/mvn"
mg system-restore ui 2>"$w/err" || fail "restore must work after a refresh killed after its swap (R36): $(cat "$w/err")"
holds "$V/usr/bin/ui1" apple-ui1 && gone "$V/usr/bin/ui2" && gone "$SR/ui" || fail "that restore puts back the original and removes the copy with none"

mkadopt uf /etc/uf_config=uf_config:config
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/uf string bin/stub" "$T/uf/mavergreen.plist"
echo apple-uf > "$V/etc/uf_config"; receipt "$V" uf ./etc/uf_config "$V/etc/uf_config"; seeded uf uf_config default-uf
mg system-replace uf || fail "setup: system-replace uf must succeed"
echo tool-uf > "$w/uf"; mv "$w/uf" "$T/var/uf/uf_config"
old="$(sha "$V/usr/bin/uf")"; echo stub-v2 > "$T/uf/bin/stub"
mg system-replace uf 2>"$w/err" && fail "an upgrade must refuse when the var link was replaced by a different real file"
grep -qF /etc/uf_config "$w/err" && grep -qF /usr/local/mavergreen/var/uf/uf_config "$w/err" || fail "that refusal names both files: $(cat "$w/err")"
holds "$T/var/uf/uf_config" tool-uf && holds "$V/etc/uf_config" default-uf && [ "$(sha "$V/usr/bin/uf")" = "$old" ] \
  || fail "that refusal changes neither file, and refreshes no copy"
cp "$V/etc/uf_config" "$T/var/uf/uf_config"
mg system-restore uf || fail "setup: system-restore uf must succeed"

mkproduct uk uk "" bin/uk share/man/man1/uk.1
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/uk string bin/uk" \
      -c "Add :replaces:/usr/share/man/man1/uk.1 string share/man/man1/uk.1" "$T/uk/mavergreen.plist"
echo apple-uk > "$V/usr/bin/uk"; echo apple-man-uk > "$V/usr/share/man/man1/uk.1"
receipt "$V" uk ./usr/bin/uk "$V/usr/bin/uk"; receipt "$V" ukman ./usr/share/man/man1/uk.1 "$V/usr/share/man/man1/uk.1"
mg system-replace uk || fail "setup: system-replace uk must succeed"
ino="$(stat -f %i "$SR/uk/usr/bin/uk")"; mino="$(stat -f %i "$SR/uk/usr/share/man/man1/uk.1")"
rm "$V/usr/bin/uk" "$V/usr/share/man/man1/uk.1"
cp "$SR/uk/usr/bin/uk" "$V/usr/bin/uk"; cp "$SR/uk/usr/share/man/man1/uk.1" "$V/usr/share/man/man1/uk.1"
mg check 2>"$w/err" && fail "check must report an original Apple put back"
grep -qF "/usr/bin/uk is no longer uk's copy" "$w/err" || fail "check names it: $(cat "$w/err")"
mg system-replace uk 2>"$w/err" || fail "a rerun treats an Apple-stock file identical to its saved original as the original again (K.4): $(cat "$w/err")"
is_copy "$V/usr/bin/uk" "$T/uk/bin/uk" && [ "$(readlink "$V/usr/share/man/man1/uk.1")" = /usr/local/mavergreen/uk/share/man/man1/uk.1 ] \
  || fail "that rerun replaces the path again, program and man page"
holds "$SR/uk/usr/bin/uk" apple-uk && [ "$(stat -f %i "$SR/uk/usr/bin/uk")" = "$ino" ] \
  && holds "$SR/uk/usr/share/man/man1/uk.1" apple-man-uk && [ "$(stat -f %i "$SR/uk/usr/share/man/man1/uk.1")" = "$mino" ] \
  || fail "that rerun keeps the saved originals"
mg system-restore uk || fail "setup: system-restore uk must succeed"
holds "$V/usr/bin/uk" apple-uk && holds "$V/usr/share/man/man1/uk.1" apple-man-uk || fail "setup: uk restored"

mkproduct un un "" bin/un
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/un string bin/un" "$T/un/mavergreen.plist"
echo apple-un > "$V/usr/bin/un"
mg system-replace un || fail "setup: system-replace un must succeed"
rm "$V/usr/bin/un"; cp "$SR/un/usr/bin/un" "$V/usr/bin/un"; ino="$(stat -f %i "$V/usr/bin/un")"
mg system-replace un 2>"$w/err" && fail "a file identical to the saved original but in no Apple receipt is not taken for the original (K.4)"
grep -qF "/usr/bin/un was already saved once and has since changed" "$w/err" || fail "that refusal says so: $(cat "$w/err")"
holds "$V/usr/bin/un" apple-un && [ "$(stat -f %i "$V/usr/bin/un")" = "$ino" ] && holds "$SR/un/usr/bin/un" apple-un \
  || fail "that refusal changes nothing"
rc=0; mg system-restore un 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] && grep -qF "/usr/bin/un was changed after mavergreen installed it" "$w/err" && holds "$SR/un/usr/bin/un" apple-un \
  || fail "restore keeps the saved original of a file identical to it but in no Apple receipt (R39): $(cat "$w/err")"
rm "$V/usr/bin/un"; cp -p "$T/un/bin/un" "$V/usr/bin/un"
mg system-restore un || fail "setup: system-restore un must succeed"

mkproduct us us "" bin/us
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/us string bin/us" "$T/us/mavergreen.plist"
echo apple-us > "$V/usr/bin/us"; receipt "$V" us0 ./usr/bin/us "$V/usr/bin/us"
mg system-replace us || fail "setup: system-replace us must succeed"
rm "$V/usr/bin/us"; echo apple-us-update > "$V/usr/bin/us"; receipt "$V" us ./usr/bin/us "$V/usr/bin/us"
mg system-replace us 2>"$w/err" && fail "an Apple-stock file that differs from the saved original is not taken for the original (K.4)"
grep -qF "/usr/bin/us was already saved once and has since changed" "$w/err" || fail "that refusal says so: $(cat "$w/err")"
holds "$V/usr/bin/us" apple-us-update && holds "$SR/us/usr/bin/us" apple-us || fail "that refusal changes nothing"
grep -qF "run system-restore us first" "$w/err" || fail "that refusal points at system-restore, which now resolves it (R65): $(cat "$w/err")"
rc=0; mg system-restore us >"$w/out" 2>"$w/err" || rc=$?
[ "$rc" -eq 0 ] || fail "restore succeeds when Apple has put a different stock file at the path, since Apple owns it again (R65): $(cat "$w/err")"
holds "$V/usr/bin/us" apple-us-update && gone "$SR/us/usr/bin/us" && gone "$SR/us/applied.plist" && gone "$V/usr/bin/us.mavergreen-save" && gone "$T/kept/us" \
  || fail "that restore leaves Apple's file in place and discards the saved original, which was Apple's too (R65)"
grep -qF "mavergreen: /usr/bin/us is Apple's own file again" "$w/out" || fail "that restore says what it left, on stdout (R65): $(cat "$w/out")"
mg system-replace us || fail "setup: system-replace us again must succeed"
rm "$V/usr/bin/us"; echo apple-us-update2 > "$V/usr/bin/us"; receipt "$V" us2 ./usr/bin/us "$V/usr/bin/us"
rc=0; PATH="$stub:$PATH" mg uninstall us >"$w/out" 2>"$w/err" || rc=$?
[ "$rc" -eq 0 ] || fail "uninstall succeeds when Apple has put a different stock file at the path (R65): $(cat "$w/err")"
holds "$V/usr/bin/us" apple-us-update2 && gone "$T/us" && gone "$SR/us" || fail "that uninstall leaves Apple's file and removes the product"

mkadopt pr /etc/pr_config=pr_config:config
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/pr string bin/stub" "$T/pr/mavergreen.plist"
echo apple-pr > "$V/usr/bin/pr"; echo apple-prc > "$V/etc/pr_config"; receipt "$V" pr ./private/etc/pr_config "$V/etc/pr_config"
mkdir -p "$T/var/pr"; echo modern-pr > "$T/var/pr/pr_config"
mg system-replace pr 2>"$w/err" || fail "setup: system-replace pr must succeed: $(cat "$w/err")"
rm "$T/var/pr/pr_config"; echo split-pr > "$T/var/pr/pr_config"; echo edited-at-etc > "$V/etc/pr_config"
cp "$SR/pr/applied.plist" "$w/pr.applied"
rc=0; mg system-restore pr >"$w/out" 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "system-restore must refuse when an adopted config cannot go back (R64)"
grep -qF "/etc/pr_config was changed after mavergreen adopted it" "$w/err" || fail "that refusal gives restore's own reason: $(cat "$w/err")"
is_copy "$V/usr/bin/pr" "$T/pr/bin/stub" \
  || fail "a restore that refuses one entry changes nothing: the program is still the product's copy, so Apple's old binary never reads the modern config (R64)"
holds "$V/etc/pr_config" edited-at-etc && holds "$T/var/pr/pr_config" split-pr && holds "$SR/pr/usr/bin/pr" apple-pr \
  && holds "$SR/pr/etc/pr_config" apple-prc && cmp -s "$SR/pr/applied.plist" "$w/pr.applied" && [ -f "$SR/pr/.replaced" ] \
  || fail "that refusal leaves every file, saved original and record as it was (R64)"
hook pr pre-uninstall "touch '$w/pr.ran'"
rc=0; PATH="$stub:$PATH" mg uninstall pr 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "uninstall must refuse when its restore would refuse an entry (R64)"
grep -qF "/etc/pr_config was changed after mavergreen adopted it" "$w/err" || fail "that refusal gives restore's own reason: $(cat "$w/err")"
gone "$w/pr.ran" || fail "uninstall refuses before its pre-uninstall hook runs (R64)"
is_copy "$V/usr/bin/pr" "$T/pr/bin/stub" && [ -d "$T/pr" ] && cmp -s "$SR/pr/applied.plist" "$w/pr.applied" \
  || fail "that uninstall changes nothing (R64)"
rm "$T/pr/libexec/mavergreen/pre-uninstall"; cp "$V/etc/pr_config" "$T/var/pr/pr_config"
mg system-restore pr >/dev/null 2>"$w/err" || fail "restore succeeds once var holds the live config: $(cat "$w/err")"
holds "$V/usr/bin/pr" apple-pr && holds "$V/etc/pr_config" apple-prc && holds "$T/var/pr/pr_config" edited-at-etc \
  || fail "that restore puts every original back"

mkadopt ao /etc/ao_config=ao_config:config
echo apple-ao > "$V/etc/ao_config"; receipt "$V" ao ./etc/ao_config "$V/etc/ao_config"; seeded ao ao_config default-ao
mg system-replace ao 2>"$w/err" || fail "setup: system-replace ao must succeed: $(cat "$w/err")"
echo admin-ao >> "$V/etc/ao_config"
rm "$V/etc/ao_config"; echo apple-ao-2 > "$V/etc/ao_config"; receipt "$V" ao2 ./private/etc/ao_config "$V/etc/ao_config"
rc=0; mg system-restore ao >"$w/out" 2>"$w/err" || rc=$?
[ "$rc" -eq 0 ] || fail "restore succeeds when Apple has put its own stock config at an adopted path (R65): $(cat "$w/err")"
holds "$V/etc/ao_config" apple-ao-2 && holds "$T/var/ao/ao_config" apple-ao-2 && gone "$SR/ao/etc/ao_config" && gone "$SR/ao/applied.plist" \
  || fail "that restore leaves Apple's file, makes the var link a real file holding what the product read through it, and discards the saved original (R65)"
grep -qF "mavergreen: /etc/ao_config is Apple's own file again" "$w/out" || fail "that restore says what it left (R65): $(cat "$w/out")"
mg system-replace ao 2>"$w/err" || fail "a replace after that restore round-trips without refusing: $(cat "$w/err")"
mg system-restore ao >/dev/null || fail "setup: system-restore ao must succeed"

mkadopt aw /etc/aw_config=aw_config:config
echo apple-aw > "$V/etc/aw_config"; receipt "$V" aw ./etc/aw_config "$V/etc/aw_config"; seeded aw aw_config default-aw
mg system-replace aw 2>"$w/err" || fail "setup: system-replace aw must succeed: $(cat "$w/err")"
rm "$T/var/aw/aw_config"; echo tool-aw > "$T/var/aw/aw_config"
rm "$V/etc/aw_config"; echo apple-aw-2 > "$V/etc/aw_config"; receipt "$V" aw2 ./etc/aw_config "$V/etc/aw_config"
rc=0; PATH="$stub:$PATH" mg uninstall aw >"$w/out" 2>"$w/err" || rc=$?
[ "$rc" -eq 0 ] || fail "uninstall succeeds when Apple owns an adopted path again (R65): $(cat "$w/err")"
holds "$V/etc/aw_config" apple-aw-2 && holds "$V/etc/aw_config.mavergreen-save" tool-aw && gone "$T/aw" && gone "$SR/aw" \
  || fail "that uninstall leaves Apple's file and keeps the admin's var file as .mavergreen-save (R65)"

mkproduct ov ov "" bin/ov bin/ov2 share/man/man1/ov.1
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/ov string bin/ov" -c "Add :replaces:/usr/bin/ov2 string bin/ov2" \
      -c "Add :replaces:/usr/share/man/man1/ov.1 string share/man/man1/ov.1" -c "Add :adopts dict" -c "Add :adopts:/etc/ov_config dict" \
      -c "Add :adopts:/etc/ov_config:path string ov_config" -c "Add :adopts:/etc/ov_config:kind string config" "$T/ov/mavergreen.plist"
echo apple-ov > "$V/usr/bin/ov"; echo apple-ov2 > "$V/usr/bin/ov2"; echo apple-man-ov > "$V/usr/share/man/man1/ov.1"
echo admin-ov > "$V/etc/ov_config"; seeded ov ov_config default-ov
mg system-replace ov 2>"$w/err" || fail "setup: system-replace ov must succeed: $(cat "$w/err")"
cp "$T/ov/bin/ov2" "$w/ov2.copy"
"$PB" -c "Set :ProductVersion 10.11.6" "$V/System/Library/CoreServices/SystemVersion.plist"
rm "$V/usr/bin/ov"; echo apple-ov-1011 > "$V/usr/bin/ov"
rc=0; PATH="$stub:$PATH" mg uninstall ov >"$w/out" 2>"$w/err" || rc=$?
"$PB" -c "Set :ProductVersion 10.9.5" "$V/System/Library/CoreServices/SystemVersion.plist"
[ "$rc" -eq 0 ] || fail "uninstall succeeds after an OS upgrade past 10.9 rewrote a replaced program (R65): $(cat "$w/err")"
holds "$V/usr/bin/ov" apple-ov-1011 || fail "a program the OS upgrade rewrote is Apple's, and is left (R65)"
grep -qF "mavergreen: /usr/bin/ov is Apple's again (this volume is no longer Mac OS X 10.9)" "$w/out" || fail "that uninstall says so (R65): $(cat "$w/out")"
is_copy "$V/usr/bin/ov2" "$w/ov2.copy" && [ "$(readlink "$V/usr/share/man/man1/ov.1")" = /usr/local/mavergreen/ov/share/man/man1/ov.1 ] \
  || fail "off 10.9, restore never writes a system path: a copy or link still the product's is left (R65)"
grep -qF "mavergreen: /usr/bin/ov2 still holds ov's copy; this volume is no longer Mac OS X 10.9" "$w/out" \
  && grep -qF "mavergreen: /usr/share/man/man1/ov.1 still holds ov's copy" "$w/out" || fail "that uninstall names each path it left (R65): $(cat "$w/out")"
holds "$V/etc/ov_config" admin-ov && holds "$V/etc/ov_config.mavergreen-save" admin-ov \
  || fail "off 10.9 an adopted config stays where it is live, and uninstall still keeps the admin's settings (R65)"
gone "$T/ov" && gone "$T/var/ov" && gone "$SR/ov" || fail "that uninstall removes the product and its save area (R65)"
holds "$T/kept/ov/usr/bin/ov" apple-ov && holds "$T/kept/ov/usr/bin/ov2" apple-ov2 && holds "$T/kept/ov/usr/share/man/man1/ov.1" apple-man-ov \
  && holds "$T/kept/ov/etc/ov_config" admin-ov && gone "$V/usr/bin/ov.mavergreen-save" && gone "$V/usr/share/man/man1/ov.1.mavergreen-save" \
  || fail "off 10.9, an original no Apple receipt lists is kept in kept/<P>, never discarded and never written beside its path (R78)"
rm -f "$V/usr/bin/ov2" "$V/usr/share/man/man1/ov.1" "$V/etc/ov_config.mavergreen-save"

mkadopt mr /etc/mr_config=mr_config:config /etc/mr_k=mr_k:identity
seeded mr mr_config default-mr; echo key-mr > "$V/etc/mr_k"
mg system-replace mr 2>"$w/err" || fail "setup: system-replace mr must succeed: $(cat "$w/err")"
echo admin-mr >> "$V/etc/mr_config"; echo key-edit >> "$V/etc/mr_k"; cp "$V/etc/mr_config" "$w/mr.expect"
mg system-restore mr >/dev/null 2>"$w/err" || fail "setup: system-restore mr must succeed: $(cat "$w/err")"
rc=0; PATH="$stub:$PATH" mg uninstall mr >"$w/out" 2>"$w/err" || rc=$?
[ "$rc" -eq 0 ] || fail "uninstall after a manual system-restore must succeed: $(cat "$w/err")"
is_copy "$V/etc/mr_config.mavergreen-save" "$w/mr.expect" \
  || fail "uninstall after a manual system-restore keeps the config the admin changed while replaced (R69)"
grep -qF "mavergreen: /etc/mr_config.mavergreen-save keeps the settings mr used in /etc/mr_config" "$w/out" || fail "and says so (R69): $(cat "$w/out")"
gone "$V/etc/mr_k.mavergreen-save" && gone "$T/mr" && gone "$SR/mr" || fail "an identity entry is never saved, and uninstall finishes (R69)"
rm -f "$V/etc/mr_config.mavergreen-save"

mkadopt ue /etc/ue_config=ue_config:config
echo admin-ue > "$V/etc/ue_config"
(PATH="$mvstub:$PATH" MV_FAIL=var/ue/ue_config mg system-replace ue 2>"$w/err") && fail "setup: a replace whose var link fails must fail"
holds "$V/etc/ue_config" admin-ue && gone "$T/var/ue/ue_config" || fail "setup: the customized system file stays, var not yet linked"
seeded ue ue_config default-ue
mg system-replace ue 2>"$w/err" || fail "a rerun must link a var path the postinstall seeded with the product default meanwhile (R37): $(cat "$w/err")"
links ue ue_config /etc/ue_config && holds "$V/etc/ue_config" admin-ue && holds "$SR/ue/staging/ue_config" default-ue \
  || fail "that rerun sets the default aside in staging and links var to the system file"
mg system-restore ue || fail "setup: system-restore ue must succeed"

mkadopt ak /etc/ak1=ak1:config /etc/ak2=ak2:config
mkdir -p "$T/var/ak"; echo prod1 > "$T/var/ak/ak1"; echo prod2 > "$T/var/ak/ak2"
(PATH="$mvstub:$PATH" MV_FAIL=etc/ak2 mg system-replace ak 2>"$w/err") && fail "setup: a replace whose second adopted swap fails must fail"
[ "$(aplist ak originals:/etc/ak2)" = - ] && gone "$V/etc/ak2" && holds "$V/etc/ak1" prod1 \
  || fail "setup: the write-ahead recorded no original for /etc/ak2, and nothing is there yet"
mg system-replace ak 2>"$w/err" || fail "a rerun finishes an adoption stopped before its swap when the path had no original (R66): $(cat "$w/err")"
holds "$V/etc/ak1" prod1 && holds "$V/etc/ak2" prod2 && links ak ak1 /etc/ak1 && links ak ak2 /etc/ak2 \
  || fail "that rerun moves the product file in and links var to it, as a first run would (R66)"
mg system-restore ak 2>"$w/err" || fail "setup: system-restore ak must succeed: $(cat "$w/err")"
gone "$V/etc/ak1" && gone "$V/etc/ak2" && holds "$T/var/ak/ak2" prod2 || fail "setup: ak restored"

mkadopt po /etc/po_config=po_config:config
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/po string bin/stub" "$T/po/mavergreen.plist"
echo apple-po > "$V/usr/bin/po"; echo admin-po > "$V/etc/po_config"; seeded po po_config default-po
ino="$(stat -f %i "$V/etc/po_config")"
(PATH="$mvstub:$PATH" MV_FAIL=etc/po_config mg system-replace po 2>"$w/err") && fail "setup: a replace whose adopted swap fails must fail"
is_copy "$V/usr/bin/po" "$T/po/bin/stub" \
  || fail "programs are swapped before config, so a stop between them leaves the new program reading the old config, never Apple's old program reading the new one (R67)"
holds "$V/etc/po_config" admin-po && [ "$(stat -f %i "$V/etc/po_config")" = "$ino" ] && holds "$T/var/po/po_config" default-po \
  || fail "setup: the config is still the original, and var is not linked yet"
mg system-replace po 2>"$w/err" || fail "a rerun finishes a replace stopped between its programs and its config (R67): $(cat "$w/err")"
links po po_config /etc/po_config && holds "$V/etc/po_config" admin-po && is_copy "$V/usr/bin/po" "$T/po/bin/stub" \
  || fail "that rerun adopts the config and keeps the copy"
mg system-restore po 2>"$w/err" || fail "setup: system-restore po must succeed: $(cat "$w/err")"
holds "$V/usr/bin/po" apple-po && holds "$V/etc/po_config" admin-po || fail "setup: po restored"

mkproduct rz rz "" bin/rz
for k in /staging/rz /Applied.plist /.replaced /restored.sha256 /adopted.sha256.tmp; do
  rm -f "$T/rz/mavergreen.plist"; mkproduct rz rz "" bin/rz
  "$PB" -c "Add :replaces dict" -c "Add ':replaces:$k' string bin/rz" "$T/rz/mavergreen.plist"
  mg system-replace rz 2>"$w/err" && fail "a replaces key whose first component the save area keeps for itself must be refused: $k (R68)"
  grep -qF "rz declares an unsafe replaces entry: '$k'" "$w/err" || fail "that refusal names the entry: $(cat "$w/err")"
  gone "$SR/rz" && gone "$V$k" || fail "that refusal changes nothing: $k (R68)"
done
mkadopt rz /Staging/rz=rz:config
mg system-replace rz 2>"$w/err" && fail "an adopts key under /Staging, which HFS+ reads as the save area's staging/, must be refused (R68)"
grep -qF "rz declares an unsafe adopts entry: '/Staging/rz'" "$w/err" && gone "$SR/rz" || fail "that refusal names the entry and changes nothing: $(cat "$w/err")"
mkadopt rz /private/etc/rz_config=rz_config:config
"$PB" -c "Add :replaces dict" -c "Add :replaces:/etc/rz_config string bin/stub" "$T/rz/mavergreen.plist"
echo apple-rz > "$V/etc/rz_config"
mg system-replace rz 2>"$w/err" && fail "/etc/x in replaces and /private/etc/x in adopts are one path and must be refused (R68)"
grep -qF "rz declares /etc/rz_config more than once" "$w/err" && holds "$V/etc/rz_config" apple-rz && gone "$SR/rz" \
  || fail "that refusal names the path and changes nothing: $(cat "$w/err")"
mkadopt rz /etc/rz_a=rz_config:config /etc/rz_b=RZ_config:config
mg system-replace rz 2>"$w/err" && fail "two adopts entries whose var paths differ only in case are one file on HFS+ and must be refused (R68)"
grep -qF "rz declares two adopts entries at the var path" "$w/err" && gone "$SR/rz" || fail "that refusal names the var path: $(cat "$w/err")"
rm -rf "$T/rz" "$T/var/rz" "$V/etc/rz_config"

mkadopt rs7 /etc/rs7_config=rs7_config:config
echo apple-rs7 > "$V/etc/rs7_config"; receipt "$V" rs7 ./private/etc/rs7_config "$V/etc/rs7_config"
echo "admin-rs7 years of edits" > "$V/etc/rs7_config"; mkdir -p "$T/var/rs7"
mg system-replace rs7 2>"$w/err" || fail "setup: system-replace rs7 must succeed: $(cat "$w/err")"
rm "$V/etc/rs7_config"; echo apple-rs7 > "$V/etc/rs7_config"
(cd "$V/etc" && ls -a) > "$w/rs7.before"
rc=0; mg system-restore rs7 >"$w/out" 2>"$w/err" || rc=$?
[ "$rc" -eq 0 ] || fail "restore succeeds when Apple put its stock config back over a customized adopted one: $(cat "$w/err")"
holds "$V/etc/rs7_config" apple-rs7 && holds "$T/kept/rs7/etc/rs7_config" "admin-rs7 years of edits" && gone "$SR/rs7/etc/rs7_config" \
  || fail "a saved original no Apple receipt lists is the admin's, so restore moves it to kept/<P>/<path>, content intact (R78)"
(cd "$V/etc" && ls -a) > "$w/rs7.after"
cmp -s "$w/rs7.before" "$w/rs7.after" || fail "keeping the original writes nothing beside /etc/rs7_config (R78): $(diff "$w/rs7.before" "$w/rs7.after")"
grep -qF "kept as /usr/local/mavergreen/kept/rs7/etc/rs7_config" "$w/out" || fail "that restore names where it kept the original (R78): $(cat "$w/out")"
mg check 2>"$w/err" || true
if grep -q "/kept" "$w/err"; then fail "check ignores kept/ (R78): $(cat "$w/err")"; fi

mkadopt rs8 /etc/rs8_config=rs8_config:config
echo apple-rs8 > "$V/etc/rs8_config"; receipt "$V" rs8 ./private/etc/rs8_config "$V/etc/rs8_config"
echo "admin-rs8 years of edits" > "$V/etc/rs8_config"; mkdir -p "$T/var/rs8"
mg system-replace rs8 2>"$w/err" || fail "setup: system-replace rs8 must succeed: $(cat "$w/err")"
rm "$V/etc/rs8_config"; echo apple-rs8 > "$V/etc/rs8_config"; echo older-rs8 > "$V/etc/rs8_config.mavergreen-save"
rc=0; PATH="$stub:$PATH" mg uninstall rs8 >"$w/out" 2>"$w/err" || rc=$?
[ "$rc" -eq 0 ] && gone "$T/rs8" || fail "uninstall succeeds when Apple put its stock config back over a customized adopted one: $(cat "$w/err")"
holds "$T/kept/rs8/etc/rs8_config" "admin-rs8 years of edits" || fail "uninstall keeps the admin's original in kept/, and never removes kept/ (R78)"
holds "$V/etc/rs8_config.mavergreen-save" apple-rs8 \
  || fail "uninstall's own save overwrites an older .mavergreen-save again, as R34 says, now that kept originals live elsewhere (R78): $(cat "$V/etc/rs8_config.mavergreen-save")"
rm -f "$V/etc/rs8_config.mavergreen-save"

mkproduct rsu rsu "" bin/rsu
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/rsu string bin/rsu" "$T/rsu/mavergreen.plist"
echo apple-rsu-old > "$V/usr/bin/rsu"; chmod 4755 "$V/usr/bin/rsu"
mg system-replace rsu 2>"$w/err" || fail "setup: system-replace rsu must succeed: $(cat "$w/err")"
rm "$V/usr/bin/rsu"; echo apple-rsu-new > "$V/usr/bin/rsu"; receipt "$V" rsu ./usr/bin/rsu "$V/usr/bin/rsu"
rc=0; (umask 022; mg system-restore rsu >"$w/out" 2>"$w/err") || rc=$?
[ "$rc" -eq 0 ] && holds "$V/usr/bin/rsu" apple-rsu-new && holds "$T/kept/rsu/usr/bin/rsu" apple-rsu-old && gone "$SR/rsu/usr/bin/rsu" \
  && gone "$V/usr/bin/rsu.mavergreen-save" || fail "a setuid original no Apple receipt lists is kept in kept/<P>/<path> (R78): $(cat "$w/err")"
[ "$(stat -f %Mp%Lp "$T/kept/rsu/usr/bin/rsu")" = 0755 ] \
  || fail "a kept setuid original loses its set-id bits (R78): $(stat -f %Mp%Lp "$T/kept/rsu/usr/bin/rsu")"
[ "$(stat -f %Lp "$T/kept")" = 700 ] && [ "$(stat -f %Lp "$T/kept/rsu")" = 700 ] \
  || fail "kept/ and kept/<P> are root-only (0700) whatever the umask (R78): $(stat -f %Lp "$T/kept") $(stat -f %Lp "$T/kept/rsu")"
rm "$V/usr/bin/rsu"; echo apple-rsu-mid > "$V/usr/bin/rsu"
mg system-replace rsu 2>"$w/err" || fail "setup: system-replace rsu again must succeed: $(cat "$w/err")"
rm "$V/usr/bin/rsu"; echo apple-rsu-new > "$V/usr/bin/rsu"
mg system-restore rsu >"$w/out" 2>"$w/err" || fail "setup: the second restore of rsu must succeed: $(cat "$w/err")"
holds "$T/kept/rsu/usr/bin/rsu" apple-rsu-old && holds "$T/kept/rsu/usr/bin/rsu.1" apple-rsu-mid \
  || fail "a second original kept for one path takes the first free <name>.1, never overwriting the first (R78)"
grep -qF "kept as /usr/local/mavergreen/kept/rsu/usr/bin/rsu.1" "$w/out" || fail "that restore names the .1 it kept (R78): $(cat "$w/out")"

mkproduct ow ow "" bin/ow
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/ow string bin/ow" "$T/ow/mavergreen.plist"
echo apple-ow > "$V/usr/bin/ow"
mg system-replace ow 2>"$w/err" || fail "setup: system-replace ow must succeed: $(cat "$w/err")"
mkproduct ox ox "" bin/ox
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/ox string bin/ox" "$T/ox/mavergreen.plist"
echo apple-ox > "$V/usr/bin/ox"
mg system-replace ox 2>"$w/err" || fail "setup: system-replace ox must succeed: $(cat "$w/err")"
"$PB" -c "Set :ProductVersion 10.11.6" "$V/System/Library/CoreServices/SystemVersion.plist"
chmod a-w "$V/usr/bin"
rc=0; mg system-restore ow >"$w/out" 2>"$w/err" || rc=$?
rc2=0; PATH="$stub:$PATH" mg uninstall ox >"$w/out2" 2>"$w/err2" || rc2=$?
chmod u+w "$V/usr/bin"
"$PB" -c "Set :ProductVersion 10.9.5" "$V/System/Library/CoreServices/SystemVersion.plist"
[ "$rc" -eq 0 ] && [ "$rc2" -eq 0 ] \
  || fail "off 10.9, restore and uninstall succeed beside a /usr/bin no one can write, since kept originals go to kept/ (R78): $(cat "$w/err" "$w/err2")"
holds "$T/kept/ow/usr/bin/ow" apple-ow && holds "$T/kept/ox/usr/bin/ox" apple-ox && gone "$T/ox" \
  || fail "those originals are kept in kept/<P>, and uninstall leaves kept/ in place (R78)"
rm -f "$V/usr/bin/ow" "$V/usr/bin/ox"

mkadopt op9 /etc/op9_config=op9_config:config
echo admin-op9 > "$V/etc/op9_config"; mkdir -p "$T/var/op9"
mg system-replace op9 2>"$w/err" || fail "setup: system-replace op9 must succeed: $(cat "$w/err")"
mg system-restore op9 >/dev/null 2>"$w/err" || fail "setup: system-restore op9 must succeed: $(cat "$w/err")"
"$PB" -c "Add :adopts:/etc/op9dir/op9_new dict" -c "Add :adopts:/etc/op9dir/op9_new:path string op9_new" \
      -c "Add :adopts:/etc/op9dir/op9_new:kind string config" "$T/op9/mavergreen.plist"
echo product-made > "$T/var/op9/op9_new"
hook op9 pre-uninstall "touch '$w/op9.ran'"
rc=0; PATH="$stub:$PATH" mg uninstall op9 >"$w/out" 2>"$w/err" || rc=$?
[ "$rc" -eq 0 ] && [ -f "$w/op9.ran" ] && gone "$T/op9" \
  || fail "uninstall after a manual restore plans saves only for what that restore recorded, so a config the product never replaced cannot wedge it (R74): $(cat "$w/err")"
holds "$V/etc/op9_config.mavergreen-save" admin-op9 && gone "$V/etc/op9dir" \
  || fail "that uninstall keeps the restored config and writes nothing beside a path the product never replaced (R74)"
rm -f "$V/etc/op9_config.mavergreen-save"

mkadopt pd /etc/pdd/pd_config=pd_config:config
mkdir -p "$T/var/pd"; echo product-pd > "$T/var/pd/pd_config"
mg system-replace pd 2>"$w/err" || fail "setup: system-replace pd must succeed: $(cat "$w/err")"
mg system-restore pd >/dev/null 2>"$w/err" || fail "setup: system-restore pd must succeed: $(cat "$w/err")"
rmdir "$V/etc/pdd"
hook pd pre-uninstall "touch '$w/pd.ran'"
rc=0; PATH="$stub:$PATH" mg uninstall pd 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] && gone "$w/pd.ran" && [ -d "$T/pd" ] && grep -qF "/etc/pdd" "$w/err" \
  || fail "a planned save whose directory is missing refuses before the pre-uninstall hook, naming it (R74): $(cat "$w/err")"
mkdir -p "$V/etc/pdd"
PATH="$stub:$PATH" mg uninstall pd >/dev/null 2>"$w/err" || fail "setup: uninstall pd succeeds once the directory is back: $(cat "$w/err")"
rm -rf "$V/etc/pdd"

mkadopt op10 /etc/op10_config=op10_config:config
echo admin-op10 > "$V/etc/op10_config"; mkdir -p "$T/var/op10"
mg system-replace op10 2>"$w/err" || fail "setup: system-replace op10 must succeed: $(cat "$w/err")"
echo "edit-op10 while replaced" >> "$V/etc/op10_config"; cp "$V/etc/op10_config" "$w/op10.expect"
(PATH="$mvstub:$PATH" MV_FAIL=restored.sha256 mg system-restore op10 >/dev/null 2>"$w/err") && fail "setup: a restore that cannot record its baselines must fail"
gone "$SR/op10/.replaced" || fail "setup: that restore already unmarked .replaced (M6)"
rc=0; PATH="$stub:$PATH" mg uninstall op10 >"$w/out" 2>"$w/err" || rc=$?
[ "$rc" -eq 0 ] && is_copy "$V/etc/op10_config.mavergreen-save" "$w/op10.expect" \
  || fail "uninstall plans saves from applied.plist even after a restore unmarked .replaced, so the admin's edit is kept (R75): $(cat "$w/err")"
rm -f "$V/etc/op10_config.mavergreen-save"

mkproduct vn vn "" bin/vn
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/vn string bin/vn" "$T/vn/mavergreen.plist"
echo apple-vn > "$V/usr/bin/vn"
mg system-replace vn 2>"$w/err" || fail "setup: system-replace vn must succeed: $(cat "$w/err")"
mv "$V/System/Library/CoreServices/SystemVersion.plist" "$w/sv.plist"
rc=0; mg system-restore vn >"$w/out" 2>"$w/err" || rc=$?
mv "$w/sv.plist" "$V/System/Library/CoreServices/SystemVersion.plist"
[ "$rc" -ne 0 ] && grep -qF "cannot read this volume's macOS version" "$w/err" \
  || fail "restore refuses when it cannot read the volume's version, rather than taking it for one past 10.9 (R76): rc $rc, $(cat "$w/err")"
holds "$SR/vn/usr/bin/vn" apple-vn && is_copy "$V/usr/bin/vn" "$T/vn/bin/vn" && [ -f "$SR/vn/.replaced" ] \
  || fail "that refusal changes nothing: the saved original and the copy are as they were (R76)"
mg system-restore vn 2>"$w/err" || fail "setup: system-restore vn must succeed once the version is readable: $(cat "$w/err")"

mkadopt pz /etc/pz_config=pz_config:config
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/pz string bin/stub" "$T/pz/mavergreen.plist"
echo apple-pz > "$V/usr/bin/pz"; echo admin-pz > "$V/etc/pz_config"; mkdir -p "$T/var/pz"
mg system-replace pz 2>"$w/err" || fail "setup: system-replace pz must succeed: $(cat "$w/err")"
echo "edit-while-replaced" >> "$V/etc/pz_config"; cp "$V/etc/pz_config" "$w/pz.expect"
(PATH="$mvstub:$PATH" MV_FAIL=usr/bin/pz mg system-restore pz >/dev/null 2>"$w/err") && fail "setup: a restore whose program move fails must fail"
is_copy "$T/var/pz/pz_config" "$w/pz.expect" && ! aplist pz adopts:/etc/pz_config >/dev/null \
  || fail "setup: the config is back in var and dropped from applied.plist, the program is not back"
rc=0; PATH="$stub:$PATH" mg uninstall pz >"$w/out" 2>"$w/err" || rc=$?
[ "$rc" -eq 0 ] && is_copy "$V/etc/pz_config.mavergreen-save" "$w/pz.expect" \
  || fail "uninstall after a restore that stopped after the config came back keeps the admin's edit (R80): $(cat "$w/err")"
rm -f "$V/etc/pz_config.mavergreen-save"

mkadopt pk /etc/pk_config=pk_config:config
echo admin-pk > "$V/etc/pk_config"; mkdir -p "$T/var/pk"
mg system-replace pk 2>"$w/err" || fail "setup: system-replace pk must succeed: $(cat "$w/err")"
echo "edit-pk" >> "$V/etc/pk_config"; cp "$V/etc/pk_config" "$w/pk.expect"
(PATH="$mvstub:$PATH" RM_FAIL=system-replace/pk/staging mg system-restore pk >/dev/null 2>"$w/err") \
  && fail "setup: a restore stopped while clearing its save area must fail"
[ -f "$SR/pk/applied.plist" ] && ! aplist pk adopts:/etc/pk_config >/dev/null || fail "setup: the entry is dropped and applied.plist stays"
rc=0; PATH="$stub:$PATH" mg uninstall pk >"$w/out" 2>"$w/err" || rc=$?
[ "$rc" -eq 0 ] && is_copy "$V/etc/pk_config.mavergreen-save" "$w/pk.expect" \
  || fail "uninstall after a restore stopped between dropping the entry and clearing its save area keeps the admin's edit (R80): $(cat "$w/err")"
rm -f "$V/etc/pk_config.mavergreen-save"

mkproduct hl hl "" bin/hl
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/hl string bin/hl" "$T/hl/mavergreen.plist"
echo custom-hl > "$V/usr/bin/hl"; chmod 4755 "$V/usr/bin/hl"; ln "$V/usr/bin/hl" "$V/usr/bin/hl2"
mg system-replace hl 2>"$w/err" || fail "setup: system-replace hl must succeed: $(cat "$w/err")"
rm "$V/usr/bin/hl"; echo apple-hl > "$V/usr/bin/hl"; receipt "$V" hl ./usr/bin/hl "$V/usr/bin/hl"
mg system-restore hl >"$w/out" 2>"$w/err" || fail "setup: system-restore hl must succeed: $(cat "$w/err")"
[ "$(stat -f %Mp%Lp "$V/usr/bin/hl2")" = 4755 ] \
  || fail "keeping a hard-linked original never clears set-id on another link to it, such as a live program (R81): $(stat -f %Mp%Lp "$V/usr/bin/hl2")"
holds "$T/kept/hl/usr/bin/hl" custom-hl && [ "$(stat -f %Mp%Lp "$T/kept/hl/usr/bin/hl")" = 0755 ] && gone "$SR/hl/usr/bin/hl" \
  || fail "the kept copy of a hard-linked original has no set-id bits, and the save link is gone (R81): $(stat -f %Mp%Lp "$T/kept/hl/usr/bin/hl" 2>&1)"
rm -f "$V/usr/bin/hl2"

mkproduct ks ks "" bin/ks
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/ks string bin/ks" "$T/ks/mavergreen.plist"
echo apple-ks-old > "$V/usr/bin/ks"; chmod 4755 "$V/usr/bin/ks"
mg system-replace ks 2>"$w/err" || fail "setup: system-replace ks must succeed: $(cat "$w/err")"
rm "$V/usr/bin/ks"; echo apple-ks-new > "$V/usr/bin/ks"; receipt "$V" ks ./usr/bin/ks "$V/usr/bin/ks"
(PATH="$mvstub:$PATH" MV_FAIL=usr/bin/ks mg system-restore ks >"$w/out" 2>"$w/err") && fail "setup: a restore whose move into kept/ fails must fail"
if grep -q "kept as" "$w/out"; then fail "restore says an original is kept only once it has moved (R82): $(cat "$w/out")"; fi
holds "$SR/ks/usr/bin/ks" apple-ks-old || fail "setup: that failed move leaves the save in the save area"
mg system-restore ks >"$w/out" 2>"$w/err" || fail "the rerun finishes the move into kept/: $(cat "$w/err")"
holds "$T/kept/ks/usr/bin/ks" apple-ks-old && grep -qF "kept as /usr/local/mavergreen/kept/ks/usr/bin/ks" "$w/out" \
  || fail "that rerun keeps the original and says where (R82): $(cat "$w/out")"

mkadopt uo /etc/uo_config=uo_config:config
echo admin-uo > "$V/etc/uo_config"
(PATH="$mvstub:$PATH" MV_FAIL=var/uo/uo_config mg system-replace uo 2>"$w/err") && fail "setup: a replace whose var link fails must fail"
seeded uo uo_config default-uo; echo other-uo > "$T/var/uo/uo_config"
mg system-replace uo 2>"$w/err" && fail "a rerun must refuse a link-pending var file that is neither the system file nor the seeded default (R37)"
grep -qF /usr/local/mavergreen/var/uo/uo_config "$w/err" || fail "that refusal names the var file: $(cat "$w/err")"
holds "$T/var/uo/uo_config" other-uo && holds "$V/etc/uo_config" admin-uo || fail "that refusal changes neither file"
echo admin-uo > "$T/var/uo/uo_config"
mg system-restore uo || fail "setup: system-restore uo must succeed"

mkadopt uu /etc/uu_config=uu_config:config
seeded uu uu_config default-uu
mg system-replace uu 2>"$w/err" || fail "setup: system-replace uu must succeed: $(cat "$w/err")"
echo admin-uu >> "$V/etc/uu_config"; cp "$V/etc/uu_config" "$w/uu.expect"
hook uu post-system-restore "if [ ! -e '$w/uu.killed' ]; then touch '$w/uu.killed'; kill -9 \$PPID; sleep 5; fi"
rc=0; PATH="$stub:$PATH" mg uninstall uu 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] && [ -f "$w/uu.killed" ] && [ -f "$SR/uu/.replaced" ] && [ "$(aplist uu adopts:/etc/uu_config:kind)" = config ] \
  && ! aplist uu copies:/etc/uu_config >/dev/null || fail "setup: an uninstall stopped after its keep-mode restore"
mg system-replace uu 2>"$w/err" || fail "a rerun applies an adopts entry that has no records, as new (R38): $(cat "$w/err")"
links uu uu_config /etc/uu_config && is_copy "$V/etc/uu_config" "$w/uu.expect" \
  && [ "$(aplist uu copies:/etc/uu_config)" = "$(sha "$w/uu.expect")" ] && [ "$(aplist uu originals:/etc/uu_config)" = - ] \
  || fail "that rerun adopts the admin's config again and records it"
mg system-restore uu || fail "setup: system-restore uu must succeed"

mkadopt uv /etc/uv_x=uv_x:config
seeded uv uv_x default-uv
mg system-replace uv || fail "setup: system-replace uv must succeed"
"$PB" -c "Delete :adopts:/etc/uv_x" -c "Add :replaces dict" -c "Add :replaces:/etc/uv_x string bin/stub" "$T/uv/mavergreen.plist"
mg system-replace uv 2>"$w/err" && fail "an upgrade must refuse an entry that moves from adopts to replaces"
grep -qF "/etc/uv_x" "$w/err" && grep -q "moves between adopts and replaces" "$w/err" && grep -qF "run mavergreen system-restore uv, then mavergreen system-replace uv" "$w/err" || fail "that refusal names the entry and says why: $(cat "$w/err")"
holds "$V/etc/uv_x" default-uv && links uv uv_x /etc/uv_x || fail "that refusal changes nothing"
"$PB" -c "Delete :replaces:/etc/uv_x" -c "Add :adopts:/etc/uv_x dict" -c "Add :adopts:/etc/uv_x:path string uv_y" \
      -c "Add :adopts:/etc/uv_x:kind string config" "$T/uv/mavergreen.plist"
mg system-replace uv 2>"$w/err" && fail "an upgrade must refuse an adopts entry whose var path changed"
grep -qF /usr/local/mavergreen/var/uv/uv_x "$w/err" && grep -qF /usr/local/mavergreen/var/uv/uv_y "$w/err" && grep -qF "run mavergreen system-restore uv, then mavergreen system-replace uv" "$w/err" || fail "that refusal names both var paths: $(cat "$w/err")"
holds "$V/etc/uv_x" default-uv && links uv uv_x /etc/uv_x && gone "$T/var/uv/uv_y" || fail "that refusal changes nothing"
mg system-restore uv || fail "setup: system-restore uv must succeed"
mkproduct uy uy "" bin/uy
"$PB" -c "Add :replaces dict" -c "Add :replaces:/etc/uy_x string bin/uy" "$T/uy/mavergreen.plist"
echo apple-uy > "$V/etc/uy_x"
mg system-replace uy || fail "setup: system-replace uy must succeed"
"$PB" -c "Delete :replaces:/etc/uy_x" -c "Add :adopts dict" -c "Add :adopts:/etc/uy_x dict" -c "Add :adopts:/etc/uy_x:path string uy_x" \
      -c "Add :adopts:/etc/uy_x:kind string config" "$T/uy/mavergreen.plist"
mg system-replace uy 2>"$w/err" && fail "an upgrade must refuse an entry that moves from replaces to adopts"
grep -qF "/etc/uy_x moves between adopts and replaces" "$w/err" && grep -qF "run mavergreen system-restore uy, then mavergreen system-replace uy" "$w/err" || fail "that refusal names the entry and says why: $(cat "$w/err")"
is_copy "$V/etc/uy_x" "$T/uy/bin/uy" && holds "$SR/uy/etc/uy_x" apple-uy && gone "$T/var/uy/uy_x" || fail "that refusal changes nothing"
mg system-restore uy || fail "setup: system-restore uy must succeed"
mkproduct rk rk "" bin/rk1 bin/rk2 bin/rk3
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/rk1 string bin/rk1" -c "Add :replaces:/usr/bin/rk2 string bin/rk2" \
      -c "Add :replaces:/usr/bin/rk3 string bin/rk3" "$T/rk/mavergreen.plist"
for n in 1 2 3; do echo "apple-rk$n" > "$V/usr/bin/rk$n"; chmod 555 "$V/usr/bin/rk$n"; receipt "$V" "rk$n" "./usr/bin/rk$n" "$V/usr/bin/rk$n"; done
rkback() {  # $1 entry number; Apple puts its original back: same bytes, a new file
  rm "$V/usr/bin/rk$1"; cp "$SR/rk/usr/bin/rk$1" "$V/usr/bin/rk$1"
}
mg system-replace rk || fail "setup: system-replace rk must succeed"
ino="$(stat -f %i "$SR/rk/usr/bin/rk1")"; rkback 1
mg system-restore rk 2>"$w/err" || fail "restore treats an Apple-stock file identical to its saved original as already restored (R39): $(cat "$w/err")"
holds "$V/usr/bin/rk1" apple-rk1 && [ "$(stat -f %i "$V/usr/bin/rk1")" = "$ino" ] && [ "$(stat -f %Lp "$V/usr/bin/rk1")" = 555 ] \
  || fail "that restore renames the saved original into place, keeping its inode and mode"
holds "$V/usr/bin/rk2" apple-rk2 && gone "$SR/rk" || fail "that restore puts back the other entries and clears the save area"
mg system-replace rk || fail "setup: system-replace rk again must succeed"
rkback 3
(PATH="$mvstub:$PATH" MV_FAIL=usr/bin/rk3 mg system-replace rk 2>"$w/err") && fail "setup: a K.4 re-replace killed before its swap must fail"
[ "$(aplist rk copies:/usr/bin/rk3)" = "$(sha "$T/rk/bin/rk3")" ] && holds "$V/usr/bin/rk3" apple-rk3 \
  || fail "setup: the K.4 re-replace recorded its copy, and Apple's original is still in place"
mg system-restore rk 2>"$w/err" || fail "restore works after an interrupted K.4 re-replace (R39): $(cat "$w/err")"
holds "$V/usr/bin/rk1" apple-rk1 && holds "$V/usr/bin/rk2" apple-rk2 && holds "$V/usr/bin/rk3" apple-rk3 && gone "$SR/rk" \
  || fail "that restore leaves every original in place and clears the save area"
mg system-replace rk || fail "setup: system-replace rk a third time must succeed"
rkback 1
rc=0; PATH="$stub:$PATH" mg uninstall rk 2>"$w/err" || rc=$?
[ "$rc" -eq 0 ] || fail "uninstall succeeds after Apple put an original back (R39): $(cat "$w/err")"
holds "$V/usr/bin/rk1" apple-rk1 && holds "$V/usr/bin/rk2" apple-rk2 && gone "$T/rk" && gone "$SR/rk" \
  || fail "that uninstall leaves the originals in place and removes the product"
mkadopt xk /etc/xk_config=xk_config:config
seeded xk xk_config default-xk
mg system-replace xk 2>"$w/err" || fail "setup: system-replace xk must succeed: $(cat "$w/err")"
echo admin-xk >> "$V/etc/xk_config"; cp "$V/etc/xk_config" "$w/xk.expect"
hook xk post-system-restore "if [ ! -e '$w/xk.killed' ]; then touch '$w/xk.killed'; kill -9 \$PPID; sleep 5; fi"
(PATH="$stub:$PATH" mg uninstall xk 2>"$w/err") && fail "setup: an uninstall killed after its restore must fail"
! aplist xk copies:/etc/xk_config >/dev/null && [ "$(aplist xk adopts:/etc/xk_config:kind)" = config ] \
  || fail "setup: the adopts entry is left without records (R38)"
"$PB" -c "Delete :adopts:/etc/xk_config" -c "Add :replaces dict" -c "Add :replaces:/etc/xk_config string bin/stub" "$T/xk/mavergreen.plist"
mg system-replace xk 2>"$w/err" && fail "an upgrade must refuse an entry that moves from adopts to replaces even when the adoption has no records (R42)"
grep -qF "/etc/xk_config moves between adopts and replaces" "$w/err" && grep -qF "run mavergreen system-restore xk, then mavergreen system-replace xk" "$w/err" \
  || fail "that refusal names the entry and the way out: $(cat "$w/err")"
gone "$V/etc/xk_config" && is_copy "$T/var/xk/xk_config" "$w/xk.expect" && [ "$(aplist xk adopts:/etc/xk_config:kind)" = config ] \
  && ! aplist xk replaces:/etc/xk_config >/dev/null || fail "that refusal changes nothing"
mg system-restore xk 2>"$w/err" || fail "the way out: system-restore succeeds: $(cat "$w/err")"
mg system-replace xk 2>"$w/err" || fail "the way out: system-replace then succeeds: $(cat "$w/err")"
is_copy "$V/etc/xk_config" "$T/xk/bin/stub" && [ "$(aplist xk copies:/etc/xk_config)" = "$(sha "$T/xk/bin/stub")" ] \
  || fail "the path is then P's copy, recorded"
mg system-restore xk || fail "setup: system-restore xk must succeed"

mkproduct um um "" bin/um
chmod 755 "$T/um/bin/um"
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/um string bin/um" "$T/um/mavergreen.plist"
echo apple-um > "$V/usr/bin/um"
mg system-replace um || fail "setup: system-replace um must succeed"
ino="$(stat -f %i "$SR/um/usr/bin/um")"; chmod 4755 "$T/um/bin/um"; : > "$w/probe.log"
(PATH="$probe:$PATH" PROBE="$V/usr/bin/um" PROBE_LOG="$w/probe.log" mg system-replace um 2>"$w/err") \
  || fail "an upgrade whose tree file changed mode only must succeed: $(cat "$w/err")"
[ "$(stat -f %Mp%Lp "$V/usr/bin/um")" = 4755 ] && is_copy "$V/usr/bin/um" "$T/um/bin/um" \
  || fail "a tree file whose mode changed but whose bytes did not refreshes the copy (R45)"
[ ! -s "$w/probe.log" ] || fail "the system path is a real file throughout that refresh: $(cat "$w/probe.log")"
holds "$SR/um/usr/bin/um" apple-um && [ "$(stat -f %i "$SR/um/usr/bin/um")" = "$ino" ] && ! aplist um refreshing:/usr/bin/um >/dev/null \
  || fail "that refresh keeps the saved original and leaves no refreshing record"
mg system-restore um || fail "setup: system-restore um must succeed"

mkadopt uz /etc/uz_config=uz_config:config
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/uz string bin/stub" "$T/uz/mavergreen.plist"
echo apple-uz > "$V/etc/uz_config"; receipt "$V" uz ./etc/uz_config "$V/etc/uz_config"; seeded uz uz_config default-uz
echo apple-uz2 > "$V/usr/bin/uz2"
mg system-replace uz || fail "setup: system-replace uz must succeed"
old="$(sha "$V/usr/bin/uz")"; mv "$SR/uz/etc/uz_config" "$w/uz-aside"
"$PB" -c "Delete :adopts:/etc/uz_config" -c "Add :replaces:/usr/bin/uz2 string bin/stub" "$T/uz/mavergreen.plist"
echo stub-v2 > "$T/uz/bin/stub"
mg system-replace uz 2>"$w/err" && fail "an upgrade must refuse when an adoption it no longer declares cannot be restored"
grep -qF "the original saved for /etc/uz_config is missing" "$w/err" || fail "that refusal gives restore's own reason: $(cat "$w/err")"
[ "$(sha "$V/usr/bin/uz")" = "$old" ] && holds "$V/usr/bin/uz2" apple-uz2 && links uz uz_config /etc/uz_config \
  && holds "$V/etc/uz_config" default-uz && [ "$(aplist uz adopts:/etc/uz_config:kind)" = config ] \
  || fail "that refusal comes before any change: no copy refreshed, no new entry applied, the adoption left as it was"
mv "$w/uz-aside" "$SR/uz/etc/uz_config"
mg system-replace uz 2>"$w/err" || fail "the upgrade succeeds once the saved original is back: $(cat "$w/err")"
holds "$V/etc/uz_config" apple-uz && is_copy "$V/usr/bin/uz2" "$T/uz/bin/stub" || fail "that upgrade restores the adoption and applies the new entry"
mg system-restore uz || fail "setup: system-restore uz must succeed"

dkrun() {  # $1 which applied.plist rewrite is killed (2: after restoring the dropped adoption, 3: after restoring the dropped copy)  $2 rerun|restore
  mkadopt dk /etc/dk_config=dk_config:config
  "$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/dk string bin/stub" "$T/dk/mavergreen.plist"
  rm -f "$V/etc/dk_config" "$V/usr/bin/dk"; echo apple-dk > "$V/usr/bin/dk"; echo apple-dkc > "$V/etc/dk_config"
  receipt "$V" dk ./etc/dk_config "$V/etc/dk_config"; seeded dk dk_config default-dk
  mg system-replace dk || fail "setup: system-replace dk must succeed"
  "$PB" -c "Delete :replaces:/usr/bin/dk" -c "Delete :adopts:/etc/dk_config" "$T/dk/mavergreen.plist"; rm -f "$w/mvn"
  (PATH="$nth:$PATH" MVN_SUFFIX=applied.plist MVN_NTH="$1" MVN_COUNT="$w/mvn" mg system-replace dk 2>"$w/err") \
    && fail "setup: an upgrade killed while restoring a dropped entry must fail"
  if [ "$1" = 2 ]; then
    holds "$V/etc/dk_config" apple-dkc && [ "$(aplist dk adopts:/etc/dk_config:kind)" = config ] \
      || fail "setup: killed after restoring the dropped adoption, before dropping its record"
  else
    holds "$V/usr/bin/dk" apple-dk && [ "$(aplist dk replaces:/usr/bin/dk)" = bin/stub ] \
      || fail "setup: killed after restoring the dropped copy, before dropping its record"
  fi
  if [ "$2" = rerun ]; then
    mg system-replace dk 2>"$w/err" || fail "a rerun finishes an upgrade killed while restoring a dropped entry ($1): $(cat "$w/err")"
    ! aplist dk replaces:/usr/bin/dk >/dev/null && ! aplist dk adopts:/etc/dk_config >/dev/null && [ -f "$SR/dk/.replaced" ] \
      || fail "that rerun drops both entries from applied.plist ($1)"
  else
    mg system-restore dk 2>"$w/err" || fail "restore works after an upgrade killed while restoring a dropped entry ($1): $(cat "$w/err")"
    gone "$SR/dk/applied.plist" || fail "that restore clears the state ($1)"
  fi
  holds "$V/usr/bin/dk" apple-dk && holds "$V/etc/dk_config" apple-dkc && holds "$T/var/dk/dk_config" default-dk \
    || fail "every original is back and var holds the product's file ($1, $2)"
  mg system-restore dk 2>/dev/null || true
}
dkrun 2 rerun; dkrun 2 restore; dkrun 3 rerun; dkrun 3 restore

if [ "$(sh -c 'kill -INT $$; echo alive' 2>/dev/null)" = alive ]; then
  echo "SIGINT is ignored in this run (started in the background?), so no hook can be cancelled by it -- skipping the process-group SIGINT pre-uninstall hook test" >&2
elif command -v perl >/dev/null 2>&1; then
  mkproduct hookintgroup hookintgroup "" bin/hookintgroup
  mkdir -p "$T/hookintgroup/libexec/mavergreen"
  printf '#!/bin/sh\nkill -INT 0\nsleep 5\n' > "$T/hookintgroup/libexec/mavergreen/pre-uninstall"
  chmod +x "$T/hookintgroup/libexec/mavergreen/pre-uninstall"
  rc=0
  PATH="$stub:$PATH" MAVERGREEN_TRUSTED_UID="$(id -u)" perl -e 'setpgrp 0, 0; exec @ARGV' sh "$MG" --root "$V" uninstall hookintgroup 2>"$w/err" || rc=$?
  [ "$rc" -ne 0 ] || fail "uninstall must fail when a real Ctrl-C (delivered to the whole process group) kills its hook"
  grep -qi cancelled "$w/err" \
    || fail "the helper must survive a process-group SIGINT delivered while its hook runs, and report it as cancelled: $(cat "$w/err")"
  [ -d "$T/hookintgroup" ] || fail "a process-group SIGINT during the pre-uninstall hook must remove nothing"
else
  echo "no perl -- skipping the process-group SIGINT pre-uninstall hook test" >&2
fi

echo "PASS: mavergreen-helper"
