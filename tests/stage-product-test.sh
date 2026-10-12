#!/bin/sh
# platform: macOS-only -- PlistBuddy reads the manifest stage_product.sh renders
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/stage_product.sh"
[ -x /usr/libexec/PlistBuddy ] || { echo "no PlistBuddy -- skipping"; exit 77; }
w="$(mktemp -d "${TMPDIR:-/tmp}/stage-product.XXXXXX")"; trap 'chmod -R u+w "$w" 2>/dev/null; rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
run_with_timeout() {
  _secs="$1"; _rcfile="$2"; shift 2
  "$@" >/dev/null 2>&1 &
  _pid=$!
  _n=0
  while kill -0 "$_pid" 2>/dev/null; do
    _n=$((_n + 1))
    if [ "$_n" -gt "$_secs" ]; then
      kill -TERM "$_pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$_pid" 2>/dev/null || true
      wait "$_pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
  done
  wait "$_pid" 2>/dev/null
  echo $? > "$_rcfile"
  return 0
}
st="$w/stage"; mkdir -p "$st/usr/local/mavergreen/openssh/bin"; echo ssh > "$st/usr/local/mavergreen/openssh/bin/ssh"
printf 'echo post-hook-ran "$ROOT" >> "$ROOT/hook.log"\n' > "$w/hook"
sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr" --postinstall-hook "$w/hook"
[ -f "$st/usr/local/mavergreen/openssh/mavergreen.plist" ] || fail "the manifest is rendered"
sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-gen" \
  --generated "Applications/Linux X.app" || fail "stage_product must accept --generated"
[ "$(/usr/libexec/PlistBuddy -c 'Print :generated:0' "$st/usr/local/mavergreen/openssh/mavergreen.plist")" = "Applications/Linux X.app" ] \
  || fail "stage_product passes --generated through to the manifest"

sh -n "$w/scr/preinstall" || fail "generated preinstall must be valid sh"
sh -n "$w/scr/postinstall" || fail "generated postinstall must be valid sh"

V="$w/vol"; mkdir -p "$V/usr/local/mavergreen/openssh/stale" "$V/usr/local/mavergreen/var/openssh"
touch "$V/usr/local/mavergreen/var/openssh/state"
sh "$w/scr/preinstall" /x.pkg "$V/" "$V/" || fail "preinstall must succeed"
[ -d "$V/usr/local/mavergreen/openssh/stale" ] || fail "preinstall leaves the installed tree for the payload to be laid over (spec F)"
[ -f "$V/usr/local/mavergreen/var/openssh/state" ] || fail "preinstall must never touch var/"
cp -R "$st/usr/local/mavergreen/openssh" "$V/usr/local/mavergreen/"
mkdir -p "$V/usr/local/mavergreen/.base/9.9"
sed 's/@MAVERGREEN_VERSION@/9.9/' "$here/../scripts/mavergreen.sh" > "$V/usr/local/mavergreen/.base/9.9/mavergreen"
chmod +x "$V/usr/local/mavergreen/.base/9.9/mavergreen"
sh "$w/scr/postinstall" /x.pkg "$V/" "$V/" || fail "postinstall must succeed with only a staged helper"
[ ! -e "$V/usr/local/mavergreen/openssh/stale" ] || fail "postinstall prunes a directory the new payload does not carry (spec F)"
[ -f "$V/usr/local/mavergreen/var/openssh/state" ] || fail "postinstall's prune never touches var/"
[ -L "$V/usr/local/mavergreen/bin/ssh" ] || fail "postinstall links the product"
grep -q post-hook-ran "$V/hook.log" || fail "the product's own postinstall hook runs"
rm -rf "$V/usr/local/mavergreen/.base"
sh "$w/scr/postinstall" /x.pkg "$V/" "$V/" 2>/dev/null && fail "postinstall with no helper at all must fail loudly"
sh "$w/scr/preinstall" /x.pkg >/dev/null 2>&1; [ -d "$V/usr/local/mavergreen/openssh" ] || fail "preinstall with no target volume removes nothing"
mkdir -p "$w/empty"
sh "$S" --stage "$w/empty" --product openssh --name x --version 1 --scripts-out "$w/scr2" 2>/dev/null \
  && fail "a product with nothing staged at all must be refused"
so="$w/outside-only"; mkdir -p "$so/usr/lib/swift"; echo lib > "$so/usr/lib/swift/libswiftCore.dylib"
sh "$S" --stage "$so" --product swift-runtime --name "Swift Runtime" --version 1 --scripts-out "$w/scr-so" \
  || fail "a product whose every file lives where the OS dictates still stages, so its manifest can find them"
[ -f "$so/usr/local/mavergreen/swift-runtime/mavergreen.plist" ] \
  || fail "an outside-only product's manifest sits at its tree root, where the helper and conformance look"
/usr/libexec/PlistBuddy -c 'Print :outside:0' "$so/usr/local/mavergreen/swift-runtime/mavergreen.plist" 2>/dev/null \
  | grep -qx usr/lib/swift/libswiftCore.dylib \
  || fail "an outside-only product's manifest lists its files in outside, so uninstall removes them"
grep -q 'rm -rf "$ROOT/usr/local/mavergreen/openssh"' "$w/scr/preinstall" \
  && fail "the preinstall never removes the product tree wholesale, so a replaced system path never points at nothing (spec F)"

APP="$w/openssh-updater.app"
mkdir -p "$APP/Contents/MacOS"
printf '#!/bin/sh\n' > "$APP/Contents/MacOS/openssh-updater"
chmod +x "$APP/Contents/MacOS/openssh-updater"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string dev.mavergreen.openssh.updater" \
  -c "Add :SUFeedURL string https://github.com/Mavergreen/openssh/releases/latest/download/openssh.xml" \
  "$APP/Contents/Info.plist" >/dev/null
SCRU="$w/scr-updater"
sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$SCRU" --updater-app "$APP" \
  || fail "stage_product with --updater-app must succeed"
[ -d "$st/Library/Application Support/Mavergreen/openssh-updater.app" ] \
  || fail "the updater lands where the registry puts openssh's"
[ -f "$st/Library/LaunchAgents/dev.mavergreen.openssh-updatecheck.plist" ] \
  || fail "the update-check job carries the registry's label for openssh"
