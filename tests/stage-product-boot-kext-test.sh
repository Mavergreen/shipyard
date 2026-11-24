#!/bin/sh
# platform: host-agnostic
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Kexts that load at boot" --
#       stage_product.sh --boot-kext, its generated postinstall and pre-uninstall, against copies of
#       10.9.5 (13F1911)'s AppleKextExcludeList Info.plist; launchctl is a stub
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/stage_product.sh"
REAL="$here/fixtures/kext-sig-exception/AppleKextExcludeList-13F1911.plist"
SD="$(sh "$here/../scripts/fetch_stevedore.sh")" || { echo "FAIL: fetch_stevedore.sh failed"; exit 1; }; export STEVEDORE="$SD"
w="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/stage-boot-kext.XXXXXX")" && pwd)"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
umask 022
MAVERGREEN_CHAIN_UID="$(id -u)"; export MAVERGREEN_CHAIN_UID
mkdir -p "$w/repo/.mavergreen/products/recaulk"; echo Recaulk > "$w/repo/.mavergreen/products/recaulk/noun"
MAVERGREEN_REPO_ROOT="$w/repo"; GITHUB_REPOSITORY=Mavergreen/recaulk; export MAVERGREEN_REPO_ROOT GITHUB_REPOSITORY
XLREL=System/Library/Extensions/AppleKextExcludeList.kext/Contents/Info.plist
K1=dev.mavergreen.example.bootkext
K2=dev.mavergreen.example.second
kext() {  # $1 = stage, $2 = kext path, $3 = id, $4 = version, $5 = text before the top-level keys (optional)
  mkdir -p "$1/$2/Contents"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n%s\t<key>CFBundleIdentifier</key>\n\t<string>%s</string>\n\t<key>CFBundleVersion</key>\n\t<string>%s</string>\n</dict>\n</plist>\n' \
    "${5:-}" "$3" "$4" > "$1/$2/Contents/Info.plist"
}
stage() {  # $1 = stage dir
  rm -rf "$1"; mkdir -p "$1/opt/mavergreen/recaulk/bin"; echo x > "$1/opt/mavergreen/recaulk/bin/x"
  kext "$1" Library/Extensions/Boot.kext "$K1" 2611.23.5
  kext "$1" "Library/Filesystems/x y.fs/Contents/Extensions/10.9/Second.kext" "$K2" 1.0.0d1
  kext "$1" Library/Extensions/Library.kext dev.mavergreen.example.library 3.0
}
stubs="$w/stubs"; log="$w/launchctl.log"; mkdir -p "$stubs"
printf '#!/bin/sh\nprintf "%%s listed=%%s\\n" "$*" "$(grep -c "<key>%s</key>" "%s" 2>/dev/null || :)" >> "%s"\n' "$K1" "$w/vol/$XLREL" "$log" > "$stubs/launchctl"
chmod +x "$stubs/launchctl"
cat > "$w/hook" <<'EOF'
if [ -z "$ROOT" ]; then
  /bin/launchctl load /Library/LaunchDaemons/dev.mavergreen.example.loader.plist
fi
EOF
redirect() {  # $1 = generated postinstall, $2 = volume: every target path and launchctl go to the test's
  sed -e "s#\"\$ROOT/#\"$2/#g" -e "s#\"\$ROOT\"/#\"$2\"/#g" -e "s#/bin/launchctl#$stubs/launchctl#g" \
    -e 's#^mavergreen_chain_ok "$_mg_at" "$3" || exit 1$#:#' "$1" > "$1.r"
  grep -q '"$ROOT/' "$1.r" && fail "the redirected postinstall still names a target path through \$ROOT"
  grep -q '/bin/launchctl' "$1.r" && fail "the redirected postinstall still runs the real launchctl"
  return 0
}
volume() {  # $1 = volume dir, $2 = stage
  rm -rf "$1"; mkdir -p "$1/opt/mavergreen/.base/9.9" "$(dirname "$1/$XLREL")"
  cp -R "$2/." "$1/"
  sh "$here/../scripts/build-base-component.sh" --emit-helper "$1/opt/mavergreen/.base/9.9/mavergreen" --version 9.9
  cp "$REAL" "$1/$XLREL"
}
entry() { grep -A1 "<key>$1</key>" "$w/vol/$XLREL" | sed -n 2p; }

echo "== staging"
st="$w/stage"; stage "$st"
LX="$st/opt/mavergreen/recaulk/libexec/mavergreen"
mkdir -p "$LX"; printf '#!/bin/sh\n# platform: host-agnostic\necho product-hook "$MAVERGREEN_ROOT" >> "%s"\n' "$w/hook.log" > "$LX/pre-uninstall"
chmod +x "$LX/pre-uninstall"
sh "$S" --stage "$st" --product recaulk --version 1 --scripts-out "$w/scr" \
  --postinstall-hook "$w/hook" --boot-kext "$K1" --boot-kext "$K2" || fail "staging with --boot-kext must succeed"
