#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/stage_product.sh"
[ -x /usr/libexec/PlistBuddy ] || { echo "no PlistBuddy -- skipping"; exit 77; }
w="$(mktemp -d "${TMPDIR:-/tmp}/stage-product.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
st="$w/stage"; mkdir -p "$st/usr/local/mavergreen/openssh/bin"; echo ssh > "$st/usr/local/mavergreen/openssh/bin/ssh"
printf 'echo post-hook-ran "$ROOT" >> "$ROOT/hook.log"\n' > "$w/hook"
sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$w/scr" --postinstall-hook "$w/hook"
[ -f "$st/usr/local/mavergreen/openssh/mavergreen.plist" ] || fail "the manifest is rendered"

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
  && fail "a product with nothing in its tree must be refused"
grep -q 'rm -rf "$ROOT/usr/local/mavergreen/openssh"' "$w/scr/preinstall" \
  || fail "the preinstall's destructive path is a literal, never built from a variable that could be empty"

APP="$w/FakeUpdater.app"
mkdir -p "$APP/Contents/MacOS"
printf '#!/bin/sh\n' > "$APP/Contents/MacOS/FakeUpdater"
chmod +x "$APP/Contents/MacOS/FakeUpdater"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.mavergreen.FakeUpdater</string></dict></plist>\n' > "$APP/Contents/Info.plist"
SCRU="$w/scr-updater"
sh "$S" --stage "$st" --product openssh --name OpenSSH --version 1 --scripts-out "$SCRU" \
  --updater-app "$APP" --app-dir "/Library/Application Support/Mavergreen" \
  --agent-label dev.mavergreen.openssh-updatecheck \
  || fail "stage_product with --updater-app must succeed"
sh -n "$SCRU/preinstall" || fail "generated preinstall (with updater) must be valid sh"
sh -n "$SCRU/postinstall" || fail "generated postinstall (with updater) must be valid sh"
grep -q MAV_AGENT_PLIST "$SCRU/postinstall" \
  || fail "stage_updater's agent-load fragment must land in the postinstall when --updater-app is given"
[ ! -e "$SCRU/.agent-load" ] || fail "the intermediate agent-load snippet must not remain in scripts-out"

fake="$w/fake"; mkdir -p "$fake"
cp "$S" "$fake/stage_product.sh"
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
  --appcast "https://example/x?a=1&b=2" \
  --exclude "bin/extra one" --exclude "share/man/man1/extra.1" \
  --replaces "/usr/bin/ssh=bin/ssh" --replaces "/usr/bin/scp=bin/scp two" \
  --scripts-out "$w/scr3" \
  --updater-app "$w/FakeUpdater.app" \
  --app-dir "/Library/Application Support/Mavergreen" \
  --agent-label dev.mavergreen.openssh-updatecheck \
  --preinstall-hook "$w/hook" --postinstall-hook "$w/hook" \
  || fail "stage_product with a stubbed render-manifest/stage_updater must still succeed"
expected="$(printf '%s\n' \
  --stage "$st2" \
  --product openssh \
  --name "Open SSH Suite" \
  --version 1.2.3 \
  --group opengrp \
  --line 9 \
  --appcast "https://example/x?a=1&b=2" \
  --exclude "bin/extra one" \
  --exclude "share/man/man1/extra.1" \
  --replaces "/usr/bin/ssh=bin/ssh" \
  --replaces "/usr/bin/scp=bin/scp two")"
[ "$(cat "$w/rm.log")" = "$expected" ] \
  || fail "every render-manifest option, in order, with repeats and embedded spaces, must reach render-manifest intact: got [$(cat "$w/rm.log")]"
grep -qE -- '--scripts-out|--updater-app|--app-dir|--agent-label|--preinstall-hook|--postinstall-hook' "$w/rm.log" \
  && fail "a stage_product-only option must never reach render-manifest"
grep -qF "$w/scr3" "$w/rm.log" && fail "a stage_product-only option's VALUE must never reach render-manifest either"
grep -qF "Application Support" "$w/rm.log" && fail "the updater's app-dir value must never reach render-manifest"

echo "PASS: stage-product"
