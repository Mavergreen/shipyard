#!/bin/sh
# platform: macOS-only -- builds the host-native objc-compat helper against the pinned host SDK, then reads a provider declaration
#   usage: objc-provider-link-args.sh --prefix PREFIX --link-map FILE
#          Prints the linker arguments that link the Objective-C provider(s) PREFIX declares
#          (PREFIX/share/recaulk/objc-providers.json, e.g. Recaulk's openURLs backfill) into the
#          binary being linked, one argument per line, in this order: the absolute archive path,
#          -Wl,-u,_ROOT for each activation root, -framework NAME for each required framework, then
#          -Xlinker -map -Xlinker FILE so the link leaves the map scripts/objc-build-evidence.sh reads.
#          The declaration is validated first (tools/objc-compat/main.m load_provider_prefix): exactly
#          the known keys, plain identifiers, a strong framework policy, a shipping x86_64 archive whose
#          bytes match the declared digest. A path holding CR, LF or another control character is
#          refused, since it could not be one line. Nothing is evaluated: read the lines into
#          arguments (`while IFS= read -r l; do set -- "$@" "$l"; done`). Which binary to link is the
#          caller's choice. This generates linkage, not an acceptance verdict: only scripts/objc-compat.sh
#          with build evidence can say a send is provided.
#          Exit 0 printed, 2 usage, 4 an invalid or stale declaration or a helper that did not build.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
usage() { echo "usage: objc-provider-link-args.sh --prefix PREFIX --link-map FILE" >&2; exit 2; }
[ $# -eq 4 ] || usage
case "$1:$3" in --prefix:--link-map|--link-map:--prefix) ;; *) usage ;; esac
T=$(mktemp -d "${TMPDIR:-/tmp}/objc-link-args.XXXXXX")
trap 'rm -rf "$T"' EXIT
sh "$HERE/objc-compat-build.sh" --analyzer "$T/objc-compat" 2>"$T/build.log" || {
  cat "$T/build.log" >&2; echo "objc-provider-link-args: the helper did not build" >&2; exit 4; }
rc=0
"$T/objc-compat" provider-link-args "$@" || rc=$?
exit "$rc"
