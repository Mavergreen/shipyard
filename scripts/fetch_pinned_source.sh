#!/bin/sh
# platform: host-agnostic
#   usage: fetch_pinned_source.sh REPO DIGEST SHA256 DEST
#          fetch_pinned_source.sh --url REPO DIGEST
#          The family's tarball-source supply-chain boundary, for a build that must run where there is
#          no git: OS X 10.9 has none without Xcode's Command Line Tools. REPO is a GitHub repository
#          (https://github.com/OWNER/NAME, with or without .git), DIGEST its pinned commit (40 hex
#          digits), SHA256 the pinned digest of GitHub's tarball of that commit, which --url prints
#          (https://codeload.github.com/OWNER/NAME/tar.gz/DIGEST). The tarball is fetched once into
#          ${MAVERICKS_SOURCE_CACHE:-$HOME/Library/Caches/mavericks-sources} and verified by
#          mavericks_fetch.sh's mav_fetch_verified: fail closed, a mismatch deleted and its SHA-256
#          printed. Then DEST is REPLACED by a fresh extraction: the tarball's one top-level directory,
#          NAME-DIGEST, with its files, modes and symlinks as GitHub wrote them, plus
#          DEST/.mavergreen-source, one line "REPO DIGEST SHA256". Fresh on every call, so a caller that
#          patches the tree starts from upstream's bytes. Extracted into a temp dir beside DEST; then the
#          old DEST is moved aside, the new one renamed in, and the old one removed. A failed fetch or
#          extraction, a failed rename or an INT or TERM before the new tree is in place leaves DEST as it
#          was (not atomic: between the two renames DEST is briefly absent). Progress goes to
#          stderr; stdout stays empty (--url prints only the URL). Exit 1 on a failed fetch, checksum or
#          extraction, 2 on a usage error. MAVERICKS_CODELOAD replaces https://codeload.github.com (the
#          tests serve a file:// tree).
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
usage() { echo "usage: fetch_pinned_source.sh REPO DIGEST SHA256 DEST | --url REPO DIGEST" >&2; exit 2; }
URL_ONLY=0
if [ "${1:-}" = --url ]; then URL_ONLY=1; shift; [ $# -eq 2 ] || usage; else [ $# -eq 4 ] || usage; fi
REPO=$1; DIGEST=$2
case "$REPO" in
  https://github.com/*/*) ;;
  *) echo "fetch_pinned_source: '$REPO' is not a GitHub repository URL (https://github.com/OWNER/NAME)" >&2; exit 2 ;;
esac
PATH_PART="${REPO#https://github.com/}"; PATH_PART="${PATH_PART%.git}"
OWNER="${PATH_PART%%/*}"; NAME="${PATH_PART#*/}"
case "$OWNER/$NAME" in
  */*/*|/*|*/) echo "fetch_pinned_source: '$REPO' is not a GitHub repository URL (https://github.com/OWNER/NAME)" >&2; exit 2 ;;
esac
case "$DIGEST" in
  *[!0-9a-f]*|'') echo "fetch_pinned_source: '$DIGEST' is not a commit (40 hex digits)" >&2; exit 2 ;;
esac
[ "${#DIGEST}" -eq 40 ] || { echo "fetch_pinned_source: '$DIGEST' is not a commit (40 hex digits)" >&2; exit 2; }
URL="${MAVERICKS_CODELOAD:-https://codeload.github.com}/$OWNER/$NAME/tar.gz/$DIGEST"
if [ "$URL_ONLY" = 1 ]; then echo "$URL"; exit 0; fi
SHA256=$3; DEST=$4
case "$SHA256" in
  *[!0-9a-f]*|'') echo "fetch_pinned_source: '$SHA256' is not a SHA-256 (64 hex digits)" >&2; exit 2 ;;
esac
[ "${#SHA256}" -eq 64 ] || { echo "fetch_pinned_source: '$SHA256' is not a SHA-256 (64 hex digits)" >&2; exit 2; }
while [ "${DEST%/}" != "$DEST" ]; do DEST="${DEST%/}"; done
case "$DEST" in
  ''|.|..) echo "fetch_pinned_source: refusing DEST '$DEST'" >&2; exit 2 ;;
esac
. "$SELF/mavericks_fetch.sh"
CACHE="${MAVERICKS_SOURCE_CACHE:-$HOME/Library/Caches/mavericks-sources}"
TOP="$NAME-$DIGEST"
mav_fetch_verified "$URL" "$SHA256" "$CACHE" "$TOP.tar.gz" || {
  echo "fetch_pinned_source: could not fetch and verify $URL" >&2; exit 1; }
mkdir -p "$(dirname "$DEST")"
tmp=""; old=""
cleanup() {  # whatever ends this: the old DEST back if the new one is not in place, then no temp dirs
  if [ -n "$old" ] && [ -e "$old/dest" ] && [ ! -e "$DEST" ]; then mv "$old/dest" "$DEST"; fi
  rm -rf "$tmp" ${old:+"$old"}
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
tmp="$(mktemp -d "$DEST.tmp.XXXXXX")"
tar xzf "$CACHE/$TOP.tar.gz" -C "$tmp" || { echo "fetch_pinned_source: could not extract $CACHE/$TOP.tar.gz" >&2; exit 1; }
[ "$(ls -A "$tmp")" = "$TOP" ] && [ -d "$tmp/$TOP" ] || {
  echo "fetch_pinned_source: $CACHE/$TOP.tar.gz holds $(ls -A "$tmp" | tr '\n' ' ')rather than the one directory $TOP" >&2; exit 1; }
printf '%s %s %s\n' "$REPO" "$DIGEST" "$SHA256" > "$tmp/$TOP/.mavergreen-source"
if [ -e "$DEST" ] || [ -L "$DEST" ]; then old="$(mktemp -d "$DEST.old.XXXXXX")"; mv "$DEST" "$old/dest"; fi
mv "$tmp/$TOP" "$DEST" || { echo "fetch_pinned_source: could not move the new tree to $DEST" >&2; exit 1; }
echo "src extracted ($NAME@$DIGEST): $DEST" >&2
