#!/bin/sh
# platform: host-agnostic
set -eu
SOURCE_DATE_EPOCH=1700000000; export SOURCE_DATE_EPOCH
here="$(cd "$(dirname "$0")" && pwd)"
w="$(mktemp -d "${TMPDIR:-/tmp}/floor-base.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
mkdir -p "$w/root/usr/local/mavergreen/x" "$w/c"; echo x > "$w/root/usr/local/mavergreen/x/f"
SD="$(sh "$here/../scripts/fetch_stevedore.sh")" || fail "fetch_stevedore.sh failed -- the pkg block is the only gate for this seam, so it cannot be skipped"
"$SD" component --root "$w/root" --identifier dev.mavergreen.x --version 1.0 --install-location / --mtime "$SOURCE_DATE_EPOCH" --out "$w/c/x.pkg"
sh "$here/../scripts/set_install_floor.sh" --identifier dev.mavergreen.x --title X --component "$w/c/x.pkg" \
  --out "$w/out.pkg" --base-version 1.0.9 >/dev/null 2>&1 || fail "the archive must build"
"$SD" expand "$w/out.pkg" "$w/x"
[ -d "$w/x/mavergreen-base.pkg" ] || fail "the archive carries the base component"
first="$(sed -n 's/.*<line choice="\([^"]*\)".*/\1/p' "$w/x/Distribution" | grep -v '^default$' | head -1)"
[ "$first" = dev.mavergreen.base ] || fail "the base component is listed first, so its postinstall installs or upgrades the helper before the product's postinstall runs it: got $first"
grep -q 'os-version min="10.9.5"' "$w/x/Distribution" || fail "the floor is still enforced"

awk '{ n += gsub(/<line choice=/, "&"); if (gsub(/<line choice=/, "&") > 1) bad = 1 } END { exit !(n == 3 && !bad) }' "$w/x/Distribution" \
  || fail "the Distribution carries one <line choice=...> per line, so a line-oriented parse never depends on the packager reformatting it: $(grep -n 'line choice' "$w/x/Distribution")"

rc=0
sh "$here/../scripts/set_install_floor.sh" --identifier dev.mavergreen.base --title Base --component "$w/c/x.pkg" \
  --out "$w/out2.pkg" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "--identifier dev.mavergreen.base must be refused as a usage error (exit 2), since the base is added automatically and a caller passing it as the product identifier would collide with it; got $rc"
[ ! -e "$w/out2.pkg" ] || fail "a refused --identifier dev.mavergreen.base must not write an output pkg"

mkdir -p "$w/res"; printf '<html><body>restart to finish</body></html>\n' > "$w/res/Conclusion.html"
sh "$here/../scripts/set_install_floor.sh" --identifier dev.mavergreen.x --title X --component "$w/c/x.pkg" \
  --out "$w/out-c.pkg" --base-version 1.0.9 --resources "$w/res" --conclusion Conclusion.html >/dev/null 2>&1 \
  || fail "an archive with a conclusion pane must build"
"$SD" expand "$w/out-c.pkg" "$w/xc"
grep -q '<conclusion file="Conclusion.html"' "$w/xc/Distribution" \
  || fail "--conclusion names the pane in the Distribution -- the only surface Installer shows after the scripts run"
[ -f "$w/xc/Resources/Conclusion.html" ] || fail "the conclusion file ships in the archive's Resources"
rc=0
sh "$here/../scripts/set_install_floor.sh" --identifier dev.mavergreen.x --title X --component "$w/c/x.pkg" \
  --out "$w/out-c2.pkg" --conclusion Conclusion.html >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "--conclusion without --resources is a usage error (exit 2) -- the Distribution would name a file nothing ships; got $rc"

rc=0
sh "$here/../scripts/set_install_floor.sh" --identifier dev.mavergreen.x --title X --component "$w/c/x.pkg" \
  --out "$w/out-c3.pkg" --resources "$w/res" --conclusion "../Conclusion.html" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "--conclusion is interpolated into the Distribution XML, so a value with a slash must be refused as a usage error; got $rc"
[ ! -e "$w/out-c3.pkg" ] || fail "a refused --conclusion must not write an output pkg"

rc=0
sh "$here/../scripts/set_install_floor.sh" --identifier dev.mavergreen.x --title X --component "$w/c/x.pkg" \
  --out "$w/out-c4.pkg" --resources "$w/res" --conclusion 'Conclusion".html' >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "--conclusion is interpolated into the Distribution XML, so a value with a quote must be refused as a usage error; got $rc"
[ ! -e "$w/out-c4.pkg" ] || fail "a refused --conclusion must not write an output pkg"

rc=0
sh "$here/../scripts/set_install_floor.sh" --identifier dev.mavergreen.x --title X --component "$w/c/x.pkg" \
  --out "$w/out-c5.pkg" --resources "$w/res" --conclusion >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "--conclusion given last with no value is a usage error (exit 2), not an unbound-variable crash; got $rc"
[ ! -e "$w/out-c5.pkg" ] || fail "a refused --conclusion with no value must not write an output pkg"

rc=0
sh "$here/../scripts/set_install_floor.sh" --identifier dev.mavergreen.x --title X --component "$w/c/x.pkg" \
  --out "$w/out-c6.pkg" --resources "$w/res" --conclusion 'a&b.html' >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "--conclusion is interpolated into the Distribution XML, so a value with & must be refused as a usage error; got $rc"
[ ! -e "$w/out-c6.pkg" ] || fail "a refused --conclusion must not write an output pkg"

rc=0
sh "$here/../scripts/set_install_floor.sh" --identifier dev.mavergreen.x --title X --component "$w/c/x.pkg" \
  --out "$w/out-c7.pkg" --resources "$w/res" --conclusion 'a<b.html' >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "--conclusion is interpolated into the Distribution XML, so a value with < must be refused as a usage error; got $rc"
[ ! -e "$w/out-c7.pkg" ] || fail "a refused --conclusion must not write an output pkg"

rc=0
sh "$here/../scripts/set_install_floor.sh" --identifier dev.mavergreen.x --title X --component "$w/c/x.pkg" \
  --out "$w/out-c8.pkg" --resources "$w/res" --conclusion NoSuchFile.html >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "--conclusion naming a file absent from --resources is a usage error (exit 2), not a silently-broken pane; got $rc"
[ ! -e "$w/out-c8.pkg" ] || fail "a refused --conclusion for a missing file must not write an output pkg"

(umask 077; TMPDIR="$w/tmpa"; mkdir -p "$TMPDIR"; export TMPDIR; sh "$here/../scripts/set_install_floor.sh" --identifier dev.mavergreen.x --title X --component "$w/c/x.pkg" --out "$w/seam-a.pkg" --base-version 1.0.9 >/dev/null 2>&1) || fail "the archive must build under umask 077"
(umask 022; TMPDIR="$w/tmpb-with-a-longer-name"; mkdir -p "$TMPDIR"; export TMPDIR; sh "$here/../scripts/set_install_floor.sh" --identifier dev.mavergreen.x --title X --component "$w/c/x.pkg" --out "$w/seam-b.pkg" --base-version 1.0.9 >/dev/null 2>&1) || fail "the archive must build under umask 022"
cmp "$w/seam-a.pkg" "$w/seam-b.pkg" || fail "seam output ignores umask and TMPDIR"

mkdir -p "$w/res2"; cp "$w/res/Conclusion.html" "$w/res2/Conclusion.html"
for t in a b; do
  case $t in a) um=077;; b) um=022;; esac
  mkdir -p "$w/rtmp$t-xx"
  (umask $um; TMPDIR="$w/rtmp$t-xx"; export TMPDIR; sh "$here/../scripts/set_install_floor.sh" --identifier dev.mavergreen.x --title X --component "$w/c/x.pkg" --out "$w/rseam-$t.pkg" --base-version 1.0.9 --resources "$w/res2" --conclusion Conclusion.html >/dev/null 2>&1) || fail "the archive with a conclusion must build under umask $um"
done
cmp "$w/rseam-a.pkg" "$w/rseam-b.pkg" || fail "seam output with --resources and a conclusion ignores umask and TMPDIR"

echo "PASS: set-install-floor-base"
