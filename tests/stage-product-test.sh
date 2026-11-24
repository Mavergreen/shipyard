#!/bin/sh
# platform: macOS-only -- the generated preinstall runs here, and its PlistBuddy text reads the target volume's manifests; run by hand on the maintainer's 10.9 box (tests/maintainer-tests)
set -eu
umask 022
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/stage_product.sh"
SD="$(sh "$here/../scripts/fetch_stevedore.sh")" || { echo "FAIL: fetch_stevedore.sh failed"; exit 1; }; export STEVEDORE="$SD"
[ -x /usr/libexec/PlistBuddy ] || { echo "no PlistBuddy for the generated preinstall to run under -- skipping"; exit 77; }
w="$(mktemp -d "${TMPDIR:-/tmp}/stage-product.XXXXXX")"; trap 'chmod -R u+w "$w" 2>/dev/null; rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
MAVERGREEN_CHAIN_UID="$(id -u)"; export MAVERGREEN_CHAIN_UID
repo="$w/repo"
for s in openssh swift-runtime go126 go127 porthole; do mkdir -p "$repo/.mavergreen/products/$s"; echo "$s" > "$repo/.mavergreen/products/$s/noun"; done
echo Porthole > "$repo/.mavergreen/products/porthole/noun"
echo Go > "$repo/.mavergreen/products/go126/noun"; echo 1.26 > "$repo/.mavergreen/products/go126/line"
echo Go > "$repo/.mavergreen/products/go127/noun"; echo 1.27 > "$repo/.mavergreen/products/go127/line"
echo go > "$repo/.mavergreen/products/go126/group"; echo go > "$repo/.mavergreen/products/go127/group"
for s in container-tools openssh; do
  mkdir -p "$repo/.mavergreen/ingredients/$s"; echo "$s" > "$repo/.mavergreen/ingredients/$s/product"
  echo "Mavergreen/$s" > "$repo/.mavergreen/ingredients/$s/REPO"
done
MAVERGREEN_REPO_ROOT="$repo"; GITHUB_REPOSITORY=Mavergreen/openssh; export MAVERGREEN_REPO_ROOT GITHUB_REPOSITORY
xplist() {
  _xf="$1"; shift
  { printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>\n'
    while [ "$#" -ge 2 ]; do printf '<key>%s</key><string>%s</string>\n' "$1" "$2"; shift 2; done
    printf '</dict></plist>\n'; } > "$_xf"
}
mkhelper() {
  mkdir -p "$1/opt/mavergreen/mavergreen/bin" "$1/opt/mavergreen/bin"
  sh "$here/../scripts/build-base-component.sh" --emit-helper "$1/opt/mavergreen/mavergreen/bin/mavergreen" --version 9.9
  ln -s ../mavergreen/bin/mavergreen "$1/opt/mavergreen/bin/mavergreen"
}
reqs() {
  rm -rf "$repo/.mavergreen/products/porthole/requires"
  while [ $# -ge 3 ]; do
    _d="$repo/.mavergreen/products/porthole/requires/$1"; mkdir -p "$_d"
    echo "$2" > "$_d/kind"
    [ "$3" = - ] || printf '%s\n' "$3" > "$_d/min"
    shift 3
  done
}
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
st="$w/stage"; mkdir -p "$st/opt/mavergreen/openssh/bin"; echo ssh > "$st/opt/mavergreen/openssh/bin/ssh"
printf 'echo post-hook-ran "$ROOT" >> "$ROOT/hook.log"\n' > "$w/hook"
sh "$S" --stage "$st" --product openssh --version 1 --scripts-out "$w/scr" --postinstall-hook "$w/hook"
[ -f "$st/opt/mavergreen/openssh/mavergreen.plist" ] || fail "the manifest is rendered at the product's tree root under opt/mavergreen"
[ ! -e "$st/usr" ] || fail "staging puts nothing under usr/"
sh "$S" --stage "$st" --product openssh --version 1 --scripts-out "$w/scr-gen" \
  --generated "Applications/Mavergreen/Linux X.app" || fail "stage_product must accept --generated"
[ "$("$SD" plist get "$st/opt/mavergreen/openssh/mavergreen.plist" generated:0)" = "Applications/Mavergreen/Linux X.app" ] \
  || fail "stage_product passes --generated through to the manifest"
grep -q 'mavergreen_root_dir "$ROOT/Applications/Mavergreen"' "$w/scr-gen/preinstall" \
  || fail "a --generated entry under Applications/Mavergreen/ makes the preinstall create that directory"
grep -q 'Applications/Mavergreen' "$w/scr/preinstall" && fail "a product with nothing in Applications/Mavergreen/ never names it"

sh -n "$w/scr/preinstall" || fail "generated preinstall must be valid sh"
sh -n "$w/scr/postinstall" || fail "generated postinstall must be valid sh"
grep -l usr/local "$w/scr/preinstall" "$w/scr/postinstall" "$w/scr-gen/preinstall" && fail "the generated scripts name nothing under usr/local"

V="$w/vol"; mkdir -p "$V/opt/mavergreen/openssh/stale" "$V/opt/mavergreen/var/openssh"
touch "$V/opt/mavergreen/var/openssh/state"
sh "$w/scr/preinstall" /x.pkg "$V/" "$V/" || fail "preinstall must succeed"
[ ! -e "$V/opt/mavergreen/openssh" ] || fail "preinstall clears the product tree so an upgrade replaces it wholesale"
[ -f "$V/opt/mavergreen/var/openssh/state" ] || fail "preinstall must never touch var/"
cp -R "$st/opt/mavergreen/openssh" "$V/opt/mavergreen/"
mkdir -p "$V/opt/mavergreen/.base/9.9"
sh "$here/../scripts/build-base-component.sh" --emit-helper "$V/opt/mavergreen/.base/9.9/mavergreen" --version 9.9
sh "$w/scr/postinstall" /x.pkg "$V/" "$V/" || fail "postinstall must succeed with only a staged helper"
[ -L "$V/opt/mavergreen/bin/ssh" ] || fail "postinstall links the product"
grep -q post-hook-ran "$V/hook.log" || fail "the product's own postinstall hook runs"
rm -rf "$V/opt/mavergreen/.base"
sh "$w/scr/postinstall" /x.pkg "$V/" "$V/" 2>/dev/null && fail "postinstall with no helper at all must fail loudly"
sh "$w/scr/preinstall" /x.pkg >/dev/null 2>&1; [ -d "$V/opt/mavergreen/openssh" ] || fail "preinstall with no target volume removes nothing"

Vgw="$w/vol-gw"; mkdir -p "$Vgw/opt/mavergreen/openssh/bin"; echo old > "$Vgw/opt/mavergreen/openssh/bin/ssh"
chmod g+w "$Vgw/opt/mavergreen"
rc=0; sh "$w/scr/preinstall" /x.pkg "$Vgw/" "$Vgw/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "a group-writable opt/mavergreen refuses the install (1), got $rc"
grep -q 'group-writable' "$w/err" || fail "the refusal names the rule: $(cat "$w/err")"
[ -f "$Vgw/opt/mavergreen/openssh/bin/ssh" ] || fail "a refused chain removes nothing"

mkdir -p "$w/empty"
sh "$S" --stage "$w/empty" --product openssh --version 1 --scripts-out "$w/scr2" 2>/dev/null \
  && fail "a product with nothing staged at all must be refused"
so="$w/outside-only"; mkdir -p "$so/usr/lib/swift"; echo lib > "$so/usr/lib/swift/libswiftCore.dylib"
sh "$S" --stage "$so" --product swift-runtime --version 1 --scripts-out "$w/scr-so" \
  || fail "a product whose every file lives where the OS dictates still stages, so its manifest can find them"
[ -f "$so/opt/mavergreen/swift-runtime/mavergreen.plist" ] \
  || fail "an outside-only product's manifest sits at its tree root, where the helper and conformance look"
"$SD" plist get "$so/opt/mavergreen/swift-runtime/mavergreen.plist" outside:0 2>/dev/null \
  | grep -qx usr/lib/swift/libswiftCore.dylib \
  || fail "an outside-only product's manifest lists its files in outside, so uninstall removes them"
grep -q 'rm -rf "$ROOT/opt/mavergreen/openssh"' "$w/scr/preinstall" \
  || fail "the preinstall's destructive path is a literal, never built from a variable that could be empty"

sa="$w/stage-app"; mkdir -p "$sa/opt/mavergreen/go127/bin" "$sa/Applications/Go.app/Contents"
echo go > "$sa/opt/mavergreen/go127/bin/go"; : > "$sa/Applications/Go.app/Contents/Info.plist"
rc=0; sh "$S" --stage "$sa" --product go127 --version 1 --scripts-out "$w/scr-badapp" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "a staged app outside Applications/Mavergreen/ is refused (1), got $rc"
grep -q 'Applications/Go.app' "$w/err" || fail "the refusal names the app: $(cat "$w/err")"
grep -q 'Applications/Mavergreen/' "$w/err" || fail "the refusal says where apps go: $(cat "$w/err")"
[ ! -e "$sa/opt/mavergreen/go127/mavergreen.plist" ] || fail "a refused app stops staging before the manifest is rendered"
rm -rf "$sa/Applications/Go.app"; mkdir -p "$sa/Applications/Empty.app" "$w/elsewhere"
rc=0; sh "$S" --stage "$sa" --product go127 --version 1 --scripts-out "$w/scr-badapp" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] && grep -q 'Applications/Empty.app' "$w/err" || fail "an empty directory outside Applications/Mavergreen/ is refused too (got $rc): $(cat "$w/err")"
rmdir "$sa/Applications/Empty.app"; ln -s "$w/elsewhere" "$sa/Applications/Mavergreen"
rc=0; sh "$S" --stage "$sa" --product go127 --version 1 --scripts-out "$w/scr-badapp" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] && grep -q 'Applications/Mavergreen is outside' "$w/err" || fail "a staged Applications/Mavergreen that is a symlink is refused (got $rc): $(cat "$w/err")"
rm "$sa/Applications/Mavergreen"; mkdir -p "$sa/Applications/Mavergreen/Go.app/Contents"
: > "$sa/Applications/Mavergreen/Go.app/Contents/Info.plist"
sh "$S" --stage "$sa" --product go127 --version 1 --scripts-out "$w/scr-app" || fail "an app in Applications/Mavergreen/ stages"
Vapp="$w/vol-app"; mkdir -p "$Vapp/opt/mavergreen" "$Vapp/Applications"
sh "$w/scr-app/preinstall" /x.pkg "$Vapp/" "$Vapp/" 2>"$w/err" || fail "a preinstall with an app must succeed: $(cat "$w/err")"
[ -d "$Vapp/Applications/Mavergreen" ] && [ ! -L "$Vapp/Applications/Mavergreen" ] \
  || fail "a staged Applications/Mavergreen/Go.app makes the preinstall create Applications/Mavergreen"
