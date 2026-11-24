#!/bin/sh
# platform: host-agnostic
#   usage: split-debug.sh --root ROOT --short S --version V --out DIR
#          Run from the build root, where each debug map's objects resolve. For each linked Mach-O
#          (EXECUTE, DYLIB, BUNDLE) under ROOT, writes its dSYM with dsymutil as S-V-dSYM/<path>.dSYM,
#          without the Relocations/ it writes for merging dSYMs, which names ROOT; then strips its debug
#          map in place with strip -S, keeping local symbols, and writes
#          DIR/S-V-dSYM.tar.gz with stage_standalone.sh's deterministic tar settings. Nothing is
#          stripped unless every dSYM was written. An image a dsym-asset deviation's scope matches
#          (its path under ROOT; deviations from mavergreen-meta.sh's repo root) is left whole. An
#          image whose slices DSYMUTIL has no target for is left whole, unsplit, with a line on stderr
#          naming the documented exception: universal images are split on Linux or modern macOS (10.9's
#          dsymutil has no AArch64), and conformance's debug-map and dsym-asset fail such an image in
#          a release. Exit 0; 1 when a linked image has no debug map or dsymutil cannot read its
#          objects; 2 on a usage error; 4 when a tool (lib/macho-tools.sh's DSYMUTIL, STRIP, NM, LIPO
#          or OTOOL) is missing.
# spec: tests/split-debug-test.sh -- every shipped Mach-O is stripped of its debug map, and its DWARF
#       is published beside it as a dSYM tarball.
set -eu
LC_ALL=C; export LC_ALL
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavergreen-meta.sh"
. "$SELF/lib/name-rules.sh"
. "$SELF/lib/macho-tools.sh"
. "$SELF/lib/pkg-tree.sh"
. "$SELF/lib/det-tar.sh"
. "$SELF/deviation-reason.sh"
usage='usage: split-debug.sh --root ROOT --short S --version V --out DIR'
ROOT="" P="" V="" OUT=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || { echo "$usage" >&2; exit 2; }
  case "$1" in
    --root) ROOT="$2" ;;
    --short) P="$2" ;;
    --version) V="$2" ;;
    --out) OUT="$2" ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
  shift 2
done
[ -n "$ROOT" ] && [ -n "$P" ] && [ -n "$V" ] && [ -n "$OUT" ] || { echo "$usage" >&2; exit 2; }
case "$P" in -*|*[!a-z0-9-]*) echo "split-debug: '$P' is not a short name" >&2; exit 2 ;; esac
case "$V" in .*|*[!A-Za-z0-9._+-]*) echo "split-debug: '$V' is not a version" >&2; exit 2 ;; esac
[ -d "$ROOT" ] || { echo "split-debug: $ROOT is not a directory" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"
for v in DSYMUTIL STRIP NM LIPO OTOOL; do
  mach_tool "$v" || exit 4
  eval "_sd_t=\$$v"
  command -v "$_sd_t" >/dev/null 2>&1 || { echo "split-debug: $v ($_sd_t) is not there" >&2; exit 4; }
done
EPOCH="$(sh "$SELF/source-date-epoch.sh")"
top="$P-$V-dSYM"
work="$(mktemp -d "${TMPDIR:-/tmp}/split-debug.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir "$work/$top" "$work/bin"
: > "$work/whole"
ln -s "$(command -v "$LIPO")" "$work/bin/lipo"

(cd "$ROOT" && find . -type f | sed 's|^\./||' | sort) > "$work/files"
shipyard_deviations "$(dirname "$(mg_dir)")" > /dev/null 2>&1 || :
: > "$work/linked"
while IFS= read -r rel; do
  [ "$(af_macho_kind "$ROOT/$rel")" = strict ] || continue
  if why="$(shipyard_deviated dsym-asset "$rel")"; then
    echo "split-debug: $rel: DECLARED DEVIATION (dsym-asset) -- $why" >&2
    continue
  fi
  rc=0; kinds="$(sh "$SELF/macho-slices.sh" "$ROOT/$rel" 2>"$work/err")" || rc=$?
  [ "$rc" -ne 4 ] || { cat "$work/err" >&2; exit 4; }
  [ "$rc" -eq 0 ] || continue
  printf '%s\n' "$kinds" | awk '$2 == "EXECUTE" || $2 == "DYLIB" || $2 == "BUNDLE" { f = 1 } END { exit !f }' || continue
  printf '%s\n' "$rel" >> "$work/linked"
done < "$work/files"

while IFS= read -r rel; do
  "$NM" -a -arch all "$ROOT/$rel" 2>/dev/null | awk '$5 == "OSO" { f = 1 } END { exit !f }' \
    || { echo "split-debug: $rel has no debug map: build it with -g through MavergreenToolchain.cmake, or declare deviations/dsym-asset/<label>/" >&2; exit 1; }
  mkdir -p "$work/$top/$(dirname "$rel")"
  # platform: dsymutil joins a fat image's per-arch DWARF by running lipo from PATH, which Linux lacks
  rc=0; PATH="$work/bin:$PATH" "$DSYMUTIL" -o "$work/$top/$rel.dSYM" "$ROOT/$rel" > "$work/dsym.log" 2>&1 || rc=$?
  if grep -q 'unable to get target for' "$work/dsym.log"; then
    echo "split-debug: $rel: left whole, documented exception: $DSYMUTIL lacks a target its slices need; universal images are split on Linux or modern macOS" >&2
    sed 's/^/  /' "$work/dsym.log" >&2
    rm -rf "$work/$top/$rel.dSYM"
    printf '%s\n' "$rel" >> "$work/whole"
    continue
  fi
  if [ "$rc" -ne 0 ] || grep -Eqi 'unable to open object file|no such file' "$work/dsym.log"; then
    echo "split-debug: dsymutil cannot read $rel's objects from $(pwd): run from its build root" >&2
    sed 's/^/  /' "$work/dsym.log" >&2
    exit 1
  fi
  rm -rf "$work/$top/$rel.dSYM/Contents/Resources/Relocations"
done < "$work/linked"

while IFS= read -r rel; do
  ! grep -qxF "$rel" "$work/whole" || continue
  "$STRIP" -S "$ROOT/$rel" || { echo "split-debug: $STRIP -S failed on $rel" >&2; exit 1; }
done < "$work/linked"

det_tar_gz "$work" "$top" "$OUT/$top.tar.gz" "$EPOCH" split-debug
echo "split-debug: $(($(wc -l < "$work/linked") - $(wc -l < "$work/whole"))) image(s) split into $OUT/$top.tar.gz"
