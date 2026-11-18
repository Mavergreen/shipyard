#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/build-base-component.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/base-component.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
umask 022
MAVERGREEN_CHAIN_UID="$(id -u)"; export MAVERGREEN_CHAIN_UID
mode() { ls -ld "$1" | cut -c1-10; }

sh "$S" --emit-helper "$w/helper" --version 1.0.9 || fail "--emit-helper stamps the helper"
[ "$(sh "$w/helper" version)" = 1.0.9 ] || fail "the stamped helper prints its version"
grep -q 'SELF/lib' "$w/helper" && fail "the stamped helper inlines lib/root-chain.sh instead of sourcing it from a checkout it will not have"
grep -q '^mavergreen_chain_ok()' "$w/helper" || fail "the stamped helper carries the chain check inline"
sh "$S" --emit-preinstall "$w/pre" --version 1.0.9 || fail "--emit-preinstall renders the preinstall"
sh "$S" --emit-postinstall "$w/post" --version 1.0.9 || fail "--emit-postinstall renders the postinstall"
for f in pre post; do
  grep -q 'SELF/lib' "$w/$f" && fail "the rendered $f inlines its libs: a preinstall runs before any payload lands"
  grep -q '@MAVERGREEN_VERSION@' "$w/$f" && fail "the rendered $f carries its version"
  sh -n "$w/$f" || fail "the rendered $f is valid sh"
done

V="$w/empty"; mkdir "$V"
sh "$w/pre" /fake.pkg "$V/" "$V/" 2>"$w/err" || fail "the preinstall passes an empty volume: $(cat "$w/err")"
[ "$(mode "$V/opt")" = drwxr-xr-x ] || fail "the preinstall creates opt 755: $(mode "$V/opt")"
[ "$(mode "$V/opt/mavergreen")" = drwxr-xr-x ] || fail "the preinstall creates opt/mavergreen 755: $(mode "$V/opt/mavergreen")"
[ ! -e "$V/Applications" ] || fail "the preinstall never creates Applications/Mavergreen"
sh "$w/pre" /fake.pkg "$V/" "$V/" 2>"$w/err" || fail "the preinstall passes a volume it already prepared: $(cat "$w/err")"

V="$w/gw"; mkdir -p "$V/opt"; chmod 775 "$V/opt"
rc=0; sh "$w/pre" /fake.pkg "$V/" "$V/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "a group-writable opt makes the preinstall exit 1: got $rc"
grep -q "/opt: group-writable.*fix: sudo chmod go-w " "$w/err" || fail "the refusal names opt, the rule and its fix: $(cat "$w/err")"
[ ! -e "$V/opt/mavergreen" ] || fail "a refused opt gets no opt/mavergreen"

V="$w/optlink"; mkdir -p "$V/elsewhere"; ln -s elsewhere "$V/opt"
rc=0; sh "$w/pre" /fake.pkg "$V/" "$V/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "an opt that is a symlink makes the preinstall exit 1: got $rc"
[ ! -e "$V/elsewhere/mavergreen" ] || fail "a refused opt link gets nothing written through it"

V="$w/mgow"; mkdir -p "$V/opt/mavergreen"; chmod 757 "$V/opt/mavergreen"
rc=0; sh "$w/pre" /fake.pkg "$V/" "$V/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "an other-writable opt/mavergreen makes the preinstall exit 1: got $rc"
grep -q "/opt/mavergreen: other-writable" "$w/err" || fail "the refusal names opt/mavergreen and the rule: $(cat "$w/err")"

V="$w/applink"; mkdir -p "$V/Applications" "$V/mine"; ln -s ../mine "$V/Applications/Mavergreen"
rc=0; sh "$w/pre" /fake.pkg "$V/" "$V/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "an Applications/Mavergreen symlink makes the preinstall exit 1: got $rc"
grep -q "Applications/Mavergreen: symlink" "$w/err" || fail "the refusal names Applications/Mavergreen: $(cat "$w/err")"
[ -L "$V/Applications/Mavergreen" ] || fail "the preinstall leaves the refused link in place"

V="$w/appfile"; mkdir -p "$V/Applications"; : > "$V/Applications/Mavergreen"
rc=0; sh "$w/pre" /fake.pkg "$V/" "$V/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "an Applications/Mavergreen that is not a directory makes the preinstall exit 1: got $rc"
grep -q "Applications/Mavergreen: not a directory" "$w/err" || fail "the refusal names Applications/Mavergreen: $(cat "$w/err")"

