#!/bin/sh
# platform: host-agnostic
#   usage: stage-standalone-test.sh
#          scripts/stage_standalone.sh: from a staged pkg root carrying a product tree, its manifest, an
#          updater and its LaunchAgent, the archive holds the product tree alone under <short>-<version>/,
#          with its modes and links, every entry at SOURCE_DATE_EPOCH, the same bytes from two runs, and
#          passes check-standalone-archive.sh; an app the root stages in Applications/ sits at the
#          archive's top, an updater there stays out, and a bin/ link, absolute or relative, landing in
#          Applications/<Name>.app becomes relative, refused when it does not resolve in the root; an
#          AppleDouble file is refused.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/stage_standalone.sh"
C="$here/../scripts/check-standalone-archive.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/stage-standalone.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: stage-standalone: $*"; exit 1; }

R="$w/root"; T="$R/opt/mavergreen/w"
mkdir -p "$T/bin" "$T/libexec/w" "$T/share/doc/w" "$T/share/empty"
printf '#!/bin/sh\nexec "$(dirname "$0")/../libexec/w/w-real" "$@"\n' > "$T/bin/w"
printf '#!/bin/sh\necho w 1.0\n' > "$T/libexec/w/w-real"
chmod 755 "$T/bin/w" "$T/libexec/w/w-real"
printf 'readme\n' > "$T/share/doc/w/README"; chmod 600 "$T/share/doc/w/README"
ln -s ../libexec/w/w-real "$T/bin/w-real"
printf '<plist/>\n' > "$T/mavergreen.plist"
A="$R/Library/Application Support/Mavergreen/w-updater.app/Contents"; mkdir -p "$A/MacOS"
printf 'x\n' > "$A/MacOS/w-updater"; printf '<plist/>\n' > "$A/Info.plist"
mkdir -p "$R/Library/LaunchAgents"; printf '<plist/>\n' > "$R/Library/LaunchAgents/dev.mavergreen.w-updatecheck.plist"

usage() {  # $1 = label, then the arguments; must exit 2
  rc=0; sh "$S" "$@" >/dev/null 2>"$w/err" || rc=$?
  [ "$rc" -eq 2 ] || fail "$1: exit $rc, want 2: $(cat "$w/err")"
}
usage "no arguments"
usage "four arguments" "$R" w 1.0 universal
usage "an archive not named <short>-<version>-macos-<arch>.tar.gz" "$R" w 1.0 universal "$w/w-1.0.tar.gz"
usage "an archive named for another version" "$R" w 1.0 universal "$w/w-1.1-macos-universal.tar.gz"
usage "an arch the family does not ship" "$R" w 1.0 i386 "$w/w-1.0-macos-i386.tar.gz"
usage "a short name that is not one" "$R" W 1.0 universal "$w/W-1.0-macos-universal.tar.gz"
usage "a version with a slash" "$R" w 1/0 universal "$w/w-1/0-macos-universal.tar.gz"
rc=0; sh "$S" "$R" v 1.0 x86_64 "$w/v-1.0-macos-x86_64.tar.gz" >/dev/null 2>"$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "a root with no opt/mavergreen/v: exit $rc, want 1"
grep -q 'opt/mavergreen/v' "$w/err" || fail "a missing tree is named: $(cat "$w/err")"

export SOURCE_DATE_EPOCH=1700000000
mkdir "$w/one" "$w/two"
sh "$S" "$R" w 1.0 universal "$w/one/w-1.0-macos-universal.tar.gz" > "$w/out1" 2> "$w/err1" \
  || fail "staging failed: $(cat "$w/err1")"
grep -q 'Library/LaunchAgents' "$w/err1" || fail "what the pkg installs outside the tree is named as left out: $(cat "$w/err1")"
grep -q 'w-updater.app' "$w/err1" || fail "the updater is named as left out: $(cat "$w/err1")"
touch "$T/share/doc/w/README" "$T/bin/w"
sh "$S" "$R" w 1.0 universal "$w/two/w-1.0-macos-universal.tar.gz" > /dev/null 2> "$w/err2" \
  || fail "the second staging failed: $(cat "$w/err2")"
cmp -s "$w/one/w-1.0-macos-universal.tar.gz" "$w/two/w-1.0-macos-universal.tar.gz" \
  || fail "two runs over one tree, its mtimes moved between them, give different bytes"

tar -tzf "$w/one/w-1.0-macos-universal.tar.gz" | sed 's|/$||' > "$w/list"
want='w-1.0
w-1.0/bin
w-1.0/bin/w
w-1.0/bin/w-real
w-1.0/libexec
w-1.0/libexec/w
w-1.0/libexec/w/w-real
w-1.0/share
w-1.0/share/doc
w-1.0/share/doc/w
w-1.0/share/doc/w/README
w-1.0/share/empty'
[ "$(cat "$w/list")" = "$want" ] || fail "the archive is the product tree alone, in sorted order: $(cat "$w/list")"