[ "$(ls -ld "$Vapp/Applications/Mavergreen" | cut -c1-10)" = drwxr-xr-x ] \
  || fail "the preinstall creates Applications/Mavergreen 755: $(ls -ld "$Vapp/Applications/Mavergreen")"
Vnoapp="$w/vol-noapp"; mkdir -p "$Vnoapp/opt/mavergreen" "$Vnoapp/Applications"
sh "$w/scr/preinstall" /x.pkg "$Vnoapp/" "$Vnoapp/" || fail "preinstall without apps must succeed"
[ ! -e "$Vnoapp/Applications/Mavergreen" ] || fail "a product with no app never creates Applications/Mavergreen"
Vapl="$w/vol-app-link"; mkdir -p "$Vapl/opt/mavergreen/go127/bin" "$Vapl/Applications"
echo old > "$Vapl/opt/mavergreen/go127/bin/go"; ln -s "$w/elsewhere" "$Vapl/Applications/Mavergreen"
rc=0; sh "$w/scr-app/preinstall" /x.pkg "$Vapl/" "$Vapl/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "a symlinked Applications/Mavergreen refuses the install (1), got $rc"
[ -f "$Vapl/opt/mavergreen/go127/bin/go" ] || fail "a refused Applications/Mavergreen removes nothing"

sq="$w/stage-q9"; mkdir -p "$sq/opt/mavergreen/openssh/bin" "$sq/Library/Application Support/SIMBL/Plugins/X.bundle/Contents"
echo ssh > "$sq/opt/mavergreen/openssh/bin/ssh"; : > "$sq/Library/Application Support/SIMBL/Plugins/X.bundle/Contents/Info.plist"
sh "$S" --stage "$sq" --product openssh --version 1 --scripts-out "$w/scr-q9" || fail "a SIMBL plugin stages"
Vq="$w/vol-q9"; mkdir -p "$Vq/opt/mavergreen/openssh/bin" "$Vq/Library/Application Support/SIMBL/Plugins"
echo old > "$Vq/opt/mavergreen/openssh/bin/ssh"
sh "$w/scr-q9/preinstall" /x.pkg "$Vq/" "$Vq/" 2>"$w/err" || fail "root-owned ancestors under Library/Application Support pass: $(cat "$w/err")"
mkdir -p "$Vq/opt/mavergreen/openssh/bin" "$w/plugins-elsewhere"; echo old > "$Vq/opt/mavergreen/openssh/bin/ssh"
rm -rf "$Vq/Library/Application Support/SIMBL/Plugins"; ln -s "$w/plugins-elsewhere" "$Vq/Library/Application Support/SIMBL/Plugins"
rc=0; sh "$w/scr-q9/preinstall" /x.pkg "$Vq/" "$Vq/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "a symlinked ancestor under Library/Application Support refuses the install (1), got $rc"
grep -q 'SIMBL/Plugins: symlink' "$w/err" || fail "the refusal names the symlinked ancestor: $(cat "$w/err")"
[ -f "$Vq/opt/mavergreen/openssh/bin/ssh" ] || fail "a refused ancestor removes nothing"
grep -q 'Application Support/SIMBL' "$w/scr/preinstall" && fail "a product with nothing under Library/Application Support checks nothing there"