V="$w/appgw"; mkdir -p "$V/Applications/Mavergreen"; chmod 775 "$V/Applications/Mavergreen"
rc=0; sh "$w/pre" /fake.pkg "$V/" "$V/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "a hand-made Applications/Mavergreen that fails the rules makes the preinstall exit 1: got $rc"
grep -q "Applications/Mavergreen: group-writable" "$w/err" && grep -q "Applications/Mavergreen.*remove it" "$w/err" \
  || fail "the refusal names Applications/Mavergreen and says to remove it: $(cat "$w/err")"
[ "$(mode "$V/Applications/Mavergreen")" = drwxrwxr-x ] || fail "a refused Applications/Mavergreen is never silently fixed"

V="$w/appok"; mkdir -p "$V/Applications/Mavergreen"
sh "$w/pre" /fake.pkg "$V/" "$V/" 2>"$w/err" || fail "an Applications/Mavergreen owned by the trusted uid passes: $(cat "$w/err")"

rc=0; (cd "$w/empty" && sh "$w/pre" /fake.pkg) >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "with no target volume the preinstall exits 1 rather than assume /: got $rc"

SOURCE_DATE_EPOCH=1700000000; export SOURCE_DATE_EPOCH
SD="$(sh "$here/../scripts/fetch_stevedore.sh")" || fail "fetch_stevedore.sh failed -- the pkg block is the only gate for this seam, so it cannot be skipped"
for v in 1.0.9 1.0.10; do
  sh "$S" --version "$v" --out "$w/base-$v.pkg" >/dev/null 2>&1 || fail "the $v component must build"
  "$SD" expand "$w/base-$v.pkg" "$w/x-$v"
done
X="$w/x-1.0.9"
grep -q 'identifier="dev.mavergreen.base"' "$X/PackageInfo" || fail "the component is dev.mavergreen.base"
(cd "$X" && gzip -dc Payload | cpio -it 2>/dev/null) | LC_ALL=C sort > "$w/payload"
printf '%s\n' . ./opt ./opt/mavergreen ./opt/mavergreen/.base ./opt/mavergreen/.base/1.0.9 \
  ./opt/mavergreen/.base/1.0.9/manpaths ./opt/mavergreen/.base/1.0.9/mavergreen \
  ./opt/mavergreen/.base/1.0.9/mavergreen-vercmp ./opt/mavergreen/.base/1.0.9/paths | LC_ALL=C sort > "$w/want"
cmp -s "$w/payload" "$w/want" || fail "the payload stages exactly the four files under opt/mavergreen/.base/<V>/, nothing under usr/: $(cat "$w/payload")"
cmp -s "$X/Scripts/preinstall" "$w/pre" || fail "the component's preinstall is the one --emit-preinstall renders"
cmp -s "$X/Scripts/postinstall" "$w/post" || fail "the component's postinstall is the one --emit-postinstall renders"
[ -x "$X/Scripts/preinstall" ] && [ -x "$X/Scripts/postinstall" ] || fail "both scripts are executable"

V="$w/vol"; mkdir "$V"
install_base() {  # $1 version: what Installer does -- the preinstall, the payload, then the postinstall
  sh "$w/x-$1/Scripts/preinstall" /fake.pkg "$V/" "$V/" || fail "the $1 preinstall passes"
  (cd "$V" && gzip -dc "$w/x-$1/Payload" | cpio -idm 2>/dev/null)
  sh "$w/x-$1/Scripts/postinstall" /fake.pkg "$V/" "$V/"
}
H="$V/opt/mavergreen/mavergreen"
install_base 1.0.9 || fail "the 1.0.9 postinstall passes"
[ "$(sh "$V/opt/mavergreen/bin/mavergreen" version)" = 1.0.9 ] || fail "a first install puts the helper on the farm's bin"
[ "$(readlink "$V/opt/mavergreen/bin/mavergreen")" = ../mavergreen/bin/mavergreen ] || fail "bin/mavergreen links to ../mavergreen/bin/mavergreen: $(readlink "$V/opt/mavergreen/bin/mavergreen")"
for f in "$H/bin/mavergreen" "$H/libexec/mavergreen-vercmp"; do
  [ -f "$f" ] && [ ! -L "$f" ] || fail "$f is a file"
  [ "$(mode "$f")" = -rwxr-xr-x ] || fail "$f is 755: $(mode "$f")"
done
for d in "$H" "$H/bin" "$H/libexec" "$V/opt/mavergreen/bin"; do
  [ "$(mode "$d")" = drwxr-xr-x ] || fail "$d is 755: $(mode "$d")"
