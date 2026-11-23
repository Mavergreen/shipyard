#!/bin/sh
# platform: host-agnostic -- GNU tar on Linux, bsdtar on macOS; stevedore reads the requires
#   usage: stage_pkg_from_archive.sh [--repo DIR] [--requires SHORT[>=FLOOR]]... [--pkg-only SRC=DEST]...
#                                    ARCHIVE BUNDLED_LIST STAGED_ROOT
#          The archive-first entry to the pkg: ARCHIVE, SHORT-VERSION-macos-ARCH.tar.gz, is judged by
#          check-standalone-archive.sh (--repo DIR, default ., whose standalone-text deviations it
#          honours, unused ones left to conformance; given --requires, against a manifest declaring
#          them), then unpacked, and derive_pkg_tree.sh makes STAGED_ROOT/usr/local/mavergreen/SHORT
#          from its SHORT-VERSION/ with BUNDLED_LIST, the --requires and the --pkg-only paths. Each app
#          at the archive's top, <Name>.app, goes to STAGED_ROOT/Applications/<Name>.app, and a bin/
#          link to ../<Name>.app/... becomes /Applications/<Name>.app/...: the inverse of
#          stage_standalone.sh. STAGED_ROOT is then what stage_product.sh takes as --stage, given the
#          same --requires, and build_component_pkg.sh as --root. Exit 1 when the checker refuses
#          ARCHIVE, the derivation fails, or STAGED_ROOT already holds the product's tree or one of its
#          apps; 2 on a usage or naming error, a bad --requires or a bad BUNDLED_LIST.
# spec: tests/stage-pkg-from-archive-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib/requires.sh"
usage='usage: stage_pkg_from_archive.sh [--repo DIR] [--requires SHORT[>=FLOOR]]... [--pkg-only SRC=DEST]... ARCHIVE BUNDLED_LIST STAGED_ROOT'
die() { echo "stage_pkg_from_archive: $1" >&2; exit "$2"; }
nl='
'
repo=.; REQ=""; ADD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo|--requires|--pkg-only) [ $# -ge 2 ] || { echo "$usage" >&2; exit 2; } ;;
  esac
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --requires)
      mavergreen_require_short "$2" > /dev/null || die "--requires '$2' names no product" 2
      REQ="$REQ$2$nl"; shift 2 ;;
    --pkg-only) ADD="$ADD$2$nl"; shift 2 ;;
    --) shift; break ;;
    -*) echo "$usage" >&2; exit 2 ;;
    *) break ;;
  esac
done
[ $# -eq 3 ] || { echo "$usage" >&2; exit 2; }
ARCHIVE="$1" LIST="$2" ROOT="${3%/}"
[ -f "$ARCHIVE" ] || die "no archive at $ARCHIVE" 2
[ -f "$LIST" ] || die "no bundled list at $LIST" 2
b="${ARCHIVE##*/}"
case "$b" in
  *-macos-universal.tar.gz|*-macos-x86_64.tar.gz|*-macos-arm64.tar.gz) top="${b%-macos-*.tar.gz}" ;;
  *) die "$b is not named <short>-<version>-macos-<universal|x86_64|arm64>.tar.gz" 2 ;;
esac
P="$(printf '%s\n' "$top" | sed 's/-[0-9].*//')"
case "$P" in ''|-*|*[!a-z0-9-]*) die "$b does not read as <short>-<version>" 2 ;; esac
[ "$P" != "$top" ] || die "$b does not read as <short>-<version>" 2
T="$ROOT/usr/local/mavergreen/$P"
{ [ -e "$T" ] || [ -L "$T" ]; } && die "$ROOT already holds usr/local/mavergreen/$P" 1

work="$(mktemp -d "${TMPDIR:-/tmp}/stage-pkg-from-archive.XXXXXX")"
trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT
set -- --repo "$repo" --defer-unused
if [ -n "$REQ" ]; then
  {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n'
    printf '  <key>product</key>\n  <string>%s</string>\n  <key>requires</key>\n  <array>\n' "$P"
    printf '%s' "$REQ" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's|.*|    <string>&</string>|'
    printf '  </array>\n</dict>\n</plist>\n'
  } > "$work/mavergreen.plist"
  set -- "$@" --plist "$work/mavergreen.plist"
fi
sh "$SELF/check-standalone-archive.sh" "$@" "$ARCHIVE" > "$work/check" 2>&1 && rc=0 || rc=$?
sed 's/^/  /' "$work/check" >&2
case "$rc" in
  0) ;;
  1) die "check-standalone-archive.sh refuses $b; the pkg is derived only from an archive it passes" 1 ;;
  *) die "check-standalone-archive.sh cannot judge $b" 2 ;;
esac

mkdir "$work/x"
tar -xpzf "$ARCHIVE" -C "$work/x"
X="$work/x/$top"
[ -d "$X" ] || die "$b holds no $top/" 1
mkdir "$work/apps"
for app in "$X"/*.app; do
  [ -d "$app" ] && [ ! -L "$app" ] || continue
  n="${app##*/}"
  { [ -e "$ROOT/Applications/$n" ] || [ -L "$ROOT/Applications/$n" ]; } && die "$ROOT already holds Applications/$n" 1
  mv "$app" "$work/apps/$n"
done

set --
_ifs="$IFS"; IFS="$nl"
for r in $REQ; do set -- "$@" --requires "$r"; done
for a in $ADD; do set -- "$@" --pkg-only "$a"; done
IFS="$_ifs"
rc=0; sh "$SELF/derive_pkg_tree.sh" "$@" "$X" "$LIST" "$work/tree" || rc=$?
[ "$rc" -eq 0 ] || exit "$rc"

if [ -d "$work/tree/bin" ]; then
  for l in "$work/tree"/bin/*; do
    [ -L "$l" ] || continue
    tg="$(readlink "$l")"
    case "$tg" in
      ../*.app|../*.app/*)
        rest="${tg#../}"; n="${rest%%/*}"
        [ -d "$work/apps/$n" ] || continue
        rm -f "$l"; ln -s "/Applications/$rest" "$l" ;;
    esac
  done
fi

mkdir -p "$(dirname "$T")"
mv "$work/tree" "$T"
for app in "$work/apps"/*.app; do
  [ -d "$app" ] || continue
  mkdir -p "$ROOT/Applications"
  mv "$app" "$ROOT/Applications/"
done
echo "stage_pkg_from_archive: staged $P from $b into $ROOT" >&2
