#!/bin/sh
#   usage: clone_pinned.sh REPO REF DIGEST DEST
#          The family's git-source supply-chain boundary. Idempotently fetches a pinned git source
#          into a shared, mode/host-independent cache and VERIFIES the checkout is exactly the pinned
#          commit -- fail closed on any mismatch (a moved/forced tag, a MITM, a wrong ref) rather than
#          silently build other code. Consumers pin REF (the readable tag/branch label, and what the
#          version derives from) and DIGEST (the commit sha), both Renovate-managed via a
#          git-refs/currentDigest customManager, so a bump updates both together. Empty DIGEST =>
#          TOFU: trust REF's tip (a migration affordance, not the standard). ExternalProject
#          pre-creates DEST empty, so this builds in a temp sibling and atomically renames into
#          place.
# platform: with a DIGEST this fetches EXACTLY that commit -- one object, no branch tip, no history
#           walk -- so it is safe even for huge repos (llvm-project), works whether the commit is a
#           tag tip or behind a moving branch, and cannot yield anything but DIGEST (git verifies
#           fetched objects hash to it). GitHub serves any ref-reachable sha; if a server refuses a
#           bare sha this falls back to cloning REF and lets verify() reject a mismatch.
set -eu
REPO=$1; REF=$2; DIGEST=$3; DEST=$4

verify() {  # $1 = a git worktree; HEAD must be DIGEST (when a DIGEST is pinned)
  [ -n "$DIGEST" ] || return 0
  got=$(git -C "$1" rev-parse HEAD 2>/dev/null || echo none)
  [ "$got" = "$DIGEST" ] && return 0
  echo "clone-verify FAIL: $REPO wanted commit $DIGEST, got $got" >&2
  return 1
}

if [ -d "$DEST/.git" ]; then
  verify "$DEST" || exit 1        # a cached checkout must still be the pinned commit
  echo "src cache hit: $DEST" >&2
  exit 0
fi

mkdir -p "$(dirname "$DEST")"
tmp="$DEST.tmp.$$"; rm -rf "$tmp"
if [ -n "$DIGEST" ]; then
  git init -q "$tmp"
  git -C "$tmp" remote add origin "$REPO"
  if git -C "$tmp" fetch -q --depth 1 origin "$DIGEST" 2>/dev/null; then
    git -C "$tmp" checkout -q FETCH_HEAD
  else
    rm -rf "$tmp"                 # server won't serve a bare sha: clone the ref, verify() catches drift
    git clone -q --depth 1 --branch "$REF" "$REPO" "$tmp" || { rm -rf "$tmp"; exit 1; }
  fi
else
  git clone -q --depth 1 --branch "$REF" "$REPO" "$tmp" || { rm -rf "$tmp"; exit 1; }
fi
verify "$tmp" || { rm -rf "$tmp"; exit 1; }
rm -rf "$DEST"
mv "$tmp" "$DEST"
echo "src cached ($REF@${DIGEST:-unpinned}): $DEST" >&2   # progress -> stderr; stdout stays clean for callers that capture it
