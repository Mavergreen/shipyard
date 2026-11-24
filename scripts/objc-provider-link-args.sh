#!/bin/sh
# platform: host-agnostic
#   usage: objc-provider-link-args.sh --prefix PREFIX --link-map FILE [--provider ID]...
#          Runs `drydock-objc link-args` from the pinned Drydock release (components/drydock, through
#          scripts/fetch_drydock.sh) with these arguments, and exits with its status. It prints the linker
#          arguments that link the Objective-C provider(s) PREFIX declares
#          (PREFIX/share/recaulk/objc-providers.json, e.g. Recaulk's openURLs backfill) into the binary being
#          linked: each --provider ID names one to link, and with none every one is linked. One argument per
#          line: the absolute archive path, -Wl,-u,_ROOT for each activation root, -framework NAME for each
#          required framework, then -Xlinker -map -Xlinker FILE so the link leaves the map
#          scripts/objc-build-evidence.sh reads. The declaration is validated first, and a path holding a
#          control character is refused. Nothing is evaluated: read the lines into arguments
#          (`while IFS= read -r l; do set -- "$@" "$l"; done`). This generates linkage, not an acceptance
#          verdict: only scripts/objc-compat.sh with build evidence can say a send is provided.
#          Exit 0 printed, 2 usage, 4 an invalid or stale declaration, or a Drydock that could not be fetched.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
usage() { echo "usage: objc-provider-link-args.sh --prefix PREFIX --link-map FILE [--provider ID]..." >&2; exit 2; }
[ $# -ge 4 ] && [ $(($# % 2)) = 0 ] || usage
i=0 prefixes=0 maps=0
for a in "$@"; do
  i=$((i + 1))
  # platform: odd positions are option names; drydock-objc validates each value.
  [ $((i % 2)) = 1 ] || continue
  case "$a" in
    --prefix) prefixes=$((prefixes + 1)) ;;
    --link-map) maps=$((maps + 1)) ;;
    --provider) ;;
    *) usage ;;
  esac
done
[ "$prefixes" = 1 ] && [ "$maps" = 1 ] || usage
D=$(sh "$HERE/fetch_drydock.sh" "$HERE/../components/drydock") || { echo "objc-provider-link-args: the pinned Drydock could not be had" >&2; exit 4; }
exec "$D/bin/drydock-objc" link-args "$@"
