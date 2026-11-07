#!/bin/sh
# platform: host-agnostic
set -eu
SOURCE_DATE_EPOCH=1700000000; export SOURCE_DATE_EPOCH
here="$(cd "$(dirname "$0")" && pwd)"
SIF="$here/../scripts/set_install_floor.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/floor-base.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
P="$w/repo/.mavergreen/products"
noun() { mkdir -p "$P/$1"; printf '%s\n' "$2" > "$P/$1/noun"; }
noun x X; noun go127 Go; printf '1.27\n' > "$P/go127/line"; noun amp 'A&B <x>'; noun shipyard Shipyard; noun base Base
mkdir -p "$P/empty"; : > "$P/empty/noun"
MAVERGREEN_REPO_ROOT="$w/repo"; export MAVERGREEN_REPO_ROOT
SD="$(sh "$here/../scripts/fetch_stevedore.sh")" || fail "fetch_stevedore.sh failed -- the pkg block is the only gate for this seam, so it cannot be skipped"
mkdir -p "$w/root/usr/local/mavergreen/x" "$w/c"; echo x > "$w/root/usr/local/mavergreen/x/f"
comp() { "$SD" component --root "$w/root" --identifier "$2" --version 1.0 --install-location / --mtime "$SOURCE_DATE_EPOCH" --out "$w/c/$1" >/dev/null; }
comp x.pkg dev.mavergreen.x; comp go127-built.pkg dev.mavergreen.go127; comp amp.pkg dev.mavergreen.amp
comp shipyard.pkg dev.mavergreen.shipyard; comp other.pkg dev.mavergreen.other; comp empty.pkg dev.mavergreen.empty
comp base.pkg dev.mavergreen.base

out="$(sh "$SIF" --short x --version 1.0.0-mavergreen.1 --component "$w/c/x.pkg" --dist "$w/d" --base-version 1.0.9 2>/dev/null)" \
  || fail "the archive must build"