rc=0; sh "$S" --stage "$st" --product openssh --version 1 --scripts-out "$w/scr-updater" --updater-app "$w/openssh-helper.app" 2>"$w/err" || rc=$?
[ "$rc" -eq 2 ] || fail "--updater-app is a usage error (exit 2): no product ships an updater; got $rc"
grep -q 'the Engine' "$w/err" || fail "the --updater-app refusal says the Engine updates products: $(cat "$w/err")"
[ ! -e "$st/Library/LaunchAgents" ] || fail "a refused --updater-app stages no update-check job"
sh "$S" --stage "$st" --product openssh --version 1 --scripts-out "$w/scr-hu" --has-updater 2>/dev/null \
  && fail "--has-updater is never a caller's to pass"
for f in --appcast --app-dir --agent-label; do
  rc=0; sh "$S" --stage "$st" --product openssh --version 1 --scripts-out "$w/scr-refused" "$f" x 2>/dev/null || rc=$?
  [ "$rc" -eq 2 ] || fail "$f is derived, so passing it is a usage error (exit 2); got $rc"
done
rm -rf "$w/undeclared"; mkdir -p "$w/undeclared/.mavergreen/products"
rc=0; MAVERGREEN_REPO_ROOT="$w/undeclared" sh "$S" --stage "$st" --product openssh --version 1 \
  --scripts-out "$w/scr-undeclared" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "a product the repo does not declare must be refused (1), got $rc"
grep -q '.mavergreen/products/openssh/noun' "$w/err" || fail "the refusal says where to write the noun: $(cat "$w/err")"
grep -q MAV_AGENT_PLIST "$w/scr/postinstall" && fail "no generated postinstall loads an update-check agent"

fake="$w/fake/scripts"; mkdir -p "$fake" "$w/fake/.mavergreen/ingredients"
cp "$S" "$fake/stage_product.sh"
cp "$here/../scripts/fetch_stevedore.sh" "$here/../scripts/mavergreen-meta.sh" "$fake/"
cp -R "$here/../.mavergreen/ingredients/stevedore" "$w/fake/.mavergreen/ingredients/"
mkdir -p "$fake/lib"; cp "$here/../scripts/lib/vercmp.sh" "$here/../scripts/lib/name-rules.sh" "$here/../scripts/lib/root-chain.sh" "$fake/lib/"
RM_LOG="$w/rm.log"; export RM_LOG
cat > "$fake/render-manifest.sh" <<'EOF'
#!/bin/sh
: > "$RM_LOG"
for a in "$@"; do printf '%s\n' "$a" >> "$RM_LOG"; done
EOF
st2="$w/stage2"; mkdir -p "$st2/opt/mavergreen/openssh/bin"; echo ssh > "$st2/opt/mavergreen/openssh/bin/ssh"
sh "$fake/stage_product.sh" --stage "$st2" --product openssh \
  --version 1.2.3 \
  --exclude "bin/extra one" --exclude "share/man/man1/extra.1" \
  --replaces "/usr/bin/ssh=bin/ssh" --replaces "/usr/bin/scp=bin/scp two" \
  --scripts-out "$w/scr3" \
  --preinstall-hook "$w/hook" --postinstall-hook "$w/hook" \
  || fail "stage_product with a stubbed render-manifest must still succeed"
expected="$(printf '%s\n' \
  --stage "$st2" \
  --product openssh \
  \
  --version 1.2.3 \
  --exclude "bin/extra one" \
  --exclude "share/man/man1/extra.1" \
  --replaces "/usr/bin/ssh=bin/ssh" \
  --replaces "/usr/bin/scp=bin/scp two")"
[ "$(cat "$w/rm.log")" = "$expected" ] \
  || fail "every render-manifest option, in order, with repeats and embedded spaces, must reach render-manifest intact: got [$(cat "$w/rm.log")]"
grep -qE -- '--scripts-out|--app-dir|--agent-label|--preinstall-hook|--postinstall-hook|--requires|--group|--has-updater' "$w/rm.log" \
  && fail "a stage_product-only option must never reach render-manifest"
grep -qF "$w/scr3" "$w/rm.log" && fail "a stage_product-only option's VALUE must never reach render-manifest either"

for o in name:noun line:line group:group; do
  rc=0; sh "$S" --stage "$st" --product openssh --version 1 --scripts-out "$w/scr-refuse" --${o%%:*} X 2>"$w/err" || rc=$?
  [ "$rc" -eq 2 ] || fail "--${o%%:*} must be refused with exit 2, got $rc"
  grep -qF ".mavergreen/products/<P>/${o#*:}" "$w/err" || fail "the refusal of --${o%%:*} names products/<P>/${o#*:}: $(cat "$w/err")"
done
rc=0; sh "$S" --stage "$st" --product openssh --version 1 --scripts-out "$w/scr-refuse" --requires container-tools 2>"$w/err" || rc=$?
[ "$rc" -eq 2 ] || fail "--requires must be refused with exit 2, got $rc"
grep -qF ".mavergreen/products/<P>/requires/" "$w/err" || fail "the refusal of --requires names products/<P>/requires/: $(cat "$w/err")"
rc=0; sh "$S" --stage "$st" --product openssh --version 1 --scripts-out "$w/scr-refuse" --name 2>"$w/err" || rc=$?
[ "$rc" -eq 2 ] && grep -qF ".mavergreen/products/<P>/noun" "$w/err" || fail "--name with no value must hit the refusal, not 'needs a value': $(cat "$w/err")"
for s in go126 go127; do
  sl="$w/stage-$s"; mkdir -p "$sl/opt/mavergreen/$s/bin"; echo go > "$sl/opt/mavergreen/$s/bin/go"
  sh "$S" --stage "$sl" --product "$s" --version 1 --scripts-out "$w/scr-$s" || fail "staging $s must succeed"
