#!/bin/sh
# platform: host-agnostic
#   usage: release-decision.sh --manifest FILE --repo OWNER/REPO --line GLOB --repo-root DIR [--force-reason TEXT]
#          release-decision.sh --compare-only --manifest FILE --repo OWNER/REPO --against TAG
#          Compares FILE, a candidate CONTENT-MANIFEST.txt, with that of the latest release on the line
#          (previous-release-tag.sh --tag-glob GLOB over the repo's tags, from git ls-remote, or
#          $RELEASE_DECISION_TAGS, newline-separated, in tests). Prints "publish" or "skip", then
#          "product <short> new|changed|carry <tag>" for each product in FILE (each "meta <short>
#          feed-min-os" row), then a blank line and a Markdown summary. A product is carried when its
#          rows (artifacts <short>.pkg and <short>-macos-*.tar.gz, and meta <short>) equal the previous
#          manifest's and the previous release's SHA256SUMS lists <short>.xml; new when the previous
#          manifest has none of its rows; otherwise changed. skip only when every product is carried
#          and the previous release has no product FILE lacks. TEXT, trimmed and non-empty, or a
#          publish-unchanged deviation in DIR, publishes with every product changed; with no previous
#          release every product is new; a previous manifest that cannot be fetched or read publishes
#          with every product changed and a ::warning:: first in the summary. Exit 0 either way.
#          --compare-only prints the differing rows, "-<row>" and "+<row>": exit 0 identical, 1 different,
#          2 when TAG's manifest cannot be fetched or read. Exit 2 on usage. Releases are fetched by
#          fetch-release-pkg.sh, so MAVERGREEN_RELEASES serves them in tests.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Reproducible builds" -- a
#       rebuild publishes only when what a user installs changed, per product, or with a reason.
set -eu
LC_ALL=C; export LC_ALL
SELF="$(cd "$(dirname "$0")" && pwd)"
usage() {
  echo "usage: release-decision.sh --manifest FILE --repo OWNER/REPO --line GLOB --repo-root DIR [--force-reason TEXT]" >&2
  echo "       release-decision.sh --compare-only --manifest FILE --repo OWNER/REPO --against TAG" >&2
  exit 2
}
manifest=""; repo=""; line=""; root=""; reason=""; compare=no; against=""
while [ $# -gt 0 ]; do
  case "$1" in
    --compare-only) compare=yes; shift ;;
    --manifest|--repo|--line|--repo-root|--force-reason|--against)
      [ $# -ge 2 ] || usage
      case "$1" in
        --manifest) manifest="$2" ;; --repo) repo="$2" ;; --line) line="$2" ;;
        --repo-root) root="$2" ;; --force-reason) reason="$2" ;; --against) against="$2" ;;
      esac
      shift 2 ;;
    *) usage ;;
  esac
done
[ -f "$manifest" ] || usage
case "$repo" in */*) ;; *) usage ;; esac
name="${repo#*/}"
reason="$(printf '%s' "$reason" | tr '\n\t' '  ' | sed -e 's/^ *//' -e 's/ *$//')"
w="$(mktemp -d "${TMPDIR:-/tmp}/release-decision.XXXXXX")"; trap 'rm -rf "$w"' EXIT
sort -u "$manifest" > "$w/cand"

fetch() {
  why=""
  _f="$(sh "$SELF/fetch-release-pkg.sh" "$name" "$1" CONTENT-MANIFEST.txt "$w/rel/$1" 2> "$w/ferr")" \
    || { why="$(tail -n 1 "$w/ferr")"; return 1; }
  sort -u "$_f" > "$w/prev" || { why="cannot read $_f"; return 1; }
}
diffrows() {
  comm -23 "$w/prev" "$w/cand" | sed 's/^/-/' > "$w/minus"
  comm -13 "$w/prev" "$w/cand" | sed 's/^/+/' > "$w/plus"
  cat "$w/minus" "$w/plus" | sort -k1.2
}

if [ "$compare" = yes ]; then
  [ -n "$against" ] && [ -z "$line$root$reason" ] || usage
  fetch "$against" || { echo "release-decision: cannot read $repo $against's CONTENT-MANIFEST.txt: $why" >&2; exit 2; }
  diffrows > "$w/d"
  [ -s "$w/d" ] || exit 0
  cat "$w/d"
  exit 1
fi
[ -n "$line" ] && [ -d "$root" ] && [ -z "$against" ] || usage

. "$SELF/deviation-reason.sh"
shipyard_deviations "$root" > /dev/null 2>&1 || :
unchanged_why="$(shipyard_deviated publish-unchanged)" || unchanged_why=""

