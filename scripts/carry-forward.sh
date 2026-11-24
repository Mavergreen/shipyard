#!/bin/sh
# platform: host-agnostic
#   usage: carry-forward.sh DIST OWNER/REPO DECISION_FILE [NOTES]
#          For each "product <short> carry <tag>" line of DECISION_FILE (release-decision.sh's output),
#          replaces DIST/<short>.xml with <tag>'s, verified against that release's SHA256SUMS by
#          fetch-release-pkg.sh; deletes that product's rebuilt <short>-<version>.pkg,
#          <short>-<version>-macos-*.tar.gz and <short>-<version>-dSYM.tar.gz from DIST (a file belongs to
#          the longest product short that prefixes it before a hyphen); and appends, under one
#          "### Unchanged" heading at the end of DIST/NOTES (default RELEASE_NOTES.md), "- <name>:
#          unchanged, still <version>", <name> the carried feed's channel title and <version> its
#          sparkle:shortVersionString. Exit 0; 1 on a failed fetch or a feed with no version; 2 on usage.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Reproducible builds" -- an
#       unchanged product's feed keeps offering the release it was last changed in, and nothing is
#       uploaded that no feed offers.
set -eu
LC_ALL=C; export LC_ALL
SELF="$(cd "$(dirname "$0")" && pwd)"
usage() { echo "usage: carry-forward.sh DIST OWNER/REPO DECISION_FILE [NOTES]" >&2; exit 2; }
[ $# -ge 3 ] && [ $# -le 4 ] && [ -d "$1" ] && [ -f "$3" ] || usage
DIST="$1"; REPO="$2"; DEC="$3"; NOTES="${4:-RELEASE_NOTES.md}"
case "$REPO" in */*) ;; *) usage ;; esac
die() { echo "carry-forward: $1" >&2; exit 1; }
w="$(mktemp -d "${TMPDIR:-/tmp}/carry-forward.XXXXXX")"; trap 'rm -rf "$w"' EXIT

awk '$1 == "product" { print $2 }' "$DEC" | awk '{ print length($0), $0 }' | sort -rn | cut -d' ' -f2 > "$w/shorts"
owner() {
  while IFS= read -r _s; do
    case "$1" in "$_s"-*) printf '%s\n' "$_s"; return 0 ;; esac
  done < "$w/shorts"
  return 1
}

awk '$1 == "product" && $3 == "carry" && NF == 4 { print $2, $4 }' "$DEC" > "$w/carry"
[ -s "$w/carry" ] || exit 0
: > "$w/lines"
while read -r s tag; do
  f="$(sh "$SELF/fetch-release-pkg.sh" "${REPO#*/}" "$tag" "$s.xml" "$w/rel/$tag" 2> "$w/err")" \
    || die "cannot carry $s's feed from $tag: $(tail -n 1 "$w/err")"
  v="$(sed -n 's:.*<sparkle\:shortVersionString>\([^<]*\)</sparkle\:shortVersionString>.*:\1:p' "$f" | head -n 1)"
  [ -n "$v" ] || die "$tag's $s.xml has no sparkle:shortVersionString"
  name="$(sed -n 's:.*<title>\([^<]*\)</title>.*:\1:p' "$f" | head -n 1 | sed -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&amp;/\&/g')"
  cp "$f" "$DIST/$s.xml"
  for a in "$DIST"/"$s"-*; do
    [ -f "$a" ] || continue
    b="${a##*/}"
    [ "$(owner "$b")" = "$s" ] || continue
    case "$b" in *.pkg|*-macos-*.tar.gz|*-dSYM.tar.gz) rm -f "$a" ;; esac
  done
  printf -- '- %s: unchanged, still %s\n' "${name:-$s}" "$v" >> "$w/lines"
done < "$w/carry"
printf '\n### Unchanged\n\n' >> "$DIST/$NOTES"
cat "$w/lines" >> "$DIST/$NOTES"
