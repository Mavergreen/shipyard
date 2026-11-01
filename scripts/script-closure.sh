#!/bin/sh
# platform: host-agnostic
#   usage: script-closure.sh NAME...
#          Prints, sorted and one per line, every path under scripts/ (relative to it) that the named
#          files need at run time: themselves and, transitively, every other file under scripts/ whose
#          path (or a trailing part of it, as in "$SELF/lib/vercmp.sh") a non-comment line of theirs
#          names. A script copied elsewhere with its closure runs there. Exit 2 on no NAME or a NAME
#          that is not a file under scripts/.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
[ "$#" -gt 0 ] || { echo "usage: script-closure.sh NAME..." >&2; exit 2; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/script-closure.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
( cd "$SELF" && find . -type f | sed 's|^\./||' | LC_ALL=C sort ) > "$WORK/all"
: > "$WORK/todo"
for n in "$@"; do
  grep -Fxq -- "$n" "$WORK/all" || { echo "script-closure: $n is not a file under $SELF" >&2; exit 2; }
  echo "$n" >> "$WORK/todo"
done
: > "$WORK/seen"
while [ -s "$WORK/todo" ]; do
  LC_ALL=C sort -u "$WORK/todo" > "$WORK/batch"
  : > "$WORK/todo"
  LC_ALL=C comm -23 "$WORK/batch" "$WORK/seen" > "$WORK/new"
  [ -s "$WORK/new" ] || break
  cat "$WORK/new" >> "$WORK/seen"
  LC_ALL=C sort -o "$WORK/seen" "$WORK/seen"
  while IFS= read -r f; do
    sed '/^[[:space:]]*#/d' "$SELF/$f" 2>/dev/null | LC_ALL=C tr -c 'A-Za-z0-9_./-' '\n' \
      | awk 'NF { t = $0; sub(/[.-]+$/, "", t); print t; while ((i = index(t, "/")) > 0) { t = substr(t, i + 1); print t } }' \
      | grep -Fx -f "$WORK/all" >> "$WORK/todo" || :
  done < "$WORK/new"
done
cat "$WORK/seen"
