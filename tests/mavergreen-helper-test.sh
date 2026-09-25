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
mg() { sh "$MG" --root "$V" "$@"; }
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

mkproduct openssh openssh "" bin/ssh sbin/sshd
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/ssh string bin/ssh" \
      -c "Add :replaces:/usr/sbin/sshd string sbin/sshd" "$T/openssh/mavergreen.plist"
mkdir -p "$V/usr/bin" "$V/usr/sbin" "$V/System/Library/CoreServices"
echo apple-ssh > "$V/usr/bin/ssh"
"$PB" -c "Add :ProductVersion string 26.0" "$V/System/Library/CoreServices/SystemVersion.plist" >/dev/null
mg system-replace openssh 2>"$w/err" && fail "system-replace must refuse a volume that is not 10.9"
grep -q 'sealed\|10.9' "$w/err" || fail "the refusal must say why"
"$PB" -c "Set :ProductVersion 10.9.5" "$V/System/Library/CoreServices/SystemVersion.plist"
mg system-replace openssh || fail "system-replace on 10.9 must succeed"
[ "$(readlink "$V/usr/bin/ssh")" = /usr/local/mavergreen/openssh/bin/ssh ] || fail "the system path becomes a link into the product"
[ "$(cat "$T/var/system-replace/openssh/usr/bin/ssh")" = apple-ssh ] || fail "the original is saved"
[ -L "$V/usr/sbin/sshd" ] || fail "a replacement with no original still gets its link"
mg system-replace openssh || fail "system-replace must be idempotent"
[ "$(cat "$T/var/system-replace/openssh/usr/bin/ssh")" = apple-ssh ] || fail "a second replace must not overwrite the saved original with our own link"
rm "$V/usr/bin/ssh"; echo apple-update > "$V/usr/bin/ssh"
mg check 2>"$w/err" && fail "a replaced path that is no longer our link is drift, and check must fail"
grep -q /usr/bin/ssh "$w/err" || fail "check must name the drifted path"
mg system-replace openssh 2>"$w/err" && fail "system-replace must refuse a drifted path whose original was already saved"
grep -q 'system-restore\|already saved' "$w/err" || fail "the refusal must say to run system-restore"
[ "$(cat "$T/var/system-replace/openssh/usr/bin/ssh")" = apple-ssh ] \
  || fail "a refused system-replace must not touch the saved original"
[ -f "$T/var/system-replace/openssh/.replaced" ] || fail "a refused system-replace must not remove the .replaced marker"
[ "$(cat "$V/usr/bin/ssh")" = apple-update ] || fail "a refused system-replace must leave the drifted path alone"
rm "$V/usr/bin/ssh"; ln -s /usr/local/mavergreen/openssh/bin/ssh "$V/usr/bin/ssh"
mg system-restore openssh || fail "system-restore must succeed"
[ "$(cat "$V/usr/bin/ssh")" = apple-ssh ] && [ ! -L "$V/usr/bin/ssh" ] || fail "restore puts the original back"
[ ! -e "$V/usr/sbin/sshd" ] && [ ! -L "$V/usr/sbin/sshd" ] || fail "restore removes a link that had no original"
[ ! -e "$T/var/system-replace/openssh" ] || fail "restore clears its saved state"

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

mkproduct dropped dropped "" bin/h
"$PB" -c "Add :replaces dict" -c "Add :replaces:/usr/bin/h string bin/h" "$T/dropped/mavergreen.plist"
echo apple-h > "$V/usr/bin/h"
mg system-replace dropped || fail "setup: system-replace dropped must succeed"
"$PB" -c "Delete :replaces:/usr/bin/h" "$T/dropped/mavergreen.plist"
mg system-restore dropped || fail "system-restore must succeed even when its manifest no longer lists the entry"
[ "$(cat "$V/usr/bin/h")" = apple-h ] && [ ! -L "$V/usr/bin/h" ] \
  || fail "system-restore must put back an original whose manifest entry was since dropped"
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
[ "$rc" -ne 0 ] || fail "a symlinked pre-uninstall hook must be refused, even if its target is a real, in-root file"
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
[ "$(readlink "$V/usr/bin/hookbr")" = /usr/local/mavergreen/hookbeforerestore/bin/hookbr ] \
  || fail "a failing pre-uninstall hook must run before system-restore -- the replaced system path must still be our link"
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

if command -v perl >/dev/null 2>&1; then
  mkproduct hookintgroup hookintgroup "" bin/hookintgroup
  mkdir -p "$T/hookintgroup/libexec/mavergreen"
  printf '#!/bin/sh\nkill -INT 0\nsleep 5\n' > "$T/hookintgroup/libexec/mavergreen/pre-uninstall"
  chmod +x "$T/hookintgroup/libexec/mavergreen/pre-uninstall"
  rc=0
  PATH="$stub:$PATH" perl -e 'setpgrp 0, 0; exec @ARGV' sh "$MG" --root "$V" uninstall hookintgroup 2>"$w/err" || rc=$?
  [ "$rc" -ne 0 ] || fail "uninstall must fail when a real Ctrl-C (delivered to the whole process group) kills its hook"
  grep -qi cancelled "$w/err" \
    || fail "the helper must survive a process-group SIGINT delivered while its hook runs, and report it as cancelled: $(cat "$w/err")"
  [ -d "$T/hookintgroup" ] || fail "a process-group SIGINT during the pre-uninstall hook must remove nothing"
else
  echo "no perl -- skipping the process-group SIGINT pre-uninstall hook test" >&2
fi

echo "PASS: mavergreen-helper"
