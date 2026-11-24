#!/bin/sh
# platform: host-agnostic
#   usage: stage-pkg-from-archive-test.sh
#          scripts/stage_pkg_from_archive.sh: an archive stage_standalone.sh made from a pkg root, its
#          bundled requirement among the tree, stages back into that root's tree and app less the
#          bundle and plus the pkg-only path, a bin/ link into the app absolute again, which
#          stage_product.sh and build_component_pkg.sh then take as today. A script naming a declared
#          requires' prefix passes only given that --requires. It refuses an archive the checker
#          refuses, a bundle that is not a declared requires, and a root already holding the tree or
#          an app (exit 1), leaving the root as it was, and a usage or naming error (exit 2).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts"
E="$S/stage_pkg_from_archive.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/stage-pkg-from-archive.XXXXXX")"; trap 'chmod -R u+w "$w" 2>/dev/null; rm -rf "$w"' EXIT
fail() { echo "FAIL: stage-pkg-from-archive: $*"; exit 1; }
want() {  # $1 = exit status, $2 = label, then the arguments
  _want="$1" _label="$2"; shift 2
  rc=0; sh "$E" "$@" > "$w/out" 2> "$w/err" || rc=$?
  [ "$rc" -eq "$_want" ] || fail "$_label: exit $rc, want $_want: $(cat "$w/err")"
}
export SOURCE_DATE_EPOCH=1700000000
mkdir "$w/repo"

R0="$w/root0"; T0="$R0/usr/local/mavergreen/w"
mkdir -p "$T0/bin" "$T0/libexec/w/bundled/clang22/bin" "$T0/share/w" "$R0/Applications/X.app/Contents/MacOS"
printf '#!/bin/sh\nexec "$(dirname "$0")/../libexec/w/bundled/clang22/bin/clang" "$@"\n' > "$T0/bin/w"
printf '#!/bin/sh\necho clang\n' > "$T0/libexec/w/bundled/clang22/bin/clang"
printf '#!/bin/sh\necho x\n' > "$R0/Applications/X.app/Contents/MacOS/x"
chmod 755 "$T0/bin/w" "$T0/libexec/w/bundled/clang22/bin/clang" "$R0/Applications/X.app/Contents/MacOS/x"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n  <key>CFBundleIdentifier</key>\n  <string>dev.mavergreen.x</string>\n</dict>\n</plist>\n' > "$R0/Applications/X.app/Contents/Info.plist"
printf '1.0\n' > "$T0/share/w/version"; chmod 600 "$T0/share/w/version"
ln -s /Applications/X.app/Contents/MacOS/x "$T0/bin/x"
mkdir "$w/dist"
A="$w/dist/w-1.0-macos-x86_64.tar.gz"
sh "$S/stage_standalone.sh" "$R0" w 1.0 x86_64 "$A" > /dev/null 2> "$w/err" || fail "stage_standalone.sh could not make the archive: $(cat "$w/err")"
L="$w/bundled"; printf 'clang22 libexec/w/bundled/clang22\n' > "$L"
mkdir -p "$w/hooks/mavergreen"; printf '#!/bin/sh\n' > "$w/hooks/mavergreen/uninstall"; chmod 755 "$w/hooks/mavergreen/uninstall"

R="$w/root"
want 0 "an archive-first stage" --repo "$w/repo" --requires 'clang22>=22.1' --pkg-only "$w/hooks/mavergreen=libexec/mavergreen" "$A" "$L" "$R"
mkdir -p "$w/want/usr/local/mavergreen"
cp -pRP "$R0/." "$w/want/"
rm -rf "$w/want/usr/local/mavergreen/w/libexec/w"
cp -pRP "$w/hooks/mavergreen" "$w/want/usr/local/mavergreen/w/libexec/"
(cd "$w/want" && find . | LC_ALL=C sort) > "$w/want.list" || exit 1
(cd "$R" && find . | LC_ALL=C sort) > "$w/got.list" || exit 1
diff "$w/want.list" "$w/got.list" > "$w/diff" || fail "the staged root is the pkg root less the bundle, plus the pkg-only path: $(cat "$w/diff")"
[ "$(readlink "$R/usr/local/mavergreen/w/bin/x")" = /Applications/X.app/Contents/MacOS/x ] \
  || fail "a bin/ link into the app is absolute again: $(readlink "$R/usr/local/mavergreen/w/bin/x")"
