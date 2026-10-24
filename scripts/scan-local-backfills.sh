#!/bin/sh
# platform: host-agnostic
#   usage: scan-local-backfills.sh REPO
#          scan-local-backfills.sh --inventory REPO
#          Prints one "path<TAB>line<TAB>category<TAB>symbol<TAB>reason" per CANDIDATE family-authored
#          OS/API backfill in REPO's tracked source, sorted by path then line; line 0 is the whole
#          file. Categories: definition, inline-definition, patch-definition, embedded-definition,
#          macro-definition, declaration, annotation, suspicious-path. A candidate is a name from
#          local-backfill-symbols or from compatibility-inventory.tsv, a compatibility annotation, or
#          a shim/polyfill/backfill/compat path; renamed helpers, new APIs and macro-generated
#          functions are not found, so no finding is not proof of absence.
#          --inventory validates REPO/compatibility-inventory.tsv and prints its rows, header
#          dropped; no file prints nothing. The header is "path<TAB>kind<TAB>symbols<TAB>reason";
#          kind is local-backfill, product-adaptation, upstream or test-only; path is one tracked
#          file; symbols is "-" or comma-separated names.
#          The file list is `git ls-files` when REPO is the top of a git checkout, else the
#          newline-delimited relative paths in the file MAVERGREEN_SOURCE_FILES names.
#          Exit 0: scan completed, findings or not. Exit 2: could not scan, or the inventory is
#          malformed. Whether a candidate may ship is not decided here.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
die() { printf 'scan-local-backfills: %s\n' "$*" >&2; exit 2; }
usage="usage: scan-local-backfills.sh [--inventory] REPO"
mode=scan
case "${1:-}" in
  --inventory) mode=inventory; shift ;;
  -*) die "$usage" ;;
esac
[ "$#" -eq 1 ] || die "$usage"
[ -d "$1" ] || die "$1 is not a directory"
repo="$(cd "$1" && pwd)"
INV=compatibility-inventory.tsv

w="$(mktemp -d "${TMPDIR:-/tmp}/scan-local-backfills.XXXXXX")"
trap 'rm -rf "$w"' EXIT
raw="$w/raw"
if prefix="$(git -C "$repo" rev-parse --show-prefix 2>/dev/null)" && [ -z "$prefix" ]; then
  git -C "$repo" -c core.quotepath=off ls-files > "$raw" 2>"$w/git-err" \
    || die "git ls-files failed in $repo: $(cat "$w/git-err")"
  source="git ls-files"
elif [ -n "${MAVERGREEN_SOURCE_FILES:-}" ]; then
  [ -f "$MAVERGREEN_SOURCE_FILES" ] || die "MAVERGREEN_SOURCE_FILES names $MAVERGREEN_SOURCE_FILES, which is not a file"
  cp "$MAVERGREEN_SOURCE_FILES" "$raw"
  source="$MAVERGREEN_SOURCE_FILES"
else
  die "$repo is not the top of a git checkout and MAVERGREEN_SOURCE_FILES is unset: no tracked file list to scan"
fi

LC_ALL=C awk '
  { p = $0 }
  p == "" || p ~ /^\// || p ~ /^"/ || p ~ /\t|\r/ || ("/" p "/") ~ /\/(\.|\.\.)?\// {
    print "scan-local-backfills: unusable path in the file list: \"" p "\"" > "/dev/stderr"; bad = 1; next }
  !(p in seen) { seen[p] = 1; print p }
  END { exit bad }' "$raw" > "$w/paths" || exit 2

files="$w/files"; : > "$files"; skipped=0
while IFS= read -r p; do
  if [ -L "$repo/$p" ] || [ -d "$repo/$p" ]; then
    skipped=$((skipped + 1))
  elif [ -f "$repo/$p" ]; then
    printf '%s\n' "$p" >> "$files"
  else
    die "$p is in the file list ($source) but is not in $repo"
  fi
done < "$w/paths"
[ -s "$files" ] || die "the file list ($source) names no file to scan"

rows="$w/inventory"; : > "$rows"
if [ -e "$repo/$INV" ]; then
  grep -qx "$INV" "$files" || die "$INV exists but is not in the file list ($source)"
  LC_ALL=C awk -v INV="$INV" '
    function fail(msg) { print "scan-local-backfills: " INV ":" FNR ": " msg > "/dev/stderr"; bad = 1 }
    FNR == NR { tracked[$0] = 1; next }
    { lines++ }
    lines == 1 {
      if ($0 != "path\tkind\tsymbols\treason") fail("the first line must be the header path<TAB>kind<TAB>symbols<TAB>reason")
      next
    }
    {
      if ($0 ~ /\r/) { fail("carriage return (CRLF line ending?)"); next }
      n = split($0, f, "\t")
      if (n != 4) { fail("expected 4 tab-separated columns, got " n); next }
      if (f[1] == "" || f[2] == "" || f[3] == "" || f[4] == "") { fail("empty column"); next }
      p = f[1]
      if (p ~ /^\// || ("/" p "/") ~ /\/(\.|\.\.)?\// || p ~ /\/$/) { fail("path \"" p "\" must be a literal repo-relative path"); next }
      if (p ~ /[*?]|\[/) { fail("path \"" p "\" is a wildcard; name each file"); next }
      if (!(p in tracked)) { fail("path \"" p "\" is not a tracked file"); next }
      if (!(f[2] in kinds)) { fail("unsupported kind \"" f[2] "\" (local-backfill, product-adaptation, upstream or test-only)"); next }
      ns = split(f[3], s, ",")
      if (f[3] != "-") for (i = 1; i <= ns; i++) if (s[i] !~ /^[A-Za-z_][A-Za-z0-9_]*$/) { fail("symbol \"" s[i] "\" is not a name"); next }
      for (i = 1; i <= ns; i++) {
        k = p SUBSEP s[i]
        if (k in dup) { fail("duplicate row for " p " symbol " s[i] " (first at line " dup[k] ")"); next }
        dup[k] = FNR
      }
      print
    }
    END { if (lines == 0) fail("empty file; it needs at least the header"); exit bad }
    BEGIN { kinds["local-backfill"]; kinds["product-adaptation"]; kinds["upstream"]; kinds["test-only"] }
  ' "$files" "$repo/$INV" > "$rows" || exit 2
fi

if [ "$mode" = inventory ]; then cat "$rows"; exit 0; fi

{
  grep -v '^#' "$SELF/local-backfill-symbols" | sed '/^$/d; s/$/	known/'
  cut -f3 "$rows" | tr ',' '\n' | grep -vx -- '-' | sed '/^$/d; s/$/	inventory/'
} > "$w/symbols"
(cd "$repo" && LC_ALL=C awk -f "$SELF/local-backfills.awk" "$w/symbols" "$files") > "$w/found" || exit 2
LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2n -k3,3 -k4,4 "$w/found"
printf 'scan-local-backfills: scanned %s files from %s (%s symlinks or submodules skipped): %s candidates. Candidates are not verdicts, and no finding is not proof of absence.\n' \
  "$(wc -l < "$files" | tr -d ' ')" "$source" "$skipped" "$(wc -l < "$w/found" | tr -d ' ')" >&2