[ "$(/usr/libexec/PlistBuddy -c 'Print :appcast' "$st/usr/local/mavergreen/openssh/mavergreen.plist")" = https://github.com/Mavergreen/openssh/releases/latest/download/openssh.xml ] \
  || fail "a product that stages an updater names the registry's feed in its manifest"
[ -z "$(/usr/libexec/PlistBuddy -c 'Print :appcast' "$so/usr/local/mavergreen/swift-runtime/mavergreen.plist")" ] \
  || fail "a product with no updater has no feed, so its manifest's appcast is empty -- never a URL that 404s"
sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-hu" --has-updater 2>/dev/null \
  && fail "--has-updater is stage_product's to pass, never a caller's"
for f in --appcast --app-dir --agent-label; do
  rc=0; sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-refused" \
    --updater-app "$APP" "$f" x 2>/dev/null || rc=$?
  [ "$rc" -eq 2 ] || fail "$f is derived from the registry, so passing it is a usage error (exit 2); got $rc"
done
WRONG="$w/wrong/openssh-updater.app"; mkdir -p "$WRONG/Contents/MacOS"
printf '#!/bin/sh\n' > "$WRONG/Contents/MacOS/openssh-updater"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string dev.mavergreen.OpenSSHUpdater" \
  -c "Add :SUFeedURL string https://github.com/Mavergreen/openssh/releases/latest/download/appcast.xml" \
  "$WRONG/Contents/Info.plist" >/dev/null
sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-wrong" \
  --updater-app "$WRONG" 2>"$w/err" \
  && fail "an updater built with another bundle id or feed than the registry's must be refused -- the app and its stage would disagree"
grep -q 'dev.mavergreen.openssh.updater' "$w/err" || fail "the refusal names the identity the registry expects: $(cat "$w/err")"
MAVERGREEN_PRODUCT_NAMES="$w/absent-registry" sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 \
  --scripts-out "$w/scr-noreg" --updater-app "$APP" 2>"$w/err" \
  && fail "an unreadable registry must refuse staging an updater"
grep -q "cannot look up openssh in shipyard's registry" "$w/err" && grep -q absent-registry "$w/err" \
  || fail "an unreadable registry is reported as such, with product-name.sh's reason: $(cat "$w/err")"
printf 'openssh dev.mavergreen.openssh Bad_Repo\n' > "$w/badrepo-names"
MAVERGREEN_PRODUCT_NAMES="$w/badrepo-names" sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 \
  --scripts-out "$w/scr-badrepo" --updater-app "$APP" 2>"$w/err" \
  && fail "a registry row with a malformed repo must refuse staging an updater"
grep -q "cannot look up openssh in shipyard's registry" "$w/err" \
  || fail "the feed lookup's failure is reported, not silent: [$(cat "$w/err")]"
ol() { _i=0; while _v="$(/usr/libexec/PlistBuddy -c "Print :outside:$_i" "$1" 2>/dev/null)"; do echo "$_v"; _i=$((_i + 1)); done; }
for s in go126 go127; do
  a="$w/lines/$s-updater.app"; mkdir -p "$a/Contents/MacOS"; printf '#!/bin/sh\n' > "$a/Contents/MacOS/$s-updater"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $(sh "$here/../scripts/product-name.sh" updater-bundle-id "$s")" \
    -c "Add :SUFeedURL string $(sh "$here/../scripts/product-name.sh" feed "$s")" "$a/Contents/Info.plist" >/dev/null
  sl="$w/stage-$s"; mkdir -p "$sl/usr/local/mavergreen/$s/bin"; echo go > "$sl/usr/local/mavergreen/$s/bin/go"
  sh "$S" --stage "$sl" --product "$s" --name Go --version 1 --group go --line "${s#go}" \
    --scripts-out "$w/scr-$s" --updater-app "$a" || fail "staging $s with its own updater must succeed"
  ol "$sl/usr/local/mavergreen/$s/mavergreen.plist" > "$w/outside-$s"
done
grep -qx 'Library/Application Support/Mavergreen/go126-updater.app' "$w/outside-go126" \
  || fail "go126's manifest lists its own updater in outside: $(cat "$w/outside-go126")"
[ -z "$(grep -Fxf "$w/outside-go126" "$w/outside-go127")" ] \
  || fail "two lines' manifests share an outside entry, so uninstalling one line would remove the other's updater"
sh -n "$SCRU/preinstall" || fail "generated preinstall (with updater) must be valid sh"
sh -n "$SCRU/postinstall" || fail "generated postinstall (with updater) must be valid sh"
grep -q MAV_AGENT_PLIST "$SCRU/postinstall" \
  || fail "stage_updater's agent-load fragment must land in the postinstall when --updater-app is given"
[ ! -e "$SCRU/.agent-load" ] || fail "the intermediate agent-load snippet must not remain in scripts-out"

sys="$w/sys"; stubs="$w/stubs"; alog="$w/agent.log"
mkdir -p "$sys/Library/LaunchAgents" "$stubs"
: > "$sys/Library/LaunchAgents/dev.mavergreen.openssh-updatecheck.plist"
for c in launchctl sudo; do printf '#!/bin/sh\necho %s "$@" >> "%s"\n' "$c" "$alog" > "$stubs/$c"; done
printf '#!/bin/sh\ncase "$*" in *%%Su*) echo tester ;; *) echo 501 ;; esac\n' > "$stubs/stat"
printf '#!/bin/sh\nexit 0\n' > "$stubs/mavergreen"
chmod +x "$stubs"/*
sed -e "s#/Library/LaunchAgents/#$sys/Library/LaunchAgents/#g" \
    -e "s#^MG=\"\$ROOT/usr/local/bin/mavergreen\"\$#MG=\"$stubs/mavergreen\"#" \
    "$SCRU/postinstall" > "$w/post-redirected"
grep -q "^MAV_AGENT_PLIST=$sys/Library/LaunchAgents/" "$w/post-redirected" \
  || fail "the test must redirect the agent-load's running-system plist path, or it proves nothing"
grep -q "^MG=\"$stubs/mavergreen\"\$" "$w/post-redirected" \
  || fail "the test must stub the helper, or a / install would link on the running system"
Vag="$w/volagent"; mkdir -p "$Vag/Library/LaunchAgents"
: > "$Vag/Library/LaunchAgents/dev.mavergreen.openssh-updatecheck.plist"
: > "$alog"
PATH="$stubs:$PATH" sh "$w/post-redirected" /x.pkg "$Vag/" "$Vag/" || fail "postinstall to another volume must succeed"
[ ! -s "$alog" ] || fail "an install to a volume other than / must never run launchctl or sudo on the running system: $(cat "$alog")"
: > "$alog"
PATH="$stubs:$PATH" sh "$w/post-redirected" /x.pkg / / || fail "postinstall to / must succeed"
grep -q '^launchctl bootstrap gui/501 ' "$alog" \
  || fail "an install to the boot volume loads the update-check agent into the console user's session: [$(cat "$alog")]"

fake="$w/fake"; mkdir -p "$fake"
cp "$S" "$fake/stage_product.sh"
cp "$here/../scripts/product-name.sh" "$here/../scripts/registry-lookup.sh" "$here/../scripts/product-names" "$fake/"
RM_LOG="$w/rm.log"; export RM_LOG
cat > "$fake/render-manifest.sh" <<'EOF'
#!/bin/sh
: > "$RM_LOG"
for a in "$@"; do printf '%s\n' "$a" >> "$RM_LOG"; done
EOF
RMU_LOG="$w/rmu.log"; export RMU_LOG
cat > "$fake/stage_updater.sh" <<'EOF'
#!/bin/sh
set -eu
: > "$RMU_LOG"
prev=""
for a in "$@"; do
  printf '%s\n' "$a" >> "$RMU_LOG"
  if [ "$prev" = --snippet-out ]; then mkdir -p "$(dirname "$a")"; : > "$a"; fi
  prev="$a"
done
EOF
: > "$w/pf-stub-file"
st2="$w/stage2"; mkdir -p "$st2/usr/local/mavergreen/openssh/bin"; echo ssh > "$st2/usr/local/mavergreen/openssh/bin/ssh"
sh "$fake/stage_product.sh" --stage "$st2" --product openssh \
  --name "Open SSH Suite" --version 1.2.3 --group opengrp --line 9 \
  --exclude "bin/extra one" --exclude "share/man/man1/extra.1" \
  --replaces "/usr/bin/ssh=bin/ssh" --replaces "/usr/bin/scp=bin/scp two" \
  --adopts "/etc/sshd_config=sshd_config:config" \
  --scripts-out "$w/scr3" \
  --updater-app "$APP" \
  --requires container-tools \
  --preinstall-hook "$w/hook" --postinstall-hook "$w/hook" \
  --preflight "$w/hook" --preflight-file "$w/pf-stub-file" \
  || fail "stage_product with a stubbed render-manifest/stage_updater must still succeed"
expected="$(printf '%s\n' \
  --stage "$st2" \
  --product openssh \
  --name "Open SSH Suite" \
  --version 1.2.3 \
  --group opengrp \
  --line 9 \
  --exclude "bin/extra one" \
  --exclude "share/man/man1/extra.1" \
  --replaces "/usr/bin/ssh=bin/ssh" \
  --replaces "/usr/bin/scp=bin/scp two" \
  --adopts "/etc/sshd_config=sshd_config:config" \
  --has-updater)"
[ "$(cat "$w/rm.log")" = "$expected" ] \
  || fail "every render-manifest option, in order, with repeats and embedded spaces, must reach render-manifest intact: got [$(cat "$w/rm.log")]"
grep -qE -- '--scripts-out|--updater-app|--app-dir|--agent-label|--preinstall-hook|--postinstall-hook|--requires|--preflight' "$w/rm.log" \
  && fail "a stage_product-only option must never reach render-manifest"
grep -qF "$w/scr3" "$w/rm.log" && fail "a stage_product-only option's VALUE must never reach render-manifest either"
grep -qF "Application Support" "$w/rm.log" && fail "the updater's app-dir value must never reach render-manifest"
grep -qF container-tools "$w/rm.log" && fail "--requires's value must never reach render-manifest either"
grep -qF pf-stub-file "$w/rm.log" && fail "--preflight-file's value must never reach render-manifest either"
[ "$(sed -n '/^--product$/{n;p;}' "$w/rmu.log")" = openssh ] \
  || fail "stage_updater is told the product, and derives the rest: got [$(cat "$w/rmu.log")]"

rc1="$w/rc1"
if run_with_timeout 5 "$rc1" sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out; then
  [ "$(cat "$rc1")" = 2 ] || fail "an option missing its value (at the end of the argument list) must exit 2, got $(cat "$rc1" 2>/dev/null)"
else
  fail "an option missing its value at the end of the argument list must exit promptly, not hang"
fi
rc2="$w/rc2"
if run_with_timeout 5 "$rc2" sh "$S" --stage "$st" --product openssh --name --end --version 1 --scripts-out "$w/scrbad2"; then
  [ "$(cat "$rc2")" = 2 ] || fail "an option value literally --end must exit 2, got $(cat "$rc2" 2>/dev/null)"
else
  fail "an option value literally --end must exit promptly, not hang"
fi

hooknonl="$w/hook-no-nl"
printf 'echo hook-no-nl-ran "$ROOT" >> "$ROOT/hook2.log"' > "$hooknonl"
scrnl="$w/scr-nonl"
sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$scrnl" \
  --preinstall-hook "$hooknonl" --postinstall-hook "$hooknonl" \
  || fail "stage_product must succeed even with a hook lacking a trailing newline"
sh -n "$scrnl/preinstall" || fail "preinstall with a no-trailing-newline hook must still be valid sh"
sh -n "$scrnl/postinstall" || fail "postinstall with a no-trailing-newline hook must still be valid sh"
tail -1 "$scrnl/preinstall" | grep -qx 'exit 0' || fail "preinstall must end with exit 0 on its own line even after a no-trailing-newline hook"
tail -1 "$scrnl/postinstall" | grep -qx 'exit 0' || fail "postinstall must end with exit 0 on its own line even after a no-trailing-newline hook"
Vnl="$w/volnl"; mkdir -p "$Vnl"
sh "$scrnl/preinstall" /x.pkg "$Vnl/" "$Vnl/" || fail "preinstall (no-trailing-newline hook) must still succeed"
grep -q hook-no-nl-ran "$Vnl/hook2.log" || fail "a hook without a trailing newline must still run, not get swallowed into the next line"

Vver="$w/volver"; mkdir -p "$Vver/usr/local/mavergreen"
cp -R "$st/usr/local/mavergreen/openssh" "$Vver/usr/local/mavergreen/"
mkdir -p "$Vver/usr/local/mavergreen/.base/1.0.9" "$Vver/usr/local/mavergreen/.base/1.0.10"
poisonlog="$w/poison.log"
{
  printf '#!/bin/sh\n'
  printf 'echo wrong-version-used >> %s\n' "$poisonlog"
  printf 'exit 1\n'
} > "$Vver/usr/local/mavergreen/.base/1.0.9/mavergreen"
chmod +x "$Vver/usr/local/mavergreen/.base/1.0.9/mavergreen"
sed 's/@MAVERGREEN_VERSION@/1.0.10/' "$here/../scripts/mavergreen.sh" > "$Vver/usr/local/mavergreen/.base/1.0.10/mavergreen"
chmod +x "$Vver/usr/local/mavergreen/.base/1.0.10/mavergreen"
sh "$w/scr/postinstall" /x.pkg "$Vver/" "$Vver/" \
  || fail "postinstall must succeed with only staged helpers present, picking the numerically newest one"
[ ! -f "$poisonlog" ] \
  || fail "postinstall picked the lexically-last staged helper (1.0.9) instead of the numerically newest (1.0.10)"
[ -L "$Vver/usr/local/mavergreen/bin/ssh" ] || fail "postinstall (numeric helper pick) must still link the product"


stg="$w/stage-go"; mkdir -p "$stg/usr/local/mavergreen/go126/bin"; echo go > "$stg/usr/local/mavergreen/go126/bin/go"
sh "$S" --stage "$stg" --product go126 --name "Go 1.26" --version 2 --group go --line 126 --scripts-out "$w/scr-go" \
  || fail "staging a group member must succeed"
Vup="$w/volup"; MGup="$Vup/usr/local/mavergreen"; mkdir -p "$Vup/usr/local/bin" "$MGup/go127/bin"
sed 's/@MAVERGREEN_VERSION@/9.9/' "$here/../scripts/mavergreen.sh" > "$Vup/usr/local/bin/mavergreen"; chmod +x "$Vup/usr/local/bin/mavergreen"
cp -R "$stg/usr/local/mavergreen/go126" "$MGup/"
echo go > "$MGup/go127/bin/go"
/usr/libexec/PlistBuddy -c "Add :product string go127" -c "Add :group string go" -c "Add :line string 127" \
  -c "Add :identifier string dev.mavergreen.go127" -c "Add :version string 1" "$MGup/go127/mavergreen.plist" >/dev/null
sh "$Vup/usr/local/bin/mavergreen" --root "$Vup" link go126; sh "$Vup/usr/local/bin/mavergreen" --root "$Vup" link go127
[ "$(cat "$MGup/var/mavergreen/selections/go")" = go126 ] || fail "fixture: the first member linked is selected"
sh "$w/scr-go/preinstall" /x.pkg "$Vup/" "$Vup/" || fail "the selected member's upgrade preinstall must succeed"
[ -f "$MGup/go126/bin/go" ] || fail "the upgrade preinstall leaves the selected member's files for the payload to be laid over (spec F)"
[ "$(cat "$MGup/var/mavergreen/selections/go")" = go126 ] || fail "an upgrade's preinstall never changes the group's selection"
cp -R "$stg/usr/local/mavergreen/go126" "$MGup/"
sh "$w/scr-go/postinstall" /x.pkg "$Vup/" "$Vup/" || fail "the selected member's upgrade postinstall must succeed"
[ "$(cat "$MGup/var/mavergreen/selections/go")" = go126 ] || fail "upgrading the selected line keeps it selected"
[ "$(readlink "$MGup/bin/go")" = ../go126/bin/go ] || fail "upgrading the selected line keeps its bare names: bin/go is $(readlink "$MGup/bin/go")"
[ "$(readlink "$MGup/bin/go-126")" = ../go126/bin/go ] || fail "upgrading a line puts its versioned names back"
[ "$(readlink "$MGup/bin/go-127")" = ../go127/bin/go ] || fail "upgrading one line leaves another line's links alone"


printf 'if [ -f "$ROOT/usr/local/mavergreen/openssh/bin/ssh" ]; then echo saw-old-tree >> "$ROOT/prehook.log"; else echo tree-gone >> "$ROOT/prehook.log"; fi\n' > "$w/prehook"
sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-pre" --preinstall-hook "$w/prehook" \
  || fail "staging with a preinstall hook must succeed"
Vp="$w/volpre"; MGp="$Vp/usr/local/mavergreen"
mkdir -p "$MGp/openssh/bin" "$MGp/openssh-other" "$MGp/bin"
echo old > "$MGp/openssh/bin/ssh"; echo keep > "$MGp/openssh-other/f"; ln -s ../openssh-other/f "$MGp/bin/f"
mkdir -p "$MGp/openssh/mavergreen.plist"
sh "$w/scr-pre/preinstall" /x.pkg "$Vp" "$Vp" || fail "preinstall must accept a target volume with no trailing slash"
[ ! -e "$MGp/openssh/mavergreen.plist" ] || fail "preinstall removes a path whose kind the payload changes when the volume has no trailing slash"
[ -f "$MGp/openssh/bin/ssh" ] || fail "preinstall keeps a file the payload keeps when the volume has no trailing slash"
[ "$(cat "$Vp/prehook.log")" = saw-old-tree ] || fail "the preinstall hook runs before the tree is removed, so it can use the outgoing version"
[ -f "$MGp/openssh-other/f" ] || fail "preinstall removes only its own tree, never a sibling whose name it prefixes"
[ -L "$MGp/bin/f" ] || fail "preinstall never touches the link farm beyond its own product's links"

stubrm="$w/stubrm"; mkdir -p "$stubrm"; rmlog="$w/rmcalls.log"; : > "$rmlog"
printf '#!/bin/sh\necho rm "$@" >> "%s"\n' "$rmlog" > "$stubrm/rm"; chmod +x "$stubrm/rm"
mkdir -p "$MGp/openssh/bin"; echo old > "$MGp/openssh/bin/ssh"
PATH="$stubrm:$PATH" sh "$w/scr-pre/preinstall" /x.pkg >/dev/null 2>&1 || fail "preinstall with no target volume exits 0"
[ ! -s "$rmlog" ] || fail "preinstall with no target volume removes nothing anywhere: $(cat "$rmlog")"
[ -f "$MGp/openssh/bin/ssh" ] || fail "preinstall with no target volume leaves every tree alone"

if [ "$(id -u)" -eq 0 ]; then
  echo "note: running as root, which ignores directory permissions -- skipping the unremovable-tree case"
else
  mkdir -p "$MGp/openssh/mavergreen.plist/x"
  chmod 555 "$MGp/openssh"
  rc=0; sh "$w/scr/preinstall" /x.pkg "$Vp/" "$Vp/" > "$w/pre-ro.out" 2>&1 || rc=$?
  chmod 755 "$MGp/openssh"
  [ "$rc" -eq 1 ] || fail "a path preinstall cannot remove stops the install, so the payload never lands over it (R51), got exit $rc"
  grep -q 'openssh: could not remove mavergreen.plist' "$w/pre-ro.out" || fail "a path preinstall cannot remove is reported: [$(cat "$w/pre-ro.out")]"
  [ -d "$MGp/openssh/mavergreen.plist" ] || fail "fixture: the unwritable parent must have kept the path"
  rm -rf "$MGp/openssh/mavergreen.plist"
fi

V2="$w/vol-hooks"; T2="$V2/usr/local/mavergreen"; mkdir -p "$V2/usr/local/bin" "$T2"
sed 's/@MAVERGREEN_VERSION@/9.9/' "$here/../scripts/mavergreen.sh" > "$V2/usr/local/bin/mavergreen"
chmod +x "$V2/usr/local/bin/mavergreen"
printf 'false\n' > "$w/hook-false"
printf 'exit 0\n' > "$w/hook-exit"
printf 'if [ -z "$ROOT" ]; then false; fi\n' > "$w/hook-guarded"
mkdir -p "$st/usr/local/mavergreen/openssh/share"; echo note > "$st/usr/local/mavergreen/openssh/share/note"
sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-false" \
  --preinstall-hook "$w/hook-false" --postinstall-hook "$w/hook-false" || fail "staging with failing hooks must succeed"
sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-exit" \
  --preinstall-hook "$w/hook-exit" || fail "staging with an exiting hook must succeed"
sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-guarded" \
  --postinstall-hook "$w/hook-guarded" || fail "staging with a guarded hook must succeed"
cp -R "$st/usr/local/mavergreen/openssh" "$T2/"
"$V2/usr/local/bin/mavergreen" --root "$V2/" link openssh || fail "setup: link the installed version"
rm "$T2/openssh/share/note"; mkdir "$T2/openssh/share/note"
rc=0; sh "$w/scr-false/preinstall" /x.pkg "$V2/" "$V2/" 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "a failing preinstall hook must fail the install -- it is how a preset refuses a missing dependency"
[ -d "$T2/openssh/share/note" ] || fail "a failing preinstall hook must stop the install before anything in the tree is removed"
[ -L "$T2/bin/ssh" ] || fail "a failing preinstall hook must leave the installed version linked, as it was"
grep -q 'preinstall hook failed' "$w/err" || fail "the failure names the preinstall hook: $(cat "$w/err")"
sh "$w/scr-exit/preinstall" /x.pkg "$V2/" "$V2/" || fail "a hook that exits 0 early is not a failure"
[ ! -e "$T2/openssh/share/note" ] || fail "a hook's exit must not skip the removal of a path whose kind changes -- each hook runs in a subshell"
cp -R "$st/usr/local/mavergreen/openssh" "$T2/"
rc=0; sh "$w/scr-false/postinstall" /x.pkg "$V2/" "$V2/" 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "a failing postinstall hook must fail the install, not be masked by the trailing exit 0"
grep -q 'postinstall hook failed' "$w/err" || fail "the failure names the postinstall hook: $(cat "$w/err")"
sh "$w/scr-guarded/postinstall" /x.pkg "$V2/" "$V2/" \
  || fail "a running-system step guarded by if [ -z \$ROOT ] is skipped on another volume, and the hook still succeeds"

printf 'echo inside)\n' > "$w/hook-paren"
printf 'echo "unbalanced\n' > "$w/hook-quote"
for h in hook-paren hook-quote; do
  rc=0; sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-$h" \
    --preinstall-hook "$w/$h" 2>"$w/err" || rc=$?
  [ "$rc" -eq 1 ] || fail "a preinstall hook that is not valid sh must be refused at staging ($h), got exit $rc"
  grep -q "$w/$h" "$w/err" || fail "the refusal names the hook ($h): $(cat "$w/err")"
  rc=0; sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-$h-post" \
    --postinstall-hook "$w/$h" 2>"$w/err" || rc=$?
  [ "$rc" -eq 1 ] || fail "a postinstall hook that is not valid sh must be refused at staging ($h), got exit $rc"
  grep -q "$w/$h" "$w/err" || fail "the refusal names the hook ($h): $(cat "$w/err")"
done

if [ "$(id -u)" -eq 0 ]; then
  echo "note: running as root, which ignores directory permissions -- skipping the failed-relink case"
else
  V3="$w/vol-relink"; T3="$V3/usr/local/mavergreen"; mkdir -p "$V3/usr/local/bin" "$T3"
  cp "$V2/usr/local/bin/mavergreen" "$V3/usr/local/bin/mavergreen"
  printf 'chmod 555 "$ROOT/usr/local/mavergreen/bin"; false\n' > "$w/hook-lockfarm"
  sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-lockfarm" \
    --preinstall-hook "$w/hook-lockfarm" || fail "staging with a farm-locking hook must succeed"
  cp -R "$st/usr/local/mavergreen/openssh" "$T3/"
  "$V3/usr/local/bin/mavergreen" --root "$V3/" link openssh || fail "setup: link the installed version"
  rc=0; sh "$w/scr-lockfarm/preinstall" /x.pkg "$V3/" "$V3/" 2>"$w/err" || rc=$?
  chmod 755 "$T3/bin"
  [ "$rc" -ne 0 ] || fail "a failing preinstall hook fails the install even when the relink fails"
  [ ! -L "$T3/bin/ssh" ] || fail "fixture: the locked farm must have kept the relink out"
  grep -q 'could not relink; run `mavergreen link openssh`' "$w/err" || fail "a failed relink is reported with its remedy: $(cat "$w/err")"
  ! grep -q 'left in place' "$w/err" || fail "a failed relink must not claim the installed version is left in place: $(cat "$w/err")"
fi

printf 'if [ -f "$ROOT/Library/Application Support/Mavergreen/openssh-updater.app/Contents/Stale" ]; then echo saw-old-bundle >> "$ROOT/bundlehook.log"; else echo bundle-gone >> "$ROOT/bundlehook.log"; fi\n' > "$w/bundlehook"
sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-bundle" \
  --updater-app "$APP" --preinstall-hook "$w/bundlehook" || fail "staging with an updater and a preinstall hook must succeed"
mkvol() {
  _v="$1"; rm -rf "$_v" "$_v.out"; mkdir -p "$_v.out/escape.app" "$_v.out/linked/x.app"
  _u="$_v/Library/Application Support/Mavergreen"
  mkdir -p "$_u/openssh-updater.app/Contents" "$_u/other-updater.app" "$_v/Library/LaunchAgents" "$_v/Library/NotABundle" \
    "$_v/usr/local/mavergreen/openssh" "$_v/usr/local/mavergreen/other/x.app"
  : > "$_u/openssh-updater.app/Contents/Stale"; : > "$_u/openssh-updater.app/Contents/Info.plist"
  : > "$_v/Library/LaunchAgents/dev.mavergreen.openssh-updatecheck.plist"; : > "$_v/Library/NotABundle/f"
  ln -s "$_v.out/linked" "$_v/Library/Linked"; ln -s "$_v.out/escape.app" "$_v/Library/Symlinked.app"
}
V4="$w/vol-bundles"; mkvol "$V4"; M4="$V4/usr/local/mavergreen/openssh/mavergreen.plist"
_i=0; /usr/libexec/PlistBuddy -c 'Add :outside array' "$M4" >/dev/null
for o in "Library/Application Support/Mavergreen/openssh-updater.app" "Library/LaunchAgents/dev.mavergreen.openssh-updatecheck.plist" \
  Library/NotABundle ../vol-bundles.out/escape.app "$V4.out/escape.app" Library/Linked/x.app Library/Symlinked.app \
  usr/local/mavergreen/other/x.app "Library/./Application Support/Mavergreen/other-updater.app" "Library/Missing.app"; do
  /usr/libexec/PlistBuddy -c "Add :outside:$_i string $o" "$M4" >/dev/null; _i=$((_i + 1))
done
sh "$w/scr-bundle/preinstall" /x.pkg "$V4/" "$V4/" 2>"$w/err" || fail "a preinstall that clears the installed bundles must succeed: $(cat "$w/err")"
[ "$(cat "$V4/bundlehook.log")" = saw-old-bundle ] \
  || fail "the product's preinstall hook runs before its bundles are cleared, so it can unload a kext first"
[ ! -e "$V4/Library/Application Support/Mavergreen/openssh-updater.app" ] \
  || fail "the installed manifest's updater bundle is cleared, so a file the new version drops cannot break its seal"
[ -f "$V4/Library/LaunchAgents/dev.mavergreen.openssh-updatecheck.plist" ] || fail "a listed file is left for the payload to overwrite"
[ -f "$V4/Library/NotABundle/f" ] || fail "a listed directory that is not a bundle is never cleared"
[ -d "$V4.out/escape.app" ] || fail "an entry that climbs out of the volume is never cleared"
[ -d "$V4.out/linked/x.app" ] || fail "an entry whose parent resolves outside the volume is never cleared"
[ -L "$V4/Library/Symlinked.app" ] || fail "a bundle entry that is a symlink is not a bundle directory, and is left alone"
[ -d "$V4/usr/local/mavergreen/other/x.app" ] || fail "an entry inside the mavergreen tree is never cleared"
[ -d "$V4/Library/Application Support/Mavergreen/other-updater.app" ] || fail "an entry with a ./ component is never cleared"
for nm in missing invalid; do
  V5="$w/vol-$nm"; mkvol "$V5"
  [ "$nm" = missing ] || printf 'not a plist\n' > "$V5/usr/local/mavergreen/openssh/mavergreen.plist"
  sh "$w/scr-bundle/preinstall" /x.pkg "$V5/" "$V5/" 2>"$w/err" || fail "a preinstall with a $nm installed manifest must succeed: $(cat "$w/err")"
  [ -f "$V5/Library/Application Support/Mavergreen/openssh-updater.app/Contents/Stale" ] \
    || fail "with a $nm installed manifest, no bundle is cleared"
done

stp="$w/stage-porthole"; mkdir -p "$stp/usr/local/mavergreen/porthole/bin"
echo porthole > "$stp/usr/local/mavergreen/porthole/bin/porthole"
SCRP="$w/scr-porthole"
sh "$S" --stage "$stp" --product porthole --name Porthole --version 1 --scripts-out "$SCRP" \
  --requires container-tools \
  || fail "staging porthole with --requires container-tools must succeed"
sh -n "$SCRP/preinstall" || fail "generated preinstall with --requires must be valid sh"

Vreq="$w/vol-requires-ok"; mkdir -p "$Vreq/usr/local/mavergreen/container-tools"
: > "$Vreq/usr/local/mavergreen/container-tools/mavergreen.plist"
sh "$SCRP/preinstall" /x.pkg "$Vreq/" "$Vreq/" || fail "preinstall proceeds when the required product's manifest exists"

Vmiss="$w/vol-requires-missing"; mkdir -p "$Vmiss/usr/local/mavergreen/porthole/bin" "$Vmiss/usr/local/bin"
echo old > "$Vmiss/usr/local/mavergreen/porthole/bin/porthole"
mglog="$w/mg-req.log"; : > "$mglog"
printf '#!/bin/sh\necho called "$@" >> "%s"\n' "$mglog" > "$Vmiss/usr/local/bin/mavergreen"
chmod +x "$Vmiss/usr/local/bin/mavergreen"
rc=0; sh "$SCRP/preinstall" /x.pkg "$Vmiss/" "$Vmiss/" 2>"$w/req-err" || rc=$?
[ "$rc" -eq 1 ] || fail "preinstall must exit 1 when a required product is missing, got $rc"
grep -q "Porthole needs container-tools installed first" "$w/req-err" \
  || fail "the refusal names this product's display name and the missing requirement: $(cat "$w/req-err")"
grep -q "https://github.com/Mavergreen/container-tools/releases/latest" "$w/req-err" \
  || fail "the refusal names the missing requirement's releases URL: $(cat "$w/req-err")"
[ -f "$Vmiss/usr/local/mavergreen/porthole/bin/porthole" ] \
  || fail "a missing requirement must leave the existing installed tree untouched"
[ ! -s "$mglog" ] || fail "a missing requirement is checked before mavergreen unlink runs: $(cat "$mglog")"

SCRP2="$w/scr-porthole2"
sh "$S" --stage "$stp" --product porthole --name Porthole --version 1 --scripts-out "$SCRP2" \
  --requires container-tools --requires openssh \
  || fail "staging porthole with two --requires must succeed"
Vtwo="$w/vol-requires-two"; mkdir -p "$Vtwo/usr/local/mavergreen/openssh"
: > "$Vtwo/usr/local/mavergreen/openssh/mavergreen.plist"
rc=0; sh "$SCRP2/preinstall" /x.pkg "$Vtwo/" "$Vtwo/" 2>"$w/req-err2" || rc=$?
[ "$rc" -eq 1 ] || fail "preinstall must exit 1 when one of two requirements is missing, got $rc"
grep -q "container-tools" "$w/req-err2" || fail "the missing requirement (container-tools) must be named: $(cat "$w/req-err2")"
grep -q "openssh" "$w/req-err2" && fail "the satisfied requirement (openssh) must not be named: $(cat "$w/req-err2")"

rc=0; sh "$S" --stage "$stp" --product porthole --name Porthole --version 1 --scripts-out "$w/scr-badreq" \
  --requires nonexistent-product 2>"$w/err" || rc=$?
[ "$rc" -eq 2 ] || fail "staging with an unregistered --requires must exit 2, got $rc"
grep -q nonexistent-product "$w/err" || fail "the refusal names the unregistered requirement: $(cat "$w/err")"

rc=0; sh "$S" --stage "$stp" --product porthole --name Porthole --version 1 --scripts-out "$w/scr-selfreq" \
  --requires porthole 2>"$w/err" || rc=$?
[ "$rc" -eq 2 ] || fail "staging with --requires naming the product itself must exit 2, got $rc"
grep -q porthole "$w/err" || fail "the refusal names the self-requirement: $(cat "$w/err")"
mkdir -p "$w/reqcwd"; : > "$w/reqcwd/container-tools"
rc=0; (cd "$w/reqcwd" && sh "$S" --stage "$stp" --product porthole --name Porthole --version 1 --scripts-out "$w/scr-globreq" \
  --requires 'container-tool?') 2>"$w/err" || rc=$?
[ "$rc" -eq 2 ] && grep -qF "container-tool? is not in shipyard's scripts/product-names" "$w/err" \
  || fail "a --requires value is never expanded as a glob, so container-tool? is unregistered (R72), got $rc: $(cat "$w/err")"

sd="$w/stage-seed"; ts="$sd/usr/local/mavergreen/openssh"; mkdir -p "$ts/share/seed" "$ts/bin"
echo ssh > "$ts/bin/ssh"; echo "Port 22" > "$ts/share/seed/sshd_config"; echo "key me" > "$ts/share/seed/with space"
echo "dangling" > "$ts/share/seed/linked"; echo "x" > "$ts/share/seed/deep"
sh "$S" --stage "$sd" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-seed" \
  --seed "sshd_config=share/seed/sshd_config" --seed "my conf/with space=share/seed/with space" \
  --seed "linked=share/seed/linked" --seed "new/deeper/dir/deep=share/seed/deep" \
  || fail "staging with --seed must succeed"
sh -n "$w/scr-seed/postinstall" || fail "generated postinstall with --seed must be valid sh"
[ "$(/usr/libexec/PlistBuddy -c 'Print' "$sd/usr/local/mavergreen/openssh/mavergreen.plist" | grep -c seed)" -eq 0 ] \
  || fail "--seed is consumed by stage_product and is not a manifest key"
Vs="$w/vol-seed"; Ts="$Vs/usr/local/mavergreen"; mkdir -p "$Ts/.base/9.9" "$Ts/var/openssh" "$w/seed-outside"
sed 's/@MAVERGREEN_VERSION@/9.9/' "$here/../scripts/mavergreen.sh" > "$Ts/.base/9.9/mavergreen"; chmod +x "$Ts/.base/9.9/mavergreen"
cp -R "$sd/usr/local/mavergreen/openssh" "$Ts/"
ln -s "$w/seed-outside/nowhere" "$Ts/var/openssh/linked"
sh "$w/scr-seed/postinstall" /x.pkg "$Vs/" "$Vs/" || fail "postinstall with seeds must succeed"
Vv="$Ts/var/openssh"
[ "$(cat "$Vv/sshd_config")" = "Port 22" ] || fail "an absent var path is seeded from the tree file"
[ "$(cat "$Vv/my conf/with space")" = "key me" ] || fail "a seed path containing a space seeds intact, creating its parent directories"
[ "$(cat "$Vv/new/deeper/dir/deep")" = x ] || fail "a seed several directories deep creates its parents"
want="$(shasum -a 256 < "$Vv/sshd_config")"; want="${want%% *}"
grep -qxF "$want  sshd_config" "$Vv/.mavergreen-seeded" || fail "the seed record has shasum's '<sha256>  <var-rel>' line: $(cat "$Vv/.mavergreen-seeded")"
want="$(shasum -a 256 < "$Vv/my conf/with space")"; want="${want%% *}"
grep -qxF "$want  my conf/with space" "$Vv/.mavergreen-seeded" || fail "a spaced path is recorded whole: $(cat "$Vv/.mavergreen-seeded")"
[ ! -e "$w/seed-outside/nowhere" ] || fail "a dangling symlink at the var path is never written through"
[ -L "$Vv/linked" ] || fail "a var path that is a (dangling) symlink is left as the link it is"
! grep -q ' linked$' "$Vv/.mavergreen-seeded" || fail "a path that was not seeded is not recorded"
echo "Port 2222" > "$Vv/sshd_config"; cp "$Vv/.mavergreen-seeded" "$w/seeded-before"
sh "$w/scr-seed/postinstall" /x.pkg "$Vs/" "$Vs/" || fail "a second postinstall must succeed"
[ "$(cat "$Vv/sshd_config")" = "Port 2222" ] || fail "a second postinstall leaves an edited seed alone"
cmp -s "$Vv/.mavergreen-seeded" "$w/seeded-before" || fail "a second postinstall leaves the seed record unchanged"
rm "$Vv/sshd_config"; echo "Port 22" > "$ts/share/seed/sshd_config"; echo "Port 23" > "$Ts/openssh/share/seed/sshd_config"
sh "$w/scr-seed/postinstall" /x.pkg "$Vs/" "$Vs/" || fail "a re-seed after removal must succeed"
[ "$(grep -c ' sshd_config$' "$Vv/.mavergreen-seeded")" -eq 1 ] || fail "re-seeding replaces the earlier record line for that path"
want="$(shasum -a 256 < "$Vv/sshd_config")"; want="${want%% *}"
grep -qxF "$want  sshd_config" "$Vv/.mavergreen-seeded" || fail "the replacement record carries the new sha256"
want="$(shasum -a 256 < "$Vv/my conf/with space")"; want="${want%% *}"
grep -qxF "$want  my conf/with space" "$Vv/.mavergreen-seeded" || fail "other paths' records survive a re-seed"

Vo="$w/vol-seed-escape"; To="$Vo/usr/local/mavergreen"; mkdir -p "$To/.base/9.9" "$To/var" "$w/seed-escape-out"
cp "$Ts/.base/9.9/mavergreen" "$To/.base/9.9/mavergreen"; cp -R "$sd/usr/local/mavergreen/openssh" "$To/"
ln -s "$w/seed-escape-out" "$To/var/openssh"
rc=0; sh "$w/scr-seed/postinstall" /x.pkg "$Vo/" "$Vo/" 2>/dev/null || rc=$?
[ "$rc" -ne 0 ] || fail "a seed whose var directory resolves outside the volume fails the install"
[ -z "$(ls -A "$w/seed-escape-out")" ] || fail "nothing is written through a symlinked parent out of the volume: $(ls -A "$w/seed-escape-out")"
seedfn="$(awk '/^_seed_one\(\) \{$/,/^}$/' "$w/scr-seed/postinstall")"
[ -n "$seedfn" ] || fail "setup: the generated postinstall defines _seed_one"
Vn="$w/vol-seed-rr"; mkdir -p "$Vn/usr/local/mavergreen/openssh/share/seed" "$Vn/usr/local/mavergreen/var/openssh"
echo x > "$Vn/usr/local/mavergreen/openssh/share/seed/deep"
rc=0; ( ROOT="$Vn"; _seed_rr=""; eval "$seedfn"; _seed_one unresolved share/seed/deep ) 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "a seed is refused when the volume root could not be resolved, rather than passing the escape check (M3)"
[ ! -e "$Vn/usr/local/mavergreen/var/openssh/unresolved" ] || fail "that refusal seeds nothing (M3)"
grep -qF "openssh: not seeding unresolved -- $Vn/ does not resolve to a directory" "$w/err" || fail "that refusal says why (M3): $(cat "$w/err")"
for bad in .mavergreen-seeded .Mavergreen-Seeded; do
  rc=0; sh "$S" --stage "$sd" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-badseed" --seed "$bad=share/seed/deep" 2>"$w/err" || rc=$?
  [ "$rc" -eq 2 ] || fail "--seed $bad=... must be refused at stage time with exit 2, since its own seed record would overwrite it (T2e), got $rc"
  grep -qF "is where the seeds are recorded" "$w/err" || fail "that refusal says why (T2e): $(cat "$w/err")"
done
mkdir -p "$w/globcwd/ok=share/seed"; touch "$w/globcwd/ok=share/seed/dex"
echo expanded > "$ts/share/seed/dex"
rc=0; (cd "$w/globcwd" && sh "$S" --stage "$sd" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-glob" \
  --seed 'ok=share/seed/de?') 2>"$w/err" || rc=$?
[ "$rc" -eq 2 ] || fail "a --seed is never expanded as a glob, so 'share/seed/de?' is not staged and is refused (M10), got $rc"
echo literal > "$ts/share/seed/de?"
(cd "$w/globcwd" && sh "$S" --stage "$sd" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-glob" \
  --seed 'ok=share/seed/de?') 2>"$w/err" || fail "a staged tree path holding ? seeds: $(cat "$w/err")"
grep -qxF "_seed_one 'ok' 'share/seed/de?' || exit 1" "$w/scr-glob/postinstall" \
  || fail "the generated postinstall seeds the tree path as given, never a glob match (M10): $(grep _seed_one "$w/scr-glob/postinstall")"
rm -f "$ts/share/seed/dex" "$ts/share/seed/de?"

for bad in "/abs=share/seed/deep" "../up=share/seed/deep" "a/../b=share/seed/deep" "ok=/abs" "ok=../x" "ok=share/seed/missing" "ok=share/seed" "noequals" "=share/seed/deep" "ok="; do
  rc=0; sh "$S" --stage "$sd" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-badseed" --seed "$bad" 2>"$w/err" || rc=$?
  [ "$rc" -eq 2 ] || fail "--seed '$bad' must be refused at stage time with exit 2, got $rc"
done
ln -s deep "$ts/share/seed/alias"
rc=0; sh "$S" --stage "$sd" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-badseed" --seed "ok=share/seed/alias" 2>"$w/err" || rc=$?
[ "$rc" -eq 2 ] || fail "a tree path that is a symlink is not a staged regular file, got $rc"
rc=0; sh "$S" --stage "$sd" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-badseed" --seed 2>"$w/err" || rc=$?
[ "$rc" -eq 2 ] || fail "--seed with no value is a usage error, got $rc"

sp="$w/stage-rr"; mkdir -p "$sp/usr/local/mavergreen/openssh/bin" "$sp/usr/local/mavergreen/openssh/share"
echo ssh > "$sp/usr/local/mavergreen/openssh/bin/ssh"; echo "Port 22" > "$sp/usr/local/mavergreen/openssh/share/sshd_config"
printf 'echo hook >> "$ROOT/mg.log"\n' > "$w/hook-rr"
sh "$S" --stage "$sp" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-rr" \
  --seed sshd_config=share/sshd_config --postinstall-hook "$w/hook-rr" || fail "staging for the re-replace tests must succeed"
Vr="$w/vol-rr"; Tr="$Vr/usr/local/mavergreen"; mkdir -p "$Tr/.base/9.9" "$Tr/var/openssh"
cp -R "$sp/usr/local/mavergreen/openssh" "$Tr/"
cat > "$Tr/.base/9.9/mavergreen" <<STUB
#!/bin/sh
s=absent; [ -f "$Tr/var/openssh/sshd_config" ] && s=seeded
t=pruned; [ ! -e "$Tr/openssh/stray" ] || t=stray
echo "\$* \$s \$t" >> "$Vr/mg.log"
case "\$*" in *system-replace*) [ -z "\${RR_FAIL:-}" ] || exit 3 ;; esac
exit 0
STUB
chmod +x "$Tr/.base/9.9/mavergreen"
sh "$w/scr-rr/postinstall" /x.pkg "$Vr/" "$Vr/" || fail "the postinstall of a product that was never replaced must succeed"
grep -q system-replace "$Vr/mg.log" && fail "the postinstall must not run system-replace for a product that was never replaced: $(cat "$Vr/mg.log")"
mkdir -p "$Tr/var/system-replace/openssh"; : > "$Tr/var/system-replace/openssh/.replaced"
mkdir -p "$Vr/System/Library/CoreServices"
/usr/libexec/PlistBuddy -c "Add :ProductVersion string 10.9.5" "$Vr/System/Library/CoreServices/SystemVersion.plist" >/dev/null
rm -f "$Tr/var/openssh/sshd_config" "$Tr/var/openssh/.mavergreen-seeded"; : > "$Vr/mg.log"
echo stray > "$Tr/openssh/stray"
sh "$w/scr-rr/postinstall" /x.pkg "$Vr/" "$Vr/" || fail "the postinstall of a replaced product must succeed"
[ "$(cat "$Vr/mg.log")" = "--root $Vr/ link openssh absent pruned
--root $Vr/ system-replace openssh seeded pruned
hook" ] || fail "a replaced product's postinstall prunes, links, seeds, re-runs system-replace, then runs its own hook (R2): $(cat "$Vr/mg.log")"
: > "$Vr/mg.log"; rc=0; RR_FAIL=1 sh "$w/scr-rr/postinstall" /x.pkg "$Vr/" "$Vr/" 2>/dev/null || rc=$?
[ "$rc" -ne 0 ] || fail "a re-replace that fails must fail the install"
grep -q '^hook' "$Vr/mg.log" && fail "a failed re-replace stops the postinstall before the product's own hook: $(cat "$Vr/mg.log")"
/usr/libexec/PlistBuddy -c "Set :ProductVersion 26.0" "$Vr/System/Library/CoreServices/SystemVersion.plist"
: > "$Vr/mg.log"; rc=0; sh "$w/scr-rr/postinstall" /x.pkg "$Vr/" "$Vr/" 2>"$w/err" || rc=$?
[ "$rc" -eq 0 ] || fail "the postinstall of a replaced product on a volume that is no longer 10.9 still succeeds (R44): $(cat "$w/err")"
grep -q system-replace "$Vr/mg.log" && fail "that postinstall does not re-run system-replace off 10.9: $(cat "$Vr/mg.log")"
grep -qxF "openssh: this volume is no longer Mac OS X 10.9; the System Replace was not re-applied" "$w/err" || fail "that postinstall says why it did not re-apply: $(cat "$w/err")"
grep -q '^hook' "$Vr/mg.log" || fail "that postinstall still runs the product's own hook"
_rrl="$(grep -n 'system-replace go126' "$w/scr-go126/postinstall" | cut -d: -f1)"
_agl="$(grep -n MAV_AGENT_PLIST "$w/scr-go126/postinstall" | head -n 1 | cut -d: -f1)"
[ -n "$_rrl" ] && [ -n "$_agl" ] && [ "$_rrl" -lt "$_agl" ] || fail "the re-replace comes before the updater's agent-load snippet (R2)"


stpf="$w/stage-pf"; mkdir -p "$stpf/usr/local/mavergreen/go126/bin"; echo go > "$stpf/usr/local/mavergreen/go126/bin/go"
printf '#!/bin/sh\necho "checked $1"\nif grep -q bad "$1" 2>/dev/null; then echo "$1: bad directive" >&2; exit 1; fi\necho "new binary warns" >&2\nexit 0\n' > "$w/pf-check"
chmod 750 "$w/pf-check"; printf 'data\n' > "$w/pf-data"; chmod 640 "$w/pf-data"
pflog="$w/pf-order.log"
{
  printf 'echo "pf $ROOT $PREFLIGHT_DIR" >> "%s"\n' "$pflog"
  printf '"$PREFLIGHT_DIR/pf-check" "$ROOT/usr/local/mavergreen/var/go126/conf"'
} > "$w/pf-hook"
printf 'echo pre-hook >> "%s"\n' "$pflog" > "$w/pf-prehook"
SCRPF="$w/scr pf"
(umask 077; sh "$S" --stage "$stpf" --product go126 --name "Go 1.26" --version 3 --group go --line 126 --scripts-out "$SCRPF" \
  --preflight "$w/pf-hook" --preflight-file "$w/pf-check" --preflight-file "$w/pf-data" --preinstall-hook "$w/pf-prehook") \
  || fail "staging with --preflight and --preflight-file must succeed"
sh -n "$SCRPF/preinstall" || fail "generated preinstall with a preflight must be valid sh"
[ "$(stat -f %Lp "$SCRPF/preflight/pf-check")" = 750 ] && [ "$(stat -f %Lp "$SCRPF/preflight/pf-data")" = 640 ] \
  || fail "each --preflight-file is copied into scripts-out/preflight/ with its mode, so the new binary stays executable"
cmp -s "$w/pf-check" "$SCRPF/preflight/pf-check" || fail "a preflight file is copied byte for byte"
Vpf="$w/vol-pf"; Mpf="$Vpf/usr/local/mavergreen"; mkdir -p "$Vpf/usr/local/bin" "$Mpf/go127/bin" "$Mpf/var/go126"
sed 's/@MAVERGREEN_VERSION@/9.9/' "$here/../scripts/mavergreen.sh" > "$Vpf/usr/local/bin/mavergreen"; chmod +x "$Vpf/usr/local/bin/mavergreen"
cp -R "$stg/usr/local/mavergreen/go126" "$Mpf/"
echo go > "$Mpf/go127/bin/go"
/usr/libexec/PlistBuddy -c "Add :product string go127" -c "Add :group string go" -c "Add :line string 127" \
  -c "Add :identifier string dev.mavergreen.go127" -c "Add :version string 1" "$Mpf/go127/mavergreen.plist" >/dev/null
sh "$Vpf/usr/local/bin/mavergreen" --root "$Vpf" link go126; sh "$Vpf/usr/local/bin/mavergreen" --root "$Vpf" link go127
echo "bad line" > "$Mpf/var/go126/conf"
[ "$(cat "$Mpf/var/mavergreen/selections/go")" = go126 ] && [ "$(readlink "$Mpf/bin/go")" = ../go126/bin/go ] \
  || fail "fixture: go126 is installed, linked and selected"
ls -lRT "$Vpf" > "$w/pf-before"
: > "$pflog"; rc=0; sh "$SCRPF/preinstall" /x.pkg "$Vpf/" "$Vpf/" > "$w/pf.out" 2> "$w/pf.err" || rc=$?
ls -lRT "$Vpf" > "$w/pf-after"
[ "$rc" -eq 1 ] || fail "a preinstall whose preflight rejects the live config exits 1, got $rc: $(cat "$w/pf.err")"
[ "$(head -n 1 "$w/pf.err")" = "go126: the new version cannot use this Mac's configuration; nothing was changed" ] \
  || fail "the refusal says the new version cannot use this Mac's configuration, first: $(cat "$w/pf.err")"
sed -n '2,$p' "$w/pf.err" | grep -qxF "$Mpf/var/go126/conf: bad directive" \
  || fail "the hook's stderr follows the refusal: $(cat "$w/pf.err")"
grep -qxF "checked $Mpf/var/go126/conf" "$w/pf.out" || fail "the hook's stdout is passed through, not lost: [$(cat "$w/pf.out")]"
[ -f "$Mpf/go126/bin/go" ] || fail "a failing preflight leaves the installed tree"
[ "$(readlink "$Mpf/bin/go")" = ../go126/bin/go ] && [ "$(readlink "$Mpf/bin/go-126")" = ../go126/bin/go ] \
  || fail "a failing preflight leaves the installed version's farm links"
[ "$(cat "$Mpf/var/mavergreen/selections/go")" = go126 ] || fail "a failing preflight leaves the group's selection"
[ "$(cat "$Mpf/var/go126/conf")" = "bad line" ] || fail "a failing preflight leaves var alone"
cmp -s "$w/pf-before" "$w/pf-after" || fail "a failing preflight changes nothing on the volume: $(diff "$w/pf-before" "$w/pf-after")"
[ "$(cat "$pflog")" = "pf $Vpf $(cd "$SCRPF" && pwd)/preflight" ] \
  || fail "the preflight runs before the product's preinstall hook, which a refusal never reaches: [$(cat "$pflog")]"
echo "fine" > "$Mpf/var/go126/conf"
rm "$Mpf/go126/bin/go"; mkdir "$Mpf/go126/bin/go"
: > "$pflog"; rc=0; sh "$SCRPF/preinstall" /x.pkg "$Vpf/" "$Vpf/" > "$w/pf.out" 2> "$w/pf.err" || rc=$?
[ "$rc" -eq 0 ] || fail "a preinstall whose preflight passes goes on and succeeds, got $rc: $(cat "$w/pf.err")"
[ "$(cat "$pflog")" = "pf $Vpf $(cd "$SCRPF" && pwd)/preflight
pre-hook" ] || fail "a passing preflight sees ROOT and PREFLIGHT_DIR (scripts-out/preflight), then the preinstall goes on: [$(cat "$pflog")]"
grep -qxF "new binary warns" "$w/pf.err" || fail "a passing preflight's stderr is passed through, not lost: [$(cat "$w/pf.err")]"
grep -q 'cannot use' "$w/pf.err" && fail "a passing preflight is not reported as a refusal: $(cat "$w/pf.err")"
[ ! -e "$Mpf/go126/bin/go" ] && [ -f "$Mpf/go126/mavergreen.plist" ] \
  || fail "after a passing preflight the preinstall does its usual steps, removing a path whose kind the payload changes"

printf 'echo pf-said-no >&2; exit 1\n' > "$w/pf-no"; printf 'exit 0\n' > "$w/pf-yes"
Vpq="$w/vol-pf-req"; mkdir -p "$Vpq/usr/local/bin"; pqlog="$w/pf-req-mg.log"; : > "$pqlog"
printf '#!/bin/sh\necho called "$@" >> "%s"\n' "$pqlog" > "$Vpq/usr/local/bin/mavergreen"; chmod +x "$Vpq/usr/local/bin/mavergreen"
sh "$S" --stage "$stp" --product porthole --name Porthole --version 1 --scripts-out "$w/scr-pf-no" \
  --requires container-tools --preflight "$w/pf-no" || fail "staging --preflight with --requires must succeed"
rc=0; sh "$w/scr-pf-no/preinstall" /x.pkg "$Vpq/" "$Vpq/" 2> "$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "a failing preflight with a missing requirement exits 1, got $rc"
grep -q 'porthole: the new version cannot use' "$w/err" && grep -qx pf-said-no "$w/err" \
  && ! grep -q 'needs container-tools' "$w/err" \
  || fail "the preflight runs before a missing --requires is reported: $(cat "$w/err")"
[ ! -s "$pqlog" ] || fail "the preflight runs before mavergreen unlink: $(cat "$pqlog")"
rc=0; TMPDIR="$w/no-such-tmpdir" sh "$w/scr-pf-no/preinstall" /x.pkg "$Vpq/" "$Vpq/" 2> "$w/err" || rc=$?
[ "$rc" -eq 1 ] && grep -q 'porthole: cannot make a temporary file for the preflight; nothing was changed' "$w/err" \
  && ! grep -q 'cannot use' "$w/err" && [ ! -s "$pqlog" ] \
  || fail "a preflight that cannot capture its stderr stops the install, saying why, before any change: $rc $(cat "$w/err")"
sh "$S" --stage "$stp" --product porthole --name Porthole --version 1 --scripts-out "$w/scr-pf-yes" \
  --requires container-tools --preflight "$w/pf-yes" || fail "staging a preflight that exits must succeed"
rc=0; sh "$w/scr-pf-yes/preinstall" /x.pkg "$Vpq/" "$Vpq/" 2> "$w/err" || rc=$?
[ "$rc" -eq 1 ] && grep -q 'needs container-tools' "$w/err" \
  || fail "a preflight's exit 0 ends only its subshell, so the preinstall still checks --requires: $rc $(cat "$w/err")"
sh "$S" --stage "$stp" --product porthole --name Porthole --version 1 --scripts-out "$w/scr-pf-yes" \
  || fail "restaging without --preflight must succeed"
[ ! -e "$w/scr-pf-yes/preflight" ] || fail "restaging without --preflight leaves no stale preflight directory to ship"
grep -q PREFLIGHT_DIR "$w/scr-pf-yes/preinstall" && fail "a product with no --preflight gets no preflight block"
sh "$S" --stage "$stp" --product porthole --name Porthole --version 1 --scripts-out "$w/scr-pf-yes" \
  --preflight "$w/pf-yes" --preflight-file "$w/pf-check" || fail "staging with one preflight file must succeed"
sh "$S" --stage "$stp" --product porthole --name Porthole --version 1 --scripts-out "$w/scr-pf-yes" \
  --preflight "$w/pf-yes" --preflight-file "$w/pf-data" || fail "restaging with another preflight file must succeed"
[ "$(ls "$w/scr-pf-yes/preflight")" = pf-data ] || fail "restaging replaces the preflight directory, leaving no stale file: $(ls "$w/scr-pf-yes/preflight")"

mkdir -p "$w/pf-other" "$w/g"; printf 'x\n' > "$w/pf-other/pf-data"; echo one > "$w/g/sshd1"; echo two > "$w/g/sshd2"
for bad in hookparen hookmissing filemissing filedir twice samebase fileonly newline glob; do
  case "$bad" in
    hookparen) set -- --preflight "$w/hook-paren"
      want=1; msg="stage_product: preflight hook $w/hook-paren is not valid sh; refusing to stage" ;;
    hookmissing) set -- --preflight "$w/no-such-hook"
      want=2; msg="stage_product: preflight hook $w/no-such-hook is not a file; refusing to stage" ;;
    filemissing) set -- --preflight "$w/pf-yes" --preflight-file "$w/no-such-file"
      want=2; msg="stage_product: --preflight-file $w/no-such-file is not a file; refusing to stage" ;;
    filedir) set -- --preflight "$w/pf-yes" --preflight-file "$w/pf-other"
      want=2; msg="stage_product: --preflight-file $w/pf-other is not a file; refusing to stage" ;;
    twice) set -- --preflight "$w/pf-yes" --preflight "$w/pf-yes"
      want=2; msg="stage_product: --preflight is given twice; a product has one preflight hook" ;;
    samebase) set -- --preflight "$w/pf-yes" --preflight-file "$w/pf-data" --preflight-file "$w/pf-other/pf-data"
      want=2; msg="stage_product: --preflight-file $w/pf-other/pf-data: another preflight file is also named pf-data, and both would be preflight/pf-data" ;;
    fileonly) set -- --preflight-file "$w/pf-data"
      want=2; msg="stage_product: --preflight-file needs --preflight, the hook that runs it" ;;
    newline) set -- --preflight "$w/pf-yes" --preflight-file "$w/pf-data
$w/pf-check"
      want=2; msg="contains a newline, which the file list cannot carry; rename the file" ;;
    glob) set -- --preflight "$w/pf-yes" --preflight-file "$w/g/sshd[12]"
      want=2; msg="stage_product: --preflight-file $w/g/sshd[12] is not a file; refusing to stage" ;;
  esac
  rm -rf "$w/scr-pf-bad"; rc=0
  sh "$S" --stage "$stp" --product porthole --name Porthole --version 1 --scripts-out "$w/scr-pf-bad" "$@" 2>"$w/err" || rc=$?
  [ "$rc" -eq "$want" ] || fail "staging must refuse a bad preflight ($bad) with exit $want, got $rc: $(cat "$w/err")"
  grep -qF -- "$msg" "$w/err" || fail "the refusal of a bad preflight ($bad) says why, naming it: [$(cat "$w/err")]"
  [ ! -e "$w/scr-pf-bad" ] || fail "a bad preflight ($bad) is refused before anything is written"
done
echo literal > "$w/g/sshd[1]"
sh "$S" --stage "$stp" --product porthole --name Porthole --version 1 --scripts-out "$w/scr-glob" \
  --preflight "$w/pf-yes" --preflight-file "$w/g/sshd[1]" || fail "a preflight file whose name holds glob characters stages"
[ "$(ls "$w/scr-glob/preflight")" = "sshd[1]" ] && [ "$(cat "$w/scr-glob/preflight/sshd[1]")" = literal ] \
  || fail "a preflight file is copied by its literal name, never glob-expanded to a sibling: $(ls "$w/scr-glob/preflight")"
printf 'cat <<fi\n' > "$w/pf-heredoc"
sh -n "$w/pf-heredoc" 2>/dev/null || fail "fixture: an unterminated heredoc passes sh -n on its own"
rc=0; sh "$S" --stage "$stp" --product porthole --name Porthole --version 1 --scripts-out "$w/scr-pf-hd" \
  --preflight "$w/pf-heredoc" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "a preflight hook that breaks the generated preinstall is refused at staging, got $rc"
grep -qF "preflight hook $w/pf-heredoc" "$w/err" && ! grep -q 'none none' "$w/err" \
  || fail "the refusal of a broken generated script names the preflight hook that went into it: [$(cat "$w/err")]"

pfe() {
  _h="$1"; shift
  sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-pfe" --preflight "$_h" >/dev/null 2>&1 \
    || fail "staging the preflight $_h must succeed"
  rm -rf "$w/vol-pfe"; mkdir -p "$w/vol-pfe/usr/local/mavergreen/openssh/bin" "$w/vol-pfe/usr/local/mavergreen/openssh/share/note"
  echo old > "$w/vol-pfe/usr/local/mavergreen/openssh/bin/ssh"
  rc=0; "$@" "$w/scr-pfe/preinstall" /x.pkg "$w/vol-pfe/" "$w/vol-pfe/" > "$w/out" 2> "$w/err" || rc=$?
}
pfref="openssh: the new version cannot use this Mac's configuration; nothing was changed"
printf 'set -e\nfalse\necho checked-ok\n' > "$w/pf-sete"
pfe "$w/pf-sete" sh
[ "$rc" -eq 1 ] && [ "$(head -n 1 "$w/err")" = "$pfref" ] && ! grep -q checked-ok "$w/out" \
  || fail "a preflight that sets -e stops at its first failure, and the preinstall refuses (R47): $rc [$(cat "$w/out")] [$(cat "$w/err")]"
[ -d "$w/vol-pfe/usr/local/mavergreen/openssh/share/note" ] || fail "a set -e preflight that fails leaves the installed tree (R47)"
printf 'echo checking\nfalse\n' > "$w/pf-last"
pfe "$w/pf-last" sh
[ "$rc" -eq 1 ] && [ "$(head -n 1 "$w/err")" = "$pfref" ] && [ -d "$w/vol-pfe/usr/local/mavergreen/openssh/share/note" ] \
  || fail "a preflight whose last command fails refuses the install, leaving the tree: $rc [$(cat "$w/err")]"
printf 'false\necho fine\n' > "$w/pf-notlast"
pfe "$w/pf-notlast" sh
[ "$rc" -eq 0 ] && [ ! -e "$w/vol-pfe/usr/local/mavergreen/openssh/share/note" ] \
  || fail "without set -e a preflight's status is its last command's, so a failed earlier command does not refuse: $rc [$(cat "$w/err")]"
for _esh in sh /bin/ksh /bin/dash; do
  case "$_esh" in /*) [ -x "$_esh" ] || continue ;; esac
  pfe "$w/pf-notlast" "$_esh" -e
  [ "$rc" -eq 1 ] && [ "$(head -n 1 "$w/err")" = "$pfref" ] && [ -d "$w/vol-pfe/usr/local/mavergreen/openssh/share/note" ] \
    || fail "a preinstall run with errexit ($_esh -e) passes it to the preflight, and still says why it refuses (R47): $rc [$(cat "$w/err")]"
done
printf 'case "$-" in *e*) echo errexit-on ;; *) echo errexit-off ;; esac >> "%s"\n' "$w/pf-opts.log" > "$w/pf-optshook"
sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-pfo" \
  --preflight "$w/pf-yes" --preinstall-hook "$w/pf-optshook" || fail "staging a preflight with an options-reporting preinstall hook must succeed"
for _eo in "sh -e:errexit-on" "sh:errexit-off"; do
  rm -rf "$w/vol-pfo"; mkdir -p "$w/vol-pfo"; : > "$w/pf-opts.log"
  ${_eo%%:*} "$w/scr-pfo/preinstall" /x.pkg "$w/vol-pfo/" "$w/vol-pfo/" 2>/dev/null || fail "a passing preflight under ${_eo%%:*} lets the preinstall succeed"
  [ "$(cat "$w/pf-opts.log")" = "${_eo#*:}" ] \
    || fail "after the preflight the preinstall runs with the errexit it was started with (${_eo%%:*}): $(cat "$w/pf-opts.log")"
done

tab="$(printf '\t')"
shape() { (cd "$1" && { find . -type l | sed 's/^/l /'; find . -type f | sed 's/^/f /'; find . -type d | sed 's/^/d /'; } | LC_ALL=C sort); }
fnew="$w/f-new"; Fn="$fnew/usr/local/mavergreen/openssh"
mkdir -p "$Fn/bin" "$Fn/lib/thing" "$Fn/lib/ldir" "$Fn/etc" "$Fn/share" "$Fn/plugins/Foo.bundle/Contents" "$Fn/var-empty" "$Fn/g*lob" "$Fn/sp ace"
echo ssh2 > "$Fn/bin/ssh"; echo ab2 > "$Fn/bin/a b"; echo inner > "$Fn/lib/thing/inner"; echo conf > "$Fn/etc/conf"; echo alias > "$Fn/lib/alias"
echo in > "$Fn/lib/ldir/in"; echo k > "$Fn/g*lob/k"; echo fx > "$Fn/sp ace/f [x]"
ln -s ../bin/ssh "$Fn/share/doc"; ln -s ../bin "$Fn/share/x"; echo info2 > "$Fn/plugins/Foo.bundle/Contents/Info.plist"
echo untouched > "$w/f-stale-target"; ln -s "$w/f-stale-target" "$Fn/.mavergreen-payload"
sh "$S" --stage "$fnew" --product openssh --name OpenSSH --version 2 --scripts-out "$w/scr-f" || fail "staging the new version must succeed"
[ "$(cat "$w/f-stale-target")" = untouched ] && [ -f "$Fn/.mavergreen-payload" ] && [ ! -L "$Fn/.mavergreen-payload" ] \
  || fail "a stale payload list in the stage that is a link is replaced, never written through"
[ "$(cat "$Fn/.mavergreen-payload")" = "d${tab}bin
f${tab}bin/a b
f${tab}bin/ssh
d${tab}etc
f${tab}etc/conf
d${tab}g*lob
f${tab}g*lob/k
d${tab}lib
f${tab}lib/alias
d${tab}lib/ldir
f${tab}lib/ldir/in
d${tab}lib/thing
f${tab}lib/thing/inner
f${tab}mavergreen.plist
d${tab}plugins
b${tab}plugins/Foo.bundle
d${tab}plugins/Foo.bundle/Contents
f${tab}plugins/Foo.bundle/Contents/Info.plist
d${tab}share
l${tab}share/doc
l${tab}share/x
d${tab}sp ace
f${tab}sp ace/f [x]
d${tab}var-empty" ] || fail "the tree's payload list names every staged path with its kind, sorted by path, never itself (spec F): [$(cat "$Fn/.mavergreen-payload")]"
cmp -s "$Fn/.mavergreen-payload" "$w/scr-f/.mavergreen-payload" || fail "scripts-out carries the same payload list, for the preinstall to read"
[ ! -e "$w/scr-f/preflight/.mavergreen-payload" ] || fail "the payload list sits beside the preinstall, never in the preflight directory"
sdd="$w/stage-staledir"; mkdir -p "$sdd/usr/local/mavergreen/openssh/bin" "$sdd/usr/local/mavergreen/openssh/.mavergreen-payload"
echo ssh > "$sdd/usr/local/mavergreen/openssh/bin/ssh"
rc=0; sh "$S" --stage "$sdd" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-staledir" 2>"$w/err" || rc=$?
[ "$rc" -eq 2 ] && grep -qF "openssh/.mavergreen-payload is a directory" "$w/err" && [ ! -e "$w/scr-staledir" ] \
  || fail "a stale payload list in the stage that is a directory is refused before anything is written: $rc [$(cat "$w/err")]"
stb="$w/stubs-pl"; mkdir -p "$stb"
printf '#!/bin/sh\ncase "$*" in *-mindepth*) /usr/bin/find "$@"; exit 1 ;; esac\nexec /usr/bin/find "$@"\n' > "$stb/find"
printf '#!/bin/sh\n[ -z "${PL_TREE:-}" ] || { /usr/bin/awk "$@"; exit 1; }\nexec /usr/bin/awk "$@"\n' > "$stb/awk"
printf '#!/bin/sh\ncase "$*" in *-k2,2*) /usr/bin/sort "$@"; exit 1 ;; esac\nexec /usr/bin/sort "$@"\n' > "$stb/sort"
for t in find awk sort; do
  rm -rf "$stb/on" "$w/scr-plfail"; mkdir -p "$stb/on"; cp "$stb/$t" "$stb/on/$t"; chmod +x "$stb/on/$t"
  rc=0; PATH="$stb/on:$PATH" sh "$S" --stage "$fnew" --product openssh --name OpenSSH --version 2 --scripts-out "$w/scr-plfail" 2>"$w/err" || rc=$?
  [ "$rc" -eq 1 ] && grep -qF "stage_product: could not list the payload under $Fn ($t failed); refusing to stage" "$w/err" \
    && [ ! -e "$w/scr-plfail/.mavergreen-payload" ] && [ ! -e "$w/scr-plfail/preinstall" ] \
    || fail "a failing $t while listing the payload refuses staging, shipping no partial list: $rc [$(cat "$w/err")]"
done
cmp -s "$Fn/.mavergreen-payload" "$w/scr-f/.mavergreen-payload" || fail "a refused restage leaves the tree's payload list as it was"
Vf="$w/vol-f"; Tf="$Vf/usr/local/mavergreen/openssh"
mkf() {
  chmod -R u+w "$Vf" 2>/dev/null || true; rm -rf "$Vf"
  mkdir -p "$Tf/bin" "$Tf/lib" "$Tf/etc/conf" "$Tf/share/old-only" "$Tf/share/x" "$Tf/old/deep/er" "$Tf/plugins/Foo.bundle/Contents" "$Vf/usr/local/bin" \
    "$Tf/g*lob" "$Tf/gXlob" "$Tf/sp ace/f [x]"
  echo ssh1 > "$Tf/bin/ssh"; echo dropped > "$Tf/bin/dropped"; echo thing > "$Tf/lib/thing"; echo a > "$Tf/etc/conf/a"
  ln -s thing "$Tf/lib/alias"; echo doc > "$Tf/share/doc"; echo x > "$Tf/share/old-only/x"; echo f > "$Tf/old/deep/er/f"
  echo info1 > "$Tf/plugins/Foo.bundle/Contents/Info.plist"; echo stale > "$Tf/plugins/Foo.bundle/Contents/Stale"; echo old > "$Tf/mavergreen.plist"
  echo ab1 > "$Tf/bin/a b"; echo st > "$Tf/bin/s t*"; echo k1 > "$Tf/g*lob/k"; echo k2 > "$Tf/gXlob/k2"; echo y > "$Tf/share/x/y"
  echo z > "$Tf/sp ace/f [x]/z"; ln -s ../bin "$Tf/lib/ldir"; mkdir "$Tf/bin/in"
  printf '#!/bin/sh\nexit 0\n' > "$Vf/usr/local/bin/mavergreen"; chmod +x "$Vf/usr/local/bin/mavergreen"
}
mkf
_ino="$(ls -i "$Tf/bin/ssh")"
sh "$w/scr-f/preinstall" /x.pkg "$Vf/" "$Vf/" 2>"$w/err" || fail "the upgrade preinstall must succeed: $(cat "$w/err")"
[ "$(cat "$Tf/bin/ssh" 2>/dev/null)" = ssh1 ] && [ "$(ls -i "$Tf/bin/ssh")" = "$_ino" ] \
  || fail "a file the new version keeps is never absent between the preinstall and the postinstall (spec F)"
[ -f "$Tf/mavergreen.plist" ] || fail "the manifest the new version keeps is never absent after the preinstall"
[ ! -e "$Tf/lib/thing" ] || fail "the preinstall removes a file the payload turns into a directory"
[ ! -e "$Tf/etc/conf" ] || fail "the preinstall removes a directory the payload turns into a file"
[ ! -e "$Tf/lib/alias" ] && [ ! -L "$Tf/lib/alias" ] || fail "the preinstall removes a link the payload turns into a file, never writing through it"
[ ! -e "$Tf/share/doc" ] || fail "the preinstall removes a file the payload turns into a link"
[ ! -e "$Tf/share/x" ] || fail "the preinstall removes a directory the payload turns into a link"
[ ! -e "$Tf/lib/ldir" ] && [ ! -L "$Tf/lib/ldir" ] && [ -f "$Tf/bin/ssh" ] && [ -d "$Tf/bin/in" ] || fail "the preinstall removes a link the payload turns into a directory, never writing through it"
[ ! -e "$Tf/sp ace/f [x]" ] || fail "the preinstall removes a path named with spaces and glob characters whose kind changes"
[ "$(cat "$Tf/bin/a b")" = ab1 ] && [ -f "$Tf/g*lob/k" ] && [ -f "$Tf/bin/s t*" ] && [ -f "$Tf/gXlob/k2" ] \
  || fail "the preinstall keeps paths named with spaces and glob characters, and their look-alike strays, for the payload and the prune"
[ ! -e "$Tf/plugins/Foo.bundle" ] && [ -d "$Tf/plugins" ] || fail "a bundle inside the tree is cleared before the payload, so a dropped file cannot break its seal (spec F)"
[ -f "$Tf/bin/dropped" ] && [ -f "$Tf/old/deep/er/f" ] || fail "the preinstall removes only what the payload cannot be laid over; a dropped file waits for the postinstall"
[ ! -s "$w/err" ] || fail "a clean upgrade preinstall says nothing: $(cat "$w/err")"
cp -R "$Fn" "$Vf/usr/local/mavergreen/" 2>"$w/err" || fail "a path that changes kind (between file, directory and link) installs cleanly over the old tree (spec F): $(cat "$w/err")"
[ "$(cat "$Tf/lib/thing/inner")" = inner ] || fail "a path that changed from file to directory holds the payload's file"
sh "$w/scr-f/postinstall" /x.pkg "$Vf/" "$Vf/" 2>"$w/err" || fail "the upgrade postinstall must succeed: $(cat "$w/err")"
[ ! -e "$Tf/bin/dropped" ] || fail "a file dropped by the new version is gone after preinstall, payload and postinstall (spec F)"
[ ! -e "$Tf/old" ] && [ ! -e "$Tf/share/old-only" ] || fail "the postinstall removes directories the prune leaves empty, bottom-up"
[ -d "$Tf/var-empty" ] || fail "an empty directory the payload carries is kept"
[ ! -e "$Tf/bin/s t*" ] && [ ! -e "$Tf/gXlob" ] && [ "$(cat "$Tf/bin/a b")" = ab2 ] && [ -f "$Tf/g*lob/k" ] \
  || fail "the prune removes strays named with spaces and glob characters, and only them"
[ "$(shape "$Tf")" = "$(shape "$Fn")" ] || fail "after the upgrade the tree is exactly the new payload: $(shape "$Tf" | tr '\n' ' ')"
sh "$w/scr-f/postinstall" /x.pkg "$Vf/" "$Vf/" 2>"$w/err" && [ "$(shape "$Tf")" = "$(shape "$Fn")" ] \
  || fail "a postinstall run again finds nothing more to prune and succeeds: $(cat "$w/err")"
rm -rf "$w/scr-f-nomf"; cp -R "$w/scr-f" "$w/scr-f-nomf"
grep -v "${tab}mavergreen.plist\$" "$w/scr-f/.mavergreen-payload" > "$w/scr-f-nomf/.mavergreen-payload"; cp "$w/scr-f-nomf/.mavergreen-payload" "$Tf/.mavergreen-payload"
sh "$w/scr-f-nomf/postinstall" /x.pkg "$Vf/" "$Vf/" 2>"$w/err" || fail "a postinstall whose list omits the manifest must succeed: $(cat "$w/err")"
[ -f "$Tf/mavergreen.plist" ] && [ -f "$Tf/.mavergreen-payload" ] || fail "the prune never removes the manifest or the payload list"
plskip="openssh: the installed tree's payload list is missing, empty or not this package's; nothing was pruned"
echo stray > "$Tf/stray-e"; : > "$Tf/.mavergreen-payload"
rc=0; sh "$w/scr-f/postinstall" /x.pkg "$Vf/" "$Vf/" 2>"$w/err" || rc=$?
[ "$rc" -eq 0 ] && [ -f "$Tf/bin/ssh" ] && [ -f "$Tf/stray-e" ] && grep -qF "$plskip" "$w/err" \
  || fail "an empty payload list in the tree prunes nothing, says so, and the install goes on: $rc [$(cat "$w/err")]"
sed '$d' "$w/scr-f/.mavergreen-payload" > "$Tf/.mavergreen-payload"
rc=0; sh "$w/scr-f/postinstall" /x.pkg "$Vf/" "$Vf/" 2>"$w/err" || rc=$?
[ "$rc" -eq 0 ] && [ -d "$Tf/var-empty" ] && [ -f "$Tf/stray-e" ] && grep -qF "$plskip" "$w/err" \
  || fail "a payload list in the tree truncated by a line prunes nothing, says so, and the install goes on: $rc [$(cat "$w/err")]"
rm -rf "$w/scr-f-empty"; cp -R "$w/scr-f" "$w/scr-f-empty"; : > "$w/scr-f-empty/.mavergreen-payload"; : > "$Tf/.mavergreen-payload"
rc=0; sh "$w/scr-f-empty/postinstall" /x.pkg "$Vf/" "$Vf/" 2>"$w/err" || rc=$?
[ "$rc" -eq 0 ] && [ -f "$Tf/bin/ssh" ] && [ -f "$Tf/stray-e" ] && grep -qF "$plskip" "$w/err" \
  || fail "an empty payload list prunes nothing even when the package's own copy is empty too: $rc [$(cat "$w/err")]"

mkf
sh "$w/scr-f/preinstall" /x.pkg "$Vf/" "$Vf/" 2>/dev/null || fail "crash case: the first preinstall must succeed"
mkdir -p "$Tf/lib/thing" "$Tf/share"; echo inner > "$Tf/lib/thing/inner"; echo ssh2 > "$Tf/bin/ssh"
sh "$w/scr-f/preinstall" /x.pkg "$Vf/" "$Vf/" 2>"$w/err" || fail "a preinstall after an install killed mid-payload must succeed: $(cat "$w/err")"
[ "$(cat "$Tf/bin/ssh")" = ssh2 ] && [ -f "$Tf/lib/thing/inner" ] || fail "a preinstall after a killed install keeps what the payload already laid down"
cp -R "$Fn" "$Vf/usr/local/mavergreen/" && sh "$w/scr-f/postinstall" /x.pkg "$Vf/" "$Vf/" 2>"$w/err" \
  || fail "the next install after one killed between preinstall and postinstall succeeds: $(cat "$w/err")"
[ "$(shape "$Tf")" = "$(shape "$Fn")" ] || fail "the next install after a killed one leaves exactly the new payload"

mglogger() { printf '#!/bin/sh\necho called "$@" >> "%s"\n' "$2" > "$1"; chmod +x "$1"; : > "$2"; }
Vfn="$w/vol-f-nolist"; mkdir -p "$Vfn/usr/local/mavergreen/openssh/share/note" "$Vfn/usr/local/bin" "$w/scr-f-nolist"
cp "$w/scr-f/preinstall" "$w/scr-f-nolist/"; nllog="$w/nolist-mg.log"; mglogger "$Vfn/usr/local/bin/mavergreen" "$nllog"
ls -lRT "$Vfn" > "$w/nl-before"
rc=0; sh "$w/scr-f-nolist/preinstall" /x.pkg "$Vfn/" "$Vfn/" 2>"$w/err" || rc=$?
ls -lRT "$Vfn" > "$w/nl-after"
[ "$rc" -eq 1 ] && grep -qF "openssh: the payload list is missing beside $w/scr-f-nolist/preinstall; nothing was changed" "$w/err" \
  || fail "a preinstall with no payload list beside it refuses, saying why: $rc [$(cat "$w/err")]"
[ ! -s "$nllog" ] && cmp -s "$w/nl-before" "$w/nl-after" || fail "a preinstall with no payload list changes nothing, not even the links"

Vfm="$w/vol-f-malformed"; Tfm="$Vfm/usr/local/mavergreen/openssh"; mkdir -p "$Tfm/bin" "$Vfm/usr/local/mavergreen/openssh-other" "$Vfm/usr/local/bin" "$w/scr-f-malformed"
echo ssh1 > "$Tfm/bin/ssh"; echo keep > "$Vfm/usr/local/mavergreen/openssh-other/f"; cp "$w/scr-f/preinstall" "$w/scr-f-malformed/"
mflog="$w/malformed-mg.log"; mglogger "$Vfm/usr/local/bin/mavergreen" "$mflog"
printf 'x\tbin/ssh\ngarbage\nd\tbin/ssh/\nd\t..\n' > "$w/scr-f-malformed/.mavergreen-payload"
sh "$w/scr-f-malformed/preinstall" /x.pkg "$Vfm/" "$Vfm/" 2>"$w/err" || fail "a preinstall whose list has a line of no known kind skips it and succeeds: $(cat "$w/err")"
[ -f "$Tfm/bin/ssh" ] || fail "a list line of no known kind removes nothing"
for mfl in 'f\t\nf\tbin/..\n' 'd\t/bin/ssh\nd\t../openssh-other/f\n'; do
  printf "$mfl" > "$w/scr-f-malformed/.mavergreen-payload"
  : > "$mflog"; ls -lRT "$Vfm" > "$w/mf-before"
  rc=0; sh "$w/scr-f-malformed/preinstall" /x.pkg "$Vfm/" "$Vfm/" 2>"$w/err" || rc=$?
  ls -lRT "$Vfm" > "$w/mf-after"
  [ "$rc" -eq 1 ] && grep -qF "openssh: the new version cannot be laid over $Tfm; nothing was changed" "$w/err" \
    || fail "a list line that is not a path inside the tree refuses the install (R52) [$mfl]: $rc [$(cat "$w/err")]"
  [ ! -s "$mflog" ] && cmp -s "$w/mf-before" "$w/mf-after" || fail "that refusal comes before unlink and changes nothing (R52) [$mfl]"
done

Vx="$w/vol-f-r53"; Ox="$w/f-r53-out"; Tx="$Ox/local/mavergreen/openssh"; mkdir -p "$Vx/usr" "$Ox/local/mavergreen" "$Ox/local/bin"; ln -s "$Ox/local" "$Vx/usr/local"
cp -R "$Fn" "$Ox/local/mavergreen/"; echo stray > "$Tx/stray"; rm "$Tx/etc/conf"; mkdir "$Tx/etc/conf"
printf '#!/bin/sh\nexit 0\n' > "$Ox/local/bin/mavergreen"; chmod +x "$Ox/local/bin/mavergreen"
sh "$w/scr-f/preinstall" /x.pkg "$Vx/" "$Vx/" 2>"$w/err" || fail "a preinstall on a volume whose usr/local links elsewhere succeeds (R53): $(cat "$w/err")"
[ ! -e "$Tx/etc/conf" ] || fail "a kind-change upgrade works on a volume whose usr/local links elsewhere (R53)"
echo conf > "$Tx/etc/conf"
sh "$w/scr-f/postinstall" /x.pkg "$Vx/" "$Vx/" 2>"$w/err" || fail "a postinstall on a volume whose usr/local links elsewhere succeeds (R53): $(cat "$w/err")"
[ ! -e "$Tx/stray" ] && [ -f "$Tx/bin/ssh" ] || fail "the prune works on a volume whose usr/local links elsewhere (R53)"
Ex="$w/f-r53-elsewhere"; mkdir -p "$Ex" "$w/scr-f-inlink"; echo victim > "$Ex/thing"; ln -s "$Ex" "$Tx/inlink"
cp "$w/scr-f/preinstall" "$w/scr-f-inlink/"; printf 'd\tinlink/thing\n' > "$w/scr-f-inlink/.mavergreen-payload"
illog="$w/inlink-mg.log"; mglogger "$Ox/local/bin/mavergreen" "$illog"
rc=0; sh "$w/scr-f-inlink/preinstall" /x.pkg "$Vx/" "$Vx/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] && [ "$(cat "$Ex/thing")" = victim ] && [ ! -s "$illog" ] \
  || fail "the preinstall never removes through a symlinked directory inside the tree, even with usr/local linked elsewhere (R53): $rc [$(cat "$w/err")]"
grep -qF "openssh: not removing inlink/thing -- it does not resolve inside $Vx/usr/local/mavergreen/openssh" "$w/err" \
  || fail "the preinstall says why it refuses a path behind a link in the tree: [$(cat "$w/err")]"

printf 'mv "$ROOT/usr/local/mavergreen/openssh" "$ROOT/usr/local/mavergreen/openssh.real"\nln -s openssh.real "$ROOT/usr/local/mavergreen/openssh"\n' > "$w/hook-swap"
sh "$S" --stage "$fnew" --product openssh --name OpenSSH --version 2 --scripts-out "$w/scr-f-swap" --preinstall-hook "$w/hook-swap" \
  || fail "staging with a tree-swapping preinstall hook must succeed"
Vs2="$w/vol-f-swap"; mkdir -p "$Vs2/usr/local/mavergreen/openssh/etc/conf" "$Vs2/usr/local/bin"; echo a > "$Vs2/usr/local/mavergreen/openssh/etc/conf/a"
printf '#!/bin/sh\nexit 0\n' > "$Vs2/usr/local/bin/mavergreen"; chmod +x "$Vs2/usr/local/bin/mavergreen"
rc=0; sh "$w/scr-f-swap/preinstall" /x.pkg "$Vs2/" "$Vs2/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] && [ -f "$Vs2/usr/local/mavergreen/openssh.real/etc/conf/a" ] && grep -qF "openssh: not removing etc/conf" "$w/err" \
  && grep -qF "openssh: the upgrade stopped before its payload" "$w/err" \
  || fail "the preinstall checks each removal again after its hook, never removing through a tree the hook made a link: $rc [$(cat "$w/err")]"

Vy="$w/vol-f-treelink"; Oy="$Vy/usr/local/mavergreen/other"; mkdir -p "$Oy" "$Vy/usr/local/bin"
cp -R "$Fn/." "$Oy/"; echo stray > "$Oy/stray"; rm "$Oy/etc/conf"; mkdir "$Oy/etc/conf"; ln -s other "$Vy/usr/local/mavergreen/openssh"
ylog="$w/treelink-mg.log"; mglogger "$Vy/usr/local/bin/mavergreen" "$ylog"
rc=0; sh "$w/scr-f/preinstall" /x.pkg "$Vy/" "$Vy/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] && [ ! -s "$ylog" ] && grep -qF "openssh: not removing etc/conf" "$w/err" \
  || fail "a preinstall whose tree is a link refuses a kind change before any change (R52): $rc [$(cat "$w/err")]"
sh "$w/scr-f/postinstall" /x.pkg "$Vy/" "$Vy/" 2>/dev/null || fail "a postinstall whose tree is a link still succeeds"
[ -d "$Oy/etc/conf" ] && [ -f "$Oy/stray" ] || fail "a product tree that is itself a link is never changed through it, even on the volume"

if [ "$(id -u)" -eq 0 ]; then
  echo "note: running as root, which ignores directory permissions -- skipping the failed-removal relink case"
else
  sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-relink" || fail "staging for the relink case must succeed"
  Vh="$w/vol-f-relink"; Th="$Vh/usr/local/mavergreen"; mkdir -p "$Vh/usr/local/bin" "$Th"
  cp "$V2/usr/local/bin/mavergreen" "$Vh/usr/local/bin/mavergreen"; cp -R "$st/usr/local/mavergreen/openssh" "$Th/"
  "$Vh/usr/local/bin/mavergreen" --root "$Vh/" link openssh || fail "setup: link the installed version"
  rm "$Th/openssh/share/note"; mkdir "$Th/openssh/share/note"; chmod 555 "$Th/openssh/share"
  rc=0; sh "$w/scr-relink/preinstall" /x.pkg "$Vh/" "$Vh/" 2>"$w/err" || rc=$?
  chmod 755 "$Th/openssh/share"
  [ "$rc" -eq 1 ] && grep -qF "openssh: could not remove share/note" "$w/err" \
    && grep -qF "openssh: the upgrade stopped before its payload; the installed version is linked again" "$w/err" \
    || fail "a removal that fails after unlink stops the install, saying why (R52): $rc [$(cat "$w/err")]"
  [ -L "$Th/bin/ssh" ] || fail "a removal that fails after unlink puts the installed version's farm links back (R52)"
fi

for nm in "bad${tab}name" "bad
name"; do
  sb="$w/stage-badname"; rm -rf "$sb" "$w/scr-badname"; mkdir -p "$sb/usr/local/mavergreen/openssh/bin"
  echo ssh > "$sb/usr/local/mavergreen/openssh/bin/ssh"; echo x > "$sb/usr/local/mavergreen/openssh/bin/$nm"
  rc=0; sh "$S" --stage "$sb" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-badname" 2>"$w/err" || rc=$?
  [ "$rc" -eq 2 ] || fail "a staged name holding a tab or newline is refused at stage time with exit 2, got $rc"
  grep -qF "which the payload list cannot carry; rename it" "$w/err" || fail "that refusal says why: [$(cat "$w/err")]"
  [ ! -e "$w/scr-badname" ] && [ ! -e "$sb/usr/local/mavergreen/openssh/mavergreen.plist" ] || fail "that refusal comes before anything is written"
done

printf 'set -e\nfalse\necho went-on >> "$ROOT/sete.log"\n' > "$w/hook-sete"
printf 'false\necho went-on >> "$ROOT/sete.log"\n' > "$w/hook-notlast"
sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-sete" \
  --preinstall-hook "$w/hook-sete" --postinstall-hook "$w/hook-sete" || fail "staging set -e hooks must succeed"
sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-notlast" \
  --preinstall-hook "$w/hook-notlast" --postinstall-hook "$w/hook-notlast" || fail "staging hooks whose earlier command fails must succeed"
mkse() {
  rm -rf "$w/vol-sete"; mkdir -p "$w/vol-sete/usr/local/bin" "$w/vol-sete/usr/local/mavergreen"
  cp "$V2/usr/local/bin/mavergreen" "$w/vol-sete/usr/local/bin/mavergreen"
  cp -R "$st/usr/local/mavergreen/openssh" "$w/vol-sete/usr/local/mavergreen/"
  "$w/vol-sete/usr/local/bin/mavergreen" --root "$w/vol-sete/" link openssh || fail "setup: link the installed version"
  rm "$w/vol-sete/usr/local/mavergreen/openssh/share/note"; mkdir "$w/vol-sete/usr/local/mavergreen/openssh/share/note"
}
mkse
rc=0; sh "$w/scr-sete/preinstall" /x.pkg "$w/vol-sete/" "$w/vol-sete/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] && [ ! -e "$w/vol-sete/sete.log" ] || fail "a preinstall hook that sets -e stops at its first failure and stops the install (R49): $rc [$(cat "$w/err")]"
grep -q 'openssh: preinstall hook failed; the installed version is left in place' "$w/err" \
  && [ -L "$w/vol-sete/usr/local/mavergreen/bin/ssh" ] && [ -d "$w/vol-sete/usr/local/mavergreen/openssh/share/note" ] \
  || fail "that failure is reported, the installed version relinked and its tree untouched (R49): [$(cat "$w/err")]"
mkse
rc=0; sh "$w/scr-sete/postinstall" /x.pkg "$w/vol-sete/" "$w/vol-sete/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] && [ ! -e "$w/vol-sete/sete.log" ] && grep -q 'openssh: postinstall hook failed' "$w/err" \
  || fail "a postinstall hook that sets -e stops at its first failure and fails the install (R49): $rc [$(cat "$w/err")]"
for _esh in sh /bin/ksh /bin/dash; do
  case "$_esh" in /*) [ -x "$_esh" ] || continue ;; esac
  mkse
  rc=0; "$_esh" -e "$w/scr-notlast/preinstall" /x.pkg "$w/vol-sete/" "$w/vol-sete/" 2>"$w/err" || rc=$?
  [ "$rc" -eq 1 ] && [ ! -e "$w/vol-sete/sete.log" ] && grep -q 'openssh: preinstall hook failed; the installed version is left in place' "$w/err" \
    || fail "a preinstall run with errexit ($_esh -e) passes it to its hook, and still relinks and says why (R49): $rc [$(cat "$w/err")]"
  mkse
  rc=0; "$_esh" -e "$w/scr-notlast/postinstall" /x.pkg "$w/vol-sete/" "$w/vol-sete/" 2>"$w/err" || rc=$?
  [ "$rc" -eq 1 ] && [ ! -e "$w/vol-sete/sete.log" ] && grep -q 'openssh: postinstall hook failed' "$w/err" \
    || fail "a postinstall run with errexit ($_esh -e) passes it to its hook, and still says why (R49): $rc [$(cat "$w/err")]"
done
mkse
sh "$w/scr-notlast/preinstall" /x.pkg "$w/vol-sete/" "$w/vol-sete/" 2>"$w/err" && [ "$(cat "$w/vol-sete/sete.log")" = went-on ] \
  || fail "without set -e a preinstall hook's status is its last command's: [$(cat "$w/err")]"

echo "PASS: stage-product"