products="$(awk '$1 == "meta" && $3 == "feed-min-os" { print $2 }' "$w/cand" | sort -u)"
rows_of() {
  awk -v s="$1" '
    $2 == s ".pkg" || ($1 == "meta" && $2 == s) { print; next }
    index($2, s "-macos-") == 1 && substr($2, length($2) - 6) == ".tar.gz" { print }' "$2"
}

warn=""; prev=""
if [ -n "${RELEASE_DECISION_TAGS+x}" ]; then
  printf '%s\n' "$RELEASE_DECISION_TAGS" > "$w/tags"
elif git ls-remote --tags --refs "https://github.com/$repo" > "$w/refs" 2> "$w/lerr"; then
  sed 's|.*refs/tags/||' "$w/refs" > "$w/tags"
else
  warn="::warning::release-decision: cannot list $repo's tags ($(tail -n 1 "$w/lerr")), so this publishes"
fi
if [ -z "$warn" ]; then
  prev="$(sh "$SELF/previous-release-tag.sh" --tags-file "$w/tags" --tag-glob "$line")" \
    || warn="::warning::release-decision: cannot find the latest release on $line, so this publishes"
fi
if [ -z "$warn" ] && [ -n "$prev" ]; then
  if ! fetch "$prev"; then
    warn="::warning::release-decision: cannot read $prev's CONTENT-MANIFEST.txt ($why), so this publishes"
  else
    . "$SELF/mavergreen_fetch.sh"
    shipyard_curl --quiet "${MAVERGREEN_RELEASES:-https://github.com}/Mavergreen/$name/releases/download/$prev/SHA256SUMS" "$w/sums" 2>/dev/null \
      || warn="::warning::release-decision: cannot read $prev's SHA256SUMS, so this publishes"
  fi
fi

: > "$w/status"
for s in $products; do
  if [ -n "$reason" ] || [ -n "$unchanged_why" ] || [ -n "$warn" ]; then st=changed
  elif [ -z "$prev" ]; then st=new
  else
    rows_of "$s" "$w/cand" > "$w/c.$s"; rows_of "$s" "$w/prev" > "$w/p.$s"
    if [ ! -s "$w/p.$s" ]; then st=new
    elif cmp -s "$w/c.$s" "$w/p.$s" && awk -v f="$s.xml" '$2 == f || $2 == "*" f { ok = 1 } END { exit !ok }' "$w/sums"; then
      st="carry $prev"
    else st=changed
    fi
  fi
  printf 'product %s %s\n' "$s" "$st" >> "$w/status"
done

decision=publish
if [ -z "$reason$unchanged_why$warn" ] && [ -n "$prev" ] && ! grep -qv ' carry ' "$w/status"; then
  printf '%s\n' "$products" > "$w/prods"
  dropped="$(awk '$1 == "meta" && $3 == "feed-min-os" { print $2 }' "$w/prev" | sort -u | comm -23 - "$w/prods")"
  [ -n "$dropped" ] || decision=skip
fi

echo "$decision"
cat "$w/status"
echo
[ -z "$warn" ] || echo "$warn"
if [ -z "$warn" ] && [ -n "$prev" ]; then diffrows > "$w/d"; else : > "$w/d"; fi
if [ "$decision" = skip ]; then
  echo "Not published: content identical to $prev."
  if [ -d "$root/.git" ] && notes="$(cd "$root" && sh "$SELF/ingredient-notes.sh" "$prev" 2>/dev/null)" && [ -n "$notes" ]; then
    printf '\nIngredients that moved:\n%s\n' "$notes"
  fi
  exit 0
fi
[ -z "$reason" ] || printf '### Forced: %s\n\n' "$reason"
if [ -n "$unchanged_why" ]; then
  if [ -z "$warn" ] && [ -n "$prev" ] && [ ! -s "$w/d" ]; then
    printf 'Published although the content is identical to %s, by the publish-unchanged deviation: %s\n\n' "$prev" "$unchanged_why"
  else
    printf 'Published by the publish-unchanged deviation: %s\n\n' "$unchanged_why"
  fi
fi
[ -n "$prev" ] || [ -n "$warn" ] || printf 'First release on %s: there is no previous release to compare.\n' "$line"
if [ -s "$w/d" ]; then
  n="$(wc -l < "$w/d" | tr -d ' ')"
  printf '### Installed files changed\n\n```diff\n'
  head -n 40 "$w/d"
  printf '```\n'
  [ "$n" -le 40 ] || printf '\nand %s more\n' "$((n - 40))"
fi