done
[ "$("$SD" plist get "$w/stage-go127/opt/mavergreen/go127/mavergreen.plist" name)" = "Go 1.27" ] \
  || fail "staging go127 (noun Go, line 1.27) writes the name 'Go 1.27'"
[ "$("$SD" plist get "$w/stage-go127/opt/mavergreen/go127/mavergreen.plist" line)" = 1.27 ] \
  || fail "staging go127 writes the line 1.27"
[ "$("$SD" plist get "$w/stage-go127/opt/mavergreen/go127/mavergreen.plist" group)" = go ] \
  || fail "staging go127 reads its group from products/go127/group"

rc1="$w/rc1"
if run_with_timeout 5 "$rc1" sh "$S" --stage "$st" --product openssh --version 1 --scripts-out; then
  [ "$(cat "$rc1")" = 2 ] || fail "an option missing its value (at the end of the argument list) must exit 2, got $(cat "$rc1" 2>/dev/null)"
else
  fail "an option missing its value at the end of the argument list must exit promptly, not hang"
fi
rc2="$w/rc2"
if run_with_timeout 5 "$rc2" sh "$S" --stage "$st" --product openssh --exclude --end --version 1 --scripts-out "$w/scrbad2"; then
  [ "$(cat "$rc2")" = 2 ] || fail "an option value literally --end must exit 2, got $(cat "$rc2" 2>/dev/null)"
else
  fail "an option value literally --end must exit promptly, not hang"
fi

hooknonl="$w/hook-no-nl"
printf 'echo hook-no-nl-ran "$ROOT" >> "$ROOT/hook2.log"' > "$hooknonl"
scrnl="$w/scr-nonl"
sh "$S" --stage "$st" --product openssh --version 1 --scripts-out "$scrnl" \
  --preinstall-hook "$hooknonl" --postinstall-hook "$hooknonl" \
  || fail "stage_product must succeed even with a hook lacking a trailing newline"
sh -n "$scrnl/preinstall" || fail "preinstall with a no-trailing-newline hook must still be valid sh"
sh -n "$scrnl/postinstall" || fail "postinstall with a no-trailing-newline hook must still be valid sh"
tail -1 "$scrnl/preinstall" | grep -qx 'exit 0' || fail "preinstall must end with exit 0 on its own line even after a no-trailing-newline hook"
tail -1 "$scrnl/postinstall" | grep -qx 'exit 0' || fail "postinstall must end with exit 0 on its own line even after a no-trailing-newline hook"
Vnl="$w/volnl"; mkdir -p "$Vnl/opt"
sh "$scrnl/preinstall" /x.pkg "$Vnl/" "$Vnl/" || fail "preinstall (no-trailing-newline hook) must still succeed"
grep -q hook-no-nl-ran "$Vnl/hook2.log" || fail "a hook without a trailing newline must still run, not get swallowed into the next line"

Vver="$w/volver"; mkdir -p "$Vver/opt/mavergreen"
cp -R "$st/opt/mavergreen/openssh" "$Vver/opt/mavergreen/"
mkdir -p "$Vver/opt/mavergreen/.base/1.0.9" "$Vver/opt/mavergreen/.base/1.0.10"
poisonlog="$w/poison.log"
{
  printf '#!/bin/sh\n'
  printf 'echo wrong-version-used >> %s\n' "$poisonlog"
  printf 'exit 1\n'
} > "$Vver/opt/mavergreen/.base/1.0.9/mavergreen"
chmod +x "$Vver/opt/mavergreen/.base/1.0.9/mavergreen"
sh "$here/../scripts/build-base-component.sh" --emit-helper "$Vver/opt/mavergreen/.base/1.0.10/mavergreen" --version 1.0.10
sh "$w/scr/postinstall" /x.pkg "$Vver/" "$Vver/" \
  || fail "postinstall must succeed with only staged helpers present, picking the numerically newest one"
[ ! -f "$poisonlog" ] \
  || fail "postinstall picked the lexically-last staged helper (1.0.9) instead of the numerically newest (1.0.10)"
[ -L "$Vver/opt/mavergreen/bin/ssh" ] || fail "postinstall (numeric helper pick) must still link the product"
grep -q '_mg_newer' "$w/scr/postinstall" && fail "the postinstall orders staged helpers with the one comparator, mavergreen_vercmp"
rm -f "$Vver/opt/mavergreen/bin/ssh"; chmod g+w "$Vver/opt/mavergreen/.base/1.0.10"
rc=0; sh "$w/scr/postinstall" /x.pkg "$Vver/" "$Vver/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "a staged helper in a group-writable directory is never run (1), got $rc"
grep -q 'group-writable' "$w/err" || fail "the refusal names the rule: $(cat "$w/err")"
[ ! -L "$Vver/opt/mavergreen/bin/ssh" ] || fail "a refused staged helper links nothing"

Vfl="$w/vol-farm"; mkhelper "$Vfl"; cp -R "$st/opt/mavergreen/openssh" "$Vfl/opt/mavergreen/"
chmod g+w "$Vfl/opt/mavergreen/mavergreen/bin"
rc=0; sh "$w/scr/postinstall" /x.pkg "$Vfl/" "$Vfl/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "a farm link into a group-writable tree is never run by the postinstall (1), got $rc"
grep -q 'mavergreen/bin: group-writable' "$w/err" || fail "the refusal names the helper's directory and the rule: $(cat "$w/err")"
[ ! -L "$Vfl/opt/mavergreen/bin/ssh" ] || fail "a refused helper links nothing"
rc=0; sh "$w/scr/preinstall" /x.pkg "$Vfl/" "$Vfl/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "a farm link into a group-writable tree is never run by the preinstall's unlink (1), got $rc"
[ -f "$Vfl/opt/mavergreen/openssh/bin/ssh" ] || fail "a refused helper in the preinstall removes nothing"

stg="$w/stage-go"; mkdir -p "$stg/opt/mavergreen/go127/bin"; echo go > "$stg/opt/mavergreen/go127/bin/go"
sh "$S" --stage "$stg" --product go127 --version 2 --scripts-out "$w/scr-go" \
  || fail "staging a group member must succeed"