done
rc=0; sh "$H/libexec/mavergreen-vercmp" 1.0.9 1.0.10 || rc=$?
[ "$rc" -eq 0 ] || fail "the installed mavergreen-vercmp runs alone: got $rc"
printf '/opt/mavergreen/bin\n/opt/mavergreen/sbin\n' > "$w/paths"
cmp -s "$V/etc/paths.d/mavergreen" "$w/paths" || fail "paths.d names both farm bin dirs, one per line: $(cat "$V/etc/paths.d/mavergreen")"
[ "$(cat "$V/etc/manpaths.d/mavergreen")" = /opt/mavergreen/share/man ] || fail "manpaths.d names the farm's man dir"
[ "$(cat "$V/opt/mavergreen/.base/installed-version")" = 1.0.9 ] || fail "installed-version records 1.0.9"
[ ! -e "$V/opt/mavergreen/.base/1.0.9" ] || fail "the staged copy is cleared"
[ ! -e "$V/usr" ] || fail "nothing installs under usr/"
install_base 1.0.10 || fail "the 1.0.10 postinstall passes"
[ "$(sh "$V/opt/mavergreen/bin/mavergreen" version)" = 1.0.10 ] || fail "1.0.10 is newer than 1.0.9 -- the comparison is numeric, not lexical"
install_base 1.0.9 || fail "an older postinstall still passes"
[ "$(sh "$V/opt/mavergreen/bin/mavergreen" version)" = 1.0.10 ] || fail "an older product installer must never downgrade the helper"
[ ! -e "$V/opt/mavergreen/.base/1.0.9" ] || fail "a skipped older base still clears its staged copy"
printf 'garbage\n' > "$V/opt/mavergreen/.base/installed-version"
out="$(install_base 1.0.9 2>&1)" || fail "an older base installs over a malformed installed-version: $out"
[ "$(sh "$V/opt/mavergreen/bin/mavergreen" version)" = 1.0.9 ] || fail "a malformed installed-version is treated as missing, not compared"
[ "$(cat "$V/opt/mavergreen/.base/installed-version")" = 1.0.9 ] || fail "installed-version is rewritten after installing over a malformed value"
case "$out" in *"integer expression expected"*) fail "a malformed installed-version must not reach the comparison: $out" ;; esac
install_base 1.0.10 >/dev/null 2>&1 || fail "1.0.10 reinstalls"
rm "$H/bin/mavergreen"; install_base 1.0.9 || fail "an older base passes over a missing helper"
[ "$(sh "$V/opt/mavergreen/bin/mavergreen" version)" = 1.0.9 ] || fail "a missing helper is reinstalled even from an older base"
install_base 1.0.10 >/dev/null 2>&1 || fail "1.0.10 reinstalls"
rm "$H/libexec/mavergreen-vercmp"; install_base 1.0.9 || fail "an older base passes over a missing mavergreen-vercmp"
[ -x "$H/libexec/mavergreen-vercmp" ] || fail "a missing mavergreen-vercmp is reinstalled even from an older base"

(cd "$V" && gzip -dc "$w/x-1.0.10/Payload" | cpio -idm 2>/dev/null)
chmod 775 "$V/opt/mavergreen"
rc=0; sh "$w/x-1.0.10/Scripts/postinstall" /fake.pkg "$V/" "$V/" 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "the postinstall verifies the chain again and refuses a group-writable opt/mavergreen: got $rc"
grep -q "/opt/mavergreen: group-writable" "$w/err" || fail "the postinstall's refusal names opt/mavergreen: $(cat "$w/err")"
[ "$(sh "$V/opt/mavergreen/bin/mavergreen" version)" = 1.0.9 ] || fail "a refused postinstall installs nothing"
chmod 755 "$V/opt/mavergreen"
rc=0; sh "$w/x-1.0.10/Scripts/postinstall" /fake.pkg >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "with no target volume the postinstall exits 1 rather than assume /: got $rc"

V="$w/etcdir"; mkdir -p "$V/etc/paths.d/mavergreen"
rc=0; install_base 1.0.9 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "a paths.d entry it cannot write makes the postinstall exit 1: got $rc"
[ ! -e "$V/opt/mavergreen/.base/installed-version" ] || fail "a failed paths.d write records no installed-version, so the next base retries"
[ -z "$(ls "$V/etc/paths.d/mavergreen")" ] || fail "nothing is moved into a paths.d entry that is a directory"

sh "$S" --out "$w/bad.pkg" --version 'v1.0' 2>/dev/null && fail "a non-numeric version must be refused -- the compare is numeric"
SHIPYARD_VERSION=7.7.7 sh "$S" --emit-postinstall "$w/post-env" \
  || fail "with no installed config, SHIPYARD_VERSION names the base's version (install@v1 exports it on Linux, where the action's checkout has no .git)"
grep -q '7\.7\.7' "$w/post-env" || fail "the emitted postinstall carries SHIPYARD_VERSION's version"
echo "PASS: base-component"
