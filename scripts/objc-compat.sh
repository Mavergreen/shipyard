#!/bin/sh
# platform: host-agnostic -- the wrapper; the pinned Drydock's drydock-objc analyzes on macOS only (on Linux it exits 2)
#   usage: objc-compat.sh --artifact FILE --root SHIPPED_ROOT --references REF_DIR --report NEW_FILE
#                         [--build-evidence FILE] [--provider-prefix DIR [--source-receipt FILE]] [--mode inventory|strict] [--exceptions FILE]
#          Runs `drydock-objc analyze` from the pinned Drydock release (components/drydock, through
#          scripts/fetch_drydock.sh) with these arguments, and exits with its status. The analyzer is Drydock's,
#          and its README and drydock-objc's header say what it does: it classifies every Objective-C message send
#          in FILE's x86_64 slice against the reference set REF_DIR (scripts/objc-reference-dir.sh names the
#          pinned one) and writes the schema-1 report to NEW_FILE, which must not exist in any form. FILE must
#          lie inside SHIPPED_ROOT. --build-evidence is the artifact's build evidence
#          (scripts/objc-build-evidence.sh); --provider-prefix an Objective-C provider's prefix; --source-receipt,
#          with both, the provider body's source receipt (scripts/objc-source-inventory.sh). inventory (the
#          default) reports what was measured; strict also fails on any unsupported or unresolved finding but
#          one a reviewed objc-api record listed in --exceptions names exactly (scripts/assert_binary_compatible.sh
#          writes the list). The report's analyzer id names the Drydock release and its analyzer source.
#          Nothing is executed: the artifact is read, never run or loaded.
#          Exit 0 measured (strict: and no blocking finding), 1 strict with a blocking finding,
#          2 usage, 4 cannot measure (including a Drydock that could not be fetched, or a host other than macOS).
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

usage() { echo "usage: objc-compat.sh --artifact FILE --root SHIPPED_ROOT --references REF_DIR --report NEW_FILE [--build-evidence FILE] [--provider-prefix DIR [--source-receipt FILE]] [--mode inventory|strict] [--exceptions FILE]" >&2; exit 2; }
n=$#
[ "$n" -ge 8 ] || usage
i=0
for a in "$@"; do
  i=$((i + 1))
  # platform: odd positions are option names; the analyzer validates values and repeats.
  if [ $((i % 2)) = 1 ]; then
    case "$a" in --artifact|--root|--references|--report|--build-evidence|--mode|--provider-prefix|--source-receipt|--exceptions) ;; *) usage ;; esac
  fi
done
[ $((n % 2)) = 0 ] || usage
# platform: drydock-objc's analyze is built for macOS only; on Linux it exits 2, which the guard would read as misuse, so
#   another host is cannot-measure here, before any fetch. MAVERGREEN_DRYDOCK_HOST (linux or mac) replaces the host's answer.
case "${MAVERGREEN_DRYDOCK_HOST:-$(uname -s)}" in
  mac|Darwin) ;;
  *) echo "objc-compat: drydock-objc analyze runs on macOS only, not on ${MAVERGREEN_DRYDOCK_HOST:-$(uname -s)}" >&2; exit 4 ;;
esac
D=$(sh "$HERE/fetch_drydock.sh" "$HERE/../components/drydock") || { echo "objc-compat: the pinned Drydock could not be had" >&2; exit 4; }
exec "$D/bin/drydock-objc" analyze "$@"