Vup="$w/volup"; MGup="$Vup/opt/mavergreen"; mkhelper "$Vup"; mkdir -p "$MGup/go126/bin" "$MGup/var/go127" "$MGup/var/go126"
cp -R "$stg/opt/mavergreen/go127" "$MGup/"
echo state > "$MGup/var/go127/state"; echo state > "$MGup/var/go126/state"
echo go > "$MGup/go126/bin/go"
xplist "$MGup/go126/mavergreen.plist" product go126 group go line 126 identifier dev.mavergreen.go126 version 1
"$MGup/bin/mavergreen" --root "$Vup" link go127; "$MGup/bin/mavergreen" --root "$Vup" link go126
[ "$(cat "$MGup/var/mavergreen/selections/go")" = go127 ] || fail "fixture: the first member linked is selected"
sh "$w/scr-go/preinstall" /x.pkg "$Vup/" "$Vup/" || fail "the selected member's upgrade preinstall must succeed"
[ ! -e "$MGup/go127" ] || fail "the upgrade preinstall clears the selected member's tree"
[ "$(cat "$MGup/var/mavergreen/selections/go")" = go127 ] || fail "an upgrade's preinstall never changes the group's selection"
[ "$(cat "$MGup/var/go127/state")" = state ] || fail "an upgrade's preinstall keeps opt/mavergreen/var/go127"
cp -R "$stg/opt/mavergreen/go127" "$MGup/"
sh "$w/scr-go/postinstall" /x.pkg "$Vup/" "$Vup/" || fail "the selected member's upgrade postinstall must succeed"
[ "$(cat "$MGup/var/mavergreen/selections/go")" = go127 ] || fail "upgrading the selected line keeps it selected"
[ "$(cat "$MGup/var/go127/state")" = state ] && [ "$(cat "$MGup/var/go126/state")" = state ] \
  || fail "an upgrade keeps every product's state under opt/mavergreen/var"
[ "$(readlink "$MGup/bin/go")" = ../go127/bin/go ] || fail "upgrading the selected line keeps its bare names: bin/go is $(readlink "$MGup/bin/go")"
[ "$(readlink "$MGup/bin/go-127")" = ../go127/bin/go ] || fail "upgrading a line puts its versioned names back"
[ "$(readlink "$MGup/bin/go-126")" = ../go126/bin/go ] || fail "upgrading one line leaves another line's links alone"


printf 'if [ -f "$ROOT/opt/mavergreen/openssh/bin/ssh" ]; then echo saw-old-tree >> "$ROOT/prehook.log"; else echo tree-gone >> "$ROOT/prehook.log"; fi\n' > "$w/prehook"
sh "$S" --stage "$st" --product openssh --version 1 --scripts-out "$w/scr-pre" --preinstall-hook "$w/prehook" \
  || fail "staging with a preinstall hook must succeed"
Vp="$w/volpre"; MGp="$Vp/opt/mavergreen"
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

V2="$w/vol-hooks"; T2="$V2/opt/mavergreen"; mkhelper "$V2"
printf 'false\n' > "$w/hook-false"
printf 'exit 0\n' > "$w/hook-exit"
printf 'if [ -z "$ROOT" ]; then false; fi\n' > "$w/hook-guarded"
sh "$S" --stage "$st" --product openssh --version 1 --scripts-out "$w/scr-false" \
  --preinstall-hook "$w/hook-false" --postinstall-hook "$w/hook-false" || fail "staging with failing hooks must succeed"
sh "$S" --stage "$st" --product openssh --version 1 --scripts-out "$w/scr-exit" \
  --preinstall-hook "$w/hook-exit" || fail "staging with an exiting hook must succeed"
sh "$S" --stage "$st" --product openssh --version 1 --scripts-out "$w/scr-guarded" \
  --postinstall-hook "$w/hook-guarded" || fail "staging with a guarded hook must succeed"
cp -R "$st/opt/mavergreen/openssh" "$T2/"
"$T2/bin/mavergreen" --root "$V2/" link openssh || fail "setup: link the installed version"
rc=0; sh "$w/scr-false/preinstall" /x.pkg "$V2/" "$V2/" 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "a failing preinstall hook must fail the install -- it is how a preset refuses a missing dependency"
[ -f "$T2/openssh/mavergreen.plist" ] || fail "a failing preinstall hook must stop the install before the tree is removed"
[ -L "$T2/bin/ssh" ] || fail "a failing preinstall hook must leave the installed version linked, as it was"
grep -q 'preinstall hook failed' "$w/err" || fail "the failure names the preinstall hook: $(cat "$w/err")"
sh "$w/scr-exit/preinstall" /x.pkg "$V2/" "$V2/" || fail "a hook that exits 0 early is not a failure"
[ ! -e "$T2/openssh" ] || fail "a hook's exit must not skip the tree removal -- each hook runs in a subshell"
cp -R "$st/opt/mavergreen/openssh" "$T2/"
rc=0; sh "$w/scr-false/postinstall" /x.pkg "$V2/" "$V2/" 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "a failing postinstall hook must fail the install, not be masked by the trailing exit 0"
grep -q 'postinstall hook failed' "$w/err" || fail "the failure names the postinstall hook: $(cat "$w/err")"
sh "$w/scr-guarded/postinstall" /x.pkg "$V2/" "$V2/" \
  || fail "a running-system step guarded by if [ -z \$ROOT ] is skipped on another volume, and the hook still succeeds"

printf 'echo inside)\n' > "$w/hook-paren"
printf 'echo "unbalanced\n' > "$w/hook-quote"
for h in hook-paren hook-quote; do
  rc=0; sh "$S" --stage "$st" --product openssh --version 1 --scripts-out "$w/scr-$h" \
    --preinstall-hook "$w/$h" 2>"$w/err" || rc=$?
  [ "$rc" -eq 1 ] || fail "a preinstall hook that is not valid sh must be refused at staging ($h), got exit $rc"
  grep -q "$w/$h" "$w/err" || fail "the refusal names the hook ($h): $(cat "$w/err")"
  rc=0; sh "$S" --stage "$st" --product openssh --version 1 --scripts-out "$w/scr-$h-post" \
    --postinstall-hook "$w/$h" 2>"$w/err" || rc=$?
  [ "$rc" -eq 1 ] || fail "a postinstall hook that is not valid sh must be refused at staging ($h), got exit $rc"
  grep -q "$w/$h" "$w/err" || fail "the refusal names the hook ($h): $(cat "$w/err")"
done

if [ "$(id -u)" -eq 0 ]; then
  echo "note: running as root, which ignores directory permissions -- skipping the failed-relink case"
