#!/bin/sh
# platform: host-agnostic
#   usage: derive-pkg-tree-test.sh
#          scripts/derive_pkg_tree.sh: the pkg tree is the standalone tree less each bundled
#          requirement and any directory that leaves empty, plus each pkg-only path, with modes and
#          links kept and the standalone tree untouched; adding the bundles back gives the standalone
#          tree again. It refuses a bundled requirement that is not a declared requires, a bundled path
#          the tree lacks and a pkg-only destination the tree has (exit 1), and a usage error, a bad
#          --requires, a bad list line, a missing pkg-only source and an existing output (exit 2); a
#          refused run leaves no output.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
D="$here/../scripts/derive_pkg_tree.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/derive-pkg-tree.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: derive-pkg-tree: $*"; exit 1; }
run() { rc=0; sh "$D" "$@" > "$w/out" 2> "$w/err" || rc=$?; }
want() {  # $1 = exit status, $2 = label, then the arguments
  _want="$1" _label="$2"; shift 2
  run "$@"
  [ "$rc" -eq "$_want" ] || fail "$_label: exit $rc, want $_want: $(cat "$w/err")"
}

SA="$w/stand alone/w-1.0"
mkdir -p "$SA/bin" "$SA/libexec/w/bundled/rg/bin" "$SA/libexec/w/bundled/ed25519/share/doc" "$SA/share/w" "$SA/share/empty"
printf '#!/bin/sh\nexec "$(dirname "$0")/../libexec/w/bundled/rg/bin/rg" "$@"\n' > "$SA/bin/w"
chmod 755 "$SA/bin/w"
printf 'rg\n' > "$SA/libexec/w/bundled/rg/bin/rg"; chmod 755 "$SA/libexec/w/bundled/rg/bin/rg"
printf 'license\n' > "$SA/libexec/w/bundled/ed25519/share/doc/LICENSE"
printf 'keep\n' > "$SA/libexec/w/keep"
printf '1.0\n' > "$SA/share/w/version"; chmod 600 "$SA/share/w/version"
ln -s ../share/w/version "$SA/bin/version"
L="$w/bundled list"
printf 'rg libexec/w/bundled/rg\n\ned25519 libexec/w/bundled/ed25519\n' > "$L"
mkdir -p "$w/hooks/mavergreen"; printf '#!/bin/sh\n' > "$w/hooks/mavergreen/uninstall"; chmod 755 "$w/hooks/mavergreen/uninstall"
(cd "$SA" && find . | LC_ALL=C sort) > "$w/before"

want 0 "a derivation" --requires rg --requires 'ed25519>=1.2' --pkg-only "$w/hooks/mavergreen=libexec/mavergreen" "$SA" "$L" "$w/pkg tree"
grep -q 'dropped 2 bundled requirement(s), added 1 pkg-only path(s)' "$w/err" || fail "it says what it did: $(cat "$w/err")"
P="$w/pkg tree"
(cd "$P" && find . | LC_ALL=C sort) > "$w/list"
expect='.
./bin
./bin/version
./bin/w
./libexec
./libexec/mavergreen
./libexec/mavergreen/uninstall
./libexec/w
./libexec/w/keep
./share
./share/empty
./share/w
./share/w/version'
[ "$(cat "$w/list")" = "$expect" ] || fail "the pkg tree drops the bundles and the directory they leave empty, keeps an empty directory of its own, and adds the pkg-only path: $(cat "$w/list")"
[ -x "$P/bin/w" ] && [ -x "$P/libexec/mavergreen/uninstall" ] || fail "executables keep their mode"
[ "$(ls -l "$P/share/w/version" | cut -c1-10)" = "-rw-------" ] || fail "a file keeps its mode: $(ls -l "$P/share/w/version")"
[ -L "$P/bin/version" ] && [ "$(readlink "$P/bin/version")" = ../share/w/version ] || fail "a link stays the same link"
(cd "$SA" && find . | LC_ALL=C sort) > "$w/after"
cmp -s "$w/before" "$w/after" || fail "the standalone tree is left as it was"

