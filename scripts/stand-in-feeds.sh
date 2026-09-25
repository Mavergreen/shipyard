#!/bin/sh
# platform: macOS-only -- artifact-facts.sh reads the pkgs with pkgutil and PlistBuddy
#   usage: stand-in-feeds.sh <dist-dir> <version>
#          For a build that signs nothing (a PR build, a local rehearsal): writes an UNSIGNED
#          <short>.xml for every updater the dist's pkgs install that has no feed yet, and stand-in
#          RELEASE_NOTES.md if there is none, so conformance can require every updater's feed. Never
#          run it on a dist that will be published: no installed updater accepts the stand-in.
# spec: tests/artifact-conformance-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/stand-in-marker.sh"
dist="${1:?stand-in-feeds: dist directory required}"
ver="${2:?stand-in-feeds: version required}"
_t="$(mktemp -d "${TMPDIR:-/tmp}/stand-in-feeds.XXXXXX")"; trap 'rm -rf "$_t"' EXIT
sh "$SELF/artifact-facts.sh" "$dist" "$ver" "$dist" > "$_t/facts" \
  || { echo "stand-in-feeds: artifact-facts.sh failed" >&2; exit 1; }
grep -qx end-of-facts "$_t/facts" || { echo "stand-in-feeds: the fact stream is incomplete" >&2; exit 1; }
awk '$1 == "sparkle" { print $2 }' "$_t/facts" | sort -u > "$_t/pkgs"
while IFS= read -r pk; do
  P="$(awk -v p="$pk" '$1 == "manifest" && $2 == p { print $3; exit }' "$_t/facts")"
  [ -n "$P" ] || continue
  [ ! -e "$dist/$P.xml" ] || continue
  repo="$(sh "$SELF/product-name.sh" repo "$P")" || { echo "stand-in-feeds: $P is not in scripts/product-names" >&2; exit 1; }
  [ -s "$dist/RELEASE_NOTES.md" ] || printf '%s\n\n- nothing is published from it\n' "$STAND_IN_NOTES_HEADING" > "$dist/RELEASE_NOTES.md"
  len="$(wc -c < "$dist/$pk" | tr -d ' ')"
  sh "$SELF/gen_appcast.sh" "$P" "$ver" "https://github.com/Mavergreen/$repo/releases/download/$ver/$pk" 10.9.5 \
    "$dist/RELEASE_NOTES.md" "sparkle:edSignature=\"$STAND_IN_SIGNATURE\" length=\"$len\"" > "$dist/$P.xml"
  echo "stand-in-feeds: wrote an unsigned $dist/$P.xml" >&2
done < "$_t/pkgs"
