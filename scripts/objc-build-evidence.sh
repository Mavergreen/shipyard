#!/bin/sh
# platform: macOS-only -- builds the host-native objc-compat helper against the pinned host SDK, then reads the link's outputs as data
#   usage: objc-build-evidence.sh --artifact FILE --prestrip FILE --source-root DIR [--link-map FILE
#                                 --provider-prefix DIR] --references REF_DIR --output NEW_FILE
#          For an artifact that links no provider, give neither --link-map nor --provider-prefix: the
#          evidence then records no link map and an empty provider list. One without the other is a
#          usage error.
#          Writes schema-1 Objective-C build evidence for the final artifact FILE to NEW_FILE, which
#          must not exist in any form; it is written exclusively and atomically. The evidence
#          records identities -- the final and prestrip images, the link map, the reference manifest,
#          the prepared source tree under DIR (every entry but .git, by content) -- and, for each
#          provider PREFIX declares, which members of its archive the link placed and where each of
#          their atoms landed. That mapping is checked before it is written: the final and prestrip
#          x86_64 slices must carry identical sections, the link map must list exactly the prestrip
#          image's sections, and every placed atom must be a symbol its archive member defines and
#          the prestrip image has at that address (tools/objc-compat/provider.c). A provider that
#          was not linked gets an empty mapping, not an error. The evidence is never an approval:
#          scripts/objc-compat.sh re-verifies it against the artifact's bytes every run, and guard
#          or binding receipts still need their own review (it writes none).
#          Exit 0 written, 2 usage or an existing destination, 4 a mismatch, an unreadable or
#          invalid input, or a helper that did not build.
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
T=$(mktemp -d "${TMPDIR:-/tmp}/objc-build-evidence.XXXXXX")
trap 'rm -rf "$T"' EXIT
sh "$HERE/objc-compat-build.sh" --analyzer "$T/objc-compat" 2>"$T/build.log" || {
  cat "$T/build.log" >&2; echo "objc-build-evidence: the helper did not build" >&2; exit 4; }
rc=0
"$T/objc-compat" emit-build-evidence "$@" || rc=$?
exit "$rc"