rm "$w/want/usr/local/mavergreen/w/bin/x" "$R/usr/local/mavergreen/w/bin/x"
diff -r "$w/want" "$R" > "$w/diff" 2>&1 || fail "every staged file is the pkg root's: $(cat "$w/diff")"
ln -s /Applications/X.app/Contents/MacOS/x "$R/usr/local/mavergreen/w/bin/x"
[ "$(ls -l "$R/usr/local/mavergreen/w/share/w/version" | cut -c1-10)" = "-rw-------" ] || fail "a file keeps its mode"
[ -x "$R/usr/local/mavergreen/w/bin/w" ] || fail "an executable keeps its mode"

{ cat "$S/product-names"; printf 'w dev.mavergreen.w w\n'; } > "$w/product-names"
MAVERGREEN_PRODUCT_NAMES="$w/product-names" sh "$S/stage_product.sh" --stage "$R" --product w --name W --version 1.0 --requires 'clang22>=22.1' --scripts-out "$w/scripts" > /dev/null 2> "$w/err" \
  || fail "stage_product.sh takes the staged root: $(cat "$w/err")"
[ -f "$R/usr/local/mavergreen/w/mavergreen.plist" ] || fail "stage_product.sh writes the manifest into the derived tree"
out="$(sh "$S/build_component_pkg.sh" --root "$R" --identifier dev.mavergreen.w --version 1.0 --install-location / \
  --scripts "$w/scripts" --out "$w/w.pkg" 2> "$w/err")" || fail "build_component_pkg.sh takes the staged root: $(cat "$w/err")"
[ "$out" = "$w/w.pkg" ] && [ -s "$w/w.pkg" ] || fail "build_component_pkg.sh builds the pkg: $out"

T1="$w/root1/usr/local/mavergreen/n"; mkdir -p "$T1/bin" "$T1/libexec/n/clang22/bin"
printf '#!/bin/sh\nexec /usr/local/mavergreen/clang22/bin/clang "$@"\n' > "$T1/bin/n"; chmod 755 "$T1/bin/n"
printf 'c\n' > "$T1/libexec/n/clang22/bin/clang"
AN="$w/dist/n-1.0-macos-x86_64.tar.gz"
sh "$S/stage_standalone.sh" "$w/root1" n 1.0 x86_64 "$AN" > /dev/null 2>&1 || fail "stage_standalone.sh could not make the archive naming a require"
printf 'clang22 libexec/n/clang22\n' > "$w/nlist"
want 1 "a script naming a prefix with no --requires" --repo "$w/repo" "$AN" "$w/nlist" "$w/rootn"
grep -q 'check-standalone-archive.sh refuses n-1.0-macos-x86_64.tar.gz' "$w/err" || fail "the checker's refusal is named: $(cat "$w/err")"
grep -q 'bin/n' "$w/err" || fail "the checker's finding is shown: $(cat "$w/err")"
[ ! -e "$w/rootn" ] || fail "a refused archive stages nothing"
want 0 "a script naming a declared requires' prefix" --repo "$w/repo" --requires clang22 "$AN" "$w/nlist" "$w/rootn"
[ -f "$w/rootn/usr/local/mavergreen/n/bin/n" ] && [ ! -e "$w/rootn/usr/local/mavergreen/n/libexec" ] \
  || fail "the tree is staged without its bundle, and the directories it leaves empty"

want 1 "a bundle that is not a declared requires" --repo "$w/repo" --requires zig "$A" "$L" "$w/root2"
grep -q 'clang22: bundled by' "$w/err" || fail "the undeclared bundle is named: $(cat "$w/err")"
[ ! -e "$w/root2" ] || fail "a refused derivation stages nothing"
mkdir -p "$w/root3/usr/local/mavergreen/w"
want 1 "a root already holding the tree" --repo "$w/repo" --requires clang22 "$A" "$L" "$w/root3"
mkdir -p "$w/root4/Applications/X.app"
want 1 "a root already holding the app" --repo "$w/repo" --requires clang22 "$A" "$L" "$w/root4"
[ ! -e "$w/root4/usr/local" ] || fail "a refused app leaves the root as it was"

cp "$A" "$w/w-1.0.tar.gz"
want 2 "an archive not named <short>-<version>-macos-<arch>.tar.gz" --requires clang22 "$w/w-1.0.tar.gz" "$L" "$w/root5"
want 2 "no archive" --requires clang22 "$w/dist/v-1.0-macos-x86_64.tar.gz" "$L" "$w/root5"
want 2 "no bundled list" --requires clang22 "$A" "$w/nowhere" "$w/root5"
want 2 "a --requires naming no product" --requires 'Clang' "$A" "$L" "$w/root5"
want 2 "two arguments" "$A" "$L"
want 2 "an unknown option" --plist x "$A" "$L" "$w/root5"
want 2 "a --repo with no value" --repo
[ ! -e "$w/root5" ] || fail "a usage error stages nothing"

echo "PASS: stage-pkg-from-archive"
