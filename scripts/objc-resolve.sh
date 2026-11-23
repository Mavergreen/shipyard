#!/bin/sh
# platform: host-agnostic -- the wrapper; the pinned Drydock's drydock-objc resolves on macOS only (on Linux it exits 2)
#   usage: objc-resolve.sh --artifact FILE --reviewed FILE --output NEW_FILE
#          Runs `drydock-objc resolve` from the pinned Drydock release (.mavergreen/ingredients/drydock, through
#          scripts/fetch_drydock.sh) with these arguments, and exits with its status. It reads the schema-2
#          reviewed build evidence --reviewed names and writes it to NEW_FILE, which must not exist in any form,
#          with every guard's and R2 and R3 row's symbol(s) and every crate's disambiguator read from the
#          artifact FILE; everything else is copied unchanged. A reviewed path names one function or the copies
#          of one generic instance; anything else is refused (resolve-ambiguous). The output is what
#          scripts/objc-compat.sh takes as --build-evidence; it is never an approval.
#          Exit 0 written, 2 usage or an existing destination, 4 written nothing: a path or crate the artifact
#          does not have, an ambiguous one, evidence that is not schema 2, a Drydock that could not be fetched,
#          or a host other than macOS.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
usage() { echo "usage: objc-resolve.sh --artifact FILE --reviewed FILE --output NEW_FILE" >&2; exit 2; }
[ $# -eq 6 ] || usage
case "$1 $3 $5" in
  "--artifact --reviewed --output"|"--artifact --output --reviewed"|"--reviewed --artifact --output"|\
  "--reviewed --output --artifact"|"--output --artifact --reviewed"|"--output --reviewed --artifact") ;;
  *) usage ;;
esac
# platform: drydock-objc's resolve is built for macOS only; on Linux it exits 2, which a caller would read as misuse, so
#   another host is cannot-measure here, before any fetch. MAVERGREEN_DRYDOCK_HOST (linux or mac) replaces the host's answer.
case "${MAVERGREEN_DRYDOCK_HOST:-$(uname -s)}" in
  mac|Darwin) ;;
  *) echo "objc-resolve: drydock-objc resolve runs on macOS only, not on ${MAVERGREEN_DRYDOCK_HOST:-$(uname -s)}" >&2; exit 4 ;;
esac
D=$(sh "$HERE/fetch_drydock.sh" "$HERE/..") || { echo "objc-resolve: the pinned Drydock could not be had" >&2; exit 4; }
exec "$D/bin/drydock-objc" resolve "$@"