mkdir "$w/round"; cp -pRP "$P/." "$w/round/"; rm -rf "$w/round/libexec/mavergreen"
while read -r s p; do
  [ -n "$s" ] || continue
  mkdir -p "$w/round/$(dirname "$p")"; cp -pRP "$SA/$p" "$w/round/$p"
done < "$L"
diff -r "$SA" "$w/round" > "$w/diff" 2>&1 || fail "the pkg tree, its pkg-only path gone and its bundles back, is the standalone tree: $(cat "$w/diff")"

: > "$w/empty list"
want 0 "an empty list" "$SA" "$w/empty list" "$w/copy"
diff -r "$SA" "$w/copy" > "$w/diff" 2>&1 || fail "an empty list and no pkg-only path copy the tree unchanged: $(cat "$w/diff")"

want 1 "a bundle that is not a declared requires" --requires rg "$SA" "$L" "$w/no"
grep -q 'ed25519: bundled by .*, but not among the product.s requires (rg )' "$w/err" || fail "the undeclared bundle is named: $(cat "$w/err")"
[ ! -e "$w/no" ] || fail "a refused derivation leaves no output"
want 1 "bundles with no requires at all" "$SA" "$L" "$w/no"
grep -q '^derive_pkg_tree: rg: bundled by' "$w/err" || fail "the first undeclared bundle is named: $(cat "$w/err")"
printf 'rgx libexec/w/bundled/rg\n' > "$w/prefix list"
want 1 "a bundle whose name a requires only begins with" --requires rg "$SA" "$w/prefix list" "$w/no"

printf 'rg libexec/w/bundled/rg\ned25519 libexec/w/bundled/gone\n' > "$w/missing list"
want 1 "a bundled path the tree lacks" --requires rg --requires ed25519 "$SA" "$w/missing list" "$w/no"
grep -q 'ed25519: libexec/w/bundled/gone is not in' "$w/err" || fail "the missing bundle is named: $(cat "$w/err")"
[ ! -e "$w/no" ] || fail "a missing bundle leaves no output"
[ -z "$(find "$w" -name 'no.derive.*' | head -1)" ] || fail "a refused derivation leaves no work directory"

printf 'k\n' > "$w/k"
want 1 "a pkg-only destination the tree has" --requires rg --requires ed25519 --pkg-only "$w/k=libexec/w/keep" "$SA" "$L" "$w/no"
grep -q 'libexec/w/keep is already in' "$w/err" || fail "the clashing destination is named: $(cat "$w/err")"
[ ! -e "$w/no" ] || fail "a clashing pkg-only path leaves no output"
[ -z "$(find "$w" -name 'no.derive.*' | head -1)" ] || fail "a clashing pkg-only path leaves no work directory"

for bad in "rg /abs/path" "rg ../up" "rg a/../../up" "rg a/./b" "rg ./a" "rg a/.." "rg" "rg ." "rg a b" "RG a" "-rg a"; do
  printf '%s\n' "$bad" > "$w/bad list"
  want 2 "a bad list line, '$bad'" --requires rg "$SA" "$w/bad list" "$w/no"
  [ ! -e "$w/no" ] || fail "a bad list line, '$bad', leaves no output"
done
want 2 "a --requires naming no product" --requires 'R>=1' "$SA" "$L" "$w/no"
want 2 "a missing pkg-only source" --pkg-only "$w/nowhere=libexec/x" "$SA" "$L" "$w/no"
want 2 "a pkg-only argument with no =" --pkg-only "$w/k" "$SA" "$L" "$w/no"
for dest in /abs ../up a/../b . ''; do
  want 2 "a pkg-only destination outside the tree, '$dest'" --pkg-only "$w/k=$dest" "$SA" "$L" "$w/no"
done
want 2 "an existing output" --requires rg --requires ed25519 "$SA" "$L" "$w/pkg tree"
want 2 "no arguments"
want 2 "two arguments" "$SA" "$L"
want 2 "an unknown option" --bundled "$L" "$SA" "$L" "$w/no"
want 2 "a --requires with no value" --requires
want 2 "no standalone tree" "$w/nowhere" "$L" "$w/no"
want 2 "no bundled list" "$SA" "$w/nowhere" "$w/no"
[ ! -e "$w/no" ] || fail "a usage error leaves no output"

echo "PASS: derive-pkg-tree"
