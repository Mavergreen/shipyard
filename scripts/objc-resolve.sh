#!/bin/sh
# platform: host-agnostic
#   usage: objc-resolve.sh --artifact FILE --reviewed FILE --output NEW_FILE
#          Runs `drydock-objc resolve` from the pinned Drydock release (components/drydock, through
#          scripts/fetch_drydock.sh) with these arguments, and exits with its status. It reads the schema-2
#          reviewed build evidence --reviewed names and writes it to NEW_FILE, which must not exist in any form,
#          with every guard's and R2 and R3 row's symbol(s) and every crate's disambiguator read from the
#          artifact FILE; everything else is copied unchanged. A reviewed path names one function or the copies
#          of one generic instance; anything else is refused (resolve-ambiguous). The output is what
#          scripts/objc-compat.sh takes as --build-evidence; it is never an approval.
#          Exit 0 written, 2 usage or an existing destination, 4 written nothing: a path or crate the artifact
#          does not have, an ambiguous one, evidence that is not schema 2, or a Drydock that could not be fetched.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
usage() { echo "usage: objc-resolve.sh --artifact FILE --reviewed FILE --output NEW_FILE" >&2; exit 2; }
[ $# -eq 6 ] || usage
case "$1 $3 $5" in
  "--artifact --reviewed --output"|"--artifact --output --reviewed"|"--reviewed --artifact --output"|\
  "--reviewed --output --artifact"|"--output --artifact --reviewed"|"--output --reviewed --artifact") ;;
  *) usage ;;
esac
D=$(sh "$HERE/fetch_drydock.sh" "$HERE/../components/drydock") || { echo "objc-resolve: the pinned Drydock could not be had" >&2; exit 4; }
exec "$D/bin/drydock-objc" resolve "$@"
