#!/bin/sh
# platform: host-agnostic -- the wrapper; the pinned Drydock's drydock-objc writes evidence on macOS only (on Linux it exits 2)
#   usage: objc-build-evidence.sh --artifact FILE --prestrip FILE --source-root DIR [--link-map FILE
#                                 --provider-prefix DIR] --references REF_DIR --output NEW_FILE
#          Runs `drydock-objc evidence` from the pinned Drydock release (.mavergreen/ingredients/drydock, through
#          scripts/fetch_drydock.sh) with these arguments, and exits with its status. It writes schema-1
#          Objective-C build evidence for the final artifact FILE to NEW_FILE, which must not exist in any form:
#          the identities of the final and prestrip images, the link map, the reference set and the prepared
#          source tree under DIR, and, for each provider PREFIX declares, which members of its archive the link
#          placed and where their atoms landed, checked before it is written. For an artifact that links no
#          provider, give neither --link-map nor --provider-prefix; one without the other is a usage error. The
#          evidence is never an approval: scripts/objc-compat.sh re-verifies it against the artifact every run.
#          Exit 0 written, 2 usage or an existing destination, 4 a mismatch, an unreadable or invalid input,
#          a Drydock that could not be fetched, or a host other than macOS.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
usage() { echo "usage: objc-build-evidence.sh --artifact FILE --prestrip FILE --source-root DIR [--link-map FILE --provider-prefix DIR] --references REF_DIR --output NEW_FILE" >&2; exit 2; }
[ $# -eq 14 ] || [ $# -eq 10 ] || usage
i=0
for a in "$@"; do
  i=$((i + 1))
  # platform: odd positions are option names; the helper checks each appears once.
  if [ $((i % 2)) = 1 ]; then
    case "$a" in --artifact|--prestrip|--source-root|--link-map|--provider-prefix|--references|--output) ;; *) usage ;; esac
  fi
done
# platform: drydock-objc's evidence is built for macOS only; on Linux it exits 2, which the guard would read as misuse, so
#   another host is cannot-measure here, before any fetch. MAVERGREEN_DRYDOCK_HOST (linux or mac) replaces the host's answer.
case "${MAVERGREEN_DRYDOCK_HOST:-$(uname -s)}" in
  mac|Darwin) ;;
  *) echo "objc-build-evidence: drydock-objc evidence runs on macOS only, not on ${MAVERGREEN_DRYDOCK_HOST:-$(uname -s)}" >&2; exit 4 ;;
esac
D=$(sh "$HERE/fetch_drydock.sh" "$HERE/..") || { echo "objc-build-evidence: the pinned Drydock could not be had" >&2; exit 4; }
exec "$D/bin/drydock-objc" evidence "$@"
