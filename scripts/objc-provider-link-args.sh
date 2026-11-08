#!/bin/sh
# platform: host-agnostic -- the wrapper; the pinned Drydock's drydock-objc prints link arguments on macOS only (on Linux it exits 2)
#   usage: objc-provider-link-args.sh --prefix PREFIX --link-map FILE
#          Runs `drydock-objc link-args` from the pinned Drydock release (components/drydock, through
#          scripts/fetch_drydock.sh) with these arguments, and exits with its status. It prints the linker
#          arguments that link the Objective-C provider(s) PREFIX declares
#          (PREFIX/share/recaulk/objc-providers.json, e.g. Recaulk's openURLs backfill) into the binary being
#          linked, one argument per line: the absolute archive path, -Wl,-u,_ROOT for each activation root,
#          -framework NAME for each required framework, then -Xlinker -map -Xlinker FILE so the link leaves the
#          map scripts/objc-build-evidence.sh reads. The declaration is validated first, and a path holding a
#          control character is refused. Nothing is evaluated: read the lines into arguments
#          (`while IFS= read -r l; do set -- "$@" "$l"; done`). This generates linkage, not an acceptance
#          verdict: only scripts/objc-compat.sh with build evidence can say a send is provided.
#          Exit 0 printed, 2 usage, 4 an invalid or stale declaration, a Drydock that could not be fetched, or a host other than macOS.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
usage() { echo "usage: objc-provider-link-args.sh --prefix PREFIX --link-map FILE" >&2; exit 2; }
[ $# -eq 4 ] || usage
case "$1:$3" in --prefix:--link-map|--link-map:--prefix) ;; *) usage ;; esac
# platform: drydock-objc's link-args is built for macOS only; on Linux it exits 2, which the guard would read as misuse, so
#   another host is cannot-measure here, before any fetch. MAVERGREEN_DRYDOCK_HOST (linux or mac) replaces the host's answer.
case "${MAVERGREEN_DRYDOCK_HOST:-$(uname -s)}" in
  mac|Darwin) ;;
  *) echo "objc-provider-link-args: drydock-objc link-args runs on macOS only, not on ${MAVERGREEN_DRYDOCK_HOST:-$(uname -s)}" >&2; exit 4 ;;
esac
D=$(sh "$HERE/fetch_drydock.sh" "$HERE/../components/drydock") || { echo "objc-provider-link-args: the pinned Drydock could not be had" >&2; exit 4; }
exec "$D/bin/drydock-objc" link-args "$@"