else
  V3="$w/vol-relink"; T3="$V3/opt/mavergreen"; mkhelper "$V3"
  printf 'chmod 555 "$ROOT/opt/mavergreen/bin"; false\n' > "$w/hook-lockfarm"
  sh "$S" --stage "$st" --product openssh --version 1 --scripts-out "$w/scr-lockfarm" \
    --preinstall-hook "$w/hook-lockfarm" || fail "staging with a farm-locking hook must succeed"
  cp -R "$st/opt/mavergreen/openssh" "$T3/"
  "$T3/bin/mavergreen" --root "$V3/" link openssh || fail "setup: link the installed version"
  rc=0; sh "$w/scr-lockfarm/preinstall" /x.pkg "$V3/" "$V3/" 2>"$w/err" || rc=$?
  chmod 755 "$T3/bin"
  [ "$rc" -ne 0 ] || fail "a failing preinstall hook fails the install even when the relink fails"
  [ ! -L "$T3/bin/ssh" ] || fail "fixture: the locked farm must have kept the relink out"
  grep -q 'could not relink; run `mavergreen link openssh`' "$w/err" || fail "a failed relink is reported with its remedy: $(cat "$w/err")"
  ! grep -q 'left in place' "$w/err" || fail "a failed relink must not claim the installed version is left in place: $(cat "$w/err")"
fi

printf 'if [ -f "$ROOT/Library/Application Support/Mavergreen/openssh-helper.app/Contents/Stale" ]; then echo saw-old-bundle >> "$ROOT/bundlehook.log"; else echo bundle-gone >> "$ROOT/bundlehook.log"; fi\n' > "$w/bundlehook"
sh "$S" --stage "$st" --product openssh --version 1 --scripts-out "$w/scr-bundle" \
  --preinstall-hook "$w/bundlehook" || fail "staging with a preinstall hook must succeed"
mkvol() {
  _v="$1"; rm -rf "$_v" "$_v.out"; mkdir -p "$_v.out/escape.app" "$_v.out/linked/x.app"
  _u="$_v/Library/Application Support/Mavergreen"
  mkdir -p "$_u/openssh-helper.app/Contents" "$_u/other-helper.app" "$_v/Library/LaunchAgents" "$_v/Library/NotABundle" \
    "$_v/opt/mavergreen/openssh" "$_v/opt/mavergreen/other/x.app" "$_v/Library/Java/JavaVirtualMachines/x.jdk/Contents" "$_v/System/Library/Filesystems/z.fs/Contents"
  : > "$_v/Library/Java/JavaVirtualMachines/x.jdk/Contents/Stale"; : > "$_v/System/Library/Filesystems/z.fs/Contents/Stale"
  : > "$_u/openssh-helper.app/Contents/Stale"; : > "$_u/openssh-helper.app/Contents/Info.plist"
  : > "$_v/Library/LaunchAgents/dev.mavergreen.openssh-updatecheck.plist"; : > "$_v/Library/NotABundle/f"
  ln -s "$_v.out/linked" "$_v/Library/Linked"; ln -s "$_v.out/escape.app" "$_v/Library/Symlinked.app"
}
V4="$w/vol-bundles"; mkvol "$V4"; M4="$V4/opt/mavergreen/openssh/mavergreen.plist"
{ printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>outside</key><array>\n'
for o in "Library/Application Support/Mavergreen/openssh-helper.app" "Library/LaunchAgents/dev.mavergreen.openssh-updatecheck.plist" \
  Library/NotABundle ../vol-bundles.out/escape.app "$V4.out/escape.app" Library/Linked/x.app Library/Symlinked.app \
  opt/mavergreen/other/x.app "Library/./Application Support/Mavergreen/other-helper.app" "Library/Missing.app" \
  Library/Java/JavaVirtualMachines/x.jdk System/Library/Filesystems/z.fs; do
  printf '<string>%s</string>\n' "$o"
done
printf '</array></dict></plist>\n'; } > "$M4"
sh "$w/scr-bundle/preinstall" /x.pkg "$V4/" "$V4/" 2>"$w/err" || fail "a preinstall that clears the installed bundles must succeed: $(cat "$w/err")"
[ "$(cat "$V4/bundlehook.log")" = saw-old-bundle ] \
  || fail "the product's preinstall hook runs before its bundles are cleared, so it can unload a kext first"
[ ! -e "$V4/Library/Application Support/Mavergreen/openssh-helper.app" ] \
  || fail "the installed manifest's updater bundle is cleared, so a file the new version drops cannot break its seal"
[ ! -e "$V4/Library/Java/JavaVirtualMachines/x.jdk" ] || fail "an installed .jdk bundle is cleared like an .app, so a file the new version drops cannot linger"
[ ! -e "$V4/System/Library/Filesystems/z.fs" ] || fail "an installed .fs bundle is cleared like an .app, so a file the new version drops cannot linger"
[ -f "$V4/Library/LaunchAgents/dev.mavergreen.openssh-updatecheck.plist" ] || fail "a listed file is left for the payload to overwrite"
[ -f "$V4/Library/NotABundle/f" ] || fail "a listed directory that is not a bundle is never cleared"
[ -d "$V4.out/escape.app" ] || fail "an entry that climbs out of the volume is never cleared"
[ -d "$V4.out/linked/x.app" ] || fail "an entry whose parent resolves outside the volume is never cleared"
[ -L "$V4/Library/Symlinked.app" ] || fail "a bundle entry that is a symlink is not a bundle directory, and is left alone"
[ -d "$V4/opt/mavergreen/other/x.app" ] || fail "an entry inside the mavergreen tree is never cleared"
[ -d "$V4/Library/Application Support/Mavergreen/other-helper.app" ] || fail "an entry with a ./ component is never cleared"
for nm in missing invalid; do
  V5="$w/vol-$nm"; mkvol "$V5"
  [ "$nm" = missing ] || printf 'not a plist\n' > "$V5/opt/mavergreen/openssh/mavergreen.plist"
  sh "$w/scr-bundle/preinstall" /x.pkg "$V5/" "$V5/" 2>"$w/err" || fail "a preinstall with a $nm installed manifest must succeed: $(cat "$w/err")"
  [ -f "$V5/Library/Application Support/Mavergreen/openssh-helper.app/Contents/Stale" ] \
    || fail "with a $nm installed manifest, no bundle is cleared"
done

stp="$w/stage-porthole"; mkdir -p "$stp/opt/mavergreen/porthole/bin"
echo porthole > "$stp/opt/mavergreen/porthole/bin/porthole"
SCRP="$w/scr-porthole"
reqs container-tools service -
sh "$S" --stage "$stp" --product porthole --version 1 --scripts-out "$SCRP" \
  || fail "staging porthole with requires/container-tools must succeed"
sh -n "$SCRP/preinstall" || fail "generated preinstall with a requirement must be valid sh"

Vreq="$w/vol-requires-ok"; mkdir -p "$Vreq/opt/mavergreen/container-tools"
: > "$Vreq/opt/mavergreen/container-tools/mavergreen.plist"
sh "$SCRP/preinstall" /x.pkg "$Vreq/" "$Vreq/" || fail "preinstall proceeds when the required product's manifest exists"

