#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/package-system-replace.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/system-replace-pkg.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

sh "$S" --emit-postinstall "$w/post" --product openssh
grep -q 'system-replace openssh' "$w/post" || fail "the postinstall runs the helper's system-replace for this product"
sh "$S" --emit-postinstall "$w/post" --product no-such 2>/dev/null && fail "an unregistered product must be refused"
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
sh "$S" --product openssh --title x --version 1 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "an option given without a value at the end of the argument list must be a usage error, exit 2 (got $rc)"

reg="$w/product-names"
printf 'Bad_Name dev.mavergreen.bad-name\n' > "$reg"
rc=0
MAVERGREEN_PRODUCT_NAMES="$reg" sh "$S" --emit-postinstall "$w/post2" --product Bad_Name 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "a registered but malformed short name (not matching ^[a-z0-9][a-z0-9-]*\$) must still be refused before anything is emitted, exit 2 (got $rc)"
[ ! -e "$w/post2" ] || fail "a refused product name must not emit a postinstall"

if command -v productbuild >/dev/null 2>&1; then
  sh "$S" --product openssh --title "OpenSSH System Replace" --version 10.5p1-mavericks.5 --out "$w/r.pkg" --base-version 1.0.9 >/dev/null 2>&1 \
    || fail "the pkg must build"
  pkgutil --expand "$w/r.pkg" "$w/x"
  grep -q 'id="dev.mavergreen.openssh.system-replace"' "$w/x/Distribution" || fail "the component is <identifier>.system-replace"
  grep -q 'dev.mavergreen.base' "$w/x/Distribution" || fail "it carries the base like every product archive"
fi

echo "PASS: package-system-replace"