cmp -s "$LX/kext-sig-exception" "$here/../scripts/kext_sig_exception.sh" || fail "the tool is staged into the product's libexec"
[ -x "$LX/kext-sig-exception" ] && [ -x "$LX/pre-uninstall" ] || fail "the tool and the pre-uninstall hook are executable"
grep -q product-hook "$LX/pre-uninstall.product" || fail "the product's own pre-uninstall hook is kept as pre-uninstall.product"
sh -n "$w/scr/postinstall" && sh -n "$LX/pre-uninstall" || fail "the generated scripts are valid sh"
sh "$S" --stage "$st" --product recaulk --version 1 --scripts-out "$w/scr" \
  --postinstall-hook "$w/hook" --boot-kext "$K1" --boot-kext "$K2" || fail "staging again must succeed"
grep -q product-hook "$LX/pre-uninstall.product" || fail "staging again keeps the product's own hook"
grep -q 'kext-sig-exception" remove' "$LX/pre-uninstall" || fail "staging again leaves the generated hook in place"
n_kx="$(grep -n kext-sig-exception "$w/scr/postinstall" | head -1 | cut -d: -f1)"
n_hook="$(grep -n dev.mavergreen.example.loader "$w/scr/postinstall" | cut -d: -f1)"
[ "$n_kx" -lt "$n_hook" ] || fail "the exception and the kextd restart come before the postinstall hook"
grep -q dev.mavergreen.example.library "$w/scr/postinstall" "$LX/pre-uninstall" && fail "an undeclared kext is listed"

echo "== refusals"
r="$w/refused"
for a in "--boot-kext dev.mavergreen.absent" "--boot-kext bad<id" "--boot-kext $K1 --boot-kext $K1" "--boot-kext"; do
  stage "$r"
  # platform: $a is split on purpose, into its options
  if sh "$S" --stage "$r" --product recaulk --version 1 --scripts-out "$w/scr-r" $a 2>/dev/null; then
    fail "accepted: $a"
  fi
done
stage "$r"; kext "$r" Library/Extensions/Twin.kext "$K1" 1.0
sh "$S" --stage "$r" --product recaulk --version 1 --scripts-out "$w/scr-r" --boot-kext "$K1" 2>/dev/null \
  && fail "two kexts with one id must be refused"
stage "$r"; kext "$r" Library/Extensions/Boot.kext "$K1" 2611.23.5 "$(printf '\t<key>IOKitPersonalities</key>\n\t<dict>\n\t\t<key>CFBundleVersion</key>\n\t\t<string>9.9</string>\n\t</dict>\n')"
sh "$S" --stage "$r" --product recaulk --version 1 --scripts-out "$w/scr-r" --boot-kext "$K1" 2>"$w/err" \
  && fail "a kext whose first CFBundleVersion is not its own must be refused: the postinstall would list the wrong version"
grep -q CFBundleVersion "$w/err" || fail "the refusal names CFBundleVersion: $(cat "$w/err")"
stage "$r"; mkdir -p "$r/opt/mavergreen/recaulk/libexec/mavergreen"
: > "$r/opt/mavergreen/recaulk/libexec/mavergreen/pre-uninstall"; : > "$r/opt/mavergreen/recaulk/libexec/mavergreen/pre-uninstall.product"
sh "$S" --stage "$r" --product recaulk --version 1 --scripts-out "$w/scr-r" --boot-kext "$K1" 2>/dev/null \
  && fail "a staged pre-uninstall.product beside a product pre-uninstall must be refused"

