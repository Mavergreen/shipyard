#!/bin/sh
# platform: host-agnostic
#   usage: objc-build-evidence.sh --artifact FILE --prestrip FILE --source-root DIR [--link-map FILE
#                                 [--provider-prefix DIR]] --references REF_DIR --output NEW_FILE
#          objc-build-evidence.sh --tree-digest-only --source-root DIR
#          objc-build-evidence.sh --sdk-digest-only --sdk-root DIR
#          Runs `drydock-objc evidence` from the pinned Drydock release (components/drydock, through
#          scripts/fetch_drydock.sh) with these arguments, and exits with its status. It writes schema-1
#          Objective-C build evidence for the final artifact FILE to NEW_FILE, which must not exist in any form:
#          the identities of the final and prestrip images, the link map, the reference set and the prepared
#          source tree under DIR, and, for each provider PREFIX declares, which members of its archive the link
#          placed and where their atoms landed, checked before it is written. --link-map records the link
#          map's identity, which scripts/objc-compat.sh's --link-map must match; --provider-prefix needs --link-map. The
#          evidence is never an approval: scripts/objc-compat.sh re-verifies it against the artifact every run.
#          --tree-digest-only prints the digest of the prepared source tree DIR, the source.tree_sha256 that
#          schema-2 evidence names; --sdk-digest-only prints the header digest of the SDK DIR, which an sdk: cite
#          holds against only when it is the reference set's pinned floor SDK's. Each writes nothing else.
#          Exit 0 written (or printed), 2 usage or an existing destination, 4 a mismatch, an unreadable or invalid input,
#          or a Drydock that could not be fetched.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
usage() {
  echo "usage: objc-build-evidence.sh --artifact FILE --prestrip FILE --source-root DIR [--link-map FILE [--provider-prefix DIR]] --references REF_DIR --output NEW_FILE" >&2
  echo "       objc-build-evidence.sh --tree-digest-only --source-root DIR | --sdk-digest-only --sdk-root DIR" >&2
  exit 2
}
if [ $# -eq 3 ]; then
  case "$1:$2" in --tree-digest-only:--source-root|--sdk-digest-only:--sdk-root) ;; *) usage ;; esac
  [ -n "$3" ] || usage
else
  [ $# -eq 14 ] || [ $# -eq 12 ] || [ $# -eq 10 ] || usage
  i=0
  for a in "$@"; do
    i=$((i + 1))
    # platform: odd positions are option names; the helper checks each appears once.
    if [ $((i % 2)) = 1 ]; then
      case "$a" in --artifact|--prestrip|--source-root|--link-map|--provider-prefix|--references|--output) ;; *) usage ;; esac
    fi
  done
fi
D=$(sh "$HERE/fetch_drydock.sh" "$HERE/../components/drydock") || { echo "objc-build-evidence: the pinned Drydock could not be had" >&2; exit 4; }
exec "$D/bin/drydock-objc" evidence "$@"