mglog="$w/mg-req.log"; : > "$mglog"
reqvol() {
  _rv="$1"; shift
  mkdir -p "$_rv/opt/mavergreen/porthole/bin" "$_rv/opt/mavergreen/bin"
  echo old > "$_rv/opt/mavergreen/porthole/bin/porthole"
  printf '#!/bin/sh\necho called "$@" >> "%s"\n' "$mglog" > "$_rv/opt/mavergreen/bin/mavergreen"
  chmod +x "$_rv/opt/mavergreen/bin/mavergreen"
  while [ $# -ge 2 ]; do
    mkdir -p "$_rv/opt/mavergreen/$1"
    _rvp="$_rv/opt/mavergreen/$1/mavergreen.plist"
    if [ "$2" = - ]; then
      xplist "$_rvp" name x
    else
      xplist "$_rvp" version "$2"
    fi
    shift 2
  done
}
Vmiss="$w/vol-requires-missing"; reqvol "$Vmiss"
rc=0; sh "$SCRP/preinstall" /x.pkg "$Vmiss/" "$Vmiss/" 2>"$w/req-err" || rc=$?
[ "$rc" -eq 1 ] || fail "preinstall must exit 1 when a required product is missing, got $rc"
grep -q "Porthole needs container-tools installed first" "$w/req-err" \
  || fail "the refusal names this product's display name and the missing requirement: $(cat "$w/req-err")"
grep -q "https://github.com/Mavergreen/container-tools/releases " "$w/req-err" \
  || fail "the refusal names the missing requirement's releases URL: $(cat "$w/req-err")"
[ -f "$Vmiss/opt/mavergreen/porthole/bin/porthole" ] \
  || fail "a missing requirement must leave the existing installed tree untouched"
[ ! -s "$mglog" ] || fail "a missing requirement is checked before mavergreen unlink runs: $(cat "$mglog")"

SCRP2="$w/scr-porthole2"
reqs container-tools service - openssh tool -
sh "$S" --stage "$stp" --product porthole --version 1 --scripts-out "$SCRP2" \
  || fail "staging porthole with two requirements must succeed"
Vtwo="$w/vol-requires-two"; mkdir -p "$Vtwo/opt/mavergreen/openssh"
: > "$Vtwo/opt/mavergreen/openssh/mavergreen.plist"
rc=0; sh "$SCRP2/preinstall" /x.pkg "$Vtwo/" "$Vtwo/" 2>"$w/req-err2" || rc=$?
[ "$rc" -eq 1 ] || fail "preinstall must exit 1 when one of two requirements is missing, got $rc"
grep -q "container-tools" "$w/req-err2" || fail "the missing requirement (container-tools) must be named: $(cat "$w/req-err2")"
grep -q "openssh" "$w/req-err2" && fail "the satisfied requirement (openssh) must not be named: $(cat "$w/req-err2")"

reqs xcode external -
sh "$S" --stage "$stp" --product porthole --version 1 --scripts-out "$w/scr-external" \
  || fail "an external requirement needs no ingredient and stages"
grep -q xcode "$w/scr-external/preinstall" && fail "an external requirement generates nothing"

reqs nonexistent-product tool -
rc=0; sh "$S" --stage "$stp" --product porthole --version 1 --scripts-out "$w/scr-badreq" 2>"$w/err" || rc=$?
[ "$rc" -eq 2 ] || fail "staging with a requirement the repo has no ingredient for must exit 2, got $rc"
grep -q '.mavergreen/ingredients/nonexistent-product/REPO' "$w/err" || fail "the refusal says where to declare the requirement's REPO: $(cat "$w/err")"
mkdir -p "$repo/.mavergreen/ingredients/norepo"; echo norepo > "$repo/.mavergreen/ingredients/norepo/product"
reqs norepo tool -
rc=0; sh "$S" --stage "$stp" --product porthole --version 1 --scripts-out "$w/scr-norepo-req" 2>"$w/err" || rc=$?
[ "$rc" -eq 2 ] || fail "staging with a requirement whose ingredient has no REPO must exit 2, got $rc"
grep -q '.mavergreen/ingredients/norepo/REPO' "$w/err" || fail "the refusal names the ingredient missing its REPO: $(cat "$w/err")"
echo notarepo > "$repo/.mavergreen/ingredients/norepo/REPO"
rc=0; sh "$S" --stage "$stp" --product porthole --version 1 --scripts-out "$w/scr-norepo-req" 2>"$w/err" || rc=$?
[ "$rc" -eq 2 ] && grep -q 'owner/repo' "$w/err" || fail "a REPO that is not owner/repo is refused (2), got $rc: $(cat "$w/err")"
mkdir -p "$repo/.mavergreen/ingredients/porthole"; echo Mavergreen/porthole > "$repo/.mavergreen/ingredients/porthole/REPO"
reqs porthole tool -
rc=0; sh "$S" --stage "$stp" --product porthole --version 1 --scripts-out "$w/scr-selfreq" 2>"$w/err" || rc=$?
[ "$rc" -eq 2 ] || fail "staging with a requirement naming the product itself must exit 2, got $rc"
grep -q 'requires/porthole' "$w/err" || fail "the refusal names the self-requirement: $(cat "$w/err")"
rm -rf "$repo/.mavergreen/ingredients/porthole"

SCRM="$w/scr-porthole-min"
reqs container-tools service 20261019.1
sh "$S" --stage "$stp" --product porthole --version 1 --scripts-out "$SCRM" \
  || fail "staging porthole with requires/container-tools/min 20261019.1 must succeed"
sh -n "$SCRM/preinstall" || fail "generated preinstall with a minimum must be valid sh"
sh "$here/../scripts/check-shell-portability.sh" "$SCRM/preinstall" >/dev/null \
  || fail "generated preinstall with a minimum must pass check-shell-portability.sh"
sh "$here/../scripts/check-shell-portability.sh" "$SCRM/postinstall" >/dev/null \
  || fail "generated postinstall must pass check-shell-portability.sh"
grep -q mavergreen_vercmp "$SCRP/preinstall" && fail "a preinstall with no minimum carries no comparator"
for v in 20261019.1 20261019.2; do
  V="$w/vol-min-$v"; reqvol "$V" container-tools "$v"
  sh "$SCRM/preinstall" /x.pkg "$V/" "$V/" 2>"$w/err" \
    || fail "preinstall proceeds when the required product is at $v (minimum 20261019.1): $(cat "$w/err")"
  [ ! -s "$w/err" ] || fail "a met minimum ($v) prints nothing: $(cat "$w/err")"
done
V="$w/vol min old"; : > "$mglog"; reqvol "$V" container-tools 20261018.9
rc=0; sh "$SCRM/preinstall" /x.pkg "$V/" "$V/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "preinstall must exit 1 when the required product is older than the minimum, got $rc"
[ "$(cat "$w/err")" = "Porthole needs container-tools 20261019.1 or newer (installed: 20261018.9): https://github.com/Mavergreen/container-tools/releases -- update it, then run this installer again." ] \
  || fail "the refusal names the requirement, its minimum and the installed version: $(cat "$w/err")"
[ -f "$V/opt/mavergreen/porthole/bin/porthole" ] \
  || fail "an unmet minimum must leave the existing installed tree untouched"
[ ! -s "$mglog" ] || fail "an unmet minimum is checked before mavergreen unlink runs: $(cat "$mglog")"
V="$w/vol min ok"; reqvol "$V" container-tools 20261019.1
sh "$SCRM/preinstall" /x.pkg "$V/" "$V/" 2>"$w/err" \
  || fail "a volume path containing a space must work with a minimum: $(cat "$w/err")"
for v in - 1.0-rc1 dict; do
  V="$w/vol-min-unorderable$v"
  case "$v" in
    -) reqvol "$V" container-tools -; shown=none ;;
    dict) reqvol "$V" container-tools -; shown='Dict {'
      printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>version</key><dict><key>a</key><string>1</string></dict></dict></plist>\n' > "$V/opt/mavergreen/container-tools/mavergreen.plist" ;;
    *) reqvol "$V" container-tools "$v"; shown="$v" ;;
  esac
  rc=0; sh "$SCRM/preinstall" /x.pkg "$V/" "$V/" 2>"$w/err" || rc=$?
  [ "$rc" -eq 1 ] || fail "preinstall must exit 1 when the installed version ($v) cannot be compared, got $rc"
  [ "$(cat "$w/err")" = "Porthole needs container-tools 20261019.1 or newer, but its installed version ($shown) cannot be compared: https://github.com/Mavergreen/container-tools/releases -- update it, then run this installer again." ] \
    || fail "the refusal says the installed version ($v) cannot be compared: $(cat "$w/err")"
  [ -f "$V/opt/mavergreen/porthole/bin/porthole" ] \
    || fail "an uncomparable installed version ($v) must leave the existing installed tree untouched"