[ "$out" = "$w/d/x-1.0.0-mavergreen.1.pkg" ] || fail "set_install_floor.sh prints only the path of the pkg it wrote, named <short>-<version>.pkg in --dist: got '$out'"
"$SD" expand "$out" "$w/x"
[ -d "$w/x/mavergreen-base.pkg" ] || fail "the archive carries the base component"
first="$(sed -n 's/.*<line choice="\([^"]*\)".*/\1/p' "$w/x/Distribution" | grep -v '^default$' | head -1)"
[ "$first" = dev.mavergreen.base ] || fail "the base component is listed first, so its postinstall installs or upgrades the helper before the product's postinstall runs it: got $first"
grep -q 'os-version min="10.9.5"' "$w/x/Distribution" || fail "the floor is still enforced"
awk '{ n += gsub(/<line choice=/, "&"); if (gsub(/<line choice=/, "&") > 1) bad = 1 } END { exit !(n == 3 && !bad) }' "$w/x/Distribution" \
  || fail "the Distribution carries one <line choice=...> per line, so a line-oriented parse never depends on the packager reformatting it: $(grep -n 'line choice' "$w/x/Distribution")"

out="$(sh "$SIF" --short go127 --version 1.27.2-mavergreen.1 --component "$w/c/go127-built.pkg" --dist "$w/d" --base-version 1.0.9 2>/dev/null)" \
  || fail "go127's archive must build"
[ "$out" = "$w/d/go127-1.27.2-mavergreen.1.pkg" ] || fail "go127 at 1.27.2-mavergreen.1 is go127-1.27.2-mavergreen.1.pkg: got '$out'"
"$SD" expand "$out" "$w/xg"
grep -qF '<title>Mavergreen Go 1.27</title>' "$w/xg/Distribution" || fail "the Installer title is derived, Mavergreen <noun> <line>: $(grep title "$w/xg/Distribution")"
grep -q '<pkg-ref id="dev.mavergreen.go127"[^>]*>#*go127.pkg</pkg-ref>' "$w/xg/Distribution" \
  || fail "the component is copied to its derived name, so the pkg-ref names go127.pkg whatever the caller called it: $(grep 'pkg-ref' "$w/xg/Distribution")"
[ -d "$w/xg/go127.pkg" ] || fail "the archive carries the component as go127.pkg"

out="$(sh "$SIF" --short amp --version 1.0 --component "$w/c/amp.pkg" --dist "$w/d" --base-version 1.0.9 2>/dev/null)" \
  || fail "a noun holding XML-special characters still builds"
"$SD" expand "$out" "$w/xa"
grep -qF '<title>Mavergreen A&amp;B &lt;x&gt;</title>' "$w/xa/Distribution" \
  || fail "the Installer title is XML-escaped where it is written: $(grep title "$w/xa/Distribution")"

out="$(sh "$SIF" --short shipyard --version v1.0.300 --component "$w/c/shipyard.pkg" --dist "$w/d" --base-version 1.0.9 2>/dev/null)" \
  || fail "shipyard's archive must build"
[ "$out" = "$w/d/shipyard-1.0.300.pkg" ] || fail "a version's leading v is not part of the filename: got '$out'"

refused() {  # $1 = flag  $2 = its value  $3 = the fix it must name
  rc=0
  err="$(sh "$SIF" --short x --version 1.0 --component "$w/c/x.pkg" --dist "$w/r-$1" "--$1" "$2" 2>&1 >/dev/null)" || rc=$?
  [ "$rc" -eq 2 ] || fail "--$1 is refused as a usage error (exit 2): got $rc"
  printf '%s\n' "$err" | grep -qF -- "$3" || fail "the refusal of --$1 names its fix ($3): got '$err'"
  [ ! -e "$w/r-$1" ] || fail "a refused --$1 writes nothing"
}
refused title X 'write .mavergreen/products/<short>/noun'
refused out "$w/o.pkg" 'the filename is derived, <short>-<version>.pkg; pass --dist'
refused identifier dev.mavergreen.x 'the identifier is dev.mavergreen.<short>'

rc=0
sh "$SIF" --short x --version 1.0 --component "$w/c/other.pkg" --dist "$w/do" >/dev/null 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "a component whose identifier is not dev.mavergreen.<short> must be refused"
grep -q 'dev.mavergreen.other' "$w/err" && grep -q 'dev.mavergreen.x' "$w/err" \
  || fail "the refusal names the identifier found and the one derived: $(cat "$w/err")"
[ -z "$(ls "$w/do" 2>/dev/null)" ] || fail "a refused component writes no pkg"

rc=0
sh "$SIF" --short empty --version 1.0 --component "$w/c/empty.pkg" --dist "$w/de" >/dev/null 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "an empty noun stops the build with status 1: got $rc"
grep -q 'products/empty/noun' "$w/err" || fail "the refusal names the noun file: $(cat "$w/err")"
[ -z "$(ls "$w/de" 2>/dev/null)" ] || fail "an empty noun packages nothing"

rc=0
sh "$SIF" --short base --version 1.0 --component "$w/c/base.pkg" --dist "$w/db" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "a product whose identifier is dev.mavergreen.base is a usage error (exit 2), since the base is added automatically; got $rc"
[ -z "$(ls "$w/db" 2>/dev/null)" ] || fail "a refused dev.mavergreen.base must not write an output pkg"

sif() { sh "$SIF" --short x --version 1.0 --component "$w/c/x.pkg" "$@"; }
mkdir -p "$w/res"; printf '<html><body>restart to finish</body></html>\n' > "$w/res/Conclusion.html"
out="$(sif --dist "$w/dc" --base-version 1.0.9 --resources "$w/res" --conclusion Conclusion.html 2>/dev/null)" \
  || fail "an archive with a conclusion pane must build"
"$SD" expand "$out" "$w/xc"
grep -q '<conclusion file="Conclusion.html"' "$w/xc/Distribution" \
  || fail "--conclusion names the pane in the Distribution -- the only surface Installer shows after the scripts run"
[ -f "$w/xc/Resources/Conclusion.html" ] || fail "the conclusion file ships in the archive's Resources"

conclusion_refused() {  # $1 = label  $2 = why  then the extra args
  _l="$1"; _why="$2"; shift 2
  rc=0
  sif --dist "$w/dr-$_l" "$@" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || fail "$_why; got $rc"
  [ -z "$(ls "$w/dr-$_l" 2>/dev/null)" ] || fail "a refused --conclusion ($_l) must not write an output pkg"
}
conclusion_refused nores "--conclusion without --resources is a usage error (exit 2) -- the Distribution would name a file nothing ships" --conclusion Conclusion.html
conclusion_refused slash "--conclusion is interpolated into the Distribution XML, so a value with a slash must be refused as a usage error" --resources "$w/res" --conclusion ../Conclusion.html
conclusion_refused quote "--conclusion is interpolated into the Distribution XML, so a value with a quote must be refused as a usage error" --resources "$w/res" --conclusion 'Conclusion".html'
conclusion_refused novalue "--conclusion given last with no value is a usage error (exit 2), not an unbound-variable crash" --resources "$w/res" --conclusion
conclusion_refused amp "--conclusion is interpolated into the Distribution XML, so a value with & must be refused as a usage error" --resources "$w/res" --conclusion 'a&b.html'
conclusion_refused lt "--conclusion is interpolated into the Distribution XML, so a value with < must be refused as a usage error" --resources "$w/res" --conclusion 'a<b.html'
conclusion_refused missing "--conclusion naming a file absent from --resources is a usage error (exit 2), not a silently-broken pane" --resources "$w/res" --conclusion NoSuchFile.html

(umask 077; TMPDIR="$w/tmpa"; mkdir -p "$TMPDIR"; export TMPDIR; sif --dist "$w/seam-a" --base-version 1.0.9 >/dev/null 2>&1) || fail "the archive must build under umask 077"
(umask 022; TMPDIR="$w/tmpb-with-a-longer-name"; mkdir -p "$TMPDIR"; export TMPDIR; sif --dist "$w/seam-b" --base-version 1.0.9 >/dev/null 2>&1) || fail "the archive must build under umask 022"
cmp "$w/seam-a/x-1.0.pkg" "$w/seam-b/x-1.0.pkg" || fail "seam output ignores umask and TMPDIR"

mkdir -p "$w/res2"; cp "$w/res/Conclusion.html" "$w/res2/Conclusion.html"
for t in a b; do
  case $t in a) um=077;; b) um=022;; esac
  mkdir -p "$w/rtmp$t-xx"
  (umask $um; TMPDIR="$w/rtmp$t-xx"; export TMPDIR; sif --dist "$w/rseam-$t" --base-version 1.0.9 --resources "$w/res2" --conclusion Conclusion.html >/dev/null 2>&1) || fail "the archive with a conclusion must build under umask $um"
done
cmp "$w/rseam-a/x-1.0.pkg" "$w/rseam-b/x-1.0.pkg" || fail "seam output with --resources and a conclusion ignores umask and TMPDIR"

echo "PASS: set-install-floor-base"
