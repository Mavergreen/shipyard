#!/bin/sh
# platform: host-agnostic -- GNU tar on Linux, bsdtar on macOS; 10.9's bsdtar 2.8 cannot record root:wheel
#   usage: stage_standalone.sh STAGED_PKG_ROOT SHORT VERSION ARCH OUT.tar.gz
#          The standalone archive, from the same staged root stage_product.sh filled for the pkg: one
#          build, two forms. OUT is SHORT-VERSION-macos-ARCH.tar.gz (ARCH universal, x86_64 or arm64),
#          holding one top directory SHORT-VERSION/: STAGED_PKG_ROOT/usr/local/mavergreen/SHORT exactly
#          as the pkg installs it, without its manifest (mavergreen.plist). The updater, its LaunchAgent,
#          the install scripts and anything else staged outside the tree stay out, and stderr names what
#          was left out. Entries are sorted, stamped at source-date-epoch.sh's time, root:wheel with no
#          Mac metadata where this tar can say so, and gzipped without a name or time, so one tree gives
#          the same bytes every run. Exit 1 when STAGED_PKG_ROOT holds no tree for SHORT, 2 on a usage
#          or naming error.
# spec: tests/stage-standalone-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
usage='usage: stage_standalone.sh STAGED_PKG_ROOT SHORT VERSION ARCH OUT.tar.gz'
[ $# -eq 5 ] || { echo "$usage" >&2; exit 2; }
ROOT="${1%/}" P="$2" V="$3" ARCH="$4" OUT="$5"
case "$P" in ''|-*|*[!a-z0-9-]*) echo "stage_standalone: '$P' is not a short name" >&2; exit 2 ;; esac
case "$V" in ''|.*|*[!A-Za-z0-9._+-]*) echo "stage_standalone: '$V' is not a version" >&2; exit 2 ;; esac
case "$ARCH" in universal|x86_64|arm64) ;; *) echo "stage_standalone: ARCH is universal, x86_64 or arm64, not '$ARCH'" >&2; exit 2 ;; esac
want="$P-$V-macos-$ARCH.tar.gz"
[ "${OUT##*/}" = "$want" ] || { echo "stage_standalone: $OUT must be named $want" >&2; exit 2; }
TREE="$ROOT/usr/local/mavergreen/$P"
[ -d "$TREE" ] || { echo "stage_standalone: $ROOT has no usr/local/mavergreen/$P to archive" >&2; exit 1; }
EPOCH="$(sh "$SELF/source-date-epoch.sh")"
stamp="$(date -u -d "@$EPOCH" +%Y%m%d%H%M.%S 2>/dev/null || date -u -r "$EPOCH" +%Y%m%d%H%M.%S)"

work="$(mktemp -d "${TMPDIR:-/tmp}/stage-standalone.XXXXXX")"
trap 'rm -rf "$work"' EXIT
top="$P-$V"
cp -pRP "$TREE" "$work/$top"
rm -f "$work/$top/mavergreen.plist"
find "$work/$top" \( -name '._*' -o -name .DS_Store \) -exec rm -rf {} + 2>/dev/null || :
(cd "$ROOT" && find . \( -type f -o -type l \) ! -path "./usr/local/mavergreen/$P/*" | sed 's|^\./||' | LC_ALL=C sort) > "$work/left"
if [ -s "$work/left" ]; then
  echo "stage_standalone: left out of $want, as the pkg's alone:" >&2
  sed 's/^/  /' "$work/left" >&2
fi
[ ! -f "$TREE/mavergreen.plist" ] || echo "stage_standalone: left out of $want, as the pkg's alone: usr/local/mavergreen/$P/mavergreen.plist" >&2
(cd "$work" && find "$top" -exec env TZ=UTC0 touch -h -t "$stamp" {} +)
(cd "$work" && find "$top" | LC_ALL=C sort) > "$work/list"

mkdir -p "$(dirname "$OUT")"
if tar --version 2>/dev/null | head -1 | grep -q 'GNU tar'; then
  set -- --format=gnu --owner=root:0 --group=wheel:0 --mtime="@$EPOCH"
else
  set -- --uid 0 --gid 0 --uname root --gname wheel --no-mac-metadata
  if ! (cd "$work" && COPYFILE_DISABLE=1 tar -c -f /dev/null --no-recursion "$@" "$top") 2>/dev/null; then
    echo "stage_standalone: this tar ($(tar --version 2>&1 | head -1)) cannot record root:wheel or omit Mac metadata; the archive keeps this machine's owner" >&2
    set --
  fi
fi
(cd "$work" && COPYFILE_DISABLE=1 tar -c -f out.tar --no-recursion "$@" -T list)
gzip -n -9 "$work/out.tar"
mv "$work/out.tar.gz" "$OUT"
echo "stage_standalone: built $OUT"
