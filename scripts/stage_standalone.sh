#!/bin/sh
# platform: host-agnostic -- GNU tar on Linux, bsdtar on macOS; 10.9's bsdtar 2.8 cannot record root:wheel
#   usage: stage_standalone.sh STAGED_PKG_ROOT SHORT VERSION ARCH OUT.tar.gz
#          The standalone archive, from the staged root stage_product.sh filled for the pkg (pkg-first),
#          or from a root holding the product's tree and apps alone, from which stage_pkg_from_archive.sh
#          then derives the pkg's (archive-first). OUT is SHORT-VERSION-macos-ARCH.tar.gz (ARCH universal, x86_64 or arm64),
#          holding one top directory SHORT-VERSION/: the tree at STAGED_PKG_ROOT/$(mavergreen_prefix SHORT)
#          exactly as the pkg installs it, without its manifest (mavergreen.plist), and beside it each app
#          the pkg installs at Applications/Mavergreen/<Name>.app, as SHORT-VERSION/<Name>.app. A bin/ link
#          is resolved within STAGED_PKG_ROOT, its target absolute or relative: one landing in
#          Applications/Mavergreen/<Name>.app/... becomes ../<Name>.app/..., and one that does not resolve there,
#          or a relative one that does not resolve in the root, fails. The updater, its LaunchAgent,
#          the install scripts and anything else staged outside the tree stay out, and stderr names what was left out. Entries are sorted, stamped at source-date-epoch.sh's time, root:wheel with no
#          Mac metadata where this tar can say so, and gzipped without a name or time, so one tree gives
#          the same bytes every run. Exit 1 when STAGED_PKG_ROOT holds no tree for SHORT, an app's name
#          is taken in the tree, a bin/ link does not resolve, or the tree or an app holds an
#          AppleDouble file (._*); 2 on a usage or naming error.
# spec: tests/stage-standalone-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavergreen-meta.sh"
. "$SELF/lib/name-rules.sh"
usage='usage: stage_standalone.sh STAGED_PKG_ROOT SHORT VERSION ARCH OUT.tar.gz'
[ $# -eq 5 ] || { echo "$usage" >&2; exit 2; }
ROOT="${1%/}" P="$2" V="$3" ARCH="$4" OUT="$5"
case "$P" in ''|-*|*[!a-z0-9-]*) echo "stage_standalone: '$P' is not a short name" >&2; exit 2 ;; esac
case "$V" in ''|.*|*[!A-Za-z0-9._+-]*) echo "stage_standalone: '$V' is not a version" >&2; exit 2 ;; esac
case "$ARCH" in universal|x86_64|arm64) ;; *) echo "stage_standalone: ARCH is universal, x86_64 or arm64, not '$ARCH'" >&2; exit 2 ;; esac
want="$P-$V-macos-$ARCH.tar.gz"
[ "${OUT##*/}" = "$want" ] || { echo "stage_standalone: $OUT must be named $want" >&2; exit 2; }
REL="$(mavergreen_prefix "$P")" || exit 2
REL="${REL#/}" APPS=Applications/Mavergreen
TREE="$ROOT/$REL"
[ -d "$TREE" ] || { echo "stage_standalone: $ROOT has no $REL to archive" >&2; exit 1; }
EPOCH="$(sh "$SELF/source-date-epoch.sh")"
stamp="$(date -u -d "@$EPOCH" +%Y%m%d%H%M.%S 2>/dev/null || date -u -r "$EPOCH" +%Y%m%d%H%M.%S)"

ad="$(cd "$ROOT" && find "$REL" "$APPS" -name '._*' 2>/dev/null | LC_ALL=C sort | head -1)"
[ -z "$ad" ] || { echo "stage_standalone: an AppleDouble file, $ROOT/$ad: a staged root holds none" >&2; exit 1; }
work="$(mktemp -d "${TMPDIR:-/tmp}/stage-standalone.XXXXXX")"
trap 'rm -rf "$work"' EXIT
top="$P-$V"
cp -pRP "$TREE" "$work/$top"
rm -f "$work/$top/mavergreen.plist"
: > "$work/apps"
for app in "$ROOT/$APPS"/*.app; do
  [ -d "$app" ] && [ ! -L "$app" ] || continue
  n="${app##*/}"
  case "$n" in *-updater.app) continue ;; esac
  [ ! -e "$work/$top/$n" ] && [ ! -L "$work/$top/$n" ] \
    || { echo "stage_standalone: $APPS/$n cannot sit at the top of $want: $REL/$n is already there" >&2; exit 1; }
  cp -pRP "$app" "$work/$top/$n"
  printf '%s\n' "$n" >> "$work/apps"
done
if [ -d "$work/$top/bin" ]; then
  for l in "$work/$top"/bin/*; do
    [ -L "$l" ] || continue
    tg="$(readlink "$l")"
    case "$tg" in /*) p="$tg" ;; *) p="$REL/bin/$tg" ;; esac
    p="$(printf '%s\n' "$p" | awk '{
        n = split($0, c, "/"); k = 0
        for (i = 1; i <= n; i++) {
          if (c[i] == "" || c[i] == ".") continue
          if (c[i] == "..") { if (k == 0) { print "/"; exit } k--; continue }
          o[++k] = c[i]
        }
        s = ""; for (i = 1; i <= k; i++) s = s (i > 1 ? "/" : "") o[i]; print s
      }')"
    case "$p" in
      "$APPS"/*)
        rest="${p#"$APPS"/}"; n="${rest%%/*}"
        if grep -qxF "$n" "$work/apps" && { [ -e "$work/$top/$rest" ] || [ -L "$work/$top/$rest" ]; }; then
          rm -f "$l"; ln -s "../$rest" "$l"
        else
          echo "stage_standalone: bin/${l##*/} links to $tg, which no app staged in $ROOT/$APPS holds" >&2; exit 1
        fi ;;
      *)
        case "$tg" in /*) continue ;; esac
        [ -n "$p" ] && [ "$p" != / ] && { [ -e "$ROOT/$p" ] || [ -L "$ROOT/$p" ]; } \
          || { echo "stage_standalone: bin/${l##*/} links to $tg, which does not resolve within $ROOT" >&2; exit 1; } ;;
    esac
  done
fi
find "$work/$top" -name .DS_Store -exec rm -rf {} + 2>/dev/null || :
(cd "$ROOT" && find . \( -type f -o -type l \) ! -path "./$REL/*" | sed 's|^\./||' | LC_ALL=C sort) \
  | awk -v apps="$work/apps" -v pfx="$APPS/" 'BEGIN { while ((getline n < apps) > 0) a[pfx n "/"] = 1 }
      { for (k in a) if (index($0, k) == 1) next; print }' > "$work/left"
if [ -s "$work/left" ]; then
  echo "stage_standalone: left out of $want, as the pkg's alone:" >&2
  sed 's/^/  /' "$work/left" >&2
fi
[ ! -f "$TREE/mavergreen.plist" ] || echo "stage_standalone: left out of $want, as the pkg's alone: $REL/mavergreen.plist" >&2
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
