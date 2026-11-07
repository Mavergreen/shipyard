#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/package-system-replace.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/system-replace-pkg.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
R="$w/repo/.mavergreen/products"
for n in Bad_Name 'ab;id' 'ab$(x)cd'; do mkdir -p "$R/$n"; echo "$n" > "$R/$n/noun"; done
mkdir -p "$R/openssh"; echo OpenSSH > "$R/openssh/noun"
MAVERGREEN_REPO_ROOT="$w/repo"; export MAVERGREEN_REPO_ROOT

sh "$S" --emit-postinstall "$w/post" --product openssh
grep -q 'system-replace openssh' "$w/post" || fail "the postinstall runs the helper's system-replace for this product"
sh "$S" --emit-postinstall "$w/post" --product no-such 2>/dev/null && fail "a product the repo does not declare must be refused"
out="$(sh "$w/post" 2>&1)" && fail "no target volume must fail: $out"

sh "$S" --emit-postinstall "$w/post" --product openssh
sh -n "$w/post" || fail "the generated postinstall must be valid POSIX sh (sh -n)"
grep -q 'ROOT="${3%/}"' "$w/post" || fail "the generated postinstall computes ROOT by trimming a trailing slash off \$3"
root_join="$(sh -c 'ROOT="${1%/}"; printf %s "$ROOT/"' _ /)"
[ "$root_join" = "/" ] || fail "with \$3 = / the trimmed ROOT is empty, so --root \"\$ROOT/\" must still be / (got: $root_join)"

rc=0
sh "$S" --emit-postinstall "$w/post" --product 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "an option given without a value must be a usage error, exit 2, never a hang or a silent mis-parse (got $rc)"

rc=0
sh "$S" --product openssh --dist "$w/d0" --version 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "an option given without a value at the end of the argument list must be a usage error, exit 2 (got $rc)"

rc=0
sh "$S" --emit-postinstall "$w/post2" --product Bad_Name 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "a declared but malformed short name (not matching ^[a-z0-9][a-z0-9-]*\$) must still be refused before anything is emitted, exit 2 (got $rc)"
[ ! -e "$w/post2" ] || fail "a refused product name must not emit a postinstall"


rc=0
sh "$S" --emit-postinstall "$w/inject1" --product 'ab;id' 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "a disallowed character past position 2 ('ab;id') must be refused by the shape check, exit 2, even though the repo declares it -- a case pattern's trailing * matches anything, so [a-z0-9][a-z0-9-]* only constrains the first two characters (got $rc)"
[ ! -e "$w/inject1" ] || fail "a refused product name must not emit a postinstall (ab;id)"

rc=0
sh "$S" --emit-postinstall "$w/inject2" --product 'ab$(x)cd' 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "a disallowed character past position 2 ('ab\$(x)cd') must be refused by the shape check, exit 2 -- \$P is interpolated unquoted into the generated postinstall's exec line, which runs as root, so this is the injection shape (got $rc)"
[ ! -e "$w/inject2" ] || fail "a refused product name must not emit a postinstall (ab\$(x)cd)"

rc=0
sh "$S" --emit-postinstall "$w/inject3" --product 'ab/cd' 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "a disallowed character past position 2 ('ab/cd') must be refused by the shape check, exit 2 (got $rc)"
[ ! -e "$w/inject3" ] || fail "a refused product name must not emit a postinstall (ab/cd)"

rc=0
sh "$S" --emit-postinstall "$w/inject4" --product 'ab cd' 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "a disallowed character past position 2 ('ab cd') must be refused by the shape check, exit 2; exit 2 (not 1) proves the SHAPE check, not the declaration lookup, is what caught it (got $rc)"
[ ! -e "$w/inject4" ] || fail "a refused product name must not emit a postinstall (ab cd)"

for f in title out; do
  rc=0
  err="$(sh "$S" --product openssh --version 1 --dist "$w/r-$f" "--$f" x 2>&1 >/dev/null)" || rc=$?
  [ "$rc" -eq 2 ] || fail "--$f is refused as a usage error (exit 2): got $rc"
  [ ! -e "$w/r-$f" ] || fail "a refused --$f writes nothing"
  case "$f" in
    title) printf '%s\n' "$err" | grep -qF 'write .mavergreen/products/<short>/noun' || fail "the refusal of --title names its fix: $err" ;;
    out) printf '%s\n' "$err" | grep -qF 'pass --dist' || fail "the refusal of --out names its fix: $err" ;;
  esac
done

SOURCE_DATE_EPOCH=1700000000; export SOURCE_DATE_EPOCH
SD="$(sh "$here/../scripts/fetch_stevedore.sh")" || fail "fetch_stevedore.sh failed -- the pkg block is the only gate for this seam, so it cannot be skipped"
out="$(sh "$S" --product openssh --version 10.5p1-mavergreen.5 --dist "$w/d" --base-version 1.0.9 2>/dev/null)" \
  || fail "the pkg must build"
[ "$out" = "$w/d/openssh-system-replace-10.5p1-mavergreen.5.pkg" ] \
  || fail "the System Replace pkg is <short>-system-replace-<version>.pkg, and its path is printed: got '$out'"
"$SD" expand "$out" "$w/x"
grep -q 'id="dev.mavergreen.openssh.system-replace"' "$w/x/Distribution" || fail "the component is <identifier>.system-replace"
grep -qF '<title>Mavergreen OpenSSH System Replace</title>' "$w/x/Distribution" \
  || fail "the Installer title is Mavergreen <name> System Replace: $(grep title "$w/x/Distribution")"
grep -q 'dev.mavergreen.base' "$w/x/Distribution" || fail "it carries the base like every product archive"
C="$w/x/openssh-system-replace.pkg"
[ -d "$C" ] || fail "the expanded archive carries openssh-system-replace.pkg"
[ ! -e "$C/Payload" ] || fail "the system-replace pkg has no payload member"
[ -f "$C/PackageInfo" ] || fail "the expanded system-replace component has a PackageInfo"
! grep -q "<payload" "$C/PackageInfo" || fail "the system-replace component declares a payload, so it would install files"
[ ! -e "$C/Bom" ] || fail "the system-replace component carries a Bom, so it would install files"
for t in a b; do
  case $t in a) um=077;; b) um=022;; esac
  mkdir -p "$w/tmp$t-xx"
  (umask $um; TMPDIR="$w/tmp$t-xx"; export TMPDIR; sh "$S" --product openssh --version 10.5p1-mavergreen.5 --dist "$w/seam-$t" --base-version 1.0.9 >/dev/null 2>&1) || fail "the pkg must build under umask $um"
done
cmp "$w/seam-a/openssh-system-replace-10.5p1-mavergreen.5.pkg" "$w/seam-b/openssh-system-replace-10.5p1-mavergreen.5.pkg" || fail "seam output ignores umask and TMPDIR"

echo "PASS: package-system-replace"