if grep -q 'cannot record root:wheel' "$w/err1"; then
  echo "INFO: this tar cannot record root:wheel; owner not asserted"
else
  tar -tvzf "$w/one/w-1.0-macos-universal.tar.gz" | awk '!($3 == "root" && $4 == "wheel") && $2 != "root/wheel" { print; exit 1 }' > "$w/own" \
    || fail "every entry is root:wheel: $(cat "$w/own")"
fi

mkdir "$w/x"; tar -xzf "$w/one/w-1.0-macos-universal.tar.gz" -C "$w/x"
X="$w/x/w-1.0"
[ -x "$X/bin/w" ] && [ -x "$X/libexec/w/w-real" ] || fail "executables keep their mode"
[ "$(ls -l "$X/share/doc/w/README" | cut -c1-10)" = "-rw-------" ] || fail "a file keeps its mode: $(ls -l "$X/share/doc/w/README")"
[ -L "$X/bin/w-real" ] && [ "$(ls -l "$X/bin/w-real" | sed 's/.* -> //')" = ../libexec/w/w-real ] || fail "a symlink stays a relative symlink"
[ "$("$X/bin/w")" = "w 1.0" ] || fail "the unpacked tree runs from where it was unpacked"
TZ=UTC0 touch -t 202311142213.20 "$w/ref"
for f in "$X" "$X/bin/w" "$X/share/doc/w/README" "$X/share/empty"; do
  [ ! "$f" -nt "$w/ref" ] && [ ! "$w/ref" -nt "$f" ] || fail "$f is not stamped at SOURCE_DATE_EPOCH: $(ls -ld "$f")"
done
gzip -dc "$w/one/w-1.0-macos-universal.tar.gz" | grep -a -q -E 'LIBARCHIVE\.xattr\.|SCHILY\.xattr\.' \
  && fail "the archive stores extended attributes"

sh "$C" "$w/one/w-1.0-macos-universal.tar.gz" > "$w/chk" 2>&1 || fail "check-standalone-archive refuses what stage_standalone made: $(cat "$w/chk")"

R="$w/approot"; T="$R/opt/mavergreen/x"
mkdir -p "$T/bin" "$R/Applications/Mavergreen/X.app/Contents/MacOS" "$R/Applications/Mavergreen/X.app/Contents/Resources"
printf '#!/bin/sh\necho x 1.0\n' > "$R/Applications/Mavergreen/X.app/Contents/MacOS/x"; chmod 755 "$R/Applications/Mavergreen/X.app/Contents/MacOS/x"
printf '<plist/>\n' > "$R/Applications/Mavergreen/X.app/Contents/Info.plist"
ln -s /Applications/Mavergreen/X.app/Contents/MacOS/x "$T/bin/x"
mkdir -p "$R/Applications/Mavergreen/x-updater.app/Contents"; printf '<plist/>\n' > "$R/Applications/Mavergreen/x-updater.app/Contents/Info.plist"
printf '<plist/>\n' > "$T/mavergreen.plist"
sh "$S" "$R" x 1.0 x86_64 "$w/one/x-1.0-macos-x86_64.tar.gz" > /dev/null 2> "$w/err" \
  || fail "staging a product with an app failed: $(cat "$w/err")"
grep -q 'x-updater.app' "$w/err" || fail "an updater in Applications is left out: $(cat "$w/err")"
grep -q 'Applications/Mavergreen/X.app' "$w/err" && fail "the archived app is not named as left out: $(cat "$w/err")"
tar -tzf "$w/one/x-1.0-macos-x86_64.tar.gz" | sed 's|/$||' > "$w/list"
want='x-1.0
x-1.0/X.app
x-1.0/X.app/Contents
x-1.0/X.app/Contents/Info.plist
x-1.0/X.app/Contents/MacOS
x-1.0/X.app/Contents/MacOS/x
x-1.0/X.app/Contents/Resources
x-1.0/bin
x-1.0/bin/x'
[ "$(cat "$w/list")" = "$want" ] || fail "the archive holds the tree and the app at its top: $(cat "$w/list")"
rm -rf "$w/x"; mkdir "$w/x"; tar -xzf "$w/one/x-1.0-macos-x86_64.tar.gz" -C "$w/x"
[ "$(ls -l "$w/x/x-1.0/bin/x" | sed 's/.* -> //')" = ../X.app/Contents/MacOS/x ] \
  || fail "a bin/ link into /Applications/Mavergreen/X.app becomes relative: $(ls -l "$w/x/x-1.0/bin/x")"