echo "== postinstall to another volume"
V="$w/vol"; volume "$V" "$st"; : > "$log"
sed -e "s#/bin/launchctl#$stubs/launchctl#g" "$w/scr/postinstall" > "$w/post-other"
grep -q /bin/launchctl "$w/post-other" && fail "the test must stub launchctl"
sh "$w/post-other" /x.pkg "$V/" "$V/" || fail "the postinstall must succeed"
[ "$(entry "$K1")" = "$(printf '\t\t<string>2611.23.5</string>')" ] || fail "$K1 is listed at its installed CFBundleVersion, 2611.23.5: $(entry "$K1")"
[ "$(entry "$K2")" = "$(printf '\t\t<string>1.0.0d1</string>')" ] || fail "$K2 is listed at its installed CFBundleVersion, 1.0.0d1: $(entry "$K2")"
[ ! -s "$log" ] || fail "an install to another volume never restarts kextd or loads a job: $(cat "$log")"
[ "$(($(wc -l < "$V/$XLREL") - $(wc -l < "$REAL")))" = 4 ] || fail "only the two declared ids are added"
sh "$w/post-other" /x.pkg "$V/" "$V/" || fail "a second postinstall must succeed"
[ "$(grep -c "<key>$K1</key>" "$V/$XLREL")" = 1 ] || fail "a reinstall lists $K1 once"
kext "$V" Library/Extensions/Boot.kext "$K1" 2612.1.1
sh "$w/post-other" /x.pkg "$V/" "$V/" || fail "an upgrade's postinstall must succeed"
[ "$(entry "$K1")" = "$(printf '\t\t<string>2612.1.1</string>')" ] || fail "an upgrade lists the new installed version: $(entry "$K1")"

echo "== pre-uninstall"
: > "$w/hook.log"
MAVERGREEN_ROOT="$V/" "$V/opt/mavergreen/recaulk/libexec/mavergreen/pre-uninstall" || fail "the pre-uninstall hook must succeed"
cmp -s "$V/$XLREL" "$REAL" || fail "the pre-uninstall hook restores Apple's file byte for byte"
grep -qx "product-hook $V/" "$w/hook.log" || fail "the product's own hook runs: $(cat "$w/hook.log")"
MAVERGREEN_ROOT="$V/" "$V/opt/mavergreen/recaulk/libexec/mavergreen/pre-uninstall" || fail "the pre-uninstall hook succeeds with no entry"
cmp -s "$V/$XLREL" "$REAL" || fail "a pre-uninstall with no entry changes nothing"
sh "$w/post-other" /x.pkg "$V/" "$V/" || fail "reinstalling must succeed"
cp "$V/$XLREL" "$w/listed"
printf '#!/bin/sh\nexit 3\n' > "$V/opt/mavergreen/recaulk/libexec/mavergreen/pre-uninstall.product"
rc=0; MAVERGREEN_ROOT="$V/" "$V/opt/mavergreen/recaulk/libexec/mavergreen/pre-uninstall" || rc=$?
[ "$rc" = 3 ] || fail "a failing product hook's status stops the uninstall; got $rc"
cmp -s "$V/$XLREL" "$w/listed" || fail "a stopped uninstall leaves the entries in place"
rm "$V/$XLREL"
rm "$V/opt/mavergreen/recaulk/libexec/mavergreen/pre-uninstall.product"
MAVERGREEN_ROOT="$V/" "$V/opt/mavergreen/recaulk/libexec/mavergreen/pre-uninstall" || fail "a volume with no exclude list is not a failure"

echo "== a volume with no exclude list"
volume "$V" "$st"; rm "$V/$XLREL"; : > "$log"
redirect "$w/scr/postinstall" "$V"
PATH="$stubs:$PATH" sh "$w/scr/postinstall.r" /x.pkg / / 2>"$w/err" || fail "a volume with no exclude list is not a failure"
[ -s "$w/err" ] && fail "a volume with no exclude list is quiet: $(cat "$w/err")"
[ "$(grep -c kextd "$log" || :)" = 0 ] || fail "with nothing listed, kextd is not restarted: $(cat "$log")"

echo "== postinstall to the boot volume"
volume "$V" "$st"; : > "$log"
PATH="$stubs:$PATH" sh "$w/scr/postinstall.r" /x.pkg / / || fail "the boot-volume postinstall must succeed"
[ "$(entry "$K1")" = "$(printf '\t\t<string>2611.23.5</string>')" ] || fail "the boot volume lists $K1 at 2611.23.5: $(entry "$K1")"
printf 'stop com.apple.kextd listed=1\nload /Library/LaunchDaemons/dev.mavergreen.example.loader.plist listed=1\n' | cmp -s - "$log" \
  || fail "on the boot volume the entry is written, then kextd restarts, then the hook loads its daemon: $(cat "$log")"
volume "$V" "$st"; printf '<?xml version="1.0"?>\n<plist version="1.0"><dict/></plist>\n' > "$V/$XLREL"; : > "$log"
PATH="$stubs:$PATH" sh "$w/scr/postinstall.r" /x.pkg / / 2>"$w/err" || fail "a refused exclude list does not fail the install"
grep -q "kext-dev-mode" "$w/err" || fail "a refused exclude list is reported: $(cat "$w/err")"
[ "$(grep -c kextd "$log" || :)" = 0 ] || fail "with nothing listed, kextd is not restarted: $(cat "$log")"

echo "stage-product-boot-kext OK"