done

SCRM2="$w/scr-porthole-min2"
reqs container-tools service 20261019.1 openssh tool 9.9p2
sh "$S" --stage "$stp" --product porthole --version 1 --scripts-out "$SCRM2" \
  || fail "staging porthole with two minimums must succeed"
[ "$(grep -c '^mavergreen_vercmp()' "$SCRM2/preinstall")" -eq 1 ] \
  || fail "the comparator is inlined once, however many minimums there are"
V="$w/vol-min-one-unmet"; reqvol "$V" container-tools 20261019.1 openssh 9.9p1
rc=0; sh "$SCRM2/preinstall" /x.pkg "$V/" "$V/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "preinstall must exit 1 when one of two minimums is unmet, got $rc"
[ "$(cat "$w/err")" = "Porthole needs openssh 9.9p2 or newer (installed: 9.9p1): https://github.com/Mavergreen/openssh/releases -- update it, then run this installer again." ] \
  || fail "only the unmet minimum (openssh) is named: $(cat "$w/err")"
V="$w/vol-min-both-unmet"; reqvol "$V" container-tools 20261018.9 openssh 9.9p1
rc=0; sh "$SCRM2/preinstall" /x.pkg "$V/" "$V/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "preinstall must exit 1 when both minimums are unmet, got $rc"
[ "$(cat "$w/err")" = "Porthole needs container-tools 20261019.1 or newer (installed: 20261018.9): https://github.com/Mavergreen/container-tools/releases -- update it, then run this installer again.
Porthole needs openssh 9.9p2 or newer (installed: 9.9p1): https://github.com/Mavergreen/openssh/releases -- update it, then run this installer again." ] \
  || fail "both unmet minimums must be named: $(cat "$w/err")"
V="$w/vol-min-absent-and-rc"; : > "$mglog"; reqvol "$V" openssh 1.0-rc1
rc=0; sh "$SCRM2/preinstall" /x.pkg "$V/" "$V/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "preinstall must exit 1 when one requirement is absent and another cannot be compared, got $rc"
[ "$(cat "$w/err")" = "Porthole needs container-tools installed first: https://github.com/Mavergreen/container-tools/releases -- install it, then run this installer again.
Porthole needs openssh 9.9p2 or newer, but its installed version (1.0-rc1) cannot be compared: https://github.com/Mavergreen/openssh/releases -- update it, then run this installer again." ] \
  || fail "an absent requirement and an uncomparable one are both reported before exit 1: $(cat "$w/err")"
[ ! -s "$mglog" ] && [ -f "$V/opt/mavergreen/porthole/bin/porthole" ] || fail "unmet requirements change nothing"

reqs container-tools service -
V="$w/vol-nomin-any"; reqvol "$V" container-tools 1.0-rc1
sh "$SCRP/preinstall" /x.pkg "$V/" "$V/" 2>"$w/err" \
  || fail "a requirement with no minimum passes with any installed version: $(cat "$w/err")"

SD="$(sh "$here/../scripts/fetch_stevedore.sh")" || fail "fetch_stevedore.sh failed"
for u in 077 022; do
  mkdir -p "$w/um$u/opt/mavergreen/openssh/bin"; echo ssh > "$w/um$u/opt/mavergreen/openssh/bin/ssh"
  (umask $u; sh "$S" --stage "$w/um$u" --product openssh --version 1 --scripts-out "$w/umscr$u") >/dev/null 2>&1 || fail "stage_product must run under umask $u"
  SOURCE_DATE_EPOCH=1700000000 "$SD" component --root "$w/um$u" --scripts "$w/umscr$u" --identifier dev.mavergreen.openssh --version 1 --install-location / --mtime 1700000000 --out "$w/um$u.pkg" || fail "component must build under umask $u"
done
cmp "$w/um077.pkg" "$w/um022.pkg" || fail "stage_product output ignores umask"

for bad in '' 1.0-rc1 abc; do
  reqs container-tools service "$bad"
  rc=0; sh "$S" --stage "$stp" --product porthole --version 1 --scripts-out "$w/scr-badmin" 2>"$w/err" || rc=$?
  [ "$rc" -eq 2 ] || fail "staging with requires/container-tools/min '$bad' must exit 2, got $rc"
  [ "$(cat "$w/err")" = "stage_product: .mavergreen/products/porthole/requires/container-tools/min: '$bad' is not an orderable version (see scripts/lib/vercmp.sh)" ] \
    || fail "the refusal names the file and the value '$bad': $(cat "$w/err")"
done

echo "PASS: stage-product"
