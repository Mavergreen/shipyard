#!/bin/sh
# platform: host-agnostic
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Kexts that load at boot" --
#       kext-facts.sh reads what a pkg's payload and scripts say about kexts
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
KF="$here/../scripts/kext-facts.sh"
SD="$(sh "$here/../scripts/fetch_stevedore.sh")" || { echo "FAIL: fetch_stevedore.sh failed"; exit 1; }; export STEVEDORE="$SD"
w="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/kext-facts.XXXXXX")" && pwd)"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
kext() {  # $1 = kext dir, $2 = id, $3 = extra top-level keys
  mkdir -p "$1/Contents"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n\t<key>CFBundleIdentifier</key>\n\t<string>%s</string>\n\t<key>CFBundleVersion</key>\n\t<string>1.0</string>\n%s</dict>\n</plist>\n' "$2" "${3:-}" > "$1/Contents/Info.plist"
}
P='	<key>IOKitPersonalities</key>
	<dict>
		<key>x</key>
		<dict/>
	</dict>
'
C='	<key>OSBundleCompatibleVersion</key>
	<string>1.0</string>
'
st="$w/stage"
mkdir -p "$st/usr/local/mavergreen/recaulk/bin"; echo x > "$st/usr/local/mavergreen/recaulk/bin/x"
kext "$st/Library/Extensions/Boot.kext" dev.mavergreen.p.boot "$P"
kext "$st/Library/Extensions/KPI.kext" dev.mavergreen.p.kpi "$C"
kext "$st/Library/Extensions/Both.kext" dev.mavergreen.p.both "$C$P"
kext "$st/Library/Extensions/Plain Name.kext" dev.mavergreen.p.plain
kext "$st/Library/Extensions/Boot.kext/Contents/PlugIns/Inner.kext" dev.mavergreen.p.inner "$C"
sh "$here/../scripts/stage_product.sh" --stage "$st" --product recaulk --name Recaulk --version 1 --scripts-out "$w/scr" \
  --boot-kext dev.mavergreen.p.boot --boot-kext dev.mavergreen.p.plain >/dev/null || fail "staging must succeed"
out="$(sh "$KF" p.pkg --root "$st" --scripts "$w/scr")" || fail "kext-facts.sh failed"
want='kext p.pkg Library/Extensions/Boot.kext dev.mavergreen.p.boot boot
kext p.pkg Library/Extensions/Boot.kext/Contents/PlugIns/Inner.kext dev.mavergreen.p.inner library
kext p.pkg Library/Extensions/Both.kext dev.mavergreen.p.both boot
kext p.pkg Library/Extensions/KPI.kext dev.mavergreen.p.kpi library
kext p.pkg Library/Extensions/Plain%20Name.kext dev.mavergreen.p.plain boot
kext-exception p.pkg dev.mavergreen.p.boot
kext-exception p.pkg dev.mavergreen.p.plain'
[ "$out" = "$want" ] || fail "want:
$want
got:
$out"

mkdir -p "$w/hand"
cp "$w/scr/preinstall" "$w/hand/preinstall"
{ sed '$d' "$w/scr/postinstall"
  printf '%s\n' '_kl="$ROOT/System/Library/Extensions/AppleKextExcludeList.kext/Contents/Info.plist"' \
    'sh "$ROOT/usr/local/mavergreen/recaulk/libexec/recaulk/kext-exception.sh" add "$_kl" dev.mavergreen.p.boot 1.0' 'exit 0'
} > "$w/hand/postinstall"
out="$(sh "$KF" p.pkg --scripts "$w/hand")" || fail "kext-facts.sh failed on hand-written scripts"
printf '%s\n' "$out" | grep -qx 'excludelist-script p.pkg postinstall' \
  || fail "a postinstall that edits the exclude list itself is reported: $out"
printf '%s\n' "$out" | grep -q 'excludelist-script p.pkg preinstall' && fail "an untouched preinstall is reported: $out"
printf 'defaults write /System/Library/Extensions/AppleKextExcludeList.kext/Contents/Info.plist OSKextSigExceptionList -dict-add x 1\n' > "$w/hand/preinstall"
sh "$KF" p.pkg --scripts "$w/hand" | grep -qx 'excludelist-script p.pkg preinstall' || fail "a preinstall that edits the exclude list is reported"
out="$(sh "$KF" p.pkg --scripts "$w/scr")"
printf '%s\n' "$out" | grep -q excludelist-script && fail "the generated block alone is not reported: $out"
out="$(sh "$KF" p.pkg --root "" --scripts "")" || fail "empty --root and --scripts are no work"
[ -z "$out" ] || fail "empty --root and --scripts emit nothing: $out"

mkdir -p "$w/dist" "$w/repo"
"$STEVEDORE" component --root "$st" --identifier dev.mavergreen.recaulk --version 1.0-mavericks.1 --install-location / \
  --mtime 1700000000 --scripts "$w/scr" --out "$w/dist/p.pkg" > /dev/null || fail "stevedore could not build the pkg"
facts="$(sh "$here/../scripts/artifact-facts.sh" "$w/dist" 1.0-mavericks.1 "$w/repo" 2>"$w/err")" || fail "artifact-facts.sh failed: $(cat "$w/err")"
printf '%s\n' "$facts" | grep '^kext' > "$w/kfacts" || :
printf '%s\n' "$want" | cmp -s - "$w/kfacts" || fail "artifact-facts.sh carries kext-facts.sh's facts from a real pkg: $(cat "$w/kfacts")"
echo "kext-facts OK"