[ "$("$w/x/x-1.0/bin/x")" = "x 1.0" ] || fail "the relinked tool runs from where it was unpacked"
sh "$C" "$w/one/x-1.0-macos-x86_64.tar.gz" > "$w/chk" 2>&1 || fail "check-standalone-archive refuses the archive with an app: $(cat "$w/chk")"
rm "$T/bin/x"; ln -s /Applications/Mavergreen/Y.app/Contents/MacOS/y "$T/bin/x"
rc=0; sh "$S" "$R" x 1.0 x86_64 "$w/two/x-1.0-macos-x86_64.tar.gz" > /dev/null 2> "$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "a bin/ link into an app the root does not stage: exit $rc, want 1: $(cat "$w/err")"
grep -q 'bin/x' "$w/err" || fail "the unresolvable link is named: $(cat "$w/err")"
rm "$T/bin/x"; ln -s /Applications/Mavergreen/X.app/Contents/MacOS/gone "$T/bin/x"
rc=0; sh "$S" "$R" x 1.0 x86_64 "$w/two/x-1.0-macos-x86_64.tar.gz" > /dev/null 2> "$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "a bin/ link to nothing in the app: exit $rc, want 1: $(cat "$w/err")"

rm "$T/bin/x"; ln -s ../../../../Applications/Mavergreen/X.app/Contents/MacOS/x "$T/bin/x"
ln -s ../../../../Applications/Mavergreen/X.app "$T/bin/X.app"
rm -f "$w/two/x-1.0-macos-x86_64.tar.gz"
sh "$S" "$R" x 1.0 x86_64 "$w/two/x-1.0-macos-x86_64.tar.gz" > /dev/null 2> "$w/err" \
  || fail "staging a product whose bin/ link reaches the app relatively failed: $(cat "$w/err")"
rm -rf "$w/x"; mkdir "$w/x"; tar -xzf "$w/two/x-1.0-macos-x86_64.tar.gz" -C "$w/x"
[ "$(ls -l "$w/x/x-1.0/bin/x" | sed 's/.* -> //')" = ../X.app/Contents/MacOS/x ] \
  || fail "a relative bin/ link into Applications/X.app is rewritten into the archive: $(ls -l "$w/x/x-1.0/bin/x")"
[ "$(ls -l "$w/x/x-1.0/bin/X.app" | sed 's/.* -> //')" = ../X.app ] \
  || fail "a relative bin/ link to the app itself is rewritten: $(ls -l "$w/x/x-1.0/bin/X.app")"
[ "$("$w/x/x-1.0/bin/x")" = "x 1.0" ] || fail "the relatively linked tool runs from where it was unpacked"
rm "$T/bin/X.app"
for bad in ../../../../Applications/Mavergreen/X.app/Contents/MacOS/gone ../../../Applications/Mavergreen/X.app/Contents/MacOS/x ../../../../../x ../libexec/gone; do
  rm "$T/bin/x"; ln -s "$bad" "$T/bin/x"
  rc=0; sh "$S" "$R" x 1.0 x86_64 "$w/two/x-1.0-macos-x86_64.tar.gz" > /dev/null 2> "$w/err" || rc=$?
  [ "$rc" -eq 1 ] || fail "a relative bin/ link, $bad, that does not resolve in the root: exit $rc, want 1: $(cat "$w/err")"
  grep -q "bin/x links to $bad" "$w/err" || fail "the unresolvable relative link is named: $(cat "$w/err")"
done
rm "$T/bin/x"; ln -s /Applications/Mavergreen/X.app/Contents/MacOS/x "$T/bin/x"
printf 'junk' > "$R/Applications/Mavergreen/X.app/Contents/._Info.plist"; rm -f "$w/two/x-1.0-macos-x86_64.tar.gz"
rc=0; sh "$S" "$R" x 1.0 x86_64 "$w/two/x-1.0-macos-x86_64.tar.gz" > /dev/null 2> "$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "an AppleDouble file in a staged app: exit $rc, want 1: $(cat "$w/err")"
grep -q 'AppleDouble.*X.app/Contents/._Info.plist' "$w/err" || fail "the AppleDouble entry is named: $(cat "$w/err")"
rm "$R/Applications/Mavergreen/X.app/Contents/._Info.plist"; printf 'junk' > "$T/bin/._x"
rc=0; sh "$S" "$R" x 1.0 x86_64 "$w/two/x-1.0-macos-x86_64.tar.gz" > /dev/null 2> "$w/err" || rc=$?
[ "$rc" -eq 1 ] || fail "an AppleDouble file in the tree: exit $rc, want 1: $(cat "$w/err")"
grep -q 'AppleDouble.*bin/._x' "$w/err" || fail "the AppleDouble entry in the tree is named: $(cat "$w/err")"
[ ! -e "$w/two/x-1.0-macos-x86_64.tar.gz" ] || fail "a refused stage leaves no archive"
rm "$T/bin/._x"

echo "PASS: stage-standalone"
