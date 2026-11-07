#!/bin/sh
# platform: host-agnostic
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/check-lib.sh"
chk_ran retired-name
tab="$(printf '\t')"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/retired-name.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
chk_tracked_files > "$tmp/paths" || exit 2
cut -f1 "$SELF/retired-names" > "$tmp/tokens"
[ -s "$tmp/tokens" ] || exit 0
while IFS= read -r p; do
  case "$p" in
    scripts/retired-names|.mavergreen/release-notes/*|tests/fixtures/checks/*) continue ;;
  esac
  [ -f "$p" ] || continue
  grep -I -o -F -f "$tmp/tokens" "$p" 2>/dev/null | sort -u > "$tmp/hits" || :
  [ -s "$tmp/hits" ] || continue
  while IFS= read -r tok; do
    chk_deviated retired-name "$p" >/dev/null && continue
    repl="$(awk -F'\t' -v t="$tok" '$1 == t { print $2; exit }' "$SELF/retired-names")"
    chk_fail retired-name "$p uses $tok, a retired family name" \
      '"Mavericks" names only the OS an artifact targets' \
      "write $repl"
  done < "$tmp/hits"
done < "$tmp/paths"
exit "$chk_status"
