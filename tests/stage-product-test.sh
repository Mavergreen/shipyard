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
[ ! -e "$V/usr/local/mavergreen/openssh" ] || fail "preinstall clears the product tree so an upgrade replaces it wholesale"
[ -f "$V/usr/local/mavergreen/var/openssh/state" ] || fail "preinstall must never touch var/"
cp -R "$st/usr/local/mavergreen/openssh" "$V/usr/local/mavergreen/"
mkdir -p "$V/usr/local/mavergreen/.base/9.9"
sed 's/@MAVERGREEN_VERSION@/9.9/' "$here/../scripts/mavergreen.sh" > "$V/usr/local/mavergreen/.base/9.9/mavergreen"
chmod +x "$V/usr/local/mavergreen/.base/9.9/mavergreen"
sh "$w/scr/postinstall" /x.pkg "$V/" "$V/" || fail "postinstall must succeed with only a staged helper"
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
  || fail "the preinstall's destructive path is a literal, never built from a variable that could be empty"

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
cp "$here/../scripts/product-name.sh" "$here/../scripts/product-names" "$fake/"
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
st2="$w/stage2"; mkdir -p "$st2/usr/local/mavergreen/openssh/bin"; echo ssh > "$st2/usr/local/mavergreen/openssh/bin/ssh"
sh "$fake/stage_product.sh" --stage "$st2" --product openssh \
  --name "Open SSH Suite" --version 1.2.3 --group opengrp --line 9 \
  --exclude "bin/extra one" --exclude "share/man/man1/extra.1" \
  --replaces "/usr/bin/ssh=bin/ssh" --replaces "/usr/bin/scp=bin/scp two" \
  --scripts-out "$w/scr3" \
  --updater-app "$APP" \
  --preinstall-hook "$w/hook" --postinstall-hook "$w/hook" \
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
  --has-updater)"
[ "$(cat "$w/rm.log")" = "$expected" ] \
  || fail "every render-manifest option, in order, with repeats and embedded spaces, must reach render-manifest intact: got [$(cat "$w/rm.log")]"
grep -qE -- '--scripts-out|--updater-app|--app-dir|--agent-label|--preinstall-hook|--postinstall-hook' "$w/rm.log" \
  && fail "a stage_product-only option must never reach render-manifest"
grep -qF "$w/scr3" "$w/rm.log" && fail "a stage_product-only option's VALUE must never reach render-manifest either"
grep -qF "Application Support" "$w/rm.log" && fail "the updater's app-dir value must never reach render-manifest"
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
[ ! -e "$MGup/go126" ] || fail "the upgrade preinstall clears the selected member's tree"
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
sh "$w/scr-pre/preinstall" /x.pkg "$Vp" "$Vp" || fail "preinstall must accept a target volume with no trailing slash"
[ ! -e "$MGp/openssh" ] || fail "preinstall clears the product tree when the volume has no trailing slash"
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
  chmod 555 "$MGp"
  rc=0; sh "$w/scr/preinstall" /x.pkg "$Vp/" "$Vp/" > "$w/pre-ro.out" 2>&1 || rc=$?
  chmod 755 "$MGp"
  [ "$rc" -eq 0 ] || fail "a tree preinstall cannot remove must never fail the install, got exit $rc"
  grep -q 'openssh: could not clear' "$w/pre-ro.out" || fail "a tree preinstall cannot remove is reported: [$(cat "$w/pre-ro.out")]"
  [ -d "$MGp/openssh" ] || fail "fixture: the unwritable parent must have kept the tree"
fi

V2="$w/vol-hooks"; T2="$V2/usr/local/mavergreen"; mkdir -p "$V2/usr/local/bin" "$T2"
sed 's/@MAVERGREEN_VERSION@/9.9/' "$here/../scripts/mavergreen.sh" > "$V2/usr/local/bin/mavergreen"
chmod +x "$V2/usr/local/bin/mavergreen"
printf 'false\n' > "$w/hook-false"
printf 'exit 0\n' > "$w/hook-exit"
printf 'if [ -z "$ROOT" ]; then false; fi\n' > "$w/hook-guarded"
sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-false" \
  --preinstall-hook "$w/hook-false" --postinstall-hook "$w/hook-false" || fail "staging with failing hooks must succeed"
sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-exit" \
  --preinstall-hook "$w/hook-exit" || fail "staging with an exiting hook must succeed"
sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr-guarded" \
  --postinstall-hook "$w/hook-guarded" || fail "staging with a guarded hook must succeed"
cp -R "$st/usr/local/mavergreen/openssh" "$T2/"
"$V2/usr/local/bin/mavergreen" --root "$V2/" link openssh || fail "setup: link the installed version"
rc=0; sh "$w/scr-false/preinstall" /x.pkg "$V2/" "$V2/" 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "a failing preinstall hook must fail the install -- it is how a preset refuses a missing dependency"
[ -f "$T2/openssh/mavergreen.plist" ] || fail "a failing preinstall hook must stop the install before the tree is removed"
[ -L "$T2/bin/ssh" ] || fail "a failing preinstall hook must leave the installed version linked, as it was"
grep -q 'preinstall hook failed' "$w/err" || fail "the failure names the preinstall hook: $(cat "$w/err")"
sh "$w/scr-exit/preinstall" /x.pkg "$V2/" "$V2/" || fail "a hook that exits 0 early is not a failure"
[ ! -e "$T2/openssh" ] || fail "a hook's exit must not skip the tree removal -- each hook runs in a subshell"
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

echo "PASS: stage-product"
