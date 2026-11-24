#!/bin/sh
# platform: host-agnostic -- Mach-O payloads need LIPO, OTOOL and NM off macOS (macho-slices.sh, macho-cxxabi.sh)
#   usage: stand-in-feeds.sh <dist-dir> <version> [repo-root]
#          For a build that signs nothing (a PR build, a local rehearsal): writes an UNSIGNED
#          <short>.xml for every product the dist's pkgs ship that has no feed yet, and stand-in
#          RELEASE_NOTES.md if there is none, so conformance can require every product's feed. Never
#          run it on a dist that will be published: the Engine accepts no stand-in. The repo root
#          (default $MAVERGREEN_REPO_ROOT, else the current directory) declares the products.
# spec: tests/artifact-conformance-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavergreen-meta.sh"
. "$SELF/stand-in-marker.sh"
dist="${1:?stand-in-feeds: dist directory required}"
ver="${2:?stand-in-feeds: version required}"
root="${3:-${MAVERGREEN_REPO_ROOT:-.}}"
_t="$(mktemp -d "${TMPDIR:-/tmp}/stand-in-feeds.XXXXXX")"; trap 'rm -rf "$_t"' EXIT
sh "$SELF/artifact-facts.sh" "$dist" "$ver" "$root" > "$_t/facts" \
  || { echo "stand-in-feeds: artifact-facts.sh failed" >&2; exit 1; }
grep -qx end-of-facts "$_t/facts" || { echo "stand-in-feeds: the fact stream is incomplete" >&2; exit 1; }
awk '$1 == "derived" && $3 != "none" { d[$2] = 1 } $1 == "built-on-install" { b[$2] = 1 } $1 == "manifest" { m[$2] = $3 }
     END { for (k in m) if ((m[k] in d) && !(m[k] in b)) print k }' "$_t/facts" | sort -u > "$_t/pkgs"
while IFS= read -r pk; do
  P="$(awk -v p="$pk" '$1 == "manifest" && $2 == p { print $3; exit }' "$_t/facts")"
  [ -n "$P" ] || continue
  [ ! -e "$dist/$P.xml" ] || continue
  repo="$(mg_repo)" || { echo "stand-in-feeds: cannot tell which repo $P's release is in; set GITHUB_REPOSITORY (OWNER/REPO)" >&2; exit 2; }
  [ -s "$dist/RELEASE_NOTES.md" ] || printf '%s\n\n- nothing is published from it\n' "$STAND_IN_NOTES_HEADING" > "$dist/RELEASE_NOTES.md"
  len="$(wc -c < "$dist/$pk" | tr -d ' ')"
  sh "$SELF/gen_appcast.sh" "$P" "$ver" "https://github.com/Mavergreen/${repo#*/}/releases/download/$ver/$pk" 10.9.5 \
    "$dist/RELEASE_NOTES.md" "sparkle:edSignature=\"$STAND_IN_SIGNATURE\" length=\"$len\"" > "$dist/$P.xml"
  echo "stand-in-feeds: wrote an unsigned $dist/$P.xml" >&2
done < "$_t/pkgs"
