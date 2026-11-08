#!/bin/sh
# platform: host-agnostic -- x86_64 Linux (Recaulk's release host) or a Mac; the receipt is the same on both
#   usage: objc-source-inventory.sh [--clang-prefix PREFIX] --inputs FILE --root DIR [--root DIR ...]
#                                   --unit LABEL [--unit LABEL ...] [--include LABELDIR ...] --output NEW_FILE
#          Writes the Objective-C source receipt for the prepared provider source FILE lists (`SHA256  LABEL`
#          lines, as Recaulk's build records them), found under the --root directories, to NEW_FILE, with
#          `drydock-objc receipt` from the pinned Drydock release (components/drydock, through
#          scripts/fetch_drydock.sh: on Linux its Linux archive's drydock-objc). PREFIX is the pinned clang
#          (components/objc-receipt-clang: the first clang22 whose Linux archive ships libclang), fetched
#          through fetch_clang22.sh when not given; drydock-objc loads its libclang and parses against the pinned
#          floor SDK, which this fetches through fetch_sdk.sh. Generation only: the analyzer reads the receipt
#          and never loads libclang. Nothing supplied is executed.
#          Exit 0 written, 2 usage or an existing destination, 4 a prerequisite, an unverifiable input or a
#          parse failure. drydock-objc runs libclang in its own process, so any other exit it gives, a death by
#          signal included, is 4.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
fail() { echo "objc-source-inventory: $*" >&2; exit 4; }
usage() { echo 'usage: objc-source-inventory.sh [--clang-prefix PREFIX] --inputs FILE --root DIR [--root DIR ...] --unit LABEL [--unit LABEL ...] [--include LABELDIR ...] --output NEW_FILE' >&2; exit 2; }
prefix=
n=0
for a in "$@"; do
  n=$((n + 1))
  # platform: odd positions are option names; drydock-objc validates values and repeats.
  if [ $((n % 2)) = 1 ]; then
    case "$a" in --clang-prefix|--inputs|--root|--unit|--include|--output) ;; *) usage ;; esac
  fi
done
[ $((n % 2)) = 0 ] && [ "$n" -ge 8 ] || usage
remaining=$#
while [ "$remaining" -gt 0 ]; do
  case "$1" in
    --clang-prefix) [ -z "$prefix" ] || usage; prefix=$2; shift 2 ;;
    *) option=$1; value=$2; shift 2; set -- "$@" "$option" "$value" ;;
  esac
  remaining=$((remaining - 2))
done
D=$(sh "$HERE/fetch_drydock.sh" "$HERE/../components/drydock") || fail 'cannot fetch the pinned Drydock'
if [ -z "$prefix" ]; then
  prefix=$(sh "$HERE/fetch_clang22.sh" "$HERE/../components/objc-receipt-clang") || fail 'cannot fetch the pinned receipt clang'
fi
# spec: Drydock's cli/drydock-objc.c header -- the receipt parses against the floor SDK Recaulk's build uses.
floor_sdk=$(sh "$HERE/fetch_sdk.sh" --arch x86_64) || fail 'cannot fetch the pinned floor SDK'
rc=0
"$D/bin/drydock-objc" receipt --clang-prefix "$prefix" --sdk "$floor_sdk" "$@" || rc=$?
case "$rc" in 0|2|4) exit "$rc" ;; *) fail "drydock-objc receipt failed (exit $rc)" ;; esac
